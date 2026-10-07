# Gzowo Concierge - builds AppIcon.icns from web/icon-1024.png (flat bot art): squircle mask, soft drop shadow, standard macOS margins.
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFilter

art_path, out_dir = sys.argv[1], sys.argv[2]
S = 4096
W = 1024
inset = 100

def squircle(size, ins, n=5.0):
    m = Image.new('L', (size, size), 0)
    px = m.load()
    c = size / 2
    r = (size - 2 * ins) / 2
    for y in range(size):
        for x in range(size):
            dx, dy = abs(x - c) / r, abs(y - c) / r
            if dx ** n + dy ** n <= 1:
                px[x, y] = 255
    return m

mask = squircle(W, inset).filter(ImageFilter.GaussianBlur(0.8)).resize((S, S), Image.LANCZOS)
art = Image.open(art_path).convert('RGBA').resize((S - 8 * inset, S - 8 * inset), Image.LANCZOS)
tile = Image.new('RGBA', (S, S), (0, 0, 0, 0))
tile.paste(art, (4 * inset, 4 * inset))
tile.putalpha(mask)

shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
sh = Image.new('L', (S, S), 0)
sh.paste(mask, (0, int(S * 0.012)))
sh = sh.filter(ImageFilter.GaussianBlur(S * 0.016))
shadow.putalpha(sh.point(lambda v: int(v * 0.28)))
base = Image.alpha_composite(shadow, tile)

master = base.resize((1024, 1024), Image.LANCZOS)
os.makedirs(out_dir, exist_ok=True)
master.save(os.path.join(out_dir, 'icon-1024.png'))
iconset = os.path.join(out_dir, 'AppIcon.iconset')
os.makedirs(iconset, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    master.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, f'icon_{size}x{size}.png'))
    master.resize((size * 2, size * 2), Image.LANCZOS).save(os.path.join(iconset, f'icon_{size}x{size}@2x.png'))
subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', os.path.join(out_dir, 'AppIcon.icns')], check=True)
print('icon built from art')
