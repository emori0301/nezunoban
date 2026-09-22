"""assets/models/*.glb を読み込んで 3/4 視点でレンダし docs/previews/ に出す。

blender --background --python tools/blender/render_previews.py -- [name ...]

全部を並べた docs/previews/contact_sheet.png も作る。
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Vector
from common import MODEL_DIR, PREVIEW_DIR, reset_scene, read_png, contact_sheet

RES = 256
SAMPLES = 24

# モデルごとのカメラ方向(既定は 3/4 手前上)
ANGLES = {
    "body_face": (0.10, -0.22, 1.60),      # 小窓から真上に近い角度
    "coffin": (1.0, -1.05, 0.80),
    "coffin_lid_open": (1.0, -1.05, 0.80),
    "futon": (0.7, -1.0, 1.15),
    "hanging_robe": (0.85, -1.40, 0.18),
    "body_risen": (1.55, 0.35, 0.45),
    "zabuton": (0.7, -1.0, 1.10),
    "slippers": (0.6, -1.0, 1.10),
    "matches": (0.6, -1.0, 1.05),
    "iei_frame": (0.55, -1.35, 0.45),
    "notice_board": (0.45, -1.4, 0.35),
    "wall_clock": (0.35, -1.45, 0.30),
    "door_wood": (0.9, -1.35, 0.35),
    "door_steel": (0.9, -1.35, 0.35),
    "window_frame": (0.9, -1.35, 0.35),
    "vending_machine": (0.7, -1.3, 0.45),
    # キャラは Blender の +Y が正面(glTF で Godot の -Z になる)ので、
    # カメラを +Y 側に置かないと後ろ姿になる
    "cat": (1.0, 1.25, 0.62),
    "kasha": (1.0, 1.25, 0.62),
    "npc_boss": (1.0, 1.25, 0.62),
    "npc_son": (1.0, 1.25, 0.62),
    "npc_granddaughter": (1.0, 1.25, 0.62),
}


def pick_engine():
    names = [i.identifier for i in
             bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    for want in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        if want in names:
            return want
    return "CYCLES"


def setup_world(dark=0.055):
    w = bpy.data.worlds.get("PreviewWorld") or bpy.data.worlds.new("PreviewWorld")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (dark, dark, dark * 1.12, 1.0)
    bg.inputs[1].default_value = 1.0
    bpy.context.scene.world = w


# テクスチャ側に陰影が焼いてあるもの(顔・遺影)は弱い光で撮る
# アニメ帯用の画角の上書き: (カメラ距離の倍率, 注視点のずらし)
# 落下などで rest ポーズの外へ動くものは、広めに引かないと画面から出る。
STRIP_FRAME = {"hanging_robe": (1.85, (0.0, -0.55, -0.60))}

DIM = {"body_face": 0.50, "iei_frame": 0.55, "body_risen": 0.62}


def add_lights(center, radius, key=1.0):
    """キー / フィル / リム の 3 灯。距離はモデルの大きさに合わせる。"""
    d = max(radius * 3.0, 1.0)
    # 面光源の放射照度 ~ P / (4*pi*d^2)。狙った明るさになるよう係数を決める。
    specs = [
        ("Key", (0.9, -1.0, 1.15), 1.0, 0.82 * key),
        ("Fill", (-1.1, -0.75, 0.42), 0.9, 0.20 * key),
        ("Rim", (-0.35, 1.25, 0.95), 1.1, 0.34 * key),
    ]
    for name, dirv, sz, power in specs:
        lt = bpy.data.lights.new(name, 'AREA')
        lt.energy = power * (d * d) * 4.0 * math.pi
        lt.size = max(radius * sz * 2.0, 0.4)
        lt.color = (1.0, 0.97, 0.92) if name == "Key" else (0.82, 0.86, 1.0)
        ob = bpy.data.objects.new(name, lt)
        bpy.context.collection.objects.link(ob)
        v = Vector(dirv).normalized() * d
        ob.location = Vector(center) + v
        ob.rotation_euler = (-v).to_track_quat('-Z', 'Y').to_euler()
    # 足元の反射板がわりに床
    me = bpy.data.meshes.new("Ground")
    s = radius * 6.0
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    me.update()
    g = bpy.data.objects.new("Ground", me)
    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.13, 0.13, 0.14, 1)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.92
    me.materials.append(mat)
    g.location = (center[0], center[1], 0.0)
    bpy.context.collection.objects.link(g)


def import_glb(path):
    """glb を読み込み、実体のオブジェクトだけ返す。
    glTF インポータは `glTF_not_exported` コレクションに補助メッシュ(Icosphere)
    を作るので、それは描画からも bbox からも外す。"""
    bpy.ops.import_scene.gltf(filepath=path)
    keep = []
    for o in list(bpy.context.scene.objects):
        if any(c.name.startswith("glTF_not_exported") for c in o.users_collection):
            o.hide_render = True
            o.hide_viewport = True
            continue
        keep.append(o)
    return keep


def bbox_of(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    any_ = False
    for o in objs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
            any_ = True
    if not any_:
        return Vector((0, 0, 0)), Vector((1, 1, 1))
    return lo, hi


def render_one(name, path, engine, angle=(1.0, -1.25, 0.62)):
    key = DIM.get(name, 1.0)
    reset_scene()
    for w in list(bpy.data.worlds):
        bpy.data.worlds.remove(w, do_unlink=True)
    for lt in list(bpy.data.lights):
        bpy.data.lights.remove(lt, do_unlink=True)
    objs = import_glb(path)
    lo, hi = bbox_of(objs)
    center = (lo + hi) * 0.5
    size = (hi - lo)
    radius = max(size.length * 0.5, 0.08)

    setup_world()
    add_lights(center, radius, key)

    cam_d = radius * 2.55
    v = Vector(angle).normalized() * cam_d
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 48.0
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(cam)
    cam.location = center + v
    cam.rotation_euler = (-v).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam

    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    if engine == 'CYCLES':
        sc.cycles.samples = SAMPLES
        sc.cycles.use_denoising = True
        sc.cycles.device = 'CPU'
    elif engine.startswith('BLENDER_EEVEE'):
        try:
            sc.eevee.taa_render_samples = SAMPLES
        except Exception:
            pass
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.15

    out = os.path.join(PREVIEW_DIR, name + ".png")
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    return out


def render_anim_strips(name, path, engine, angle):
    """アニメ付き glb は、各アクションから 5 姿勢を抜いて横一列の帯にする。"""
    import numpy as np
    from common import write_png
    reset_scene()
    for w in list(bpy.data.worlds):
        bpy.data.worlds.remove(w, do_unlink=True)
    for lt in list(bpy.data.lights):
        bpy.data.lights.remove(lt, do_unlink=True)
    objs = import_glb(path)
    arms = [o for o in objs if o.type == 'ARMATURE']
    if not arms:
        return []
    ao = arms[0]
    acts = sorted(bpy.data.actions, key=lambda a: a.name)
    if not acts:
        return []

    lo, hi = bbox_of(objs)
    center = (lo + hi) * 0.5
    radius = max((hi - lo).length * 0.5, 0.08)
    zoom, coff = STRIP_FRAME.get(name, (1.0, (0.0, 0.0, 0.0)))
    center = center + Vector(coff)
    setup_world()
    add_lights(center, radius, DIM.get(name, 1.0))
    v = Vector(angle).normalized() * (radius * 2.9 * zoom)
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 46.0
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(cam)
    cam.location = center + v
    cam.rotation_euler = (-v).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = engine
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.exposure = 0.15
    if engine.startswith('BLENDER_EEVEE'):
        try:
            sc.eevee.taa_render_samples = SAMPLES
        except Exception:
            pass

    if ao.animation_data is None:
        ao.animation_data_create()
    out = []
    tmp = os.path.join(PREVIEW_DIR, "_tmp_frame.png")
    for act in acts:
        ao.animation_data.action = act
        try:
            if len(act.slots):
                ao.animation_data.action_slot = act.slots[0]
        except Exception:
            pass
        f0, f1 = act.frame_range
        shots = []
        for k in range(5):
            sc.frame_set(int(round(f0 + (f1 - f0) * k / 4.0)))
            sc.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            shots.append(read_png(tmp)[..., :3])
        strip = np.concatenate(shots, axis=1)
        p = os.path.join(PREVIEW_DIR, "%s_%s.png" % (name, act.name))
        write_png(p, strip)
        out.append((name + "_" + act.name, strip))
        print("  anim   %s / %s" % (name, act.name))
    ao.animation_data.action = None
    if os.path.exists(tmp):
        os.remove(tmp)
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv if argv else sorted(
        f[:-4] for f in os.listdir(MODEL_DIR) if f.endswith(".glb"))
    engine = pick_engine()
    print("engine:", engine, " models:", len(names))
    ok = []
    for n in names:
        p = os.path.join(MODEL_DIR, n + ".glb")
        if not os.path.exists(p):
            print("  skip (missing)", n)
            continue
        try:
            render_one(n, p, engine, ANGLES.get(n, (1.0, -1.25, 0.62)))
            print("  preview", n)
            ok.append(n)
        except Exception as e:
            print("  FAILED", n, e)

    # アニメ付きのものは姿勢の帯も作る
    anim_items = []
    for n in ok:
        p = os.path.join(MODEL_DIR, n + ".glb")
        try:
            anim_items += render_anim_strips(n, p, engine, ANGLES.get(n, (1.0, -1.25, 0.62)))
        except Exception as e:
            print("  anim FAILED", n, e)
    if anim_items:
        contact_sheet(anim_items, os.path.join(PREVIEW_DIR, "anim_sheet.png"),
                      cell=640, cols=1, pad=6)
        print("anim_sheet:", len(anim_items), "strips")

    items = []
    model_names = set(f[:-4] for f in os.listdir(MODEL_DIR) if f.endswith(".glb"))
    for n in sorted(model_names):
        fp = os.path.join(PREVIEW_DIR, n + ".png")
        if not os.path.exists(fp):
            continue
        try:
            items.append((n, read_png(fp)))
        except Exception as e:
            print("  sheet skip", n, e)
    if items:
        contact_sheet(items, os.path.join(PREVIEW_DIR, "contact_sheet.png"),
                      cell=128, cols=8)
        print("contact_sheet:", len(items), "entries")


if __name__ == "__main__":
    main()
