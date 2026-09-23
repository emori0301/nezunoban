"""人物 3 体を MPFB2(MakeHuman Plugin for Blender)の人体から作る。

    blender --background --python tools/blender/build_humans_mpfb.py

手続き的な筒モデルでは「人間の体型」にならなかったので、素体を MPFB2 に任せる。
MPFB2 は Blender の Extensions から入れる(初回のみ tools/blender/install_mpfb.py)。

流れ:
  1. HumanService.create_human() で年齢・性別・体重・身長のマクロから素体を作る
  2. game_engine リグ(53 ボーン、ウェイト付き)を入れる
  3. ヘルパー形状を消して Decimate で 3000 頂点程度に落とす
  4. 服の厚みを法線方向に出し、部位ごとにマテリアルを割る
  5. 顔だけ正面から平面投影して、自作の写真劣化テクスチャを貼る
  6. 髪をかぶせる
  7. 既存の 5 アニメ(idle/walk/sit/sit_floor/sleep)を game_engine のボーン名に
     読み替えて付ける
  8. Godot の -Z 正面に合わせて 180 度回し、glb に出す

ライセンス: MPFB2 本体は GPL-3.0-or-later。生成される素体は MakeHuman の
ベースメッシュとターゲット由来で CC0。詳細は docs/previews/models_notes.md。
"""

import os
import sys
import math
import importlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import bmesh
import addon_utils
from mathutils import Vector

from common import (reset_scene, material, Builder, emit, dump_report, box_taper,
                    tube, cyl, tr, Anim, set_scene_frames, TEX_DIR)
import build_chars as BC

MPFB = "bl_ext.user_default.mpfb"
R = math.radians

# game_engine リグのボーン名。自前のアニメはこの名前に読み替えて付ける。
GE = {
    "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_03",
    "Neck": "neck_01", "Head": "head",
    "UpperArm.L": "upperarm_l", "UpperArm.R": "upperarm_r",
    "LowerArm.L": "lowerarm_l", "LowerArm.R": "lowerarm_r",
    "UpperLeg.L": "thigh_l", "UpperLeg.R": "thigh_r",
    "LowerLeg.L": "calf_l", "LowerLeg.R": "calf_r",
}
# 素体は A ポーズ(上腕が 41 度開いている)。腕を体側へ下ろすための基準回転。
ARM_DOWN = 41.0


def ensure_mpfb():
    addon_utils.enable(MPFB, default_set=True, persistent=True)
    hs = importlib.import_module(MPFB + ".services.humanservice").HumanService
    ts = importlib.import_module(MPFB + ".services.targetservice").TargetService
    return hs, ts


# ---------------------------------------------------------------- 素体

def make_body(macro, height_m):
    """マクロから素体を作り、リグを入れて (mesh, armature) を返す。"""
    HS, TS = ensure_mpfb()
    d = TS.get_default_macro_info_dict()
    d.update({k: v for k, v in macro.items() if k != "race"})
    d["race"] = macro.get("race", {"african": 0.0, "asian": 1.0, "caucasian": 0.0})
    body = HS.create_human(mask_helpers=True, detailed_helpers=False,
                           extra_vertex_groups=True, feet_on_ground=True,
                           scale=0.1, macro_detail_dict=d)
    arm = HS.add_builtin_rig(body, "game_engine", import_weights=True)

    # ヘルパー形状(服合わせ用の余分なメッシュ)を削除
    for m in list(body.modifiers):
        if m.type == 'MASK':
            body.modifiers.remove(m)
    gi = {g.name: g.index for g in body.vertex_groups}
    drop = [gi[n] for n in ("HelperGeometry", "JointCubes") if n in gi]
    if drop:
        bm = bmesh.new()
        bm.from_mesh(body.data)
        dl = bm.verts.layers.deform.verify()
        kill = [v for v in bm.verts if any(i in v[dl] for i in drop)]
        bmesh.ops.delete(bm, geom=kill, context='VERTS')
        bm.to_mesh(body.data)
        bm.free()
        body.data.update()

    # 身長を合わせる(マクロだけでは細かく決まらないので最後に等倍スケール)
    bpy.context.view_layer.update()
    zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
    cur = max(zs) - min(zs)
    if cur > 0.01:
        s = height_m / cur
        for o in (body, arm):
            o.scale = (s, s, s)
        bpy.ops.object.select_all(action='DESELECT')
        body.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # 足を床に乗せる
    bpy.context.view_layer.update()
    zmin = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    for o in (body, arm):
        o.location.z -= zmin
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    bpy.context.view_layer.update()
    return body, arm


def bake_shape(obj):
    """マクロはシェイプキーとして乗っているので、形に焼き込む。
    シェイプキーが残っていると Decimate が適用できない。"""
    HS, TS = ensure_mpfb()
    bpy.context.view_layer.objects.active = obj
    try:
        TS.bake_targets(obj)
    except Exception as e:
        print("  bake_targets failed (%s), falling back to operator" % e)
        try:
            bpy.ops.mpfb.bake_shapekeys()
        except Exception as e2:
            print("  operator failed too:", e2)
    me = obj.data
    if me.shape_keys:
        # それでも残っていたら、現在の形を頂点に書き戻してキーを消す
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg).to_mesh()
        co = [v.co.copy() for v in ev.vertices]
        obj.evaluated_get(dg).to_mesh_clear()
        obj.shape_key_clear()
        for i, c in enumerate(co):
            if i < len(me.vertices):
                me.vertices[i].co = c
    print("  shape keys after bake:", bool(me.shape_keys))


def decimate(obj, target_verts):
    """頂点数を target_verts 程度まで落とす(ウェイトは保たれる)。"""
    n = len(obj.data.vertices)
    if n <= target_verts:
        return
    mod = obj.modifiers.new("Decimate", 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = max(0.02, float(target_verts) / n)
    mod.use_collapse_triangulate = False
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


# ---------------------------------------------------------------- 部位分け

def body_regions(obj):
    """高さと位置から、頭・首・胴・腕・手・脚・足に分ける。
    戻り値は {region: set(polygon index)}。MakeHuman の頂点グループには
    部位別のものが無いので、姿勢が分かっている素体の形から判定する。"""
    me = obj.data
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    H = z1 - z0
    xs = [abs(v.co.x) for v in me.vertices]
    xmax = max(xs)

    def h(z):
        return (z - z0) / H

    reg = {k: set() for k in ("head", "neck", "torso", "hand", "leg", "foot")}
    for p in me.polygons:
        c = p.center
        hh = h(c.z)
        ax = abs(c.x)
        if hh >= 0.874:
            reg["head"].add(p.index)
        elif hh >= 0.836:
            reg["neck"].add(p.index)
        elif ax > xmax * 0.74 and hh < 0.66:
            reg["hand"].add(p.index)          # A ポーズなので手は外側の低い位置
        elif hh >= 0.455:
            reg["torso"].add(p.index)
        elif hh >= 0.045:
            reg["leg"].add(p.index)
        else:
            reg["foot"].add(p.index)
    return reg, (z0, z1, xmax)


def inflate(obj, poly_idx, amount):
    """指定の面の頂点を法線方向へ押し出して、服の厚みを作る。"""
    me = obj.data
    me.calc_loop_triangles()
    vids = set()
    for i in poly_idx:
        vids.update(me.polygons[i].vertices)
    for vi in vids:
        v = me.vertices[vi]
        v.co = v.co + v.normal * amount


# ---------------------------------------------------------------- UV と顔

def set_uvs(obj, reg, bounds, face_rect):
    """UV を貼り直す。顔だけ正面から平面投影、ほかは部位ごとに箱投影。"""
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uvl = me.uv_layers.new(name="UVMap")
    data = uvl.data
    z0, z1, xmax = bounds
    fx0, fx1, fz0, fz1 = face_rect

    for p in me.polygons:
        is_face = p.index in reg["face"]
        n = p.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if is_face:
                u = 1.0 - (co.x - fx0) / max(fx1 - fx0, 1e-6)
                v = (co.z - fz0) / max(fz1 - fz0, 1e-6)
                data[li].uv = (min(max(u, 0.0), 1.0), min(max(v, 0.0), 1.0))
            else:
                s = 1.6
                if ax == 2:
                    data[li].uv = (co.x * s, co.y * s)
                elif ax == 1:
                    data[li].uv = (co.x * s, co.z * s)
                else:
                    data[li].uv = (co.y * s, co.z * s)


def find_face(obj, reg, bounds):
    """頭のうち「顎から生え際まで、前を向いている面」を顔とする。"""
    me = obj.data
    z0, z1, xmax = bounds
    head = [me.polygons[i] for i in reg["head"]]
    if not head:
        return set(), (0, 1, 0, 1)
    hz = [p.center.z for p in head]
    htop = max(hz)
    hbot = min(hz)
    hh = htop - hbot
    # 顎 = 頭の下から 8%、生え際 = 下から 78%
    zc0 = hbot + hh * 0.06
    zc1 = hbot + hh * 0.76
    ys = [p.center.y for p in head]
    ymid = (min(ys) + max(ys)) * 0.5
    face = set()
    for p in head:
        if zc0 <= p.center.z <= zc1 and p.center.y < ymid and p.normal.y < -0.25:
            face.add(p.index)
    if not face:
        return set(), (0, 1, 0, 1)
    xs = [me.vertices[vi].co.x for i in face for vi in me.polygons[i].vertices]
    zs = [me.vertices[vi].co.z for i in face for vi in me.polygons[i].vertices]
    pad_x = (max(xs) - min(xs)) * 0.04
    pad_z = (max(zs) - min(zs)) * 0.03
    return face, (min(xs) - pad_x, max(xs) + pad_x, min(zs) - pad_z, max(zs) + pad_z)


# ---------------------------------------------------------------- 髪

def add_hair(name, obj, reg, bounds, hair_mat, spec):
    """頭の上半分に沿わせた髪。素体の頭の形から半径を測って被せる。"""
    me = obj.data
    head_v = [me.vertices[vi].co for i in reg["head"] for vi in me.polygons[i].vertices]
    if not head_v:
        return None
    hz = [c.z for c in head_v]
    htop, hbot = max(hz), min(hz)
    cx = sum(c.x for c in head_v) / len(head_v)
    cy = sum(c.y for c in head_v) / len(head_v)

    def radius_at(z, tol):
        sel = [c for c in head_v if abs(c.z - z) < tol]
        if not sel:
            return 0.08, 0.09, cy
        rx = max(abs(c.x - cx) for c in sel)
        ys = [c.y for c in sel]
        return rx, (max(ys) - min(ys)) * 0.5, (max(ys) + min(ys)) * 0.5

    hh = htop - hbot
    z_bot = hbot + hh * (0.72 if not spec.get("long_hair") else 0.70)
    rows = []
    for t in (1.0, 0.94, 0.86, 0.74, 0.60, 0.0):
        z = z_bot + (htop - z_bot) * t
        rx, ry, ccy = radius_at(z, hh * 0.05)
        grow = 1.04 + 0.025 * (1.0 - t)
        back = spec.get("hair_back", 0.0)
        rows.append((z + (0.004 if t > 0.98 else 0.0), cx, ccy + back,
                     max(rx * grow, 0.012), max(ry * grow, 0.012), t))
    b = Builder("Hair_" + name)
    b.add(tube([(cx2, cy2, z, rx, ry, v) for (z, cx2, cy2, rx, ry, v) in rows],
               n=12, cap_end=False), hair_mat, uvscale=6.0, smooth=True)
    if spec.get("long_hair"):
        rx, ry, ccy = radius_at(z_bot, hh * 0.06)
        long_rows = []
        for (t, dz, g, back) in ((1.0, 0.00, 1.02, 0.010), (0.66, -0.09, 1.10, 0.020),
                                 (0.33, -0.19, 1.16, 0.028), (0.0, -0.28, 1.20, 0.034)):
            long_rows.append((cx, ccy + back, z_bot + dz, rx * g, ry * g * 0.94, t))
        b.add(tube(long_rows, n=10, cap_start=False), hair_mat, uvscale=3.4, smooth=True)
    ob = b.build()
    return ob


# ---------------------------------------------------------------- アニメ

class RemapAnim(Anim):
    """自前のボーン名で書いたアニメを、別のリグのボーン名へ読み替える。"""

    def __init__(self, arm_obj, name, length, remap):
        self.remap = remap
        super().__init__(arm_obj, name, length)

    def key(self, frame, bone, loc=None, rot=None, scale=None):
        super().key(frame, self.remap.get(bone, bone), loc=loc, rot=rot, scale=scale)

    def keyw(self, frame, bone, axis, angle):
        super().keyw(frame, self.remap.get(bone, bone), axis, angle)

    def keyw_mul(self, frame, bone, pairs):
        super().keyw_mul(frame, self.remap.get(bone, bone), pairs)

    def keyw_loc(self, frame, bone, world_vec):
        super().keyw_loc(frame, self.remap.get(bone, bone), world_vec)


def with_arm_down(fn):
    """A ポーズの上腕を体側へ下ろす基準回転を足したアニメを作る。"""
    def wrapped(ao, *a, **kw):
        orig_mul = RemapAnim.keyw_mul
        orig_w = RemapAnim.keyw

        def mul(self, f, bone, pairs):
            if bone.startswith("UpperArm."):
                sgn = 1.0 if bone.endswith(".L") else -1.0
                pairs = list(pairs) + [('Y', R(ARM_DOWN) * sgn)]
            orig_mul(self, f, bone, pairs)

        def one(self, f, bone, axis, angle):
            if bone.startswith("UpperArm."):
                mul(self, f, bone, [(axis, angle)])
            else:
                orig_w(self, f, bone, axis, angle)

        RemapAnim.keyw_mul = mul
        RemapAnim.keyw = one
        try:
            return fn(ao, *a, **kw)
        finally:
            RemapAnim.keyw_mul = orig_mul
            RemapAnim.keyw = orig_w
    return wrapped


def build_anims(ao):
    """build_chars.py の 5 アニメを game_engine のボーン名で作り直す。"""
    orig = BC.Anim
    BC.Anim = lambda a, n, l: RemapAnim(a, n, l, GE)
    try:
        for fn in (BC.anim_human_idle, BC.anim_human_walk, BC.anim_human_sit,
                   BC.anim_human_sit_floor, BC.anim_human_sleep):
            with_arm_down(fn)(ao)
    finally:
        BC.Anim = orig


# ---------------------------------------------------------------- 組み立て

SPECS = {
    "npc_boss": dict(
        height=1.68, verts=3000,
        macro={"gender": 0.94, "age": 0.80, "muscle": 0.38, "weight": 0.74,
               "height": 0.40, "proportions": 0.45},
        jacket=0.016, trouser=0.011, hair_back=0.006, long_hair=False,
        tex=dict(face="face_boss", skin="skin_boss", torso="torso_suit",
                 leg="suit_black", shoe="shoe_leather", hair="hair_thin"),
    ),
    "npc_son": dict(
        height=1.72, verts=3000,
        macro={"gender": 0.90, "age": 0.76, "muscle": 0.46, "weight": 0.60,
               "height": 0.50, "proportions": 0.50},
        jacket=0.019, trouser=0.013, hair_back=0.002, long_hair=False,
        tex=dict(face="face_son", skin="skin_son", torso="torso_jumper",
                 leg="jumper", shoe="shoe_leather", hair="hair_salt"),
    ),
    "npc_granddaughter": dict(
        height=1.60, verts=3000,
        macro={"gender": 0.06, "age": 0.32, "muscle": 0.38, "weight": 0.42,
               "height": 0.42, "proportions": 0.58, "cupsize": 0.45},
        jacket=0.012, trouser=0.0, hair_back=0.004, long_hair=True,
        tex=dict(face="face_granddaughter", skin="skin_gd", torso="torso_dress",
                 leg="skin_gd", shoe="shoe_leather", hair="hair_long"),
    ),
}


def build_one(name):
    spec = SPECS[name]
    reset_scene()
    BC.setup_fps()
    t = spec["tex"]
    m_face = material(name + "_Face", t["face"], rough=0.8)
    m_skin = material(name + "_Skin", t["skin"], rough=0.8)
    m_torso = material(name + "_Cloth", t["torso"], rough=0.9)
    m_leg = material(name + "_Leg", t["leg"], rough=0.9)
    m_shoe = material(name + "_Shoe", t["shoe"], rough=0.45)
    m_hair = material(name + "_Hair", t["hair"], rough=0.9)

    body, arm = make_body(spec["macro"], spec["height"])
    body.name = name
    arm.name = name + "_rig"

    bake_shape(body)
    decimate(body, spec["verts"])
    reg, bounds = body_regions(body)
    face, face_rect = find_face(body, reg, bounds)
    reg["face"] = face
    reg["head"] -= face

    # 服の厚み(素体は裸なので、着ている部分を法線方向へ膨らませる)
    if spec["jacket"] > 0:
        inflate(body, reg["torso"], spec["jacket"])
    if spec["trouser"] > 0:
        inflate(body, reg["leg"], spec["trouser"])
    inflate(body, reg["foot"], 0.007)

    set_uvs(body, reg, bounds, face_rect)

    me = body.data
    me.materials.clear()
    order = [m_skin, m_face, m_torso, m_leg, m_shoe, m_hair]
    for m in order:
        me.materials.append(m)
    slot = {"head": 0, "neck": 0, "hand": 0, "face": 1,
            "torso": 2, "leg": 3, "foot": 4}
    for key, idx in slot.items():
        for pi in reg.get(key, ()):
            me.polygons[pi].material_index = idx
    for p in me.polygons:
        p.use_smooth = True

    hair = add_hair(name, body, reg, bounds, m_hair, spec)
    if hair is not None:
        hair.parent = arm
        bpy.context.view_layer.update()
        hair.matrix_parent_inverse = arm.matrix_world.inverted()
        vg = hair.vertex_groups.new(name=GE["Head"])
        vg.add(list(range(len(hair.data.vertices))), 1.0, 'REPLACE')
        mod = hair.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm

    set_scene_frames(180)
    build_anims(arm)
    BC.face_godot_forward(arm)
    objs = [arm, body] + ([hair] if hair is not None else [])
    emit(name, objs, animations=True)


def main():
    only = None
    if "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1:]
        if rest:
            only = rest
    for n in (only or list(SPECS)):
        print("=== building", n, "===")
        build_one(n)
    dump_report()


if __name__ == "__main__":
    main()
