"""小物: kettle guest_book_stand umbrella_stand slippers wall_clock radio body_bag
fire_extinguisher notice_board sake_bottle beer_can matches incense_box
coil_incense hanging_robe

blender --background --python tools/blender/build_props.py
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from common import (reset_scene, material, Builder, emit, dump_report,
                    box, box_mm, box_taper, cyl, sphere, prism, tr, frame_quads,
                    make_armature, chain_weights, loft_rings, ring, Anim,
                    set_scene_frames, build_at)

R = math.radians
FPS = 30

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


# ---------------------------------------------------------------- 湯灌室

# ハンガーのフックの先端が z = 2.00(原点は床)
HOOK_Z = 2.00
ROBE_TOP = 1.84      # 肩のライン
ROBE_BOT = 0.58      # 裾

ROBE_BONES = [
    ("Hook",       (0.00, 0.00, 1.86), (0.00, 0.00, HOOK_Z), None),
    ("RobeTop",    (0.00, 0.00, ROBE_TOP), (0.00, 0.00, 1.30), "Hook"),
    ("RobeBottom", (0.00, 0.00, 1.30), (0.00, 0.00, ROBE_BOT), "RobeTop"),
]


def build_hanging_robe():
    """湯灌室に吊るした白装束(経帷子)。
    原点は床。ハンガーのフックの先端が +Z 2.00。
    アニメ `sway`(4 秒ループ)と `drop`(1.5 秒、1 回)。"""
    reset_scene()
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0

    cloth = material("RobeCloth", "white_cloth", color=(0.87, 0.86, 0.83), rough=0.95)
    wire = material("HangerWire", "steel", color=(0.56, 0.57, 0.58), rough=0.45, metal=0.8)

    b = Builder("hanging_robe")

    # --- ハンガー(Hook ボーンに固定。落ちても残る) ---
    hanger_idx = []
    h0 = b.count()
    b.add(cyl(0.006, 0.10, 6, (0, 0, 1.905)), wire, 30.0)               # 縦の針金
    for k in range(5):                                                   # フックの曲がり
        a = math.pi * (0.15 + 0.70 * k / 4.0)
        b.add(cyl(0.005, 0.030, 5,
                  (math.cos(a) * 0.030, 0, 1.962 + math.sin(a) * 0.032)), wire, 40.0)
    for sx in (-1, 1):                                                   # 肩の斜材
        v, f = box(0.200, 0.014, 0.014, (0, 0, 0))
        v = tr(v, rot=(0, 0.28, 0), t=(sx * 0.098, 0, 1.818))
        b.add((v, f), wire, 16.0)
    b.add(box_mm(-0.192, 0.192, -0.007, 0.007, 1.760, 1.774), wire, 12.0)  # 下の横棒
    hanger_idx = list(range(h0, b.count()))

    # --- 経帷子(白装束)。胴は 1 本のロフトで裂けないように ---
    body = [
        ring(0.0, 0.0, ROBE_TOP + 0.015, 0.212, 0.072, axis='Z'),
        ring(0.0, 0.0, 1.700, 0.226, 0.090, axis='Z'),
        ring(0.0, 0.0, 1.450, 0.222, 0.096, axis='Z'),
        ring(0.0, 0.0, 1.150, 0.216, 0.090, axis='Z'),
        ring(0.0, 0.0, 0.850, 0.210, 0.084, axis='Z'),
        ring(0.0, 0.0, ROBE_BOT, 0.206, 0.078, axis='Z'),
    ]
    b.add(loft_rings(body), cloth, 3.8)
    # 袖(着物なので四角く大きい)
    for sx in (-1, 1):
        b.add(box_taper(0.230, 0.100, 0.215, 0.092, 0.135,
                        (sx * 0.318, 0.0, 1.790)), cloth, 4.6)
        b.add(box_mm(sx * 0.300 - 0.072 if sx > 0 else sx * 0.300 - 0.072,
                     sx * 0.300 + 0.072, -0.048, 0.048, 1.380, 1.722), cloth, 4.6)
    # 襟(前で V にあわせる)
    for sx in (-1, 1):
        v, f = box(0.052, 0.022, 0.300, (0, 0, 0))
        v = tr(v, rot=(0, sx * 0.30, 0), t=(sx * 0.052, -0.088, 1.700))
        b.add((v, f), cloth, 8.0)
    # 紐
    b.add(box_mm(-0.216, 0.216, -0.100, -0.082, 1.268, 1.306), cloth, 6.0)
    b.add(box_mm(-0.030, 0.030, -0.108, -0.086, 1.150, 1.290), cloth, 10.0)

    mesh = b.build()

    ao = make_armature("hanging_robe", ROBE_BONES, scale=1.0)
    # 胴と袖は z に沿って滑らかに、ハンガーだけインデックスで固定
    chain_weights(mesh, ao, [("RobeBottom", 0.95), ("RobeTop", 1.65)],
                  lambda c: c.z, rigid_idx={"Hook": hanger_idx})

    set_scene_frames(121)

    # --- sway: ゆっくり揺れる(4.0 秒ちょうどでループ) ---
    a = Anim(ao, "sway", 121)
    N = 12
    for k in range(N + 1):
        f = 1 + k * 120.0 / N
        t = k / float(N)
        w = 2 * math.pi * t
        a.keyw_mul(f, "RobeTop", [('Y', R(2.2) * math.sin(w)),
                                  ('X', R(1.4) * math.sin(w + 0.7)),
                                  ('Z', R(1.2) * math.sin(w * 2))])
        a.keyw_mul(f, "RobeBottom", [('Y', R(3.6) * math.sin(w - 0.55)),
                                     ('X', R(2.2) * math.sin(w + 0.2)),
                                     ('Z', R(1.8) * math.sin(w * 2 - 0.9))])
    a.finish()

    # --- drop: 1.5 秒で床に落ちる(1 回) ---
    set_scene_frames(46)
    a = Anim(ao, "drop", 46)
    N = 12
    for k in range(N + 1):
        f = 1 + k * 45.0 / N
        t = k / float(N)
        fall = min(max((t - 0.08) / 0.62, 0.0), 1.0)
        settle = min(max((t - 0.62) / 0.38, 0.0), 1.0)
        se = settle * settle * (3 - 2 * settle)
        # 落下は加速する
        a.keyw_loc(f, "RobeTop", (0.055 * fall, -0.10 * fall, -1.74 * (fall ** 2)))
        a.keyw_mul(f, "RobeTop", [('X', R(-88) * (fall ** 1.4)),
                                  ('Y', R(11) * fall),
                                  ('Z', R(-7) * fall)])
        a.keyw_mul(f, "RobeBottom", [('X', R(34) * se),
                                     ('Y', R(-14) * se + R(5) * fall)])
    a.finish()

    set_scene_frames(121)
    emit("hanging_robe", [ao, mesh], animations=True)



def build_radio():
    """古いトランジスタラジオ。0.25 x 0.15 x 0.08、正面は -Y。
    選局つまみは別ノード `Dial`(原点 = つまみの回転軸、軸は Blender +Y)。
    Godot では `Dial` のローカル Z 回転で回る。"""
    reset_scene()
    case = material("RadioCase", "plastic_beige", color=(0.62, 0.575, 0.48), rough=0.72)
    dk = material("RadioDark", "metal_dark", color=(0.16, 0.16, 0.17), rough=0.55, metal=0.4)
    mesh = material("RadioMesh", "steel", color=(0.26, 0.26, 0.27), rough=0.60, metal=0.6)
    scale = material("RadioScale", "paper_yellow", color=(0.80, 0.76, 0.60), rough=0.85)

    W, D, H = 0.25, 0.08, 0.150
    FY = -D / 2                                  # 正面(-Y)
    b = Builder("radio")
    # 筐体と足
    b.add(box_mm(-W / 2, W / 2, FY, D / 2, 0.009, H), case, 5.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(box_mm(sx * 0.100 - 0.010, sx * 0.100 + 0.010,
                         sy * 0.028 - 0.008, sy * 0.028 + 0.008, 0.0, 0.010), dk, 16.0)
    # スピーカー網(左)+ 枠
    b.add(box_mm(-0.116, 0.004, FY - 0.003, FY, 0.024, 0.130), dk, 7.0)
    b.add(box_mm(-0.110, -0.002, FY - 0.004, FY - 0.002, 0.030, 0.124), mesh, 9.0)
    for k in range(9):
        z0 = 0.032 + k * 0.0105
        b.add(box_mm(-0.108, -0.004, FY - 0.0052, FY - 0.0038, z0, z0 + 0.0052),
              dk, 18.0)
    # 選局の目盛り窓(右上)
    b.add(box_mm(0.020, 0.118, FY - 0.003, FY, 0.092, 0.134), dk, 8.0)
    b.add(box_mm(0.024, 0.114, FY - 0.0042, FY - 0.0032, 0.096, 0.130), scale, 1.0,
          uv=[UVQ] * 6)
    b.add(box_mm(0.064, 0.067, FY - 0.0050, FY - 0.0044, 0.096, 0.130), dk, 20.0)
    # 音量つまみ(右側面)
    b.add(cyl(0.017, 0.014, 8, (W / 2 + 0.005, 0.004, 0.045), axis='X'), dk, 12.0)
    # 収納したロッドアンテナ(天面の奥)
    b.add(cyl(0.0035, 0.21, 6, (0.0, 0.031, 0.1455), axis='X'),
          material("RadioAnt", "metal_gray", color=(0.45, 0.45, 0.47),
                   rough=0.35, metal=0.85), 14.0)
    body = b.build()

    # 選局つまみ: 原点をつまみの軸に置いた別ノード
    d = Builder("Dial")
    KX, KZ = 0.069, 0.046
    d.add(cyl(0.026, 0.016, 12, (KX, FY - 0.008, KZ), axis='Y'), dk, 10.0)
    d.add(cyl(0.010, 0.019, 8, (KX, FY - 0.009, KZ), axis='Y'), mesh, 16.0)
    for k in range(10):                          # 滑り止めの刻み
        a = 2 * math.pi * k / 10.0
        d.add(box_mm(KX + math.cos(a) * 0.025 - 0.002,
                     KX + math.cos(a) * 0.025 + 0.002,
                     FY - 0.016, FY - 0.001,
                     KZ + math.sin(a) * 0.025 - 0.002,
                     KZ + math.sin(a) * 0.025 + 0.002), mesh, 24.0)
    dial = build_at(d, (KX, FY, KZ), parent=body)
    emit("radio", [body, dial])


def _sack_ring(x, cz, ry, rz, n=14, wob=0.0, seed=0, flat=0.0):
    """袋の断面。wob で周方向に皺を付け、flat で上面を潰す。"""
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        w = 1.0 + wob * math.sin(a * 3.0 + seed * 1.7) \
                + wob * 0.6 * math.sin(a * 5.0 - seed * 2.3)
        cy = math.cos(a) * ry * w
        czz = math.sin(a) * rz * w
        if czz > 0:
            czz *= (1.0 - flat)
        pts.append((x, cy, cz + czz))
    return pts


def build_body_bag():
    """黒いビニールの遺体袋。0.6 x 0.25 x 0.4、口を縛って左(-X)に寄せる。
    白い伝票は別マテリアル `Tag`。"""
    reset_scene()
    vinyl = material("BagVinyl", "car_black", color=(0.060, 0.060, 0.065),
                     rough=0.58)
    cord = material("BagCord", "white_cloth", color=(0.66, 0.64, 0.58), rough=0.85)
    tag = material("Tag", "notice_paper", color=(0.84, 0.82, 0.76), rough=0.88)

    # (x, 中心 z, 横半径, 縦半径, 皺, 上面の潰し)
    rows = [(-0.300, 0.258, 0.013, 0.013, 0.00, 0.00),
            (-0.276, 0.244, 0.020, 0.020, 0.05, 0.00),
            (-0.256, 0.228, 0.025, 0.025, 0.05, 0.00),   # ここを紐で縛る
            (-0.240, 0.206, 0.048, 0.052, 0.26, 0.00),   # 縛りの下で一気に広がる
            (-0.206, 0.158, 0.086, 0.108, 0.20, 0.06),
            (-0.140, 0.166, 0.112, 0.160, 0.12, 0.10),
            (-0.050, 0.190, 0.125, 0.186, 0.08, 0.12),   # 胸のあたり
            ( 0.046, 0.184, 0.123, 0.180, 0.07, 0.14),
            ( 0.132, 0.162, 0.112, 0.158, 0.08, 0.12),   # 腰
            ( 0.206, 0.130, 0.092, 0.126, 0.10, 0.08),
            ( 0.262, 0.086, 0.062, 0.082, 0.12, 0.04),
            ( 0.300, 0.038, 0.028, 0.034, 0.08, 0.00)]
    b = Builder("body_bag")
    b.add(loft_rings([_sack_ring(x, cz, ry, rz, wob=w, seed=i, flat=fl)
                      for i, (x, cz, ry, rz, w, fl) in enumerate(rows)]),
          vinyl, 3.0, smooth=True)
    # 縛った紐(2 周)
    for k in range(2):
        b.add(loft_rings([_sack_ring(-0.260 + k * 0.011, 0.228, 0.029, 0.029),
                          _sack_ring(-0.253 + k * 0.011, 0.228, 0.029, 0.029)],
                         cap=False), cord, 8.0)
    # 紐の余り
    b.add(box_mm(-0.266, -0.238, -0.006, 0.006, 0.248, 0.256), cord, 12.0)
    # 白い伝票(上面寄りの +Y 側に貼る。上から見て読める角度)
    q = [(-0.042, -0.134, 0.196), (0.072, -0.134, 0.196),
         (0.072, -0.134, 0.270), (-0.042, -0.134, 0.270)]
    b.add((q, [(0, 1, 2, 3)]), tag, 1.0, uv=[UVQ])
    b.add((list(reversed(q)), [(0, 1, 2, 3)]), tag, 1.0, uv=[UVQ])
    emit("body_bag", [b.build()])


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
    build_hanging_robe()
    build_radio()
    build_body_bag()
    dump_report()


if __name__ == "__main__":
    main()
