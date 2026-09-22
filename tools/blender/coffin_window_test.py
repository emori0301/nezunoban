"""棺の小窓が本当に貫通しているかを絵で確かめる。

blender --background --python tools/blender/coffin_window_test.py
  -> docs/previews/coffin_window.png

左: Window 表示(小窓が閉じている)
中: Window 非表示(穴から body_face の顔が見える)
右: Lid を蝶番で 60 度開いた状態
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
import bpy
from mathutils import Vector
from common import MODEL_DIR, PREVIEW_DIR, reset_scene, read_png, write_png, contact_sheet
from render_previews import pick_engine, setup_world, import_glb, RES, SAMPLES

# 小窓の中心(build_ritual.py の WIN_X0/WIN_X1 と合わせる)
WIN_C = Vector((0.64, 0.0, 0.42))


def find(name):
    for o in bpy.context.scene.objects:
        if o.name == name or o.name.startswith(name + "."):
            return o
    return None


def lights(k=1.0):
    for (nm, pos, power) in (("Key", (1.30, -1.10, 1.60), 34.0 * k),
                             ("Fill", (-0.60, -1.30, 0.90), 10.0 * k),
                             ("Top", (0.64, 0.10, 1.90), 9.0 * k)):
        lt = bpy.data.lights.new(nm, 'AREA')
        lt.energy = power
        lt.size = 0.9
        ob = bpy.data.objects.new(nm, lt)
        bpy.context.collection.objects.link(ob)
        ob.location = pos
        v = WIN_C - Vector(pos)
        ob.rotation_euler = v.to_track_quat('-Z', 'Y').to_euler()


def shot(engine, path, hide_window, lid_angle=0.0, cam_pos=None, lens=55.0, key=1.0):
    reset_scene()
    for w in list(bpy.data.worlds):
        bpy.data.worlds.remove(w, do_unlink=True)
    for lt in list(bpy.data.lights):
        bpy.data.lights.remove(lt, do_unlink=True)

    import_glb(os.path.join(MODEL_DIR, "coffin.glb"))
    import_glb(os.path.join(MODEL_DIR, "body_face.glb"))

    # body_face を小窓の真下、棺の中に置く
    face = find("body_face")
    face.location = (0.64, 0.0, 0.275)
    bpy.context.view_layer.update()
    print("  body_face world =", tuple(round(a, 3) for a in face.matrix_world.translation),
          "dims =", tuple(round(a, 3) for a in face.dimensions))

    win = find("Window")
    if win is not None:
        win.hide_render = hide_window
    lid = find("Lid")
    if lid is not None and lid_angle:
        # glTF インポータはオブジェクトを QUATERNION モードにするので、
        # rotation_euler を入れても効かない。モードを戻してから回す。
        lid.rotation_mode = 'XYZ'
        lid.rotation_euler = (math.radians(lid_angle), 0, 0)

    setup_world(0.02)
    lights(key)

    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(cam)
    cam.location = cam_pos if cam_pos else (0.99, -0.55, 0.92)
    cam.rotation_euler = (WIN_C - Vector(cam.location)).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = engine
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.exposure = 0.0
    if engine.startswith('BLENDER_EEVEE'):
        try:
            sc.eevee.taa_render_samples = SAMPLES
        except Exception:
            pass
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    engine = pick_engine()
    tmp = os.path.join(PREVIEW_DIR, "_cw_%d.png")
    # 棺の中は暗いので、覗き込むカットだけ照明を強くする
    cases = [("Window visible", False, 0.0, None, 55.0, 1.0),
             ("Window hidden", True, 0.0, None, 55.0, 1.0),
             ("through window", True, 0.0, (0.70, -0.16, 1.02), 62.0, 3.2),
             ("Lid open 60deg", True, 60.0, None, 55.0, 1.6)]
    items = []
    for i, (label, hide, ang, cpos, lens, key) in enumerate(cases):
        p = tmp % i
        shot(engine, p, hide, ang, cpos, lens, key)
        items.append((label, read_png(p)[..., :3]))
        os.remove(p)
    out = os.path.join(PREVIEW_DIR, "coffin_window.png")
    contact_sheet(items, out, cell=RES, cols=4, pad=6)
    print("coffin window proof:", out)


if __name__ == "__main__":
    main()
