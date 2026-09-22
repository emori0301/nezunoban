import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TEX_DIR, PREVIEW_DIR, read_png, contact_sheet
import numpy as np

names = sorted(f[:-4] for f in os.listdir(TEX_DIR) if f.endswith(".png"))
items = []
for n in names:
    a = read_png(os.path.join(TEX_DIR, n + ".png"))
    items.append((n, a))
# 2x2 タイルで並べてシームレスかも見る
tiled = []
for n, a in items:
    t = np.tile(a, (2, 2, 1))
    tiled.append((n, t))
contact_sheet(items, os.path.join(PREVIEW_DIR, "_tex_sheet.png"), cell=112, cols=8)
contact_sheet(tiled, os.path.join(PREVIEW_DIR, "_tex_tiled.png"), cell=112, cols=8)
print("sheets written", len(items))
