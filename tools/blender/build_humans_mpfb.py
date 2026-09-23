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
from mathutils import Vector, Matrix

from common import (reset_scene, material, Builder, emit, dump_report, box_taper,
                    tube, cyl, tr, Anim, set_scene_frames, TEX_DIR,
                    world_quat_from, add_chain_weights, add_rigid_weights,
                    bind_weights, box_mm)
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

def bake_transform(body, arm, scale, dz):
    """メッシュの頂点とボーンの位置を同じ変換で動かす。

    オブジェクトの location/scale を使って transform_apply すると、
    親子付け(メッシュはアーマチュアの子)のせいでズレる。データを直接動かす。
    """
    for v in body.data.vertices:
        c = v.co.copy() * scale
        c.z += dz
        v.co = c
    body.data.update()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for eb in arm.data.edit_bones:
        h, t = eb.head.copy() * scale, eb.tail.copy() * scale
        h.z += dz
        t.z += dz
        eb.head, eb.tail = h, t
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()


# scale=0.1 で作ったときの素体の身長(実測)。目標身長から生成スケールを逆算する。
BASE_HEIGHT_AT_01 = 1.695


def _spawn(macro, scale):
    HS, TS = ensure_mpfb()
    d = TS.get_default_macro_info_dict()
    d.update({k: v for k, v in macro.items() if k != "race"})
    d["race"] = macro.get("race", {"african": 0.0, "asian": 1.0, "caucasian": 0.0})
    return HS.create_human(mask_helpers=True, detailed_helpers=False,
                           extra_vertex_groups=True, feet_on_ground=False,
                           scale=scale, macro_detail_dict=d)


def _real_height(body):
    """ヘルパー形状を除いた実際の身長。"""
    gi = {g.name: g.index for g in body.vertex_groups}
    bad = {gi.get("HelperGeometry", -1), gi.get("JointCubes", -1)}
    zs = [v.co.z for v in body.data.vertices
          if not any(g.group in bad for g in v.groups)]
    return (max(zs) - min(zs)) if zs else 1.0


def make_body(macro, height_m):
    """マクロから素体を作り、リグを入れて (mesh, armature) を返す。

    MPFB の癖が 3 つある。
    - `feet_on_ground=True` はメッシュだけ持ち上げてリグを動かさず 0.8m ズレる
    - `add_builtin_rig` は MPFB 側の基準フレームで骨を作るので、先に頂点を
      動かしても骨は付いてこない
    - マクロはシェイプキーとして乗るので、素の頂点座標から身長は測れない

    なので **一度作って実身長を測り、生成スケールを直して作り直す**。
    足を床に乗せるのはアーマチュアの location でやる(メッシュは子)。
    """
    probe = _spawn(macro, 0.1)
    bake_shape(probe)
    h0 = _real_height(probe)
    for o in (probe, ):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)

    body = _spawn(macro, 0.1 * (height_m / max(h0, 0.01)))
    bake_shape(body)
    HS, _ = ensure_mpfb()
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
    bpy.context.view_layer.update()
    zs = [v.co.z for v in body.data.vertices]
    bz = [b.head_local.z for b in arm.data.bones] + [b.tail_local.z for b in arm.data.bones]
    print("    body z %+.3f..%+.3f (H %.3f)  bones z %+.3f..%+.3f" %
          (min(zs), max(zs), max(zs) - min(zs), min(bz), max(bz)))
    return body, arm


def feet_to_floor(body, arm):
    """アーマチュアの location で足を床(z=0)に乗せる。データは触らない。"""
    bpy.context.view_layer.update()
    zmin = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    arm.location.z -= zmin
    bpy.context.view_layer.update()


# レストポーズで真下(あるいは指定方向)へ向けたいボーンと、その向き
STRAIGHTEN = [
    ("upperarm_l", (0.0, 0.0, -1.0)), ("lowerarm_l", (0.0, 0.0, -1.0)),
    ("hand_l", (0.0, 0.0, -1.0)),
    ("upperarm_r", (0.0, 0.0, -1.0)), ("lowerarm_r", (0.0, 0.0, -1.0)),
    ("hand_r", (0.0, 0.0, -1.0)),
    ("thigh_l", (0.0, 0.0, -1.0)), ("calf_l", (0.0, 0.0, -1.0)),
    ("thigh_r", (0.0, 0.0, -1.0)), ("calf_r", (0.0, 0.0, -1.0)),
]


def straighten_rest(body, arm, verbose=False):
    """素体の A ポーズを「腕も脚も真下」に直して、それをレストポーズにする。

    自作のアニメは「腕が真下」を前提に書いてあるので、A ポーズのまま当てると
    肘から先がねじれる。レストポーズ自体を正立させれば、アニメはそのまま使える。

    親が既に回っている状態で子に回転を足すので、`matrix_local`(レスト)を
    基準にした変換では合わない。`pose_bone.matrix`(アーマチュア空間)を
    直接書き換えて、親子関係は Blender に解かせる。
    """
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()

    for bone_name, target in STRAIGHTEN:
        if bone_name not in arm.pose.bones:
            continue
        pb = arm.pose.bones[bone_name]
        cur = (pb.tail - pb.head)
        if cur.length < 1e-6:
            continue
        q = cur.normalized().rotation_difference(Vector(target))
        # pose_bone.matrix にそのまま掛けると「アーマチュア原点まわり」の回転に
        # なって骨の頭ごと動く。頭を原点に戻してから回して、戻す。
        head = pb.matrix.translation.copy()
        T = Matrix.Translation(head)
        pb.matrix = T @ q.to_matrix().to_4x4() @ T.inverted() @ pb.matrix
        bpy.context.view_layer.update()
        if verbose:
            d = (pb.tail - pb.head).normalized()
            print("    %-12s -> (%+.2f,%+.2f,%+.2f)" % (bone_name, d.x, d.y, d.z))

    bpy.ops.object.mode_set(mode='OBJECT')
    # メッシュ: 今の変形を焼いてから、モディファイアを付け直す
    bpy.context.view_layer.objects.active = body
    for m in [m for m in body.modifiers if m.type == 'ARMATURE']:
        bpy.ops.object.modifier_apply(modifier=m.name)
    nm = body.modifiers.new("Armature", 'ARMATURE')
    nm.object = arm
    # アーマチュア: 今のポーズをレストにする
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply()
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()


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

BONE_REGION = {
    "head": "head", "neck_01": "neck",
    "clavicle_l": "torso", "clavicle_r": "torso",
    "pelvis": "torso", "spine_01": "torso", "spine_02": "torso", "spine_03": "torso",
    "upperarm_l": "arm", "upperarm_r": "arm",
    "lowerarm_l": "arm", "lowerarm_r": "arm",
    "hand_l": "hand", "hand_r": "hand",
    "thigh_l": "leg", "thigh_r": "leg", "calf_l": "leg", "calf_r": "leg",
    "foot_l": "foot", "foot_r": "foot", "ball_l": "foot", "ball_r": "foot",
}
FINGER_PREFIX = ("index_", "middle_", "ring_", "pinky_", "thumb_")


def body_regions(obj):
    """リグの頂点グループから部位を決める。

    高さや x のしきい値で切ると、腰と手のように「高さが近くて別部位」の
    ところが混ざって、まだら模様になる。ウェイトを持つ骨で判定する。
    """
    me = obj.data
    g2r = {}
    for g in obj.vertex_groups:
        n = g.name
        if n in BONE_REGION:
            g2r[g.index] = BONE_REGION[n]
        elif n.startswith(FINGER_PREFIX):
            g2r[g.index] = "hand"
    reg = {k: set() for k in ("head", "neck", "torso", "arm", "hand", "leg", "foot")}
    for p in me.polygons:
        score = {}
        for vi in p.vertices:
            for g in me.vertices[vi].groups:
                r = g2r.get(g.group)
                if r:
                    score[r] = score.get(r, 0.0) + g.weight
        if score:
            reg[max(score, key=score.get)].add(p.index)
        else:
            reg["torso"].add(p.index)
    zs = [v.co.z for v in me.vertices]
    xs = [abs(v.co.x) for v in me.vertices]
    return reg, (min(zs), max(zs), max(xs))


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


# ---------------------------------------------------------------- 服

def torso_ids(body):
    """胴(腕を含まない)の頂点。断面を測るのに使う。"""
    names = ("pelvis", "spine_01", "spine_02", "spine_03")
    gi = {g.index for g in body.vertex_groups if g.name in names}
    return [v.index for v in body.data.vertices
            if any(g.group in gi and g.weight > 0.4 for g in v.groups)]


def group_ids(body, names, w=0.4):
    gi = {g.index for g in body.vertex_groups if g.name in names}
    return [v.index for v in body.data.vertices
            if any(g.group in gi and g.weight > w for g in v.groups)]


def section(body, ids, z, tol):
    """その高さでの胴の半幅・半奥行・中心 y。"""
    pts = [body.data.vertices[i].co for i in ids
           if abs(body.data.vertices[i].co.z - z) < tol]
    if len(pts) < 4:
        return 0.16, 0.11, 0.0
    rx = max(abs(p.x) for p in pts)
    ys = [p.y for p in pts]
    return max(rx, 0.05), max((max(ys) - min(ys)) * 0.5, 0.04), (max(ys) + min(ys)) * 0.5


def add_garment(name, body, arm, reg, mats, spec):
    """胴に着せる上着。骨の位置から着丈を決め、素体の断面を測って一回り
    大きい筒を作る。素体を膨らませるだけだと「黒いボディスーツ」に見えるので、
    裾・襟・ネクタイを形として足す。"""
    style = spec.get("garment")
    if not style:
        return []
    # 着丈の基準はメッシュから測る。
    # `add_builtin_rig` の骨は素体のスケールに完全には追従せず(頭の骨は
    # 身長を変えても同じ位置に来る)、骨基準だと背の低い人物で服が浮く。
    me = body.data
    nz = [me.vertices[vi].co.z for i in reg["neck"] for vi in me.polygons[i].vertices]
    lz = [me.vertices[vi].co.z for i in reg["leg"] for vi in me.polygons[i].vertices]
    fz = [me.vertices[vi].co.z for i in reg["foot"] for vi in me.polygons[i].vertices]
    if not nz or not lz:
        return []
    z_neck = min(nz)                             # 首の付け根 = 肩のライン
    z_hip = max(lz)                              # 腰(腿の付け根)
    z_foot = min(fz) if fz else min(lz)
    z_knee = z_foot + (z_hip - z_foot) * 0.52    # 膝
    span = max(z_neck - z_hip, 0.05)
    ids = torso_ids(body)
    if not ids:
        return []
    tol = span * 0.07

    def at(t, grow):
        """t=1 が首の付け根、t=0 が腰。"""
        z = z_hip + span * t
        rx, ry, cy = section(body, ids, z, tol)
        return (0.0, cy, z, rx * grow, ry * grow, t)

    b = Builder("Garment_" + name)
    if style == "dress":
        hem_z = z_knee + (z_hip - z_knee) * 0.10        # 膝丈
        # 一番上は首の穴。すぐ下を肩幅にして肩の傾斜を作る
        # (首の高さを肩幅のままにすると、頭が樽から出ているように見える)
        nr = section(body, group_ids(body, ("neck_01",), 0.5) or ids,
                     z_neck + span * 0.03, tol * 0.6)
        rows = [(0.0, nr[2], z_neck + span * 0.02, nr[0] * 1.25, nr[1] * 1.30, 1.06),
                at(0.94, 1.02), at(0.78, 1.06), at(0.52, 1.07), at(0.22, 1.09)]
        rx, ry, cy = section(body, ids, z_hip + span * 0.05, tol)
        rows.append((0.0, cy, z_hip, rx * 1.14, ry * 1.16, 0.0))
        rows.append((0.0, cy, hem_z, rx * 1.42, ry * 1.46, -0.6))
        b.add(tube(rows, n=14, cap_start=False), mats["cloth"], uvscale=2.6, smooth=True)
    else:
        nr = section(body, group_ids(body, ("neck_01",), 0.5) or ids,
                     z_neck + span * 0.03, tol * 0.6)
        rows = [(0.0, nr[2], z_neck + span * 0.02, nr[0] * 1.25, nr[1] * 1.30, 1.06),
                at(0.94, 1.03), at(0.76, 1.08), at(0.50, 1.10), at(0.22, 1.12)]
        rx, ry, cy = section(body, ids, z_hip + span * 0.05, tol)
        drop = span * (0.26 if style == "jacket" else 0.10)
        hem_z = z_hip - drop
        rows.append((0.0, cy, z_hip, rx * 1.14, ry * 1.16, 0.0))
        rows.append((0.0, cy, hem_z, rx * 1.16, ry * 1.18, -0.3))
        b.add(tube(rows, n=14, cap_start=False), mats["cloth"], uvscale=2.6, smooth=True)
        if style == "jumper":                            # 裾のリブ
            b.add(tube([(0.0, cy, hem_z + span * 0.06, rx * 1.15, ry * 1.17, 1.0),
                        (0.0, cy, hem_z - span * 0.01, rx * 1.08, ry * 1.10, 0.0)],
                       n=14, cap_start=False, cap_end=False),
                  mats["cloth"], uvscale=5.0, smooth=True)

    # 襟。肩幅ではなく **首の太さ** から測る(胴の断面だと襟が肩まで広がる)
    nids = group_ids(body, ("neck_01",), w=0.5)
    nrx, nry, ncy = section(body, nids or ids, z_neck + span * 0.04, tol * 0.6)
    b.add(tube([(0.0, ncy, z_neck + span * 0.09, nrx * 1.10, nry * 1.12, 1.0),
                (0.0, ncy, z_neck - span * 0.01, nrx * 1.34, nry * 1.40, 0.0)],
               n=12, cap_start=False, cap_end=False),
          mats["collar"], uvscale=7.0, smooth=True)

    if style == "jacket":
        srx, sry, scy = section(body, ids, z_neck - span * 0.10, tol)
        for sx in (-1, 1):
            v, f = box_taper(srx * 0.34, sry * 0.14, srx * 0.20, sry * 0.11,
                             span * 0.34,
                             (sx * srx * 0.32, scy - sry * 1.04, z_neck - span * 0.22))
            v = tr(v, rot=(0, sx * 0.18, 0),
                   pivot=(sx * srx * 0.32, scy - sry * 1.04, z_neck - span * 0.05))
            b.add((v, f), mats["cloth"], uvscale=4.0)
        # ネクタイ(結び目 + 剣先)
        b.add(box_taper(srx * 0.22, sry * 0.10, srx * 0.16, sry * 0.10, span * 0.08,
                        (0.0, scy - sry * 1.06, z_neck - span * 0.08)),
              mats["tie"], uvscale=9.0)
        b.add(box_taper(srx * 0.16, sry * 0.09, srx * 0.22, sry * 0.09, span * 0.40,
                        (0.0, scy - sry * 1.06, z_neck - span * 0.32)),
              mats["tie"], uvscale=6.0)

    ob = b.build()
    ob.parent = arm
    ob.matrix_parent_inverse = Matrix.Identity(4)
    g = {}
    chain = [("pelvis", z_hip - span * 0.10), ("spine_01", z_hip + span * 0.30),
             ("spine_03", z_hip + span * 0.72), ("neck_01", z_neck + span * 0.04)]
    add_chain_weights(g, ob, range(len(ob.data.vertices)), chain, lambda c: c.z)
    bind_weights(ob, arm, g)
    # bind_weights は matrix_parent_inverse を arm.matrix_world の逆で上書きする。
    # 素体と同じ「アーマチュアのローカル空間」に置きたいので戻す。
    ob.matrix_parent_inverse = Matrix.Identity(4)
    return [ob]


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
            fn(ao)
    finally:
        BC.Anim = orig


# ---------------------------------------------------------------- 組み立て

SPECS = {
    "npc_boss": dict(
        height=1.68, verts=2200,
        macro={"gender": 0.94, "age": 0.80, "muscle": 0.38, "weight": 0.74,
               "height": 0.40, "proportions": 0.45},
        jacket=0.006, trouser=0.008, hair_back=0.006, long_hair=False,
        garment="jacket",
        tex=dict(face="face_boss", skin="skin_boss", torso="torso_suit",
                 leg="suit_black", shoe="shoe_leather", hair="hair_thin"),
    ),
    "npc_son": dict(
        height=1.72, verts=2200,
        macro={"gender": 0.90, "age": 0.76, "muscle": 0.46, "weight": 0.60,
               "height": 0.50, "proportions": 0.50},
        jacket=0.008, trouser=0.010, hair_back=0.002, long_hair=False,
        garment="jumper",
        tex=dict(face="face_son", skin="skin_son", torso="torso_jumper",
                 leg="jumper", shoe="shoe_leather", hair="hair_salt"),
    ),
    "npc_granddaughter": dict(
        height=1.60, verts=2200,
        macro={"gender": 0.02, "age": 0.26, "muscle": 0.30, "weight": 0.34,
               "height": 0.40, "proportions": 0.62, "cupsize": 0.45,
               "firmness": 0.6},
        jacket=0.005, trouser=0.0, hair_back=0.004, long_hair=True,
        garment="dress",
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
    m_collar = material(name + "_Collar", t.get("collar", t["torso"]), rough=0.9)
    m_tie = material(name + "_Tie", t.get("tie", t["torso"]), rough=0.8)

    body, arm = make_body(spec["macro"], spec["height"])
    body.name = name
    arm.name = name + "_rig"

    straighten_rest(body, arm)
    feet_to_floor(body, arm)
    decimate(body, spec["verts"])
    reg, bounds = body_regions(body)
    face, face_rect = find_face(body, reg, bounds)
    reg["face"] = face
    reg["head"] -= face

    # 服の厚み(素体は裸なので、着ている部分を法線方向へ膨らませる)
    if spec["jacket"] > 0:
        inflate(body, reg["torso"] | reg["arm"], spec["jacket"])
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
            "torso": 2, "arm": 2, "leg": 3, "foot": 4}
    for key, idx in slot.items():
        for pi in reg.get(key, ()):
            me.polygons[pi].material_index = idx
    for p in me.polygons:
        p.use_smooth = True

    garments = add_garment(name, body, arm, reg, {
        "cloth": m_torso, "collar": m_collar, "tie": m_tie}, spec)
    hair = add_hair(name, body, reg, bounds, m_hair, spec)
    if hair is not None:
        hair.parent = arm
        hair.matrix_parent_inverse = Matrix.Identity(4)
        vg = hair.vertex_groups.new(name=GE["Head"])
        vg.add(list(range(len(hair.data.vertices))), 1.0, 'REPLACE')
        mod = hair.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm

    set_scene_frames(180)
    build_anims(arm)
    BC.face_godot_forward(arm)
    objs = [arm, body] + garments + ([hair] if hair is not None else [])
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
