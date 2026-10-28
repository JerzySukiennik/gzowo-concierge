# Gzowo wake word: builds training audio ("Hej Gzowo" / "OK Gzowo" in Polish TTS voices plus Jurek's own recordings, near-miss and everyday Polish negatives), augments it with room reverb and noise, embeds it with openWakeWord's feature models and trains a small classifier exported to ONNX.
import glob
import json
import math
import os
import random
import shutil
import struct
import subprocess
import time
import urllib.request
import wave

import numpy as np

SMOKE = os.environ.get("SMOKE") == "1"
IN = os.environ.get("IN_DIR", "")
if not IN:
    found = sorted(glob.glob("/kaggle/input/**/clips/index.json", recursive=True))
    IN = os.path.dirname(os.path.dirname(found[0])) if found else "/kaggle/input/gzowo-wake-data"
WORK = os.environ.get("WORK", "/kaggle/working")
TMP = os.environ.get("TMPD", "/tmp/gz")
OUT = os.path.join(WORK, "out")
os.makedirs(TMP, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)
random.seed(7)
SR = 16000
WIN = 32000


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def sh(cmd):
    subprocess.run(cmd, shell=True, check=True)


if not SMOKE:
    sh("pip -q install piper-tts onnx onnxscript onnxruntime scipy scikit-learn tqdm requests && pip -q install --no-deps openwakeword==0.6.0")

from scipy.signal import fftconvolve, resample_poly  # noqa: E402


def retry(fn, tries=8):
    for i in range(tries):
        try:
            return fn()
        except Exception as e:
            if i == tries - 1:
                raise
            log(f"retry {i + 1} after {e}")
            time.sleep(10 * (i + 1))


def fetch(url, path):
    if not os.path.exists(path):
        retry(lambda: urllib.request.urlretrieve(url, path + ".part"))
        os.replace(path + ".part", path)
    return path


def to16k(x, sr):
    if sr == SR:
        return x
    g = math.gcd(sr, SR)
    return resample_poly(x, SR // g, sr // g).astype(np.float32)


def read_wav(path):
    from scipy.io import wavfile
    sr, x = wavfile.read(path)
    if x.dtype == np.int16:
        x = x.astype(np.float32) / 32768
    elif x.dtype == np.int32:
        x = x.astype(np.float32) / 2147483648
    elif x.dtype == np.uint8:
        x = (x.astype(np.float32) - 128) / 128
    else:
        x = x.astype(np.float32)
    if x.ndim > 1:
        x = x.mean(1)
    return to16k(x, sr)


def trim(x, pad=0.05):
    f = 320
    e = np.array([np.sqrt(np.mean(x[i:i + f] ** 2) + 1e-12) for i in range(0, max(1, len(x) - f), f)])
    if len(e) == 0:
        return x
    floor = np.percentile(e, 20)
    on = np.where(e > max(floor * 4, e.max() * 0.08))[0]
    if len(on) == 0:
        return x
    s = max(0, on[0] * f - int(pad * SR))
    t = min(len(x), (on[-1] + 1) * f + int(pad * SR))
    return x[s:t]


def rms(x):
    return float(np.sqrt(np.mean(x ** 2) + 1e-12))


# ---------- real recordings and TTS clips ----------
idx = json.load(open(os.path.join(IN, "clips/index.json")))
real_pos, real_hold, room_noise, real_other = [], [], [], []
for c in idx:
    x = read_wav(os.path.join(IN, c["clip"]))
    lab = c.get("label")
    if lab in ("hej_gzowo", "ok_gzowo"):
        t = trim(x)
        hold = c["file"] == "mode-mikrofon" or (c["file"] == "train-pos-1b" and random.random() < 0.2)
        (real_hold if hold else real_pos).append((c["clip"], t, x))
    elif lab == "noise":
        room_noise.append(x)
    else:
        real_other.append(x)
log(f"real positives train {len(real_pos)}, holdout {len(real_hold)}, room noise clips {len(room_noise)}, other {len(real_other)}")
gem_pos = [trim(read_wav(f)) for f in sorted(glob.glob(os.path.join(IN, "tts/*.wav")))]
log(f"gemini tts positives {len(gem_pos)}")

# ---------- Piper Polish voices ----------
from piper import PiperVoice  # noqa: E402

VOICES = ["darkman/medium/pl_PL-darkman-medium", "gosia/medium/pl_PL-gosia-medium", "mc_speech/medium/pl_PL-mc_speech-medium", "bass/high/pl_PL-bass-high", "mls_6892/low/pl_PL-mls_6892-low"]
voices = []
for v in VOICES:
    n = os.path.basename(v)
    base = f"https://huggingface.co/rhasspy/piper-voices/resolve/main/pl/pl_PL/{v}"
    local = os.environ.get("PIPER_DIR")
    if local and os.path.exists(os.path.join(local, n + ".onnx")):
        path = os.path.join(local, n + ".onnx")
    else:
        path = fetch(base + ".onnx", os.path.join(TMP, n + ".onnx"))
        fetch(base + ".onnx.json", path + ".json")
    voices.append(PiperVoice.load(path))
log("piper voices", len(voices))


def say(voice, text, ls, ns, nw):
    try:
        from piper import SynthesisConfig
        chunks = list(voice.synthesize(text, syn_config=SynthesisConfig(length_scale=ls, noise_scale=ns, noise_w_scale=nw)))
        x = np.concatenate([c.audio_float_array for c in chunks]).astype(np.float32)
        return to16k(x, chunks[0].sample_rate)
    except ImportError:
        raw = b"".join(voice.synthesize_stream_raw(text, length_scale=ls, noise_scale=ns, noise_w=nw, sentence_silence=0.0))
        x = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768
        return to16k(x, voice.config.sample_rate)


HEJ = ["Hej Gzowo", "Hej, Gzowo", "Hej Gzowo!", "Hej Gzowo?", "Hej, Gzowo!", "Hej Gzowo."]
OK = ["OK Gzowo", "Okej Gzowo", "Okej, Gzowo", "OK, Gzowo!", "Okej Gzowo?", "Okej, Gzowo."]
SCALES = [0.7, 0.8, 0.9, 1.0, 1.15, 1.3]
piper_pos = []
for v in voices:
    for text in (HEJ + OK)[: 2 if SMOKE else None]:
        for ls in SCALES[: 1 if SMOKE else None]:
            for _ in range(1 if SMOKE else 3):
                piper_pos.append(trim(say(v, text, ls, float(rng.uniform(0.3, 1.0)), float(rng.uniform(0.4, 1.1)))))
log("piper positives", len(piper_pos))

NEAR = [
    "do Gzowa", "w Gzowie", "z Gzowa", "Gzowo", "Gzowo jest daleko", "jedziemy do Gzowa", "Gzowo Labs", "Gzowo Space Program",
    "hej", "okej", "OK", "hej Gosia", "hej Zosia", "hej Kuba", "okej Kuba", "okej gotowe", "okej, zrobione", "hej, gotowe",
    "hej, zobacz", "hej, ziomek", "OK Google", "Hej Siri", "nowo", "lewo", "okej, nowe", "hej, lewo", "gazowa", "kuchenka gazowa",
    "Hej, w Gzowie było fajnie", "Okej, w Gzowie zrobimy start", "hej, gdzie jesteś", "okej, dobra", "hej, chodź tu", "Gosia, chodź",
    "hej, Grzesiek", "okej, zobaczymy", "hej, co tam", "okej, rozumiem", "Gzowa nie ma na mapie",
    "o, Gzowo", "ej, Zośka", "hej, wołowina", "okej, sowa", "hej, krowa", "okej, głowa", "hej, Józwa", "ok, w porządku",
    "w Gzowie", "w Gzowie odpalimy rakietę", "wszystko w porządku, w Gzowie", "hej, gdzie są klucze", "hej, gdzie jesteś",
    "hej, gdzie idziesz", "okej, gdzie to jest", "okej, w porządku", "hej, głośniej", "okej, głośniej", "hej, gramy", "okej, gramy",
    "hej, Grześ", "hej, Krzysiek", "okej, Krzysiek", "hej, zrobione", "okej, to w Gzowie", "nad Narwią w Gzowie",
    "w Gzowie jest cicho", "do Gzowa jedziemy", "z Gzowa wracamy", "hej, gotowy", "okej, gotowy", "hej, gwiazda", "okej, gra",
]
SENTENCES = [
    "Dzisiaj po szkole muszę jeszcze odrobić zadanie z matematyki.", "Mamo, gdzie jest moja ładowarka do telefonu?",
    "Tata mówi, że w weekend pojedziemy na działkę.", "Jutro mam sprawdzian z fizyki, muszę się pouczyć.",
    "Zrób mi proszę herbatę, jak będziesz w kuchni.", "Wydrukowałem nową część rakiety na drukarce.",
    "Pies znowu szczeka na listonosza.", "Obiad będzie gotowy za dziesięć minut.", "Czy ktoś widział pilota od telewizora?",
    "Muszę jeszcze poćwiczyć na pianinie przed lekcją.", "Ten film był naprawdę dobry, polecam.", "Wyłącz światło, jak wychodzisz.",
    "W sobotę idziemy do babci na urodziny.", "Kup po drodze chleb i mleko.", "Zamknij okno, bo jest zimno.",
    "Brat znowu zabrał moje słuchawki.", "Ile jeszcze będziesz siedział przy komputerze?", "Odłóż telefon i chodź na kolację.",
    "Silnik rakiety musi być mocniejszy.", "Gdzie położyłeś klucze od garażu?", "Nauczycielka zadała nam wypracowanie.",
    "Pada deszcz, weź parasol.", "Pociąg ma dwadzieścia minut spóźnienia.", "Zagrajmy jeszcze jedną rundę.",
    "To zadanie jest trudniejsze, niż myślałem.", "Muszę naładować laptopa.", "Kto zjadł ostatni kawałek pizzy?",
    "Jutro rano wstaję o siódmej.", "Słuchaj, mam pomysł na nową grę.", "Nie zapomnij nakarmić kota.",
    "Wszystko w porządku, zaraz przyjdę.", "Dobra, to widzimy się jutro.", "Okej, to ja idę spać.",
    "Hej, gdzie są moje buty?", "Okej, zrobię to później.", "Chodź zobaczyć, co zbudowałem.", "Na działce w Gzowie jest teraz pięknie.",
    "W Gzowie odpalimy rakietę w niedzielę.", "Gzowo leży nad Narwią.", "Jak było w szkole?", "Co dzisiaj na obiad?",
    "Muszę jeszcze wysłać maila do nauczyciela.", "Zrobiłeś już lekcje?", "Daj mi chwilę, kończę grę.",
    "Telewizor jest za głośno, ścisz trochę.", "Mam jutro trening o szesnastej.", "Babcia dzwoniła i pytała o ciebie.",
    "Musimy posprzątać pokój przed weekendem.", "Ta piosenka ciągle mi chodzi po głowie.", "Gdzie jest moja bluza?",
]
neg_near, neg_speech = [], []
for v in voices:
    for text in NEAR[: 4 if SMOKE else None]:
        for ls in ([1.0] if SMOKE else [0.8, 1.0, 1.2]):
            neg_near.append(trim(say(v, text, ls, float(rng.uniform(0.3, 1.0)), float(rng.uniform(0.4, 1.1)))))
    for text in SENTENCES[: 3 if SMOKE else None]:
        neg_speech.append(say(v, text, float(rng.uniform(0.85, 1.15)), 0.667, 0.8))
for f in sorted(glob.glob(os.path.join(IN, "negatives/*.wav"))):
    neg_speech.append(read_wav(f))
log("near-miss clips", len(neg_near), "sentences", len(neg_speech))

# ---------- room impulse responses ----------
rirs = []
try:
    tree = retry(lambda: json.load(urllib.request.urlopen("https://huggingface.co/api/datasets/davidscripka/MIT_environmental_impulse_responses/tree/main/16khz", timeout=60)))
    files = [t["path"] for t in tree if t["path"].endswith(".wav")][: 20 if SMOKE else None]
    for p in files:
        local = fetch(f"https://huggingface.co/datasets/davidscripka/MIT_environmental_impulse_responses/resolve/main/{p}", os.path.join(TMP, os.path.basename(p)))
        r = read_wav(local)
        if len(r) > 64:
            rirs.append(r / (np.abs(r).max() + 1e-9))
except Exception as e:
    log("rir download failed", e)
log("rirs", len(rirs))

babble = np.concatenate(neg_speech) if neg_speech else np.zeros(SR, np.float32)
room = np.concatenate(room_noise) if room_noise else np.zeros(SR, np.float32)


def colored(n):
    kind = rng.integers(3)
    w = rng.standard_normal(n).astype(np.float32)
    if kind == 1:
        w = np.cumsum(w)
        w -= np.convolve(w, np.ones(400) / 400, mode="same")
    elif kind == 2:
        f = np.fft.rfft(w)
        f /= np.sqrt(np.arange(1, len(f) + 1))
        w = np.fft.irfft(f, n).astype(np.float32)
    return w / (rms(w) + 1e-9)


def background(n):
    choice = rng.random()
    if choice < 0.45 and len(room) > n:
        s = int(rng.integers(0, len(room) - n))
        b = room[s:s + n].copy()
    elif choice < 0.7 and len(babble) > n:
        s = int(rng.integers(0, len(babble) - n))
        b = babble[s:s + n] * 0.6
    else:
        b = colored(n)
    return b / (rms(b) + 1e-9)


def augment(x, rir_p=0.65):
    f = float(rng.uniform(0.88, 1.12))
    if abs(f - 1) > 0.01:
        x = resample_poly(x, 100, int(round(100 * f))).astype(np.float32)
    if rirs and rng.random() < rir_p:
        r = rirs[int(rng.integers(len(rirs)))]
        y = fftconvolve(x, r)[: len(x) + SR // 4].astype(np.float32)
        x = y / (np.abs(y).max() + 1e-9) * np.abs(x).max()
    return x


def window(x, end_jitter=(0, 0.25), snr=(3, 28), level=(-30, -6)):
    n = WIN
    if len(x) > n - 1600:
        x = x[-(n - 1600):]
    out = background(n) * 0.0
    end = n - int(rng.uniform(*end_jitter) * SR)
    start = max(0, end - len(x))
    out[start:start + len(x)] += x[: n - start]
    sig = rms(x)
    noise = background(n)
    s = float(rng.uniform(*snr))
    out += noise * sig / (10 ** (s / 20))
    peak = np.abs(out).max() + 1e-9
    target = 10 ** (float(rng.uniform(*level)) / 20)
    return (out / peak * target).astype(np.float32)


def noise_window(level=(-45, -15)):
    b = background(WIN)
    return (b / (np.abs(b).max() + 1e-9) * 10 ** (float(rng.uniform(*level)) / 20)).astype(np.float32)


log("building windows")
pos = []
for clip in piper_pos:
    for _ in range(1 if SMOKE else 3):
        pos.append(window(augment(clip)))
for _, t, _ in real_pos:
    for _ in range(2 if SMOKE else 45):
        pos.append(window(augment(t, rir_p=0.35)))
for clip in gem_pos:
    for _ in range(1 if SMOKE else 30):
        pos.append(window(augment(clip)))
neg = []
for clip in neg_near:
    for _ in range(1 if SMOKE else 3):
        neg.append(window(augment(clip), end_jitter=(0, 0.6)))
for clip in real_other:
    neg.append(window(clip, end_jitter=(0, 0.6)))
for sent in neg_speech:
    for _ in range(1 if SMOKE else 2):
        a = augment(sent)
        for s in range(0, max(1, len(a) - WIN), SR // 2):
            seg = a[s:s + WIN]
            if len(seg) == WIN:
                neg.append(window(seg, end_jitter=(0, 0)))
for _ in range(50 if SMOKE else 3000):
    neg.append(noise_window())
hold = [(c, window(t, snr=(25, 40), level=(-12, -6), end_jitter=(0.05, 0.1))) for c, t, _ in real_hold]
hold_noisy = [(c, window(augment(t, rir_p=0.0), snr=(8, 15), level=(-20, -8))) for c, t, _ in real_hold]
log(f"windows: positives {len(pos)}, negatives {len(neg)}, holdout {len(hold)}")

# ---------- features ----------
from openwakeword.utils import AudioFeatures, download_models  # noqa: E402

retry(lambda: download_models(model_names=["alexa"]))
F = AudioFeatures(inference_framework="onnx", ncpu=4)


def embed(wins):
    if not wins:
        return np.zeros((0, 16, 96), np.float32)
    x = (np.clip(np.stack(wins), -1, 1) * 32767).astype(np.int16)
    out = []
    for i in range(0, len(x), 256):
        out.append(F.embed_clips(x[i:i + 256], batch_size=256))
    e = np.concatenate(out).astype(np.float32)
    return e[:, -16:, :]


Xp = embed(pos)
Xn = embed(neg)
Xh = embed([w for _, w in hold])
Xhn = embed([w for _, w in hold_noisy])
log("features", Xp.shape, Xn.shape, Xh.shape)

# ---------- big negative set ----------
def partial_npy(url, path, max_bytes):
    if not os.path.exists(path):
        def get():
            req = urllib.request.Request(url, headers={"Range": f"bytes=0-{max_bytes - 1}"})
            with urllib.request.urlopen(req, timeout=600) as r, open(path + ".part", "wb") as f:
                shutil.copyfileobj(r, f, 1 << 24)
        retry(get)
        os.replace(path + ".part", path)
    with open(path, "rb") as f:
        magic = f.read(6)
        major = f.read(1)[0]
        f.read(1)
        hlen = struct.unpack("<H" if major == 1 else "<I", f.read(2 if major == 1 else 4))[0]
        header = eval(f.read(hlen).decode("latin1"))
        offset = f.tell()
    shape = header["shape"]
    dtype = np.dtype(header["descr"])
    rec = int(np.prod(shape[1:])) * dtype.itemsize
    n = (os.path.getsize(path) - offset) // rec
    return np.memmap(path, dtype=dtype, mode="r", offset=offset, shape=(min(n, shape[0]),) + tuple(shape[1:]))


HF = "https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main"
val_stream = np.load(fetch(f"{HF}/validation_set_features.npy", os.path.join(TMP, "validation_set_features.npy"))).astype(np.float32)
val = np.lib.stride_tricks.sliding_window_view(val_stream, (16, 96))[:, 0]
acav = partial_npy(f"{HF}/openwakeword_features_ACAV100M_2000_hrs_16bit.npy", os.path.join(TMP, "acav.npy"), (60 << 20) if SMOKE else (5 << 30))
acav = np.ascontiguousarray(acav)
log("validation", val.shape, "acav", acav.shape, acav.dtype)
val_hours = val_stream.shape[0] * 0.08 / 3600

# ---------- training ----------
import torch  # noqa: E402
import torch.nn as nn  # noqa: E402

torch.manual_seed(7)
torch.set_num_threads(4)
model = nn.Sequential(
    nn.Flatten(), nn.Linear(16 * 96, 128), nn.LayerNorm(128), nn.ReLU(),
    nn.Linear(128, 128), nn.LayerNorm(128), nn.ReLU(), nn.Linear(128, 1),
)
STEPS = 300 if SMOKE else 30000
opt = torch.optim.AdamW(model.parameters(), lr=1e-3, weight_decay=1e-4)
sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=1e-3, total_steps=STEPS, pct_start=0.1)
tp = torch.from_numpy(Xp)
tn = torch.from_numpy(Xn)
hard = torch.zeros((0, 16, 96))


def score(x, bs=8192):
    model.eval()
    out = []
    with torch.no_grad():
        for i in range(0, len(x), bs):
            out.append(torch.sigmoid(model(torch.as_tensor(np.asarray(x[i:i + bs], dtype=np.float32)))).squeeze(1).numpy())
    model.train()
    return np.concatenate(out) if out else np.zeros(0)


def false_alarms(s, th, cooldown=19):
    count, last = 0, -cooldown
    for i in np.where(s >= th)[0]:
        if i - last >= cooldown:
            count += 1
        last = i
    return count


def evaluate(step):
    sv = score(val)
    sh_ = score(Xh)
    shn = score(Xhn)
    snear = score(Xn)
    rows = []
    for th in [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95]:
        rows.append({
            "threshold": th,
            "recall_holdout": float((sh_ >= th).mean()) if len(sh_) else None,
            "recall_holdout_noisy": float((shn >= th).mean()) if len(shn) else None,
            "fa_per_hour": false_alarms(sv, th) / val_hours,
            "polish_negatives_hit": float((snear >= th).mean()),
        })
    log(f"step {step}: " + " | ".join(f"{r['threshold']}: R {r['recall_holdout']:.2f}/{r['recall_holdout_noisy']:.2f} FA {r['fa_per_hour']:.2f}/h PL {r['polish_negatives_hit']:.3f}" for r in rows))
    return rows, sv


bce = nn.BCEWithLogitsLoss(reduction="none")
history = []
for step in range(1, STEPS + 1):
    ip = torch.randint(0, len(tp), (192,))
    ineg = torch.randint(0, len(tn), (192,))
    ia = np.sort(rng.integers(0, acav.shape[0], 512))
    parts = [tp[ip], tn[ineg], torch.from_numpy(np.asarray(acav[ia], dtype=np.float32))]
    labels = [torch.ones(192), torch.zeros(192), torch.zeros(512)]
    if len(hard):
        ih = torch.randint(0, len(hard), (128,))
        parts.append(hard[ih])
        labels.append(torch.zeros(128))
    x = torch.cat(parts)
    y = torch.cat(labels)
    w = torch.where(y > 0, torch.ones_like(y), torch.full_like(y, 1 + 4 * step / STEPS))
    loss = (bce(model(x).squeeze(1), y) * w).mean()
    opt.zero_grad()
    loss.backward()
    opt.step()
    sched.step()
    if step % (100 if SMOKE else 3000) == 0 or step == STEPS:
        log(f"step {step} loss {loss.item():.4f}")
        rows, sv = evaluate(step)
        history.append({"step": step, "rows": rows})
        sample = np.sort(rng.choice(acav.shape[0], min(200000, acav.shape[0]), replace=False))
        sa = score(acav[sample])
        top = sample[np.argsort(-sa)[:4000]]
        sn = score(Xn)
        hard = torch.cat([torch.from_numpy(np.asarray(acav[np.sort(top)], dtype=np.float32)), tn[torch.from_numpy(np.argsort(-sn)[:2000].copy())], torch.from_numpy(np.ascontiguousarray(val[np.sort(np.argsort(-sv)[:500])]))])

rows, _ = evaluate(STEPS)
ok = [r for r in rows if r["fa_per_hour"] <= 0.3 and r["polish_negatives_hit"] <= 0.02]
best = max(ok, key=lambda r: (r["recall_holdout"] or 0)) if ok else rows[-1]


class Wake(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, x):
        return torch.sigmoid(self.m(x))


model.eval()
torch.save(model.state_dict(), os.path.join(OUT, "gzowo_wake.pt"))
export_args = (Wake(model), torch.zeros(1, 16, 96), os.path.join(OUT, "gzowo_wake.onnx"))
export_kw = dict(input_names=["x"], output_names=["y"], opset_version=13, dynamic_axes={"x": {0: "n"}, "y": {0: "n"}})
try:
    torch.onnx.export(*export_args, dynamo=False, **export_kw)
except TypeError:
    torch.onnx.export(*export_args, **export_kw)
holdout_scores = {c: float(s) for (c, _), s in zip(hold, score(Xh))}
json.dump({"threshold": best["threshold"], "final": rows, "history": history, "holdout_scores": holdout_scores,
           "counts": {"pos": len(pos), "neg": len(neg), "acav": int(acav.shape[0]), "val_hours": val_hours}}, open(os.path.join(OUT, "metrics.json"), "w"), indent=1)
log("done, threshold", best["threshold"], best)
