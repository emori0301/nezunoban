"""家具・設備: folding_chair low_table zabuton futon tv_crt office_desk
office_chair phone monitor_crt freezer_chest dry_ice_box vending_machine
breaker_box safe sink shelf cabinet toilet

blender --background --python tools/blender/build_furniture.py
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from common import (reset_scene, material, Builder, emit, dump_report,
                    box, box_mm, box_taper, cyl, sphere, prism, tr,
                    loft_rings, donut, oval_cyl, build_at)

UVQ = [(0, 0), (1, 0), (1, 1), (0, 1)]


def M():
    return dict(
        steel=material("Steel", "steel", color=(0.62, 0.63, 0.64), rough=0.42, metal=0.8),
        gray=material("PaintGray", "metal_gray", color=(0.46, 0.47, 0.46), rough=0.65),
        dark=material("PaintDark", "metal_dark", color=(0.19, 0.20, 0.21), rough=0.6),
        wood=material("WoodDark", "wood_dark", color=(0.16, 0.11, 0.08), rough=0.7),
        beige=material("Plastic", "plastic_beige", color=(0.74, 0.70, 0.60), rough=0.55),
        screen=material("Screen", "crt_screen", color=(0.05, 0.05, 0.06), rough=0.15),
        cloth=material("Cloth", "white_cloth", color=(0.88, 0.87, 0.84), rough=0.95),
        zab=material("Zabuton", "zabuton_cloth", color=(0.42, 0.16, 0.18), rough=0.95),
        fut=material("Futon", "futon_cloth", color=(0.78, 0.75, 0.68), rough=0.95),
        foam=material("Styrofoam", "styrofoam", color=(0.90, 0.90, 0.88), rough=1.0),
        card=material("Cardboard", "cardboard", color=(0.58, 0.46, 0.32), rough=0.95),
        tat=material("Tatami", "tatami", color=(0.62, 0.60, 0.40), rough=0.95),
    )


# ---------------------------------------------------------------- 椅子・座

def build_folding_chair():
    """パイプ椅子。"""
    reset_scene()
    m = M()
    b = Builder("folding_chair")
    pipe, seat = m["dark"], m["gray"]
    W, D, SH, BH = 0.42, 0.42, 0.44, 0.82
    # 前脚 / 後脚(X 字)
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.02)
        for (y0, y1, z0, z1) in ((-D / 2 + 0.03, D / 2 - 0.12, 0.0, SH),
                                 (D / 2 - 0.04, -D / 2 + 0.10, 0.0, BH)):
            dy = y1 - y0
            dz = z1 - z0
            ln = math.hypot(dy, dz)
            v, f = cyl(0.014, ln, 5, (0, 0, 0))
            v = tr(v, rot=('X', math.atan2(dy, dz)))
            v = tr(v, t=(x, (y0 + y1) / 2, (z0 + z1) / 2))
            b.add((v, f), pipe, 14.0)
    # 横桟
    for (y, z) in ((0.05, 0.22), (-0.06, 0.26)):
        v, f = cyl(0.012, W - 0.03, 5, (0, y, z), axis='X')
        b.add((v, f), pipe, 14.0)
    # 座面
    b.add(box_mm(-W / 2, W / 2, -D / 2 + 0.02, D / 2 - 0.06, SH, SH + 0.022), seat, 5.0)
    b.add(box_mm(-W / 2 + 0.01, W / 2 - 0.01, -D / 2 + 0.03, D / 2 - 0.07,
                 SH + 0.022, SH + 0.034), seat, 5.0)
    # 背もたれ
    b.add(box_mm(-W / 2 + 0.01, W / 2 - 0.01, D / 2 - 0.10, D / 2 - 0.07,
                 BH - 0.20, BH - 0.02), seat, 5.0)
    emit("folding_chair", [b.build()])


def build_zabuton():
    reset_scene()
    m = M()
    b = Builder("zabuton")
    S, H = 0.56, 0.065
    b.add(box_taper(S - 0.04, S - 0.04, S, S, H * 0.55, (0, 0, H * 0.275)), m["zab"], 2.2)
    b.add(box_taper(S, S, S - 0.05, S - 0.05, H * 0.45, (0, 0, H * 0.775)), m["zab"], 2.2)
    # 四隅の房
    for (sx, sy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        b.add(box_mm(sx * S / 2 - 0.018, sx * S / 2 + 0.018,
                     sy * S / 2 - 0.018, sy * S / 2 + 0.018, H * 0.25, H * 0.7),
              m["cloth"], 10.0)
    # 中央の綴じ
    b.add(cyl(0.012, 0.01, 5, (0, 0, H)), m["cloth"], 14.0)
    emit("zabuton", [b.build()])


def build_low_table():
    """座卓。"""
    reset_scene()
    m = M()
    b = Builder("low_table")
    W, D, H = 1.00, 0.62, 0.33
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, H - 0.035, H), m["wood"], 1.6)
    b.add(box_mm(-W / 2 + 0.02, W / 2 - 0.02, -D / 2 + 0.02, D / 2 - 0.02,
                 H - 0.055, H - 0.035), m["wood"], 2.0)
    for (sx, sy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x = sx * (W / 2 - 0.07)
        y = sy * (D / 2 - 0.07)
        b.add(box_mm(x - 0.022, x + 0.022, y - 0.022, y + 0.022, 0.0, H - 0.055),
              m["wood"], 7.0)
    # 貫
    for sy in (-1, 1):
        b.add(box_mm(-W / 2 + 0.09, W / 2 - 0.09, sy * (D / 2 - 0.08) - 0.012,
                     sy * (D / 2 - 0.08) + 0.012, 0.10, 0.13), m["wood"], 6.0)
    emit("low_table", [b.build()])


def _quilt_ring(y, w, h, z0, n_top=5):
    """掛け布団の断面(上が丸い蒲鉾形、下は平ら)。8 点の閉ループ。"""
    pts = []
    for i in range(n_top):
        a = math.pi * (1.0 - i / (n_top - 1.0))      # π → 0(-w/2 から +w/2 へ)
        pts.append((math.cos(a) * w / 2.0, y, z0 + math.sin(a) * h))
    for x in (w / 4.0, 0.0, -w / 4.0):               # 下側を戻る
        pts.append((x, y, z0))
    return pts


def build_futon():
    """敷いた布団。+Y が頭側。掛け布団は蒲鉾形にふくらませ、
    柄(futon_cloth)が見えるように敷布団のシーツ(白)と色を分ける。"""
    reset_scene()
    m = M()
    b = Builder("futon")
    W, L = 0.98, 2.00
    MAT_H = 0.095

    # --- 敷布団(白いシーツを掛けた状態) ---
    b.add(box_taper(W - 0.06, L - 0.06, W, L, MAT_H * 0.70,
                    (0, 0, MAT_H * 0.35)), m["cloth"], 2.8)
    b.add(box_taper(W, L, W - 0.05, L - 0.05, MAT_H * 0.30,
                    (0, 0, MAT_H * 0.85)), m["cloth"], 2.8)

    # --- 掛け布団(足元 -Y から胸 +Y まで。腹のあたりが一番高い) ---
    ys = (-0.995, -0.86, -0.62, -0.34, -0.05, 0.16, 0.30)
    secs = []
    for i, y in enumerate(ys):
        t = i / (len(ys) - 1.0)
        # 足先は低く、腰〜腹で膨らみ、胸元でまた下がる
        h = 0.075 + 0.145 * math.sin(min(1.0, t * 1.18) * math.pi * 0.92)
        w = W + 0.075 - 0.030 * t
        secs.append(_quilt_ring(y, w, h, MAT_H - 0.012))
    b.add(loft_rings(secs), m["fut"], 2.6)

    # --- 襟(掛け布団を折り返して白い裏地が見えるところ) ---
    b.add(box_taper(W + 0.045, 0.145, W + 0.015, 0.125, 0.105,
                    (0, 0.345, MAT_H + 0.048)), m["cloth"], 3.2)
    b.add(box_mm(-(W + 0.045) / 2, (W + 0.045) / 2, 0.272, 0.300,
                 MAT_H - 0.012, MAT_H + 0.085), m["fut"], 3.2)

    # --- 枕 ---
    b.add(box_taper(0.48, 0.28, 0.44, 0.24, 0.055, (0, 0.735, MAT_H + 0.028)),
          m["cloth"], 3.6)
    b.add(box_taper(0.44, 0.24, 0.40, 0.21, 0.045, (0, 0.735, MAT_H + 0.078)),
          m["cloth"], 3.6)
    emit("futon", [b.build()])


# ---------------------------------------------------------------- 事務所

def build_office_desk():
    """スチール事務机(袖引き出し付き)。"""
    reset_scene()
    m = M()
    b = Builder("office_desk")
    W, D, H = 1.20, 0.70, 0.72
    # 天板
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, H - 0.032, H), m["wood"], 1.5)
    b.add(box_mm(-W / 2 - 0.006, W / 2 + 0.006, -D / 2 - 0.006, D / 2 + 0.006,
                 H - 0.040, H - 0.030), m["dark"], 3.0)
    # 右の袖(引き出し 3 段)
    bx0, bx1 = W / 2 - 0.42, W / 2 - 0.02
    b.add(box_mm(bx0, bx1, -D / 2 + 0.04, D / 2 - 0.02, 0.05, H - 0.040), m["gray"], 1.8)
    for k in range(3):
        z = 0.10 + k * 0.20
        b.add(box_mm(bx0 - 0.010, bx0 - 0.002, -D / 2 + 0.03, D / 2 - 0.03, z, z + 0.175),
              m["gray"], 3.0)
        b.add(box_mm(bx0 - 0.020, bx0 - 0.008, -0.06, 0.06, z + 0.07, z + 0.105),
              m["steel"], 8.0)
    # 左の脚と幕板
    b.add(box_mm(-W / 2 + 0.02, -W / 2 + 0.06, -D / 2 + 0.04, D / 2 - 0.02, 0.05, H - 0.040),
          m["gray"], 2.0)
    b.add(box_mm(-W / 2 + 0.02, bx0, D / 2 - 0.08, D / 2 - 0.02, 0.44, H - 0.040),
          m["gray"], 2.0)
    # 台輪
    b.add(box_mm(-W / 2 + 0.02, bx1, -D / 2 + 0.06, D / 2 - 0.04, 0.0, 0.05), m["dark"], 3.0)
    emit("office_desk", [b.build()])


def build_office_chair():
    """事務椅子(5 本脚キャスター)。"""
    reset_scene()
    m = M()
    b = Builder("office_chair")
    seat = material("ChairFabric", "suit_black", color=(0.14, 0.14, 0.16), rough=0.95)
    SH = 0.46
    # 脚
    for k in range(5):
        a = math.pi * 2 * k / 5
        dx, dy = math.cos(a), math.sin(a)
        v, f = box(0.30, 0.045, 0.028, (0.15, 0, 0.055))
        v = tr(v, rot=('Z', a))
        b.add((v, f), m["dark"], 8.0)
        b.add(cyl(0.028, 0.045, 6, (dx * 0.28, dy * 0.28, 0.024)), m["dark"], 14.0)
    b.add(cyl(0.055, 0.05, 8, (0, 0, 0.075)), m["dark"], 10.0)
    # ガスシリンダ
    b.add(cyl(0.030, 0.26, 8, (0, 0, 0.21)), m["steel"], 10.0)
    b.add(cyl(0.042, 0.05, 8, (0, 0, SH - 0.06)), m["dark"], 10.0)
    # 座面
    b.add(box_taper(0.44, 0.44, 0.46, 0.44, 0.075, (0, 0, SH + 0.01)), seat, 2.4)
    b.add(box_mm(-0.20, 0.20, -0.20, 0.20, SH - 0.035, SH - 0.020), m["dark"], 3.0)
    # 背もたれ
    v, f = box_taper(0.40, 0.07, 0.36, 0.06, 0.40, (0, 0, 0))
    v = tr(v, rot=('X', -0.16), t=(0, 0.20, SH + 0.28))
    b.add((v, f), seat, 2.4)
    b.add(box_mm(-0.035, 0.035, 0.17, 0.21, SH + 0.045, SH + 0.14), m["dark"], 6.0)
    emit("office_chair", [b.build()])


def build_phone():
    """ビジネスフォン。受話器は別メッシュ `Handset`。"""
    reset_scene()
    m = M()
    body = material("PhoneBody", "plastic_beige", color=(0.70, 0.67, 0.58), rough=0.55)
    key = material("PhoneKey", "metal_dark", color=(0.22, 0.22, 0.23), rough=0.6)
    lcd = material("PhoneLcd", "crt_screen", color=(0.30, 0.40, 0.32), rough=0.2,
                   emission=(0.10, 0.18, 0.10), emission_strength=0.6)

    b = Builder("phone")
    W, D = 0.215, 0.215
    b.add(box_taper(W, D, W - 0.02, D - 0.02, 0.040, (0, 0, 0.020)), body, 4.0)
    # 本体の傾いた上面
    v, f = box_taper(W - 0.02, D - 0.03, W - 0.03, D - 0.05, 0.028, (0, 0, 0))
    v = tr(v, rot=('X', 0.20), t=(0, -0.005, 0.054))
    b.add((v, f), body, 4.0)
    # 液晶
    b.add(box_mm(-0.055, 0.055, 0.020, 0.072, 0.066, 0.070), lcd, 8.0)
    # キーパッド 3x4 + 機能キー
    for r in range(4):
        for c in range(3):
            x = -0.040 + c * 0.040
            y = -0.010 - r * 0.026
            b.add(box_mm(x - 0.016, x + 0.016, y - 0.010, y + 0.010, 0.060, 0.068), key, 14.0)
    for c in range(4):
        x = -0.078 + c * 0.052
        b.add(box_mm(x - 0.020, x + 0.020, 0.080, 0.096, 0.056, 0.062), key, 14.0)
    # 受話器を置く台の突起
    for sx in (-1, 1):
        b.add(box_mm(sx * 0.078 - 0.010, sx * 0.078 + 0.010, -0.06, -0.02, 0.040, 0.052),
              body, 14.0)
    ob = b.build()

    # --- Handset ---
    h = Builder("Handset")
    hz = 0.052
    h.add(box_taper(0.052, 0.20, 0.046, 0.19, 0.026, (0, -0.04, hz + 0.013)), body, 6.0)
    for sy in (-1, 1):
        h.add(box_taper(0.056, 0.060, 0.050, 0.054, 0.034,
                        (0, -0.04 + sy * 0.082, hz + 0.030)), body, 6.0)
    # 受話口・送話口の穴(暗い面)
    for sy in (-1, 1):
        h.add(box_mm(-0.018, 0.018, -0.04 + sy * 0.082 - 0.018, -0.04 + sy * 0.082 + 0.018,
                     hz + 0.046, hz + 0.048), key, 12.0)
    # カールコード
    for k in range(7):
        t = k / 6.0
        x = 0.085 + math.sin(t * 9.0) * 0.018
        y = -0.13 - t * 0.02
        z = 0.030 + math.cos(t * 9.0) * 0.012
        h.add(sphere(0.008, 4, 3, (x, y, z)), key, 20.0)
    hob = h.build()
    emit("phone", [ob, hob])


def build_monitor_crt():
    """事務所のモニタ(CRT)。画面は別マテリアル `Screen`。"""
    reset_scene()
    m = M()
    case = material("MonitorCase", "plastic_beige", color=(0.72, 0.68, 0.58), rough=0.55)
    scr = material("Screen", "crt_screen", color=(0.06, 0.06, 0.07), rough=0.12,
                   emission=(0.05, 0.06, 0.07), emission_strength=0.8)
    b = Builder("monitor_crt")
    W, D, H = 0.40, 0.42, 0.38
    # スタンド
    b.add(cyl(0.15, 0.030, 10, (0, 0.02, 0.015)), case, 5.0)
    b.add(cyl(0.075, 0.035, 8, (0, 0.02, 0.048)), case, 8.0)
    # 筐体(後ろすぼまり)
    b.add(box_taper(W, D, W - 0.14, D, H - 0.09, (0, 0.03, 0.066 + (H - 0.09) / 2)), case, 2.2)
    # 前面のベゼル
    b.add(box_mm(-W / 2 - 0.006, W / 2 + 0.006, -D / 2 - 0.012, -D / 2 + 0.02,
                 0.066, 0.066 + H - 0.09), case, 2.8)
    # 画面(わずかに凸)
    sx, sz0, sz1 = W / 2 - 0.035, 0.066 + 0.035, 0.066 + H - 0.125
    b.add(box_mm(-sx, sx, -D / 2 - 0.016, -D / 2 - 0.012, sz0, sz1), scr,
          uv=[UVQ] * 6)
    # つまみとランプ
    for k in range(3):
        b.add(box_mm(-0.12 + k * 0.05, -0.09 + k * 0.05, -D / 2 - 0.014, -D / 2 - 0.004,
                     0.080, 0.094), m["dark"], 16.0)
    b.add(cyl(0.006, 0.006, 5, (0.14, -D / 2 - 0.012, 0.087), axis='Y'),
          material("MonLed", None, color=(0.2, 0.9, 0.3),
                   emission=(0.15, 0.9, 0.25), emission_strength=3.0), 20.0)
    emit("monitor_crt", [b.build()])


def build_tv_crt():
    """控室のブラウン管テレビ。"""
    reset_scene()
    m = M()
    case = material("TvCase", "plastic_beige", color=(0.42, 0.38, 0.33), rough=0.6)
    scr = material("Screen", "crt_screen", color=(0.06, 0.06, 0.07), rough=0.12,
                   emission=(0.04, 0.05, 0.06), emission_strength=0.6)
    b = Builder("tv_crt")
    W, D, H = 0.56, 0.48, 0.46
    b.add(box_taper(W, D, W - 0.16, D, H - 0.06, (0, 0.02, 0.03 + (H - 0.06) / 2)), case, 1.8)
    b.add(box_mm(-W / 2 - 0.008, W / 2 + 0.008, -D / 2 - 0.014, -D / 2 + 0.03,
                 0.03, H - 0.03), case, 2.2)
    # 脚
    for (sx, sy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        b.add(box_mm(sx * (W / 2 - 0.06) - 0.025, sx * (W / 2 - 0.06) + 0.025,
                     sy * (D / 2 - 0.06) - 0.025, sy * (D / 2 - 0.06) + 0.025, 0.0, 0.03),
              m["dark"], 10.0)
    # 画面
    b.add(box_mm(-W / 2 + 0.05, W / 2 - 0.115, -D / 2 - 0.018, -D / 2 - 0.014,
                 0.075, H - 0.075), scr, uv=[UVQ] * 6)
    # 右の操作パネル
    b.add(box_mm(W / 2 - 0.10, W / 2 - 0.02, -D / 2 - 0.016, -D / 2 - 0.008, 0.07, H - 0.07),
          m["dark"], 6.0)
    for k in range(4):
        b.add(cyl(0.011, 0.008, 6, (W / 2 - 0.06, -D / 2 - 0.020, 0.11 + k * 0.07), axis='Y'),
              case, 14.0)
    emit("tv_crt", [b.build()])


# ---------------------------------------------------------------- バックヤード

def build_freezer_chest():
    """横型の冷凍庫。蓋は別ノード `Lid`(原点 = 奥側の蝶番)。X 回転で開く。"""
    reset_scene()
    m = M()
    white = material("FreezerBody", "metal_gray", color=(0.70, 0.70, 0.68), rough=0.5)
    W, D, H = 1.22, 0.66, 0.86
    LID_Z = H - 0.075

    frost = material("FreezerInner", "styrofoam", color=(0.80, 0.83, 0.85), rough=0.85)
    WT = 0.075                                   # 断熱壁の厚み

    b = Builder("freezer_chest")
    # 蓋を開けたときに中が見えるよう、天面は開けて 4 枚の壁で組む
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, 0.045, 0.26), white, 1.4)   # 下半分は詰まった台
    for (x0, x1, y0, y1) in ((-W / 2, W / 2, -D / 2, -D / 2 + WT),
                             (-W / 2, W / 2, D / 2 - WT, D / 2),
                             (-W / 2, -W / 2 + WT, -D / 2 + WT, D / 2 - WT),
                             (W / 2 - WT, W / 2, -D / 2 + WT, D / 2 - WT)):
        b.add(box_mm(x0, x1, y0, y1, 0.26, LID_Z), white, 1.4)
    # 庫内(霜のついた内張り)
    b.add(box_mm(-W / 2 + WT, W / 2 - WT, -D / 2 + WT, D / 2 - WT, 0.26, 0.285), frost, 2.4)
    for (x0, x1, y0, y1) in ((-W / 2 + WT, W / 2 - WT, -D / 2 + WT, -D / 2 + WT + 0.010),
                             (-W / 2 + WT, W / 2 - WT, D / 2 - WT - 0.010, D / 2 - WT),
                             (-W / 2 + WT, -W / 2 + WT + 0.010, -D / 2 + WT, D / 2 - WT),
                             (W / 2 - WT - 0.010, W / 2 - WT, -D / 2 + WT, D / 2 - WT)):
        b.add(box_mm(x0, x1, y0, y1, 0.285, LID_Z), frost, 2.4)
    b.add(box_mm(-W / 2 + 0.03, W / 2 - 0.03, -D / 2 + 0.03, D / 2 - 0.03, 0.0, 0.045),
          m["dark"], 2.5)
    # 温度計と表示ランプ(本体側)
    b.add(box_mm(W / 2 - 0.26, W / 2 - 0.10, -D / 2 - 0.014, -D / 2 - 0.004, 0.58, 0.68),
          m["dark"], 5.0)
    b.add(box_mm(W / 2 - 0.235, W / 2 - 0.125, -D / 2 - 0.018, -D / 2 - 0.012, 0.605, 0.655),
          material("FreezerLed", None, color=(0.9, 0.25, 0.2),
                   emission=(1.0, 0.22, 0.15), emission_strength=2.0), 8.0)
    body = b.build()

    # --- 蓋(奥の長辺が蝶番) ---
    lid = Builder("Lid")
    lid.add(box_mm(-W / 2 - 0.012, W / 2 + 0.012, -D / 2 - 0.012, D / 2 + 0.012,
                   LID_Z, H), white, 1.4)
    lid.add(box_mm(-W / 2 - 0.012, W / 2 + 0.012, -D / 2 - 0.016, -D / 2 - 0.006,
                   H - 0.055, H - 0.018), m["steel"], 3.0)
    lid.add(box_mm(-0.16, 0.16, -D / 2 - 0.045, -D / 2 - 0.014, H - 0.055, H - 0.028),
            m["steel"], 6.0)                                   # ハンドル
    lid_ob = build_at(lid, (0.0, D / 2 + 0.012, LID_Z))
    emit("freezer_chest", [body, lid_ob])


def build_dry_ice_box():
    """発泡スチロールの箱(ドライアイス用、蓋はずらしてある)。"""
    reset_scene()
    m = M()
    b = Builder("dry_ice_box")
    W, D, H = 0.52, 0.36, 0.30
    t = 0.035
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, 0.0, t), m["foam"], 2.2)
    for (x0, x1, y0, y1) in ((-W / 2, -W / 2 + t, -D / 2, D / 2),
                             (W / 2 - t, W / 2, -D / 2, D / 2),
                             (-W / 2 + t, W / 2 - t, -D / 2, -D / 2 + t),
                             (-W / 2 + t, W / 2 - t, D / 2 - t, D / 2)):
        b.add(box_mm(x0, x1, y0, y1, t, H - 0.05), m["foam"], 2.2)
    # 蓋(少しずらして載せる)
    b.add(box_mm(-W / 2 + 0.04, W / 2 + 0.04, -D / 2 + 0.02, D / 2 + 0.02, H - 0.05, H),
          m["foam"], 2.2)
    b.add(box_mm(-W / 2 + 0.09, W / 2 - 0.01, -D / 2 + 0.07, D / 2 - 0.03,
                 H - 0.068, H - 0.05), m["foam"], 2.6)
    # ガムテープ
    b.add(box_mm(-0.07, 0.07, -D / 2 - 0.004, D / 2 + 0.004, H - 0.052, H + 0.002),
          m["card"], 6.0)
    emit("dry_ice_box", [b.build()])


def build_vending_machine():
    """自販機。前面は発光用に別マテリアル `Panel`。"""
    reset_scene()
    m = M()
    body = material("VendBody", "paint_red", color=(0.52, 0.09, 0.08), rough=0.5)
    # 発光は控えめに。level/systems 側で emission_energy を上げれば夜に効く。
    panel = material("Panel", "vending_panel", color=(0.85, 0.2, 0.15), rough=0.25,
                     emission=(0.95, 0.88, 0.72), emission_strength=0.30)
    b = Builder("vending_machine")
    W, D, H = 1.05, 0.76, 1.86
    b.add(box_mm(-W / 2, W / 2, -D / 2 + 0.03, D / 2, 0.06, H), body, 1.2)
    b.add(box_mm(-W / 2 + 0.03, W / 2 - 0.03, -D / 2 + 0.06, D / 2 - 0.03, 0.0, 0.06),
          m["dark"], 2.0)
    # 前面パネル(発光)
    b.add(box_mm(-W / 2 + 0.035, W / 2 - 0.035, -D / 2 + 0.005, -D / 2 + 0.03, 0.40, H - 0.06),
          panel, uv=[UVQ] * 6)
    # パネルの枠
    for (x0, x1, z0, z1) in ((-W / 2, -W / 2 + 0.035, 0.36, H - 0.03),
                             (W / 2 - 0.035, W / 2, 0.36, H - 0.03),
                             (-W / 2, W / 2, H - 0.06, H - 0.03),
                             (-W / 2, W / 2, 0.36, 0.40)):
        b.add(box_mm(x0, x1, -D / 2, -D / 2 + 0.03, z0, z1), m["dark"], 3.0)
    # 取り出し口
    b.add(box_mm(-W / 2 + 0.08, -W / 2 + 0.50, -D / 2 - 0.012, -D / 2 + 0.03, 0.10, 0.34),
          m["dark"], 2.4)
    b.add(box_mm(-W / 2 + 0.10, -W / 2 + 0.48, -D / 2 - 0.020, -D / 2 - 0.008, 0.13, 0.31),
          m["steel"], 3.0)
    # コイン投入・返却
    b.add(box_mm(W / 2 - 0.32, W / 2 - 0.06, -D / 2 - 0.010, -D / 2 + 0.03, 0.12, 0.34),
          m["gray"], 3.0)
    b.add(cyl(0.016, 0.012, 6, (W / 2 - 0.16, -D / 2 - 0.014, 0.28), axis='Y'), m["dark"], 14.0)
    emit("vending_machine", [b.build()])


def build_breaker_box():
    """分電盤。原点は箱の下端中央(level が壁の高さ 推奨 1.40m へ置く)。
    主幹ブレーカーのレバーは別ノード `Lever`(原点 = 回転軸)。X 回転で上下。"""
    reset_scene()
    m = M()
    W, D, H = 0.42, 0.11, 0.32
    LVX = -W / 2 + 0.070          # 主幹レバーの中心
    LVZ = 0.210                   # 回転軸の高さ
    LVY = -0.006                  # 盤面(レバーはここから手前 -Y へ出る)

    b = Builder("breaker_box")
    b.add(box_mm(-W / 2, W / 2, 0.0, D, 0.0, H), m["gray"], 3.0)
    # 扉(開いた状態: 左に 100 度)
    v, f = box_mm(0, W - 0.03, 0, 0.014, 0.012, H - 0.012)
    v = tr(v, rot=('Z', 2.0), t=(-W / 2 + 0.01, 0.0, 0))
    b.add((v, f), m["gray"], 3.0)
    # 内部のブレーカ列
    b.add(box_mm(-W / 2 + 0.025, W / 2 - 0.025, 0.0, 0.006, 0.03, H - 0.03), m["dark"], 4.0)
    b.add(box_mm(-W / 2 + 0.035, -W / 2 + 0.105, -0.010, 0.006, 0.16, 0.26),
          m["beige"], 8.0)                                    # 主幹ブレーカーの本体
    for k in range(8):
        x = -W / 2 + 0.135 + k * 0.032
        b.add(box_mm(x, x + 0.024, -0.008, 0.006, 0.14, 0.24), m["beige"], 12.0)
        b.add(box_mm(x + 0.004, x + 0.020, -0.014, -0.006, 0.175, 0.205), m["dark"], 18.0)
    body = b.build()

    # --- 主幹レバー(原点は回転軸。X 回転で上下に倒れる) ---
    lv = Builder("Lever")
    lv.add(box_mm(LVX - 0.018, LVX + 0.018, LVY - 0.024, LVY, LVZ - 0.014, LVZ + 0.014),
           m["dark"], 16.0)
    lv.add(box_mm(LVX - 0.014, LVX + 0.014, LVY - 0.030, LVY - 0.022,
                  LVZ - 0.010, LVZ + 0.010), m["dark"], 20.0)
    lever = build_at(lv, (LVX, LVY, LVZ))
    emit("breaker_box", [body, lever])


def build_safe():
    """事務所の金庫。扉は別ノード `Door`(原点 = 左側の蝶番)。Z 回転で開く。"""
    reset_scene()
    m = M()
    dark = material("SafeBody", "metal_dark", color=(0.16, 0.17, 0.17), rough=0.55)
    W, D, H = 0.46, 0.48, 0.58
    DX0 = -W / 2 + 0.025          # 扉の左端 = 蝶番
    DY = -D / 2 - 0.014           # 扉の前面

    WT = 0.05                     # 金庫の壁厚
    inner = material("SafeInner", "metal_dark", color=(0.09, 0.09, 0.10), rough=0.9)

    b = Builder("safe")
    # 扉を開けたときに中が見えるよう、前面は開けて 5 枚で組む
    for (x0, x1, y0, y1, z0, z1) in (
            (-W / 2, W / 2, -D / 2 + WT, D / 2, 0.02, H),               # 奥と側面をまとめた塊
            (-W / 2, -W / 2 + WT, -D / 2, -D / 2 + WT, 0.02, H),        # 前面の左枠
            (W / 2 - WT, W / 2, -D / 2, -D / 2 + WT, 0.02, H),          # 前面の右枠
            (-W / 2 + WT, W / 2 - WT, -D / 2, -D / 2 + WT, 0.02, 0.07),  # 前面の下枠
            (-W / 2 + WT, W / 2 - WT, -D / 2, -D / 2 + WT, H - 0.05, H)):  # 前面の上枠
        b.add(box_mm(x0, x1, y0, y1, z0, z1), dark, 2.2)
    b.add(box_mm(-W / 2 + 0.02, W / 2 - 0.02, -D / 2 + 0.02, D / 2 - 0.02, 0.0, 0.02),
          m["dark"], 4.0)
    # 庫内(奥と棚板)
    b.add(box_mm(-W / 2 + WT, W / 2 - WT, -D / 2 + WT, -D / 2 + WT + 0.008, 0.07, H - 0.05),
          inner, 3.0)
    b.add(box_mm(-W / 2 + WT, W / 2 - WT, -D / 2 + WT, D / 2 - WT, 0.07, 0.085), inner, 3.0)
    b.add(box_mm(-W / 2 + WT, W / 2 - WT, -D / 2 + WT, D / 2 - WT, 0.30, 0.315), dark, 3.0)
    body = b.build()

    # --- 扉(ダイヤル・ハンドル・銘板も扉側) ---
    d = Builder("Door")
    d.add(box_mm(DX0, W / 2 - 0.025, DY, -D / 2 + 0.01, 0.05, H - 0.03), dark, 2.6)
    d.add(cyl(0.062, 0.014, 10, (-0.03, DY - 0.007, 0.36), axis='Y'), m["steel"], 6.0)
    d.add(cyl(0.048, 0.010, 10, (-0.03, DY - 0.014, 0.36), axis='Y'), m["dark"], 7.0)
    d.add(box_mm(-0.034, -0.026, DY - 0.020, DY - 0.012, 0.36, 0.405), m["steel"], 18.0)
    d.add(cyl(0.012, 0.11, 6, (0.13, DY - 0.011, 0.30)), m["steel"], 10.0)
    d.add(cyl(0.010, 0.07, 6, (0.13, DY - 0.011, 0.30), axis='X'), m["steel"], 10.0)
    d.add(cyl(0.024, 0.020, 8, (0.13, DY - 0.004, 0.30), axis='Y'), m["steel"], 10.0)
    d.add(box_mm(-0.06, 0.06, DY - 0.004, DY, 0.50, 0.53), m["steel"], 10.0)
    door_ob = build_at(d, (DX0, DY, 0.05))
    emit("safe", [body, door_ob])


def build_sink():
    """バックヤードの流し(ステンレス)。"""
    reset_scene()
    m = M()
    b = Builder("sink")
    W, D, H = 0.72, 0.48, 0.82
    # 天板
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, H - 0.03, H), m["steel"], 2.2)
    # 槽(内側をへこませる: 縁 4 枚 + 底)
    sx0, sx1, sy0, sy1 = -0.26, 0.26, -0.17, 0.17
    b.add(box_mm(sx0, sx1, sy0, sy1, H - 0.22, H - 0.20), m["steel"], 3.0)
    for (x0, x1, y0, y1) in ((sx0 - 0.02, sx0, sy0 - 0.02, sy1 + 0.02),
                             (sx1, sx1 + 0.02, sy0 - 0.02, sy1 + 0.02),
                             (sx0, sx1, sy0 - 0.02, sy0),
                             (sx0, sx1, sy1, sy1 + 0.02)):
        b.add(box_mm(x0, x1, y0, y1, H - 0.22, H - 0.03), m["steel"], 3.0)
    b.add(cyl(0.028, 0.02, 8, (0, 0, H - 0.205)), m["dark"], 12.0)
    # 本体(キャビネット)
    b.add(box_mm(-W / 2 + 0.02, W / 2 - 0.02, -D / 2 + 0.03, D / 2 - 0.02, 0.05, H - 0.03),
          m["steel"], 1.8)
    b.add(box_mm(-W / 2 + 0.04, W / 2 - 0.04, -D / 2 + 0.05, D / 2 - 0.04, 0.0, 0.05),
          m["dark"], 3.0)
    b.add(box_mm(-W / 2 + 0.03, W / 2 - 0.03, -D / 2 + 0.02, -D / 2 + 0.032, 0.10, H - 0.10),
          m["steel"], 2.4)
    b.add(box_mm(-0.10, 0.10, -D / 2 + 0.010, -D / 2 + 0.024, 0.50, 0.52), m["dark"], 8.0)
    # 蛇口
    b.add(cyl(0.022, 0.24, 8, (0, D / 2 - 0.08, H + 0.12)), m["steel"], 8.0)
    b.add(cyl(0.016, 0.22, 6, (0, D / 2 - 0.19, H + 0.22), axis='Y'), m["steel"], 10.0)
    b.add(cyl(0.013, 0.05, 6, (0, D / 2 - 0.30, H + 0.20)), m["steel"], 12.0)
    for sx in (-1, 1):
        b.add(box_mm(sx * 0.03, sx * 0.075, D / 2 - 0.095, D / 2 - 0.065, H + 0.19, H + 0.21),
              m["steel"], 14.0)
    emit("sink", [b.build()])


def build_shelf():
    """在庫棚(スチールラック 4 段)。"""
    reset_scene()
    m = M()
    b = Builder("shelf")
    W, D, H = 0.92, 0.42, 1.80
    for (sx, sy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x = sx * (W / 2 - 0.022)
        y = sy * (D / 2 - 0.022)
        b.add(box_mm(x - 0.020, x + 0.020, y - 0.020, y + 0.020, 0.0, H), m["gray"], 5.0)
    for k in range(4):
        z = 0.16 + k * 0.52
        b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, z, z + 0.022), m["gray"], 1.6)
        b.add(box_mm(-W / 2, W / 2, -D / 2, -D / 2 + 0.016, z + 0.022, z + 0.045),
              m["gray"], 3.0)
        b.add(box_mm(-W / 2, W / 2, D / 2 - 0.016, D / 2, z + 0.022, z + 0.045), m["gray"], 3.0)
    # 積んである段ボールと線香の箱
    for (x, y, z, w, d, h) in ((-0.24, 0.02, 0.182, 0.34, 0.28, 0.22),
                               (0.20, -0.02, 0.182, 0.28, 0.24, 0.18),
                               (-0.18, 0.0, 0.702, 0.30, 0.26, 0.20),
                               (0.22, 0.02, 1.222, 0.26, 0.22, 0.16)):
        b.add(box_mm(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z, z + h), m["card"], 2.4)
    emit("shelf", [b.build()])


def build_cabinet():
    """書庫(両開きのスチール書棚)。"""
    reset_scene()
    m = M()
    b = Builder("cabinet")
    W, D, H = 0.90, 0.46, 1.80
    b.add(box_mm(-W / 2, W / 2, -D / 2 + 0.02, D / 2, 0.04, H), m["gray"], 1.4)
    b.add(box_mm(-W / 2 + 0.02, W / 2 - 0.02, -D / 2 + 0.04, D / 2 - 0.02, 0.0, 0.04),
          m["dark"], 3.0)
    # 扉 2 枚
    for sx in (-1, 1):
        x0 = 0.004 if sx > 0 else -W / 2 + 0.01
        x1 = W / 2 - 0.01 if sx > 0 else -0.004
        b.add(box_mm(x0, x1, -D / 2 + 0.004, -D / 2 + 0.022, 0.07, H - 0.03), m["gray"], 1.8)
        hx = sx * 0.05
        b.add(box_mm(hx - 0.010, hx + 0.010, -D / 2 - 0.016, -D / 2 + 0.006, 0.86, 1.02),
              m["steel"], 8.0)
    # 天板の見切り
    b.add(box_mm(-W / 2 - 0.008, W / 2 + 0.008, -D / 2, D / 2 + 0.008, H - 0.022, H),
          m["gray"], 2.0)
    # ラベル差し
    b.add(box_mm(-0.30, -0.12, -D / 2 - 0.002, -D / 2 + 0.006, 1.40, 1.46), m["beige"], 8.0)
    emit("cabinet", [b.build()])


def build_toilet():
    """洋式便器(タンク付き、白い陶器)。蓋は上げてタンクに立てかけた状態。
    原点は床の中心、正面は -Y。"""
    reset_scene()
    m = M()
    porc = material("Porcelain", "porcelain", color=(0.90, 0.90, 0.88), rough=0.16)
    seat = material("ToiletSeat", "plastic_beige", color=(0.86, 0.84, 0.78), rough=0.32)
    water = material("ToiletWater", None, color=(0.13, 0.18, 0.20), rough=0.05)

    b = Builder("toilet")
    # 台座(床から鉢まで、いったん細くなって広がる)
    b.add(box_taper(0.30, 0.44, 0.24, 0.40, 0.055, (0, -0.02, 0.0275)), porc, 3.0)
    b.add(box_taper(0.24, 0.40, 0.27, 0.42, 0.155, (0, -0.02, 0.1325)), porc, 3.0)
    b.add(box_taper(0.27, 0.42, 0.33, 0.45, 0.090, (0, -0.03, 0.255)), porc, 3.0)
    # 鉢(楕円)
    b.add(oval_cyl(0.168, 0.202, 0.100, 12, (0, -0.05, 0.350),
                   rx_top=0.186, ry_top=0.226), porc, 3.0)
    # 溜まった水
    b.add(oval_cyl(0.132, 0.162, 0.004, 12, (0, -0.05, 0.332)), water, 4.0)
    # リム
    b.add(donut(0, -0.05, 0.396, 0.140, 0.172, 0.190, 0.230, 0.022, 12), porc, 4.0)
    # 便座
    b.add(donut(0, -0.05, 0.418, 0.128, 0.158, 0.196, 0.236, 0.026, 12), seat, 4.0)
    # 蓋(上げてタンクに立てかける)
    lv, lf = oval_cyl(0.196, 0.238, 0.020, 12, (0, 0, 0))
    lv = tr(lv, rot=('X', 1.36), t=(0, 0.100, 0.590))
    b.add((lv, lf), seat, 4.0)
    # タンク
    b.add(box_mm(-0.190, 0.190, 0.155, 0.345, 0.400, 0.740), porc, 2.4)
    b.add(box_mm(-0.202, 0.202, 0.143, 0.357, 0.740, 0.775), porc, 2.4)
    # 洗浄レバー
    b.add(cyl(0.013, 0.030, 6, (-0.148, 0.152, 0.688), axis='Y'), m["steel"], 12.0)
    b.add(box_mm(-0.170, -0.126, 0.108, 0.152, 0.676, 0.698), m["steel"], 10.0)
    # 給水管と止水栓
    b.add(cyl(0.011, 0.300, 6, (0.145, 0.330, 0.250)), m["steel"], 10.0)
    b.add(cyl(0.021, 0.048, 6, (0.145, 0.330, 0.086)), m["steel"], 12.0)
    emit("toilet", [b.build()])


def main():
    build_folding_chair()
    build_zabuton()
    build_low_table()
    build_futon()
    build_office_desk()
    build_office_chair()
    build_phone()
    build_monitor_crt()
    build_tv_crt()
    build_freezer_chest()
    build_dry_ice_box()
    build_vending_machine()
    build_breaker_box()
    build_safe()
    build_sink()
    build_shelf()
    build_cabinet()
    build_toilet()
    dump_report()


if __name__ == "__main__":
    main()
