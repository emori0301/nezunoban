"""assets/textures/*.png を生成する。

blender --background --python tools/blender/gen_textures.py

すべて 256x256。level が床/壁に貼るものはシームレス(タイル可能)。
顔・遺影・時計盤など「模様が決まっているもの」はタイルしない(明示 UV で貼る)。
"""

import os
import sys
import math

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
from common import (save_tex, fbm, value_noise, white, norm, rgb, mix, mul_gray,
                    grunge, speckle, scratches, stains, posterize, finish,
                    rect, disc, ellipse, blur, tile_coords, rgba, stroke)

S = 256


def hstreak(a, n=10, axis=1):
    out = a.copy()
    for _ in range(n):
        out = (out + np.roll(out, 1, axis) + np.roll(out, -1, axis)) / 3.0
    return out


def periodic_lines(size, freq, axis=0, width=0.06, soft=0.02):
    t = (np.arange(size) + 0.5) / size
    p = np.abs(((t * freq) % 1.0) - 0.5) * 2.0    # 0..1 三角波
    m = np.clip((p - (1.0 - width)) / max(soft, 1e-6), 0.0, 1.0)
    if axis == 0:
        return m[:, None] * np.ones((1, size))
    return np.ones((size, 1)) * m[None, :]


# ---------------------------------------------------------------- 床・壁

def t_floor_lino():
    base = rgb(S, (0.82, 0.78, 0.67))
    fl = norm(fbm(S, cells=32, octaves=3, seed=11))
    base = mix(base, rgb(S, (0.72, 0.68, 0.58)), fl * 0.5)
    sp = (white(S, 12) > 0.985).astype(float)
    base = mix(base, rgb(S, (0.45, 0.42, 0.36)), sp * 0.7)
    sp2 = (white(S, 13) > 0.99).astype(float)
    base = mix(base, rgb(S, (0.93, 0.91, 0.85)), sp2 * 0.6)
    # タイルの目地(64px ごと)
    seam = np.maximum(periodic_lines(S, 2, 0, 0.030, 0.010),
                      periodic_lines(S, 2, 1, 0.030, 0.010))
    base = mix(base, rgb(S, (0.54, 0.50, 0.42)), seam * 0.70)
    g = grunge(S, 14, 0.30, cells=3) * stains(S, 15, 5, 0.25, 50) * scratches(S, 16, 60, 0.10, 50)
    return finish(mul_gray(base, g), 17)


def t_tatami():
    base = rgb(S, (0.68, 0.66, 0.42))
    # い草の織り(縦方向の筋 + 横の節)
    y = (np.arange(S) + 0.5) / S
    weave = 0.5 + 0.5 * np.sin(y * 2 * math.pi * 64)
    weave = np.ones((S, 1)) * weave[None, :]
    base = mul_gray(base, 0.88 + weave * 0.22)
    knot = 0.5 + 0.5 * np.sin(((np.arange(S) + 0.5) / S) * 2 * math.pi * 8)
    base = mul_gray(base, 0.94 + knot[:, None] * 0.10)
    disc_n = norm(fbm(S, cells=6, octaves=4, seed=21))
    base = mix(base, rgb(S, (0.55, 0.50, 0.30)), disc_n * 0.35)     # 日焼け・退色むら
    # 縁(へり): 上下端に紺地の布
    h = 16
    her = rgb(S, (0.12, 0.13, 0.22))
    hn = norm(fbm(S, cells=24, octaves=2, seed=22))
    her = mix(her, rgb(S, (0.30, 0.26, 0.16)), hn * 0.35)
    base[:h] = her[:h]
    base[S - h:] = her[S - h:]
    base = rect(base, h - 2, 0, h, S, (0.35, 0.32, 0.20), 0.5)
    base = rect(base, S - h, 0, S - h + 2, S, (0.35, 0.32, 0.20), 0.5)
    g = grunge(S, 23, 0.26) * stains(S, 24, 4, 0.20, 44)
    return finish(mul_gray(base, g), 25)


def t_wall_plaster():
    base = rgb(S, (0.86, 0.83, 0.74))
    n = norm(fbm(S, cells=4, octaves=6, seed=31))
    base = mix(base, rgb(S, (0.74, 0.69, 0.55)), n * 0.45)          # 黄ばみ
    fine = norm(fbm(S, cells=64, octaves=2, seed=32))
    base = mul_gray(base, 0.93 + fine * 0.12)
    # 雨だれ状の汚れ(上から下へ)
    drip = norm(fbm(S, cells=20, octaves=3, seed=33))
    drip = hstreak(drip, 14, axis=0)
    drip = np.clip((drip - 0.5) * 2.0, 0, 1)
    base = mix(base, rgb(S, (0.58, 0.54, 0.44)), drip * 0.30)
    g = stains(S, 34, 6, 0.24, 52) * scratches(S, 35, 25, 0.08, 34)
    return finish(mul_gray(base, g), 36)


def t_wall_wood():
    base = rgb(S, (0.42, 0.29, 0.18))
    x = (np.arange(S) + 0.5) / S
    g = norm(fbm(S, cells=8, octaves=4, seed=41))
    grain = 0.5 + 0.5 * np.sin(2 * math.pi * (x[:, None] * 26 + g * 2.4))
    base = mul_gray(base, 0.78 + grain * 0.36)
    base = mix(base, rgb(S, (0.26, 0.17, 0.10)), norm(fbm(S, 5, 4, 42)) * 0.4)
    # 板の継ぎ目(縦4枚)
    seam = periodic_lines(S, 4, 0, 0.035, 0.012)
    base = mix(base, rgb(S, (0.10, 0.07, 0.04)), seam * 0.9)
    hl = periodic_lines(S, 4, 0, 0.075, 0.05) - periodic_lines(S, 4, 0, 0.035, 0.012)
    base = mix(base, rgb(S, (0.52, 0.37, 0.24)), np.clip(hl, 0, 1) * 0.35)
    gg = grunge(S, 43, 0.28) * scratches(S, 44, 30, 0.10, 40)
    return finish(mul_gray(base, gg), 45)


def t_ceiling_tile():
    base = rgb(S, (0.80, 0.78, 0.72))
    n = norm(fbm(S, cells=48, octaves=3, seed=51))
    base = mul_gray(base, 0.90 + n * 0.16)
    # 穴あきボードの小穴
    r = np.random.default_rng(52)
    holes = np.zeros((S, S))
    for i in range(10, S, 11):
        for j in range(10, S, 11):
            ii = (i + int(r.integers(-2, 3))) % S
            jj = (j + int(r.integers(-2, 3))) % S
            holes[ii, jj] = 1.0
            holes[(ii + 1) % S, jj] = 0.6
            holes[ii, (jj + 1) % S] = 0.6
    base = mix(base, rgb(S, (0.30, 0.29, 0.27)), holes * 0.85)
    # 目地(2x2 枚)
    seam = np.maximum(periodic_lines(S, 2, 0, 0.018, 0.004),
                      periodic_lines(S, 2, 1, 0.018, 0.004))
    base = mix(base, rgb(S, (0.52, 0.50, 0.46)), seam * 0.8)
    g = stains(S, 53, 4, 0.30, 40)        # 雨漏りの染み
    return finish(mul_gray(base, g), 54)


def t_concrete():
    base = rgb(S, (0.55, 0.54, 0.52))
    n = norm(fbm(S, cells=5, octaves=6, seed=61))
    base = mul_gray(base, 0.78 + n * 0.40)
    sp = (white(S, 62) > 0.992).astype(float)
    base = mix(base, rgb(S, (0.33, 0.32, 0.30)), sp * 0.7)
    crack = norm(fbm(S, cells=10, octaves=3, seed=63))
    crack = np.clip(1.0 - np.abs(crack - 0.5) * 14.0, 0, 1)
    base = mix(base, rgb(S, (0.26, 0.25, 0.24)), crack * 0.35)
    return finish(mul_gray(base, grunge(S, 64, 0.22) * stains(S, 65, 5, 0.18, 46)), 66)


def t_asphalt():
    base = rgb(S, (0.20, 0.20, 0.21))
    n = norm(fbm(S, cells=64, octaves=3, seed=71))
    base = mul_gray(base, 0.70 + n * 0.60)
    sp = (white(S, 72) > 0.97).astype(float)
    base = mix(base, rgb(S, (0.42, 0.41, 0.39)), sp * 0.55)
    base = mix(base, rgb(S, (0.12, 0.12, 0.13)), norm(fbm(S, 6, 4, 73)) * 0.4)
    return finish(mul_gray(base, stains(S, 74, 4, 0.22, 50)), 75)


def t_wood_dark():
    base = rgb(S, (0.115, 0.082, 0.062))
    x = (np.arange(S) + 0.5) / S
    g = norm(fbm(S, cells=6, octaves=4, seed=81))
    grain = 0.5 + 0.5 * np.sin(2 * math.pi * (x[None, :] * 18 + g * 1.8))
    base = mul_gray(base, 0.72 + grain * 0.52)
    base = mix(base, rgb(S, (0.05, 0.035, 0.028)), norm(fbm(S, 4, 5, 82)) * 0.45)
    return finish(mul_gray(base, scratches(S, 83, 22, 0.10, 36)), 84, noise=0.02)


def t_white_wood():
    """白木(棺)。ほぼ白い柾目。"""
    base = rgb(S, (0.86, 0.81, 0.70))
    x = (np.arange(S) + 0.5) / S
    g = norm(fbm(S, cells=8, octaves=4, seed=91))
    grain = 0.5 + 0.5 * np.sin(2 * math.pi * (x[None, :] * 34 + g * 1.4))
    base = mul_gray(base, 0.90 + grain * 0.16)
    base = mix(base, rgb(S, (0.72, 0.66, 0.53)), norm(fbm(S, 5, 4, 92)) * 0.30)
    return finish(mul_gray(base, grunge(S, 93, 0.14)), 94)


def _noise1d(seed, cells, axis, size=None):
    """タイル可能な 1 次元ノイズ。2 次元場の等高線は「石の脈」に見えるので、
    皺は必ず片方の軸だけで変化させる。"""
    size = size or S
    g = value_noise(size, cells, seed)
    return norm(g.mean(axis=1 - axis))


def _folds(freq, wobble, seed, cells, axis, size=None):
    """平行な皺の帯。位置だけをもう片方の軸のノイズで揺らす。
    axis=0 なら縦に流れる皺。size は 256 以外のテクスチャ(胴など)で渡す。"""
    size = size or S
    t = (np.arange(size) + 0.5) / size
    n = _noise1d(seed, cells, 1 - axis, size)
    if axis == 0:
        f = t[:, None] * freq + n[None, :] * wobble
    else:
        f = t[None, :] * freq + n[:, None] * wobble
    return 0.5 + 0.5 * np.cos(2 * math.pi * f)


def t_white_cloth():
    """白布。棺台・祭壇の白幕・シーツで共用。
    石に見えないよう、皺は一方向に流れる帯にして、織り目を実際に出す。"""
    base = rgb(S, (0.885, 0.880, 0.858))

    # --- 織り目(縦糸・横糸。これが無いと布に見えない) ---
    base = mul_gray(base, 1.0 - periodic_lines(S, 56, 0, 0.44, 0.36) * 0.050)
    base = mul_gray(base, 1.0 - periodic_lines(S, 56, 1, 0.44, 0.36) * 0.042)
    base = mul_gray(base, 0.984 + white(S, 100) * 0.032)

    # --- 縦に流れるドレープ(主) ---
    d1 = _folds(5.0, 0.55, 111, 6, axis=0)
    amp1 = 0.07 + 0.06 * _noise1d(113, 5, 1)[None, :]
    base = mul_gray(base, 1.0 - amp1 * (1.0 - d1))

    # --- 横に走る緩い皺(従) ---
    d2 = _folds(3.0, 0.40, 112, 5, axis=1)
    base = mul_gray(base, 1.0 - 0.045 * (1.0 - d2))

    # --- 畳んだ折り目(まっすぐな線。谷は暗く、山は明るい) ---
    valley = periodic_lines(S, 2, 1, 0.016, 0.010)
    ridge = np.clip(periodic_lines(S, 2, 1, 0.060, 0.044) - valley, 0, 1)
    base = mul_gray(base, 1.0 - valley * 0.085)
    base = mix(base, rgb(S, (0.955, 0.950, 0.935)), ridge * 0.16)

    # --- 経年のくすみ ---
    base = mix(base, rgb(S, (0.79, 0.78, 0.745)), norm(fbm(S, 3, 3, 103)) * 0.13)
    return finish(mul_gray(base, grunge(S, 104, 0.07) * stains(S, 105, 3, 0.07, 26)),
                  106, noise=0.020)


def t_brocade():
    """金襴: 赤地に金の菱文様。"""
    base = rgb(S, (0.42, 0.06, 0.08))
    n = norm(fbm(S, cells=48, octaves=2, seed=111))
    base = mul_gray(base, 0.85 + n * 0.28)
    u, v = tile_coords(S)
    # 菱格子
    a = ((u * 6 + v * 6) % 1.0)
    b = ((u * 6 - v * 6) % 1.0)
    la = np.clip(1.0 - np.abs(a - 0.5) * 13.0, 0, 1)
    lb = np.clip(1.0 - np.abs(b - 0.5) * 13.0, 0, 1)
    lat = np.maximum(la, lb)
    gold = rgb(S, (0.78, 0.62, 0.20))
    gold = mul_gray(gold, 0.82 + norm(fbm(S, 32, 2, 112)) * 0.36)
    base = mix(base, gold, lat * 0.9)
    # 菱の中心に小さな金の点
    da = np.abs(a - 0.5) + np.abs(b - 0.5)
    dot = np.clip(1.0 - da * 9.0, 0, 1)
    base = mix(base, gold, dot * 0.8)
    return finish(mul_gray(base, grunge(S, 113, 0.16)), 114, levels=28)


def t_steel():
    base = rgb(S, (0.62, 0.63, 0.64))
    n = white(S, 121)
    n = hstreak(n, 16, axis=1)
    n = norm(n)
    base = mul_gray(base, 0.74 + n * 0.52)
    n2 = hstreak(white(S, 126), 4, axis=1)
    base = mul_gray(base, 0.92 + norm(n2) * 0.16)
    base = mul_gray(base, 0.94 + norm(fbm(S, 8, 3, 122)) * 0.16)
    return finish(mul_gray(base, scratches(S, 123, 45, 0.08, 46) * stains(S, 124, 3, 0.10, 30)), 125)


def t_glass_frost():
    base = rgb(S, (0.74, 0.78, 0.80))
    n = norm(fbm(S, cells=40, octaves=3, seed=131))
    base = mul_gray(base, 0.88 + n * 0.22)
    n2 = norm(fbm(S, cells=7, octaves=3, seed=132))
    base = mix(base, rgb(S, (0.62, 0.67, 0.70)), n2 * 0.30)
    return finish(base, 133)


def t_shoji():
    base = rgb(S, (0.88, 0.85, 0.74))
    n = norm(fbm(S, cells=56, octaves=2, seed=141))
    base = mul_gray(base, 0.93 + n * 0.12)
    base = mix(base, rgb(S, (0.76, 0.71, 0.58)), norm(fbm(S, 4, 4, 142)) * 0.25)
    # 組子(縦3 横4)
    lat = np.maximum(periodic_lines(S, 3, 0, 0.030, 0.006),
                     periodic_lines(S, 4, 1, 0.030, 0.006))
    base = mix(base, rgb(S, (0.30, 0.22, 0.14)), lat * 0.9)
    # 破れかけ・シミ
    base = mul_gray(base, stains(S, 143, 4, 0.22, 34))
    return finish(base, 144)


# ---------------------------------------------------------------- 小物素材

def t_metal_gray():
    base = rgb(S, (0.46, 0.47, 0.46))
    base = mul_gray(base, 0.92 + norm(fbm(S, 40, 3, 151)) * 0.16)
    base = mix(base, rgb(S, (0.35, 0.33, 0.30)), norm(fbm(S, 5, 4, 152)) * 0.30)
    rust = np.clip((norm(fbm(S, 12, 4, 153)) - 0.68) * 4.0, 0, 1)
    base = mix(base, rgb(S, (0.42, 0.24, 0.12)), rust * 0.65)
    return finish(mul_gray(base, scratches(S, 154, 40, 0.12, 40)), 155)


def t_metal_dark():
    base = rgb(S, (0.205, 0.215, 0.225))
    base = mul_gray(base, 0.85 + norm(fbm(S, 36, 3, 161)) * 0.30)
    rust = np.clip((norm(fbm(S, 10, 4, 162)) - 0.72) * 4.0, 0, 1)
    base = mix(base, rgb(S, (0.34, 0.19, 0.10)), rust * 0.5)
    return finish(mul_gray(base, scratches(S, 163, 30, 0.14, 36)), 164)


def t_plastic_beige():
    base = rgb(S, (0.76, 0.72, 0.62))
    base = mul_gray(base, 0.95 + norm(fbm(S, 64, 2, 171)) * 0.10)
    yellow = norm(fbm(S, 4, 4, 172))
    base = mix(base, rgb(S, (0.66, 0.58, 0.40)), yellow * 0.40)      # 日焼け
    return finish(mul_gray(base, scratches(S, 173, 20, 0.07, 26) * grunge(S, 174, 0.14)), 175)


def t_crt_screen():
    base = rgb(S, (0.045, 0.05, 0.055))
    scan = periodic_lines(S, 64, 0, 0.45, 0.4)
    base = mul_gray(base, 1.0 - scan * 0.35)
    glow = 1.0 - norm(np.sqrt(((np.arange(S)[:, None] - S / 2) / (S / 2)) ** 2
                              + ((np.arange(S)[None, :] - S / 2) / (S / 2)) ** 2))
    base = mix(base, rgb(S, (0.10, 0.12, 0.13)), glow * 0.35)
    base = mul_gray(base, 0.9 + white(S, 181) * 0.2)
    return finish(mul_gray(base, stains(S, 182, 3, 0.2, 40)), 183, noise=0.02)


def t_tv_static():
    n = white(S, 191)
    n = blur(n, 1)
    n = norm(n)
    base = rgb(S, (1, 1, 1)) * n[..., None]
    base = mul_gray(base, 1.0 - periodic_lines(S, 64, 0, 0.4, 0.4) * 0.25)
    band = np.clip(1.0 - np.abs((np.arange(S) - 60) / 12.0), 0, 1)
    base = mix(base, rgb(S, (0.85, 0.85, 0.88)), (band[:, None] * np.ones((1, S))) * 0.4)
    return finish(base, 192, noise=0.0, levels=16)


def t_zabuton():
    base = rgb(S, (0.40, 0.13, 0.17))
    base = mul_gray(base, 0.88 + norm(fbm(S, 48, 3, 201)) * 0.22)
    fade = norm(fbm(S, 3, 4, 202))
    base = mix(base, rgb(S, (0.52, 0.34, 0.32)), fade * 0.45)        # 色褪せ
    u, v = tile_coords(S)
    a = ((u * 4 + v * 4) % 1.0)
    b = ((u * 4 - v * 4) % 1.0)
    lat = np.maximum(np.clip(1 - np.abs(a - 0.5) * 16, 0, 1),
                     np.clip(1 - np.abs(b - 0.5) * 16, 0, 1))
    base = mix(base, rgb(S, (0.58, 0.40, 0.18)), lat * 0.35)
    return finish(mul_gray(base, grunge(S, 203, 0.24) * stains(S, 204, 4, 0.2, 34)), 205)


def t_futon_cloth():
    """掛け布団の側生地。紺の格子(和柄)がはっきり出るようにする。"""
    base = rgb(S, (0.82, 0.79, 0.71))
    base = mul_gray(base, 0.94 + norm(fbm(S, 56, 2, 211)) * 0.12)
    # 織り目
    base = mul_gray(base, 1.0 - periodic_lines(S, 64, 0, 0.40, 0.34) * 0.05)
    base = mul_gray(base, 1.0 - periodic_lines(S, 64, 1, 0.40, 0.34) * 0.04)

    navy = rgb(S, (0.20, 0.24, 0.36))
    navy = mul_gray(navy, 0.85 + norm(fbm(S, 40, 2, 216)) * 0.30)
    # 太い格子(縦横)
    wide_u = periodic_lines(S, 4, 0, 0.055, 0.018)
    wide_v = periodic_lines(S, 4, 1, 0.055, 0.018)
    base = mix(base, navy, np.maximum(wide_u, wide_v) * 0.46)
    # 細い格子(太い線の間に 1 本ずつ)
    thin_u = periodic_lines(S, 8, 0, 0.022, 0.012)
    thin_v = periodic_lines(S, 8, 1, 0.022, 0.012)
    base = mix(base, navy, np.maximum(thin_u, thin_v) * 0.22)
    # 交点だけ少し濃い
    base = mix(base, navy * 0.80, (wide_u * wide_v) * 0.30)

    # 布らしい皺(白布と同じく一方向の帯で)
    base = mul_gray(base, 1.0 - 0.075 * (1.0 - _folds(4.0, 0.48, 212, 5, axis=0)))
    base = mul_gray(base, 1.0 - 0.040 * (1.0 - _folds(2.5, 0.35, 217, 4, axis=1)))
    return finish(mul_gray(base, grunge(S, 213, 0.16) * stains(S, 214, 3, 0.14, 30)), 215)


def t_fur_black():
    base = rgb(S, (0.085, 0.085, 0.095))
    n = white(S, 221)
    n = hstreak(n, 3, axis=0)
    n = norm(n)
    base = mul_gray(base, 0.55 + n * 0.95)
    base = mix(base, rgb(S, (0.14, 0.13, 0.15)), norm(fbm(S, 12, 3, 222)) * 0.35)
    return finish(base, 223, noise=0.05)


def t_kasha_skin():
    base = rgb(S, (0.055, 0.052, 0.062))
    n = norm(fbm(S, 20, 4, 231))
    base = mul_gray(base, 0.5 + n * 1.0)
    streak = hstreak(norm(white(S, 232)), 6, axis=0)
    base = mul_gray(base, 0.8 + norm(streak) * 0.5)
    return finish(base, 233, noise=0.04, levels=20)


def t_suit_black():
    base = rgb(S, (0.105, 0.105, 0.120))
    base = mul_gray(base, 0.88 + norm(fbm(S, 64, 2, 241)) * 0.22)
    base = mix(base, rgb(S, (0.14, 0.14, 0.16)), norm(fbm(S, 6, 3, 242)) * 0.3)
    return finish(base, 243, noise=0.025)


def t_dress_black():
    base = rgb(S, (0.090, 0.090, 0.105))
    base = mul_gray(base, 0.85 + norm(fbm(S, 40, 3, 251)) * 0.3)
    w = norm(fbm(S, 6, 4, 252))
    base = mul_gray(base, 1.0 - np.clip(1 - np.abs(w - 0.5) * 8, 0, 1) * 0.25)
    return finish(base, 253, noise=0.025)


def t_jumper():
    """くたびれたジャンパー(くすんだ紺 + 擦れ)。"""
    base = rgb(S, (0.17, 0.20, 0.26))
    base = mul_gray(base, 0.86 + norm(fbm(S, 40, 3, 261)) * 0.28)
    worn = np.clip((norm(fbm(S, 5, 4, 262)) - 0.55) * 3.0, 0, 1)
    base = mix(base, rgb(S, (0.34, 0.34, 0.36)), worn * 0.45)
    return finish(mul_gray(base, scratches(S, 263, 30, 0.1, 40) * stains(S, 264, 4, 0.2, 34)), 265)


def t_skin_pale():
    base = rgb(S, (0.74, 0.62, 0.54))
    base = mul_gray(base, 0.93 + norm(fbm(S, 40, 3, 271)) * 0.14)
    base = mix(base, rgb(S, (0.62, 0.48, 0.42)), norm(fbm(S, 6, 3, 272)) * 0.25)
    return finish(base, 273)


def _skin(base, seed, sallow=0.0, sallow_col=None, ruddy=0.0):
    """顔テクスチャと色を合わせた肌。首・耳・手に使う。
    顔だけ暗くすると、頭の側面や首との境に段が出る。"""
    img = rgb(S, base)
    img = mul_gray(img, 0.93 + norm(fbm(S, 40, 3, seed)) * 0.14)
    img = mix(img, rgb(S, tuple(c * 0.84 for c in base)), norm(fbm(S, 6, 3, seed + 1)) * 0.24)
    if sallow > 0:
        img = mix(img, rgb(S, sallow_col or (0.66, 0.60, 0.42)), sallow * 0.16)
    if ruddy > 0:
        img = mix(img, rgb(S, (0.74, 0.34, 0.28)),
                  np.clip((norm(fbm(S, 26, 3, seed + 2)) - 0.66) * 4.0, 0, 1) * ruddy * 0.26)
    return finish(img, seed + 5)


def t_skin_boss():
    return _skin((0.585, 0.470, 0.375), 801, sallow=0.70, sallow_col=(0.50, 0.43, 0.26))


def t_skin_son():
    return _skin((0.74, 0.52, 0.42), 811, ruddy=0.85)


def t_skin_gd():
    return _skin((0.755, 0.615, 0.545), 821)


def t_paper_yellow():
    base = rgb(S, (0.84, 0.80, 0.67))
    base = mul_gray(base, 0.94 + norm(fbm(S, 48, 2, 281)) * 0.12)
    base = mix(base, rgb(S, (0.70, 0.64, 0.46)), norm(fbm(S, 4, 4, 282)) * 0.35)
    # 罫線らしきもの
    base = mix(base, rgb(S, (0.55, 0.52, 0.44)),
               periodic_lines(S, 16, 0, 0.05, 0.02) * 0.25)
    return finish(mul_gray(base, stains(S, 283, 5, 0.22, 34)), 284)


def t_cardboard():
    base = rgb(S, (0.60, 0.48, 0.33))
    base = mul_gray(base, 0.90 + norm(fbm(S, 48, 3, 291)) * 0.20)
    base = mul_gray(base, 1.0 - periodic_lines(S, 40, 1, 0.3, 0.25) * 0.10)
    return finish(mul_gray(base, grunge(S, 292, 0.2) * scratches(S, 293, 20, 0.1, 30)), 294)


def t_styrofoam():
    base = rgb(S, (0.90, 0.90, 0.88))
    r = np.random.default_rng(301)
    bead = np.zeros((S, S))
    for _ in range(1400):
        i, j = int(r.integers(0, S)), int(r.integers(0, S))
        bead[i, j] = 1.0
    bead = norm(blur(bead, 2))
    base = mul_gray(base, 0.88 + bead * 0.20)
    return finish(mul_gray(base, grunge(S, 302, 0.10)), 303)


def t_gold():
    base = rgb(S, (0.72, 0.56, 0.18))
    base = mul_gray(base, 0.80 + norm(fbm(S, 24, 3, 311)) * 0.45)
    base = mix(base, rgb(S, (0.42, 0.32, 0.10)), norm(fbm(S, 6, 3, 312)) * 0.35)
    return finish(base, 313, levels=24)


def t_paint_red():
    base = rgb(S, (0.55, 0.09, 0.07))
    base = mul_gray(base, 0.90 + norm(fbm(S, 48, 2, 321)) * 0.18)
    base = mix(base, rgb(S, (0.30, 0.06, 0.05)), norm(fbm(S, 5, 3, 322)) * 0.3)
    return finish(mul_gray(base, scratches(S, 323, 30, 0.12, 30)), 324)


def t_ash():
    base = rgb(S, (0.68, 0.66, 0.62))
    base = mul_gray(base, 0.80 + norm(fbm(S, 32, 4, 331)) * 0.40)
    base = mix(base, rgb(S, (0.42, 0.40, 0.37)), norm(fbm(S, 8, 3, 332)) * 0.35)
    return finish(base, 333)


def t_flower_white():
    base = rgb(S, (0.78, 0.77, 0.70))
    base = mul_gray(base, 0.85 + norm(fbm(S, 16, 3, 340)) * 0.30)
    r = np.random.default_rng(341)
    gx, gy = np.meshgrid(np.arange(S), np.arange(S), indexing="ij")
    for _ in range(26):
        cx = float(r.integers(0, S)); cy = float(r.integers(0, S))
        rad = 16 + r.random() * 16
        ang = np.arctan2(np.minimum(np.abs(gy - cy), S - np.abs(gy - cy)) * np.sign(gy - cy),
                         np.minimum(np.abs(gx - cx), S - np.abs(gx - cx)) * np.sign(gx - cx))
        dx = np.minimum(np.abs(gx - cx), S - np.abs(gx - cx))
        dy = np.minimum(np.abs(gy - cy), S - np.abs(gy - cy))
        d = np.sqrt(dx * dx + dy * dy) / (rad * (0.78 + 0.22 * np.abs(np.sin(ang * 8))))
        m = np.clip((1.0 - d) * 3.0, 0, 1)
        shade = 0.86 + 0.14 * np.cos(ang * 8)
        col = np.stack([shade, shade * 0.995, shade * 0.95], axis=2) * (0.95 + r.random() * 0.08)
        base = base * (1 - m[..., None]) + np.clip(col, 0, 1) * m[..., None]
        base = mix(base, rgb(S, (0.62, 0.60, 0.52)),
                   np.clip((d - 0.70) * 3.0, 0, 1) * m * 0.5)
    return finish(base, 342)


def t_leaves_dark():
    base = rgb(S, (0.09, 0.14, 0.09))
    n = norm(fbm(S, 16, 4, 351))
    base = mul_gray(base, 0.55 + n * 0.95)
    base = mix(base, rgb(S, (0.16, 0.20, 0.11)), (white(S, 352) > 0.9).astype(float) * 0.4)
    return finish(base, 353, noise=0.05)


def t_bark():
    base = rgb(S, (0.21, 0.17, 0.13))
    y = (np.arange(S) + 0.5) / S
    g = norm(fbm(S, 8, 4, 361))
    ridge = 0.5 + 0.5 * np.sin(2 * math.pi * (y[:, None] * 16 + g * 3.0))
    base = mul_gray(base, 0.62 + ridge * 0.70)
    return finish(base, 362, noise=0.04)


def t_car_black():
    base = rgb(S, (0.080, 0.080, 0.090))
    base = mul_gray(base, 0.9 + norm(fbm(S, 56, 2, 371)) * 0.2)
    return finish(mul_gray(base, scratches(S, 372, 14, 0.08, 30)), 373, noise=0.015)


def t_slipper():
    base = rgb(S, (0.22, 0.34, 0.26))
    base = mul_gray(base, 0.9 + norm(fbm(S, 48, 2, 381)) * 0.2)
    base = mix(base, rgb(S, (0.42, 0.40, 0.34)), norm(fbm(S, 5, 3, 382)) * 0.3)
    return finish(mul_gray(base, grunge(S, 383, 0.22)), 384)


def t_porcelain():
    """便器・洗面の白い陶器。ほぼ真っ白で、貫入と隅の汚れだけ。"""
    base = rgb(S, (0.905, 0.905, 0.885))
    base = mul_gray(base, 0.975 + norm(fbm(S, 44, 2, 621)) * 0.050)
    base = mix(base, rgb(S, (0.82, 0.82, 0.80)), norm(fbm(S, 4, 3, 622)) * 0.16)
    cr = norm(fbm(S, 13, 3, 623))
    cr = np.clip(1.0 - np.abs(cr - 0.5) * 30.0, 0, 1)          # 貫入(細いひび)
    base = mix(base, rgb(S, (0.70, 0.70, 0.68)), cr * 0.20)
    return finish(mul_gray(base, stains(S, 624, 3, 0.11, 26)), 625, noise=0.018)


def t_tile_white():
    base = rgb(S, (0.80, 0.81, 0.78))
    base = mul_gray(base, 0.95 + norm(fbm(S, 48, 2, 391)) * 0.10)
    seam = np.maximum(periodic_lines(S, 8, 0, 0.05, 0.01),
                      periodic_lines(S, 8, 1, 0.05, 0.01))
    base = mix(base, rgb(S, (0.52, 0.52, 0.48)), seam * 0.75)
    return finish(mul_gray(base, stains(S, 392, 5, 0.22, 30)), 393)


# ---------------------------------------------------------------- 顔(非タイル)

def _old_face(img, cx, cy, sc, eyes="closed", mouth="closed", turn=0.0, seed=400,
              skin=None, shade=None):
    """img に老女の顔を描く。cx=行(上下), cy=列(左右), sc=顔の高さ半径。"""
    skin = skin or (0.78, 0.71, 0.66)
    shade = shade or (0.60, 0.52, 0.50)
    dark = (0.30, 0.24, 0.24)
    ty = cy + turn * sc * 0.62

    # 顔の輪郭(縦長の楕円。第1引数=行=縦、第2引数=列=横)
    ellipse(img, cx, ty, sc, sc * 0.64, skin, 1.0, soft=1.6)
    # 顎のとがり
    ellipse(img, cx + sc * 0.68, ty, sc * 0.34, sc * 0.40, skin, 1.0, soft=3)
    # 頬のこけ(縦に落ちくぼんだ影)
    ellipse(img, cx + sc * 0.22, ty - sc * 0.42, sc * 0.30, sc * 0.14, shade, 0.45, soft=7)
    ellipse(img, cx + sc * 0.22, ty + sc * 0.42, sc * 0.30, sc * 0.14, shade, 0.45, soft=7)
    # こめかみの影
    ellipse(img, cx - sc * 0.34, ty - sc * 0.52, sc * 0.22, sc * 0.10, shade, 0.35, soft=6)
    ellipse(img, cx - sc * 0.34, ty + sc * 0.52, sc * 0.22, sc * 0.10, shade, 0.35, soft=6)
    ellipse(img, cx - sc * 0.72, ty, sc * 0.16, sc * 0.44, shade, 0.22, soft=10)  # 額の影
    # 眉
    ellipse(img, cx - sc * 0.30, ty - sc * 0.34, sc * 0.035, sc * 0.17, (0.42, 0.38, 0.36), 0.7, soft=2)
    ellipse(img, cx - sc * 0.30, ty + sc * 0.34, sc * 0.035, sc * 0.17, (0.42, 0.38, 0.36), 0.7, soft=2)

    ey = cx - sc * 0.12
    exl = ty - sc * 0.30
    exr = ty + sc * 0.30
    if eyes == "closed":
        for ex in (exl, exr):
            ellipse(img, ey, ex, sc * 0.030, sc * 0.17, dark, 0.85, soft=1.2)
            ellipse(img, ey + sc * 0.05, ex, sc * 0.02, sc * 0.15, shade, 0.5, soft=2)
    else:
        for k, ex in enumerate((exl, exr)):
            ellipse(img, ey, ex, sc * 0.10, sc * 0.16, (0.86, 0.85, 0.80), 1.0, soft=1.2)
            gaze = turn * sc * 0.06
            ellipse(img, ey + sc * 0.01, ex + gaze, sc * 0.062, sc * 0.062, (0.10, 0.09, 0.09), 1.0, soft=1.0)
            ellipse(img, ey + sc * 0.01, ex + gaze, sc * 0.028, sc * 0.028, (0.02, 0.02, 0.02), 1.0, soft=0.8)
            # 上まぶたの影
            ellipse(img, ey - sc * 0.11, ex, sc * 0.05, sc * 0.17, shade, 0.55, soft=2)
    # 目の下のくぼみ
    for ex in (exl, exr):
        ellipse(img, ey + sc * 0.14, ex, sc * 0.05, sc * 0.15, shade, 0.30, soft=4)

    # 鼻
    ellipse(img, cx + sc * 0.12, ty, sc * 0.16, sc * 0.09, shade, 0.35, soft=4)
    ellipse(img, cx + sc * 0.24, ty - sc * 0.07, sc * 0.022, sc * 0.022, dark, 0.7, soft=1)
    ellipse(img, cx + sc * 0.24, ty + sc * 0.07, sc * 0.022, sc * 0.022, dark, 0.7, soft=1)

    # 口
    my = cx + sc * 0.50
    if mouth == "open":
        ellipse(img, my, ty, sc * 0.085, sc * 0.13, (0.07, 0.05, 0.05), 0.95, soft=1.4)
        ellipse(img, my - sc * 0.06, ty, sc * 0.03, sc * 0.14, (0.52, 0.42, 0.40), 0.6, soft=2)
    else:
        ellipse(img, my, ty, sc * 0.022, sc * 0.17, (0.38, 0.28, 0.28), 0.8, soft=1.4)
    # 口元の皺
    ellipse(img, my - sc * 0.05, ty - sc * 0.22, sc * 0.16, sc * 0.02, shade, 0.4, soft=3)
    ellipse(img, my - sc * 0.05, ty + sc * 0.22, sc * 0.16, sc * 0.02, shade, 0.4, soft=3)
    # 顎
    ellipse(img, cx + sc * 0.80, ty, sc * 0.10, sc * 0.22, shade, 0.25, soft=6)
    return img


def _face_plate(eyes, mouth, turn, seed):
    """白布に囲まれた老女の顔。棺の小窓越しに見る用。"""
    # 白布(皺あり)
    img = rgb(S, (0.84, 0.83, 0.80))
    w = norm(fbm(S, 5, 4, seed + 1))
    fold = np.clip(1.0 - np.abs(w - 0.5) * 6.0, 0, 1)
    img = mul_gray(img, 1.0 - fold * 0.28)
    img = mul_gray(img, 0.95 + norm(fbm(S, 40, 2, seed + 2)) * 0.10)

    gx, gy = np.meshgrid(np.arange(S), np.arange(S), indexing="ij")

    # 布の開口(顔の周りに落ちる影)
    d = np.sqrt(((gx - 130) / 100.0) ** 2 + ((gy - 128) / 74.0) ** 2)
    img = mul_gray(img, np.clip(0.45 + d * 0.75, 0, 1.0))
    ring = np.clip((d - 0.86) * 5.0, 0, 1) * np.clip((1.30 - d) * 3.5, 0, 1)
    img = mix(img, rgb(S, (0.20, 0.19, 0.19)), ring * 0.70)

    # 白髪(額の上、布の内側から少しだけ)
    ellipse(img, 34, 128, 30, 58, (0.55, 0.54, 0.53), 0.85, soft=6)
    ellipse(img, 26, 128, 22, 48, (0.70, 0.69, 0.68), 0.55, soft=8)

    # 血の気の無い、蝋のような肌
    skin = (0.70, 0.665, 0.635)
    shade = (0.47, 0.45, 0.45)
    _old_face(img, 132, 128, 88, eyes=eyes, mouth=mouth, turn=turn, seed=seed,
              skin=skin, shade=shade)

    # 死斑・くすみ
    blot = np.clip((norm(fbm(S, 9, 4, seed + 3)) - 0.60) * 3.0, 0, 1)
    face_m = np.clip((1.0 - d) * 3.0, 0, 1)
    img = mix(img, rgb(S, (0.44, 0.38, 0.40)), blot * face_m * 0.45)

    # 上からの弱い光 + 強いビネット(小窓の外は暗い)
    vg = np.clip(1.0 - ((gx - 105) / 175.0) ** 2 - ((gy - 128) / 175.0) ** 2, 0, 1)
    img = mul_gray(img, 0.30 + vg * 0.85)
    img = mul_gray(img, stains(S, seed + 5, 4, 0.18, 34))
    return finish(img, seed + 6, noise=0.05, levels=22)


def t_body_face_calm():
    return _face_plate("closed", "closed", 0.0, 410)


def t_body_face_mouth():
    return _face_plate("closed", "open", 0.0, 420)


def t_body_face_eyes():
    return _face_plate("open", "open", 0.0, 430)


def t_body_face_turned():
    return _face_plate("open", "closed", 0.85, 440)


def t_iei_photo():
    """白黒の遺影。笑っているが目はこちらを見ている。"""
    # 写真館の暗いグラデ背景
    gx, gy = np.meshgrid(np.arange(S), np.arange(S), indexing="ij")
    bg = np.clip(0.66 - np.sqrt(((gx - 60) / 300.0) ** 2 + ((gy - 128) / 300.0) ** 2) * 0.40, 0.22, 1.0)
    img = np.stack([bg, bg, bg], axis=2)
    img = mul_gray(img, 0.90 + norm(fbm(S, 5, 3, 451)) * 0.20)

    # 黒い着物の肩
    ellipse(img, 252, 128, 86, 104, (0.10, 0.10, 0.11), 1.0, soft=5)
    ellipse(img, 244, 128, 62, 46, (0.17, 0.17, 0.18), 0.9, soft=8)
    # 白い半襟
    ellipse(img, 204, 128, 18, 26, (0.70, 0.69, 0.67), 0.85, soft=6)
    ellipse(img, 210, 128, 20, 16, (0.12, 0.12, 0.13), 1.0, soft=3)
    # 首
    rect(img, 166, 112, 206, 144, (0.60, 0.57, 0.55), 1.0)
    ellipse(img, 176, 128, 16, 22, (0.46, 0.44, 0.43), 0.5, soft=6)

    # 結い上げた白髪(顔より先に置く)
    ellipse(img, 96, 128, 64, 54, (0.66, 0.65, 0.64), 1.0, soft=4)
    ellipse(img, 44, 128, 26, 40, (0.74, 0.73, 0.72), 1.0, soft=5)

    _old_face(img, 116, 128, 58, eyes="open", mouth="closed", turn=0.0, seed=452,
              skin=(0.72, 0.68, 0.65), shade=(0.48, 0.45, 0.44))

    # 笑顔: 口角を上げ、目尻に皺
    ellipse(img, 116 + 58 * 0.50, 128, 58 * 0.026, 58 * 0.20, (0.30, 0.27, 0.26), 0.9, soft=1.4)
    ellipse(img, 116 + 58 * 0.44, 128 - 58 * 0.20, 58 * 0.045, 58 * 0.045, (0.58, 0.55, 0.53), 0.8, soft=2)
    ellipse(img, 116 + 58 * 0.44, 128 + 58 * 0.20, 58 * 0.045, 58 * 0.045, (0.58, 0.55, 0.53), 0.8, soft=2)
    ellipse(img, 116 + 58 * 0.56, 128, 58 * 0.10, 58 * 0.13, (0.62, 0.58, 0.56), 0.4, soft=4)
    for sgn in (-1, 1):
        ellipse(img, 116 - 58 * 0.06, 128 + sgn * 58 * 0.46, 58 * 0.085, 58 * 0.030,
                (0.46, 0.44, 0.43), 0.6, soft=2)
        ellipse(img, 116 + 58 * 0.02, 128 + sgn * 58 * 0.44, 58 * 0.07, 58 * 0.028,
                (0.46, 0.44, 0.43), 0.45, soft=2)
    # 前髪の影を額に
    ellipse(img, 116 - 58 * 0.86, 128, 58 * 0.18, 58 * 0.50, (0.40, 0.38, 0.37), 0.45, soft=6)

    # モノクロ・コントラスト上げ
    lum = img.mean(axis=2)
    lum = np.clip((lum - 0.5) * 1.12 + 0.50, 0, 1)
    img = np.stack([lum, lum * 0.985, lum * 0.95], axis=2)
    # ビネット + 粒子
    d = np.sqrt(((gx - 128) / 230.0) ** 2 + ((gy - 128) / 230.0) ** 2)
    img = mul_gray(img, np.clip(1.08 - d * 0.40, 0, 1.2))
    img = mul_gray(img, stains(S, 453, 4, 0.12, 40))
    return finish(img, 454, noise=0.05, levels=22)


def t_iei_photo_player():
    """暗く潰れて誰か分からない人物写真。"""
    img = rgb(S, (0.18, 0.18, 0.19))
    g = norm(fbm(S, 5, 4, 461))
    img = mul_gray(img, 0.6 + g * 0.6)
    ellipse(img, 240, 128, 76, 92, (0.09, 0.09, 0.10), 1.0, soft=8)
    ellipse(img, 120, 128, 58, 46, (0.30, 0.28, 0.27), 1.0, soft=10)   # 顔らしき塊
    ellipse(img, 104, 128, 30, 40, (0.36, 0.34, 0.33), 0.6, soft=14)
    ellipse(img, 116, 108, 8, 10, (0.10, 0.10, 0.10), 0.8, soft=4)
    ellipse(img, 116, 148, 8, 10, (0.10, 0.10, 0.10), 0.8, soft=4)
    img = blur(img, 2)
    lum = img.mean(axis=2)
    img = np.stack([lum, lum, lum * 1.02], axis=2)
    gx, gy = np.meshgrid(np.arange(S), np.arange(S), indexing="ij")
    d = np.sqrt(((gx - 128) / 140.0) ** 2 + ((gy - 128) / 140.0) ** 2)
    img = mul_gray(img, np.clip(1.10 - d * 0.75, 0, 1.2))
    return finish(img, 462, noise=0.07, levels=16)


# ---------------------------------------------------------------- 顔(NPC)

def _degrade(img, seed, out=128, fade=0.18, grain=0.085, block=0.13, contrast=1.0):
    """写真を劣化させたような仕上げ。256 で描いて out へ落とす。
    ぼかし → 縮小 → 粒子 → 色ノイズ → ブロックノイズ → 退色 → 減色。"""
    R = img.shape[0]
    img = blur(img, 1)
    f = R // out
    small = img.reshape(out, f, out, f, 3).mean(axis=(1, 3))
    small = mul_gray(small, 1.0 - grain * 0.5 + white(out, seed + 21) * grain)
    for c in range(3):
        small[..., c] = small[..., c] * (0.985 + white(out, seed + 30 + c) * 0.030)
    nb = out // 8
    blk = small.reshape(nb, 8, nb, 8, 3).mean(axis=(1, 3))
    blk = np.repeat(np.repeat(blk, 8, axis=0), 8, axis=1)
    small = mix(small, blk, block)
    lum = small.mean(axis=2, keepdims=True)
    small = mix(small, np.repeat(lum, 3, axis=2), fade)
    small = np.clip((small - 0.5) * (0.94 * contrast) + 0.5, 0, 1)
    return posterize(small, 28)


def _photo_face(skin, brow, seed, age=0.6, ruddy=0.0, stubble=0.0, bags=0.5,
                female=False, lips=None, sallow=0.0, sallow_col=None, jowl=0.0,
                brow_w=1.0, eye=1.0, lip_full=1.0, blush=0.0, eye_red=0.0,
                nose_big=0.0, shade=0.70, feat=1.0, contrast=1.0):
    """shade: 影の濃さ(小さいほど濃い)。feat: 目鼻口の陰影の強さ。
    contrast: 仕上げのコントラスト。640x360 + VHS で顔が潰れるときに上げる。"""
    """人物の顔。1 枚で頭の正面だけに貼る(128x128)。
    アニメ絵にならないよう、輪郭線を引かず、面の明暗と皺で作る。"""
    R = 256
    rng = np.random.default_rng(seed)
    sh = tuple(c * shade for c in skin)
    dk = tuple(c * (shade * 0.63) for c in skin)
    hl = tuple(min(1.0, c * 1.14) for c in skin)
    lips = lips or (min(1.0, skin[0] * 1.02), skin[1] * 0.70, skin[2] * 0.70)

    img = rgb(R, skin)
    # 肌のムラ(血色と日焼けの斑)
    img = mul_gray(img, 0.92 + norm(fbm(R, 7, 4, seed + 1)) * 0.16)
    img = mix(img, rgb(R, tuple(c * 0.88 for c in skin)), norm(fbm(R, 16, 3, seed + 2)) * 0.20)
    img = mix(img, rgb(R, hl), norm(fbm(R, 4, 3, seed + 3)) * 0.12)

    # --- 面の明暗(立体感) ---
    for sgn in (-1, 1):
        ellipse(img, 140, 128 + sgn * 120, 150, 62, sh, 0.58, soft=72)   # 側面を落とす
        ellipse(img, 118, 128 + sgn * 96, 46, 26, sh, 0.30, soft=36)     # こめかみ
        ellipse(img, 134, 128 + sgn * 62, 30, 34, hl, 0.26, soft=42)     # 頬骨
    ellipse(img, 60, 128, 40, 72, hl, 0.32, soft=48)                     # 額
    ellipse(img, 88, 128, 15, 88, sh, 0.20 * feat, soft=32)                     # 眉の張り出し
    ellipse(img, 130, 128, 50, 13, hl, 0.30, soft=22)                    # 鼻筋
    for sgn in (-1, 1):
        ellipse(img, 146, 128 + sgn * 27, 36, 12, sh, 0.34 * feat, soft=20)     # 鼻の脇
        ellipse(img, 158, 128 + sgn * 22, 12, 13, sh, 0.42 * feat, soft=8)      # 小鼻
        ellipse(img, 161, 128 + sgn * 20, 6, 7, dk, min(1.0, 0.50 * feat), soft=5)        # 鼻孔
    ellipse(img, 152, 128, 12, 16, hl, 0.22, soft=10)                    # 鼻頭
    ellipse(img, 170, 128, 9, 20, sh, 0.28 * feat, soft=11)                     # 鼻の下
    ellipse(img, 236, 128, 28, 62, sh, 0.34, soft=32)                    # 顎の下
    ellipse(img, 214, 128, 18, 34, hl, 0.20, soft=22)                    # 顎の先

    # --- 眉 ---
    for sgn in (-1, 1):
        bx = 128 + sgn * 46
        ellipse(img, 86, bx, 7 * brow_w, 29 * (0.85 + 0.15 * brow_w), brow,
                min(1.0, (0.32 + 0.16 * brow_w) * feat), soft=8)
        for _ in range(int(30 * brow_w) + 8):
            t = rng.random()
            r0 = 86 + rng.normal(0, 3.0 * brow_w)
            c0 = bx - 27 + t * 54
            stroke(img, (r0, c0), (r0 - 2 - rng.random() * 4 * brow_w, c0 + sgn * 5),
                   1.4 * brow_w + 0.4, brow, min(1.0, 0.36 * feat), soft=1.6)

    # --- 目 ---
    for i, sgn in enumerate((-1, 1)):
        ex = 128 + sgn * 46 + (2 if i else -1)        # 少し非対称にする
        ey = 112 + (1 if i else 0)
        eh = 10.5 * eye
        ew = 21.0 * eye
        ellipse(img, ey, ex, 21, 33, sh, min(1.0, 0.28 * feat), soft=17)                  # 眼窩
        sclera = (0.86, 0.845, 0.815) if female else (0.78, 0.76, 0.72)
        ellipse(img, ey, ex, eh, ew, sclera, 0.92, soft=3.0)   # 白目
        if eye_red > 0:
            ellipse(img, ey + 4, ex, eh * 0.7, ew, (0.70, 0.40, 0.38),
                    eye_red * 0.45, soft=6)
        ellipse(img, ey - eh * 1.15, ex, eh * 0.80, ew * 1.08, sh,
                min(1.0, (0.34 if female else 0.55) * feat), soft=6)
        ellipse(img, ey + 1, ex, eh * 0.88, eh * 0.88, (0.26, 0.18, 0.12), 0.88, soft=3.0)
        ellipse(img, ey + 1, ex, eh * 0.46, eh * 0.46, (0.09, 0.06, 0.05), 0.90, soft=2.2)
        ellipse(img, ey - 3, ex - 4, 2.4, 2.4, (0.90, 0.89, 0.86), 0.62, soft=1.6)
        stroke(img, (ey - eh, ex - ew * 0.9), (ey - eh - 1, ex + ew * 0.9),
               2.6 + 1.2 * female, (0.22, 0.17, 0.14),
               min(1.0, (0.50 + 0.22 * female) * feat), soft=3.0)
        stroke(img, (ey + eh, ex - ew * 0.78), (ey + eh + 1, ex + ew * 0.78),
               2.2, sh, 0.38, soft=3.2)
        ellipse(img, ey + 21, ex, 13, 25, (0.44, 0.33, 0.37), bags * 0.42, soft=15)
        ellipse(img, ey + 14, ex, 5, 22, sh, bags * 0.32, soft=5)        # 涙袋の影
        if bags > 0.7:                                                    # 深いくまは二重に
            ellipse(img, ey + 27, ex, 8, 22, (0.40, 0.30, 0.34), (bags - 0.7) * 0.9, soft=12)

    # --- 口 ---
    my = 194
    mw = 36 * (0.88 + 0.22 * lip_full)
    ellipse(img, my + 5, 128, 9 * lip_full, mw * 0.94, lips, 0.46 + 0.16 * lip_full, soft=8)
    ellipse(img, my - 6, 128, 7 * lip_full, mw * 0.86, lips, 0.34, soft=7)
    stroke(img, (my, 128 - mw * 0.88), (my, 128 + mw * 0.88), 2.8 + 0.6 * (feat - 1.0),
           (0.28, 0.16, 0.15), min(1.0, 0.60 * feat), soft=2.8)
    ellipse(img, my + 9, 128, 5, mw * 0.55, hl, 0.16 + 0.12 * lip_full, soft=9)
    for sgn in (-1, 1):
        ellipse(img, my + 2, 128 + sgn * mw * 0.92, 5, 7, sh, 0.42, soft=5)

    # --- 皺 ---
    for k in range(3):
        y = 52 + k * 14
        stroke(img, (y, 128 - 60), (y + 2, 128 + 60), 2.4, sh, 0.16 * age, soft=4.5)
    for sgn in (-1, 1):
        stroke(img, (152, 128 + sgn * 33), (190, 128 + sgn * 48), 5.0, sh,
               min(1.0, (0.26 * age + 0.10) * feat), soft=7)                                # 法令線
        for k in range(3):
            stroke(img, (104 + k * 8, 128 + sgn * 70), (98 + k * 10, 128 + sgn * 86),
                   1.8, sh, 0.22 * age, soft=2.6)                        # 目尻
        ellipse(img, 206, 128 + sgn * 40, 14, 10, sh, 0.16 * age, soft=10)

    if jowl > 0:                                        # 顎のたるみ(老けた男)
        for sgn in (-1, 1):
            ellipse(img, 208, 128 + sgn * 56, 26, 22, sh, jowl * 0.35, soft=20)
            stroke(img, (186, 128 + sgn * 62), (214, 128 + sgn * 52), 4.0, sh,
                   jowl * 0.30, soft=6)
        ellipse(img, 226, 128, 16, 44, sh, jowl * 0.30, soft=18)
    if nose_big > 0:                                    # 団子鼻
        ellipse(img, 154, 128, 17, 21, hl, nose_big * 0.22, soft=14)
        ellipse(img, 158, 128, 13, 17, (0.80, 0.42, 0.36), nose_big * 0.30, soft=12)
    if blush > 0:
        for sgn in (-1, 1):
            ellipse(img, 150, 128 + sgn * 58, 22, 26, (0.84, 0.52, 0.50),
                    blush * 0.26, soft=26)
    if sallow > 0:                                      # 血の気の薄い黄ばんだ肌
        img = mix(img, rgb(R, sallow_col or (0.66, 0.60, 0.42)), sallow * 0.16)

    # --- 赤ら顔・毛細血管 ---
    if ruddy > 0:
        for sgn in (-1, 1):
            ellipse(img, 148, 128 + sgn * 60, 28, 32, (0.78, 0.34, 0.28),
                    ruddy * 0.34, soft=28)
        ellipse(img, 152, 128, 19, 17, (0.80, 0.36, 0.30), ruddy * 0.40, soft=17)
        veins = np.clip((norm(fbm(R, 30, 3, seed + 11)) - 0.68) * 4.0, 0, 1)
        img = mix(img, rgb(R, (0.74, 0.30, 0.26)), veins * ruddy * 0.26)

    # --- 無精髭 ---
    if stubble > 0:
        m = np.zeros((R, R, 3))
        ellipse(m, 206, 128, 46, 74, (1, 1, 1), 1.0, soft=26)
        ellipse(m, 176, 128, 22, 44, (1, 1, 1), 1.0, soft=18)
        ellipse(m, 186, 128, 16, 26, (0, 0, 0), 1.0, soft=10)            # 口の部分は抜く
        msk = np.clip(m[..., 0], 0, 1)
        n = (white(R, seed + 9) > 0.42).astype(float)
        n = np.maximum(n, (white(R, seed + 19) > 0.62).astype(float))
        img = mix(img, rgb(R, (0.26, 0.24, 0.25)), msk * n * stubble * 0.62)
        img = mix(img, rgb(R, (0.34, 0.31, 0.30)), msk * stubble * 0.16)

    # --- 生え際の影(髪はモデル側にある) ---
    ellipse(img, 26, 128, 26, 104, sh, 0.35, soft=20)
    # 端はごく軽く落とすだけにする。強く落とすと頭の側面との境が目立ち、
    # 顔がシールを貼ったように見える。
    gx, gy = np.meshgrid(np.arange(R), np.arange(R), indexing="ij")
    d = np.clip(1.0 - ((gy - 128) / 150.0) ** 2, 0, 1)
    img = mul_gray(img, 0.93 + d * 0.08)
    img = mul_gray(img, stains(R, seed + 13, 3, 0.07, 30))
    return _degrade(img, seed, out=128, contrast=contrast)


def t_face_boss():
    """社長(60 代)。血の気が薄く疲れている。眉は薄い白髪混じり、顎がたるむ。"""
    # 蛍光灯の下 + 640x360 + VHS では白い楕円に潰れたので、
    # 肌をもう 1 段暗く黄ばませ、目の窪み・眉・口・鼻の陰影を息子と同程度まで上げた。
    return _photo_face((0.585, 0.470, 0.375), (0.17, 0.145, 0.125), 470,
                       age=1.00, ruddy=0.20, stubble=0.28, bags=0.95,
                       sallow=0.70, sallow_col=(0.50, 0.43, 0.26),
                       jowl=0.85, brow_w=1.00, eye=0.88,
                       lip_full=0.75, lips=(0.50, 0.32, 0.29),
                       shade=0.52, feat=1.45, contrast=1.22)


def t_face_son():
    """息子(60 代)。酒焼けで赤黒い、無精髭が濃い、団子鼻、瞼が腫れぼったい。"""
    return _photo_face((0.74, 0.52, 0.42), (0.18, 0.15, 0.13), 480,
                       age=0.85, ruddy=1.0, stubble=1.0, bags=1.0,
                       jowl=0.55, brow_w=1.35, eye=0.72, nose_big=0.9,
                       lip_full=0.85, lips=(0.68, 0.38, 0.34),
                       shade=0.56, feat=1.25, contrast=1.12)


def t_face_granddaughter():
    """孫娘(20 代)。肌は滑らか、眉は細い、泣き腫らして目のふちが赤い。"""
    # 若い肌は滑らかなままに、目・眉・唇だけ濃くして小さくても読めるようにする
    # 目が暗い窪みに潰れるので、白目・虹彩・まつ毛を強めに出す
    return _photo_face((0.775, 0.640, 0.570), (0.10, 0.075, 0.072), 490,
                       age=0.10, ruddy=0.0, stubble=0.0, bags=0.42,
                       female=True, brow_w=0.58, eye=1.26, lip_full=1.35,
                       blush=0.60, eye_red=0.55, lips=(0.70, 0.38, 0.38),
                       shade=0.64, feat=1.70, contrast=1.18)


# ---------------------------------------------------------------- 胴の柄

def _torso_base(color, seed):
    """128x128。u=0 が背中、u=0.5(列 64)が正面の中心。v=1(行 0)が肩。"""
    T = 128
    base = rgb(T, color)
    base = mul_gray(base, 0.90 + norm(fbm(T, 20, 3, seed)) * 0.20)
    base = mul_gray(base, 1.0 - periodic_lines(T, 48, 0, 0.40, 0.34) * 0.04)
    base = mul_gray(base, 1.0 - periodic_lines(T, 48, 1, 0.40, 0.34) * 0.04)
    return base


def t_torso_suit():
    """黒いスーツ。襟・白シャツ・ネクタイを正面中央に描く。"""
    T = 128
    img = _torso_base((0.105, 0.105, 0.120), 701)
    # 白シャツ(襟元の V)。u は胴を一周するので、正面中央(列 64)の近くだけに描く
    for r in range(0, 30):
        w = max(0, int(9 - r * 0.22))
        if w > 0:
            rect(img, r, 64 - w, r + 1, 64 + w, (0.74, 0.73, 0.70), 1.0)
    # 襟(左右の折り返し)
    for sgn in (-1, 1):
        for r in range(0, 34):
            c0 = 64 + sgn * (8 + int(r * 0.30))
            rect(img, r, min(c0, c0 + sgn * 7), r + 1, max(c0, c0 + sgn * 7),
                 (0.17, 0.17, 0.19), 1.0)
            rect(img, r, c0, r + 1, c0 + sgn * 2, (0.27, 0.27, 0.29), 0.8)
    # ネクタイ(結び目 + 剣先)
    rect(img, 4, 60, 16, 68, (0.20, 0.16, 0.22), 1.0)
    for r in range(16, 82):
        w = 3 + int((r - 16) * 0.045)
        rect(img, r, 64 - w, r + 1, 64 + w, (0.17, 0.13, 0.19), 1.0)
    for r in range(20, 80, 8):                                  # 斜めのストライプ
        for k in range(7):
            rect(img, r + k, 64 - 6 + k, r + k + 1, 64 - 4 + k, (0.31, 0.25, 0.33), 0.7)
    # 前立てのボタン
    for r in (88, 104):
        disc(img, r, 72, 2.2, (0.06, 0.06, 0.07), 1.0, 1.2)
    return finish(mul_gray(img, grunge(T, 702, 0.12)), 703, noise=0.02)


def t_torso_jumper():
    """くたびれたジャンパー。正面中央にファスナー、胸ポケット。"""
    T = 128
    img = _torso_base((0.19, 0.22, 0.28), 711)
    worn = np.clip((norm(fbm(T, 5, 4, 712)) - 0.55) * 3.0, 0, 1)
    img = mix(img, rgb(T, (0.34, 0.35, 0.38)), worn * 0.40)
    # 襟(立ち襟。正面まわりだけ)
    rect(img, 0, 46, 14, 82, (0.14, 0.17, 0.22), 1.0)
    rect(img, 13, 46, 15, 82, (0.30, 0.32, 0.36), 0.7)
    # ファスナー(務歯を交互に)
    rect(img, 8, 61, 128, 67, (0.13, 0.15, 0.19), 1.0)
    for r in range(10, 128, 3):
        rect(img, r, 61, r + 2, 64, (0.58, 0.58, 0.60), 0.9)
        rect(img, r + 1, 64, r + 3, 67, (0.46, 0.46, 0.48), 0.9)
    rect(img, 8, 59, 128, 61, (0.10, 0.12, 0.15), 0.8)
    rect(img, 8, 67, 128, 69, (0.10, 0.12, 0.15), 0.8)
    # スライダー
    rect(img, 30, 58, 40, 70, (0.62, 0.62, 0.64), 1.0)
    rect(img, 39, 62, 47, 66, (0.55, 0.55, 0.57), 1.0)
    # 胸ポケット
    rect(img, 34, 76, 54, 94, (0.16, 0.19, 0.25), 1.0)
    rect(img, 34, 76, 37, 94, (0.30, 0.32, 0.36), 0.8)
    # 裾のリブ
    for r in range(118, 128):
        rect(img, r, 0, r + 1, 128, (0.15, 0.18, 0.23), 0.5)
    img = mul_gray(img, 1.0 - periodic_lines(T, 32, 1, 0.30, 0.2) * 0.06)
    return finish(mul_gray(img, grunge(T, 713, 0.20) * stains(T, 714, 4, 0.18, 26)), 715)


def t_torso_dress():
    """黒いワンピース。正面中央に小さな白襟。"""
    T = 128
    img = _torso_base((0.085, 0.085, 0.100), 721)
    # 白い丸襟。首の穴のまわりを一周する細い輪にする(塗りつぶすと球に見える)
    disc(img, 1, 64, 18, (0.50, 0.50, 0.48), 0.55, 2.5)          # 襟の外縁
    disc(img, 1, 64, 16, (0.80, 0.79, 0.77), 1.0, 1.8)           # 襟
    disc(img, 1, 64, 10, (0.085, 0.085, 0.100), 1.0, 1.8)        # 首の穴
    for r in range(0, 20):                                       # 前の開き(V)
        w = max(0, int(4 - r * 0.18))
        if w > 0:
            rect(img, r, 64 - w, r + 1, 64 + w, (0.085, 0.085, 0.100), 1.0)
    # 前身頃の切り替えとダーツ
    rect(img, 22, 63, 128, 65, (0.05, 0.05, 0.06), 0.55)
    for sgn in (-1, 1):
        for r in range(30, 90):
            c = 64 + sgn * (16 + int((r - 30) * 0.10))
            rect(img, r, c, r + 1, c + 1, (0.05, 0.05, 0.06), 0.35)
    rect(img, 0, 26, 128, 28, (0.05, 0.05, 0.06), 0.5)
    rect(img, 0, 100, 128, 102, (0.05, 0.05, 0.06), 0.5)
    # 布の落ち感
    img = mul_gray(img, 1.0 - 0.10 * (1.0 - _folds(3.0, 0.40, 722, 5, axis=1, size=T)))
    return finish(mul_gray(img, grunge(T, 723, 0.10)), 724, noise=0.022)


# ---------------------------------------------------------------- 髪と靴

def _hair(base, seed, grey=0.0, scalp=0.0, scalp_col=(0.62, 0.50, 0.44)):
    T = 128
    img = rgb(T, base)
    strand = hstreak(white(T, seed), 3, axis=1)
    img = mul_gray(img, 0.62 + norm(strand) * 0.80)
    img = mix(img, rgb(T, tuple(min(1.0, c * 1.9 + 0.05) for c in base)),
              norm(fbm(T, 10, 3, seed + 1)) * 0.28)
    if grey > 0:
        g = (hstreak(white(T, seed + 2), 2, axis=1) > 0.60).astype(float)
        img = mix(img, rgb(T, (0.72, 0.71, 0.70)), g * grey * 0.55)
    if scalp > 0:
        sc = np.clip((norm(fbm(T, 4, 3, seed + 3)) - 0.45) * 2.4, 0, 1)
        img = mix(img, rgb(T, scalp_col), sc * scalp)
    return finish(img, seed + 7, noise=0.04)


def t_hair_thin():
    """社長。薄くなって地肌が透ける。地肌は肌色、毛は白髪混じりの黒。"""
    return _hair((0.115, 0.105, 0.100), 731, grey=0.34, scalp=0.30,
                 scalp_col=(0.52, 0.42, 0.36))


def t_hair_salt():
    """息子。白髪混じりの短髪。"""
    return _hair((0.16, 0.15, 0.14), 741, grey=0.62, scalp=0.12)


def t_hair_long():
    """孫娘。黒い長髪。縦に流れる筋を出す。"""
    T = 128
    img = rgb(T, (0.125, 0.118, 0.132))
    strand = hstreak(white(T, 751), 10, axis=1)
    img = mul_gray(img, 0.45 + norm(strand) * 1.35)
    img = mul_gray(img, 1.0 - 0.22 * (1.0 - _folds(7.0, 0.30, 752, 6, axis=0, size=T)))
    img = mix(img, rgb(T, (0.32, 0.30, 0.35)), norm(fbm(T, 8, 3, 753)) * 0.30)
    return finish(img, 754, noise=0.035)


def t_ihai():
    """位牌の札。黒塗りに金の文字風。128x128、札の前面に 1 枚貼る。"""
    T = 128
    img = rgb(T, (0.045, 0.040, 0.042))
    img = mul_gray(img, 0.80 + norm(fbm(T, 30, 3, 771)) * 0.40)     # 漆の艶むら
    rect(img, 4, 18, 124, 110, (0.075, 0.066, 0.068), 1.0)
    # 金の縁
    for (a, b2, c, d) in ((4, 18, 7, 110), (121, 18, 124, 110),
                          (4, 18, 124, 21), (4, 107, 124, 110)):
        rect(img, a, b2, c, d, (0.62, 0.50, 0.18), 0.85)
    # 金の文字(縦書きの戒名らしい並び)
    r = 16
    rng = np.random.default_rng(772)
    while r < 116:
        h = int(rng.integers(10, 17))
        cw = int(rng.integers(16, 26))
        c0 = 64 - cw // 2
        # 1 文字を数本の横棒と縦棒で表す
        for k in range(int(rng.integers(2, 4))):
            y = r + 2 + k * (h // 3)
            rect(img, y, c0, y + 2, c0 + cw, (0.78, 0.64, 0.26), 0.9)
        vx = c0 + cw // 2
        rect(img, r + 1, vx - 1, r + h - 1, vx + 2, (0.78, 0.64, 0.26), 0.9)
        if rng.random() > 0.5:
            rect(img, r + 2, c0 + 2, r + h - 2, c0 + 4, (0.72, 0.58, 0.22), 0.8)
            rect(img, r + 2, c0 + cw - 4, r + h - 2, c0 + cw - 2, (0.72, 0.58, 0.22), 0.8)
        r += h + int(rng.integers(4, 8))
    img = blur(img, 1)
    return finish(mul_gray(img, grunge(T, 773, 0.10)), 774, noise=0.02, levels=26)


def t_lantern_paper():
    """回転灯籠の外筒。温かい白紙に淡い菊の模様と縦の骨。
    横方向にタイルする(筒を一周)。"""
    T = 256
    img = rgb(T, (0.90, 0.85, 0.72))
    img = mul_gray(img, 0.94 + norm(fbm(T, 40, 3, 781)) * 0.12)
    img = mix(img, rgb(T, (0.80, 0.72, 0.56)), norm(fbm(T, 5, 3, 782)) * 0.22)
    # 縦の骨(u 方向に等間隔)
    ribs = periodic_lines(T, 12, 1, 0.045, 0.012)
    img = mix(img, rgb(T, (0.42, 0.34, 0.24)), ribs * 0.55)
    # 上下の帯
    rect(img, 0, 0, 10, T, (0.52, 0.40, 0.26), 0.8)
    rect(img, T - 10, 0, T, T, (0.52, 0.40, 0.26), 0.8)
    # 淡い菊の輪
    rng = np.random.default_rng(783)
    for _ in range(9):
        cx = float(rng.integers(30, T - 30))
        cy = float(rng.integers(0, T))
        rr = 16 + rng.random() * 12
        for k in range(10):
            a = 2 * math.pi * k / 10
            disc(img, cx + math.cos(a) * rr * 0.62, cy + math.sin(a) * rr * 0.62,
                 rr * 0.30, (0.72, 0.60, 0.40), 0.28, rr * 0.35)
        disc(img, cx, cy, rr * 0.22, (0.70, 0.56, 0.32), 0.30, 3.0)
    return finish(mul_gray(img, stains(T, 784, 3, 0.10, 30)), 785)


def t_lantern_inner():
    """回転灯籠の内筒。透かしの影絵(蓮と波)。横方向にタイルする。"""
    T = 256
    img = rgb(T, (0.10, 0.09, 0.09))
    img = mul_gray(img, 0.85 + norm(fbm(T, 30, 2, 791)) * 0.30)
    # 波(下半分)
    for k in range(3):
        base_r = 150 + k * 32
        for c in range(T):
            h = base_r + int(math.sin(c / T * 2 * math.pi * 4 + k) * 12)
            rect(img, h, c, h + 9, c + 1, (0.42, 0.36, 0.28), 0.75)
    # 蓮の花の影(上半分)
    for cx in (60, 190):
        for k in range(7):
            a = -math.pi * 0.15 - math.pi * 0.70 * k / 6.0
            disc(img, 86 + math.sin(a) * 26, cx + math.cos(a) * 30, 12,
                 (0.40, 0.34, 0.26), 0.7, 5.0)
        disc(img, 86, cx, 13, (0.46, 0.38, 0.28), 0.7, 4.0)
    return finish(img, 792, noise=0.03, levels=22)


def t_hair_strand():
    """毛束の帯。縦の筋 + アルファ抜き。u が帯の幅、v が長さ(v=0 が毛先)。"""
    T = 128
    base = rgb(T, (0.105, 0.098, 0.112))
    strand = hstreak(white(T, 831), 12, axis=1)
    base = mul_gray(base, 0.45 + norm(strand) * 1.30)
    base = mix(base, rgb(T, (0.30, 0.28, 0.33)),
               norm(fbm(T, 7, 3, 832)) * 0.30)
    # 縦の筋(u 方向に細い束)
    v = (np.arange(T) + 0.5) / T
    fine = 0.5 + 0.5 * np.cos(2 * math.pi * v * 9.0)
    a = np.ones((T, 1)) * (0.45 + 0.55 * fine)[None, :]
    # 束のふちを透かす
    edge = np.clip((1.0 - np.abs(v - 0.5) * 2.0) * 3.2, 0, 1)
    a = a * (np.ones((T, 1)) * edge[None, :])
    # 毛先(行が大きいほど下)を細らせる
    u = (np.arange(T) + 0.5) / T
    taper = np.clip((1.0 - u) * 2.6, 0, 1)[:, None] * np.ones((1, T))
    a = np.clip(a * (0.35 + 0.65 * taper), 0, 1)
    a = a * (0.80 + white(T, 833) * 0.25)
    return rgba(posterize(base, 26), np.clip(a, 0, 1))


def _fabric(color, seed, weave=0.05, folds=0.10):
    """無地の布。指定色に織り目と縦皺だけ乗せる。"""
    T = 128
    img = rgb(T, color)
    img = mul_gray(img, 0.93 + norm(fbm(T, 26, 3, seed)) * 0.14)
    img = mul_gray(img, 1.0 - periodic_lines(T, 52, 0, 0.42, 0.34) * weave)
    img = mul_gray(img, 1.0 - periodic_lines(T, 52, 1, 0.42, 0.34) * weave * 0.85)
    img = mul_gray(img, 1.0 - folds * (1.0 - _folds(4.0, 0.42, seed + 3, 5,
                                                    axis=0, size=T)))
    return finish(mul_gray(img, grunge(T, seed + 7, 0.10)), seed + 9, noise=0.022)


def t_cloth_navy():      return _fabric((0.080, 0.080, 0.120), 841)
def t_cloth_navy_lt():   return _fabric((0.110, 0.110, 0.130), 851)
def t_cloth_olive():     return _fabric((0.210, 0.205, 0.145), 861, folds=0.14)
def t_cloth_gray():      return _fabric((0.135, 0.135, 0.140), 871)
def t_cloth_black():     return _fabric((0.070, 0.070, 0.082), 881, folds=0.13)
def t_cloth_tights():    return _fabric((0.095, 0.095, 0.105), 891, weave=0.03)


def t_shoe_sneaker():
    T = 128
    img = rgb(T, (0.72, 0.71, 0.68))
    img = mul_gray(img, 0.88 + norm(fbm(T, 30, 3, 901)) * 0.22)
    img = mix(img, rgb(T, (0.52, 0.51, 0.48)), norm(fbm(T, 6, 3, 902)) * 0.26)
    rect(img, 96, 0, 128, T, (0.86, 0.85, 0.82), 0.9)          # ソール
    rect(img, 92, 0, 98, T, (0.30, 0.30, 0.32), 0.7)
    return finish(mul_gray(img, grunge(T, 903, 0.24)), 904)


def t_shoe_loafer():
    T = 128
    img = rgb(T, (0.065, 0.062, 0.068))
    img = mul_gray(img, 0.80 + norm(fbm(T, 34, 3, 911)) * 0.45)
    img = mix(img, rgb(T, (0.20, 0.19, 0.20)), norm(fbm(T, 14, 2, 912)) * 0.18)
    return finish(img, 913, noise=0.02)


def t_shoe_leather():
    T = 128
    img = rgb(T, (0.085, 0.082, 0.085))
    img = mul_gray(img, 0.80 + norm(fbm(T, 30, 3, 761)) * 0.42)
    crease = norm(hstreak(fbm(T, 7, 3, 762), 12, axis=1))
    img = mul_gray(img, 1.0 - np.clip(1.0 - np.abs(crease - 0.5) * 9.0, 0, 1) * 0.30)
    img = mix(img, rgb(T, (0.26, 0.25, 0.24)), norm(fbm(T, 16, 2, 763)) * 0.16)
    return finish(mul_gray(img, scratches(T, 764, 24, 0.12, 26)), 765, noise=0.025)


# ---------------------------------------------------------------- 文字もの

def t_vending_panel():
    """自販機の前面(発光用)。"""
    img = rgb(S, (0.86, 0.14, 0.12))
    img = mul_gray(img, 0.9 + norm(fbm(S, 40, 2, 501)) * 0.2)
    rect(img, 0, 0, 30, S, (0.92, 0.88, 0.20), 1.0)
    rect(img, 30, 0, 34, S, (0.20, 0.18, 0.18), 1.0)
    # 商品サンプルの列
    r = np.random.default_rng(502)
    cols = [(0.20, 0.42, 0.75), (0.85, 0.80, 0.25), (0.25, 0.55, 0.30),
            (0.80, 0.30, 0.25), (0.90, 0.88, 0.84), (0.35, 0.28, 0.20)]
    for row in range(3):
        for col in range(5):
            x0 = 46 + row * 56
            y0 = 12 + col * 47
            c = cols[int(r.integers(0, len(cols)))]
            rect(img, x0, y0, x0 + 40, y0 + 34, (0.05, 0.05, 0.06), 1.0)
            rect(img, x0 + 3, y0 + 8, x0 + 37, y0 + 28, c, 1.0)
            rect(img, x0 + 3, y0 + 8, x0 + 10, y0 + 28, (1, 1, 1), 0.25)
            rect(img, x0 + 42, y0 + 8, x0 + 48, y0 + 26, (0.85, 0.20, 0.18), 1.0)
    rect(img, 218, 0, S, S, (0.14, 0.13, 0.13), 1.0)
    rect(img, 224, 18, 244, 120, (0.30, 0.30, 0.32), 1.0)       # 取り出し口
    disc(img, 232, 200, 12, (0.55, 0.55, 0.58), 1.0, 1.5)       # コイン投入
    return finish(img, 503, noise=0.03, levels=24)


def t_clock_face():
    img = rgb(S, (0.90, 0.88, 0.82))
    img = mul_gray(img, 0.95 + norm(fbm(S, 40, 2, 511)) * 0.10)
    disc(img, 128, 128, 120, (0.93, 0.91, 0.86), 1.0, 2)
    for i in range(12):
        a = i * math.pi / 6.0
        rr = 104
        x = 128 - math.cos(a) * rr
        y = 128 + math.sin(a) * rr
        s = 9 if i % 3 == 0 else 5
        disc(img, x, y, s, (0.12, 0.11, 0.11), 1.0, 1.2)
    # 針(10時10分)
    for (ang, ln, w) in ((math.radians(60), 62, 5), (math.radians(-60), 88, 4)):
        for i in range(ln):
            x = 128 - math.cos(ang) * i
            y = 128 + math.sin(ang) * i
            disc(img, x, y, w * 0.5, (0.10, 0.10, 0.10), 1.0, 1.0)
    disc(img, 128, 128, 7, (0.10, 0.10, 0.10), 1.0, 1.2)
    img = mul_gray(img, stains(S, 512, 4, 0.18, 30))
    return finish(img, 513, levels=28)


def t_notice_paper():
    """掲示板に貼られた紙の束。"""
    img = rgb(S, (0.30, 0.26, 0.21))
    img = mul_gray(img, 0.9 + norm(fbm(S, 30, 3, 521)) * 0.2)
    r = np.random.default_rng(522)
    for _ in range(7):
        x0 = int(r.integers(6, 150))
        y0 = int(r.integers(6, 150))
        w = int(r.integers(58, 96))
        h = int(r.integers(70, 104))
        tone = 0.72 + r.random() * 0.18
        rect(img, x0, y0, x0 + w, y0 + h, (tone, tone * 0.97, tone * 0.88), 1.0)
        for k in range(4, h - 6, 9):
            ln = int(r.integers(int(w * 0.3), int(w * 0.85)))
            rect(img, x0 + k, y0 + 5, x0 + k + 3, y0 + 5 + ln, (0.30, 0.28, 0.26), 0.8)
        disc(img, x0 + 6, y0 + w // 2, 4, (0.75, 0.15, 0.12), 1.0, 1.0)
    return finish(mul_gray(img, grunge(S, 523, 0.18)), 524)


def t_label_sake():
    img = rgb(S, (0.10, 0.14, 0.11))
    img = mul_gray(img, 0.85 + norm(fbm(S, 40, 2, 531)) * 0.3)
    rect(img, 70, 80, 200, 176, (0.90, 0.87, 0.76), 1.0)
    rect(img, 76, 86, 194, 170, (0.88, 0.84, 0.70), 1.0)
    for k in range(92, 186, 22):
        rect(img, 90, k, 178, k + 11, (0.22, 0.14, 0.10), 0.85)
        rect(img, 96, k + 2, 172, k + 9, (0.88, 0.84, 0.70), 0.35)
    rect(img, 66, 78, 72, 178, (0.62, 0.12, 0.10), 1.0)
    return finish(img, 532, levels=24)


def t_label_beer():
    img = rgb(S, (0.72, 0.72, 0.74))
    n = white(S, 541)
    img = mul_gray(img, 0.88 + hstreak(norm(n), 10, 1) * 0.26)
    rect(img, 80, 0, 176, S, (0.80, 0.16, 0.14), 1.0)
    rect(img, 80, 0, 88, S, (0.92, 0.82, 0.30), 1.0)
    rect(img, 168, 0, 176, S, (0.92, 0.82, 0.30), 1.0)
    for k in range(10, S, 64):
        rect(img, 104, k, 152, k + 40, (0.95, 0.92, 0.84), 0.9)
        rect(img, 112, k + 6, 144, k + 34, (0.80, 0.16, 0.14), 0.9)
    rect(img, 0, 0, 22, S, (0.55, 0.55, 0.58), 1.0)
    rect(img, 236, 0, S, S, (0.55, 0.55, 0.58), 1.0)
    return finish(img, 542, levels=24)


def t_matchbox():
    img = rgb(S, (0.72, 0.64, 0.48))
    img = mul_gray(img, 0.92 + norm(fbm(S, 40, 2, 551)) * 0.16)
    rect(img, 40, 30, 216, 226, (0.58, 0.16, 0.12), 1.0)
    rect(img, 52, 42, 204, 214, (0.80, 0.74, 0.60), 1.0)
    for k in range(70, 190, 26):
        rect(img, 80, k, 170, k + 12, (0.30, 0.20, 0.14), 0.85)
    rect(img, 176, 42, 204, 214, (0.30, 0.22, 0.16), 1.0)   # 側薬
    img = mul_gray(img, grunge(S, 552, 0.2))
    return finish(img, 553, levels=24)


def t_incense_box():
    img = rgb(S, (0.45, 0.30, 0.22))
    img = mul_gray(img, 0.9 + norm(fbm(S, 40, 2, 561)) * 0.2)
    rect(img, 24, 24, 232, 232, (0.72, 0.63, 0.48), 1.0)
    rect(img, 34, 34, 222, 222, (0.60, 0.20, 0.16), 1.0)
    rect(img, 48, 48, 208, 208, (0.84, 0.78, 0.62), 1.0)
    for k in range(70, 190, 30):
        rect(img, 76, k, 180, k + 14, (0.26, 0.18, 0.14), 0.9)
        rect(img, 84, k + 3, 172, k + 11, (0.84, 0.78, 0.62), 0.3)
    return finish(mul_gray(img, grunge(S, 562, 0.16)), 563, levels=24)


def t_guest_book():
    img = rgb(S, (0.88, 0.85, 0.76))
    img = mul_gray(img, 0.94 + norm(fbm(S, 48, 2, 571)) * 0.12)
    rect(img, 0, 118, S, 138, (0.60, 0.56, 0.46), 0.8)      # 綴じ目
    for k in range(20, 240, 18):
        rect(img, k, 14, k + 2, 112, (0.55, 0.52, 0.45), 0.6)
        rect(img, k, 144, k + 2, 242, (0.55, 0.52, 0.45), 0.6)
    r = np.random.default_rng(572)
    for k in range(24, 160, 18):
        ln = int(r.integers(30, 80))
        rect(img, k + 3, 20, k + 9, 20 + ln, (0.18, 0.16, 0.20), 0.85)
    return finish(mul_gray(img, stains(S, 573, 3, 0.14, 26)), 574)


# ---------------------------------------------------------------- デカール

def _mask(size):
    return np.zeros((size, size, 3))


def t_paw_print():
    """濡れた猫の足跡(64x64, アルファ付き)。上(row 0)が進行方向。
    廊下 → 式場 に並べて置く用。"""
    S2 = 64
    m = _mask(S2)
    # 指球 4 つ(外側ほど下がる弧)
    for (r, c, rx, ry) in ((21.0, 13.0, 6.2, 5.4), (15.5, 25.0, 6.4, 5.6),
                           (15.5, 39.0, 6.4, 5.6), (21.0, 51.0, 6.2, 5.4)):
        ellipse(m, r, c, rx, ry, (1, 1, 1), 1.0, soft=2.4)
    # 掌球(下がふくらんだ三角)
    ellipse(m, 44.0, 32.0, 12.5, 15.5, (1, 1, 1), 1.0, soft=2.6)
    ellipse(m, 35.0, 32.0, 7.0, 10.0, (1, 1, 1), 1.0, soft=3.2)
    mask = np.clip(m[..., 0], 0, 1)

    n = norm(fbm(S2, cells=10, octaves=3, seed=601))
    n2 = norm(fbm(S2, cells=26, octaves=2, seed=602))
    # 水の膜: 中は薄く、縁に溜まって濃い
    rim = np.clip((mask - 0.30) * 3.0, 0, 1) * np.clip((0.92 - mask) * 3.0, 0, 1)
    col = rgb(S2, (0.085, 0.095, 0.115))
    col = mix(col, rgb(S2, (0.17, 0.19, 0.21)), n * 0.45)     # 濡れたムラ
    col = mix(col, rgb(S2, (0.05, 0.055, 0.07)), rim * 0.65)  # 縁の水溜まり
    a = mask * (0.52 + n * 0.30 + n2 * 0.10) + rim * 0.22
    # 端は完全に透明にしてタイルの継ぎ目を出さない
    edge = np.ones((S2, S2))
    edge[:2] = 0; edge[-2:] = 0; edge[:, :2] = 0; edge[:, -2:] = 0
    a = np.clip(a * edge, 0, 1)
    return rgba(posterize(col, 24), a)


def t_handprint():
    """棺の小窓の内側に付いた手形(128x128, アルファ付き)。
    皮脂で曇ったような白っぽい跡。指先が上(row 0)。"""
    S2 = 128
    m = _mask(S2)
    # 掌
    ellipse(m, 84.0, 62.0, 25.0, 23.0, (1, 1, 1), 1.0, soft=5.0)
    ellipse(m, 96.0, 62.0, 16.0, 20.0, (1, 1, 1), 1.0, soft=6.0)
    # 指 4 本(付け根 → 指先。少し開く)
    fingers = (((62.0, 40.0), (26.0, 31.0), 7.0),
               ((59.0, 55.0), (18.0, 50.0), 7.4),
               ((59.0, 70.0), (19.0, 69.0), 7.2),
               ((63.0, 84.0), (28.0, 88.0), 6.6))
    for (p0, p1, rad) in fingers:
        stroke(m, p0, p1, rad, (1, 1, 1), 1.0, soft=3.0)
        disc(m, p1[0], p1[1], rad * 0.95, (1, 1, 1), 1.0, 2.2)
    # 親指(斜めに出る)
    stroke(m, (88.0, 40.0), (74.0, 16.0), 8.2, (1, 1, 1), 1.0, soft=3.2)
    disc(m, 74.0, 16.0, 8.0, (1, 1, 1), 1.0, 2.4)
    mask = np.clip(m[..., 0], 0, 1)

    n = norm(fbm(S2, cells=14, octaves=4, seed=611))
    n2 = norm(fbm(S2, cells=40, octaves=2, seed=612))
    # 皮脂の曇り: 接地が強いところほど白い
    col = rgb(S2, (0.90, 0.90, 0.88))
    col = mix(col, rgb(S2, (0.74, 0.75, 0.76)), n * 0.45)
    # 掌の中央は浮いていて薄い(ドーナツ状に残る)
    hollow = np.clip(1.0 - np.sqrt(((np.arange(S2)[:, None] - 90) / 17.0) ** 2
                                   + ((np.arange(S2)[None, :] - 62) / 15.0) ** 2), 0, 1)
    a = mask * (0.42 + n * 0.24 + n2 * 0.12)
    a = a * (1.0 - hollow * 0.30)
    # 指紋らしい細い筋
    ridge = 0.5 + 0.5 * np.sin(norm(fbm(S2, cells=8, octaves=3, seed=613)) * 44.0)
    a = a * (0.80 + ridge * 0.30)
    edge = np.ones((S2, S2))
    edge[:2] = 0; edge[-2:] = 0; edge[:, :2] = 0; edge[:, -2:] = 0
    a = np.clip(a * edge, 0, 1)
    return rgba(posterize(col, 26), a)


ALL = {
    # level が使う(シームレス)
    "floor_lino": t_floor_lino,
    "tatami": t_tatami,
    "wall_plaster": t_wall_plaster,
    "wall_wood": t_wall_wood,
    "ceiling_tile": t_ceiling_tile,
    "concrete": t_concrete,
    "asphalt": t_asphalt,
    "wood_dark": t_wood_dark,
    "white_cloth": t_white_cloth,
    "brocade": t_brocade,
    "steel": t_steel,
    "glass_frost": t_glass_frost,
    "shoji": t_shoji,
    # models が使う素材
    "white_wood": t_white_wood,
    "metal_gray": t_metal_gray,
    "metal_dark": t_metal_dark,
    "plastic_beige": t_plastic_beige,
    "crt_screen": t_crt_screen,
    "tv_static": t_tv_static,
    "zabuton_cloth": t_zabuton,
    "futon_cloth": t_futon_cloth,
    "fur_black": t_fur_black,
    "kasha_skin": t_kasha_skin,
    "suit_black": t_suit_black,
    "dress_black": t_dress_black,
    "jumper": t_jumper,
    "skin_pale": t_skin_pale,
    "skin_boss": t_skin_boss,
    "skin_son": t_skin_son,
    "skin_gd": t_skin_gd,
    "paper_yellow": t_paper_yellow,
    "cardboard": t_cardboard,
    "styrofoam": t_styrofoam,
    "gold": t_gold,
    "paint_red": t_paint_red,
    "ash": t_ash,
    "flower_white": t_flower_white,
    "leaves_dark": t_leaves_dark,
    "bark": t_bark,
    "car_black": t_car_black,
    "slipper": t_slipper,
    "tile_white": t_tile_white,
    "porcelain": t_porcelain,
    # 顔・写真・文字もの(タイルしない)
    "body_face_calm": t_body_face_calm,
    "body_face_mouth": t_body_face_mouth,
    "body_face_eyes": t_body_face_eyes,
    "body_face_turned": t_body_face_turned,
    "iei_photo": t_iei_photo,
    "iei_photo_player": t_iei_photo_player,
    "face_boss": t_face_boss,
    "torso_suit": t_torso_suit,
    "torso_jumper": t_torso_jumper,
    "torso_dress": t_torso_dress,
    "hair_thin": t_hair_thin,
    "hair_salt": t_hair_salt,
    "hair_long": t_hair_long,
    "hair_strand": t_hair_strand,
    "shoe_leather": t_shoe_leather,
    "shoe_sneaker": t_shoe_sneaker,
    "shoe_loafer": t_shoe_loafer,
    "cloth_navy": t_cloth_navy,
    "cloth_navy_lt": t_cloth_navy_lt,
    "cloth_olive": t_cloth_olive,
    "cloth_gray": t_cloth_gray,
    "cloth_black": t_cloth_black,
    "cloth_tights": t_cloth_tights,
    "ihai": t_ihai,
    "lantern_paper": t_lantern_paper,
    "lantern_inner": t_lantern_inner,
    "face_son": t_face_son,
    "face_granddaughter": t_face_granddaughter,
    "vending_panel": t_vending_panel,
    "clock_face": t_clock_face,
    "notice_paper": t_notice_paper,
    "label_sake": t_label_sake,
    "label_beer": t_label_beer,
    "matchbox": t_matchbox,
    "incense_box_tex": t_incense_box,
    "guest_book": t_guest_book,
    # デカール(アルファ付き。タイルしない)
    "paw_print": t_paw_print,
    "handprint": t_handprint,
}


def main():
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    print("generating textures ->", os.path.dirname(os.path.abspath(__file__)))
    for name, fn in ALL.items():
        if only and name not in only:
            continue
        save_tex(name, fn())
    print("done:", len(ALL), "textures")


if __name__ == "__main__":
    main()
