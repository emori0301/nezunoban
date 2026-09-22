"""小物: kettle guest_book_stand umbrella_stand slippers wall_clock
fire_extinguisher notice_board sake_bottle beer_can matches incense_box
coil_incense

blender --background --python tools/blender/build_props.py
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from common import (reset_scene, material, Builder, emit, dump_report,
                    box, box_mm, box_taper, cyl, sphere, prism, tr, frame_quads)

UVQ = [(0, 0), (1, 0), (1, 1), (0, 1)]


def build_kettle():
    """やかん(アルミ)。"""
    reset_scene()
    al = material("Alu", "steel", color=(0.60, 0.60, 0.61), rough=0.40, metal=0.8)
    dk = material("KettleGrip", "metal_dark", color=(0.14, 0.14, 0.15), rough=0.8)
    b = Builder("kettle")
    b.add(cyl(0.105, 0.115, 10, (0, 0, 0.060), r_top=0.095), al, 5.0)
    b.add(cyl(0.095, 0.045, 10, (0, 0, 0.140), r_top=0.055), al, 6.0)
    b.add(cyl(0.056, 0.016, 8, (0, 0, 0.170)), al, 10.0)
    b.add(cyl(0.050, 0.012, 8, (0, 0, 0.182)), al, 10.0)
    b.add(sphere(0.016, 5, 3, (0, 0, 0.196)), dk, 14.0)
    # 注ぎ口
    v, f = cyl(0.020, 0.13, 6, (0, 0, 0), r_top=0.012)
    v = tr(v, rot=('Y', 1.15), t=(0.11, 0, 0.115))
    b.add((v, f), al, 12.0)
    # つる(ハンドル)
    for k in range(5):
        t = k / 4.0
        a = math.pi * t
        b.add(cyl(0.008, 0.045, 4, (math.cos(a) * 0.098, 0, 0.165 + math.sin(a) * 0.075)),
              dk, 16.0)
    emit("kettle", [b.build()])


def build_guest_book_stand():
    """芳名帳の記帳台(傾いた天板 + 芳名帳 + 筆ペン)。"""
    reset_scene()
    wood = material("StandWood", "wood_dark", color=(0.17, 0.12, 0.09), rough=0.7)
    cloth = material("StandCloth", "white_cloth", color=(0.87, 0.86, 0.83), rough=0.95)
    book = material("GuestBook", "guest_book", color=(0.85, 0.83, 0.75), rough=0.9)
    dk = material("Pen", "metal_dark", color=(0.10, 0.10, 0.11), rough=0.5)
    b = Builder("guest_book_stand")
    W, D, H = 0.66, 0.42, 1.00
    for (sx, sy) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x = sx * (W / 2 - 0.05)
        y = sy * (D / 2 - 0.05)
        b.add(box_mm(x - 0.020, x + 0.020, y - 0.020, y + 0.020, 0.0, H - 0.09), wood, 8.0)
    b.add(box_mm(-W / 2 + 0.03, W / 2 - 0.03, -D / 2 + 0.03, D / 2 - 0.03, 0.14, 0.17),
          wood, 3.0)
    # 傾いた天板
    v, f = box_mm(-W / 2, W / 2, -D / 2, D / 2, -0.016, 0.0)
    v = tr(v, rot=('X', -0.20), t=(0, 0, H - 0.05))
    b.add((v, f), wood, 2.0)
    # 白布
    v, f = box_mm(-W / 2 + 0.01, W / 2 - 0.01, -D / 2 + 0.01, D / 2 - 0.01, 0.0, 0.008)
    v = tr(v, rot=('X', -0.20), t=(0, 0, H - 0.05))
    b.add((v, f), cloth, 2.0)
    # 芳名帳(開いてある)
    v, f = box_mm(-0.17, 0.17, -0.12, 0.12, 0.008, 0.028)
    v = tr(v, rot=('X', -0.20), t=(-0.04, 0.0, H - 0.05))
    b.add((v, f), book, uv=[UVQ] * 6)
    # 筆ペンと硯箱
    v, f = cyl(0.008, 0.14, 5, (0, 0, 0), axis='X')
    v = tr(v, rot=('X', -0.20), t=(0.20, -0.04, H - 0.032))
    b.add((v, f), dk, 14.0)
    emit("guest_book_stand", [b.build()])


def build_umbrella_stand():
    reset_scene()
    st = material("StandSteel", "steel", color=(0.55, 0.56, 0.57), rough=0.5, metal=0.7)
    dk = material("Umbrella", "metal_dark", color=(0.13, 0.14, 0.16), rough=0.85)
    b = Builder("umbrella_stand")
    b.add(cyl(0.135, 0.50, 10, (0, 0, 0.25)), st, 3.5)
    b.add(cyl(0.150, 0.022, 10, (0, 0, 0.011)), st, 5.0)
    b.add(cyl(0.142, 0.018, 10, (0, 0, 0.49)), st, 5.0)
    b.add(cyl(0.118, 0.010, 10, (0, 0, 0.06)), dk, 6.0)
    # 傘 2 本
    for (dx, dy, tx, ty) in ((-0.05, 0.03, -0.10, 0.06), (0.06, -0.02, 0.13, -0.05)):
        v, f = cyl(0.020, 0.86, 6, (0, 0, 0.43))
        v = [(x + tx * (z / 0.86), y + ty * (z / 0.86), z) for (x, y, z) in v]
        v = tr(v, t=(dx, dy, 0.02))
        b.add((v, f), dk, 8.0)
        b.add(cyl(0.010, 0.08, 5, (dx + tx * 1.03, dy + ty * 1.03, 0.90)), dk, 12.0)
    emit("umbrella_stand", [b.build()])


def build_slippers():
    """来客用スリッパ(2 足並べた状態)。"""
    reset_scene()
    gr = material("SlipperVinyl", "slipper", color=(0.24, 0.34, 0.27), rough=0.7)
    dk = material("SlipperSole", "metal_dark", color=(0.13, 0.13, 0.13), rough=0.95)
    b = Builder("slippers")
    for sx in (-1, 1):
        x = sx * 0.075
        b.add(box_taper(0.115, 0.28, 0.105, 0.26, 0.016, (x, 0, 0.008)), dk, 7.0)
        b.add(box_taper(0.105, 0.26, 0.100, 0.25, 0.012, (x, 0, 0.022)), gr, 7.0)
        # 甲のカバー
        v, f = box_taper(0.105, 0.115, 0.075, 0.100, 0.055, (0, 0, 0))
        v = tr(v, rot=('X', 0.22), t=(x, 0.075, 0.050))
        b.add((v, f), gr, 8.0)
        b.add(box_mm(x - 0.030, x + 0.030, 0.030, 0.108, 0.070, 0.076), gr, 9.0)
    emit("slippers", [b.build()])


def build_wall_clock():
    """壁掛け時計。原点は時計の下端中央(level が壁の高さ 推奨 1.90m へ置く)。"""
    reset_scene()
    case = material("ClockCase", "plastic_beige", color=(0.30, 0.27, 0.23), rough=0.6)
    face = material("ClockFace", "clock_face", color=(0.88, 0.86, 0.80), rough=0.6)
    glass = material("ClockGlass", "glass_frost", color=(0.85, 0.88, 0.9),
                     rough=0.08, alpha=0.18)
    b = Builder("wall_clock")
    R = 0.155
    b.add(cyl(R, 0.048, 14, (0, 0.024, R), axis='Y'), case, 3.5)
    b.add(cyl(R - 0.014, 0.008, 14, (0, -0.006, R), axis='Y'), face,
          uv=[[(0.5 + math.cos(2 * math.pi * k / 14) * 0.5,
                0.5 + math.sin(2 * math.pi * k / 14) * 0.5) for k in range(14)]] * 20)
    b.add(cyl(R - 0.008, 0.004, 14, (0, -0.012, R), axis='Y'), glass, 3.5)
    emit("wall_clock", [b.build()])


def build_fire_extinguisher():
    reset_scene()
    red = material("ExtBody", "paint_red", color=(0.50, 0.08, 0.06), rough=0.45)
    dk = material("ExtMetal", "metal_dark", color=(0.15, 0.15, 0.16), rough=0.5, metal=0.5)
    lbl = material("ExtLabel", "paper_yellow", color=(0.82, 0.78, 0.65), rough=0.85)
    b = Builder("fire_extinguisher")
    b.add(cyl(0.078, 0.40, 10, (0, 0, 0.212), r_top=0.076), red, 4.0)
    b.add(cyl(0.080, 0.022, 10, (0, 0, 0.011)), dk, 6.0)
    b.add(cyl(0.070, 0.055, 10, (0, 0, 0.440), r_top=0.032), red, 6.0)
    b.add(cyl(0.020, 0.045, 8, (0, 0, 0.488)), dk, 10.0)
    # レバー
    b.add(box_mm(-0.018, 0.018, -0.012, 0.012, 0.508, 0.522), dk, 12.0)
    b.add(box_mm(-0.016, 0.016, -0.100, 0.014, 0.520, 0.532), dk, 8.0)
    b.add(box_mm(-0.016, 0.016, -0.020, 0.090, 0.504, 0.514), dk, 8.0)
    # ホース
    for k in range(6):
        t = k / 5.0
        b.add(cyl(0.010, 0.075, 5, (0.055 + math.sin(t * 2.2) * 0.030, 0,
                                    0.46 - t * 0.30)), dk, 14.0)
    b.add(cyl(0.017, 0.07, 6, (0.085, 0, 0.13), r_top=0.026), dk, 12.0)
    # ラベル
    b.add(cyl(0.080, 0.16, 10, (0, 0, 0.26)), lbl, 4.0)
    emit("fire_extinguisher", [b.build()])


def build_notice_board():
    """掲示板(コルクに紙が貼ってある)。原点は掲示板の下端中央。
    level は壁の高さ(推奨 1.05m)へ持ち上げて置く。"""
    reset_scene()
    frame = material("BoardFrame", "metal_gray", color=(0.42, 0.42, 0.41), rough=0.55)
    paper = material("BoardPaper", "notice_paper", color=(0.55, 0.50, 0.42), rough=0.95)
    b = Builder("notice_board")
    W, H = 0.92, 0.66
    Z0 = 0.0
    fv, ff = frame_quads(W, H, W - 0.05, H - 0.05, 0.0, 0.032, c=(0, 0, Z0 + H / 2))
    b.add((fv, ff), frame, 5.0)
    b.add(box_mm(-W / 2 + 0.02, W / 2 - 0.02, 0.006, 0.020, Z0 + 0.02, Z0 + H - 0.02),
          paper, uv=[UVQ] * 6)
    emit("notice_board", [b.build()])


def build_sake_bottle():
    """一升瓶。"""
    reset_scene()
    glass = material("BottleGlass", "label_sake", color=(0.10, 0.16, 0.11), rough=0.15)
    cap = material("BottleCap", "gold", color=(0.65, 0.55, 0.22), rough=0.35, metal=0.7)
    b = Builder("sake_bottle")
    b.add(cyl(0.052, 0.235, 8, (0, 0, 0.118)), glass, uv=[[(0, 0), (1, 0), (1, 1), (0, 1)]] * 10)
    b.add(cyl(0.052, 0.055, 8, (0, 0, 0.263), r_top=0.019), glass, 6.0)
    b.add(cyl(0.019, 0.095, 8, (0, 0, 0.338)), glass, 8.0)
    b.add(cyl(0.023, 0.014, 8, (0, 0, 0.392)), cap, 10.0)
    b.add(cyl(0.021, 0.026, 8, (0, 0, 0.408)), cap, 10.0)
    emit("sake_bottle", [b.build()])


def build_beer_can():
    reset_scene()
    can = material("CanBody", "label_beer", color=(0.72, 0.72, 0.74), rough=0.3, metal=0.5)
    top = material("CanTop", "steel", color=(0.62, 0.63, 0.64), rough=0.3, metal=0.9)
    b = Builder("beer_can")
    b.add(cyl(0.033, 0.104, 10, (0, 0, 0.056)), can,
          uv=[[(0, 0), (1, 0), (1, 1), (0, 1)]] * 12)
    b.add(cyl(0.033, 0.008, 10, (0, 0, 0.004), r_top=0.028), top, 8.0)
    b.add(cyl(0.033, 0.010, 10, (0, 0, 0.113), r_top=0.028), top, 8.0)
    b.add(cyl(0.028, 0.004, 10, (0, 0, 0.120)), top, 10.0)
    emit("beer_can", [b.build()])


def build_matches():
    """マッチ箱(少し開いていて軸が見える)。"""
    reset_scene()
    box_m = material("MatchBox", "matchbox", color=(0.62, 0.30, 0.20), rough=0.9)
    stick = material("MatchStick", "white_wood", color=(0.80, 0.74, 0.60), rough=0.9)
    head = material("MatchHead", "paint_red", color=(0.55, 0.12, 0.08), rough=0.7)
    b = Builder("matches")
    W, D, H = 0.056, 0.036, 0.016
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, 0.0, H), box_m, uv=[UVQ] * 6)
    # 引き出した中箱
    b.add(box_mm(-W / 2 + 0.004, W / 2 - 0.004, D / 2 - 0.004, D / 2 + 0.014,
                 0.002, H - 0.003), box_m, 12.0)
    for k in range(4):
        x = -0.016 + k * 0.011
        b.add(box_mm(x, x + 0.0028, D / 2 - 0.002, D / 2 + 0.012, H - 0.006, H - 0.0032),
              stick, 30.0)
        b.add(box_mm(x - 0.0006, x + 0.0034, D / 2 + 0.010, D / 2 + 0.014,
                     H - 0.0068, H - 0.0026), head, 40.0)
    emit("matches", [b.build()])


def build_incense_box():
    """線香の箱(紙箱、蓋がずれて線香が見える)。"""
    reset_scene()
    paper = material("IncBox", "incense_box_tex", color=(0.62, 0.42, 0.28), rough=0.9)
    stick = material("IncStick", "wood_dark", color=(0.34, 0.25, 0.18), rough=0.9)
    b = Builder("incense_box")
    W, D, H = 0.075, 0.185, 0.040
    b.add(box_mm(-W / 2, W / 2, -D / 2, D / 2, 0.0, H * 0.62), paper, uv=[UVQ] * 6)
    # 中の線香
    for k in range(6):
        x = -0.026 + k * 0.0105
        b.add(box_mm(x, x + 0.0045, -D / 2 + 0.012, D / 2 - 0.012, H * 0.30, H * 0.56),
              stick, 24.0)
    # ずれた蓋
    b.add(box_mm(-W / 2 - 0.002, W / 2 + 0.002, -D / 2 - 0.002, D / 2 - 0.060,
                 H * 0.58, H), paper, uv=[UVQ] * 6)
    emit("incense_box", [b.build()])


def build_coil_incense():
    """渦巻き線香(皿に載せた状態)。"""
    reset_scene()
    dish = material("CoilDish", "metal_dark", color=(0.18, 0.18, 0.19), rough=0.6, metal=0.4)
    coil = material("CoilStick", "wood_dark", color=(0.36, 0.27, 0.19), rough=0.9)
    ash = material("CoilAsh", "ash", color=(0.60, 0.58, 0.55), rough=1.0)
    b = Builder("coil_incense")
    b.add(cyl(0.085, 0.012, 12, (0, 0, 0.006)), dish, 6.0)
    b.add(cyl(0.088, 0.010, 12, (0, 0, 0.016), r_top=0.092), dish, 6.0)
    b.add(cyl(0.070, 0.004, 12, (0, 0, 0.014)), ash, 8.0)
    # 渦巻き(細い箱をつないで螺旋にする)
    N = 26
    turns = 3.0
    for k in range(N):
        t = k / float(N)
        a = t * turns * 2 * math.pi
        r = 0.020 + t * 0.048
        x, y = math.cos(a) * r, math.sin(a) * r
        seg = 2 * math.pi * r / (N / turns) * 1.35
        v, f = box(max(seg, 0.008), 0.0045, 0.006, (0, 0, 0))
        v = tr(v, rot=('Z', a + math.pi / 2), t=(x, y, 0.021))
        b.add((v, f), coil, 30.0)
    b.add(cyl(0.005, 0.009, 5, (0.068, 0.0, 0.022)),
          material("CoilEmber", None, color=(0.9, 0.35, 0.12),
                   emission=(1.0, 0.34, 0.10), emission_strength=3.0), 30.0)
    emit("coil_incense", [b.build()])


def main():
    build_kettle()
    build_guest_book_stand()
    build_umbrella_stand()
    build_slippers()
    build_wall_clock()
    build_fire_extinguisher()
    build_notice_board()
    build_sake_bottle()
    build_beer_can()
    build_matches()
    build_incense_box()
    build_coil_incense()
    dump_report()


if __name__ == "__main__":
    main()
