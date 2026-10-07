# Gzowo Concierge - builds AppIcon.icns: a glass orb on a soft pearl squircle.
import math, subprocess, sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4096
out_dir = sys.argv[1]
base = Image.new('RGBA', (S, S), (0, 0, 0, 0))

def squircle_mask(size, inset, n=5.0):
    m = Image.new('L', (size, size), 0)
    px = m.load()
    c = size / 2
    r = (size - 2 * inset) / 2
    for y in range(size):
        for x in range(size):
            dx, dy = abs(x - c) / r, abs(y - c) / r
            if dx ** n + dy ** n <= 1:
                px[x, y] = 255
    return m

W = 1024
mask = squircle_mask(W, 100).filter(ImageFilter.GaussianBlur(0.8))
mask = mask.resize((S, S), Image.LANCZOS)

grad = Image.new('RGBA', (S, S))
gp = ImageDraw.Draw(grad)
top, bot = (250, 250, 251), (214, 217, 222)
for y in range(S):
    t = y / S
    gp.line([(0, y), (S, y)], fill=(int(top[0] + (bot[0] - top[0]) * t), int(top[1] + (bot[1] - top[1]) * t), int(top[2] + (bot[2] - top[2]) * t), 255))
tile = Image.new('RGBA', (S, S), (0, 0, 0, 0))
tile.paste(grad, (0, 0), mask)

shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
sh = Image.new('L', (S, S), 0)
sh.paste(mask, (0, int(S * 0.012)))
sh = sh.filter(ImageFilter.GaussianBlur(S * 0.016))
shadow.putalpha(sh.point(lambda v: int(v * 0.30)))
base = Image.alpha_composite(base, shadow)
base = Image.alpha_composite(base, tile)

cx, cy = S // 2, int(S * 0.5)
R = int(S * 0.255)

orb = Image.new('RGBA', (S, S), (0, 0, 0, 0))
op = orb.load()
for y in range(cy - R - 2, cy + R + 3):
    for x in range(cx - R - 2, cx + R + 3):
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        if d <= R:
            nx, ny = dx / R, dy / R
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            light = max(0.0, (-nx * 0.35 + -ny * 0.62 + nz * 0.7))
            rim = (1 - nz) ** 2.2
            r = 52 + 110 * light + 40 * rim
            g = 55 + 112 * light + 42 * rim
            b = 60 + 118 * light + 46 * rim
            op[x, y] = (int(min(r, 255)), int(min(g, 255)), int(min(b, 255)), 255)
edge = Image.new('L', (S, S), 0)
ImageDraw.Draw(edge).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
edge = edge.filter(ImageFilter.GaussianBlur(2))
orb.putalpha(ImageChops.multiply(orb.getchannel('A'), edge))

glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
gl = Image.new('L', (S, S), 0)
ImageDraw.Draw(gl).ellipse([cx - R, cy - R + int(S * 0.02), cx + R, cy + R + int(S * 0.02)], fill=255)
gl = gl.filter(ImageFilter.GaussianBlur(S * 0.03))
glow.putalpha(gl.point(lambda v: int(v * 0.35)))
glow_fill = Image.new('RGBA', (S, S), (70, 74, 84, 255))
glow = Image.composite(glow_fill, Image.new('RGBA', (S, S), (0, 0, 0, 0)), glow.getchannel('A'))
base = Image.alpha_composite(base, glow)
base = Image.alpha_composite(base, orb)

ring = Image.new('RGBA', (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
rr = int(R * 1.28)
rd.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=200, end=330, fill=(255, 255, 255, 230), width=int(S * 0.012))
rd.arc([cx - rr, cy - rr, cx + rr, cy + rr], start=330, end=380, fill=(255, 255, 255, 120), width=int(S * 0.012))
ring = ring.filter(ImageFilter.GaussianBlur(1.5))
base = Image.alpha_composite(base, ring)

core = Image.new('RGBA', (S, S), (0, 0, 0, 0))
cr = int(R * 0.34)
ImageDraw.Draw(core).ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(255, 255, 255, 235))
core = core.filter(ImageFilter.GaussianBlur(S * 0.004))
base = Image.alpha_composite(base, core)

hl = Image.new('RGBA', (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hd.ellipse([cx - int(R * 0.62), cy - int(R * 0.92), cx + int(R * 0.18), cy - int(R * 0.28)], fill=(255, 255, 255, 120))
hl = hl.filter(ImageFilter.GaussianBlur(S * 0.012))
base = Image.alpha_composite(base, hl)

sheen = Image.new('RGBA', (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(sheen)
sd.rounded_rectangle([int(S * 0.115), int(S * 0.105), int(S * 0.885), int(S * 0.5)], radius=int(S * 0.2), fill=(255, 255, 255, 70))
sheen = sheen.filter(ImageFilter.GaussianBlur(S * 0.02))
sheen.putalpha(ImageChops.multiply(sheen.getchannel('A'), mask))
base = Image.alpha_composite(base, sheen)

master = base.resize((1024, 1024), Image.LANCZOS)
os.makedirs(out_dir, exist_ok=True)
master.save(os.path.join(out_dir, 'icon-1024.png'))
iconset = os.path.join(out_dir, 'AppIcon.iconset')
os.makedirs(iconset, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    master.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f'icon_{size}x{size}.png'))
    master.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f'icon_{size}x{size}@2x.png'))
subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', os.path.join(out_dir, 'AppIcon.icns')], check=True)
print('icon built')
