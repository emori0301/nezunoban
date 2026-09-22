"""祭祀まわり: coffin / coffin_lid_open / body_face / altar / iei_frame /
incense_stand / candle_stand / flower_stand

blender --background --python tools/blender/build_ritual.py
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from common import (reset_scene, material, Builder, new_object, emit, dump_report,
                    box, box_mm, box_taper, cyl, sphere, prism, tr, frame_quads,
                    build_at)

UV01 = [(0, 0), (1, 0), (1, 1), (0, 1)]


# ---------------------------------------------------------------- coffin

COF_L, COF_W = 1.96, 0.58          # 全長 / 全幅
BODY_H = 0.34                      # 本体の高さ
LID_Z0, LID_Z1 = 0.34, 0.42
WIN_X0, WIN_X1 = 0.48, 0.80        # 小窓の開口(頭側 = +X)
WIN_Y = 0.125


# 蓋の蝶番は足側の長辺(-Y)の上端。ここを原点に Lid を回すと蓋が開く。
LID_HINGE = (0.0, -(COF_W / 2 + 0.01), LID_Z0)


def _coffin(name, lid_slide=0.0):
    """棺を 3 つのノードに分けて返す。

      <name>   本体(台輪・胴・内壁・白布の底)
      `Lid`    蓋。**小窓の位置には実際に穴が開いている**。
               原点は蝶番(足側の長辺の上端)。X 回転で開く
      `Window` 小窓の板。Lid の子。visible=false にすると穴から中が見える
    """
    wood = material("CoffinWood", "white_wood", color=(0.85, 0.80, 0.70), rough=0.8)
    trim = material("CoffinTrim", "wood_dark", color=(0.15, 0.11, 0.08), rough=0.7)
    cloth = material("CoffinCloth", "white_cloth", color=(0.88, 0.87, 0.84), rough=0.95)
    dark = material("CoffinInner", "wood_dark", color=(0.05, 0.04, 0.04), rough=1.0)

    hl, hw = COF_L / 2, COF_W / 2

    # ---------------- 本体(上面は開いている) ----------------
    # 一枚の箱にすると天面が塞がって、小窓の穴から中が見えない。
    # 4 枚の側壁 + 底 で組んで、中を空洞にしておく。
    WALL = 0.055
    b = Builder(name)
    # 台輪(下の一段)
    b.add(box_mm(-hl, hl, -hw, hw, 0.0, 0.045), trim, 2.0)
    # 底(中身が詰まった台。上面に白布を敷く)
    b.add(box_mm(-hl + 0.02, hl - 0.02, -hw + 0.02, hw - 0.02, 0.045, 0.160), wood, 2.0)
    b.add(box_mm(-hl + WALL, hl - WALL, -hw + WALL, hw - WALL, 0.160, 0.185), cloth, 3.0)
    # 側壁 4 枚(外は白木)
    walls = ((-hl, hl, -hw, -hw + WALL),
             (-hl, hl, hw - WALL, hw),
             (-hl, -hl + WALL, -hw + WALL, hw - WALL),
             (hl - WALL, hl, -hw + WALL, hw - WALL))
    for (x0, x1, y0, y1) in walls:
        b.add(box_mm(x0, x1, y0, y1, 0.045, BODY_H), wood, 1.6)
    # 内壁(空洞の内側を暗く)
    inner = ((-hl + WALL, hl - WALL, -hw + WALL, -hw + WALL + 0.008),
             (-hl + WALL, hl - WALL, hw - WALL - 0.008, hw - WALL),
             (-hl + WALL, -hl + WALL + 0.008, -hw + WALL, hw - WALL),
             (hl - WALL - 0.008, hl - WALL, -hw + WALL, hw - WALL))
    for (x0, x1, y0, y1) in inner:
        b.add(box_mm(x0, x1, y0, y1, 0.185, BODY_H), dark, 2.0)
    # 側面の羽目板を表現する帯(上下の見切り)。
    # 一枚の箱にすると中を塞いでしまうので、周囲 4 本の帯にする。
    for zz in (0.09, BODY_H - 0.035):
        for (x0, x1, y0, y1) in ((-hl - 0.005, hl + 0.005, -hw - 0.005, -hw + 0.022),
                                 (-hl - 0.005, hl + 0.005, hw - 0.022, hw + 0.005),
                                 (-hl - 0.005, -hl + 0.022, -hw + 0.022, hw - 0.022),
                                 (hl - 0.022, hl + 0.005, -hw + 0.022, hw - 0.022)):
            b.add(box_mm(x0, x1, y0, y1, zz, zz + 0.018), trim, 3.0)
    # 縦の桟(側面に 4 本ずつ)
    for sx in (-0.62, -0.21, 0.21, 0.62):
        for sy in (-1, 1):
            b.add(box_mm(sx - 0.018, sx + 0.018, sy * hw - 0.006, sy * hw + 0.006,
                         0.105, BODY_H - 0.04), trim, 4.0)
    body_ob = b.build()

    # ---------------- 蓋(小窓の穴あき) ----------------
    # 開口のまわりを 4 枚の板で囲むので、Window を消すと本当に貫通する。
    lid = Builder("Lid")
    lx0, lx1 = -hl - 0.01, hl + 0.01
    ly0, ly1 = -hw - 0.01, hw + 0.01
    wx0, wx1 = WIN_X0, WIN_X1
    wy0, wy1 = -WIN_Y, WIN_Y
    lid.add(box_mm(lx0, wx0, ly0, ly1, LID_Z0, LID_Z1), wood, 1.6)      # 足側
    lid.add(box_mm(wx1, lx1, ly0, ly1, LID_Z0, LID_Z1), wood, 1.6)      # 頭の先
    lid.add(box_mm(wx0, wx1, ly0, wy0, LID_Z0, LID_Z1), wood, 1.6)      # 窓の脇
    lid.add(box_mm(wx0, wx1, wy1, ly1, LID_Z0, LID_Z1), wood, 1.6)
    # 蓋の縁飾り
    lid.add(box_mm(lx0, lx1, ly0, ly0 + 0.022, LID_Z1, LID_Z1 + 0.016), trim, 3.0)
    lid.add(box_mm(lx0, lx1, ly1 - 0.022, ly1, LID_Z1, LID_Z1 + 0.016), trim, 3.0)
    lid.add(box_mm(lx0, lx0 + 0.022, ly0, ly1, LID_Z1, LID_Z1 + 0.016), trim, 3.0)
    lid.add(box_mm(lx1 - 0.022, lx1, ly0, ly1, LID_Z1, LID_Z1 + 0.016), trim, 3.0)
    # 小窓の枠(開口のまわりに一段高い縁)
    fv, ff = frame_quads(WIN_X1 - WIN_X0 + 0.07, WIN_Y * 2 + 0.07,
                         WIN_X1 - WIN_X0 + 0.005, WIN_Y * 2 + 0.005,
                         LID_Z1, LID_Z1 + 0.014,
                         c=((WIN_X0 + WIN_X1) / 2, 0, 0))
    fv = [(v[0], v[2], v[1]) for v in fv]        # frame_quads は XZ 面なので入れ替え
    lid.add((fv, ff), trim, 4.0)
    # 蓋ずれ版は、メッシュは同じで Lid ノードを +X にずらすだけ
    lid_ob = build_at(lid, LID_HINGE,
                      location=(LID_HINGE[0] + lid_slide, LID_HINGE[1], LID_HINGE[2]))

    # ---------------- 小窓の板(Lid の子) ----------------
    w = Builder("Window")
    w.add(box_mm(wx0 - 0.004, wx1 + 0.004, wy0 - 0.004, wy1 + 0.004,
                 LID_Z1 + 0.002, LID_Z1 + 0.018), wood, 3.0)
    w.add(box_mm(wx0 + 0.02, wx1 - 0.02, wy0 + 0.02, wy1 - 0.02,
                 LID_Z1 + 0.018, LID_Z1 + 0.024), trim, 5.0)
    win_ob = build_at(w, ((WIN_X0 + WIN_X1) / 2, 0.0, LID_Z1), parent=lid_ob)

    return [body_ob, lid_ob, win_ob]


def build_coffin():
    reset_scene()
    objs = _coffin("coffin", 0.0)
    emit("coffin", objs)


def build_coffin_lid_open():
    reset_scene()
    objs = _coffin("coffin_lid_open", 0.10)
    emit("coffin_lid_open", objs)


# ---------------------------------------------------------------- body_face

def build_body_face():
    """小窓越しに見える「白布に囲まれた顔」。materialは `Face`。
    systems がテクスチャを body_face_calm/mouth/eyes/turned に差し替える。"""
    reset_scene()
    mat = material("Face", "body_face_calm", color=(0.85, 0.83, 0.80), rough=0.95)

    W, D = 0.40, 0.30
    N = 5
    verts = []
    uvs_grid = []
    for i in range(N):
        for j in range(N):
            u = i / (N - 1.0)
            v = j / (N - 1.0)
            x = (u - 0.5) * W
            y = (v - 0.5) * D
            # 顔・布のふくらみ
            bump = math.cos((u - 0.5) * math.pi) * math.cos((v - 0.5) * math.pi)
            z = bump * 0.055
            verts.append((x, y, z))
            # 頭頂が +X(棺の頭側 = 小窓のある側)を向くように貼る
            uvs_grid.append((1.0 - v, u))
    faces = []
    fuv = []
    for i in range(N - 1):
        for j in range(N - 1):
            a = i * N + j
            bq = (i + 1) * N + j
            c = (i + 1) * N + j + 1
            d = i * N + j + 1
            faces.append((a, bq, c, d))
            fuv.append([uvs_grid[a], uvs_grid[bq], uvs_grid[c], uvs_grid[d]])

    b = Builder("body_face")
    b.add((verts, faces), mat, uv=fuv)
    ob = b.build()
    emit("body_face", [ob])


# ---------------------------------------------------------------- altar

def build_altar():
    """三段の白布祭壇 + 金襴の垂れ + 供物台。"""
    reset_scene()
    cloth = material("AltarCloth", "white_cloth", color=(0.88, 0.87, 0.84), rough=0.95)
    bro = material("AltarBrocade", "brocade", color=(0.45, 0.10, 0.10), rough=0.8)
    wood = material("AltarWood", "wood_dark", color=(0.12, 0.09, 0.07), rough=0.7)
    gold = material("AltarGold", "gold", color=(0.70, 0.55, 0.20), rough=0.45, metal=0.7)

    b = Builder("altar")
    tiers = [
        # (幅, 奥行, 上端z, 前面y)
        (2.00, 0.42, 0.40, -0.55),
        (1.74, 0.34, 0.68, -0.13),
        (1.46, 0.30, 0.94, 0.21),
    ]
    y_back = 0.51
    for i, (w, d, ztop, yfront) in enumerate(tiers):
        zbot = 0.0 if i == 0 else tiers[i - 1][2]
        b.add(box_mm(-w / 2, w / 2, yfront, yfront + d, zbot, ztop), cloth, 3.2)
        # 天板の見切り
        b.add(box_mm(-w / 2 - 0.012, w / 2 + 0.012, yfront - 0.012, yfront + d,
                     ztop - 0.020, ztop), cloth, 3.6)
        # 金襴の垂れ(前面の上部)
        dh = 0.16
        b.add(box_mm(-w / 2 - 0.014, w / 2 + 0.014, yfront - 0.016, yfront - 0.004,
                     ztop - dh, ztop - 0.004), bro, 1.4)
        # 垂れの下端の房
        for k in range(7):
            x = -w / 2 + (k + 0.5) * w / 7.0
            b.add(box_mm(x - 0.016, x + 0.016, yfront - 0.020, yfront - 0.008,
                         ztop - dh - 0.05, ztop - dh), gold, 4.0)

    # 背面の壁(白木の板 + 金の縁)
    b.add(box_mm(-1.00, 1.00, y_back, y_back + 0.05, 0.94, 1.66), cloth, 3.2)
    b.add(box_mm(-1.02, 1.02, y_back - 0.012, y_back, 1.66, 1.70), gold, 4.0)
    b.add(box_mm(-1.02, -0.98, y_back - 0.012, y_back, 0.94, 1.70), gold, 4.0)
    b.add(box_mm(0.98, 1.02, y_back - 0.012, y_back, 0.94, 1.70), gold, 4.0)
    # 背面の金襴の壁掛け
    b.add(box_mm(-0.70, 0.70, y_back - 0.018, y_back - 0.006, 1.02, 1.58), bro, 1.2)

    # 供物台(前に出した小さな台)
    b.add(box_mm(-0.42, 0.42, -0.90, -0.58, 0.0, 0.36), cloth, 3.4)
    b.add(box_mm(-0.44, 0.44, -0.92, -0.56, 0.36, 0.385), wood, 2.5)
    # 供物(果物の山と三方)
    b.add(box_mm(-0.30, -0.06, -0.84, -0.64, 0.385, 0.44), wood, 4.0)
    for (fx, fy, fz, r) in ((-0.24, -0.78, 0.47, 0.045), (-0.14, -0.74, 0.47, 0.045),
                            (-0.19, -0.76, 0.525, 0.045)):
        b.add(sphere(r, 6, 4, (fx, fy, fz)), gold, 6.0)
    b.add(box_mm(0.08, 0.32, -0.84, -0.64, 0.385, 0.44), wood, 4.0)
    b.add(box_mm(0.10, 0.30, -0.82, -0.66, 0.44, 0.50), cloth, 6.0)

    ob = b.build()
    emit("altar", [ob])


# ---------------------------------------------------------------- iei_frame

def build_iei_frame():
    """遺影: 黒縁の額 + 黒リボン + 写真(material `Photo`)。"""
    reset_scene()
    blk = material("FrameBlack", "wood_dark", color=(0.06, 0.05, 0.05), rough=0.4)
    photo = material("Photo", "iei_photo", color=(0.8, 0.8, 0.8), rough=0.55)
    rib = material("Ribbon", "suit_black", color=(0.05, 0.05, 0.055), rough=0.9)
    glass = material("FrameGlass", "glass_frost", color=(0.85, 0.88, 0.9),
                     rough=0.12, alpha=0.20)

    W, H = 0.34, 0.44
    T = 0.035          # 額縁の幅
    Z0 = 0.045         # 下のスタンドの分だけ浮かす

    b = Builder("iei_frame")
    # 縁(4 本)
    b.add(box_mm(-W / 2, W / 2, -0.016, 0.016, Z0 + H - T, Z0 + H), blk, 6.0)
    b.add(box_mm(-W / 2, W / 2, -0.016, 0.016, Z0, Z0 + T), blk, 6.0)
    b.add(box_mm(-W / 2, -W / 2 + T, -0.016, 0.016, Z0 + T, Z0 + H - T), blk, 6.0)
    b.add(box_mm(W / 2 - T, W / 2, -0.016, 0.016, Z0 + T, Z0 + H - T), blk, 6.0)
    # 写真(前面に貼る 1 枚。明示 UV)
    px0, px1 = -W / 2 + T, W / 2 - T
    pz0, pz1 = Z0 + T, Z0 + H - T
    b.add(([(px0, -0.017, pz0), (px1, -0.017, pz0), (px1, -0.017, pz1), (px0, -0.017, pz1)],
           [(0, 1, 2, 3)]), photo, uv=[[(1, 0), (0, 0), (0, 1), (1, 1)]])
    # 背板
    b.add(box_mm(px0, px1, -0.010, 0.016, pz0, pz1), blk, 6.0)
    # ガラス
    b.add(box_mm(px0, px1, -0.020, -0.018, pz0, pz1), glass, 6.0)
    # スタンド(下の台と背面の支え)
    b.add(box_mm(-W / 2 + 0.03, W / 2 - 0.03, -0.055, 0.075, 0.0, Z0), blk, 5.0)
    b.add(([(0.0, 0.016, Z0 + 0.02), (0.0, 0.10, Z0 + 0.005),
            (0.0, 0.10, Z0 - 0.02), (0.0, 0.016, Z0 - 0.02)], [(0, 1, 2, 3)]), blk, 5.0)

    # 黒リボン(左上から右下へ掛ける 2 本 + 蝶結び)
    b.add(box_mm(-W / 2 - 0.012, -W / 2 + 0.10, -0.022, -0.018, Z0 + H - 0.10, Z0 + H + 0.012),
          rib, 6.0)
    b.add(box_mm(W / 2 - 0.10, W / 2 + 0.012, -0.022, -0.018, Z0 + H - 0.10, Z0 + H + 0.012),
          rib, 6.0)
    b.add(box_mm(-0.05, 0.05, -0.024, -0.019, Z0 + H + 0.012, Z0 + H + 0.052), rib, 8.0)
    for sx in (-1, 1):
        b.add(box_mm(sx * 0.03, sx * 0.10, -0.024, -0.019, Z0 + H + 0.020, Z0 + H + 0.048),
              rib, 8.0)

    ob = b.build()
    emit("iei_frame", [ob])


# ---------------------------------------------------------------- incense

def build_incense_stand():
    """香炉(灰入り)。線香が 3 本立っている。"""
    reset_scene()
    br = material("Bronze", "gold", color=(0.40, 0.31, 0.16), rough=0.40, metal=0.70)
    ash = material("Ash", "ash", color=(0.62, 0.60, 0.57), rough=1.0)
    stick = material("IncenseStick", "wood_dark", color=(0.30, 0.22, 0.16), rough=0.9)
    wood = material("IncenseTray", "wood_dark", color=(0.12, 0.09, 0.07), rough=0.6)

    b = Builder("incense_stand")
    # 前机(小さな木の台)
    b.add(box_mm(-0.19, 0.19, -0.15, 0.15, 0.0, 0.018), wood, 4.0)
    for (sx, sy) in ((-0.16, -0.12), (0.16, -0.12), (-0.16, 0.12), (0.16, 0.12)):
        b.add(box_mm(sx - 0.014, sx + 0.014, sy - 0.014, sy + 0.014, 0.018, 0.05), wood, 8.0)
    b.add(box_mm(-0.20, 0.20, -0.16, 0.16, 0.05, 0.068), wood, 4.0)

    z0 = 0.068
    # 香炉の胴(三足の鉢)
    b.add(cyl(0.085, 0.075, 10, (0, 0, z0 + 0.038), r_top=0.105), br, 5.0)
    b.add(cyl(0.108, 0.016, 10, (0, 0, z0 + 0.082)), br, 5.0)          # 口の縁
    for k in range(3):
        a = math.pi * 2 * k / 3 + math.pi / 6
        b.add(cyl(0.014, 0.03, 5, (math.cos(a) * 0.062, math.sin(a) * 0.062, z0 + 0.015)),
              br, 10.0)
    # 灰
    b.add(cyl(0.094, 0.012, 10, (0, 0, z0 + 0.074)), ash, 6.0)
    # 線香(3 本、少し傾く)
    ember = material("Ember", None, color=(0.9, 0.35, 0.12),
                     emission=(1.0, 0.36, 0.10), emission_strength=3.0)
    for (sx, sy, tilt) in ((-0.022, 0.012, 0.06), (0.004, -0.016, -0.04), (0.024, 0.018, 0.02)):
        v, f = cyl(0.006, 0.24, 4, (0, 0, 0.12))
        v = tr(v, rot=('Y', tilt), t=(sx, sy, z0 + 0.074))
        b.add((v, f), stick, 12.0)
        ev, ef = cyl(0.0068, 0.014, 4, (0, 0, 0.247))
        ev = tr(ev, rot=('Y', tilt), t=(sx, sy, z0 + 0.074))
        b.add((ev, ef), ember, 20.0)

    ob = b.build()
    emit("incense_stand", [ob])


def build_candle_stand():
    """燭台(鶴亀ではなく簡素な真鍮の燭台 + 白ロウソク)。"""
    reset_scene()
    brass = material("Brass", "gold", color=(0.62, 0.48, 0.18), rough=0.35, metal=0.75)
    wax = material("Wax", "white_cloth", color=(0.92, 0.90, 0.84), rough=0.55)
    flame = material("Flame", None, color=(1.0, 0.72, 0.30),
                     emission=(1.0, 0.62, 0.22), emission_strength=4.0, rough=1.0)

    b = Builder("candle_stand")
    # 蓮弁の台座
    b.add(cyl(0.075, 0.018, 10, (0, 0, 0.009)), brass, 6.0)
    b.add(cyl(0.062, 0.030, 10, (0, 0, 0.033), r_top=0.040), brass, 6.0)
    for k in range(8):
        a = math.pi * 2 * k / 8
        v, f = box(0.030, 0.016, 0.012, (0.056, 0, 0.024))
        v = tr(v, rot=('Z', a))
        b.add((v, f), brass, 14.0)
    # 柱
    b.add(cyl(0.016, 0.20, 8, (0, 0, 0.148)), brass, 8.0)
    b.add(cyl(0.026, 0.014, 8, (0, 0, 0.118)), brass, 10.0)
    # 受け皿
    b.add(cyl(0.046, 0.012, 10, (0, 0, 0.254), r_top=0.056), brass, 8.0)
    b.add(cyl(0.010, 0.030, 6, (0, 0, 0.275)), brass, 12.0)            # 針
    # ロウソク
    b.add(cyl(0.020, 0.145, 8, (0, 0, 0.332), r_top=0.018), wax, 8.0)
    b.add(cyl(0.018, 0.008, 8, (0, 0, 0.408), r_top=0.012), wax, 12.0)
    # 芯と炎
    b.add(cyl(0.0022, 0.012, 4, (0, 0, 0.418)), material("Wick", None, color=(0.1, 0.09, 0.08)), 20.0)
    b.add(sphere(0.013, 6, 4, (0, 0, 0.432), squash=2.0), flame, 12.0)

    ob = b.build()
    emit("candle_stand", [ob])


def build_flower_stand():
    """供花スタンド(白菊の扇形 + 三脚)。"""
    reset_scene()
    metal = material("StandMetal", "metal_dark", color=(0.18, 0.18, 0.19), rough=0.5, metal=0.4)
    fl = material("Flower", "flower_white", color=(0.88, 0.87, 0.82), rough=0.9)
    leaf = material("Leaf", "leaves_dark", color=(0.10, 0.16, 0.10), rough=0.95)
    wood = material("StandWood", "wood_dark", color=(0.14, 0.10, 0.08), rough=0.7)

    b = Builder("flower_stand")
    # 三脚(下が開く)
    for k in range(3):
        a = math.pi * 2 * k / 3 + math.pi / 2
        dx, dy = math.cos(a) * 0.30, math.sin(a) * 0.30
        v, f = cyl(0.016, 0.86, 4, (0, 0, 0.43))
        v = [(x + dx * (0.5 - z / 0.86), y + dy * (0.5 - z / 0.86), z) for (x, y, z) in v]
        b.add((v, f), metal, 8.0)
    b.add(cyl(0.05, 0.06, 6, (0, 0, 0.87)), metal, 8.0)
    # 花を載せる受け(木の桶)
    b.add(cyl(0.16, 0.16, 8, (0, 0, 0.97), r_top=0.22), wood, 4.0)
    b.add(cyl(0.225, 0.020, 8, (0, 0, 1.055)), wood, 4.0)

    # --- 白菊の扇(XZ 面に楕円状。前(-Y)に少しふくらむ) ---
    CX, CZ = 0.0, 1.38
    RX, RZ = 0.44, 0.36
    import random
    rnd = random.Random(7)
    # 背板(葉)
    leafpoly = [(CX + math.cos(t * math.pi / 6) * (RX + 0.06),
                 CZ + math.sin(t * math.pi / 6) * (RZ + 0.06)) for t in range(12)]
    lv, lf = prism(leafpoly, 0.02, 0.06)
    lv = [(x, z2, y) for (x, y, z2) in lv]       # XY押し出し → XZ 面へ
    b.add((lv, lf), leaf, 3.0)

    rings = [(0.0, 1), (0.42, 7), (0.78, 11)]
    for (rr, cnt) in rings:
        for k in range(cnt):
            a = math.pi * 2 * k / cnt + rr * 2.0
            x = CX + math.cos(a) * RX * rr
            z = CZ + math.sin(a) * RZ * rr
            y = -0.10 + rr * 0.09 + rnd.uniform(-0.015, 0.015)
            rad = 0.062 - rr * 0.014 + rnd.uniform(-0.006, 0.006)
            b.add(sphere(rad, 5, 3, (x, y, z), squash=0.72), fl, 9.0)
    # 隙間の葉
    for k in range(9):
        a = math.pi * 2 * k / 9 + 0.3
        x = CX + math.cos(a) * RX * 0.95
        z = CZ + math.sin(a) * RZ * 0.95
        v, f = box(0.13, 0.02, 0.05, (0, 0, 0))
        v = tr(v, rot=(0, -a, 0), t=(x, 0.0, z))
        b.add((v, f), leaf, 8.0)
    # 桶から花束へ伸びる茎
    for k in range(5):
        x = -0.10 + k * 0.05
        b.add(cyl(0.008, 0.26, 4, (x, 0.0, 1.12)), leaf, 14.0)

    ob = b.build()
    emit("flower_stand", [ob])


def main():
    build_coffin()
    build_coffin_lid_open()
    build_body_face()
    build_altar()
    build_iei_frame()
    build_incense_stand()
    build_candle_stand()
    build_flower_stand()
    dump_report()


if __name__ == "__main__":
    main()
