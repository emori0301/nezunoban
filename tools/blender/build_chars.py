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
                    ring, Anim, BONES, set_scene_frames)

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

HUMAN_RULES_Z = [
    # (bone, 判定) 上から順に最初に当たったものを使う
]


def human_mesh(name, spec):
    """spec:
        cloth   : 服のマテリアル
        skin    : 肌のマテリアル
        face    : 頭のマテリアル(顔テクスチャ、左半分が顔)
        hair    : 髪のマテリアル
        s       : 全体の倍率(1.0 = 身長 1.77m)
        belly   : 腹の出っ張り(0..1)
        skirt   : True ならワンピース(腰から膝までスカート、脛は素足)
        shoulder: 肩幅の倍率
    """
    s = spec["s"]
    cloth = spec["cloth"]
    skin = spec["skin"]
    face = spec["face"]
    hair = spec["hair"]
    belly = spec.get("belly", 0.0)
    skirt = spec.get("skirt", False)
    shw = spec.get("shoulder", 1.0)
    shoe = spec.get("shoe", cloth)

    b = Builder(name)

    def S(*v):
        return tuple(x * s for x in v)

    def put(geo, mat, uvs=1.0, uv=None):
        b.add(geo, mat, uvscale=uvs, uv=uv)

    # ---- 脚 ----
    for sx in (-1, 1):
        x = sx * 0.100
        legmat = skin if skirt else cloth
        # 靴
        put(box_mm(*S(x - 0.058, x + 0.058, -0.115, 0.075, 0.0, 0.052)), shoe, 8)
        put(box_mm(*S(x - 0.052, x + 0.052, -0.090, 0.060, 0.052, 0.082)), shoe, 8)
        # 脛(2 段)
        put(cyl(*S(0.062), S(0.21)[0], 8, S(x, -0.010, 0.185), r_top=S(0.058)[0]), legmat, 7)
        put(cyl(*S(0.058), S(0.21)[0], 8, S(x, -0.004, 0.395), r_top=S(0.070)[0]), legmat, 7)
        # 腿(2 段)
        put(cyl(*S(0.078), S(0.22)[0], 8, S(x, 0.0, 0.610), r_top=S(0.086)[0]),
            skin if (skirt and False) else cloth, 6)
        put(cyl(*S(0.086), S(0.22)[0], 8, S(x, 0.0, 0.830), r_top=S(0.094)[0]), cloth, 6)

    # ---- 腰 ----
    put(box_taper(*S(0.335, 0.225, 0.310, 0.215, 0.16), c=S(0, 0, 0.955)), cloth, 4)
    skirt_idx = []
    if skirt:
        # スカートは脚と z が重なるので、座標ではなくインデックスで Hips に固定する
        i0 = b.count()
        put(box_taper(*S(0.330, 0.230, 0.460, 0.330, 0.42), c=S(0, 0, 0.83)), cloth, 2.5)
        skirt_idx = list(range(i0, b.count()))
    b.skirt_idx = skirt_idx

    # ---- 胴 ----
    bd = 0.235 + belly * 0.115
    put(box_taper(*S(0.310, 0.215, 0.340, bd, 0.14), c=S(0, -belly * 0.015, 1.105)), cloth, 4)
    put(box_taper(*S(0.340, bd, 0.355, bd - belly * 0.05, 0.15), c=S(0, -belly * 0.018, 1.250)),
        cloth, 4)
    put(box_taper(*S(0.355, 0.235, 0.375, 0.230, 0.14), c=S(0, 0, 1.395)), cloth, 4)
    # 肩
    put(box_taper(*S(0.415 * shw, 0.230, 0.395 * shw, 0.215, 0.10), c=S(0, 0, 1.425)), cloth, 4)

    # ---- 襟と前あわせ ----
    put(box_mm(*S(-0.075, 0.075, -0.125, -0.095, 1.400, 1.470)), skin, 10)     # 首元
    put(box_taper(*S(0.190, 0.060, 0.150, 0.050, 0.075), c=S(0, -0.095, 1.442)), cloth, 8)
    if not skirt:
        for sx in (-1, 1):
            v, f = box(*S(0.085, 0.030, 0.230), c=(0, 0, 0))
            v = tr(v, rot=(0, sx * 0.16, 0), t=S(sx * 0.068, -0.118, 1.300))
            put((v, f), cloth, 8)
        # ネクタイ
        put(box_mm(*S(-0.026, 0.026, -0.134, -0.122, 1.170, 1.390)),
            spec.get("tie", cloth), 10)
        put(box_mm(*S(-0.030, 0.030, -0.138, -0.124, 1.390, 1.425)),
            spec.get("tie", cloth), 14)

    # ---- 首と頭 ----
    put(cyl(*S(0.052), S(0.13)[0], 8, S(0, -0.005, 1.505)), skin, 10)
    put(box_taper(*S(0.175, 0.195, 0.205, 0.225, 0.205), c=S(0, -0.010, 1.672)),
        face, uv=HEAD_UV)
    # 頭頂と後頭部の髪
    put(box_taper(*S(0.208, 0.228, 0.165, 0.180, 0.045), c=S(0, -0.010, 1.792)), hair, 8)
    put(box_mm(*S(-0.104, 0.104, 0.030, 0.108, 1.570, 1.780)), hair, 6)
    if spec.get("long_hair"):
        put(box_mm(*S(-0.112, 0.112, 0.045, 0.125, 1.330, 1.600)), hair, 5)
        for sx in (-1, 1):
            put(box_mm(*S(sx * 0.100 - 0.024, sx * 0.100 + 0.024, -0.100, 0.110,
                          1.420, 1.790)), hair, 6)
    # 耳
    for sx in (-1, 1):
        put(box_mm(*S(sx * 0.104 - 0.012, sx * 0.104 + 0.012, -0.030, 0.030,
                      1.630, 1.700)), skin, 14)
    # 鼻
    put(box_mm(*S(-0.018, 0.018, -0.132, -0.112, 1.655, 1.690)), skin, 16)

    # ---- 腕 ----
    for sx in (-1, 1):
        x = sx * 0.235
        put(box_taper(*S(0.105 * shw, 0.105, 0.095, 0.095, 0.09), c=S(x * 0.92, 0, 1.415)),
            cloth, 8)
        put(cyl(*S(0.049), S(0.14)[0], 8, S(x, 0, 1.300), r_top=S(0.046)[0]), cloth, 8)
        put(cyl(*S(0.046), S(0.13)[0], 8, S(x + sx * 0.010, 0, 1.165), r_top=S(0.044)[0]),
            cloth, 8)
        put(cyl(*S(0.044), S(0.13)[0], 8, S(x + sx * 0.018, 0, 1.035), r_top=S(0.041)[0]),
            cloth, 8)
        put(cyl(*S(0.041), S(0.12)[0], 8, S(x + sx * 0.024, 0, 0.910), r_top=S(0.038)[0]),
            cloth, 8)
        # 手
        put(box_taper(*S(0.070, 0.048, 0.062, 0.042, 0.115), c=S(x + sx * 0.028, 0, 0.792)),
            skin, 10)
    return b


def human_groups(mesh_obj, arm_obj, s, skirt=False, force_idx=None):
    def zz(co):
        return co.z / s

    def xx(co):
        return co.x / s

    rules = [
        ("Head", lambda c: zz(c) >= 1.555),
        ("Neck", lambda c: zz(c) >= 1.455),
        ("UpperArm.L", lambda c: xx(c) > 0.185 and zz(c) >= 1.135),
        ("LowerArm.L", lambda c: xx(c) > 0.185 and zz(c) >= 0.70),
        ("UpperArm.R", lambda c: xx(c) < -0.185 and zz(c) >= 1.135),
        ("LowerArm.R", lambda c: xx(c) < -0.185 and zz(c) >= 0.70),
        ("Chest", lambda c: zz(c) >= 1.245),
        ("Spine", lambda c: zz(c) >= 1.085),
        ("Hips", lambda c: zz(c) >= 0.915 or (skirt and zz(c) >= 0.66)),
        ("UpperLeg.L", lambda c: xx(c) >= 0 and zz(c) >= 0.50),
        ("UpperLeg.R", lambda c: xx(c) < 0 and zz(c) >= 0.50),
        ("LowerLeg.L", lambda c: xx(c) >= 0),
        ("LowerLeg.R", lambda c: True),
    ]
    return auto_groups(mesh_obj, arm_obj, rules, force_idx=force_idx)


ARMS = ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]
LEGS = ["UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R"]
SPINE = ["Hips", "Spine", "Chest", "Neck", "Head"]
ALL_B = SPINE + ARMS + LEGS


def anim_human_idle(ao, length=90):
    """呼吸で上下 + わずかな重心移動。"""
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
            a.keyw_mul(f, bn, [('X', R(2.0) * ph), ('Y', sgn * R(3.0))])
        for bn in ("LowerArm.L", "LowerArm.R"):
            a.keyw(f, bn, 'X', R(-9.0) + R(1.5) * ph)
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
        sl = math.sin(w)              # 左脚: 正 = 前
        sr = -sl
        # 膝は後ろに振り出すときに曲げる
        kl = max(0.0, -math.sin(w + 0.9)) * R(38)
        kr = max(0.0, -math.sin(w + math.pi + 0.9)) * R(38)
        a.keyw(f, "UpperLeg.L", 'X', R(-amp) * sl)
        a.keyw(f, "UpperLeg.R", 'X', R(-amp) * sr)
        a.keyw(f, "LowerLeg.L", 'X', kl)
        a.keyw(f, "LowerLeg.R", 'X', kr)
        # 腕は脚と逆位相
        a.keyw_mul(f, "UpperArm.L", [('X', R(amp * 0.55) * sl), ('Y', R(4))])
        a.keyw_mul(f, "UpperArm.R", [('X', R(amp * 0.55) * sr), ('Y', R(-4))])
        a.keyw(f, "LowerArm.L", 'X', R(-14) - R(10) * max(0.0, sl))
        a.keyw(f, "LowerArm.R", 'X', R(-14) - R(10) * max(0.0, sr))
        # 腰の上下と捻り
        a.keyw_loc(f, "Hips", (0.0, 0.0, -0.022 * abs(math.cos(w))))
        a.keyw_mul(f, "Hips", [('Z', R(-5) * sl), ('Y', R(2.5) * math.cos(w))])
        a.keyw_mul(f, "Chest", [('Z', R(5) * sl), ('X', R(2.0))])
        a.keyw(f, "Neck", 'X', R(-1.5))
        a.keyw_mul(f, "Head", [('Z', R(-2) * sl)])
    return a.finish()


def build_human(name, spec):
    """spec の中のマテリアルは reset_scene() の後に作ること(参照が無効になる)。"""
    s = spec["s"]
    b = human_mesh(name, spec)
    skirt_idx = getattr(b, "skirt_idx", [])
    mesh = b.build()
    ao = make_armature(name, BONES, scale=s)
    human_groups(mesh, ao, s, spec.get("skirt", False),
                 force_idx={"Hips": skirt_idx} if skirt_idx else None)
    set_scene_frames(90)
    anim_human_idle(ao)
    anim_human_walk(ao)
    emit(name, [ao, mesh], animations=True)


def build_npc_boss():
    reset_scene()
    setup_fps()
    build_human("npc_boss", dict(
        s=0.945, belly=0.85, shoulder=1.06,
        cloth=material("BossSuit", "suit_black", color=(0.11, 0.11, 0.13), rough=0.85),
        tie=material("BossTie", "metal_dark", color=(0.18, 0.16, 0.20), rough=0.7),
        skin=material("BossSkin", "skin_pale", color=(0.70, 0.57, 0.48), rough=0.8),
        face=material("BossFace", "face_boss", color=(0.75, 0.62, 0.53), rough=0.8),
        hair=material("BossHair", "metal_dark", color=(0.11, 0.10, 0.10), rough=0.9),
        shoe=material("BossShoe", "car_black", color=(0.07, 0.07, 0.08), rough=0.35),
    ))


def build_npc_son():
    reset_scene()
    setup_fps()
    build_human("npc_son", dict(
        s=0.965, belly=0.45, shoulder=1.0,
        cloth=material("SonJumper", "jumper", color=(0.20, 0.23, 0.29), rough=0.9),
        tie=material("SonShirt", "white_cloth", color=(0.72, 0.70, 0.64), rough=0.95),
        skin=material("SonSkin", "skin_pale", color=(0.74, 0.55, 0.46), rough=0.8),
        face=material("SonFace", "face_son", color=(0.78, 0.58, 0.48), rough=0.8),
        hair=material("SonHair", "metal_dark", color=(0.14, 0.13, 0.12), rough=0.95),
        shoe=material("SonShoe", "metal_dark", color=(0.16, 0.15, 0.14), rough=0.85),
    ))


def build_npc_granddaughter():
    reset_scene()
    setup_fps()
    build_human("npc_granddaughter", dict(
        s=0.900, belly=0.0, shoulder=0.90, skirt=True, long_hair=True,
        cloth=material("GdDress", "dress_black", color=(0.09, 0.09, 0.11), rough=0.92),
        skin=material("GdSkin", "skin_pale", color=(0.80, 0.68, 0.61), rough=0.75),
        face=material("GdFace", "face_granddaughter", color=(0.82, 0.70, 0.63), rough=0.75),
        hair=material("GdHair", "suit_black", color=(0.07, 0.07, 0.08), rough=0.85),
        shoe=material("GdShoe", "car_black", color=(0.07, 0.07, 0.08), rough=0.4),
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
