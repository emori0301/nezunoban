"""共通ユーティリティ: テクスチャ生成 / メッシュ構築 / マテリアル / glTF 出力。

Blender 5.2 の python で動かす前提(numpy あり)。
単位はメートル、Blender 内は Z-up で作り、原点は「接地面の中心」。
glTF は export_yup=True で出すので Godot 側では Y-up になる。
"""

import os
import sys
import math
import zlib
import struct

import numpy as np
import bpy
from mathutils import Vector, Quaternion, Matrix, Euler

# ---------------------------------------------------------------- paths

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
MODEL_DIR = os.path.join(ROOT, "assets", "models")
PREVIEW_DIR = os.path.join(ROOT, "docs", "previews")

for _d in (TEX_DIR, MODEL_DIR, PREVIEW_DIR):
    os.makedirs(_d, exist_ok=True)


# ================================================================ PNG I/O

def write_png(path, arr):
    """arr: uint8 (H, W, 3) か (H, W, 4)。純 numpy + zlib で PNG を書く。"""
    arr = np.ascontiguousarray(arr.astype(np.uint8))
    h, w, c = arr.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = np.zeros((h, w * c + 1), dtype=np.uint8)
    raw[:, 1:] = arr.reshape(h, w * c)
    comp = zlib.compress(raw.tobytes(), 9)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    hdr = struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", hdr))
        f.write(chunk(b"IDAT", comp))
        f.write(chunk(b"IEND", b""))
    return path


def save_tex(name, rgb):
    """rgb: float (H,W,3) 0..1 を assets/textures/<name>.png に保存。"""
    a = np.clip(rgb, 0.0, 1.0)
    p = os.path.join(TEX_DIR, name + ".png")
    write_png(p, (a * 255.0 + 0.5).astype(np.uint8))
    print("  tex %-24s %s" % (name + ".png", "%dx%d" % (rgb.shape[1], rgb.shape[0])))
    return p


# ================================================================ noise

def _rng(seed):
    return np.random.default_rng(seed)


def value_noise(size, cells, seed):
    """周期的(タイル可能)な値ノイズ。size は cells の倍数でなくてよい。"""
    g = _rng(seed).random((cells, cells))
    x = np.arange(size) * (cells / float(size))
    xi = np.floor(x).astype(int)
    xf = x - xi
    u = xf * xf * (3.0 - 2.0 * xf)
    i0 = xi % cells
    i1 = (xi + 1) % cells
    A = g[np.ix_(i0, i0)]
    B = g[np.ix_(i1, i0)]
    C = g[np.ix_(i0, i1)]
    D = g[np.ix_(i1, i1)]
    ux = u[:, None]
    uy = u[None, :]
    return (A * (1 - ux) * (1 - uy) + B * ux * (1 - uy)
            + C * (1 - ux) * uy + D * ux * uy)


def fbm(size, cells=4, octaves=5, seed=0, gain=0.5):
    out = np.zeros((size, size))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        if c > size:
            break
        out += amp * value_noise(size, c, seed + o * 977)
        tot += amp
        amp *= gain
    return out / max(tot, 1e-6)


def white(size, seed, lo=0.0, hi=1.0):
    return _rng(seed).random((size, size)) * (hi - lo) + lo


def norm(a):
    lo, hi = a.min(), a.max()
    if hi - lo < 1e-9:
        return np.zeros_like(a)
    return (a - lo) / (hi - lo)


def rgb(size, color):
    out = np.empty((size, size, 3))
    out[..., 0] = color[0]
    out[..., 1] = color[1]
    out[..., 2] = color[2]
    return out


def mul_gray(img, g):
    return img * g[..., None]


def mix(a, b, t):
    """t: (H,W) か float"""
    if isinstance(t, np.ndarray) and t.ndim == 2:
        t = t[..., None]
    return a * (1.0 - t) + b * t


def grunge(size, seed, amount=0.25, cells=3):
    """汚れ: 低周波の暗い染み。掛け算用のグレー(0.7〜1.0)を返す。"""
    n = norm(fbm(size, cells=cells, octaves=4, seed=seed))
    n = np.clip((n - 0.35) / 0.65, 0.0, 1.0)
    return 1.0 - n * amount


def speckle(size, seed, amount=0.06):
    return 1.0 + (white(size, seed) - 0.5) * 2.0 * amount


def tile_coords(size):
    """0..1 の UV グリッド(u=x方向, v=y方向)"""
    t = (np.arange(size) + 0.5) / size
    return t[:, None] * np.ones((1, size)), np.ones((size, 1)) * t[None, :]


def scratches(size, seed, count=40, amount=0.12, length=40):
    """細い擦り傷。掛け算用グレー。"""
    r = _rng(seed)
    m = np.zeros((size, size))
    for _ in range(count):
        x = r.integers(0, size)
        y = r.integers(0, size)
        ang = r.random() * math.pi * 2
        ln = int(length * (0.3 + r.random()))
        dx, dy = math.cos(ang), math.sin(ang)
        for i in range(ln):
            xx = int(x + dx * i) % size
            yy = int(y + dy * i) % size
            m[xx, yy] = max(m[xx, yy], 1.0 - i / float(ln))
    return 1.0 - m * amount


def stains(size, seed, count=6, amount=0.22, radius=40):
    """円形のシミ。掛け算用グレー。"""
    r = _rng(seed)
    gx, gy = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    m = np.zeros((size, size))
    for _ in range(count):
        cx = r.integers(0, size)
        cy = r.integers(0, size)
        rad = radius * (0.4 + r.random())
        dx = np.minimum(np.abs(gx - cx), size - np.abs(gx - cx))
        dy = np.minimum(np.abs(gy - cy), size - np.abs(gy - cy))
        d = np.sqrt(dx * dx + dy * dy) / rad
        m = np.maximum(m, np.clip(1.0 - d, 0.0, 1.0) ** 2)
    n = norm(fbm(size, cells=8, octaves=3, seed=seed + 31))
    return 1.0 - m * n * amount


def posterize(img, levels=24):
    """PSX らしく色数を落とす。"""
    return np.round(np.clip(img, 0, 1) * (levels - 1)) / (levels - 1)


def finish(img, seed=0, noise=0.035, levels=32):
    """全テクスチャ共通の仕上げ: 微ノイズ + 減色。"""
    out = img * speckle(img.shape[0], seed + 7777, noise)[..., None]
    return posterize(np.clip(out, 0, 1), levels)


# ---- 描画ヘルパ(テクスチャ上に矩形や線を置く) ----

def rect(img, x0, y0, x1, y1, color, alpha=1.0):
    s = img.shape[0]
    x0 = max(0, int(x0)); x1 = min(s, int(x1))
    y0 = max(0, int(y0)); y1 = min(s, int(y1))
    if x1 <= x0 or y1 <= y0:
        return img
    c = np.array(color, dtype=float)
    img[x0:x1, y0:y1] = img[x0:x1, y0:y1] * (1 - alpha) + c * alpha
    return img


def disc(img, cx, cy, r, color, alpha=1.0, soft=1.0):
    s = img.shape[0]
    gx, gy = np.meshgrid(np.arange(s), np.arange(s), indexing="ij")
    d = np.sqrt((gx - cx) ** 2.0 + (gy - cy) ** 2.0)
    m = np.clip((r - d) / max(soft, 1e-6), 0.0, 1.0) * alpha
    c = np.array(color, dtype=float)
    img[:] = img * (1 - m[..., None]) + c * m[..., None]
    return img


def ellipse(img, cx, cy, rx, ry, color, alpha=1.0, soft=1.0):
    s = img.shape[0]
    gx, gy = np.meshgrid(np.arange(s), np.arange(s), indexing="ij")
    d = np.sqrt(((gx - cx) / max(rx, 1e-6)) ** 2.0 + ((gy - cy) / max(ry, 1e-6)) ** 2.0)
    m = np.clip((1.0 - d) * max(rx, ry) / max(soft, 1e-6), 0.0, 1.0) * alpha
    c = np.array(color, dtype=float)
    img[:] = img * (1 - m[..., None]) + c * m[..., None]
    return img


def blur(img, k=2):
    out = img.astype(float).copy()
    for _ in range(k):
        out = (out
               + np.roll(out, 1, 0) + np.roll(out, -1, 0)
               + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 5.0
    return out


# ================================================================ scene

def reset_scene():
    _MAT_CACHE.clear()
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me, do_unlink=True)
    for ar in list(bpy.data.armatures):
        bpy.data.armatures.remove(ar, do_unlink=True)
    for ac in list(bpy.data.actions):
        bpy.data.actions.remove(ac, do_unlink=True)
    for ma in list(bpy.data.materials):
        bpy.data.materials.remove(ma, do_unlink=True)
    for im in list(bpy.data.images):
        if im.users == 0 or im.name not in ("Render Result", "Viewer Node"):
            try:
                bpy.data.images.remove(im, do_unlink=True)
            except Exception:
                pass


# ================================================================ material

_MAT_CACHE = {}


def material(name, tex=None, color=(0.8, 0.8, 0.8), rough=0.85, metal=0.0,
             emission=None, emission_strength=1.0, alpha=1.0, unlit_ish=False):
    """Principled BSDF + (任意で) 画像テクスチャ。name が Godot のマテリアル名になる。"""
    if name in _MAT_CACHE:
        m = bpy.data.materials.get(name)
        if m is not None:
            return m
        del _MAT_CACHE[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = 'BLEND'
    if tex:
        path = os.path.join(TEX_DIR, tex + ".png")
        if os.path.exists(path):
            img = bpy.data.images.get(tex + ".png")
            if img is None:
                img = bpy.data.images.load(path)
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = img
            node.interpolation = 'Closest'   # PSX らしいドット感
            node.location = (-400, 200)
            nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        else:
            print("  !! texture missing:", path)
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (
            emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    _MAT_CACHE[name] = mat
    return mat


def clear_mat_cache():
    _MAT_CACHE.clear()


# ================================================================ geometry

def tr(verts, t=(0, 0, 0), rot=None, scale=(1, 1, 1), pivot=(0, 0, 0)):
    """頂点リストを変換。rot は (axis, angle_rad) か Euler タプル(rx,ry,rz)。"""
    out = []
    if rot is None:
        m = Matrix.Identity(3)
    elif isinstance(rot, tuple) and len(rot) == 2 and isinstance(rot[0], str):
        m = Matrix.Rotation(rot[1], 3, rot[0])
    else:
        m = Euler(rot, 'XYZ').to_matrix()
    for v in verts:
        p = Vector((v[0] - pivot[0], v[1] - pivot[1], v[2] - pivot[2]))
        p = Vector((p.x * scale[0], p.y * scale[1], p.z * scale[2]))
        p = m @ p
        out.append((p.x + pivot[0] + t[0], p.y + pivot[1] + t[1], p.z + pivot[2] + t[2]))
    return out


def box(sx, sy, sz, c=(0, 0, 0)):
    """中心 c、全長 (sx,sy,sz) の直方体。8頂点6面。"""
    hx, hy, hz = sx / 2.0, sy / 2.0, sz / 2.0
    x, y, z = c
    v = [(x - hx, y - hy, z - hz), (x + hx, y - hy, z - hz),
         (x + hx, y + hy, z - hz), (x - hx, y + hy, z - hz),
         (x - hx, y - hy, z + hz), (x + hx, y - hy, z + hz),
         (x + hx, y + hy, z + hz), (x - hx, y + hy, z + hz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
         (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def box_mm(x0, x1, y0, y1, z0, z1):
    return box(x1 - x0, y1 - y0, z1 - z0,
               ((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0))


def box_taper(sx0, sy0, sx1, sy1, sz, c=(0, 0, 0)):
    """下面 (sx0,sy0) → 上面 (sx1,sy1) の角錐台。c は中心。"""
    x, y, z = c
    hz = sz / 2.0
    a, b = sx0 / 2.0, sy0 / 2.0
    p, q = sx1 / 2.0, sy1 / 2.0
    v = [(x - a, y - b, z - hz), (x + a, y - b, z - hz),
         (x + a, y + b, z - hz), (x - a, y + b, z - hz),
         (x - p, y - q, z + hz), (x + p, y - q, z + hz),
         (x + p, y + q, z + hz), (x - p, y + q, z + hz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
         (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def cyl(r, h, seg=8, c=(0, 0, 0), axis='Z', cap=True, r_top=None):
    """底面が z = c[2]-h/2 の円柱(または円錐台)。"""
    if r_top is None:
        r_top = r
    v = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        v.append((math.cos(a) * r, math.sin(a) * r, -h / 2.0))
    for i in range(seg):
        a = 2 * math.pi * i / seg
        v.append((math.cos(a) * r_top, math.sin(a) * r_top, h / 2.0))
    f = []
    for i in range(seg):
        j = (i + 1) % seg
        f.append((i, j, seg + j, seg + i))
    if cap:
        if r > 1e-5:
            f.append(tuple(range(seg - 1, -1, -1)))
        if r_top > 1e-5:
            f.append(tuple(range(seg, seg * 2)))
    if axis == 'X':
        v = tr(v, rot=('Y', math.pi / 2))
    elif axis == 'Y':
        v = tr(v, rot=('X', math.pi / 2))
    v = tr(v, t=c)
    return v, f


def sphere(r, seg=8, rings=5, c=(0, 0, 0), squash=1.0):
    """低ポリ UV 球。"""
    v = []
    for j in range(1, rings):
        phi = math.pi * j / rings
        z = math.cos(phi) * r * squash
        rr = math.sin(phi) * r
        for i in range(seg):
            a = 2 * math.pi * i / seg
            v.append((math.cos(a) * rr, math.sin(a) * rr, z))
    top = len(v); v.append((0, 0, r * squash))
    bot = len(v); v.append((0, 0, -r * squash))
    f = []
    for j in range(rings - 2):
        for i in range(seg):
            i2 = (i + 1) % seg
            a = j * seg + i
            b = j * seg + i2
            cc = (j + 1) * seg + i2
            d = (j + 1) * seg + i
            f.append((a, b, cc, d))
    for i in range(seg):
        i2 = (i + 1) % seg
        f.append((top, i2, i))
        f.append((bot, (rings - 2) * seg + i, (rings - 2) * seg + i2))
    v = tr(v, t=c)
    return v, f


def quad(p0, p1, p2, p3):
    return [p0, p1, p2, p3], [(0, 1, 2, 3)]


def prism(poly_xy, z0, z1, cap=True):
    """XY 多角形(反時計回り)を Z 方向に押し出す。"""
    n = len(poly_xy)
    v = [(p[0], p[1], z0) for p in poly_xy] + [(p[0], p[1], z1) for p in poly_xy]
    f = []
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    if cap:
        f.append(tuple(range(n - 1, -1, -1)))
        f.append(tuple(range(n, 2 * n)))
    return v, f


def frame_quads(ox, oz, ix, iz, y0, y1, c=(0, 0, 0)):
    """外枠 (ox,oz) 内枠 (ix,iz) の額縁状。Y 方向に厚み y0..y1。"""
    v, f = [], []
    hox, hoz, hix, hiz = ox / 2, oz / 2, ix / 2, iz / 2
    parts = [
        (-hox, hox, hiz, hoz),     # 上
        (-hox, hox, -hoz, -hiz),   # 下
        (-hox, -hix, -hiz, hiz),   # 左
        (hix, hox, -hiz, hiz),     # 右
    ]
    for (x0, x1, z0, z1) in parts:
        bv, bf = box_mm(x0 + c[0], x1 + c[0], y0 + c[1], y1 + c[1], z0 + c[2], z1 + c[2])
        base = len(v)
        v.extend(bv)
        f.extend([tuple(base + k for k in ff) for ff in bf])
    return v, f


# ================================================================ builder

class Builder:
    """頂点・面・マテリアルを溜めて 1 オブジェクトにする。"""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.fmat = []
        self.fuv = []
        self.fscale = []

    def add(self, geo, mat, uvscale=1.0, uv=None, flip=False):
        v, f = geo
        base = len(self.verts)
        self.verts.extend(v)
        for i, ff in enumerate(f):
            idx = tuple(base + k for k in ff)
            if flip:
                idx = tuple(reversed(idx))
            self.faces.append(idx)
            self.fmat.append(mat)
            self.fuv.append(uv[i] if uv is not None else None)
            self.fscale.append(uvscale)
        return self

    def count(self):
        return len(self.verts)

    def build(self, shade_flat=True, origin=(0, 0, 0)):
        mats = []
        midx = []
        for m in self.fmat:
            nm = m.name if hasattr(m, "name") else m
            if nm not in mats:
                mats.append(nm)
            midx.append(mats.index(nm))

        verts = [(v[0] - origin[0], v[1] - origin[1], v[2] - origin[2]) for v in self.verts]
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(verts, [], self.faces)
        me.validate(verbose=False)
        me.update()

        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)

        objs = {}
        for m in self.fmat:
            nm = m.name if hasattr(m, "name") else m
            objs[nm] = m if hasattr(m, "name") else bpy.data.materials[m]
        for nm in mats:
            me.materials.append(objs[nm])
        for i, poly in enumerate(me.polygons):
            poly.material_index = midx[i]
            if shade_flat:
                poly.use_smooth = False

        # UV: 明示指定が無ければ面法線からボックス投影
        uvl = me.uv_layers.new(name="UVMap")
        data = uvl.data
        for pi, poly in enumerate(me.polygons):
            explicit = self.fuv[pi]
            s = self.fscale[pi]
            n = poly.normal
            ax = max(range(3), key=lambda k: abs(n[k]))
            for li, loop_i in enumerate(poly.loop_indices):
                if explicit is not None:
                    data[loop_i].uv = explicit[li % len(explicit)]
                    continue
                vi = me.loops[loop_i].vertex_index
                p = me.vertices[vi].co
                if ax == 2:
                    u, vv = p.x, p.y
                    if n[2] < 0:
                        u = -u
                elif ax == 1:
                    u, vv = p.x, p.z
                    if n[1] > 0:
                        u = -u
                else:
                    u, vv = p.y, p.z
                    if n[0] < 0:
                        u = -u
                data[loop_i].uv = (u * s, vv * s)
        return ob


def new_object(name, geo, mat, uvscale=1.0, uv=None):
    b = Builder(name)
    b.add(geo, mat, uvscale=uvscale, uv=uv)
    return b.build()


# ================================================================ export

def total_verts(objs):
    n = 0
    for o in objs:
        if o.type == 'MESH':
            n += len(o.data.vertices)
    return n


def export(name, objs=None, animations=False):
    """assets/models/<name>.glb に出力。objs=None ならシーン全体。"""
    if objs is None:
        objs = [o for o in bpy.context.scene.objects]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]

    path = os.path.join(MODEL_DIR, name + ".glb")
    kw = dict(
        filepath=path,
        export_format='GLB',
        export_apply=True,
        export_animations=bool(animations),
        export_yup=True,
        use_selection=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_texture_dir="",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
    )
    if animations:
        kw["export_animation_mode"] = 'ACTIONS'
        kw["export_nla_strips"] = False
        kw["export_bake_animation"] = False
        kw["export_optimize_animation_size"] = False
        kw["export_force_sampling"] = True
        kw["export_anim_single_armature"] = True
    bpy.ops.export_scene.gltf(**kw)
    nv = total_verts(objs)
    size = os.path.getsize(path)
    print("  glb %-22s verts=%-5d %6.1f KB" % (name + ".glb", nv, size / 1024.0))
    return {"name": name, "verts": nv, "bytes": size}


REPORT = []


def emit(name, objs=None, animations=False):
    r = export(name, objs, animations)
    REPORT.append(r)
    return r


def dump_report():
    print("\n==== BUILD REPORT ====")
    for r in REPORT:
        print("%-24s %5d verts  %7.1f KB" % (r["name"], r["verts"], r["bytes"] / 1024.0))
    print("total models:", len(REPORT))


# ================================================================ rig helpers

BONES = [
    # (name, head, tail, parent)
    ("Hips",        (0.00, 0.00, 0.95), (0.00, 0.00, 1.10), None),
    ("Spine",       (0.00, 0.00, 1.10), (0.00, 0.00, 1.28), "Hips"),
    ("Chest",       (0.00, 0.00, 1.28), (0.00, 0.00, 1.46), "Spine"),
    ("Neck",        (0.00, 0.00, 1.46), (0.00, 0.00, 1.56), "Chest"),
    ("Head",        (0.00, 0.00, 1.56), (0.00, 0.00, 1.76), "Neck"),
    ("UpperArm.L",  (0.20, 0.00, 1.42), (0.24, 0.00, 1.16), "Chest"),
    ("LowerArm.L",  (0.24, 0.00, 1.16), (0.26, 0.00, 0.92), "UpperArm.L"),
    ("UpperArm.R", (-0.20, 0.00, 1.42), (-0.24, 0.00, 1.16), "Chest"),
    ("LowerArm.R", (-0.24, 0.00, 1.16), (-0.26, 0.00, 0.92), "UpperArm.R"),
    ("UpperLeg.L",  (0.10, 0.00, 0.93), (0.10, 0.00, 0.50), "Hips"),
    ("LowerLeg.L",  (0.10, 0.00, 0.50), (0.10, 0.00, 0.06), "UpperLeg.L"),
    ("UpperLeg.R", (-0.10, 0.00, 0.93), (-0.10, 0.00, 0.50), "Hips"),
    ("LowerLeg.R", (-0.10, 0.00, 0.50), (-0.10, 0.00, 0.06), "UpperLeg.R"),
]


def make_armature(name, bones, scale=1.0):
    arm = bpy.data.armatures.new(name + "_arm")
    ao = bpy.data.objects.new(name + "_rig", arm)
    bpy.context.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    ao.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for (bn, head, tail, parent) in bones:
        b = arm.edit_bones.new(bn)
        b.head = (head[0] * scale, head[1] * scale, head[2] * scale)
        b.tail = (tail[0] * scale, tail[1] * scale, tail[2] * scale)
        b.use_connect = False
        eb[bn] = b
    for (bn, head, tail, parent) in bones:
        if parent:
            eb[bn].parent = eb[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in ao.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return ao


def bind(mesh_obj, arm_obj, groups):
    """groups: {bone_name: [vertex indices]} で頂点グループを手動割り当て。"""
    for bn, idxs in groups.items():
        if not idxs:
            continue
        vg = mesh_obj.vertex_groups.get(bn) or mesh_obj.vertex_groups.new(name=bn)
        vg.add(list(idxs), 1.0, 'REPLACE')
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_obj
    mesh_obj.parent = arm_obj
    mesh_obj.matrix_parent_inverse = arm_obj.matrix_world.inverted()


def auto_groups(mesh_obj, arm_obj, rules, force_idx=None):
    """rules: [(bone, test(co)->bool), ...] 上から順に最初にマッチした骨へ。
    force_idx: {bone: 頂点インデックス} 座標判定より優先(スカートなど、
    位置では脚と区別できない部位に使う)。"""
    groups = {}
    forced = {}
    if force_idx:
        for bn, idxs in force_idx.items():
            for i in idxs:
                forced[i] = bn
    for v in mesh_obj.data.vertices:
        co = v.co
        bn0 = forced.get(v.index)
        if bn0:
            groups.setdefault(bn0, []).append(v.index)
            continue
        for bn, test in rules:
            if test(co):
                groups.setdefault(bn, []).append(v.index)
                break
    bind(mesh_obj, arm_obj, groups)
    return groups


def world_quat(arm_obj, bone_name, axis, angle):
    """ワールド軸まわりの回転を、そのボーンのローカル回転に変換する。"""
    M = arm_obj.data.bones[bone_name].matrix_local.to_3x3()
    Rw = Matrix.Rotation(angle, 3, axis)
    return (M.inverted() @ Rw @ M).to_quaternion()


def loft_rings(rings, cap=True):
    """rings: [[p0,p1,p2,p3], ...] 4 点の断面を順に繋いだ筒。
    隣の断面と頂点を共有するので、ボーンで曲げても裂けない。"""
    verts = []
    for r in rings:
        verts.extend(r)
    faces = []
    n = 4
    for i in range(len(rings) - 1):
        a, b = i * n, (i + 1) * n
        for k in range(n):
            k2 = (k + 1) % n
            faces.append((a + k, a + k2, b + k2, b + k))
    if cap:
        faces.append((3, 2, 1, 0))
        last = (len(rings) - 1) * n
        faces.append((last, last + 1, last + 2, last + 3))
    return verts, faces


def ring(cx, cy, cz, hw, hh, axis='Y'):
    """axis に垂直な長方形断面。axis='Y' なら XZ 平面の 4 点。"""
    if axis == 'Y':
        return [(cx - hw, cy, cz - hh), (cx + hw, cy, cz - hh),
                (cx + hw, cy, cz + hh), (cx - hw, cy, cz + hh)]
    if axis == 'Z':
        return [(cx - hw, cy - hh, cz), (cx + hw, cy - hh, cz),
                (cx + hw, cy + hh, cz), (cx - hw, cy + hh, cz)]
    return [(cx, cy - hw, cz - hh), (cx, cy + hw, cz - hh),
            (cx, cy + hw, cz + hh), (cx, cy - hw, cz + hh)]


def chain_weights(mesh_obj, arm_obj, chain, key, rigid=None, rigid_idx=None):
    """背骨のような一列のボーンに、座標に沿って滑らかに重みを配る。

    chain     : [(bone, t), ...] を t 昇順で。t は key(co) と同じ尺度。
    key       : 頂点座標 -> t
    rigid     : [(bone, test)] 座標で判定する例外。重み 1.0 で固定。
    rigid_idx : {bone: 頂点インデックスの集合} 位置ではなく作った順で指定する例外。
                こちらが優先。腕や脚のように胴と座標が重なる部位に使う。
    """
    groups = {}
    idx_map = {}
    if rigid_idx:
        for bn, idxs in rigid_idx.items():
            for i in idxs:
                idx_map[i] = bn

    def put(bn, idx, w):
        if w > 1e-4:
            groups.setdefault(bn, []).append((idx, w))

    ts = [c[1] for c in chain]
    for v in mesh_obj.data.vertices:
        co = v.co
        hit = idx_map.get(v.index)
        if hit is None and rigid:
            for bn, test in rigid:
                if test(co):
                    hit = bn
                    break
        if hit:
            put(hit, v.index, 1.0)
            continue
        t = key(co)
        if t <= ts[0]:
            put(chain[0][0], v.index, 1.0)
        elif t >= ts[-1]:
            put(chain[-1][0], v.index, 1.0)
        else:
            for i in range(len(ts) - 1):
                if ts[i] <= t <= ts[i + 1]:
                    f = (t - ts[i]) / max(ts[i + 1] - ts[i], 1e-6)
                    put(chain[i][0], v.index, 1.0 - f)
                    put(chain[i + 1][0], v.index, f)
                    break

    for bn, items in groups.items():
        vg = mesh_obj.vertex_groups.get(bn) or mesh_obj.vertex_groups.new(name=bn)
        for (idx, w) in items:
            vg.add([idx], w, 'REPLACE')
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_obj
    mesh_obj.parent = arm_obj
    mesh_obj.matrix_parent_inverse = arm_obj.matrix_world.inverted()
    return groups


class Anim:
    """アクションを作ってポーズにキーを打つ。"""

    def __init__(self, arm_obj, name, length=40, loop=True):
        self.ao = arm_obj
        if arm_obj.animation_data is None:
            arm_obj.animation_data_create()
        self.action = bpy.data.actions.new(name)
        self.action.use_fake_user = True
        arm_obj.animation_data.action = self.action
        self.length = length
        self.name = name

    def key(self, frame, bone, loc=None, rot=None, scale=None):
        pb = self.ao.pose.bones[bone]
        pb.rotation_mode = 'QUATERNION'
        if rot is not None:
            if isinstance(rot, Quaternion):
                pb.rotation_quaternion = rot
            else:
                e = Euler(rot, 'XYZ')
                pb.rotation_quaternion = e.to_quaternion()
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if loc is not None:
            pb.location = loc
            pb.keyframe_insert(data_path="location", frame=frame)
        if scale is not None:
            pb.scale = scale
            pb.keyframe_insert(data_path="scale", frame=frame)

    def keyw(self, frame, bone, axis, angle):
        """ワールド空間で axis('X'/'Y'/'Z') 周りに angle 回した姿勢をキーにする。
        骨のローカル軸を気にせず振り付けできる。"""
        self.key(frame, bone, rot=world_quat(self.ao, bone, axis, angle))

    def keyw_mul(self, frame, bone, pairs):
        """[('X', a), ('Z', b)] を順に掛けたワールド回転。"""
        q = Quaternion((1, 0, 0, 0))
        M = self.ao.data.bones[bone].matrix_local.to_3x3()
        R = Matrix.Identity(3)
        for (ax, ang) in pairs:
            R = Matrix.Rotation(ang, 3, ax) @ R
        q = (M.inverted() @ R @ M).to_quaternion()
        self.key(frame, bone, rot=q)

    def keyw_loc(self, frame, bone, world_vec):
        """ワールド方向の平行移動をボーンローカルに直してキーにする。"""
        M = self.ao.data.bones[bone].matrix_local.to_3x3()
        v = M.inverted() @ Vector(world_vec)
        self.key(frame, bone, loc=(v.x, v.y, v.z))

    def rest(self, frame, bones):
        for b in bones:
            self.key(frame, b, rot=(0, 0, 0))

    def finish(self, interp='BEZIER'):
        for layer in self.action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for kp in fc.keyframe_points:
                            kp.interpolation = interp
        self.ao.animation_data.action = None
        return self.action


def set_scene_frames(end):
    sc = bpy.context.scene
    sc.frame_start = 1
    sc.frame_end = end


def read_png(path):
    """write_png で書いた PNG(フィルタ 0)を読む。uint8 (H,W,C)。"""
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    idat = b""
    w = h = c = 0
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + ln]
        if tag == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", payload[:10])
            c = {0: 1, 2: 3, 6: 4}[ct]
        elif tag == b"IDAT":
            idat += payload
        elif tag == b"IEND":
            break
        pos += 12 + ln
    raw = np.frombuffer(zlib.decompress(idat), dtype=np.uint8).reshape(h, w * c + 1)
    return _unfilter_png(raw, w, h, c)


def _unfilter_png(raw, w, h, c):
    """PNG のフィルタ(0..4)を解いて uint8 (H,W,C) を返す。"""
    stride = w * c
    out = np.zeros((h, stride), dtype=np.uint8)
    prev = np.zeros(stride, dtype=np.uint8)
    for y in range(h):
        ft = int(raw[y, 0])
        line = raw[y, 1:].astype(np.int32)
        if ft == 0:
            cur = line
        elif ft == 1:
            cur = line.copy()
            for i in range(c, stride):
                cur[i] = (cur[i] + cur[i - c]) & 0xFF
        elif ft == 2:
            cur = (line + prev.astype(np.int32)) & 0xFF
        elif ft == 3:
            cur = line.copy()
            pv = prev.astype(np.int32)
            for i in range(stride):
                left = cur[i - c] if i >= c else 0
                cur[i] = (cur[i] + ((left + pv[i]) >> 1)) & 0xFF
        elif ft == 4:
            cur = line.copy()
            pv = prev.astype(np.int32)
            for i in range(stride):
                a = cur[i - c] if i >= c else 0
                b = pv[i]
                cc = pv[i - c] if i >= c else 0
                pp = a + b - cc
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - cc)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else cc)
                cur[i] = (cur[i] + pred) & 0xFF
        else:
            raise ValueError("bad PNG filter %d" % ft)
        out[y] = cur.astype(np.uint8)
        prev = out[y]
    return out.reshape(h, w, c)


def contact_sheet(items, out_path, cell=128, cols=8, pad=4):
    """items: [(label, uint8 HxWxC), ...] を並べた 1 枚を書く。"""
    n = len(items)
    cols = min(cols, max(1, n))
    rows = (n + cols - 1) // cols
    W = cols * (cell + pad) + pad
    H = rows * (cell + pad + 10) + pad
    sheet = np.full((H, W, 3), 18, dtype=np.uint8)
    for i, (label, img) in enumerate(items):
        r, cc = divmod(i, cols)
        if img.shape[2] == 4:
            img = img[..., :3]
        ih, iw = img.shape[:2]
        ys = (np.arange(cell) * ih // cell).clip(0, ih - 1)
        xs = (np.arange(cell) * iw // cell).clip(0, iw - 1)
        small = img[np.ix_(ys, xs)]
        y0 = pad + r * (cell + pad + 10)
        x0 = pad + cc * (cell + pad)
        sheet[y0:y0 + cell, x0:x0 + cell] = small
        _label_strip(sheet, y0 + cell + 1, x0, label, cell)
    write_png(out_path, sheet)
    return out_path


_FONT5 = {
    "A": ["01110", "10001", "11111", "10001", "10001"],
    "B": ["11110", "10001", "11110", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "11110", "10000", "11111"],
    "F": ["11111", "10000", "11110", "10000", "10000"],
    "G": ["01111", "10000", "10011", "10001", "01111"],
    "H": ["10001", "10001", "11111", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "11100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001"],
    "O": ["01110", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "11110", "10000", "10000"],
    "Q": ["01110", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "11110", "10010", "10001"],
    "S": ["01111", "10000", "01110", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10101", "11011", "10001"],
    "X": ["10001", "01010", "00100", "01010", "10001"],
    "Y": ["10001", "01010", "00100", "00100", "00100"],
    "Z": ["11111", "00010", "00100", "01000", "11111"],
    "0": ["01110", "10011", "10101", "11001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00110", "01000", "11111"],
    "3": ["11110", "00001", "00110", "00001", "11110"],
    "4": ["00010", "00110", "01010", "11111", "00010"],
    "5": ["11111", "10000", "11110", "00001", "11110"],
    "6": ["01110", "10000", "11110", "10001", "01110"],
    "7": ["11111", "00010", "00100", "01000", "01000"],
    "8": ["01110", "10001", "01110", "10001", "01110"],
    "9": ["01110", "10001", "01111", "00001", "01110"],
    "_": ["00000", "00000", "00000", "00000", "11111"],
    ".": ["00000", "00000", "00000", "00000", "00100"],
    "-": ["00000", "00000", "11111", "00000", "00000"],
    " ": ["00000", "00000", "00000", "00000", "00000"],
}


def _label_strip(sheet, y0, x0, text, width_px):
    t = text.upper()[: max(1, width_px // 6)]
    for k, ch in enumerate(t):
        pat = _FONT5.get(ch, _FONT5[" "])
        for ry, row in enumerate(pat):
            for rx, bit in enumerate(row):
                if bit == "1":
                    yy = y0 + ry
                    xx = x0 + k * 6 + rx
                    if 0 <= yy < sheet.shape[0] and 0 <= xx < sheet.shape[1]:
                        sheet[yy, xx] = (220, 215, 205)
