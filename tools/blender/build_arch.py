"""建具と外構: door_wood door_steel window_frame hearse tree fence lantern

blender --background --python tools/blender/build_arch.py

door_* は「扉板のみ、蝶番側が原点」。原点 (0,0,0) が蝶番の下端で、
+X 方向に戸先が伸びる。level 側は原点で Y 回転させれば開閉できる。
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from common import (reset_scene, material, Builder, emit, dump_report,
                    box, box_mm, box_taper, cyl, sphere, prism, tr, frame_quads)

UVQ = [(0, 0), (1, 0), (1, 1), (0, 1)]


def build_door_wood():
    """木製扉の扉板。蝶番側 = 原点、戸先 = +X。"""
    reset_scene()
    wood = material("DoorWood", "wall_wood", color=(0.38, 0.26, 0.16), rough=0.7)
    trim = material("DoorTrim", "wood_dark", color=(0.14, 0.10, 0.07), rough=0.6)
    glass = material("DoorGlass", "glass_frost", color=(0.78, 0.82, 0.84),
                     rough=0.12, alpha=0.35)
    steel = material("DoorMetal", "steel", color=(0.55, 0.56, 0.57), rough=0.4, metal=0.8)

    W, H, T = 0.84, 2.00, 0.038
    b = Builder("door_wood")
    # 框(かまち)
    b.add(box_mm(0, 0.085, -T / 2, T / 2, 0, H), wood, 2.4)
    b.add(box_mm(W - 0.085, W, -T / 2, T / 2, 0, H), wood, 2.4)
    b.add(box_mm(0.085, W - 0.085, -T / 2, T / 2, H - 0.11, H), wood, 2.4)
    b.add(box_mm(0.085, W - 0.085, -T / 2, T / 2, 0, 0.18), wood, 2.4)
    b.add(box_mm(0.085, W - 0.085, -T / 2, T / 2, 1.02, 1.12), wood, 2.4)
    # 上の摺りガラス
    b.add(box_mm(0.085, W - 0.085, -0.006, 0.006, 1.12, H - 0.11), glass, 2.0)
    b.add(box_mm(0.085, W - 0.085, -T / 2 - 0.004, -T / 2 + 0.010, 1.12, H - 0.11), trim, 3.0)
    b.add(box_mm(0.085, W - 0.085, T / 2 - 0.010, T / 2 + 0.004, 1.12, H - 0.11), trim, 3.0)
    # 下の鏡板(一段落とす)
    b.add(box_mm(0.085, W - 0.085, -T / 2 + 0.008, T / 2 - 0.008, 0.18, 1.02), wood, 2.4)
    b.add(box_mm(0.105, W - 0.105, -T / 2 + 0.004, -T / 2 + 0.010, 0.20, 1.00), trim, 4.0)
    # ノブ(両面)
    for sy in (-1, 1):
        b.add(cyl(0.026, 0.020, 8, (W - 0.10, sy * (T / 2 + 0.010), 0.98), axis='Y'),
              steel, 8.0)
        b.add(sphere(0.032, 6, 4, (W - 0.10, sy * (T / 2 + 0.035), 0.98), squash=0.75),
              steel, 8.0)
    # 蝶番
    for z in (0.22, 1.00, 1.80):
        b.add(box_mm(0.002, 0.020, -T / 2 - 0.006, T / 2 + 0.006, z - 0.045, z + 0.045),
              steel, 10.0)
    emit("door_wood", [b.build()])


def build_door_steel():
    """勝手口などのスチール扉。蝶番側 = 原点。"""
    reset_scene()
    gray = material("DoorSteel", "metal_gray", color=(0.44, 0.45, 0.44), rough=0.6)
    dark = material("DoorSteelTrim", "metal_dark", color=(0.18, 0.19, 0.19), rough=0.55)
    steel = material("DoorHandle", "steel", color=(0.58, 0.59, 0.60), rough=0.35, metal=0.85)
    glass = material("DoorSteelGlass", "glass_frost", color=(0.72, 0.76, 0.78),
                     rough=0.12, alpha=0.4)

    W, H, T = 0.86, 2.00, 0.046
    b = Builder("door_steel")
    b.add(box_mm(0, W, -T / 2, T / 2, 0, H), gray, 2.0)
    # 面の補強リブ
    for z in (0.42, 1.24):
        b.add(box_mm(0.05, W - 0.05, -T / 2 - 0.004, -T / 2 + 0.004, z, z + 0.012), dark, 4.0)
        b.add(box_mm(0.05, W - 0.05, T / 2 - 0.004, T / 2 + 0.004, z, z + 0.012), dark, 4.0)
    # 小窓(細い摺りガラス)
    b.add(box_mm(W - 0.36, W - 0.14, -T / 2 - 0.006, T / 2 + 0.006, 1.42, 1.78), dark, 3.0)
    b.add(box_mm(W - 0.345, W - 0.155, -0.005, 0.005, 1.435, 1.765), glass, 3.0)
    # レバーハンドル + 鍵
    for sy in (-1, 1):
        b.add(cyl(0.030, 0.018, 8, (W - 0.12, sy * (T / 2 + 0.009), 1.00), axis='Y'),
              steel, 8.0)
        b.add(box_mm(W - 0.26, W - 0.10, sy * (T / 2 + 0.014) - 0.014,
                     sy * (T / 2 + 0.014) + 0.014, 0.985, 1.015), steel, 7.0)
        b.add(cyl(0.017, 0.014, 8, (W - 0.12, sy * (T / 2 + 0.008), 1.13), axis='Y'),
              steel, 12.0)
    # 蝶番 + キックプレート
    for z in (0.20, 1.00, 1.82):
        b.add(box_mm(0.0, 0.026, -T / 2 - 0.008, T / 2 + 0.008, z - 0.055, z + 0.055),
              dark, 9.0)
    b.add(box_mm(0.04, W - 0.04, -T / 2 - 0.004, -T / 2 + 0.002, 0.02, 0.30), steel, 3.0)
    emit("door_steel", [b.build()])


def build_window_frame():
    """アルミサッシの引き違い窓(枠 + 摺りガラス 2 枚)。原点は床、窓台の下端。"""
    reset_scene()
    alu = material("Sash", "steel", color=(0.56, 0.57, 0.58), rough=0.45, metal=0.7)
    dark = material("SashTrim", "metal_dark", color=(0.24, 0.25, 0.25), rough=0.6)
    glass = material("WindowGlass", "glass_frost", color=(0.74, 0.79, 0.82),
                     rough=0.10, alpha=0.30)

    W, H = 1.30, 1.10
    Z0 = 0.90
    b = Builder("window_frame")
    # 外枠
    fv, ff = frame_quads(W, H, W - 0.09, H - 0.09, -0.035, 0.035, c=(0, 0, Z0 + H / 2))
    b.add((fv, ff), alu, 4.0)
    # 窓台
    b.add(box_mm(-W / 2 - 0.03, W / 2 + 0.03, -0.075, 0.055, Z0 - 0.045, Z0 + 0.008),
          dark, 3.0)
    # 引き違いの障子 2 枚(手前と奥)
    for i, (x0, x1, y) in enumerate(((-W / 2 + 0.04, 0.03, -0.018),
                                     (-0.03, W / 2 - 0.04, 0.018))):
        z0, z1 = Z0 + 0.04, Z0 + H - 0.04
        for (a0, a1, b0, b1) in ((x0, x0 + 0.030, z0, z1), (x1 - 0.030, x1, z0, z1),
                                 (x0, x1, z0, z0 + 0.030), (x0, x1, z1 - 0.030, z1)):
            b.add(box_mm(a0, a1, y - 0.016, y + 0.016, b0, b1), alu, 6.0)
        b.add(box_mm(x0 + 0.028, x1 - 0.028, y - 0.003, y + 0.003,
                     z0 + 0.028, z1 - 0.028), glass, 1.6)
    # クレセント錠
    b.add(box_mm(-0.012, 0.030, -0.030, 0.030, Z0 + H / 2 - 0.05, Z0 + H / 2 + 0.05),
          dark, 8.0)
    b.add(cyl(0.020, 0.036, 6, (0.010, 0.0, Z0 + H / 2), axis='Y'), alu, 12.0)
    emit("window_frame", [b.build()])


# ---------------------------------------------------------------- 外

def build_hearse():
    """宮型霊柩車。前は黒い車体、後ろは金の宮(輿)。"""
    reset_scene()
    blk = material("CarPaint", "car_black", color=(0.07, 0.07, 0.08), rough=0.22)
    gold = material("HearseGold", "gold", color=(0.66, 0.52, 0.18), rough=0.35, metal=0.7)
    wood = material("HearseWood", "wood_dark", color=(0.14, 0.10, 0.07), rough=0.6)
    glass = material("CarGlass", "glass_frost", color=(0.16, 0.20, 0.22),
                     rough=0.08, alpha=0.5)
    tyre = material("Tyre", "metal_dark", color=(0.075, 0.075, 0.08), rough=0.95)
    chrome = material("Chrome", "steel", color=(0.70, 0.71, 0.72), rough=0.16, metal=1.0)

    L, W = 5.10, 1.82
    b = Builder("hearse")
    # シャシ・ボディ下半分
    b.add(box_mm(-L / 2, L / 2, -W / 2, W / 2, 0.24, 0.80), blk, 1.0)
    b.add(box_mm(-L / 2 + 0.10, L / 2 - 0.10, -W / 2 - 0.02, W / 2 + 0.02, 0.30, 0.44),
          blk, 1.4)
    # ボンネットと運転席(前 = -X)
    b.add(box_mm(-L / 2, -L / 2 + 1.10, -W / 2 + 0.03, W / 2 - 0.03, 0.80, 0.98), blk, 1.4)
    b.add(box_taper(1.30, W - 0.10, 1.10, W - 0.24, 0.52,
                    (-L / 2 + 1.75, 0, 1.06)), blk, 1.4)
    # フロントガラスと窓
    b.add(box_mm(-L / 2 + 1.12, -L / 2 + 1.22, -W / 2 + 0.10, W / 2 - 0.10, 0.88, 1.28),
          glass, 1.6)
    for sy in (-1, 1):
        b.add(box_mm(-L / 2 + 1.30, -L / 2 + 2.20, sy * (W / 2 - 0.07) - 0.008,
                     sy * (W / 2 - 0.07) + 0.008, 0.92, 1.24), glass, 1.8)
    # 宮(後部の輿)
    gx0, gx1 = -L / 2 + 2.45, L / 2 - 0.06
    b.add(box_mm(gx0, gx1, -W / 2 - 0.03, W / 2 + 0.03, 0.80, 1.62), wood, 1.2)
    # 金の腰羽目と柱
    b.add(box_mm(gx0 - 0.02, gx1 + 0.02, -W / 2 - 0.05, W / 2 + 0.05, 0.80, 0.92), gold, 2.0)
    b.add(box_mm(gx0 - 0.02, gx1 + 0.02, -W / 2 - 0.05, W / 2 + 0.05, 1.50, 1.62), gold, 2.0)
    for k in range(5):
        x = gx0 + 0.10 + k * (gx1 - gx0 - 0.20) / 4.0
        for sy in (-1, 1):
            b.add(box_mm(x - 0.035, x + 0.035, sy * (W / 2 + 0.03) - 0.025,
                         sy * (W / 2 + 0.03) + 0.025, 0.92, 1.50), gold, 3.5)
    # 唐破風の屋根(2 段の反り)
    b.add(box_taper(gx1 - gx0 + 0.34, W + 0.34, gx1 - gx0 + 0.16, W + 0.16, 0.14,
                    ((gx0 + gx1) / 2, 0, 1.69)), gold, 1.6)
    b.add(box_taper(gx1 - gx0 + 0.16, W + 0.16, gx1 - gx0 - 0.30, W - 0.30, 0.22,
                    ((gx0 + gx1) / 2, 0, 1.87)), wood, 1.6)
    b.add(box_mm(gx0 + 0.20, gx1 - 0.20, -0.06, 0.06, 1.98, 2.06), gold, 3.0)
    # 屋根の飾り(擬宝珠)
    for x in (gx0 + 0.30, (gx0 + gx1) / 2, gx1 - 0.30):
        b.add(sphere(0.055, 6, 4, (x, 0, 2.11)), gold, 8.0)
    # タイヤ
    for (ax, sy) in ((-L / 2 + 0.95, -1), (-L / 2 + 0.95, 1),
                     (L / 2 - 1.00, -1), (L / 2 - 1.00, 1)):
        b.add(cyl(0.36, 0.22, 10, (ax, sy * (W / 2 - 0.09), 0.36), axis='Y'), tyre, 2.2)
        b.add(cyl(0.20, 0.06, 8, (ax, sy * (W / 2 - 0.01), 0.36), axis='Y'), chrome, 4.0)
    # ライトとバンパー
    for sy in (-1, 1):
        b.add(box_mm(-L / 2 - 0.02, -L / 2 + 0.06, sy * 0.66 - 0.16, sy * 0.66 + 0.16,
                     0.82, 0.96),
              material("HeadLight", None, color=(0.9, 0.9, 0.82),
                       emission=(1.0, 0.95, 0.80), emission_strength=1.2), 7.0)
        b.add(box_mm(L / 2 - 0.04, L / 2 + 0.01, sy * 0.68 - 0.14, sy * 0.68 + 0.14,
                     0.50, 0.62),
              material("TailLight", None, color=(0.6, 0.08, 0.06),
                       emission=(0.9, 0.10, 0.06), emission_strength=1.0), 7.0)
    b.add(box_mm(-L / 2 - 0.05, -L / 2 + 0.04, -W / 2 + 0.04, W / 2 - 0.04, 0.42, 0.62),
          chrome, 2.4)
    b.add(box_mm(L / 2 - 0.04, L / 2 + 0.05, -W / 2 + 0.04, W / 2 - 0.04, 0.38, 0.56),
          chrome, 2.4)
    emit("hearse", [b.build()])


def build_tree():
    """暗い葉のローポリ樹。"""
    reset_scene()
    bark = material("Bark", "bark", color=(0.20, 0.16, 0.12), rough=0.95)
    leaf = material("Leaves", "leaves_dark", color=(0.09, 0.14, 0.09), rough=0.95)
    b = Builder("tree")
    # 幹(少し曲げる)
    segs = [(0.0, 0.17), (0.9, 0.14), (1.7, 0.11), (2.4, 0.085)]
    for i in range(len(segs) - 1):
        z0, r0 = segs[i]
        z1, r1 = segs[i + 1]
        v, f = cyl(r0, z1 - z0, 6, (0, 0, (z0 + z1) / 2), r_top=r1)
        lean = 0.05 * i
        v = [(x + lean, y, z) for (x, y, z) in v]
        b.add((v, f), bark, 3.0)
    # 枝
    for (a, z, ln, tilt) in ((0.4, 1.7, 1.15, 0.65), (2.6, 2.0, 0.95, 0.75),
                             (4.4, 1.5, 1.05, 0.60), (5.6, 2.3, 0.80, 0.85)):
        v, f = cyl(0.055, ln, 5, (0, 0, ln / 2), r_top=0.022)
        v = tr(v, rot=('Y', tilt))
        v = tr(v, rot=('Z', a), t=(0.12, 0, z))
        b.add((v, f), bark, 6.0)
    # 葉の塊
    import random
    rnd = random.Random(3)
    for k in range(9):
        a = rnd.uniform(0, math.pi * 2)
        r = rnd.uniform(0.35, 1.15)
        x = math.cos(a) * r + 0.15
        y = math.sin(a) * r
        z = rnd.uniform(2.35, 3.35)
        rad = rnd.uniform(0.55, 0.85)
        b.add(sphere(rad, 6, 4, (x, y, z), squash=0.70), leaf, 1.6)
    emit("tree", [b.build()])


def build_fence():
    """外周のブロック塀 + 上のフェンス(1 スパン 2m)。"""
    reset_scene()
    conc = material("Block", "concrete", color=(0.52, 0.51, 0.49), rough=0.95)
    steel = material("FenceSteel", "metal_dark", color=(0.20, 0.21, 0.21), rough=0.7)
    b = Builder("fence")
    L, T = 2.00, 0.13
    # ブロック塀(3 段)
    for k in range(3):
        z = k * 0.20
        b.add(box_mm(-L / 2, L / 2, -T / 2, T / 2, z + 0.004, z + 0.196), conc, 2.0)
    b.add(box_mm(-L / 2, L / 2, -T / 2 - 0.012, T / 2 + 0.012, 0.60, 0.645), conc, 2.2)
    # 縦格子
    for sx in (-1, 1):
        b.add(box_mm(sx * (L / 2 - 0.03) - 0.026, sx * (L / 2 - 0.03) + 0.026,
                     -0.026, 0.026, 0.645, 1.42), steel, 7.0)
    for k in range(9):
        x = -L / 2 + 0.16 + k * (L - 0.32) / 8.0
        b.add(box_mm(x - 0.011, x + 0.011, -0.011, 0.011, 0.645, 1.38), steel, 14.0)
    for z in (0.70, 1.34):
        b.add(box_mm(-L / 2 + 0.02, L / 2 - 0.02, -0.016, 0.016, z, z + 0.028), steel, 6.0)
    emit("fence", [b.build()])


def build_lantern():
    """忌中提灯(白い提灯を立てたもの)。"""
    reset_scene()
    paper = material("LanternPaper", "shoji", color=(0.86, 0.83, 0.72), rough=0.9,
                     emission=(0.95, 0.80, 0.55), emission_strength=0.9)
    wood = material("LanternWood", "wood_dark", color=(0.13, 0.10, 0.07), rough=0.7)
    steel = material("LanternMetal", "metal_dark", color=(0.18, 0.18, 0.19), rough=0.6)
    b = Builder("lantern")
    # 台と柱
    b.add(box_mm(-0.19, 0.19, -0.19, 0.19, 0.0, 0.035), wood, 4.0)
    b.add(box_mm(-0.15, 0.15, -0.15, 0.15, 0.035, 0.060), wood, 4.0)
    b.add(cyl(0.020, 1.34, 6, (0, 0, 0.73)), wood, 4.0)
    # 上の腕木
    b.add(cyl(0.015, 0.26, 5, (0.12, 0, 1.39), axis='X'), wood, 8.0)
    b.add(cyl(0.008, 0.10, 4, (0.24, 0, 1.34)), steel, 14.0)
    # 提灯(樽形: 輪を積む)
    CZ = 1.06
    prof = [(0.00, 0.050), (0.06, 0.098), (0.16, 0.128), (0.28, 0.128),
            (0.38, 0.098), (0.44, 0.050)]
    for i in range(len(prof) - 1):
        z0, r0 = prof[i]
        z1, r1 = prof[i + 1]
        b.add(cyl(r0, z1 - z0, 10, (0.24, 0, CZ + (z0 + z1) / 2), r_top=r1), paper, 3.0)
    # 骨(横の輪)
    for (zz, rr) in prof[1:-1]:
        b.add(cyl(rr + 0.004, 0.006, 10, (0.24, 0, CZ + zz)), wood, 6.0)
    # 上下の口輪
    b.add(cyl(0.056, 0.016, 8, (0.24, 0, CZ + 0.452)), wood, 8.0)
    b.add(cyl(0.056, 0.016, 8, (0.24, 0, CZ - 0.008)), wood, 8.0)
    b.add(box_mm(0.222, 0.258, -0.016, 0.016, CZ - 0.055, CZ - 0.008), wood, 10.0)
    emit("lantern", [b.build()])


def main():
    build_door_wood()
    build_door_steel()
    build_window_frame()
    build_hearse()
    build_tree()
    build_fence()
    build_lantern()
    dump_report()


if __name__ == "__main__":
    main()
