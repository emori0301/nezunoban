"""各人物の顔アップを docs/previews/npc_*_face.png に出す。

blender --background --python tools/blender/render_faces.py -- [name ...]

モデルごとに頭の位置を実測して自動でフレーミングする。
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from common import MODEL_DIR, PREVIEW_DIR, reset_scene, read_png, contact_sheet
from render_previews import import_glb, setup_world, pick_engine, add_lights, SAMPLES

RES = 320
NAMES = ["npc_boss", "npc_son", "npc_granddaughter"]


def head_center(objs):
    lo = Vector((1e9, 1e9, 1e9)); hi = -lo
    pts = []
    for o in objs:
        if o.type != 'MESH':
            continue
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            pts.append(p)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    H = hi.z - lo.z
    top = [p for p in pts if p.z > lo.z + H * 0.855]
    if not top:
        top = pts
    cz = (min(p.z for p in top) + max(p.z for p in top)) * 0.5
    cy = (min(p.y for p in top) + max(p.y for p in top)) * 0.5
    rad = max(max(p.z for p in top) - min(p.z for p in top),
              max(p.x for p in top) - min(p.x for p in top)) * 0.5
    return Vector((0.0, cy, cz)), max(rad, 0.05)


def shot(name, path, ang, key=0.55):
    reset_scene()
    for w in list(bpy.data.worlds):
        bpy.data.worlds.remove(w, do_unlink=True)
    for l in list(bpy.data.lights):
        bpy.data.lights.remove(l, do_unlink=True)
    objs = import_glb(os.path.join(MODEL_DIR, name + ".glb"))
    c, rad = head_center(objs)
    setup_world(); add_lights(c, rad * 2.2, key)
    cd = bpy.data.cameras.new("C"); cd.lens = 62.0
    cam = bpy.data.objects.new("C", cd); bpy.context.collection.objects.link(cam)
    v = Vector(ang).normalized() * (rad * 4.6)
    cam.location = c + v
    cam.rotation_euler = (-v).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam; sc.render.engine = pick_engine()
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.view_settings.view_transform = 'Standard'; sc.view_settings.exposure = 0.15
    try:
        sc.eevee.taa_render_samples = SAMPLES
    except Exception:
        pass
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or NAMES
    items = []
    for n in names:
        if not os.path.exists(os.path.join(MODEL_DIR, n + ".glb")):
            continue
        p = os.path.join(PREVIEW_DIR, n + "_face.png")
        shot(n, p, (0.0, 1.0, 0.06))
        print("  face", n)
        items.append((n, read_png(p)[..., :3]))
        tmp = os.path.join(PREVIEW_DIR, "_f34_%s.png" % n)
        shot(n, tmp, (0.75, 1.0, 0.12))
        items.append((n + " 3/4", read_png(tmp)[..., :3]))
        os.remove(tmp)
    if items:
        contact_sheet(items, os.path.join(PREVIEW_DIR, "npc_faces.png"),
                      cell=RES, cols=2)
        print("npc_faces.png:", len(items))


if __name__ == "__main__":
    main()
