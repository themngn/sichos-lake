#!/usr/bin/env python3
"""Wallpaper picker backend (WallpaperPicker.qml, SUPER+SHIFT+W).

  wallpaper.py list           JSON: {"current": path, "dir": ..., "items": [{path, name, thumb}]}
  wallpaper.py set <path>     show it on every monitor and remember it
  wallpaper.py restore        show the remembered one (login, after resume)
  wallpaper.py colors on|off  theme colors follow the wallpaper, or stay SichOS's own
  wallpaper.py scrim          redo the bar scrims (BarScrim.qml, for a new monitor)

Wallpapers are the images in ~/Pictures/Wallpapers, plus the deployed
~/Pictures/wallpaper.jpg (the repo's default) unless the folder already
holds a copy of it. The pick is kept as a symlink,
~/.local/state/sichos/wallpaper, which hyprlock.conf reads too, so the lock
screen follows; nothing in the repo or under ~/Pictures is rewritten (the
deployed wallpaper.jpg is update.sh's, overwriting it would show up as a
local edit).

Colors: unless turned off, the shell's palette follows the wallpaper.
Theme.qml's own colors (tuned on SoothingGreen, the default wallpaper) are
re-tinted, not replaced: each keeps its OKLCH lightness -- so every contrast
the UI was tuned for holds -- and its hue offset from the accent, while the
accent moves onto the wallpaper's most prominent colorful hue and every
chroma scales with how colorful the wallpaper is (capped, so text and
surfaces stay near-neutral on a vivid one). The default wallpaper gets the
palette back verbatim. Written to ~/.config/quickshell/theme-colors.json
(Theme.qml watches it) and ~/.local/state/sichos/hyprlock-colors.conf
(sourced by hyprlock.conf; a missing file only logs a parse error there).

Bar scrim: over an empty workspace the bar is transparent, and its light
text vanishes wherever the wallpaper behind it is bright -- often only in
part of it (sky on the left, dark trees on the right). A uniform tint would
fix that and dull every dark wallpaper, so instead each monitor gets an
alpha mask (black, ~/.cache/sichos/bar-scrim) that is only as dark as the
wallpaper right there needs: per column, the brightest spot under the bar
(as hyprpaper's cover fit crops it for that monitor) sets how much to
darken for ~3.5:1 contrast with white text, zero over dark areas, then
widened and blurred sideways and eased out downwards over three more bar
heights (a 2-height fade still read as a band on a bright sky), so it reads
as shade rather than a tint. BarScrim.qml stretches it
under the bar.

Thumbnails: decoding the full images in QML took seconds per card (one is
9504x6336), so each gets a 1280x720-cover JPEG once, keyed by path + mtime
+ size, under ~/.cache/sichos/wallpaper-thumbs.
"""
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, "Pictures", "Wallpapers")
DEFAULT = os.path.join(HOME, "Pictures", "wallpaper.jpg")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "sichos")
LINK = os.path.join(STATE, "wallpaper")
THUMBS = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "sichos", "wallpaper-thumbs")
EXTS = (".jpg", ".jpeg", ".png", ".webp")
COLORS_OFF = os.path.join(STATE, "wallpaper-colors-off")
THEME_JSON = os.path.join(HOME, ".config", "quickshell", "theme-colors.json")
HYPRLOCK_COLORS = os.path.join(STATE, "hyprlock-colors.conf")
SCRIMS = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "sichos", "bar-scrim")
BAR_HEIGHT = 24      # Theme.barHeight; the scrim is 4 bar heights tall (BarScrim.qml)
SCRIM_TARGET = 0.25  # max linear luminance left under the text: (1+.05)/(.25+.05) = 3.5:1
SCRIM_MAX = 0.7      # never fully black, even on a white sky

# Theme.qml's palette (keep in step with its literals) plus the two
# hyprlock-only shades (its input field's fill and the now-playing line).
BASE = {
    "text": "#f0f9e3", "textMuted": "#cbd2c1", "textDim": "#8f9796",
    "cardBackground": "#141c1e", "accent": "#698b85", "accentHover": "#77a29b",
    "submap": "#e1ffdf", "success": "#b2cfb8", "critical": "#a9b495", "urgent": "#a5ac97",
    "perfPerformance": "#a9b495", "perfBalanced": "#698b85", "perfPowerSaver": "#b2cfb8",
    "surface": "#222726", "surfaceRaised": "#2d3332",
    "lockField": "#0e1415", "lockDim": "#b4bbaa",
}
# What extract() finds in SoothingGreen.jpg (the default): BASE's accent
# chroma corresponds to this much wallpaper chroma.
REF_CHROMA = 0.0232


def current():
    try:
        target = os.readlink(LINK)
        if os.path.isfile(target):
            return target
    except OSError:
        pass
    return DEFAULT


def thumb_for(path):
    st = os.stat(path)
    key = hashlib.sha1(f"{path}\0{st.st_mtime_ns}\0{st.st_size}".encode()).hexdigest()[:16]
    out = os.path.join(THUMBS, key + ".jpg")
    if not os.path.exists(out):
        tmp = out + ".part"
        # -thumbnail strips metadata; "^" = cover the box, keeping the
        # aspect -- the cards crop it themselves (PreserveAspectCrop).
        r = subprocess.run(["magick", path + "[0]", "-auto-orient", "-thumbnail", "1280x720^",
                            "-quality", "85", "jpg:" + tmp], capture_output=True)
        if r.returncode != 0:
            return path
        os.replace(tmp, out)
    return out


def _lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    c = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return round(c * 255)


def to_oklch(hexs):
    r, g, b = (_lin(int(hexs[i:i + 2], 16)) for i in (1, 3, 5))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def _rgb(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def from_oklch(L, C, H):
    # Out of sRGB: give up chroma, never lightness (the contrasts).
    while C > 0:
        rgb = _rgb(L, C, H)
        if all(-1e-4 <= x <= 1 + 1e-4 for x in rgb):
            break
        C -= 0.002
    else:
        rgb = _rgb(L, 0, H)
    return "#" + "".join(f"{min(255, max(0, _gam(min(1, max(0, x))))):02x}" for x in rgb)


def extract(image):
    """(hue, chroma) of the image's most prominent colorful color: 12
    clusters, each weighted by pixel count x chroma^1.5, ignoring near-black
    and near-white ones (a dark backdrop otherwise wins on count alone --
    SoothingGreen's black would beat its leaves)."""
    out = subprocess.run(["magick", image, "-resize", "120x120!", "-colors", "12",
                          "-format", "%c", "histogram:info:-"], capture_output=True, text=True).stdout
    best = (0, 0.0, 0.0)
    for line in out.splitlines():
        m = re.search(r"(\d+):.*?(#[0-9A-Fa-f]{6})", line)
        if not m:
            continue
        L, C, H = to_oklch(m[2])
        w = int(m[1]) * C ** 1.5 * min(1, max(0, (L - 0.25) / 0.2)) * min(1, max(0, (0.95 - L) / 0.1))
        if w > best[0]:
            best = (w, H, C)
    return best[1], best[2]


def palette(hue, chroma):
    acc_l, acc_c, acc_h = to_oklch(BASE["accent"])
    new_c = min(0.10, max(0.012, acc_c * (chroma / REF_CHROMA) ** 0.6))
    k, dh = new_c / acc_c, hue - acc_h
    out = {}
    for name, hexs in BASE.items():
        L, C, H = to_oklch(hexs)
        cap = 0.035 if L > 0.8 else 0.02 if L < 0.35 else 0.10
        out[name] = from_oklch(L, min(C * k, max(C, cap)), (H + dh) % 360)
    return out


def palette_for(path, thumb):
    """BASE for the default wallpaper (or a copy of it), else derived from
    the thumbnail; cached beside it."""
    if is_default(path):
        return dict(BASE)
    cache = thumb + ".colors.json"
    try:
        with open(cache) as f:
            return json.load(f)
    except (OSError, ValueError):
        pass
    pal = palette(*extract(thumb))
    try:
        with open(cache, "w") as f:
            json.dump(pal, f)
    except OSError:
        pass
    return pal


def monitors():
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout
        mons = json.loads(out)
    except (OSError, ValueError):
        return []
    res = []
    for m in mons:
        w, h = m["width"], m["height"]
        if m.get("transform", 0) % 2:
            w, h = h, w
        res.append((m["name"], w, h, m.get("scale", 1) or 1))
    return res


def _box(vals, r):
    n, out, acc = len(vals), [], 0.0
    pre = [0.0]
    for v in vals:
        acc += v
        pre.append(acc)
    for i in range(n):
        lo, hi = max(0, i - r), min(n, i + r + 1)
        out.append((pre[hi] - pre[lo]) / (hi - lo))
    return out


def scrim_for(path, name, w, h, scale):
    st = os.stat(path)
    key = hashlib.sha1(f"{path}\0{st.st_mtime_ns}\0{w}x{h}@{scale}\0v2".encode()).hexdigest()[:16]
    out = os.path.join(SCRIMS, f"{name}-{key}.png")
    if os.path.exists(out):
        return out
    cols = max(64, w // 4)
    band = max(1, round(BAR_HEIGHT * scale))       # the bar itself, in monitor pixels
    rows = 3                                         # luminance samples down the bar
    # From the thumbnail (whole image, aspect kept): same crop, and the
    # full 9504x6336 one took 2s to decode for a mask this blurred.
    lum = subprocess.run(["magick", thumb_for(path), "-resize", f"{w}x{h}^",
                          "-gravity", "center", "-extent", f"{w}x{h}", "+repage",
                          "-gravity", "northwest", "-crop", f"{w}x{band}+0+0", "+repage", "-resize", f"{cols}x{rows}!",
                          "-colorspace", "LinearGray", "-depth", "8", "gray:-"],
                         capture_output=True).stdout
    if len(lum) != cols * rows:
        return None
    peak = [max(lum[r * cols + c] for r in range(rows)) / 255 for c in range(cols)]
    need = [min(SCRIM_MAX, max(0.0, 1 - SCRIM_TARGET / l)) if l > 0 else 0.0 for l in peak]
    # Widen first (a bright spot's shade has to reach past the glyphs
    # beside it), then blur, so a small bright cloud still gets its full
    # strength in the middle instead of being averaged away.
    r = max(2, cols // 50)
    need = [max(need[max(0, i - r):i + r + 1]) for i in range(cols)]
    for _ in range(3):
        need = _box(need, max(2, cols // 40))
    height = 32
    alpha = bytearray()
    for y in range(height):
        t = (y + 0.5) / height * 4                   # in bar heights
        f = min(1.0, max(0.0, (t - 0.8) / 3.2))
        v = (1 - f) ** 2 * (1 + 2 * f)               # smoothstep down: full behind the text, soft tail
        alpha.extend(round(255 * a * v) for a in need)
    os.makedirs(SCRIMS, exist_ok=True)
    for old in os.listdir(SCRIMS):
        if old.startswith(name + "-"):
            try:
                os.remove(os.path.join(SCRIMS, old))
            except OSError:
                pass
    r = subprocess.run(["magick", "-size", f"{cols}x{height}", "xc:black",
                        "(", "-size", f"{cols}x{height}", "-depth", "8", "gray:-", ")",
                        "-alpha", "off", "-compose", "CopyOpacity", "-composite", "png:" + out],
                       input=bytes(alpha), capture_output=True)
    return out if r.returncode == 0 else None


def scrims(path):
    return {n: p for n, w, h, sc in monitors() if (p := scrim_for(path, n, w, h, sc))}


def is_default(path):
    if path == DEFAULT:
        return True
    try:
        if os.path.getsize(path) != os.path.getsize(DEFAULT):
            return False
        with open(path, "rb") as a, open(DEFAULT, "rb") as b:
            return a.read() == b.read()
    except OSError:
        return False


def follow_colors():
    return not os.path.exists(COLORS_OFF)


def write_colors(path):
    pal = palette_for(path, thumb_for(path)) if follow_colors() else dict(BASE)
    pal = dict(pal, barScrim=scrims(path))
    os.makedirs(os.path.dirname(THEME_JSON), exist_ok=True)
    tmp = THEME_JSON + ".new"
    with open(tmp, "w") as f:
        json.dump(pal, f, indent=1)
    os.replace(tmp, THEME_JSON)
    os.makedirs(STATE, exist_ok=True)
    with open(HYPRLOCK_COLORS + ".new", "w") as f:
        f.write("# Written by quickshell/scripts/wallpaper.py -- the wallpaper's colors.\n")
        for var, key, alpha in (("accent", "accent", "ff"), ("text", "text", "ff"), ("softText", "text", "cc"),
                                ("field", "lockField", "bf"), ("dim", "lockDim", "aa")):
            f.write(f"${var} = rgba({pal[key][1:]}{alpha})\n")
    os.replace(HYPRLOCK_COLORS + ".new", HYPRLOCK_COLORS)


def listing():
    paths = []
    if os.path.isdir(DIR):
        for n in sorted(os.listdir(DIR), key=str.lower):
            p = os.path.join(DIR, n)
            if n.lower().endswith(EXTS) and os.path.isfile(p):
                paths.append(p)
    # A copy of the default in the folder stands in for it (and counts as
    # current while the default is).
    copy = None
    if os.path.isfile(DEFAULT):
        size = os.path.getsize(DEFAULT)
        with open(DEFAULT, "rb") as f:
            data = f.read()
        for p in paths:
            if os.path.getsize(p) == size:
                with open(p, "rb") as f:
                    if f.read() == data:
                        copy = p
                        break
        if not copy:
            paths.insert(0, DEFAULT)
    os.makedirs(THUMBS, exist_ok=True)
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        thumbs = list(ex.map(thumb_for, paths))
    cur = current()
    if copy and cur == DEFAULT:
        cur = copy
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        pals = list(ex.map(palette_for, paths, thumbs))
    # "colors": the swatch the picker shows under the name.
    items = [{"path": p, "thumb": t,
              "name": "SichOS" if p == DEFAULT else os.path.splitext(os.path.basename(p))[0],
              "colors": [pal[k] for k in ("accent", "accentHover", "success", "critical", "text")]}
             for p, t, pal in zip(paths, thumbs, pals)]
    print(json.dumps({"current": cur, "dir": DIR, "follow": follow_colors(), "items": items}))


def show(path):
    # hyprpaper 0.8 sets a wallpaper straight from the path (no preload);
    # it can still be starting at login, so retry for a few seconds.
    for _ in range(20):
        r = subprocess.run(["hyprctl", "hyprpaper", "wallpaper", f",{path},cover"],
                           capture_output=True, text=True)
        # Success prints nothing; failures say "error: ..." with rc 1.
        if r.returncode == 0 and "error" not in r.stdout.lower():
            return True
        time.sleep(0.25)
    return False


def remember(path):
    os.makedirs(STATE, exist_ok=True)
    tmp = LINK + ".new"
    try:
        os.remove(tmp)
    except FileNotFoundError:
        pass
    os.symlink(path, tmp)
    os.replace(tmp, LINK)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        listing()
    elif cmd == "set" and len(sys.argv) > 2:
        path = os.path.abspath(sys.argv[2])
        if not os.path.isfile(path):
            sys.exit(f"no such file: {path}")
        remember(path)
        write_colors(path)
        sys.exit(0 if show(path) else 1)
    elif cmd == "colors" and len(sys.argv) > 2 and sys.argv[2] in ("on", "off"):
        if sys.argv[2] == "on":
            try:
                os.remove(COLORS_OFF)
            except FileNotFoundError:
                pass
        else:
            os.makedirs(STATE, exist_ok=True)
            open(COLORS_OFF, "w").close()
        write_colors(current())
    elif cmd == "scrim":
        write_colors(current())
    elif cmd == "restore":
        path = current()
        # Recreated every login so hyprlock always has a target, also on a
        # machine where nothing was ever picked.
        remember(path)
        write_colors(path)
        sys.exit(0 if show(path) else 1)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
