#!/usr/bin/env python3
"""
Prepara imágenes de amps/pedales en alta resolución para la app.

Uso (desde la raíz del repo):
    python3 ios/TonexDirect/tools/prepare_skins.py --assets
        → procesa en su lugar las imágenes nuevas que agregaste directo en Assets.xcassets
          (respalda el original en skins_hd_originales/)
    python3 ios/TonexDirect/tools/prepare_skins.py skins_hd_originales/
        → toma imágenes de esa carpeta y las instala en Assets.xcassets

Toma cada imagen de la carpeta (png/jpg) cuyo nombre corresponda a una imagen de la
app (p. ej. "5150.jpg", "skin_5150.png", "pskin_klongold.jpg", "jcm.png") y:
  1. quita el fondo: cuadritos de transparencia pintados, o un fondo liso (blanco, gris,
     negro o de color) conectado con los bordes;
     no toca las partes del amp del mismo color que no tocan el borde,
  2. recorta al contenido,
  3. la reduce a 1400 px de ancho (suficiente para la pantalla retina del iPad),
  4. la guarda como PNG real en Assets.xcassets/<nombre>.imageset.

Requiere Pillow y numpy:  pip3 install pillow numpy  (scipy opcional, limpia mejor los restos)
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

MAX_W = 1400
HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'TonexDirect', 'Assets.xcassets')


def background_color(rgb):
    """Color del fondo = el que comparten las esquinas (si son parecidas). None si no hay fondo liso."""
    w, h = rgb.size
    pts = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    cols = [rgb.getpixel(p) for p in pts]
    best = max(cols, key=lambda c: sum(1 for d in cols if max(abs(c[i] - d[i]) for i in range(3)) <= 24))
    similar = [c for c in cols if max(abs(best[i] - c[i]) for i in range(3)) <= 24]
    return best if len(similar) >= 5 else None


def _box_mean(m, ry, rx=None):
    """Promedio en ventana (2ry+1) x (2rx+1) con sumas acumuladas."""
    rx = ry if rx is None else rx
    c = np.pad(m.astype(np.float32), ((ry + 1, ry), (rx + 1, rx)), mode='edge').cumsum(0).cumsum(1)
    h, w = m.shape
    ky, kx = 2 * ry + 1, 2 * rx + 1
    tot = c[ky:ky + h, kx:kx + w] - c[0:h, kx:kx + w] - c[ky:ky + h, 0:w] + c[0:h, 0:w]
    return tot / (ky * kx)

def _period(line, mid):
    b = np.full(line.shape, -1); b[line > mid + 5] = 1; b[line < mid - 5] = 0
    idx = np.flatnonzero(b >= 0); v = b[idx]
    ch = np.flatnonzero(np.diff(v) != 0)
    d = np.diff((idx[ch] + idx[ch + 1]) / 2.0)
    d = d[d > 4]
    return float(np.median(d)) if len(d) >= 4 else None

def remove_checkerboard(im, verbose=True, icon=False):
    rgb = np.asarray(im.convert('RGB')).astype(np.int16)
    gray = rgb.mean(axis=2); sat = rgb.max(2) - rgb.min(2)
    h, w = gray.shape
    sides = [(gray[2], sat[2]), (gray[-3], sat[-3]), (gray[:, 2], sat[:, 2]), (gray[:, -3], sat[:, -3])]
    def looks_checker(l):
        a, b = np.percentile(l, 15), np.percentile(l, 85)
        return a > 150 and b - a > 15
    sides = [s for s in sides if looks_checker(s[0])]   # un lado puede tocar el amp o su sombra
    if len(sides) < 2: return None
    ring = np.concatenate([s[0] for s in sides]); ring_sat = np.concatenate([s[1] for s in sides])
    lo_v, hi_v = np.percentile(ring, 15), np.percentile(ring, 85)
    if hi_v - lo_v < 15 or lo_v < 150: return None
    mid = (lo_v + hi_v) / 2
    hi_c = np.median(ring[ring > mid]); lo_c = np.median(ring[ring <= mid])
    tol = min(10, (hi_c - lo_c) / 3)
    on_ring = ((np.abs(ring - hi_c) <= tol) | (np.abs(ring - lo_c) <= tol)) & (ring_sat < 18)
    if on_ring.mean() < 0.6: return None
    sqs = [p for p in (_period(l, mid) for l, _ in sides) if p]
    sqs = [p for p in sqs if 4 < p < max(h, w) / 4]
    if not sqs: return None
    sq = float(np.median(sqs))
    # el claro varía más en la imagen (p. ej. 255 arriba, 242 abajo): se acepta más hacia abajo
    is_hi = (gray >= hi_c - max(tol, 0.35 * (hi_c - lo_c))) & (gray <= hi_c + tol) & (sat < 18)
    is_lo = (np.abs(gray - lo_c) <= tol) & (sat < 18)
    match = is_hi | is_lo
    r = max(3, int(round(0.75 * sq)))
    rs = max(1, int(sq // 6))
    # cuadrito real: alrededor hay de los dos colores en proporción pareja.
    # Una placa blanca/gris del amp solo tiene uno → no pasa (salvo una franja mínima).
    # Ventana cuadrada + franjas delgadas horizontal/vertical (para una sola fila/columna de
    # cuadritos pegada al amp).
    cand = np.zeros((h, w), bool); mixed = np.zeros((h, w), bool)
    near_gray = (gray > lo_c - tol) & (gray < hi_c + tol) & (sat < 18)
    for ry, rx in ((r, r), (r, rs), (rs, r)):
        f_hi, f_lo = _box_mean(is_hi, ry, rx), _box_mean(is_lo, ry, rx)
        fm = f_hi + f_lo
        lo_frac = f_lo / np.maximum(fm, 1e-6)
        ok = (lo_frac > 0.3) & (lo_frac < 0.7)
        cand |= match & (fm > 0.3) & ok
        # el borde de cada cuadrito (JPEG mezcla ambos colores) también es fondo si está entre cuadritos
        mixed |= near_gray & (fm > 0.6) & ok
    cand |= mixed
    if icon:
        # íconos: dibujo plano sobre los cuadritos → es fondo todo lo claro y sin color
        ink = np.clip(((lo_c - 12) - gray) / 24.0, 0, 1)
        ink = np.maximum(ink, np.clip((sat - 30) / 30.0, 0, 1))
        alpha = Image.fromarray((ink * 255).astype(np.uint8), 'L').filter(ImageFilter.GaussianBlur(0.8))
        out = im.convert('RGBA'); out.putalpha(alpha)
        if verbose: print(f'   fondo de cuadritos ({sq:.0f} px) quitado (ícono)')
        return out
    lab = Image.fromarray((cand * 255).astype(np.uint8), 'L').copy()
    step = max(2, int(sq // 3))
    seeds = [(x, y) for x in range(0, w, step) for y in (0, 1, h - 2, h - 1)] + \
            [(x, y) for y in range(0, h, step) for x in (0, 1, w - 2, w - 1)]
    for x, y in seeds:
        if lab.getpixel((x, y)) == 255:
            ImageDraw.floodfill(lab, (x, y), 128, thresh=0)
    bg = np.asarray(lab) == 128
    try:
        from scipy import ndimage as ndi
        # rayitas entre cuadritos (bordes mezclados por el JPEG) que quedaron entre dos zonas de fondo
        k = max(3, int(sq // 5)) | 1
        closed = ndi.binary_closing(bg, structure=np.ones((k, k), bool))
        bg |= closed & near_gray
        # restos sueltos de cuadritos fuera del amp: islas pequeñas casi todas de color de fondo
        fg = ~bg
        comp, n = ndi.label(fg)
        if n > 1:
            area = np.bincount(comp.ravel(), minlength=n + 1)
            mfrac = np.bincount(comp.ravel(), weights=match.ravel(), minlength=n + 1) / np.maximum(area, 1)
            big = area[1:].max()
            drop = np.flatnonzero(((mfrac > 0.6) & (area < 0.02 * big)) | (area < 0.003 * big))
            drop = drop[drop > 0]
            if len(drop): bg |= np.isin(comp, drop)
    except ImportError:
        pass
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8), 'L')
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    out = im.convert('RGBA'); out.putalpha(alpha)
    if verbose: print(f'   fondo de cuadritos ({sq:.0f} px) quitado')
    return out


def remove_edge_background(im, tolerance=40, icon=False):
    """Quita el fondo liso (de cualquier color) conectado con los bordes.
    Lo que esté dentro del amp con el mismo color no se toca, porque no toca el borde."""
    w, h = im.size
    if im.mode == 'RGBA' and im.getchannel('A').getextrema()[0] < 250:
        return im.convert('RGBA')                 # ya trae transparencia: no tocar
    checker = remove_checkerboard(im, icon=icon)
    if checker is not None:
        return checker
    work = im.convert('RGB')
    bg = background_color(work)
    if bg is None:
        print('   (sin fondo liso detectable; se deja como está)')
        return im.convert('RGBA')
    mark = (255, 0, 255) if bg != (255, 0, 255) else (0, 255, 0)
    near = lambda c: max(abs(c[i] - bg[i]) for i in range(3)) <= tolerance
    step = max(1, min(w, h) // 200)
    seeds = [(x, y) for x in range(0, w, step) for y in (0, h - 1)] + \
            [(x, y) for y in range(0, h, step) for x in (0, w - 1)]
    for p in seeds:
        c = work.getpixel(p)
        if c != mark and near(c):
            ImageDraw.floodfill(work, p, mark, thresh=tolerance)
    px = work.load()
    alpha = Image.new('L', (w, h), 255)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] == mark:
                ap[x, y] = 0
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = im.convert('RGBA')
    out.putalpha(alpha)
    print(f'   fondo {bg} quitado')
    return out


def asset_name(filename, existing):
    stem = os.path.splitext(os.path.basename(filename))[0].lower()
    for cand in (stem, 'skin_' + stem, 'pskin_' + stem):
        if cand in existing:
            return cand
    # nombres cortos del repo (skins_png): 5150, jcm, ac30… → buscar por sufijo
    hits = [e for e in existing if e.split('_', 1)[-1] == stem]
    return hits[0] if len(hits) == 1 else None


def install(im, name):
    """Quita el fondo, recorta, ajusta tamano y guarda como unico PNG del imageset."""
    is_icon = name.startswith('effect_icon')
    im = remove_edge_background(im, icon=is_icon)
    bbox = im.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    if is_icon:
        side = round(max(im.size) * 1.06)
        canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        canvas.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = canvas.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)
    elif im.width > MAX_W:
        im = im.resize((MAX_W, round(im.height * MAX_W / im.width)), Image.LANCZOS)
    d = os.path.join(ASSETS, name + '.imageset')
    for old in os.listdir(d):
        if old != 'Contents.json':
            os.remove(os.path.join(d, old))
    im.save(os.path.join(d, name + '.png'), 'PNG', optimize=True)
    json.dump({'images': [{'filename': name + '.png', 'idiom': 'universal'}],
               'info': {'author': 'xcode', 'version': 1}},
              open(os.path.join(d, 'Contents.json'), 'w'), indent=2)
    return im.size


def main(folder):
    existing = {d[:-9] for d in os.listdir(ASSETS) if d.endswith('.imageset')}
    for f in sorted(os.listdir(folder)):
        if not f.lower().endswith(('.png', '.jpg', '.jpeg')) or f.startswith(('preview_', '_')):
            continue
        name = asset_name(f.replace('_original', ''), existing)
        if not name:
            print(f'- {f}: no corresponde a ninguna imagen de la app, la salto')
            continue
        im = Image.open(os.path.join(folder, f))
        if max(im.size) < 200:
            continue
        print(f'- {f} -> {name}')
        size = install(im, name)
        print(f'  ok {size[0]}x{size[1]}')


ORIGINAL_SIZES = {(397, 133), (163, 133), (45, 45)}   # originales del repo (baja resolución)
ICON_SIZE = 192   # íconos de efectos: se ven a ~48 pt → 192 px cubre 3x
BACKUP = os.path.join(HERE, '..', '..', '..', 'skins_hd_originales')


def needs_processing(path, max_w=MAX_W):
    """Imagen nueva que hay que preparar: no es la original de baja resolución y aún no está
    lista (PNG con fondo transparente y ≤ max_w)."""
    im = Image.open(path)
    if im.size in ORIGINAL_SIZES or max(im.size) < 200:   # originales chicas del repo: no tocar
        return False
    if im.format == 'PNG' and im.mode == 'RGBA' and im.width <= max_w:
        a = im.getchannel('A')
        w, h = im.size
        if all(a.getpixel(c) < 16 for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]):
            return False                       # ya preparada
    return True


def process_assets():
    """Procesa en su lugar las imágenes nuevas que se agregaron directo en Assets.xcassets."""
    os.makedirs(BACKUP, exist_ok=True)
    done = 0
    for d in sorted(os.listdir(ASSETS)):
        if not d.endswith('.imageset'):
            continue
        name = d[:-9]
        is_icon = name.startswith('effect_icon')
        max_w = ICON_SIZE if is_icon else MAX_W
        folder = os.path.join(ASSETS, d)
        files = [f for f in os.listdir(folder) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.heic', '.webp'))]
        candidates = [f for f in files if needs_processing(os.path.join(folder, f), max_w)]
        if not candidates:
            continue
        # la más grande de las nuevas (Xcode puede haberla puesto en 1x/2x/3x)
        src = max(candidates, key=lambda f: Image.open(os.path.join(folder, f)).size[0])
        print(f'· {name}: {src}')
        im = Image.open(os.path.join(folder, src))
        ext = os.path.splitext(src)[1]
        backup = os.path.join(BACKUP, f'{name}_original{ext}')
        if not os.path.exists(backup):
            with open(os.path.join(folder, src), 'rb') as fi, open(backup, 'wb') as fo:
                fo.write(fi.read())
        size = install(im, name)
        print(f'  ok {size[0]}x{size[1]} (original respaldado en skins_hd_originales/)')
        done += 1
    print(f'{done} imagen(es) procesada(s)')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--assets':
        process_assets()
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else 'skins_hd_originales')
