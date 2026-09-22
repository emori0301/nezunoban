"""キャラクター: cat kasha npc_boss npc_son npc_granddaughter body_risen

blender --background --python tools/blender/build_chars.py

向き: Blender の -Y が正面。export_yup=True なので Godot では -Z が正面になる
(Godot のキャラクタの既定の前方と一致する)。
アニメは bpy.data.actions に作り、export_animation_mode='ACTIONS' で glb に入れる。
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Vector, Quaternion
from common import (reset_scene, material, Builder, emit, dump_report,
                    box, box_mm, box_taper, cyl, sphere, tr,
                    make_armature, bind, auto_groups, chain_weights, loft_rings,
                    ring, tube, add_chain_weights, add_rigid_weights, bind_weights,
                    Anim, BONES, set_scene_frames)

R = math.radians
FPS = 30

FACE_UV = [(0.50, 0.0), (0.0, 0.0), (0.0, 1.0), (0.50, 1.0)]
HAIR_UV = [(0.56, 0.0), (1.0, 0.0), (1.0, 1.0), (0.56, 1.0)]
HEAD_UV = [HAIR_UV, HAIR_UV, FACE_UV, HAIR_UV, HAIR_UV, HAIR_UV]


def setup_fps():
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.render.fps_base = 1.0


# ================================================================ 人物

# 頭の正面だけに顔テクスチャを貼る(128x128 の全面が顔)
FACE_QUAD_UV = [[(1.0, 0.0), (0.0, 0.0), (0.0, 1.0), (1.0, 1.0)]]

# 頭。箱にすると「積み木」に見えるので、断面を並べた丸い形にして、
# 顔テクスチャはその前面に沿わせた格子に貼る。
# (z, cy, rx, ry, v)
HEAD_ROWS = [
    (1.772, -0.004, 0.058, 0.062),
    (1.752, -0.004, 0.086, 0.094),
    (1.712, -0.004, 0.097, 0.105),
    (1.660, -0.004, 0.095, 0.103),
    (1.610, -0.003, 0.086, 0.093),
    (1.570, -0.001, 0.069, 0.075),
    (1.546, 0.003, 0.049, 0.055),
]
FACE_Z0 = 1.556                          # 顎
FACE_TOP = 1.706                         # 生え際


def _head_at(z):
    """その高さでの頭の (cy, rx, ry) を線形補間で返す。"""
    rows = HEAD_ROWS
    if z >= rows[0][0]:
        return rows[0][1:]
    if z <= rows[-1][0]:
        return rows[-1][1:]
    for i in range(len(rows) - 1):
        z0, z1 = rows[i][0], rows[i + 1][0]
        if z1 <= z <= z0:
            t = (z0 - z) / (z0 - z1)
            return tuple(rows[i][k + 1] + t * (rows[i + 1][k + 1] - rows[i][k + 1])
                         for k in range(3))
    return rows[-1][1:]


def _face_grid(s, nc=5, nr=6, out=0.011):
    """顔テクスチャを頭の前面に沿わせた格子。(verts, faces, uvs) を返す。
    平らな板に貼るとシールに見えるので、頭の丸みに乗せる。"""
    verts, uvs_g = [], []
    for i in range(nr):
        z = FACE_TOP - (FACE_TOP - FACE_Z0) * i / (nr - 1.0)
        cy, rx, ry = _head_at(z)
        v = 1.0 - i / (nr - 1.0)
        for j in range(nc):
            t = j / (nc - 1.0)
            x = (t - 0.5) * 2.0 * rx * 0.88
            k = min(1.0, abs(x) / max(rx, 1e-6))
            y = cy - (ry + out) * math.sqrt(max(0.0, 1.0 - k * k))
            verts.append((x * s, y * s, z * s))
            uvs_g.append((1.0 - t, v))
    faces, uvs = [], []
    for i in range(nr - 1):
        for j in range(nc - 1):
            a = i * nc + j
            b2 = i * nc + j + 1
            c = (i + 1) * nc + j + 1
            d = (i + 1) * nc + j
            faces.append((a, b2, c, d))
            uvs.append([uvs_g[a], uvs_g[b2], uvs_g[c], uvs_g[d]])
    return verts, faces, uvs


def _tube_sections(rows, s):
    """[(z, cx, cy, rx, ry, v), ...] を倍率 s でスケールして tube() へ渡す形にする。
    tube() は (cx, cy, cz, rx, ry, v) の順で、z の降順に並べる。"""
    return [(cx * s, cy * s, z * s, rx * s, ry * s, v)
            for (z, cx, cy, rx, ry, v) in rows]


def human_mesh(name, spec):
    """人物のメッシュ。胴・腕・脚は断面を並べた筒(tube)で作り、
    スムーズシェーディングにして「積み木」に見えないようにする。

    spec:
      s        全体の倍率(1.0 = 身長 1.77m)
      torso    胴のマテリアル(正面中央に襟/ネクタイ/ファスナーを描いたテクスチャ)
      skin     肌 / face 顔 / hair 髪 / shoe 靴
      belly    腹の出っ張り 0..1
      bust     胸のふくらみ 0..1
      shoulder 肩幅の倍率
      hair_*   髪の形(後退具合・長さ)
    """
    s = spec["s"]
    torso_m = spec["torso"]
    skin = spec["skin"]
    face = spec["face"]
    hair_m = spec["hair"]
    shoe_m = spec["shoe"]
    b = spec.get("belly", 0.0)
    bust = spec.get("bust", 0.0)
    shw = spec.get("shoulder", 1.0)

    bld = Builder(name)
    idx = {}

    def mark(key, fn):
        i0 = bld.count()
        fn()
        idx.setdefault(key, []).extend(range(i0, bld.count()))

    # ---------------- 胴(n=14 の筒) ----------------
    # (z, cx, cy, rx, ry, v)  v=1 が肩、v=0 が腰
    torso_rows = [
        (1.480, 0, 0.000, 0.132 * shw, 0.088, 1.00),
        (1.440, 0, 0.000, 0.192 * shw, 0.106, 0.95),
        (1.375, 0, 0.000, 0.196 * shw, 0.114 + bust * 0.010, 0.86),
        (1.290, 0, -b * 0.010 - bust * 0.014, 0.178, 0.117 + b * 0.022 + bust * 0.026, 0.74),
        (1.195, 0, -b * 0.022, 0.163, 0.111 + b * 0.052, 0.62),
        (1.100, 0, -b * 0.030, 0.150 + b * 0.034 - bust * 0.008,
         0.101 + b * 0.076, 0.50),
        (1.010, 0, -b * 0.018, 0.164 + b * 0.020, 0.106 + b * 0.046, 0.36),
        (0.935, 0, 0.000, 0.178, 0.112, 0.22),
        (0.880, 0, 0.000, 0.170, 0.105, 0.10),
        (0.840, 0, 0.000, 0.152, 0.096, 0.00),
    ]
    mark("torso", lambda: bld.add(
        tube(_tube_sections(torso_rows, s), n=14), torso_m, smooth=True))

    # ---------------- 首 ----------------
    neck_rows = [
        (1.575, 0, -0.004, 0.050, 0.047, 1.0),
        (1.500, 0, -0.004, 0.054, 0.051, 0.5),
        (1.425, 0, -0.002, 0.062, 0.058, 0.0),
    ]
    mark("head", lambda: bld.add(
        tube(_tube_sections(neck_rows, s), n=10, cap_start=False), skin,
        uvscale=8.0, smooth=True))

    # ---------------- 頭(丸い筒 + 前面に沿わせた顔) ----------------
    head_rows = [(z, 0.0, cy, rx, ry, 1.0 - k / (len(HEAD_ROWS) - 1.0))
                 for k, (z, cy, rx, ry) in enumerate(HEAD_ROWS)]
    mark("head", lambda: bld.add(
        tube(_tube_sections(head_rows, s), n=10), skin, uvscale=7.0, smooth=True))
    mark("head", lambda: bld.add(_face_grid(s), face, smooth=True))
    # 耳(頭に沿わせる。出っ張らせると板が浮いて見える)
    for sx in (-1, 1):
        mark("head", lambda sx=sx: bld.add(
            box_taper(0.012 * s, 0.026 * s, 0.009 * s, 0.034 * s, 0.048 * s,
                      (sx * 0.0885 * s, 0.006 * s, 1.646 * s)), skin, uvscale=16.0))

    # ---------------- 髪 ----------------
    back = spec.get("hair_back", 0.0)         # 後退具合(社長は大きい)
    z0 = spec.get("hair_z0", 1.800)
    z1 = spec.get("hair_z1", FACE_TOP - 0.004)
    # 頭(半幅 0.097 / 半奥 0.104)より少しだけ大きい程度に収める
    hair_rows = [
        (z0, 0, back * 0.4 - 0.004, 0.046, 0.050, 1.00),
        (z0 - 0.018, 0, back * 0.5 - 0.004, 0.080, 0.086, 0.88),
        (z0 - 0.046, 0, back * 0.7 - 0.004, 0.098, 0.106, 0.66),
        (z0 - 0.086, 0, back * 0.9 - 0.004, 0.102, 0.110, 0.38),
        (z1, 0, back - 0.004, 0.099, 0.107, 0.08),
    ]
    mark("head", lambda: bld.add(
        tube(_tube_sections(hair_rows, s), n=12, cap_end=False), hair_m,
        uvscale=6.0, smooth=True))
    # 後頭部(短い髪でも後ろは残る)
    mark("head", lambda: bld.add(
        box_taper(0.168 * s, 0.090 * s, 0.184 * s, 0.104 * s, 0.106 * s,
                  (0, 0.046 * s, 1.686 * s)), hair_m, uvscale=6.0))
    if spec.get("long_hair"):
        # 肩にかかる黒髪。頭に沿わせ、下ほど広がる
        # 前に回り込むと顎まで隠れるので、下ほど後ろへ寄せる
        long_rows = [
            (1.712, 0, 0.046, 0.098, 0.098, 1.00),
            (1.640, 0, 0.058, 0.104, 0.100, 0.74),
            (1.540, 0, 0.070, 0.110, 0.102, 0.40),
            (1.452, 0, 0.078, 0.114, 0.104, 0.00),
        ]
        mark("head", lambda: bld.add(
            tube(_tube_sections(long_rows, s), n=10, cap_start=False),
            hair_m, uvscale=3.4, smooth=True))
        for sx in (-1, 1):
            mark("head", lambda sx=sx: bld.add(
                box_taper(0.030 * s, 0.072 * s, 0.036 * s, 0.086 * s, 0.216 * s,
                          (sx * 0.100 * s, 0.048 * s, 1.572 * s)), hair_m, uvscale=4.0))

    # ---------------- 腕 ----------------
    for sx in (-1, 1):
        side = "L" if sx > 0 else "R"
        arm_rows = [
            (1.438, sx * 0.148, 0, 0.070, 0.070, 1.00),
            (1.400, sx * 0.205, 0, 0.058, 0.058, 0.90),
            (1.300, sx * 0.222, 0, 0.050, 0.050, 0.72),
            (1.180, sx * 0.238, 0, 0.044, 0.046, 0.52),
            (1.060, sx * 0.250, 0, 0.040, 0.041, 0.32),
            (0.955, sx * 0.258, 0, 0.035, 0.036, 0.14),
            (0.900, sx * 0.262, 0, 0.031, 0.032, 0.00),
        ]
        mark("arm" + side, lambda sx=sx, r=arm_rows: bld.add(
            tube(_tube_sections(r, s), n=10, cap_start=False), torso_m,
            uvscale=1.0, smooth=True))
        # 袖口
        mark("arm" + side, lambda sx=sx: bld.add(
            cyl(0.034 * s, 0.022 * s, 10, (sx * 0.262 * s, 0, 0.908 * s)),
            torso_m, uvscale=9.0))
        # 手(指なしの手袋型)
        mark("hand" + side, lambda sx=sx: bld.add(
            box_taper(0.056 * s, 0.034 * s, 0.052 * s, 0.032 * s, 0.070 * s,
                      (sx * 0.264 * s, -0.006 * s, 0.862 * s)), skin, uvscale=11.0))
        mark("hand" + side, lambda sx=sx: bld.add(
            box_taper(0.052 * s, 0.032 * s, 0.034 * s, 0.024 * s, 0.038 * s,
                      (sx * 0.264 * s, -0.010 * s, 0.808 * s)), skin, uvscale=13.0))
        mark("hand" + side, lambda sx=sx: bld.add(
            box_taper(0.020 * s, 0.026 * s, 0.015 * s, 0.020 * s, 0.046 * s,
                      (sx * 0.232 * s, -0.012 * s, 0.856 * s)), skin, uvscale=16.0))

    # ---------------- 脚 ----------------
    for sx in (-1, 1):
        side = "L" if sx > 0 else "R"
        leg_rows = [
            (0.955, sx * 0.100, 0, 0.098, 0.101, 1.00),
            (0.860, sx * 0.100, 0, 0.096, 0.099, 0.90),
            (0.720, sx * 0.100, 0, 0.085, 0.090, 0.74),
            (0.590, sx * 0.100, 0, 0.071, 0.076, 0.58),
            (0.500, sx * 0.100, 0, 0.065, 0.069, 0.46),
            (0.425, sx * 0.100, 0.006, 0.070, 0.077, 0.36),
            (0.300, sx * 0.100, 0.004, 0.058, 0.063, 0.24),
            (0.180, sx * 0.100, 0, 0.046, 0.049, 0.12),
            (0.085, sx * 0.100, 0, 0.039, 0.043, 0.00),
        ]
        mark("leg" + side, lambda sx=sx, r=leg_rows: bld.add(
            tube(_tube_sections(r, s), n=12, cap_start=False), spec.get("legmat", torso_m),
            uvscale=1.0, smooth=True))
        # 靴
        sh_w, sh_l = spec.get("shoe_w", 0.096), spec.get("shoe_l", 0.238)
        mark("shoe" + side, lambda sx=sx, w=sh_w, l=sh_l: bld.add(
            box_taper(w * s, l * s, (w - 0.006) * s, (l - 0.010) * s, 0.024 * s,
                      (sx * 0.100 * s, -0.028 * s, 0.012 * s)), shoe_m, uvscale=6.0))
        mark("shoe" + side, lambda sx=sx, w=sh_w, l=sh_l: bld.add(
            box_taper((w - 0.006) * s, (l - 0.010) * s, (w - 0.026) * s,
                      (l - 0.076) * s, 0.042 * s,
                      (sx * 0.100 * s, -0.030 * s, 0.045 * s)), shoe_m, uvscale=7.0))
        mark("shoe" + side, lambda sx=sx, w=sh_w, l=sh_l: bld.add(
            box_taper((w - 0.024) * s, (l - 0.120) * s, (w - 0.032) * s,
                      (l - 0.150) * s, 0.038 * s,
                      (sx * 0.100 * s, 0.026 * s, 0.084 * s)), shoe_m, uvscale=9.0))

    # ---------------- スカート・ベルト ----------------
    if spec.get("skirt"):
        skirt_rows = [
            (0.910, 0, 0, 0.176, 0.116, 1.0),
            (0.830, 0, 0, 0.196, 0.133, 0.7),
            (0.710, 0, 0, 0.224, 0.154, 0.35),
            (0.628, 0, 0, 0.234, 0.162, 0.0),
        ]
        mark("skirt", lambda: bld.add(
            tube(_tube_sections(skirt_rows, s), n=12, cap_start=False),
            spec["skirt"], uvscale=2.6, smooth=True))
    if spec.get("belt"):
        mark("torso", lambda: bld.add(
            tube(_tube_sections([
                (1.075, 0, -b * 0.028, 0.156 + b * 0.034, 0.106 + b * 0.074, 1.0),
                (1.030, 0, -b * 0.024, 0.160 + b * 0.030, 0.108 + b * 0.062, 0.0),
            ], s), n=14, cap_start=False, cap_end=False),
            spec["belt"], uvscale=3.0, smooth=True))
    return bld, idx


def human_bind(mesh, ao, idx, s):
    """胴は背骨に沿って、腕脚はそれぞれの鎖に沿って滑らかに配分する。
    肘や膝が 90 度曲がっても裂けない。"""
    g = {}
    z = lambda c: c.z / s
    add_chain_weights(g, mesh, idx["torso"],
                      [("Hips", 0.90), ("Spine", 1.09), ("Chest", 1.33),
                       ("Neck", 1.47)], z)
    add_rigid_weights(g, idx["head"], "Head")
    if "skirt" in idx:
        add_rigid_weights(g, idx["skirt"], "Hips")
    for side in ("L", "R"):
        add_chain_weights(g, mesh, idx["arm" + side],
                          [("LowerArm." + side, 1.04), ("UpperArm." + side, 1.32)], z)
        add_rigid_weights(g, idx["hand" + side], "LowerArm." + side)
        add_chain_weights(g, mesh, idx["leg" + side],
                          [("LowerLeg." + side, 0.42), ("UpperLeg." + side, 0.63)], z)
        add_rigid_weights(g, idx["shoe" + side], "LowerLeg." + side)
    bind_weights(mesh, ao, g)
    return g


ARMS = ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]
LEGS = ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R"]
SPINE = ["Hips", "Spine", "Chest", "Neck", "Head"]


def anim_human_idle(ao, length=90):
    """立ち。呼吸で上下 + わずかな重心移動。"""
    a = Anim(ao, "idle", length)
    N = 6
    for k in range(N + 1):
        f = 1 + k * (length - 1) / N
        t = k / float(N)
        ph = math.sin(t * 2 * math.pi)
        ph2 = math.sin(t * 2 * math.pi + 1.0)
        a.keyw_loc(f, "Hips", (0.0, 0.0, 0.006 * ph))
        a.keyw_mul(f, "Hips", [('Y', R(1.4) * ph2), ('Z', R(1.0) * ph)])
        a.keyw(f, "Spine", 'X', R(-1.6) * ph)
        a.keyw(f, "Chest", 'X', R(-2.2) * ph)
        a.keyw_mul(f, "Neck", [('X', R(1.2) * ph), ('Z', R(1.8) * ph2)])
        a.keyw_mul(f, "Head", [('X', R(0.8) * ph2), ('Z', R(-2.4) * ph2)])
        for (bn, sgn) in (("UpperArm.L", 1), ("UpperArm.R", -1)):
            a.keyw_mul(f, bn, [('X', R(2.0) * ph), ('Y', sgn * R(4.0))])
        for bn in ("LowerArm.L", "LowerArm.R"):
            a.keyw(f, bn, 'X', R(-10.0) + R(1.5) * ph)
        for bn in LEGS:
            a.keyw(f, bn, 'X', 0.0)
    return a.finish()


def anim_human_walk(ao, length=30, amp=24.0):
    """歩行 1 周期。その場歩き(移動は Godot 側)。"""
    a = Anim(ao, "walk", length)
    N = 8
    for k in range(N + 1):
        f = 1 + k * (length - 1) / float(N)
        t = k / float(N)
        w = 2 * math.pi * t
        sl = math.sin(w)
        sr = -sl
        kl = max(0.0, -math.sin(w + 0.9)) * R(38)
        kr = max(0.0, -math.sin(w + math.pi + 0.9)) * R(38)
        a.keyw(f, "UpperLeg.L", 'X', R(-amp) * sl)
        a.keyw(f, "UpperLeg.R", 'X', R(-amp) * sr)
        a.keyw(f, "LowerLeg.L", 'X', kl)
        a.keyw(f, "LowerLeg.R", 'X', kr)
        a.keyw_mul(f, "UpperArm.L", [('X', R(amp * 0.55) * sl), ('Y', R(5))])
        a.keyw_mul(f, "UpperArm.R", [('X', R(amp * 0.55) * sr), ('Y', R(-5))])
        a.keyw(f, "LowerArm.L", 'X', R(-14) - R(10) * max(0.0, sl))
        a.keyw(f, "LowerArm.R", 'X', R(-14) - R(10) * max(0.0, sr))
        a.keyw_loc(f, "Hips", (0.0, 0.0, -0.022 * abs(math.cos(w))))
        a.keyw_mul(f, "Hips", [('Z', R(-5) * sl), ('Y', R(2.5) * math.cos(w))])
        a.keyw_mul(f, "Chest", [('Z', R(5) * sl), ('X', R(2.0))])
        a.keyw(f, "Neck", 'X', R(-1.5))
        a.keyw_mul(f, "Head", [('Z', R(-2) * sl)])
    return a.finish()


def anim_human_sit(ao, length=90):
    """椅子に座る。腰を落として腿を前へ、脛は下へ。ループ(呼吸)。"""
    HIP_X = -9.0
    a = Anim(ao, "sit", length)
    N = 6
    for k in range(N + 1):
        f = 1 + k * (length - 1) / N
        t = k / float(N)
        ph = math.sin(t * 2 * math.pi)
        # 腰を座面の高さへ落とす(腿の付け根が z=0.50 になる)
        a.keyw_loc(f, "Hips", (0.0, 0.020, -0.430))
        a.keyw_mul(f, "Hips", [('X', R(HIP_X)), ('Z', R(1.2) * ph)])
        a.keyw(f, "Spine", 'X', R(5.0) + R(1.0) * ph)
        a.keyw(f, "Chest", 'X', R(3.5) + R(1.8) * ph)
        a.keyw_mul(f, "Neck", [('X', R(2.0)), ('Z', R(1.5) * ph)])
        a.keyw_mul(f, "Head", [('X', R(4.0)), ('Z', R(-2.0) * ph)])
        # 腿を水平に(親の傾き分を差し引く)
        for side in ("L", "R"):
            a.keyw_mul(f, "UpperLeg." + side,
                       [('X', R(-84.0 - HIP_X)), ('Z', R(3.0 if side == "L" else -3.0))])
            a.keyw(f, "LowerLeg." + side, 'X', R(80.0))
        # 腕は腿の上に置く
        for (side, sgn) in (("L", 1), ("R", -1)):
            a.keyw_mul(f, "UpperArm." + side,
                       [('X', R(-26.0) + R(1.2) * ph), ('Y', sgn * R(7.0))])
            a.keyw(f, "LowerArm." + side, 'X', R(-46.0))
    return a.finish()


def anim_human_sleep(ao, length=120):
    """座布団の上でうつ伏せ寄りに横になる。ループ(寝息)。"""
    a = Anim(ao, "sleep", length)
    N = 8
    for k in range(N + 1):
        f = 1 + k * (length - 1) / N
        t = k / float(N)
        br = math.sin(t * 2 * math.pi)          # 寝息
        # 腰を床へ。X +90 でうつ伏せ(頭が -Y)、Y 回転で少し横向きに
        a.keyw_loc(f, "Hips", (0.02, 0.10, -0.775 + 0.004 * br))
        a.keyw_mul(f, "Hips", [('X', R(90.0)), ('Y', R(24.0)), ('Z', R(4.0))])
        a.keyw_mul(f, "Spine", [('X', R(-6.0) + R(1.4) * br), ('Z', R(-5.0))])
        a.keyw_mul(f, "Chest", [('X', R(-8.0) + R(2.2) * br), ('Z', R(-7.0))])
        a.keyw_mul(f, "Neck", [('X', R(-6.0)), ('Z', R(16.0))])
        a.keyw_mul(f, "Head", [('X', R(-4.0)), ('Z', R(30.0)), ('Y', R(-12.0))])
        # 右腕は頭の横へ折り、左腕は体の下へ
        a.keyw_mul(f, "UpperArm.R", [('X', R(-96.0)), ('Y', R(-26.0)), ('Z', R(12.0))])
        a.keyw(f, "LowerArm.R", 'X', R(-62.0))
        a.keyw_mul(f, "UpperArm.L", [('X', R(18.0)), ('Y', R(16.0))])
        a.keyw(f, "LowerArm.L", 'X', R(-38.0))
        # 片脚を曲げる
        a.keyw_mul(f, "UpperLeg.L", [('X', R(-16.0)), ('Z', R(-22.0))])
        a.keyw(f, "LowerLeg.L", 'X', R(64.0))
        a.keyw_mul(f, "UpperLeg.R", [('X', R(4.0)), ('Z', R(4.0))])
        a.keyw(f, "LowerLeg.R", 'X', R(14.0))
    return a.finish()


def _drink_curve(t):
    """0..1 の周期位置から「缶を口に運ぶ」量を返す。上げる→保つ→下ろす。"""
    if t < 0.40 or t > 0.70:
        return 0.0
    if t < 0.50:
        u = (t - 0.40) / 0.10
    elif t < 0.60:
        return 1.0
    else:
        u = 1.0 - (t - 0.60) / 0.10
    return u * u * (3.0 - 2.0 * u)


def anim_human_sit_floor(ao, length=180):
    """座布団の上であぐら。ループ(呼吸 + ときどき缶を口へ)。
    腰は床から 0.20m。座布団(厚み 0.065)の上に座る想定。"""
    a = Anim(ao, "sit_floor", length)
    N = 24
    for k in range(N + 1):
        f = 1 + k * (length - 1) / float(N)
        t = k / float(N)
        br = math.sin(t * 2 * math.pi * 3.0)        # 呼吸(1 周期に 3 回)
        dr = _drink_curve(t)

        a.keyw_loc(f, "Hips", (0.0, 0.040, -0.750 + 0.004 * br))
        a.keyw_mul(f, "Hips", [('X', R(-6.0)), ('Z', R(2.0) * br)])
        a.keyw(f, "Spine", 'X', R(7.0) + R(1.2) * br)
        a.keyw_mul(f, "Chest", [('X', R(5.0) + R(2.0) * br), ('Z', R(-2.5) * br)])
        a.keyw_mul(f, "Neck", [('X', R(3.0) - R(9.0) * dr), ('Z', R(1.5) * br)])
        a.keyw_mul(f, "Head", [('X', R(5.0) - R(14.0) * dr), ('Z', R(-2.0) * br)])

        # あぐら: 腿を前へ倒して外へ開き、脛をたたんで内側へ
        for (side, sgn) in (("L", 1), ("R", -1)):
            a.keyw_mul(f, "UpperLeg." + side,
                       [('X', R(-82.0)), ('Z', sgn * R(48.0)), ('Y', sgn * R(14.0))])
            a.keyw_mul(f, "LowerLeg." + side,
                       [('X', R(92.0)), ('Z', -sgn * R(66.0))])

        # Y 回転は、左腕は負が外向き、右腕は正が外向き(腕は下を向いているため)
        # 腕は体側に下ろし、前腕だけ曲げて手を腿の上へ。
        # 肩を開きすぎると「両手を広げている」姿勢になる。
        # 座っているので肩の位置が低い。前腕を曲げすぎると手が前に突き出す。
        a.keyw_mul(f, "UpperArm.L", [('X', R(-7.0) + R(1.5) * br), ('Y', R(-12.0))])
        a.keyw_mul(f, "LowerArm.L", [('X', R(-42.0)), ('Z', R(16.0))])
        # 右手は缶を持ち、ときどき口へ運ぶ
        a.keyw_mul(f, "UpperArm.R",
                   [('X', R(-8.0) + R(18.0) * dr + R(1.5) * br),
                    ('Y', R(11.0) - R(6.0) * dr)])
        a.keyw_mul(f, "LowerArm.R",
                   [('X', R(-44.0) - R(86.0) * dr), ('Z', -R(16.0) + R(8.0) * dr)])
    return a.finish()


def build_human(name, spec):
    """spec の中のマテリアルは reset_scene() の後に作ること(参照が無効になる)。"""
    s = spec["s"]
    bld, idx = human_mesh(name, spec)
    mesh = bld.build()
    ao = make_armature(name, BONES, scale=s)
    human_bind(mesh, ao, idx, s)
    set_scene_frames(180)
    anim_human_idle(ao)
    anim_human_walk(ao)
    anim_human_sit(ao)
    anim_human_sit_floor(ao)
    anim_human_sleep(ao)
    emit(name, [ao, mesh], animations=True)


def build_npc_boss():
    """社長 60 代。黒いスーツ、腹が出ている、髪は薄い。"""
    reset_scene()
    setup_fps()
    build_human("npc_boss", dict(
        s=0.945, belly=0.85, shoulder=1.06,
        hair_back=0.034, hair_z0=1.806, hair_z1=1.716,
        torso=material("BossSuit", "torso_suit", color=(0.11, 0.11, 0.13), rough=0.85),
        legmat=material("BossTrouser", "suit_black", color=(0.11, 0.11, 0.13), rough=0.88),
        belt=material("BossBelt", "shoe_leather", color=(0.08, 0.08, 0.08), rough=0.5),
        skin=material("BossSkin", "skin_pale", color=(0.70, 0.57, 0.48), rough=0.8),
        face=material("BossFace", "face_boss", color=(0.75, 0.62, 0.53), rough=0.8),
        hair=material("BossHair", "hair_thin", color=(0.13, 0.12, 0.11), rough=0.9),
        shoe=material("BossShoe", "shoe_leather", color=(0.07, 0.07, 0.08), rough=0.35),
    ))


def build_npc_son():
    """息子 60 代。くたびれたジャンパー、赤ら顔、白髪混じりの短髪。"""
    reset_scene()
    setup_fps()
    build_human("npc_son", dict(
        s=0.965, belly=0.45, shoulder=1.0,
        hair_back=0.006, hair_z0=1.800, hair_z1=1.698,
        torso=material("SonJumper", "torso_jumper", color=(0.20, 0.23, 0.29), rough=0.9),
        legmat=material("SonTrouser", "jumper", color=(0.22, 0.22, 0.24), rough=0.92),
        belt=material("SonBelt", "shoe_leather", color=(0.12, 0.10, 0.09), rough=0.6),
        skin=material("SonSkin", "skin_pale", color=(0.74, 0.55, 0.46), rough=0.8),
        face=material("SonFace", "face_son", color=(0.78, 0.58, 0.48), rough=0.8),
        hair=material("SonHair", "hair_salt", color=(0.16, 0.15, 0.14), rough=0.95),
        shoe=material("SonShoe", "shoe_leather", color=(0.16, 0.15, 0.14), rough=0.7),
    ))


def build_npc_granddaughter():
    """孫娘 20 代。黒いワンピース、肩にかかる黒い長髪。"""
    reset_scene()
    setup_fps()
    build_human("npc_granddaughter", dict(
        s=0.900, belly=0.0, bust=0.85, shoulder=0.90, long_hair=True,
        hair_back=0.004, hair_z0=1.806, hair_z1=1.700,
        shoe_w=0.082, shoe_l=0.230,
        torso=material("GdDress", "torso_dress", color=(0.09, 0.09, 0.11), rough=0.92),
        skirt=material("GdSkirt", "dress_black", color=(0.09, 0.09, 0.11), rough=0.92),
        legmat=material("GdLeg", "skin_pale", color=(0.80, 0.68, 0.61), rough=0.75),
        skin=material("GdSkin", "skin_pale", color=(0.80, 0.68, 0.61), rough=0.75),
        face=material("GdFace", "face_granddaughter", color=(0.82, 0.70, 0.63), rough=0.75),
        hair=material("GdHair", "hair_long", color=(0.07, 0.07, 0.08), rough=0.85),
        shoe=material("GdShoe", "shoe_leather", color=(0.07, 0.07, 0.08), rough=0.4),
    ))


# ================================================================ body_risen

RISEN_BONES = [
    # 寝た状態で組む(頭 = -Y、足 = +Y、高さ z=0.16)
    ("Hips",        (0.00, 0.10, 0.16), (0.00, -0.04, 0.16), None),
    ("Spine",       (0.00, -0.04, 0.16), (0.00, -0.22, 0.16), "Hips"),
    ("Chest",       (0.00, -0.22, 0.16), (0.00, -0.42, 0.16), "Spine"),
    ("Neck",        (0.00, -0.42, 0.16), (0.00, -0.52, 0.16), "Chest"),
    ("Head",        (0.00, -0.52, 0.16), (0.00, -0.74, 0.16), "Neck"),
    ("UpperArm.L",  (0.19, -0.36, 0.15), (0.21, -0.14, 0.14), "Chest"),
    ("LowerArm.L",  (0.21, -0.14, 0.14), (0.22, 0.08, 0.14), "UpperArm.L"),
    ("UpperArm.R", (-0.19, -0.36, 0.15), (-0.21, -0.14, 0.14), "Chest"),
    ("LowerArm.R", (-0.21, -0.14, 0.14), (-0.22, 0.08, 0.14), "UpperArm.R"),
    ("UpperLeg.L",  (0.10, 0.12, 0.15), (0.10, 0.52, 0.14), "Hips"),
    ("LowerLeg.L",  (0.10, 0.52, 0.14), (0.10, 0.92, 0.12), "UpperLeg.L"),
    ("UpperLeg.R", (-0.10, 0.12, 0.15), (-0.10, 0.52, 0.14), "Hips"),
    ("LowerLeg.R", (-0.10, 0.52, 0.14), (-0.10, 0.92, 0.12), "UpperLeg.R"),
]


def build_body_risen():
    """白装束の故人。寝た姿勢で組み、`rise` で 2 秒かけて上体を起こす。"""
    reset_scene()
    setup_fps()
    sh = material("ShroudCloth", "white_cloth", color=(0.86, 0.85, 0.82), rough=0.95)
    skin = material("DeadSkin", "skin_pale", color=(0.66, 0.62, 0.60), rough=0.9)
    face = material("DeadFace", "body_face_eyes", color=(0.72, 0.70, 0.68), rough=0.9)
    hair = material("DeadHair", "white_cloth", color=(0.55, 0.54, 0.53), rough=0.95)

    b = Builder("body_risen")
    # 胴〜頭は 1 本の筒(断面を共有)にして、曲げても裂けないようにする。
    # y = +0.98(足先) → -0.74(頭頂) の順に断面を並べる。
    torso = [
        ring(0.0, 0.16, 0.155, 0.175, 0.115),   # 腰
        ring(0.0, 0.03, 0.160, 0.180, 0.118),
        ring(0.0, -0.08, 0.160, 0.175, 0.112),  # 腹
        ring(0.0, -0.20, 0.160, 0.180, 0.112),
        ring(0.0, -0.32, 0.160, 0.190, 0.115),  # 胸
        ring(0.0, -0.42, 0.160, 0.185, 0.110),  # 肩
        ring(0.0, -0.47, 0.160, 0.070, 0.060),  # 首
        ring(0.0, -0.53, 0.165, 0.090, 0.100),  # 顎
        ring(0.0, -0.68, 0.168, 0.102, 0.112),  # 頭
        ring(0.0, -0.74, 0.168, 0.070, 0.080),  # 頭頂
    ]
    b.add(loft_rings(torso), sh, 4)
    # 白装束の打ち合わせ(左前)
    for sx in (-1, 1):
        v, f = box(0.13, 0.22, 0.03, (0, 0, 0))
        v = tr(v, rot=(0, 0, sx * 0.12), t=(sx * 0.062, -0.30, 0.272))
        b.add((v, f), sh, 7)
    b.add(box_mm(-0.052, 0.052, -0.40, -0.10, 0.272, 0.286), sh, 8)
    # 顔(頭の上面に貼る 1 枚。頭頂が -Y 側)
    b.add(([(0.095, -0.535, 0.276), (-0.095, -0.535, 0.276),
            (-0.095, -0.720, 0.276), (0.095, -0.720, 0.276)], [(0, 1, 2, 3)]),
          face, uv=[[(0.06, 0.06), (0.44, 0.06), (0.44, 0.96), (0.06, 0.96)]])
    b.add(box_mm(-0.098, 0.098, -0.745, -0.660, 0.150, 0.272), hair, 7)   # 白髪
    # 腕と脚は、作った順(頂点インデックス)でボーンに割り当てる。
    # 胴のロフトと座標が重なるので、位置で判定すると腰が脚に引っ張られる。
    limb_idx = {}

    def mark(bone, fn):
        i0 = b.count()
        fn()
        limb_idx.setdefault(bone, []).extend(range(i0, b.count()))

    for sx in (-1, 1):
        x = sx * 0.20
        side = "L" if sx > 0 else "R"
        mark("UpperArm." + side, lambda x=x, sx=sx: b.add(
            cyl(0.050, 0.22, 8, (x, -0.25, 0.150), axis='Y', r_top=0.046), sh, 8))
        mark("LowerArm." + side, lambda x=x, sx=sx: (
            b.add(cyl(0.046, 0.22, 8, (x + sx * 0.012, -0.03, 0.145), axis='Y',
                      r_top=0.042), sh, 8),
            b.add(box_taper(0.070, 0.115, 0.060, 0.100, 0.048,
                            (x + sx * 0.022, 0.135, 0.14)), skin, 10)))
    for sx in (-1, 1):
        x = sx * 0.10
        side = "L" if sx > 0 else "R"
        mark("UpperLeg." + side, lambda x=x: b.add(
            cyl(0.082, 0.40, 8, (x, 0.32, 0.15), axis='Y', r_top=0.070), sh, 6))
        mark("LowerLeg." + side, lambda x=x: (
            b.add(cyl(0.070, 0.40, 8, (x, 0.72, 0.13), axis='Y', r_top=0.060), sh, 6),
            b.add(box_mm(x - 0.055, x + 0.055, 0.90, 0.96, 0.075, 0.205), sh, 9),
            b.add(box_mm(x - 0.050, x + 0.050, 0.96, 1.02, 0.075, 0.150), sh, 9)))
    mesh = b.build()

    ao = make_armature("body_risen", RISEN_BONES, scale=1.0)
    # 胴体は y に沿って滑らかに配分(裂けない)、腕と脚はインデックスで固定
    chain = [
        ("Head", -0.62), ("Neck", -0.46), ("Chest", -0.30),
        ("Spine", -0.12), ("Hips", 0.10),
    ]   # t(= y)の昇順であること。chain_weights は昇順を前提に補間する。
    chain_weights(mesh, ao, chain, lambda c: c.y, rigid_idx=limb_idx)
    set_scene_frames(60)
    a = Anim(ao, "rise", 60)
    N = 10
    for k in range(N + 1):
        f = 1 + k * 59.0 / N
        t = k / float(N)
        # ゆっくり始まって最後は止まる
        e = t * t * (3 - 2 * t)
        a.keyw(f, "Spine", 'X', R(-46) * e)
        a.keyw(f, "Chest", 'X', R(-38) * e)
        a.keyw(f, "Neck", 'X', R(-8) * e + R(4) * (1 - e))
        a.keyw_mul(f, "Head", [('X', R(14) * e), ('Z', R(-10) * e)])
        for sx, bn in ((1, "UpperArm.L"), (-1, "UpperArm.R")):
            a.keyw_mul(f, bn, [('X', R(-10) * e), ('Z', sx * R(8) * e)])
        for bn in ("LowerArm.L", "LowerArm.R"):
            a.keyw(f, bn, 'X', R(-6) * e)
        a.keyw(f, "Hips", 'X', R(-4) * e)
    a.finish()
    emit("body_risen", [ao, mesh], animations=True)


# ================================================================ 猫

CAT_BONES = [
    ("Hips",  (0.000, 0.100, 0.215), (0.000, 0.020, 0.225), None),
    ("Spine", (0.000, 0.020, 0.225), (0.000, -0.090, 0.235), "Hips"),
    ("Chest", (0.000, -0.090, 0.235), (0.000, -0.185, 0.240), "Spine"),
    ("Neck",  (0.000, -0.185, 0.240), (0.000, -0.245, 0.260), "Chest"),
    ("Head",  (0.000, -0.245, 0.260), (0.000, -0.340, 0.262), "Neck"),
    ("Tail1", (0.000, 0.135, 0.220), (0.000, 0.230, 0.255), "Hips"),
    ("Tail2", (0.000, 0.230, 0.255), (0.000, 0.310, 0.300), "Tail1"),
    ("LegBL", (0.055, 0.085, 0.195), (0.055, 0.095, 0.105), "Hips"),
    ("PawBL", (0.055, 0.095, 0.105), (0.055, 0.055, 0.005), "LegBL"),
    ("LegBR", (-0.055, 0.085, 0.195), (-0.055, 0.095, 0.105), "Hips"),
    ("PawBR", (-0.055, 0.095, 0.105), (-0.055, 0.055, 0.005), "LegBR"),
    ("LegFL", (0.050, -0.145, 0.200), (0.050, -0.150, 0.105), "Chest"),
    ("PawFL", (0.050, -0.150, 0.105), (0.050, -0.165, 0.005), "LegFL"),
    ("LegFR", (-0.050, -0.145, 0.200), (-0.050, -0.150, 0.105), "Chest"),
    ("PawFR", (-0.050, -0.150, 0.105), (-0.050, -0.165, 0.005), "LegFR"),
]

CAT_LEGS = ["LegBL", "LegBR", "LegFL", "LegFR", "PawBL", "PawBR", "PawFL", "PawFR"]


def build_cat():
    """黒猫。目だけ自発光(マテリアル `Eyes`)。"""
    reset_scene()
    setup_fps()
    fur = material("CatFur", "fur_black", color=(0.075, 0.075, 0.085), rough=0.95)
    inner = material("CatInner", "skin_pale", color=(0.36, 0.22, 0.24), rough=0.9)
    eyes = material("Eyes", None, color=(0.85, 0.82, 0.30),
                    emission=(1.0, 0.92, 0.35), emission_strength=3.2, rough=0.3)

    b = Builder("cat")
    # 胴(頭 = -Y)
    b.add(box_taper(0.135, 0.150, 0.150, 0.130, 0.140, (0, 0.075, 0.222)), fur, 7)
    b.add(box_taper(0.150, 0.130, 0.148, 0.130, 0.150, (0, -0.055, 0.232)), fur, 7)
    b.add(box_taper(0.148, 0.130, 0.128, 0.120, 0.110, (0, -0.165, 0.238)), fur, 8)
    # 首と頭
    b.add(cyl(0.048, 0.06, 8, (0, -0.225, 0.250), axis='Y'), fur, 12)
    b.add(box_taper(0.115, 0.105, 0.100, 0.100, 0.100, (0, -0.290, 0.262)), fur, 10)
    b.add(box_taper(0.082, 0.070, 0.062, 0.050, 0.045, (0, -0.348, 0.245)), fur, 14)
    b.add(box_mm(-0.016, 0.016, -0.378, -0.366, 0.240, 0.254), inner, 22)     # 鼻
    # 耳
    for sx in (-1, 1):
        v, f = box_taper(0.055, 0.022, 0.010, 0.010, 0.060, (0, 0, 0))
        v = tr(v, rot=(0, sx * 0.30, 0), t=(sx * 0.042, -0.272, 0.336))
        b.add((v, f), fur, 14)
        v2, f2 = box_taper(0.032, 0.010, 0.006, 0.006, 0.040, (0, 0, 0))
        v2 = tr(v2, rot=(0, sx * 0.30, 0), t=(sx * 0.042, -0.280, 0.328))
        b.add((v2, f2), inner, 18)
    # 目(自発光)
    for sx in (-1, 1):
        b.add(box_taper(0.030, 0.012, 0.018, 0.008, 0.026,
                        (sx * 0.040, -0.338, 0.280)), eyes, 22)
    # 脚
    for (sx, sy, fy) in ((1, 1, 0.090), (-1, 1, 0.090), (1, -1, -0.148), (-1, -1, -0.148)):
        x = sx * (0.055 if sy > 0 else 0.050)
        b.add(cyl(0.030, 0.095, 6, (x, fy, 0.150), r_top=0.024), fur, 16)
        b.add(cyl(0.024, 0.100, 6, (x, fy - 0.012 * sy, 0.055), r_top=0.022), fur, 16)
        b.add(box_taper(0.052, 0.070, 0.048, 0.062, 0.030,
                        (x, fy - 0.030 * sy, 0.015)), fur, 18)
    # 尻尾
    for k in range(5):
        t = k / 4.0
        y = 0.135 + t * 0.185
        z = 0.220 + t * t * 0.090
        b.add(cyl(0.020 - t * 0.008, 0.050, 6, (0, y, z), axis='Y'), fur, 20)
    mesh = b.build()

    ao = make_armature("cat", CAT_BONES, scale=1.0)
    rules = [
        ("PawFL", lambda c: c.z < 0.105 and c.y < 0.0 and c.x >= 0),
        ("PawFR", lambda c: c.z < 0.105 and c.y < 0.0),
        ("PawBL", lambda c: c.z < 0.105 and c.y < 0.13 and c.x >= 0),
        ("PawBR", lambda c: c.z < 0.105 and c.y < 0.13),
        ("LegFL", lambda c: c.z < 0.195 and c.y < 0.0 and c.x >= 0.028),
        ("LegFR", lambda c: c.z < 0.195 and c.y < 0.0 and c.x <= -0.028),
        ("LegBL", lambda c: c.z < 0.195 and c.y < 0.13 and c.x >= 0.028),
        ("LegBR", lambda c: c.z < 0.195 and c.y < 0.13 and c.x <= -0.028),
        ("Tail2", lambda c: c.y > 0.245),
        ("Tail1", lambda c: c.y > 0.130),
        ("Head", lambda c: c.y < -0.255),
        ("Neck", lambda c: c.y < -0.205),
        ("Chest", lambda c: c.y < -0.075),
        ("Spine", lambda c: c.y < 0.035),
        ("Hips", lambda c: True),
    ]
    auto_groups(mesh, ao, rules)

    set_scene_frames(96)

    # --- idle: 呼吸 + 尻尾の揺れ + 時々の首振り ---
    a = Anim(ao, "idle", 96)
    N = 8
    for k in range(N + 1):
        f = 1 + k * 95.0 / N
        t = k / float(N)
        w = 2 * math.pi * t
        a.keyw(f, "Chest", 'X', R(1.8) * math.sin(w))
        a.keyw(f, "Spine", 'X', R(1.2) * math.sin(w))
        a.keyw_mul(f, "Neck", [('Z', R(4.0) * math.sin(w * 0.5))])
        a.keyw_mul(f, "Head", [('Z', R(-7.0) * math.sin(w * 0.5)),
                               ('X', R(3.0) * math.sin(w))])
        a.keyw_mul(f, "Tail1", [('Z', R(14.0) * math.sin(w)), ('X', R(-8.0))])
        a.keyw_mul(f, "Tail2", [('Z', R(20.0) * math.sin(w + 1.0)), ('X', R(-12.0))])
        for bn in CAT_LEGS:
            a.keyw(f, bn, 'X', 0.0)
        a.keyw_loc(f, "Hips", (0, 0, 0.004 * math.sin(w)))
    a.finish()

    # --- walk ---
    a = Anim(ao, "walk", 24)
    N = 8
    for k in range(N + 1):
        f = 1 + k * 23.0 / N
        t = k / float(N)
        w = 2 * math.pi * t
        # 対角の脚が同位相(トロット)
        pairs = (("LegFL", "PawFL", 0.0), ("LegBR", "PawBR", 0.0),
                 ("LegFR", "PawFR", math.pi), ("LegBL", "PawBL", math.pi))
        for (leg, paw, ph) in pairs:
            sw = math.sin(w + ph)
            a.keyw(f, leg, 'X', R(-26) * sw)
            a.keyw(f, paw, 'X', R(22) * max(0.0, -math.sin(w + ph + 0.8)))
        a.keyw_loc(f, "Hips", (0, 0, 0.012 * abs(math.cos(w))))
        a.keyw(f, "Spine", 'X', R(2.5) * math.sin(w * 2))
        a.keyw(f, "Chest", 'X', R(-2.0) * math.sin(w * 2))
        a.keyw_mul(f, "Tail1", [('Z', R(10) * math.sin(w)), ('X', R(-16))])
        a.keyw_mul(f, "Tail2", [('Z', R(14) * math.sin(w + 0.8)), ('X', R(-20))])
        a.keyw(f, "Head", 'X', R(2) * math.sin(w * 2))
    a.finish()

    # --- sit: 座った姿勢を保ち、尻尾と首だけ動く ---
    # keyw はワールド回転だが親の回転は積み上がるので、前脚は胴の傾き分を戻す。
    HIP, SPN, CHS = -10.0, -32.0, -32.0
    inherit_front = HIP + SPN + CHS          # 前脚が受け継ぐ傾き
    a = Anim(ao, "sit", 72)
    N = 6
    for k in range(N + 1):
        f = 1 + k * 71.0 / N
        t = k / float(N)
        w = 2 * math.pi * t
        a.keyw_loc(f, "Hips", (0, 0.030, -0.115))    # 尻を床に落とす
        a.keyw(f, "Hips", 'X', R(HIP))
        a.keyw(f, "Spine", 'X', R(SPN))
        a.keyw(f, "Chest", 'X', R(CHS))
        a.keyw(f, "Neck", 'X', R(26))
        a.keyw_mul(f, "Head", [('X', R(20)), ('Z', R(-6) * math.sin(w * 0.5))])
        # 前脚: 垂直に立てる
        for leg, paw in (("LegFL", "PawFL"), ("LegFR", "PawFR")):
            a.keyw(f, leg, 'X', R(-inherit_front))
            a.keyw(f, paw, 'X', R(-16))
        # 後脚: 腿を前下へ、脛を床に寝かせる
        for leg, paw in (("LegBL", "PawBL"), ("LegBR", "PawBR")):
            a.keyw(f, leg, 'X', R(-50 - HIP))
            a.keyw(f, paw, 'X', R(118))
        a.keyw_mul(f, "Tail1", [('Z', R(24) * math.sin(w)), ('X', R(40))])
        a.keyw_mul(f, "Tail2", [('Z', R(32) * math.sin(w + 1.2)), ('X', R(18))])
    a.finish()

    emit("cat", [ao, mesh], animations=True)


# ================================================================ 火車

KASHA_BONES = [
    ("Hips",  (0.000, 0.360, 0.560), (0.000, 0.180, 0.580), None),
    ("Spine", (0.000, 0.180, 0.580), (0.000, -0.060, 0.600), "Hips"),
    ("Chest", (0.000, -0.060, 0.600), (0.000, -0.320, 0.590), "Spine"),
    ("Neck",  (0.000, -0.320, 0.590), (0.000, -0.470, 0.620), "Chest"),
    ("Head",  (0.000, -0.470, 0.620), (0.000, -0.680, 0.610), "Neck"),
    ("Tail1", (0.000, 0.420, 0.560), (0.000, 0.680, 0.630), "Hips"),
    ("Tail2", (0.000, 0.680, 0.630), (0.000, 0.920, 0.740), "Tail1"),
    # 関節が逆: 肩 → 上へ跳ね上がる肘 → 下へ伸びる前腕
    ("UpperArm.L",  (0.150, -0.280, 0.590), (0.290, -0.420, 0.880), "Chest"),
    ("LowerArm.L",  (0.290, -0.420, 0.880), (0.330, -0.330, 0.020), "UpperArm.L"),
    ("UpperArm.R", (-0.150, -0.280, 0.590), (-0.290, -0.420, 0.880), "Chest"),
    ("LowerArm.R", (-0.290, -0.420, 0.880), (-0.330, -0.330, 0.020), "UpperArm.R"),
    ("UpperLeg.L",  (0.140, 0.330, 0.560), (0.270, 0.480, 0.860), "Hips"),
    ("LowerLeg.L",  (0.270, 0.480, 0.860), (0.300, 0.380, 0.020), "UpperLeg.L"),
    ("UpperLeg.R", (-0.140, 0.330, 0.560), (-0.270, 0.480, 0.860), "Hips"),
    ("LowerLeg.R", (-0.270, 0.480, 0.860), (-0.300, 0.380, 0.020), "UpperLeg.R"),
]


def _kasha_limb(b, mat, p0, p1, p2, r0, r1, r2):
    """2 本の錐台で「く」の字の手足を作る。"""
    def seg(a, c, ra, rc):
        d = Vector(c) - Vector(a)
        ln = d.length
        mid = (Vector(a) + Vector(c)) / 2.0
        v, f = cyl(ra, ln, 6, (0, 0, 0), r_top=rc)
        q = d.normalized().to_track_quat('Z', 'Y')
        v = [tuple(q @ Vector(p)) for p in v]
        v = [(p[0] + mid.x, p[1] + mid.y, p[2] + mid.z) for p in v]
        b.add((v, f), mat, 8)
    seg(p0, p1, r0, r1)
    seg(p1, p2, r1, r2)


def build_kasha():
    """火車: 猫を引き伸ばした影。手足が長く関節が逆。目だけ赤の自発光。"""
    reset_scene()
    setup_fps()
    skin = material("KashaSkin", "kasha_skin", color=(0.045, 0.045, 0.052), rough=0.98)
    eyes = material("Eyes", None, color=(0.75, 0.05, 0.04),
                    emission=(1.0, 0.06, 0.03), emission_strength=5.0, rough=0.3)

    b = Builder("kasha")
    # 細長い胴(頭 = -Y)
    b.add(box_taper(0.230, 0.220, 0.260, 0.240, 0.22, (0, 0.290, 0.565)), skin, 4)
    b.add(box_taper(0.260, 0.240, 0.250, 0.230, 0.26, (0, 0.060, 0.585)), skin, 4)
    b.add(box_taper(0.250, 0.230, 0.215, 0.205, 0.28, (0, -0.200, 0.595)), skin, 4)
    b.add(cyl(0.080, 0.16, 8, (0, -0.390, 0.605), axis='Y', r_top=0.095), skin, 7)
    # 頭(猫だが細長い)
    b.add(box_taper(0.190, 0.165, 0.155, 0.150, 0.20, (0, -0.545, 0.615)), skin, 7)
    b.add(box_taper(0.130, 0.110, 0.080, 0.075, 0.14, (0, -0.700, 0.588)), skin, 9)
    # 長い耳
    for sx in (-1, 1):
        v, f = box_taper(0.075, 0.030, 0.008, 0.008, 0.190, (0, 0, 0))
        v = tr(v, rot=(0.25, sx * 0.34, 0), t=(sx * 0.072, -0.500, 0.735))
        b.add((v, f), skin, 9)
    # 赤い目
    for sx in (-1, 1):
        b.add(box_taper(0.046, 0.022, 0.028, 0.012, 0.038,
                        (sx * 0.062, -0.655, 0.640)), eyes, 16)
    # 手足(関節が逆)
    for sx in (-1, 1):
        _kasha_limb(b, skin, (sx * 0.150, -0.280, 0.590), (sx * 0.290, -0.420, 0.880),
                    (sx * 0.330, -0.330, 0.020), 0.070, 0.050, 0.030)
        _kasha_limb(b, skin, (sx * 0.140, 0.330, 0.560), (sx * 0.270, 0.480, 0.860),
                    (sx * 0.300, 0.380, 0.020), 0.075, 0.052, 0.032)
        # 手先(長い指)
        for k in (-1, 0, 1):
            v, f = box(0.022, 0.150, 0.020, (0, 0, 0))
            v = tr(v, rot=(0, 0, k * 0.30), t=(sx * 0.330 + k * 0.030, -0.400, 0.014))
            b.add((v, f), skin, 14)
            v, f = box(0.022, 0.140, 0.020, (0, 0, 0))
            v = tr(v, rot=(0, 0, k * 0.30), t=(sx * 0.300 + k * 0.030, 0.310, 0.014))
            b.add((v, f), skin, 14)
    # 長い尾
    for k in range(6):
        t = k / 5.0
        y = 0.420 + t * 0.520
        z = 0.560 + t * t * 0.220
        b.add(cyl(0.048 - t * 0.030, 0.110, 6, (0, y, z), axis='Y'), skin, 12)
    mesh = b.build()

    ao = make_armature("kasha", KASHA_BONES, scale=1.0)
    rules = [
        ("LowerArm.L", lambda c: c.x > 0.20 and c.y < 0.10 and c.z < 0.80),
        ("UpperArm.L", lambda c: c.x > 0.115 and c.y < 0.10),
        ("LowerArm.R", lambda c: c.x < -0.20 and c.y < 0.10 and c.z < 0.80),
        ("UpperArm.R", lambda c: c.x < -0.115 and c.y < 0.10),
        ("LowerLeg.L", lambda c: c.x > 0.20 and c.z < 0.80),
        ("UpperLeg.L", lambda c: c.x > 0.115),
        ("LowerLeg.R", lambda c: c.x < -0.20 and c.z < 0.80),
        ("UpperLeg.R", lambda c: c.x < -0.115),
        ("Tail2", lambda c: c.y > 0.690),
        ("Tail1", lambda c: c.y > 0.415),
        ("Head", lambda c: c.y < -0.480),
        ("Neck", lambda c: c.y < -0.335),
        ("Chest", lambda c: c.y < -0.070),
        ("Spine", lambda c: c.y < 0.175),
        ("Hips", lambda c: True),
    ]
    auto_groups(mesh, ao, rules)

    set_scene_frames(96)

    # --- idle: ほとんど動かず、頭と尾だけ不気味に揺れる ---
    a = Anim(ao, "idle", 96)
    N = 8
    for k in range(N + 1):
        f = 1 + k * 95.0 / N
        t = k / float(N)
        w = 2 * math.pi * t
        a.keyw(f, "Spine", 'X', R(1.5) * math.sin(w))
        a.keyw_mul(f, "Chest", [('X', R(2.0) * math.sin(w)), ('Z', R(2.5) * math.sin(w * 0.5))])
        a.keyw_mul(f, "Neck", [('Z', R(6.0) * math.sin(w * 0.5)), ('X', R(-3.0))])
        a.keyw_mul(f, "Head", [('Z', R(-11.0) * math.sin(w * 0.5)),
                               ('Y', R(9.0) * math.sin(w * 0.25))])
        a.keyw_mul(f, "Tail1", [('Z', R(13.0) * math.sin(w)), ('X', R(-10.0))])
        a.keyw_mul(f, "Tail2", [('Z', R(22.0) * math.sin(w + 1.1)), ('X', R(-16.0))])
        for bn in ("UpperArm.L", "UpperArm.R", "UpperLeg.L", "UpperLeg.R",
                   "LowerArm.L", "LowerArm.R", "LowerLeg.L", "LowerLeg.R"):
            a.keyw(f, bn, 'X', 0.0)
        a.keyw_loc(f, "Hips", (0, 0, 0.012 * math.sin(w)))
    a.finish()

    # --- crawl: 4 本の長い手足を交互に前へ出して這う ---
    a = Anim(ao, "crawl", 40)
    N = 8
    for k in range(N + 1):
        f = 1 + k * 39.0 / N
        t = k / float(N)
        w = 2 * math.pi * t
        limbs = (("UpperArm.L", "LowerArm.L", 0.0),
                 ("UpperLeg.R", "LowerLeg.R", 0.0),
                 ("UpperArm.R", "LowerArm.R", math.pi),
                 ("UpperLeg.L", "LowerLeg.L", math.pi))
        for (up, lo, ph) in limbs:
            sw = math.sin(w + ph)
            reach = max(0.0, sw)
            a.keyw_mul(f, up, [('X', R(-34) * sw), ('Z', R(9) * reach)])
            a.keyw(f, lo, 'X', R(30) * sw + R(-12) * reach)
        # 背骨のうねり
        a.keyw_mul(f, "Hips", [('Z', R(-8) * math.sin(w)), ('X', R(3) * math.cos(w))])
        a.keyw(f, "Spine", 'Z', R(10) * math.sin(w + 0.5))
        a.keyw(f, "Chest", 'Z', R(-9) * math.sin(w + 1.0))
        a.keyw_mul(f, "Neck", [('X', R(-10)), ('Z', R(6) * math.sin(w + 1.6))])
        a.keyw_mul(f, "Head", [('X', R(12)), ('Z', R(-8) * math.sin(w + 1.6))])
        a.keyw_loc(f, "Hips", (0, 0, -0.045 + 0.030 * abs(math.cos(w))))
        a.keyw_mul(f, "Tail1", [('Z', R(20) * math.sin(w)), ('X', R(-6))])
        a.keyw_mul(f, "Tail2", [('Z', R(28) * math.sin(w + 1.0)), ('X', R(-10))])
    a.finish()

    emit("kasha", [ao, mesh], animations=True)


def main():
    build_cat()
    build_kasha()
    build_npc_boss()
    build_npc_son()
    build_npc_granddaughter()
    build_body_risen()
    dump_report()


if __name__ == "__main__":
    main()
