"""デカール(アルファ付きテクスチャ)を、実際に貼る面の上に合成して確認する。

blender --background --python tools/blender/decal_sheet.py
  -> docs/previews/decals.png
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from common import TEX_DIR, PREVIEW_DIR, read_png, write_png, contact_sheet

# (デカール, 下地, 何枚並べるか, ラベル)
CASES = [
    ("paw_print", "floor_lino", 3, "paw on lino"),
    ("paw_print", "tatami", 3, "paw on tatami"),
    ("paw_print", "concrete", 3, "paw on concrete"),
    ("handprint", "white_wood", 1, "hand on coffin"),
    ("handprint", "glass_frost", 1, "hand on glass"),
]

CELL = 256


def load(name):
    return read_png(os.path.join(TEX_DIR, name + ".png")).astype(float) / 255.0


def fit(a, n):
    """a を n x n タイルに敷き詰めて CELL x CELL にする。"""
    t = np.tile(a, (n, n, 1)) if a.shape[0] * n <= CELL * 4 else a
    ys = (np.arange(CELL) * t.shape[0] // CELL).clip(0, t.shape[0] - 1)
    xs = (np.arange(CELL) * t.shape[1] // CELL).clip(0, t.shape[1] - 1)
    return t[np.ix_(ys, xs)]


def main():
    items = []
    for (dec, base, n, label) in CASES:
        d = load(dec)
        b = load(base)[..., :3]
        bg = fit(b, max(1, CELL // b.shape[0]))
        # デカールを n x n に並べ、少しずらして自然に見せる
        reps = np.tile(d, (n, n, 1))
        off = int(reps.shape[0] / (n * 2.0))
        reps = np.roll(reps, off, axis=1)
        dd = fit(reps, 1)
        a = dd[..., 3:4]
        out = bg * (1.0 - a) + dd[..., :3] * a
        items.append((label, (np.clip(out, 0, 1) * 255).astype(np.uint8)))

    # アルファ単体も並べる(形が分かるように市松の上へ)
    for dec in ("paw_print", "handprint"):
        d = load(dec)
        checker = np.indices((CELL, CELL)).sum(axis=0) // 16 % 2
        bg = np.stack([0.55 + checker * 0.18] * 3, axis=2)
        dd = fit(d, 1)
        a = dd[..., 3:4]
        out = bg * (1.0 - a) + dd[..., :3] * a
        items.append((dec + " alpha", (np.clip(out, 0, 1) * 255).astype(np.uint8)))

    p = os.path.join(PREVIEW_DIR, "decals.png")
    contact_sheet(items, p, cell=CELL, cols=4, pad=6)
    print("decals sheet:", p, len(items), "cells")


if __name__ == "__main__":
    main()
