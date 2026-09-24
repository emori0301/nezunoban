"""家族写真・遺影・棺の中の顔を、MPFB 製の人物を Blender でレンダリングして作る。

    blender --background --python tools/blender/render_photos.py
    blender --background --python tools/blender/render_photos.py -- family iei face

手描きの顔を貼るのをやめ、実際に 3D の人物を光の下で撮ってから写真として
劣化させる。そうしないと「絵」に見えてしまう。

出力:
  assets/textures/family_photo.png         256x192  4 人目の顔が擦れて潰れている
  assets/textures/family_photo_player.png  256x192  4 人目が黒い後ろ姿
  assets/textures/iei_photo.png            256x256  キヨの遺影(白黒・微笑)
  assets/textures/body_face_{calm,mouth,eyes,turned}.png  256x256  棺の小窓越しの顔
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy
import numpy as np
from mathutils import Vector, Euler

from common import (reset_scene, save_tex, read_png, write_png, rgb, mix,
                    mul_gray, blur, norm, fbm, white, stains, posterize,
                    ellipse, rect, finish, MODEL_DIR, TEX_DIR, PREVIEW_DIR,
                    material, Builder, box_mm, contact_sheet, _rng)
import render_previews as RP


# ---------------------------------------------------------------- 下ごしらえ

def scene_setup(w, h, exposure=0.0, samples=48):
    sc = bpy.context.scene
    sc.render.engine = RP.pick_engine()
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.exposure = exposure
    if sc.render.engine.startswith('BLENDER_EEVEE'):
        try:
            sc.eevee.taa_render_samples = samples
        except Exception:
            pass
    return sc


def world_color(col, strength=1.0):
    wd = bpy.data.worlds.new("W")
    wd.use_nodes = True
    bg = wd.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (col[0], col[1], col[2], 1.0)
    bg.inputs[1].default_value = strength
    bpy.context.scene.world = wd
    return wd


def add_area(name, loc, rot, size, energy, col=(1.0, 0.97, 0.92)):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy
    ld.size = size
    ld.color = col
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    ob.rotation_euler = Euler(rot)
    bpy.context.collection.objects.link(ob)
    return ob


def add_camera(loc, target, lens=55.0, dof_at=None, fstop=4.0):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(cam)
    cam.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    if dof_at is not None:
        cd.dof.use_dof = True
        cd.dof.focus_distance = (Vector(dof_at) - Vector(loc)).length
        cd.dof.aperture_fstop = fstop
    bpy.context.scene.camera = cam
    return cam


def render_np(w, h):
    """レンダリングして (h, w, 3) の 0..1 float で返す。"""
    tmp = os.path.join(PREVIEW_DIR, "_photo_tmp.png")
    bpy.context.scene.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = read_png(tmp).astype(float) / 255.0
    if os.path.exists(tmp):
        os.remove(tmp)
    return img[..., :3]


def place(name, loc, yaw_deg=0.0, action=None, frame=1):
    """glb を読み込んで置く。yaw は Z 回転(度)。"""
    before = set(bpy.context.scene.objects)
    RP.import_glb(os.path.join(MODEL_DIR, name + ".glb"))
    objs = [o for o in bpy.context.scene.objects if o not in before]
    roots = [o for o in objs if o.parent is None or o.parent not in objs]
    piv = bpy.data.objects.new("piv_" + name, None)
    bpy.context.collection.objects.link(piv)
    piv.location = Vector(loc)
    piv.rotation_euler = Euler((0.0, 0.0, math.radians(yaw_deg)))
    for r in roots:
        r.parent = piv
    arms = [o for o in objs if o.type == 'ARMATURE']
    if action and arms:
        ao = arms[0]
        act = bpy.data.actions.get(action)
        if act is not None:
            if ao.animation_data is None:
                ao.animation_data_create()
            ao.animation_data.action = act
            try:
                if len(act.slots):
                    ao.animation_data.action_slot = act.slots[0]
            except Exception:
                pass
            bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return objs, piv


def matte(objs, rough=0.96):
    """肌や布がテカらないようにする。小さな面光源だと鼻に白い点が出る。"""
    for o in objs:
        if o.type != 'MESH':
            continue
        for m in o.data.materials:
            if m is None or not m.use_nodes:
                continue
            for n in m.node_tree.nodes:
                if n.type != 'BSDF_PRINCIPLED':
                    continue
                # Blender 5.2 の Principled は Specular 入力が無い。
                # IOR=1.0 にすると鏡面反射そのものが消える。
                for key, val in (("Roughness", rough), ("IOR", 1.0),
                                 ("Specular IOR Level", 0.0), ("Metallic", 0.0),
                                 ("Coat Weight", 0.0), ("Sheen Weight", 0.0)):
                    if key in n.inputs:
                        try:
                            n.inputs[key].default_value = val
                        except Exception:
                            pass


def blacken(objs, col=(0.020, 0.020, 0.024)):
    """その人物のマテリアルを真っ黒に差し替える(後ろ姿の影用)。"""
    dark = material("PhotoSilhouette", None, color=col, rough=0.95)
    for o in objs:
        if o.type != 'MESH':
            continue
        o.data.materials.clear()
        o.data.materials.append(dark)
        for p in o.data.polygons:
            p.material_index = 0


# ---------------------------------------------------------------- 縁側のセット

def veranda():
    wood = material("PhWood", "wood_dark", color=(0.34, 0.24, 0.16), rough=0.62)
    dark = material("PhBeam", "wall_wood", color=(0.16, 0.12, 0.09), rough=0.8)
    paper = material("PhShoji", "shoji", color=(0.56, 0.54, 0.48), rough=0.95)
    grass = material("PhGarden", "leaves_dark", color=(0.20, 0.24, 0.14), rough=0.95)

    b = Builder("set")
    # 縁側の板(手前 = -Y、奥 = +Y)
    b.add(box_mm(-3.0, 3.0, -0.10, 1.10, -0.02, 0.00), wood, 6.0)
    for k in range(13):
        y = -0.10 + k * 0.094
        b.add(box_mm(-3.0, 3.0, y, y + 0.006, 0.000, 0.003), dark, 14.0)
    # 障子の壁(奥)
    b.add(box_mm(-3.0, 3.0, 1.10, 1.16, 0.00, 2.30), paper, 2.2)
    for k in range(17):                      # 縦桟
        x = -2.8 + k * 0.35
        b.add(box_mm(x, x + 0.030, 1.07, 1.10, 0.02, 2.05), dark, 9.0)
    for k in range(6):                       # 横桟
        z = 0.32 + k * 0.30
        b.add(box_mm(-3.0, 3.0, 1.07, 1.10, z, z + 0.026), dark, 9.0)
    b.add(box_mm(-3.0, 3.0, 1.02, 1.16, 2.05, 2.24), dark, 5.0)      # 鴨居
    b.add(box_mm(-3.0, 3.0, 1.02, 1.16, 0.00, 0.06), dark, 8.0)      # 敷居
    for x in (-2.40, 2.40):                  # 柱
        b.add(box_mm(x, x + 0.11, 0.98, 1.09, 0.00, 2.30), dark, 4.0)
    # 庭(縁側の手前の低い地面。カメラは y=-3 付近なので、これより奥に置く)
    b.add(box_mm(-4.0, 4.0, -2.20, -0.10, -0.44, -0.42), grass, 3.0)
    return b.build()


def daylight():
    world_color((0.52, 0.58, 0.66), 0.55)
    add_area("key", (0.9, -3.2, 2.4), (math.radians(60), 0, math.radians(12)),
             5.0, 300.0, (1.0, 0.96, 0.88))
    add_area("fill", (-2.4, -2.4, 1.7), (math.radians(78), 0, math.radians(-40)),
             4.0, 95.0, (0.82, 0.88, 1.0))
    add_area("back", (0.0, 2.6, 2.1), (math.radians(-64), 0, 0),
             4.0, 12.0, (1.0, 0.94, 0.86))
    add_area("floor", (0.0, -1.2, 0.9), (math.radians(96), 0, 0),
             3.0, 22.0, (1.0, 0.92, 0.80))


# ---------------------------------------------------------------- 写真の劣化

def degrade_photo(img, seed, out_w, out_h, fade=0.34, warm=True,
                  grain=0.10, mono=False, corner=0.035, bleed=2):
    """レンダリングを古い写真にする。退色・粒子・角の丸み・にじみ。"""
    H0, W0 = img.shape[0], img.shape[1]
    img = blur(img, bleed)
    fy, fx = H0 // out_h, W0 // out_w
    if fy >= 1 and fx >= 1 and H0 % out_h == 0 and W0 % out_w == 0:
        img = img.reshape(out_h, fy, out_w, fx, 3).mean(axis=(1, 3))
    H, W = img.shape[0], img.shape[1]
    gx, gy = np.meshgrid(np.arange(H), np.arange(W), indexing="ij")

    lum = img.mean(axis=2, keepdims=True)
    if mono:
        img = np.repeat(lum, 3, axis=2)
        img = img * np.array([1.0, 0.985, 0.945])
    else:
        img = mix(img, np.repeat(lum, 3, axis=2), fade)
        if warm:
            img = img * np.array([1.07, 1.00, 0.84])
    con = 1.16 if mono else 1.02
    img = np.clip((img - 0.5) * con + (0.49 if mono else 0.50), 0, 1)

    sq = lambda fn, *a, **k: fn(max(H, W), *a, **k)[:H, :W]
    img = mul_gray(img, 0.93 + sq(lambda s, c, o, d: norm(fbm(s, c, o, d)),
                                  9, 4, seed + 1) * 0.16)
    img = mul_gray(img, 1.0 - grain * 0.5 + sq(white, seed + 2) * grain)
    img = mul_gray(img, sq(stains, seed + 3, 7, 0.16, 34))

    # 縁の焼けと角の丸み(プリントを写した感じ)
    ex = np.minimum(gx, H - 1 - gx) / (H * 0.10)
    ey = np.minimum(gy, W - 1 - gy) / (W * 0.10)
    edge = np.clip(1.0 - np.minimum(ex, ey), 0, 1)
    img = mix(img, rgb(H, (0.70, 0.62, 0.48), width=W), edge * 0.45)
    r = corner * min(H, W) * 4.0
    for (cx, cy) in ((r, r), (r, W - r), (H - r, r), (H - r, W - r)):
        d = np.sqrt(((gx - cx) / r) ** 2 + ((gy - cy) / r) ** 2)
        outside = (((gx - cx) * np.sign(cx - H * 0.5) > 0) &
                   ((gy - cy) * np.sign(cy - W * 0.5) > 0))
        m = np.clip((d - 1.0) * 3.0, 0, 1) * outside
        img = mix(img, rgb(H, (0.82, 0.78, 0.70), width=W), m)
    return finish(img, seed + 4, noise=0.045, levels=24)


# ---------------------------------------------------------------- 家族写真

# (glb, 立ち位置 x, yaw, idle のフレーム)
FAMILY = [
    ("npc_kiyo", -0.60, 7.0, 1),            # キヨ(88)
    ("npc_son", -0.19, -5.0, 37),            # 60 代の男
    ("npc_granddaughter", 0.26, 4.0, 61),    # 20 代の女
    ("npc_boss", 0.74, -3.0, 23),            # 4 人目
]


def build_family(fourth):
    """fourth: "smudge"(顔を潰す) か "back"(黒い後ろ姿)。"""
    reset_scene()
    veranda()
    daylight()
    cams = []
    for i, (nm, x, yaw, fr) in enumerate(FAMILY):
        last = (i == len(FAMILY) - 1)
        back = last and fourth == "back"
        objs, piv = place(nm, (x, 0.42, 0.0),
                          yaw_deg=yaw if back else (yaw + 180.0),
                          action="idle", frame=fr)
        print("  placed %-20s meshes=%d" % (nm, sum(1 for o in objs
                                                    if o.type == 'MESH')))
        matte(objs)
        if back:
            blacken(objs)
        if last:
            cams.append(piv)
    return cams


def head_screen_pos(scene, cam, world_pos):
    """ワールド座標を 0..1 の画面座標にする(顔を擦る位置を出すため)。"""
    from bpy_extras.object_utils import world_to_camera_view
    co = world_to_camera_view(scene, cam, Vector(world_pos))
    return co.x, 1.0 - co.y


def make_family(variant, out_name):
    build_family(variant)
    W, H = 1024, 768
    sc = scene_setup(W, H, exposure=0.10, samples=48)
    print("  objects in scene:", len(bpy.context.scene.objects))
    cam = add_camera((0.06, -3.70, 1.22), (0.06, 0.42, 0.97), lens=60.0,
                     dof_at=(0.06, 0.42, 1.12), fstop=6.3)
    img = render_np(W, H)
    write_png(os.path.join(PREVIEW_DIR, "_raw_family_%s.png" % variant),
              img * 255.0)

    if variant == "smudge":
        # 4 人目の顔だけを擦って潰す
        hx, hy = head_screen_pos(sc, cam, (0.74, 0.42, 1.51))
        cx, cy = hy * H, hx * W
        gx, gy = np.meshgrid(np.arange(H), np.arange(W), indexing="ij")
        m = np.clip(1.0 - np.sqrt(((gx - cx) / (H * 0.085)) ** 2
                                  + ((gy - cy) / (W * 0.055)) ** 2), 0, 1)
        m = np.clip(m * 2.0, 0, 1)
        sm = blur(img.copy(), 14)
        img = mix(img, sm, m)
        scr = white(max(H, W), 9911)[:H, :W]
        img = mix(img, rgb(H, (0.80, 0.77, 0.72), width=W),
                  m * (0.34 + scr * 0.42))

    out = degrade_photo(img, 6100 if variant == "smudge" else 6200, 256, 192)
    save_tex(out_name, out)
    return out


# ---------------------------------------------------------------- 遺影

def make_iei():
    reset_scene()
    world_color((0.10, 0.10, 0.11), 0.30)
    # 写真館: 斜め上から柔らかい主光 + 背景を分ける弱い逆光
    add_area("key", (-1.30, -2.10, 2.55), (math.radians(52), 0, math.radians(-28)),
             2.0, 420.0, (1.0, 0.97, 0.93))
    add_area("fill", (1.55, -1.80, 1.55), (math.radians(82), 0, math.radians(40)),
             1.6, 70.0, (0.88, 0.92, 1.0))
    add_area("rim", (0.85, 1.35, 2.00), (math.radians(-52), 0, math.radians(18)),
             1.2, 40.0)
    # 背景の暗い幕
    b = Builder("bg")
    b.add(box_mm(-2.4, 2.4, 1.85, 1.90, 0.00, 2.60),
          material("IeiBg", "wall_plaster", color=(0.085, 0.085, 0.090), rough=0.98), 2.0)
    b.build()

    objs, _ = place("npc_kiyo", (0.0, 0.0, 0.0), yaw_deg=180.0,
                    action="idle", frame=5)
    # 微笑んだ顔に差し替える
    for o in objs:
        if o.type != 'MESH':
            continue
        for m in o.data.materials:
            if m is not None and m.name.endswith("_Face"):
                _swap_face_tex(m, "face_kiyo_smile")
    matte(objs)

    R = 768
    scene_setup(R, R, exposure=0.14, samples=64)
    add_camera((0.015, -1.02, 1.399), (0.0, 0.0, 1.318), lens=76.0,
               dof_at=(0.0, 0.0, 1.37), fstop=3.6)
    img = render_np(R, R)
    out = degrade_photo(img, 6300, 256, 256, mono=True, grain=0.085,
                        corner=0.0, bleed=1)
    save_tex("iei_photo", out)
    return out


def _swap_face_tex(mat, tex_name):
    """マテリアルの画像テクスチャを別の png に差し替える。"""
    if not mat.use_nodes:
        return
    path = os.path.join(TEX_DIR, tex_name + ".png")
    if not os.path.exists(path):
        return
    img = bpy.data.images.load(path, check_existing=True)
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE':
            n.image = img


# ---------------------------------------------------------------- 棺の中の顔

FACE_VARIANTS = [
    ("body_face_calm", "face_kiyo_calm", 0.0, 6310),      # 目を閉じ、口も閉じる
    ("body_face_mouth", "face_kiyo_mouth", 0.0, 6320),    # 目を閉じ、口が開く
    ("body_face_eyes", "face_kiyo_eyes", 0.0, 6330),      # 目を見開き、口も開く
    ("body_face_turned", "face_kiyo", 15.0, 6340),        # 目を開け、横を向く
]


def _recenter(img, thresh=0.30):
    """顔(明るい塊)の重心が画面中央に来るように平行移動する。
    横を向かせると足元を軸に回るので頭が横へ逃げる。数値で測って戻す。"""
    H, W = img.shape[0], img.shape[1]
    lum = img.mean(axis=2)
    m = lum > thresh
    if m.sum() < 200:
        return img
    gx, gy = np.meshgrid(np.arange(H), np.arange(W), indexing="ij")
    cy = float((gy * m).sum() / m.sum())
    cx = float((gx * m).sum() / m.sum())
    return np.roll(np.roll(img, int(round(H * 0.5 - cx)), axis=0),
                   int(round(W * 0.5 - cy)), axis=1)


def _cloth_plate(seed):
    """顔の周りの白布。既存の body_face_* と同じ見え方にする。"""
    S = 256
    img = rgb(S, (0.84, 0.83, 0.80))
    w = norm(fbm(S, 5, 4, seed + 1))
    fold = np.clip(1.0 - np.abs(w - 0.5) * 6.0, 0, 1)
    img = mul_gray(img, 1.0 - fold * 0.28)
    img = mul_gray(img, 0.95 + norm(fbm(S, 40, 2, seed + 2)) * 0.10)
    gx, gy = np.meshgrid(np.arange(S), np.arange(S), indexing="ij")
    d = np.sqrt(((gx - 130) / 100.0) ** 2 + ((gy - 128) / 74.0) ** 2)
    img = mul_gray(img, np.clip(0.45 + d * 0.75, 0, 1.0))
    ring = np.clip((d - 0.86) * 5.0, 0, 1) * np.clip((1.30 - d) * 3.5, 0, 1)
    img = mix(img, rgb(S, (0.20, 0.19, 0.19)), ring * 0.70)
    return img, d


def make_body_faces():
    outs = []
    for (out_name, tex, yaw, seed) in FACE_VARIANTS:
        reset_scene()
        world_color((0.06, 0.06, 0.07), 0.25)
        # 棺の小窓: 上から弱い光が落ちるだけ
        add_area("key", (0.0, -1.70, 2.80), (math.radians(33), 0, 0),
                 2.2, 92.0, (0.92, 0.94, 1.0))
        add_area("fill", (-1.25, -1.15, 1.55), (math.radians(80), 0,
                                                math.radians(-42)),
                 1.4, 30.0, (0.80, 0.86, 1.0))
        # 回転の軸は足元なので、横を向くと頭が横へ逃げる。その分だけ戻す。
        objs, _ = place("npc_kiyo", (0.0, 0.0, 0.0),
                        yaw_deg=180.0 + yaw, action="idle", frame=1)
        for o in objs:
            if o.type != 'MESH':
                continue
            for m in o.data.materials:
                if m is not None and m.name.endswith("_Face"):
                    _swap_face_tex(m, tex)
        matte(objs)

        R = 768
        scene_setup(R, R, exposure=-0.10, samples=64)
        add_camera((0.0, -0.62, 1.400), (0.0, 0.0, 1.382), lens=60.0)
        head = render_np(R, R)
        f = R // 256
        head = head.reshape(256, f, 256, f, 3).mean(axis=(1, 3))
        head = _recenter(head)

        plate, d = _cloth_plate(seed)
        m = np.clip((0.96 - d) * 6.0, 0, 1)[..., None]     # 布の開口だけ顔を出す
        img = plate * (1.0 - m) + head * m
        # 死斑・くすみ
        blot = np.clip((norm(fbm(256, 9, 4, seed + 3)) - 0.60) * 3.0, 0, 1)
        img = mix(img, rgb(256, (0.44, 0.38, 0.40)), blot * m[..., 0] * 0.40)
        gx, gy = np.meshgrid(np.arange(256), np.arange(256), indexing="ij")
        vg = np.clip(1.0 - ((gx - 105) / 175.0) ** 2 - ((gy - 128) / 175.0) ** 2, 0, 1)
        img = mul_gray(img, 0.30 + vg * 0.85)
        img = mul_gray(img, stains(256, seed + 5, 4, 0.18, 34))
        out = finish(img, seed + 6, noise=0.05, levels=22)
        save_tex(out_name, out)
        outs.append((out_name, out))
    return outs


# ---------------------------------------------------------------- main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    todo = argv or ["family", "iei", "face"]
    shots = []
    if "family" in todo:
        shots.append(("family_photo", make_family("smudge", "family_photo")))
        shots.append(("family_photo_player",
                      make_family("back", "family_photo_player")))
    if "iei" in todo:
        shots.append(("iei_photo", make_iei()))
    if "face" in todo:
        shots += make_body_faces()
    if shots:
        contact_sheet([(n, i * 255.0) for (n, i) in shots],
                      os.path.join(PREVIEW_DIR, "photo_sheet.png"),
                      cell=300, cols=4)
        print("photo_sheet:", len(shots))


if __name__ == "__main__":
    main()
