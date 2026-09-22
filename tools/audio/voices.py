# -*- coding: utf-8 -*-
"""寝ずの番 | The Wake — 音の設計本体.

CLAUDE.md「音名一覧」の名前で VOICES に登録する。
  VOICES[name] = (生成関数, ループするか, ピーク正規化 dBFS)
生成関数は引数なしで float64 の mono 配列を返す。
"""

import math

import numpy as np

import dsp
from dsp import (
    N, SR, TWO_PI, as_array, band, bandpass, bitcrush, brown, db2lin, dc_kill,
    delay_taps, env_ar, env_exp, env_gauss, env_hann, fade, filt, fftconv,
    glide, grain_env, harm, highpass, lfo, loop_noise, loop_smooth, lowpass,
    mix, norm_peak, pad_to, peaking, pink, phase, pulse_train, place,
    place_wrap, resonators, reverb, reverb_ir, ring_mod, rng, saw_amps,
    segments, sine, smooth_noise, snap, softclip, square_amps, stick_slip,
    svf_tv, tremolo, trim_tail, white, zeros,
)

VOICES = {}

# 単発 -3 dBFS / 環境ループ -12 dBFS / ドローン -15 dBFS
SINGLE_DB = -3.0
LOOP_DB = -12.0
DRONE_DB = -15.0


def reg(name, loop=False, target=SINGLE_DB):
    def deco(fn):
        VOICES[name] = (fn, loop, target)
        return fn
    return deco


# ==========================================================================
# 共通の部品
# ==========================================================================
# 部屋ごとの残響プリセット: (長さ, 減衰, ダンプ, プリディレイ, seed)
ROOM_LINO = dict(dur=0.85, decay=0.18, damp_hz=4200.0, predelay=0.007, seed=101)
ROOM_HALL = dict(dur=2.2, decay=0.62, damp_hz=3000.0, predelay=0.020, seed=102)  # 式場
ROOM_TATAMI = dict(dur=0.5, decay=0.085, damp_hz=1800.0, predelay=0.005, seed=103)
ROOM_OUT = dict(dur=1.6, decay=0.30, damp_hz=2200.0, predelay=0.030, seed=104)
ROOM_TILE = dict(dur=1.3, decay=0.42, damp_hz=6000.0, predelay=0.009, seed=105)  # 湯灌室/トイレ
ROOM_TIGHT = dict(dur=0.35, decay=0.06, damp_hz=3000.0, predelay=0.004, seed=106)


def room(x, preset, wet=0.25, dry=1.0):
    return reverb(x, wet=wet, dry=dry, **preset)


def formant(x, specs, circular=False):
    """specs = [(中心周波数, Q, ゲイン dB), ...] の並列バンドパス。"""
    out = zeros(len(x))
    for f, q, g in specs:
        out += db2lin(g) * bandpass(x, f, q, 1, circular)
    return out


def partials(n, freqs, decays, amps, seed=0, detune=0.003, phase_rand=True):
    """減衰する正弦の和 (金属・ガラス・鐘の胴鳴り)。各成分はわずかにデチューンして唸らせる。"""
    r = rng(seed)
    out = zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        for s in (-1.0, 1.0):
            ff = f * (1.0 + s * detune * (0.4 + r.random()))
            p0 = r.random() * TWO_PI if phase_rand else 0.0
            out += 0.5 * a * sine(ff, n, p0) * env_exp(n, d)
    return out


def click(n, seed, bright=3000.0, q=3.0, dur=0.0012):
    """ごく短い打撃の芯。"""
    e = env_ar(n, 0.00008, dur, 6.0)
    return bandpass(white(n, seed) * e, bright, q, 1)


def wood_knock(n, seed, pitch=1.0, decay=1.0, bright=1.0, thump=1.0):
    """木を叩く音: 短い励振 + 木の胴鳴り。"""
    exc = white(n, seed) * env_ar(n, 0.00012, 0.0022, 7.0)
    lowf = [186.0, 302.0, 468.0]
    hif = [812.0, 1310.0, 2080.0]
    body = resonators(
        exc,
        [f * pitch for f in lowf],
        [34 * decay, 28 * decay, 24 * decay],
        [1.0, 0.55, 0.30],
    )
    top = resonators(
        exc,
        [f * pitch for f in hif],
        [16 * decay, 13 * decay, 10 * decay],
        [0.42 * bright, 0.26 * bright, 0.16 * bright],
    )
    thd = lowpass(white(n, seed + 1) * env_ar(n, 0.0004, 0.02, 5.0), 130.0, order=2) * 1.6 * thump
    return body + top + thd


def metal_hit(n, seed, base=520.0, spread=1.0, decay=0.55, count=7, bright=1.0):
    """金属の非調和クラスタ。"""
    r = rng(seed)
    ratios = [1.0, 1.41, 1.93, 2.37, 3.11, 3.79, 4.63, 5.41, 6.72][:count]
    freqs = [base * (1.0 + (r.random() - 0.5) * 0.06 * spread) * x for x in ratios]
    decays = [decay * (0.95 ** i) * (0.7 + 0.6 * r.random()) for i in range(len(freqs))]
    amps = [(1.0 / (1.0 + 0.8 * i)) * (0.6 + 0.8 * r.random()) * (bright ** (i * 0.25)) for i in range(len(freqs))]
    out = partials(n, freqs, decays, amps, seed=seed + 5, detune=0.005)
    out += 0.55 * bandpass(white(n, seed + 9) * env_ar(n, 0.0002, 0.004, 6.0), base * 2.2, 1.6, 1)
    return out


def scrape(n, seed, lo, hi, rate, rough=0.8, jitter=0.6, sharp=60.0, order=2):
    """擦る音 (stick-slip)。rate は配列可。"""
    src = band(white(n, seed), lo, hi, order=order)
    mod = stick_slip(n, rate, seed + 1, jitter=jitter, sharp=sharp)
    g = grain_env(n, max(8, int(n / SR * 90)), seed + 2, dur_sec=0.004)
    return src * ((1.0 - rough) + rough * (0.55 * mod + 0.45 * g))


def creak(n, f0, f1, seed, rate=48.0, ratios=(1.0, 2.04, 3.09, 4.71), q=42.0, curve=1.0, jitter=0.6, sharp=110.0):
    """軋み: 共鳴のピッチグライドを stick-slip で励振する。"""
    ra = as_array(rate, n)
    exc = stick_slip(n, ra, seed, jitter=jitter, sharp=sharp)
    exc = exc * (0.55 + 0.45 * white(n, seed + 1))
    f = glide(f0, f1, n, curve)
    out = zeros(n)
    for i, rt in enumerate(ratios):
        out += (1.0 / (1.0 + i * 0.9)) * svf_tv(exc, np.clip(f * rt, 30.0, 12000.0), q, "bp")
    return out / max(1e-9, np.max(np.abs(out)))


def voice_src(n, f0, seed=0, jitter=0.018, width=0.085, breath=0.10, rough=0.0):
    """声帯モデル: ジッタ付きパルス列 + 息。"""
    f = as_array(f0, n) * (1.0 + jitter * smooth_noise(n, 26.0, seed))
    src = pulse_train(f, n, width)
    if rough > 0.0:
        src = src * (1.0 - rough + rough * (0.5 + 0.5 * sine(as_array(f0, n) * 0.5, n)))
    src = src + breath * white(n, seed + 1) * 0.5
    return src


def breath_noise(n, seed, lo=260.0, hi=2600.0, shape=None):
    x = band(white(n, seed), lo, hi, order=2)
    x = x * (0.6 + 0.4 * smooth_noise(n, 18.0, seed + 1))
    if shape is None:
        shape = env_gauss(n, 0.45, 0.24)
    return x * shape


def water_drop(seed, f0=760.0, f1=2100.0, dur=0.05):
    n = N(dur)
    f = glide(f0, f1, n, 0.55)
    return sine(f, n) * env_ar(n, 0.0006, dur * 0.45, 5.0)


def tick_wood(seed, pitch=1.0, level=1.0):
    """柱時計の秒針。木の箱で響く。"""
    n = N(0.13)
    exc = white(n, seed) * env_ar(n, 0.00008, 0.0009, 9.0)
    hi = resonators(exc, [1240 * pitch, 2580 * pitch, 4250 * pitch], [15, 18, 12], [1.0, 0.55, 0.30])
    box = resonators(exc, [176 * pitch, 424 * pitch, 735 * pitch], [26, 22, 17], [1.0, 0.48, 0.22])
    t = 0.55 * hi + 0.95 * box
    t = room(t, ROOM_TATAMI, wet=0.22)
    return norm_peak(t, -0.5) * level


def soft_click(seed, bright=2600.0, q=3.0, body=1.0, dur=0.05):
    """UI / プラスチックの控えめなカチ音。"""
    n = N(dur)
    exc = white(n, seed) * env_ar(n, 0.00006, 0.0009, 8.0)
    x = bandpass(exc, bright, q, 1) + body * 0.5 * resonators(exc, [bright * 0.35, bright * 0.62], [9, 7], [1.0, 0.5])
    return fade(x, 0.0002, 0.006)


# ==========================================================================
# 環境ループ (すべて周期的に作るので継ぎ目は数学的に連続)
# ==========================================================================
@reg("amb_room", loop=True, target=LOOP_DB)
def amb_room():
    dur = 20.0
    n = N(dur)
    r = rng(1001)
    hum = zeros(n)
    for f, a in ((50.0, 1.0), (100.0, 0.52), (150.0, 0.20), (200.0, 0.09), (300.0, 0.035)):
        hum += a * sine(snap(f, dur), n, r.random() * TWO_PI)
    hum *= 1.0 + 0.20 * loop_smooth(n, 0.30, 1002) + 0.10 * lfo(n, snap(0.17, dur))
    rumble = lowpass(loop_noise(n, 2.0, 1003), 150.0, order=3, circular=True)
    rumble *= 0.55 + 0.45 * (0.5 + 0.5 * loop_smooth(n, 0.6, 1004))
    hvac = lowpass(loop_noise(n, 1.0, 1005), 800.0, order=2, circular=True)
    hvac = highpass(hvac, 65.0, order=1, circular=True)
    hvac *= 0.78 + 0.22 * (0.5 + 0.5 * loop_smooth(n, 0.4, 1006))
    hvac = peaking(hvac, 180.0, 1.3, 4.0, circular=True)
    air = highpass(loop_noise(n, 0.6, 1007), 2600.0, order=2, circular=True) * 0.05
    out = 0.46 * hum + 0.85 * rumble + 1.35 * hvac + air
    # 冷蔵庫のリレーが一度だけカチと鳴る
    rel = norm_peak(soft_click(1008, 1900.0, 4.0, 0.7), -14.0)
    place_wrap(out, rel, 13.4, 0.5)
    return dc_kill(out, circular=True)


@reg("amb_outside", loop=True, target=LOOP_DB)
def amb_outside():
    dur = 20.0
    n = N(dur)
    gust = 0.30 + 0.70 * (0.5 + 0.5 * loop_smooth(n, 0.22, 1101, slope=1.4))
    gust *= 0.75 + 0.25 * (0.5 + 0.5 * lfo(n, snap(0.05, dur)))
    wind = lowpass(loop_noise(n, 2.0, 1102), 700.0, order=2, circular=True) * gust
    whistle = bandpass(loop_noise(n, 1.0, 1103), 820.0, 1.1, 1, circular=True) * (gust ** 2.2) * 0.30
    hiss = highpass(loop_noise(n, 1.0, 1104), 1800.0, order=2, circular=True) * (gust ** 3) * 0.07
    road = lowpass(loop_noise(n, 1.0, 1105), 300.0, order=3, circular=True) * 0.55
    road *= 0.8 + 0.2 * (0.5 + 0.5 * loop_smooth(n, 0.5, 1106))
    out = 1.0 * wind + whistle + hiss + road
    # 車が2台通る (近づいて遠ざかる膨らみ + ゆるいドップラ)
    for at, g, sd, f_hi, f_lo in ((4.3, 0.38, 1107, 300.0, 155.0), (12.9, 0.24, 1108, 260.0, 140.0)):
        nc = N(4.4)
        src = lowpass(white(nc, sd), 1600.0, order=2)
        src = svf_tv(src, glide(f_hi, f_lo, nc, 0.75), 1.05, "lp")
        car = src * env_gauss(nc, 0.5, 0.16)
        place_wrap(out, norm_peak(car, -1.0), at, g)
    # ごく稀に遠い犬
    for at, g, sd, f in ((16.6, 0.16, 1109, 300.0), (17.02, 0.12, 1110, 268.0)):
        nb = N(0.26)
        v = voice_src(nb, glide(f, f * 0.78, nb, 0.5), sd, jitter=0.05, width=0.13, breath=0.25)
        v = formant(v, [(480.0, 4.0, 0.0), (1250.0, 5.0, -5.0), (2400.0, 6.0, -13.0)])
        v *= env_ar(nb, 0.008, 0.10, 4.0)
        v = lowpass(v, 1100.0, order=2)
        v = room(v, ROOM_OUT, wet=0.55)
        place_wrap(out, norm_peak(v, -1.0), at, g)
    return dc_kill(out, circular=True)


@reg("amb_shikijo", loop=True, target=LOOP_DB)
def amb_shikijo():
    dur = 20.0
    n = N(dur)
    r = rng(1201)
    tone = lowpass(loop_noise(n, 1.2, 1202), 520.0, order=3, circular=True) * 0.55
    tone += 0.16 * sine(snap(58.0, dur), n, r.random() * TWO_PI)
    tone += 0.07 * sine(snap(116.0, dur), n, r.random() * TWO_PI)
    tone += highpass(loop_noise(n, 0.8, 1203), 3000.0, order=2, circular=True) * 0.03
    tone *= 0.85 + 0.15 * (0.5 + 0.5 * loop_smooth(n, 0.25, 1204))
    out = tone * db2lin(-6.0)
    # 線香が燃える「チリ…」: ごく小さい微小クリックを散らす
    for i in range(34):
        nc = N(0.006 + 0.004 * r.random())
        c = bandpass(white(nc, 1210 + i) * env_ar(nc, 0.0002, 0.0018, 6.0), 3200.0 + 3000.0 * r.random(), 3.0, 1)
        c = room(c, ROOM_HALL, wet=0.30)
        place_wrap(out, norm_peak(c, -20.0 - 7.0 * r.random()), r.random() * dur)
    # 時々の木の軋み
    for at, f0, f1, sd, g in ((7.1, 96.0, 132.0, 1230, 0.45), (15.4, 128.0, 104.0, 1231, 0.33)):
        nk = N(0.9)
        k = creak(nk, f0, f1, sd, rate=segments([(0, 22), (0.4, 14), (1, 9)], nk), q=30.0, sharp=70.0)
        k *= env_ar(nk, 0.06, 0.45, 3.0)
        k = lowpass(k, 1400.0, order=2)
        k = room(k, ROOM_HALL, wet=0.35)
        place_wrap(out, norm_peak(k, -6.0), at, g)
    return dc_kill(out, circular=True)


@reg("amb_tatami", loop=True, target=LOOP_DB)
def amb_tatami():
    dur = 10.0
    n = N(dur)
    tone = lowpass(loop_noise(n, 1.3, 1301), 600.0, order=3, circular=True) * 0.5
    tone += 0.10 * sine(snap(62.0, dur), n)
    tone += highpass(loop_noise(n, 0.8, 1302), 2800.0, order=2, circular=True) * 0.035
    out = tone * db2lin(-7.0)
    # 掛け時計の秒針: 1 秒周期。カチ/コチを交互に
    for i in range(10):
        t = 0.5 + i
        if i % 2 == 0:
            place_wrap(out, tick_wood(1310 + i, 1.0, 1.0), t, 0.80)
        else:
            place_wrap(out, tick_wood(1320 + i, 0.94, 0.82), t, 0.80)
    return dc_kill(out, circular=True)


def _machine_hum(n, dur, f0, seed, harm_amps, drive, bp_f, bp_q, beat_hz=0.0):
    r = rng(seed)
    f = snap(f0, dur)
    h = harm(f, n, harm_amps, r.random() * TWO_PI)
    if beat_hz:
        h = h + 0.7 * harm(snap(f0 + beat_hz, dur), n, harm_amps, r.random() * TWO_PI)
    h = softclip(h, drive)
    return bandpass(h, bp_f, bp_q, 1, circular=True) + 0.45 * lowpass(h, 400.0, order=2, circular=True)


@reg("amb_freezer", loop=True, target=LOOP_DB)
def amb_freezer():
    dur = 12.0
    n = N(dur)
    hum = _machine_hum(n, dur, 100.0, 1401, [1.0, 0.55, 0.70, 0.22, 0.34, 0.12, 0.18, 0.07], 2.2, 230.0, 0.9, beat_hz=0.583)
    rattle = bandpass(loop_noise(n, 1.0, 1402), 430.0, 2.6, 1, circular=True)
    rattle *= 0.25 + 0.75 * (0.5 + 0.5 * loop_smooth(n, 3.5, 1403))
    hiss = highpass(loop_noise(n, 0.5, 1404), 2800.0, order=2, circular=True) * 0.22
    body = lowpass(loop_noise(n, 2.0, 1405), 120.0, order=3, circular=True) * 0.7
    out = 0.9 * hum + 0.35 * rattle + hiss + body
    return dc_kill(out, circular=True)


@reg("amb_vending", loop=True, target=LOOP_DB)
def amb_vending():
    dur = 12.0
    n = N(dur)
    hum = _machine_hum(n, dur, 100.0, 1501, [1.0, 0.38, 0.52, 0.30, 0.22, 0.14, 0.10, 0.06], 1.6, 620.0, 1.1, beat_hz=1.0)
    fan = band(loop_noise(n, 1.0, 1502), 380.0, 2400.0, order=2, circular=True) * 0.55
    fan *= 0.85 + 0.15 * (0.5 + 0.5 * loop_smooth(n, 2.0, 1503))
    buzz = bandpass(softclip(harm(snap(100.0, dur), n, square_amps(11, 1.15)), 3.0), 1600.0, 1.4, 1, circular=True) * 0.16
    hiss = highpass(loop_noise(n, 0.6, 1504), 4000.0, order=2, circular=True) * 0.12
    out = 0.75 * hum + fan + buzz + hiss
    return dc_kill(out, circular=True)


@reg("amb_fluorescent", loop=True, target=LOOP_DB)
def amb_fluorescent():
    dur = 10.0
    n = N(dur)
    f = snap(100.0, dur)
    src = softclip(harm(f, n, square_amps(29, 0.85)), 4.5)
    buzz = bandpass(src, 1500.0, 1.0, 1, circular=True) * 1.0
    buzz += bandpass(src, 3200.0, 1.6, 1, circular=True) * 0.45
    buzz += lowpass(src, 400.0, order=2, circular=True) * 0.22
    hiss = highpass(loop_noise(n, 0.5, 1601), 5000.0, order=2, circular=True) * 0.13
    flick = 1.0 + 0.10 * loop_smooth(n, 14.0, 1602, slope=0.4)
    out = (buzz + hiss) * flick
    return dc_kill(out, circular=True)


@reg("amb_drone_low", loop=True, target=DRONE_DB)
def amb_drone_low():
    dur = 20.0
    n = N(dur)
    r = rng(1701)
    d = zeros(n)
    for f, a in ((42.0, 1.0), (42.25, 0.85), (63.3, 0.45), (84.6, 0.18)):
        d += a * sine(snap(f, dur), n, r.random() * TWO_PI)
    d *= 0.62 + 0.38 * (0.5 + 0.5 * loop_smooth(n, 0.18, 1702))
    sub = lowpass(loop_noise(n, 2.0, 1703), 95.0, order=3, circular=True) * 0.45
    met = zeros(n)
    for f, a in ((347.0, 1.0), (521.5, 0.6), (733.0, 0.38), (989.0, 0.2), (1307.0, 0.1)):
        met += a * sine(snap(f, dur), n, r.random() * TWO_PI)
        met += a * 0.7 * sine(snap(f * 1.004, dur), n, r.random() * TWO_PI)
    met *= 0.35 + 0.65 * (0.5 + 0.5 * loop_smooth(n, 0.12, 1704))
    met = bandpass(met, 700.0, 0.7, 1, circular=True) * db2lin(-26.0)
    out = d + sub + met
    return dc_kill(out, circular=True)


@reg("amb_drone_high", loop=True, target=DRONE_DB)
def amb_drone_high():
    dur = 20.0
    n = N(dur)
    r = rng(1801)
    out = zeros(n)
    # 短2度 (220 / 233.08) の持続。上の倍音もぶつける
    for base, a in ((220.0, 1.0), (233.08, 0.92)):
        for k, ka in ((1, 1.0), (2, 0.42), (3, 0.20), (5, 0.09)):
            out += a * ka * sine(snap(base * k, dur), n, r.random() * TWO_PI)
            out += a * ka * 0.6 * sine(snap(base * k * 1.0022, dur), n, r.random() * TWO_PI)
    out *= 0.55 + 0.45 * (0.5 + 0.5 * loop_smooth(n, 0.30, 1802))
    out = softclip(out * 0.5, 1.8)
    breath = band(loop_noise(n, 0.8, 1803), 1500.0, 4500.0, order=2, circular=True)
    breath *= 0.3 + 0.7 * (0.5 + 0.5 * loop_smooth(n, 0.9, 1804))
    out = out + 0.35 * breath
    out += 0.12 * sine(snap(55.0, dur), n)
    return dc_kill(out, circular=True)


@reg("amb_static", loop=True, target=LOOP_DB)
def amb_static():
    dur = 10.0
    n = N(dur)
    st = highpass(loop_noise(n, 0.15, 1901), 700.0, order=2, circular=True)
    st *= 0.82 + 0.18 * loop_smooth(n, 60.0, 1902, slope=0.3)
    st += 0.35 * highpass(loop_noise(n, 0.3, 1903), 4500.0, order=2, circular=True)
    hum = 0.05 * sine(snap(60.0, dur), n) + 0.025 * sine(snap(120.0, dur), n)
    whine = 0.030 * sine(snap(15734.0, dur), n)
    out = st + hum + whine
    # 走査線のうねり (ゆっくり動く帯域の膨らみ)
    bandmod = 1.0 + 0.25 * loop_smooth(n, 1.6, 1904)
    out = out * bandmod
    return dc_kill(out, circular=True)


# ==========================================================================
# 足音
# ==========================================================================
def _step_lino(seed, pitch, length, level):
    n = N(0.26 * length)
    r = rng(seed)
    exc = white(n, seed) * env_ar(n, 0.00015, 0.0035, 7.0)
    heel = resonators(
        exc,
        [1550 * pitch, 2450 * pitch, 3650 * pitch, 5400 * pitch],
        [11, 9, 8, 6],
        [1.0, 0.72, 0.42, 0.22],
    )
    floorb = resonators(exc, [95 * pitch, 168 * pitch, 260 * pitch], [16, 13, 10], [1.0, 0.5, 0.25])
    rub = band(white(n, seed + 1), 900.0, 6000.0, order=2) * env_ar(n, 0.004, 0.018, 5.0) * 0.35
    x = 0.9 * heel + 1.1 * floorb + rub
    x = room(x, ROOM_LINO, wet=0.26)
    return norm_peak(trim_tail(x, -70.0), -0.5) * level


def _step_tatami(seed, pitch, length, level):
    n = N(0.30 * length)
    exc = white(n, seed) * env_ar(n, 0.0008, 0.010, 5.0)
    soft = resonators(exc, [72 * pitch, 128 * pitch, 205 * pitch], [12, 10, 8], [1.0, 0.55, 0.26])
    straw = band(white(n, seed + 1), 1600.0, 5200.0, order=2)
    straw *= grain_env(n, 26, seed + 2, spread=0.55, dur_sec=0.006) * env_ar(n, 0.002, 0.045, 4.0) * 0.30
    mat = lowpass(white(n, seed + 3) * env_ar(n, 0.002, 0.030, 4.0), 700.0, order=2) * 0.5
    x = 1.2 * soft + straw + mat
    x = lowpass(x, 5200.0, order=1)
    x = room(x, ROOM_TATAMI, wet=0.12)
    return norm_peak(trim_tail(x, -70.0), -0.5) * level


def _step_concrete(seed, pitch, length, level):
    n = N(0.5 * length)
    exc = white(n, seed) * env_ar(n, 0.0001, 0.0028, 8.0)
    hard = resonators(
        exc,
        [1180 * pitch, 2150 * pitch, 3300 * pitch, 4900 * pitch, 7200 * pitch],
        [9, 8, 7, 6, 5],
        [1.0, 0.8, 0.55, 0.32, 0.16],
    )
    thud = resonators(exc, [78 * pitch, 140 * pitch], [13, 10], [1.0, 0.45])
    grit = band(white(n, seed + 1), 2500.0, 9000.0, order=2)
    grit *= grain_env(n, 9, seed + 2, spread=0.25, dur_sec=0.004) * 0.35
    x = 1.0 * hard + 1.0 * thud + grit
    x = room(x, dict(dur=0.6, decay=0.13, damp_hz=2600.0, predelay=0.018, seed=107), wet=0.32)
    return norm_peak(trim_tail(x, -62.0), -0.5) * level


_STEP_VARIANTS = (
    (1.06, 0.92, 1.00),
    (0.94, 1.08, 0.93),
    (1.13, 0.86, 0.87),
    (0.88, 1.00, 0.97),
)
for _i, (_p, _l, _v) in enumerate(_STEP_VARIANTS, start=1):
    reg("step_lino_%d" % _i)(lambda p=_p, l=_l, v=_v, s=2100 + _i: _step_lino(s, p, l, v))
    reg("step_tatami_%d" % _i)(lambda p=_p, l=_l, v=_v, s=2200 + _i: _step_tatami(s, p, l, v))
    reg("step_concrete_%d" % _i)(lambda p=_p, l=_l, v=_v, s=2300 + _i: _step_concrete(s, p, l, v))


@reg("footstep_ceiling_1")
def footstep_ceiling_1():
    return _ceiling_step(2401, 1.0, 1.0)


@reg("footstep_ceiling_2")
def footstep_ceiling_2():
    return _ceiling_step(2402, 0.9, 1.12)


@reg("footstep_ceiling_3")
def footstep_ceiling_3():
    return _ceiling_step(2403, 1.12, 0.9)


def _ceiling_step(seed, pitch, length):
    """天井裏を歩く: 重い衝撃が板と天井でこもる。"""
    n = N(0.6 * length)
    exc = white(n, seed) * env_ar(n, 0.0009, 0.012, 5.0)
    thud = resonators(exc, [46 * pitch, 63 * pitch, 92 * pitch], [11, 9, 8], [1.0, 0.7, 0.4])
    board = resonators(exc, [148 * pitch, 236 * pitch, 390 * pitch], [18, 15, 12], [0.55, 0.32, 0.16])
    dust = lowpass(white(n, seed + 1) * env_ar(n, 0.004, 0.10, 3.5), 300.0, order=2) * 0.28
    x = 1.3 * thud + board + dust
    x = lowpass(x, 420.0, order=3)
    x = room(x, ROOM_TIGHT, wet=0.22)
    return norm_peak(x, -0.5)


# ==========================================================================
# 扉・窓
# ==========================================================================
@reg("door_open")
def door_open():
    """木戸: ラッチが外れる -> 蝶番の軋み (ピッチが上がる) -> 木の落ち着き。"""
    total = N(1.65)
    out = zeros(total)
    nl = N(0.12)
    latch = metal_hit(nl, 2501, base=2100.0, decay=0.020, count=5, bright=0.8) * env_ar(nl, 0.0002, 0.010, 6.0)
    latch += wood_knock(nl, 2502, pitch=1.3, decay=0.35, thump=0.4) * 0.5
    place(out, norm_peak(latch, -6.0), 0.0)
    nc = N(1.05)
    rate = segments([(0.0, 26.0), (0.25, 44.0), (0.7, 30.0), (1.0, 16.0)], nc)
    cr = creak(nc, 210.0, 470.0, 2503, rate=rate, ratios=(1.0, 2.03, 3.11, 4.68, 6.2), q=44.0, curve=0.8)
    cr *= segments([(0.0, 0.0), (0.05, 0.9), (0.45, 1.0), (0.8, 0.55), (1.0, 0.0)], nc)
    cr = cr + 0.25 * svf_tv(white(nc, 2504) * 0.5, glide(210.0, 470.0, nc, 0.8) * 2.0, 6.0, "bp") * segments(
        [(0.0, 0.0), (0.1, 0.7), (1.0, 0.0)], nc
    )
    place(out, norm_peak(cr, -2.5), 0.09)
    nw = N(0.32)
    settle = wood_knock(nw, 2505, pitch=0.8, decay=0.7, thump=1.0) * 0.55
    place(out, norm_peak(settle, -10.0), 1.22)
    out = room(out, ROOM_LINO, wet=0.24)
    return norm_peak(trim_tail(out, -68.0), -0.5)


@reg("door_close")
def door_close():
    """重い衝突 + ラッチ + 短い残響。"""
    total = N(1.1)
    out = zeros(total)
    ns = N(0.20)
    swing = band(white(ns, 2601), 200.0, 1800.0, order=2) * segments([(0, 0.0), (0.8, 0.5), (1, 1.0)], ns) * 0.22
    place(out, swing, 0.0)
    nb = N(0.55)
    slam = wood_knock(nb, 2602, pitch=0.62, decay=1.5, bright=0.7, thump=2.4)
    slam += lowpass(white(nb, 2603) * env_ar(nb, 0.0006, 0.035, 4.0), 220.0, order=3) * 1.5
    place(out, norm_peak(slam, -0.8), 0.20)
    nl = N(0.10)
    latch = metal_hit(nl, 2604, base=1900.0, decay=0.018, count=5) * env_ar(nl, 0.0002, 0.008, 7.0)
    place(out, norm_peak(latch, -11.0), 0.245)
    out = room(out, ROOM_LINO, wet=0.30)
    return norm_peak(trim_tail(out, -68.0), -0.5)


@reg("door_locked")
def door_locked():
    """ガチャガチャ 2 回。ノブの金属とラッチが噛む音 + 戸の低い抵抗。"""
    total = N(1.35)
    out = zeros(total)
    r = rng(2701)
    for gi, t0 in enumerate((0.02, 0.44)):
        for k in range(4):
            at = t0 + k * (0.055 + 0.03 * r.random())
            nl = N(0.09)
            m = metal_hit(nl, 2710 + gi * 10 + k, base=1500.0 + 900.0 * r.random(), decay=0.016, count=5, bright=1.1)
            m *= env_ar(nl, 0.00015, 0.007, 7.0)
            place(out, norm_peak(m, -2.0 - 4.0 * r.random()), at)
        nb = N(0.28)
        body = wood_knock(nb, 2740 + gi, pitch=0.55, decay=1.1, bright=0.4, thump=1.8) * 0.5
        place(out, norm_peak(body, -9.0), t0 + 0.035)
    out = room(out, ROOM_LINO, wet=0.26)
    return norm_peak(trim_tail(out, -68.0), -0.5)


@reg("door_steel_open")
def door_steel_open():
    """鉄扉: 甲高い金属の軋み + 低い蝶番のうなり。"""
    total = N(1.9)
    out = zeros(total)
    nl = N(0.12)
    place(out, norm_peak(metal_hit(nl, 2801, base=2600.0, decay=0.030, count=6, bright=1.3), -5.0), 0.0)
    nc = N(1.35)
    rate = segments([(0.0, 30.0), (0.3, 58.0), (0.75, 40.0), (1.0, 20.0)], nc)
    hi = creak(nc, 900.0, 2250.0, 2802, rate=rate, ratios=(1.0, 1.98, 3.02), q=70.0, curve=0.75)
    hi *= segments([(0.0, 0.0), (0.06, 1.0), (0.55, 0.85), (1.0, 0.0)], nc)
    lo = creak(nc, 105.0, 168.0, 2803, rate=rate * 0.5, ratios=(1.0, 2.1, 3.3), q=28.0)
    lo *= segments([(0.0, 0.0), (0.1, 0.8), (1.0, 0.0)], nc)
    place(out, norm_peak(hi, -1.5), 0.07)
    place(out, norm_peak(lo, -8.0), 0.07)
    nm = N(0.5)
    place(out, norm_peak(metal_hit(nm, 2804, base=430.0, decay=0.22, count=7), -13.0), 1.35)
    out = room(out, ROOM_TILE, wet=0.32)
    return norm_peak(trim_tail(out, -68.0), -0.5)


@reg("door_steel_close")
def door_steel_close():
    """鉄扉の重い閉音: 打撃 + 長い金属の残鳴。"""
    total = N(2.0)
    out = zeros(total)
    nb = N(1.7)
    boom = lowpass(white(nb, 2901) * env_ar(nb, 0.0005, 0.045, 4.0), 160.0, order=3) * 2.0
    boom += resonators(white(nb, 2902) * env_ar(nb, 0.0002, 0.004, 7.0), [62, 108, 175], [14, 12, 10], [1.0, 0.6, 0.3]) * 1.4
    ring = metal_hit(nb, 2903, base=330.0, decay=0.60, count=9, bright=1.2) * 0.85
    ring += metal_hit(nb, 2904, base=1250.0, decay=0.22, count=7, bright=1.0) * 0.45
    place(out, norm_peak(boom + ring, -0.8), 0.0)
    nl = N(0.12)
    place(out, norm_peak(metal_hit(nl, 2905, base=2400.0, decay=0.020, count=5), -9.0), 0.055)
    out = room(out, ROOM_TILE, wet=0.35)
    return norm_peak(trim_tail(out, -68.0), -0.5)


def _knock3(seed, spacing, force, pitch):
    total = N(1.5)
    out = zeros(total)
    r = rng(seed)
    t = 0.02
    for k in range(3):
        nk = N(0.45)
        kk = wood_knock(nk, seed + k, pitch=pitch * (1.0 + (r.random() - 0.5) * 0.07), decay=1.0, bright=1.0, thump=1.3)
        g = force * (1.0 if k == 0 else (0.92 + 0.16 * r.random()))
        place(out, norm_peak(kk, -0.8), t, g)
        t += spacing * (1.0 + (r.random() - 0.5) * 0.18)
    out = room(out, ROOM_LINO, wet=0.34)
    return norm_peak(trim_tail(out, -68.0), -0.5)


reg("door_knock_1")(lambda: _knock3(3001, 0.215, 1.0, 1.0))
reg("door_knock_2")(lambda: _knock3(3011, 0.165, 1.0, 0.88))
reg("door_knock_3")(lambda: _knock3(3021, 0.285, 0.85, 1.14))


def _sash(seed, f_lo, f_hi, dur, thunk_pitch, glass=0.5):
    """アルミサッシの引き開け/閉め。"""
    total = N(dur + 0.55)
    out = zeros(total)
    ns = N(dur)
    rate = segments([(0.0, 90.0), (0.3, 150.0), (1.0, 70.0)], ns)
    sl = scrape(ns, seed, f_lo, f_hi, rate, rough=0.75, jitter=0.5, sharp=140.0)
    sl *= segments([(0.0, 0.0), (0.08, 1.0), (0.75, 0.85), (1.0, 0.25)], ns)
    sl += 0.30 * bandpass(white(ns, seed + 1), 240.0, 1.4, 1) * segments([(0, 0.0), (0.2, 1.0), (1, 0.4)], ns)
    place(out, norm_peak(sl, -3.5), 0.0)
    nr = N(0.32)
    rat = metal_hit(nr, seed + 2, base=1900.0 * thunk_pitch, decay=0.055, count=6, bright=1.2) * glass
    place(out, norm_peak(rat, -6.0), dur - 0.02)
    nt = N(0.3)
    th = wood_knock(nt, seed + 3, pitch=0.7 * thunk_pitch, decay=0.7, bright=0.5, thump=1.6)
    place(out, norm_peak(th, -4.0), dur - 0.01)
    out = room(out, ROOM_LINO, wet=0.22)
    return norm_peak(trim_tail(out, -68.0), -0.5)


reg("window_open")(lambda: _sash(3101, 350.0, 3200.0, 0.85, 1.0, 0.55))
reg("window_close")(lambda: _sash(3111, 300.0, 2600.0, 0.62, 0.85, 0.75))


@reg("window_tap")
def window_tap():
    """ガラスを軽く叩く/何かが当たる。"""
    n = N(0.7)
    exc = white(n, 3201) * env_ar(n, 0.00006, 0.0008, 9.0)
    g = partials(
        n,
        [2480.0, 3810.0, 5230.0, 6940.0, 9100.0],
        [0.16, 0.12, 0.09, 0.06, 0.04],
        [1.0, 0.66, 0.42, 0.24, 0.12],
        seed=3202,
        detune=0.004,
    )
    g += 0.5 * bandpass(exc, 4200.0, 2.0, 1)
    frame = resonators(exc, [190.0, 340.0], [14, 11], [0.45, 0.2])
    x = g * 1.0 + frame
    x = room(x, ROOM_LINO, wet=0.20)
    return norm_peak(trim_tail(x, -68.0), -0.5)


# ==========================================================================
# 火 (線香・ロウソク・マッチ)
# ==========================================================================
def _strike_scrape(n, seed, lo=1800.0, hi=9000.0, rate=220.0):
    x = band(white(n, seed), lo, hi, order=2)
    x *= grain_env(n, max(10, int(n / SR * 260)), seed + 1, dur_sec=0.0022, jitter=0.8)
    x *= 0.4 + 0.6 * stick_slip(n, rate, seed + 2, jitter=0.7, sharp=300.0)
    return x


def _ignite(n, seed, bright=1.0, depth=1.0):
    """発火の「ポッ」: 帯域が一気に下がるノイズの膨らみ。"""
    e = segments([(0.0, 0.0), (0.03, 1.0), (0.25, 0.45), (1.0, 0.0)], n)
    f = glide(4200.0 * bright, 700.0, n, 0.5)
    x = svf_tv(white(n, seed) * e, f, 1.1, "lp")
    x += lowpass(white(n, seed + 1) * e, 400.0, order=2) * 0.8 * depth
    return x


def _flame_flutter(n, seed, level=1.0):
    x = lowpass(white(n, seed), 900.0, order=2)
    x *= 0.25 + 0.75 * np.abs(smooth_noise(n, 9.0, seed + 1))
    tick = zeros(n)
    r = rng(seed + 2)
    for _ in range(max(2, int(n / SR * 9))):
        pos = int(r.random() * n)
        nc = N(0.004)
        if pos + nc < n:
            tick[pos : pos + nc] += bandpass(white(nc, int(r.random() * 1e6)) * env_ar(nc, 0.0002, 0.0012, 6.0), 2600.0, 3.0, 1)
    return (x * 0.55 + tick * 0.5) * level


@reg("match_strike")
def match_strike():
    total = N(1.25)
    out = zeros(total)
    ns = N(0.13)
    place(out, norm_peak(_strike_scrape(ns, 4001), -2.0), 0.0)
    ni = N(0.35)
    place(out, norm_peak(_ignite(ni, 4002, 1.0, 1.0), -0.5), 0.10)
    nf = N(0.75)
    fl = _flame_flutter(nf, 4003) * segments([(0, 1.0), (1, 0.35)], nf)
    place(out, norm_peak(fl, -17.0), 0.42)
    out = room(out, ROOM_LINO, wet=0.18)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("match_fail")
def match_fail():
    """擦るだけ。火が点かない。2 回。"""
    total = N(0.95)
    out = zeros(total)
    for at, sd, g, d in ((0.02, 4011, 1.0, 0.11), (0.38, 4012, 0.85, 0.09)):
        ns = N(d)
        place(out, norm_peak(_strike_scrape(ns, sd, 1600.0, 9500.0, 240.0), -1.0), at, g)
    out = room(out, ROOM_LINO, wet=0.18)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("incense_light")
def incense_light():
    """マッチ -> 線香に火が移る「シュ…」。"""
    total = N(2.4)
    out = zeros(total)
    ns = N(0.12)
    place(out, norm_peak(_strike_scrape(ns, 4101), -5.0), 0.0)
    ni = N(0.3)
    place(out, norm_peak(_ignite(ni, 4102, 0.9, 0.8), -2.0), 0.09)
    # 火が移るときの長い「シュ…」
    nh = N(1.5)
    hiss = band(white(nh, 4103), 900.0, 7000.0, order=2)
    hiss *= segments([(0.0, 0.0), (0.06, 1.0), (0.45, 0.6), (1.0, 0.0)], nh)
    hiss *= 0.5 + 0.5 * np.abs(smooth_noise(nh, 14.0, 4104))
    place(out, norm_peak(hiss, -4.0), 0.36)
    nf = N(0.9)
    place(out, norm_peak(_flame_flutter(nf, 4105), -16.0), 0.5)
    out = room(out, ROOM_HALL, wet=0.20)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("incense_hiss", loop=True)
def incense_hiss():
    """線香が燃える微音のループ (4 秒)。ほぼ無音 + たまに「チリ」。"""
    dur = 4.0
    n = N(dur)
    bed = band(loop_noise(n, 0.7, 4201), 1800.0, 9000.0, order=2, circular=True)
    bed *= 0.45 + 0.55 * (0.5 + 0.5 * loop_smooth(n, 11.0, 4202))
    out = bed * 0.30
    r = rng(4203)
    for i in range(16):
        nc = N(0.0035 + 0.0035 * r.random())
        c = bandpass(white(nc, 4210 + i) * env_ar(nc, 0.00015, 0.0012, 7.0), 2600.0 + 4200.0 * r.random(), 3.5, 1)
        place_wrap(out, norm_peak(c, -3.0 - 9.0 * r.random()), r.random() * dur, 0.5)
    return dc_kill(out, circular=True)


@reg("candle_light")
def candle_light():
    total = N(1.9)
    out = zeros(total)
    ns = N(0.12)
    place(out, norm_peak(_strike_scrape(ns, 4301), -6.0), 0.0)
    ni = N(0.42)
    place(out, norm_peak(_ignite(ni, 4302, 0.7, 1.3), -0.5), 0.09)
    nf = N(1.2)
    fl = _flame_flutter(nf, 4303) * segments([(0, 0.45), (0.15, 1.0), (1, 0.5)], nf)
    place(out, norm_peak(fl, -13.0), 0.4)
    out = room(out, ROOM_HALL, wet=0.22)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("candle_blow")
def candle_blow():
    """息で消える: 息 -> 炎が消える「ふっ」-> 芯のわずかな燻り。"""
    total = N(1.7)
    out = zeros(total)
    nb = N(0.55)
    br = band(white(nb, 4401), 260.0, 3000.0, order=2)
    br = svf_tv(br, glide(320.0, 900.0, nb, 0.7), 1.0, "bp") * 2.0
    br *= segments([(0.0, 0.0), (0.18, 1.0), (0.55, 0.8), (1.0, 0.0)], nb)
    place(out, norm_peak(br, -1.0), 0.0)
    np_ = N(0.18)
    puff = lowpass(white(np_, 4402) * segments([(0, 0.0), (0.1, 1.0), (1, 0.0)], np_), 600.0, order=2)
    place(out, norm_peak(puff, -9.0), 0.30)
    nw = N(0.6)
    wick = band(white(nw, 4403), 1200.0, 6000.0, order=2) * segments([(0, 1.0), (1, 0.0)], nw)
    wick *= grain_env(nw, 14, 4404, dur_sec=0.003)
    place(out, norm_peak(wick, -21.0), 0.42)
    out = room(out, ROOM_HALL, wet=0.22)
    return norm_peak(trim_tail(out, -66.0), -0.5)


# ==========================================================================
# 電話
# ==========================================================================
@reg("phone_ring", loop=True)
def phone_ring():
    """日本のビジネスフォン。2 秒鳴って 1 秒休む 3 秒ループ。"""
    dur = 3.0
    n = N(dur)
    out = zeros(n)
    nr = N(2.0)
    # 「プルルル」: 電子ベルの倍音 + 細かいトレモロ
    base = harm(1030.0, nr, [1.0, 0.55, 0.30, 0.18, 0.10, 0.06])
    base += 0.7 * harm(1287.0, nr, [1.0, 0.42, 0.22, 0.12, 0.07])
    base = softclip(base * 0.5, 2.6)
    trill = 0.5 + 0.5 * lfo(nr, 21.0, 1.0, 0.0, 0.0, "sine")
    trill = trill ** 1.6
    base = base * (0.12 + 0.88 * trill)
    # 小さなスピーカで鳴っている感じ
    base = bandpass(base, 1500.0, 0.85, 1) + 0.35 * bandpass(base, 3000.0, 1.6, 1)
    base = highpass(base, 420.0, order=2)
    # 筐体のビリつき
    buzz = bandpass(white(nr, 4501), 2300.0, 2.5, 1) * (trill ** 3) * 0.10
    ring = (base + buzz) * segments([(0.0, 0.0), (0.004, 1.0), (0.97, 1.0), (1.0, 0.0)], nr)
    ring = room(ring, ROOM_TIGHT, wet=0.20)[:nr]
    place(out, norm_peak(ring, -0.5), 0.0)
    return fade(dc_kill(out), 0.002, 0.03)


@reg("phone_pickup")
def phone_pickup():
    total = N(0.75)
    out = zeros(total)
    place(out, norm_peak(soft_click(4601, 2400.0, 3.0, 1.0, 0.07), -1.0), 0.0)
    place(out, norm_peak(soft_click(4602, 1500.0, 4.0, 1.2, 0.09), -3.0), 0.045)
    nr = N(0.35)
    cord = band(white(nr, 4603), 500.0, 4000.0, order=2) * grain_env(nr, 12, 4604, dur_sec=0.01) * 0.5
    place(out, norm_peak(cord, -12.0), 0.08)
    nl = N(0.25)
    line = band(white(nl, 4605), 300.0, 3400.0, order=2) * segments([(0, 0.0), (0.2, 1.0), (1, 0.8)], nl)
    place(out, norm_peak(line, -30.0), 0.2)
    out = room(out, ROOM_TIGHT, wet=0.16)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("phone_hangup")
def phone_hangup():
    total = N(0.9)
    out = zeros(total)
    nc = N(0.3)
    clack = wood_knock(nc, 4701, pitch=2.4, decay=0.22, bright=1.4, thump=0.5)
    clack += metal_hit(nc, 4702, base=1700.0, decay=0.030, count=5) * 0.6
    place(out, norm_peak(clack, -0.5), 0.0)
    nb = N(0.45)
    bellring = partials(nb, [1030.0, 1287.0, 2100.0], [0.05, 0.04, 0.025], [1.0, 0.6, 0.25], seed=4703)
    place(out, norm_peak(bellring, -20.0), 0.012)
    place(out, norm_peak(soft_click(4704, 1200.0, 4.0, 1.0, 0.06), -9.0), 0.07)
    out = room(out, ROOM_TIGHT, wet=0.18)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("phone_breath")
def phone_breath():
    """受話器越しの息。帯域 300-3400Hz + 回線のノイズ。"""
    n = N(3.2)
    bed = band(white(n, 4801), 300.0, 3400.0, order=2) * 0.05
    out = bed.copy()
    for at, d, sd, g in ((0.25, 0.85, 4802, 1.0), (1.55, 1.05, 4803, 0.85)):
        nb = N(d)
        b = band(white(nb, sd), 300.0, 2600.0, order=2)
        b = svf_tv(b, segments([(0, 480.0), (0.4, 1100.0), (1, 620.0)], nb), 0.9, "bp") * 2.2
        b *= segments([(0.0, 0.0), (0.22, 1.0), (0.6, 0.75), (1.0, 0.0)], nb)
        place(out, norm_peak(b, -1.0), at, g)
    out = band(out, 300.0, 3400.0, order=3)
    out = softclip(out * 1.2, 1.4)
    out += 0.012 * sine(50.0, len(out))
    return norm_peak(dc_kill(out), -0.5)


@reg("phone_voice_wet")
def phone_voice_wet():
    """言葉ではない、濡れた低い唸り (3 秒)。帯域制限 + 歪み。"""
    n = N(3.2)
    f0 = segments([(0.0, 88.0), (0.25, 74.0), (0.6, 96.0), (1.0, 62.0)], n)
    src = voice_src(n, f0, 4901, jitter=0.055, width=0.11, breath=0.22, rough=0.35)
    v = formant(src, [(330.0, 4.5, 0.0), (760.0, 5.0, -4.0), (1450.0, 6.0, -11.0), (2500.0, 7.0, -18.0)])
    # 濡れた感じ: 低周波ノイズで開閉する共鳴 + ごぼつき
    wet = svf_tv(src, segments([(0, 420.0), (0.3, 250.0), (0.7, 560.0), (1, 300.0)], n), 5.0, "bp")
    gurgle = 0.55 + 0.45 * smooth_noise(n, 7.0, 4902)
    x = (v + 0.7 * wet) * gurgle
    x *= segments([(0.0, 0.0), (0.06, 1.0), (0.75, 0.95), (1.0, 0.0)], n)
    x = softclip(x * 2.2, 2.8)
    x = band(x, 300.0, 3400.0, order=3)
    x += 0.02 * band(white(n, 4903), 300.0, 3400.0, order=2)
    return norm_peak(dc_kill(x), -0.5)


# ==========================================================================
# 猫
# ==========================================================================
def _meow(seed, dur, f0_pts, f1_pts, f2_pts, rough, breath, nasal_end=1.0):
    n = N(dur)
    f0 = segments(f0_pts, n)
    src = voice_src(n, f0, seed, jitter=0.022, width=0.10, breath=breath, rough=rough)
    f1 = segments(f1_pts, n)
    f2 = segments(f2_pts, n)
    v = 1.00 * svf_tv(src, f1, 4.5, "bp")
    v += 0.55 * svf_tv(src, f2, 5.5, "bp")
    v += 0.22 * bandpass(src, 3100.0, 5.0, 1)
    v += 0.10 * bandpass(src, 4600.0, 6.0, 1)
    # 口の開閉 (最初と最後はこもる)
    open_env = segments([(0.0, 0.25), (0.18, 1.0), (0.62, 1.0), (1.0, 0.25 * nasal_end)], n)
    v = svf_tv(v, 700.0 + 5200.0 * open_env, 0.8, "lp")
    amp = segments([(0.0, 0.0), (0.06, 0.85), (0.3, 1.0), (0.72, 0.8), (1.0, 0.0)], n)
    v *= amp
    v += 0.10 * band(white(n, seed + 7), 2500.0, 7000.0, order=2) * amp
    v = room(v, ROOM_LINO, wet=0.22)
    return norm_peak(dc_kill(trim_tail(v, -66.0)), -0.5)


reg("cat_meow_1")(
    lambda: _meow(
        5001, 0.85,
        [(0, 470), (0.14, 690), (0.45, 760), (0.8, 600), (1, 470)],
        [(0, 420), (0.25, 880), (0.7, 700), (1, 430)],
        [(0, 1150), (0.25, 2000), (0.7, 1600), (1, 1180)],
        rough=0.10, breath=0.10,
    )
)
reg("cat_meow_2")(
    lambda: _meow(
        5011, 1.25,
        [(0, 560), (0.1, 800), (0.35, 840), (0.7, 700), (1, 520)],
        [(0, 380), (0.2, 950), (0.55, 820), (1, 400)],
        [(0, 1050), (0.2, 2250), (0.6, 1750), (1, 1100)],
        rough=0.20, breath=0.14, nasal_end=1.3,
    )
)
reg("cat_meow_3")(
    lambda: _meow(
        5021, 0.62,
        [(0, 640), (0.2, 790), (0.6, 720), (1, 560)],
        [(0, 500), (0.3, 1050), (1, 520)],
        [(0, 1300), (0.3, 2500), (1, 1350)],
        rough=0.30, breath=0.20,
    )
)


@reg("cat_hiss")
def cat_hiss():
    n = N(1.25)
    hi = band(white(n, 5101), 2800.0, 9500.0, order=2)
    hi = svf_tv(hi, segments([(0, 5200.0), (0.3, 4200.0), (1, 5800.0)], n), 1.1, "bp") * 1.8
    hi *= segments([(0.0, 0.0), (0.03, 1.0), (0.55, 0.85), (1.0, 0.0)], n)
    hi *= 0.6 + 0.4 * np.abs(smooth_noise(n, 22.0, 5102))
    spit = band(white(N(0.05), 5103), 1500.0, 9000.0, order=2) * env_ar(N(0.05), 0.0005, 0.010, 6.0)
    growl = voice_src(n, segments([(0, 130), (1, 96)], n), 5104, jitter=0.07, width=0.14, breath=0.3, rough=0.5)
    growl = formant(growl, [(280.0, 4.0, 0.0), (700.0, 5.0, -7.0)]) * segments([(0, 0.0), (0.2, 0.7), (1, 0.0)], n)
    out = hi + 0.35 * growl
    place(out, norm_peak(spit, -1.0), 0.0, 0.8)
    out = room(out, ROOM_LINO, wet=0.20)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


def _claw(seed, dur, count, lo, hi, wood_pitch, muffle=None, rev=ROOM_LINO, rev_wet=0.22):
    """爪で引っ掻く: 速い連続の微小スクレイプ + 木の胴鳴り。"""
    n = N(dur)
    r = rng(seed)
    out = zeros(n)
    t = 0.01
    for k in range(count):
        d = 0.035 + 0.05 * r.random()
        ns = min(N(d), n - N(t) - 1)
        if ns < 64:
            break
        sc = band(white(ns, seed + k), lo, hi, order=2)
        sc *= grain_env(ns, 20, seed + 100 + k, dur_sec=0.0018, jitter=0.9)
        sc *= segments([(0, 0.2), (0.15, 1.0), (1, 0.0)], ns)
        exc = white(ns, seed + 200 + k) * env_ar(ns, 0.0002, 0.0018, 7.0)
        body = resonators(exc, [210 * wood_pitch, 355 * wood_pitch, 640 * wood_pitch], [22, 18, 14], [1.0, 0.5, 0.22])
        seg = 1.0 * sc + 0.5 * body
        place(out, norm_peak(seg, -1.0 - 5.0 * r.random()), t)
        t += d * (0.55 + 0.5 * r.random())
        if t > dur - 0.08:
            break
    if muffle:
        out = lowpass(out, muffle, order=3)
    out = room(out, rev, wet=rev_wet)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


reg("cat_scratch_1")(lambda: _claw(5201, 0.75, 9, 1400.0, 8000.0, 1.0))
reg("cat_scratch_2")(lambda: _claw(5221, 1.05, 14, 1700.0, 9000.0, 0.88))
reg("cat_scratch_3")(lambda: _claw(5241, 0.55, 6, 1200.0, 7000.0, 1.15))


@reg("cat_purr", loop=True)
def cat_purr():
    dur = 2.0
    n = N(dur)
    rate = snap(26.0, dur)
    src = pulse_train(rate, n, 0.30)
    src = src + 0.9 * loop_noise(n, 1.4, 5301)
    body = bandpass(src, 155.0, 1.8, 1, circular=True) * 1.0
    body += bandpass(src, 330.0, 2.2, 1, circular=True) * 0.45
    body += bandpass(src, 720.0, 3.0, 1, circular=True) * 0.14
    am = 0.35 + 0.65 * (0.5 + 0.5 * lfo(n, rate, 1.0, 0.0, 0.0, "sine")) ** 1.4
    # 吸う/吐くの 2 相 (ループ長でちょうど 1 往復)
    phase2 = 0.62 + 0.38 * (0.5 + 0.5 * lfo(n, snap(0.5, dur)))
    out = body * am * phase2
    out += 0.06 * lowpass(loop_noise(n, 1.0, 5302), 900.0, order=2, circular=True) * phase2
    return dc_kill(out, circular=True)


# ==========================================================================
# 棺 (すべて「内側から」なのでこもらせる)
# ==========================================================================
BOX = dict(dur=0.28, decay=0.045, damp_hz=1200.0, predelay=0.003, seed=108)


@reg("coffin_knock")
def coffin_knock():
    n = N(1.0)
    k = wood_knock(n, 5401, pitch=0.62, decay=1.6, bright=0.35, thump=2.2)
    k += resonators(white(n, 5402) * env_ar(n, 0.0004, 0.006, 6.0), [88.0, 132.0], [20, 16], [1.0, 0.5]) * 1.2
    k = lowpass(k, 620.0, order=3)
    k = room(k, BOX, wet=0.35)
    k = room(k, ROOM_HALL, wet=0.28)
    return norm_peak(dc_kill(trim_tail(k, -66.0)), -0.5)


@reg("coffin_creak")
def coffin_creak():
    n = N(1.8)
    rate = segments([(0, 16.0), (0.35, 26.0), (1, 10.0)], n)
    c = creak(n, 88.0, 148.0, 5501, rate=rate, ratios=(1.0, 2.05, 3.2, 4.6), q=32.0, sharp=60.0)
    c *= segments([(0.0, 0.0), (0.1, 1.0), (0.6, 0.7), (1.0, 0.0)], n)
    c = lowpass(c, 900.0, order=3)
    c = room(c, BOX, wet=0.30)
    c = room(c, ROOM_HALL, wet=0.30)
    return norm_peak(dc_kill(trim_tail(c, -66.0)), -0.5)


@reg("coffin_scratch")
def coffin_scratch():
    return _claw(5601, 1.6, 16, 900.0, 5000.0, 0.7, muffle=800.0, rev=ROOM_HALL, rev_wet=0.30)


@reg("coffin_lid_slide")
def coffin_lid_slide():
    """木が擦れる 1 秒 + 最後に当たる。"""
    total = N(1.9)
    out = zeros(total)
    ns = N(1.0)
    rate = segments([(0, 42.0), (0.4, 72.0), (1, 34.0)], ns)
    sl = scrape(ns, 5701, 180.0, 2200.0, rate, rough=0.85, jitter=0.55, sharp=90.0)
    sl *= segments([(0.0, 0.0), (0.1, 1.0), (0.8, 0.9), (1.0, 0.3)], ns)
    rum = lowpass(white(ns, 5702), 220.0, order=3) * segments([(0, 0.0), (0.15, 1.0), (1, 0.4)], ns) * 0.9
    place(out, norm_peak(sl + rum, -1.0), 0.0)
    nk = N(0.55)
    place(out, norm_peak(wood_knock(nk, 5703, pitch=0.55, decay=1.3, bright=0.4, thump=1.7), -6.0), 0.97)
    out = room(out, ROOM_HALL, wet=0.28)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


# ==========================================================================
# 電気まわり
# ==========================================================================
@reg("breaker_click")
def breaker_click():
    total = N(0.6)
    out = zeros(total)
    nc = N(0.12)
    c1 = metal_hit(nc, 5801, base=1450.0, decay=0.014, count=5, bright=1.1) * env_ar(nc, 0.0001, 0.005, 8.0)
    c1 += wood_knock(nc, 5802, pitch=2.6, decay=0.18, bright=1.2, thump=0.35) * 0.7
    place(out, norm_peak(c1, -0.5), 0.0)
    c2 = metal_hit(nc, 5803, base=2300.0, decay=0.010, count=4, bright=1.0) * env_ar(nc, 0.0001, 0.004, 8.0)
    place(out, norm_peak(c2, -7.0), 0.022)
    ns = N(0.18)
    spring = partials(ns, [3200.0, 4700.0], [0.020, 0.014], [1.0, 0.5], seed=5804)
    place(out, norm_peak(spring, -18.0), 0.024)
    out = room(out, ROOM_TIGHT, wet=0.22)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("lights_off")
def lights_off():
    """電源が落ちる「ブン…」+ コイルの残響 + 蛍光灯が死ぬ。"""
    total = N(2.0)
    out = zeros(total)
    nc = N(0.1)
    place(out, norm_peak(metal_hit(nc, 5901, base=900.0, decay=0.012, count=5), -5.0), 0.0)
    nh = N(1.1)
    hum = harm(120.0, nh, [1.0, 0.5, 0.28, 0.12, 0.06])
    hum += 0.6 * harm(60.0, nh, [1.0, 0.35, 0.15])
    hum = softclip(hum * 0.6, 1.8)
    hum *= env_ar(nh, 0.004, 0.16, 4.5)
    hum = lowpass(hum, 900.0, order=2)
    place(out, norm_peak(hum, -0.5), 0.005)
    nt = N(0.85)
    tube = bandpass(white(nt, 5902), 2400.0, 2.0, 1) * env_ar(nt, 0.002, 0.07, 5.0) * 0.5
    tube += sine(glide(4200.0, 900.0, nt, 1.6), nt) * env_ar(nt, 0.002, 0.10, 5.0) * 0.30
    place(out, norm_peak(tube, -14.0), 0.02)
    out = room(out, ROOM_LINO, wet=0.28)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("lights_on")
def lights_on():
    """リレー -> グロー球のどもり -> ハムが立ち上がる。"""
    total = N(2.2)
    out = zeros(total)
    nc = N(0.12)
    place(out, norm_peak(metal_hit(nc, 6001, base=1100.0, decay=0.014, count=5), -3.0), 0.0)
    r = rng(6002)
    for k, at in enumerate((0.09, 0.21, 0.30, 0.42)):
        nb = N(0.04 + 0.05 * r.random())
        b = softclip(harm(100.0, nb, square_amps(23, 0.9)), 5.0)
        b = bandpass(b, 1500.0 + 900.0 * r.random(), 1.2, 1)
        b *= env_ar(nb, 0.0015, 0.02, 4.0)
        place(out, norm_peak(b, -2.0 - 3.0 * r.random()), at)
    nh = N(1.5)
    buzz = softclip(harm(100.0, nh, square_amps(25, 0.85)), 4.5)
    buzz = bandpass(buzz, 1500.0, 1.0, 1) * 1.0 + 0.4 * bandpass(buzz, 3200.0, 1.6, 1)
    buzz *= segments([(0.0, 0.0), (0.08, 1.0), (0.3, 0.7), (1.0, 0.55)], nh)
    place(out, norm_peak(buzz, -11.0), 0.46)
    out = room(out, ROOM_LINO, wet=0.24)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("fluorescent_flicker")
def fluorescent_flicker():
    total = N(1.1)
    out = zeros(total)
    r = rng(6101)
    t = 0.0
    while t < 0.9:
        nb = N(0.012 + 0.05 * r.random())
        b = softclip(harm(100.0, nb, square_amps(27, 0.85)), 5.5)
        b = bandpass(b, 1400.0 + 1600.0 * r.random(), 1.3, 1) + 0.4 * bandpass(b, 3400.0, 1.8, 1)
        b *= env_ar(nb, 0.0012, 0.03, 4.0)
        place(out, norm_peak(b, -0.5 - 6.0 * r.random()), t)
        nt = N(0.02)
        place(out, norm_peak(bandpass(white(nt, 6110 + int(t * 100)) * env_ar(nt, 0.0002, 0.002, 7.0), 5200.0, 3.0, 1), -12.0), t)
        t += 0.03 + 0.14 * r.random()
    out = room(out, ROOM_LINO, wet=0.24)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


# ==========================================================================
# 小道具
# ==========================================================================
@reg("freezer_open")
def freezer_open():
    """パッキンが剥がれる「ヴシュッ」+ 蓋の軋み + 中の冷気。"""
    total = N(1.8)
    out = zeros(total)
    ng = N(0.32)
    gasket = band(white(ng, 6201), 120.0, 2600.0, order=2)
    gasket = svf_tv(gasket, glide(200.0, 900.0, ng, 0.6), 1.3, "bp") * 1.8
    gasket *= segments([(0.0, 0.0), (0.12, 1.0), (0.45, 0.6), (1.0, 0.0)], ng)
    place(out, norm_peak(gasket, -0.5), 0.0)
    nc = N(0.7)
    cr = creak(nc, 150.0, 260.0, 6202, rate=segments([(0, 18), (0.5, 30), (1, 12)], nc), q=26.0)
    cr *= segments([(0.0, 0.0), (0.15, 1.0), (1.0, 0.0)], nc)
    place(out, norm_peak(cr, -9.0), 0.16)
    nh = N(1.1)
    cold = highpass(white(nh, 6203), 2600.0, order=2) * segments([(0, 0.0), (0.2, 1.0), (1, 0.5)], nh) * 0.4
    cold += lowpass(white(nh, 6204), 200.0, order=2) * segments([(0, 0.0), (0.2, 1.0), (1, 0.6)], nh) * 0.6
    place(out, norm_peak(cold, -16.0), 0.25)
    out = room(out, ROOM_TIGHT, wet=0.22)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("freezer_close")
def freezer_close():
    total = N(1.3)
    out = zeros(total)
    ns = N(0.22)
    suck = band(white(ns, 6301), 150.0, 1800.0, order=2)
    suck = svf_tv(suck, glide(800.0, 220.0, ns, 0.8), 1.2, "bp") * 1.6
    suck *= segments([(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)], ns)
    place(out, norm_peak(suck, -5.0), 0.0)
    nb = N(0.6)
    thud = lowpass(white(nb, 6302) * env_ar(nb, 0.0008, 0.030, 4.5), 200.0, order=3) * 1.8
    thud += resonators(white(nb, 6303) * env_ar(nb, 0.0002, 0.004, 7.0), [84.0, 146.0, 250.0], [15, 12, 10], [1.0, 0.5, 0.25])
    thud += metal_hit(nb, 6304, base=640.0, decay=0.08, count=6) * 0.4
    place(out, norm_peak(thud, -0.5), 0.18)
    out = room(out, ROOM_TIGHT, wet=0.26)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("dry_ice_sizzle")
def dry_ice_sizzle():
    """昇華の「シュー」。細かい泡立ちと小さな弾け。"""
    n = N(2.4)
    fz = band(white(n, 6401), 700.0, 7000.0, order=2)
    fz = svf_tv(fz, segments([(0, 2200.0), (0.4, 3100.0), (1, 1800.0)], n), 0.8, "bp") * 1.7
    fz *= 0.55 + 0.45 * np.abs(smooth_noise(n, 45.0, 6402))
    fz *= segments([(0.0, 0.0), (0.05, 1.0), (0.65, 0.85), (1.0, 0.0)], n)
    out = fz
    r = rng(6403)
    for _ in range(40):
        nc = N(0.004)
        pos = r.random() * 0.9
        c = bandpass(white(nc, int(r.random() * 1e6)) * env_ar(nc, 0.0002, 0.0012, 7.0), 1200.0 + 4000.0 * r.random(), 3.0, 1)
        place(out, norm_peak(c, -9.0 - 10.0 * r.random()), pos * 2.4)
    out += lowpass(white(n, 6404), 300.0, order=2) * segments([(0, 0.0), (0.1, 1.0), (1, 0.0)], n) * 0.18
    out = room(out, ROOM_TIGHT, wet=0.18)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("water_pour")
def water_pour():
    """花器に水を注ぐ。溜まるにつれて共鳴が上がる。"""
    n = N(2.8)
    stream = band(white(n, 6501), 500.0, 6000.0, order=2)
    stream = svf_tv(stream, segments([(0, 1500.0), (0.5, 2100.0), (1, 2600.0)], n), 0.9, "bp") * 1.6
    stream *= 0.5 + 0.5 * np.abs(smooth_noise(n, 30.0, 6502))
    stream *= segments([(0.0, 0.0), (0.06, 1.0), (0.82, 0.9), (0.95, 0.15), (1.0, 0.0)], n)
    out = stream * 0.8
    r = rng(6503)
    for _ in range(70):
        u = r.random() * 0.9
        f0 = 500.0 + 900.0 * u + 500.0 * r.random()
        d = water_drop(int(r.random() * 1e6), f0, f0 * (2.2 + 0.8 * r.random()), 0.035 + 0.03 * r.random())
        place(out, norm_peak(d, -6.0 - 12.0 * r.random()), 0.05 + u * 2.5, 0.5)
    body = bandpass(out, 300.0, 1.2, 1) * 0.5
    out = out + body
    out = room(out, dict(dur=0.8, decay=0.24, damp_hz=5000.0, predelay=0.008, seed=113), wet=0.20)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("paper_rustle")
def paper_rustle():
    n = N(1.1)
    x = band(white(n, 6601), 1400.0, 11000.0, order=2)
    x *= grain_env(n, 90, 6602, dur_sec=0.006, jitter=0.9)
    x *= segments([(0.0, 0.2), (0.15, 1.0), (0.6, 0.8), (1.0, 0.0)], n)
    x += band(white(n, 6603), 500.0, 2500.0, order=2) * grain_env(n, 26, 6604, dur_sec=0.012) * 0.35
    x = room(x, ROOM_TIGHT, wet=0.14)
    return norm_peak(dc_kill(trim_tail(x, -66.0)), -0.5)


@reg("page_turn")
def page_turn():
    total = N(0.8)
    out = zeros(total)
    ns = N(0.42)
    sw = band(white(ns, 6701), 900.0, 9000.0, order=2)
    sw = svf_tv(sw, glide(2200.0, 5200.0, ns, 0.8), 0.9, "bp") * 1.5
    sw *= segments([(0.0, 0.0), (0.3, 0.6), (0.72, 1.0), (1.0, 0.0)], ns)
    place(out, norm_peak(sw, -4.0), 0.0)
    nf = N(0.12)
    flip = band(white(nf, 6702), 2000.0, 12000.0, order=2) * env_ar(nf, 0.0015, 0.012, 5.0)
    place(out, norm_peak(flip, -0.5), 0.30)
    nl = N(0.2)
    lay = band(white(nl, 6703), 300.0, 3000.0, order=2) * env_ar(nl, 0.004, 0.035, 4.0)
    place(out, norm_peak(lay, -10.0), 0.38)
    out = room(out, ROOM_TIGHT, wet=0.16)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("book_close")
def book_close():
    total = N(1.0)
    out = zeros(total)
    ns = N(0.22)
    wh = band(white(ns, 6801), 700.0, 7000.0, order=2) * segments([(0, 0.1), (0.7, 1.0), (1, 0.3)], ns)
    place(out, norm_peak(wh, -8.0), 0.0)
    nt = N(0.5)
    th = lowpass(white(nt, 6802) * env_ar(nt, 0.0008, 0.020, 5.0), 400.0, order=3) * 1.6
    th += resonators(white(nt, 6803) * env_ar(nt, 0.0003, 0.004, 7.0), [130.0, 240.0, 420.0], [14, 11, 9], [1.0, 0.5, 0.22])
    th += band(white(nt, 6804), 900.0, 6000.0, order=2) * env_ar(nt, 0.0006, 0.010, 6.0) * 0.5
    place(out, norm_peak(th, -0.5), 0.17)
    out = room(out, ROOM_TIGHT, wet=0.20)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("safe_dial")
def safe_dial():
    """ダイヤルを回す: 金属のクリックが並び、最後に止まる。"""
    total = N(2.0)
    out = zeros(total)
    r = rng(6901)
    nrot = N(1.5)
    rot = band(white(nrot, 6902), 300.0, 3500.0, order=2) * 0.10
    rot *= segments([(0.0, 0.0), (0.06, 1.0), (0.85, 0.7), (1.0, 0.0)], nrot)
    place(out, rot, 0.0)
    t = 0.03
    gap = 0.085
    while t < 1.45:
        nc = N(0.06)
        c = metal_hit(nc, int(r.random() * 1e6), base=2100.0 + 800.0 * r.random(), decay=0.008, count=4, bright=1.2)
        c *= env_ar(nc, 0.00008, 0.0035, 8.0)
        place(out, norm_peak(c, -1.0 - 4.0 * r.random()), t)
        t += gap * (0.85 + 0.3 * r.random())
        gap *= 1.09
    nk = N(0.35)
    stop = metal_hit(nk, 6903, base=900.0, decay=0.045, count=6) + wood_knock(nk, 6904, pitch=1.6, decay=0.4, thump=0.6) * 0.5
    place(out, norm_peak(stop, -3.0), 1.5)
    out = room(out, ROOM_TIGHT, wet=0.22)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("safe_open")
def safe_open():
    """かんぬきが引っ込む -> 重い扉が開く。"""
    total = N(2.6)
    out = zeros(total)
    r = rng(7001)
    for k, at in enumerate((0.0, 0.085, 0.155)):
        nb = N(0.3)
        b = metal_hit(nb, 7010 + k, base=380.0 + 180.0 * r.random(), decay=0.09, count=7, bright=0.9)
        b += lowpass(white(nb, 7020 + k) * env_ar(nb, 0.0006, 0.018, 5.0), 250.0, order=3) * 1.2
        place(out, norm_peak(b, -1.0 - 2.0 * k), at)
    nc = N(1.1)
    cr = creak(nc, 180.0, 340.0, 7002, rate=segments([(0, 22), (0.5, 40), (1, 16)], nc), q=38.0)
    cr *= segments([(0.0, 0.0), (0.12, 1.0), (0.7, 0.6), (1.0, 0.0)], nc)
    place(out, norm_peak(cr, -7.0), 0.30)
    nt = N(0.7)
    place(out, norm_peak(metal_hit(nt, 7003, base=210.0, decay=0.20, count=8), -10.0), 1.35)
    out = room(out, ROOM_TIGHT, wet=0.26)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("tv_on")
def tv_on():
    total = N(1.6)
    out = zeros(total)
    nd = N(0.35)
    deg = lowpass(white(nd, 7101) * env_ar(nd, 0.002, 0.05, 4.0), 160.0, order=3) * 1.5
    deg += sine(58.0, nd) * env_ar(nd, 0.004, 0.06, 4.0) * 0.8
    place(out, norm_peak(deg, -3.0), 0.0)
    nw = N(1.4)
    whine = sine(glide(9000.0, 15734.0, nw, 0.35), nw) * segments([(0.0, 0.0), (0.05, 1.0), (0.25, 0.55), (1.0, 0.42)], nw)
    whine += sine(glide(18000.0, 15734.0 * 2, nw, 0.35), nw) * 0.10 * segments([(0, 0.0), (0.08, 1.0), (1, 0.3)], nw)
    place(out, norm_peak(whine, -8.0), 0.02)
    nb = N(0.6)
    burst = highpass(white(nb, 7102), 800.0, order=2) * segments([(0.0, 0.0), (0.04, 1.0), (0.3, 0.5), (1.0, 0.45)], nb)
    place(out, norm_peak(burst, -6.0), 0.12)
    place(out, norm_peak(soft_click(7103, 1800.0, 3.0, 1.0, 0.06), -9.0), 0.0)
    out = room(out, ROOM_TATAMI, wet=0.14)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("tv_static", loop=True)
def tv_static():
    dur = 3.0
    n = N(dur)
    st = highpass(loop_noise(n, 0.2, 7201), 800.0, order=2, circular=True)
    st *= 0.8 + 0.2 * loop_smooth(n, 70.0, 7202, slope=0.3)
    st += 0.3 * highpass(loop_noise(n, 0.35, 7203), 5000.0, order=2, circular=True)
    st += 0.05 * sine(snap(60.0, dur), n) + 0.03 * sine(snap(15734.0, dur), n)
    st *= 1.0 + 0.2 * loop_smooth(n, 2.0, 7204)
    return dc_kill(st, circular=True)


@reg("tv_off")
def tv_off():
    total = N(1.2)
    out = zeros(total)
    nc = N(0.25)
    st = highpass(white(nc, 7301), 800.0, order=2) * segments([(0, 1.0), (0.25, 0.7), (1, 0.0)], nc)
    place(out, norm_peak(st, -6.0), 0.0)
    nw = N(0.5)
    fall = sine(glide(15734.0, 2500.0, nw, 1.8), nw) * env_ar(nw, 0.001, 0.09, 4.0)
    place(out, norm_peak(fall, -7.0), 0.02)
    nt = N(0.45)
    tink = partials(nt, [3400.0, 5200.0, 7100.0], [0.05, 0.035, 0.02], [1.0, 0.5, 0.25], seed=7302)
    tink += lowpass(white(nt, 7303) * env_ar(nt, 0.001, 0.02, 5.0), 200.0, order=3) * 1.0
    place(out, norm_peak(tink, -0.5), 0.04)
    place(out, norm_peak(soft_click(7304, 1500.0, 3.0, 1.0, 0.06), -8.0), 0.0)
    out = room(out, ROOM_TATAMI, wet=0.14)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("chair_drag")
def chair_drag():
    """パイプ椅子をリノリウムの上で引きずる。"""
    total = N(1.4)
    out = zeros(total)
    ns = N(1.0)
    rate = segments([(0, 55.0), (0.25, 78.0), (0.7, 64.0), (1, 38.0)], ns)
    sc = scrape(ns, 7401, 220.0, 4500.0, rate, rough=0.9, jitter=0.35, sharp=45.0)
    sc *= segments([(0.0, 0.0), (0.05, 1.0), (0.75, 0.9), (1.0, 0.1)], ns)
    # パイプの共鳴
    sc = sc + 0.6 * resonators(sc, [420.0, 980.0, 1640.0], [9, 11, 8], [1.0, 0.6, 0.3])
    place(out, norm_peak(sc, -0.5), 0.0)
    nr = N(0.4)
    rat = metal_hit(nr, 7402, base=1250.0, decay=0.05, count=6, bright=1.1)
    place(out, norm_peak(rat, -8.0), 0.97)
    out = room(out, dict(dur=1.0, decay=0.30, damp_hz=3200.0, predelay=0.016, seed=114), wet=0.26)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("tatami_creak")
def tatami_creak():
    n = N(1.0)
    cr = creak(n, 62.0, 104.0, 7501, rate=segments([(0, 14), (0.4, 24), (1, 9)], n), ratios=(1.0, 2.1, 3.3, 5.0), q=24.0, sharp=50.0)
    cr *= segments([(0.0, 0.0), (0.12, 1.0), (0.55, 0.7), (1.0, 0.0)], n)
    straw = band(white(n, 7502), 1200.0, 4500.0, order=2) * grain_env(n, 22, 7503, dur_sec=0.008) * 0.12
    x = cr + straw
    x = lowpass(x, 3000.0, order=2)
    x = room(x, ROOM_TATAMI, wet=0.16)
    return norm_peak(dc_kill(trim_tail(x, -66.0)), -0.5)


# ==========================================================================
# 怪異
# ==========================================================================
VOWELS = [
    (800.0, 1200.0, 2800.0),   # a
    (300.0, 2300.0, 3000.0),   # i
    (350.0, 1250.0, 2200.0),   # u
    (500.0, 1900.0, 2600.0),   # e
    (500.0, 850.0, 2700.0),    # o
]


def _moving_comb(x, seed, d1=0.0021, d2=0.0058, rate=0.7, depth=0.4):
    """ゆっくり動くコム。mono でも「左右に揺れる」ような不安定さが出る。"""
    n = len(x)
    n1, n2 = N(d1), N(d2)
    a = zeros(n)
    b = zeros(n)
    a[n1:] = x[: n - n1]
    b[n2:] = x[: n - n2]
    w = 0.5 + 0.5 * lfo(n, rate, 1.0, 0.0, rng(seed).random() * TWO_PI)
    return x + depth * (a * w + b * (1.0 - w))


def _whisper(seed, n_syl, dur, tilt=1.0):
    n = N(dur)
    out = zeros(n)
    r = rng(seed)
    t = 0.05
    for i in range(n_syl):
        d = 0.085 + 0.085 * r.random()
        ns = N(d)
        if N(t) + ns >= n:
            break
        v = VOWELS[int(r.random() * len(VOWELS)) % len(VOWELS)]
        src = white(ns, seed + i * 7 + 1)
        f1 = segments([(0, v[0] * 0.78), (0.35, v[0]), (1, v[0] * 0.88)], ns)
        f2 = segments([(0, v[1] * 0.86), (0.35, v[1]), (1, v[1] * 0.96)], ns)
        # 囁きは声帯を使わないので F1 は弱く、擦過音の帯域が主役になる
        y = 0.45 * svf_tv(src, f1, 7.0, "bp")
        y += 0.95 * svf_tv(src, f2, 9.0, "bp")
        y += 0.70 * bandpass(src, v[2], 8.0, 1)
        y += 0.55 * bandpass(src, 4400.0, 3.0, 1)
        y += 0.30 * bandpass(src, 6600.0, 3.0, 1)
        y *= segments([(0.0, 0.0), (0.16, 1.0), (0.68, 0.8), (1.0, 0.0)], ns)
        # 子音 (s / k / t のような立ち上がり)
        nc = N(0.028)
        cons = bandpass(white(nc, seed + 300 + i), 3200.0 + 3500.0 * r.random(), 2.2, 1)
        cons *= env_ar(nc, 0.002, 0.012, 4.0)
        place(out, norm_peak(cons, -8.0 - 6.0 * r.random()), t - 0.018 if t > 0.02 else 0.0)
        place(out, norm_peak(y, -1.0 - 4.0 * r.random()), t)
        t += d * (1.45 + 0.75 * r.random()) + 0.02
    out *= 0.65 + 0.35 * (0.5 + 0.5 * smooth_noise(n, 3.2, seed + 91))
    out = _moving_comb(out, seed + 5, rate=0.55 + 0.4 * r.random(), depth=0.42)
    out = band(out, 420.0, 9500.0 * tilt, order=2)
    out = filt(out, "highshelf", 2600.0, 0.7, 5.0)
    out = room(out, dict(dur=1.1, decay=0.30, damp_hz=3200.0, predelay=0.016, seed=112), wet=0.26)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


reg("whisper_1")(lambda: _whisper(8001, 6, 2.1, 1.0))
reg("whisper_2")(lambda: _whisper(8021, 4, 1.5, 0.85))
reg("whisper_3")(lambda: _whisper(8041, 8, 2.8, 1.15))


@reg("breath_close")
def breath_close():
    """耳元の息。近接効果で低域が持ち上がる。"""
    n = N(2.2)
    out = zeros(n)
    nl = N(0.03)
    place(out, norm_peak(bandpass(white(nl, 8101) * env_ar(nl, 0.001, 0.006, 6.0), 900.0, 2.0, 1), -14.0), 0.0)
    nb = N(1.6)
    b = band(white(nb, 8102), 120.0, 5000.0, order=2)
    b = svf_tv(b, segments([(0, 380.0), (0.35, 780.0), (0.8, 520.0), (1, 320.0)], nb), 0.85, "bp") * 2.0
    b += lowpass(white(nb, 8103), 300.0, order=2) * 0.9
    b += band(white(nb, 8104), 3000.0, 8000.0, order=2) * 0.18
    b *= segments([(0.0, 0.0), (0.16, 1.0), (0.55, 0.85), (1.0, 0.0)], nb)
    b *= 0.75 + 0.25 * smooth_noise(nb, 12.0, 8105)
    place(out, norm_peak(b, -0.5), 0.05)
    out = peaking(out, 160.0, 0.9, 5.0)
    out = _moving_comb(out, 8106, rate=0.4, depth=0.20)
    out = room(out, ROOM_TIGHT, wet=0.10)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("heartbeat", loop=True)
def heartbeat():
    """2 拍、1 秒ループ。"""
    dur = 1.0
    n = N(dur)
    out = zeros(n)

    def beat(seed, f, dcy, level, punch):
        nb = N(0.34)
        x = sine(glide(f * 1.7, f, nb, 1.4), nb) * env_ar(nb, 0.006, dcy, 4.0)
        x += sine(glide(f * 0.9, f * 0.6, nb, 1.4), nb) * env_ar(nb, 0.010, dcy * 1.4, 4.0) * 0.7
        x += lowpass(white(nb, seed) * env_ar(nb, 0.003, 0.030, 5.0), 260.0, order=3) * punch
        x = lowpass(x, 420.0, order=2)
        return norm_peak(x, -0.5) * level

    place(out, beat(8201, 58.0, 0.075, 1.0, 1.0), 0.06)
    place(out, beat(8202, 50.0, 0.095, 0.62, 0.7), 0.37)
    return fade(dc_kill(out), 0.001, 0.02)


def _stinger_metal(n, seed, base, count, decay, bright):
    r = rng(seed)
    ratios = [1.0, 1.06, 1.49, 2.11, 2.67, 3.41, 4.09, 5.33, 6.71, 8.12][:count]
    freqs = [base * x * (1.0 + (r.random() - 0.5) * 0.05) for x in ratios]
    decays = [decay * (0.88 ** i) * (0.6 + 0.8 * r.random()) for i in range(count)]
    amps = [(1.0 / (1.0 + 0.55 * i)) * (0.5 + 0.9 * r.random()) * bright for i in range(count)]
    return partials(n, freqs, decays, amps, seed=seed + 3, detune=0.006)


@reg("stinger_1")
def stinger_1():
    """金属の不協和クラスタ + ノイズの急な立ち上がり。鋭く、乾いている。"""
    n = N(1.0)
    hit = _stinger_metal(n, 8301, 620.0, 9, 0.22, 1.0)
    hit += _stinger_metal(n, 8302, 1870.0, 7, 0.10, 0.6)
    slam = highpass(white(n, 8303), 500.0, order=2) * env_ar(n, 0.0005, 0.025, 5.0) * 1.4
    sub = sine(glide(150.0, 42.0, n, 2.2), n) * env_ar(n, 0.002, 0.10, 4.0) * 1.1
    x = hit * 1.0 + slam + sub
    x = softclip(x * 1.4, 2.0)
    x = room(x, dict(dur=0.5, decay=0.18, damp_hz=3200.0, predelay=0.014, seed=110), wet=0.30)
    return norm_peak(dc_kill(trim_tail(x, -54.0)), -0.5)


@reg("stinger_2")
def stinger_2():
    """吸い込むような盛り上がりから叩きつける。長め。"""
    total = N(1.25)
    out = zeros(total)
    nr = N(0.32)
    rise = band(white(nr, 8401), 400.0, 9000.0, order=2)
    rise = svf_tv(rise, glide(600.0, 5200.0, nr, 1.6), 1.4, "bp") * 1.6
    rise *= segments([(0.0, 0.0), (0.6, 0.35), (1.0, 1.0)], nr) ** 1.5
    rise += sine(glide(180.0, 900.0, nr, 2.0), nr) * segments([(0, 0.0), (1, 0.6)], nr)
    place(out, norm_peak(rise, -6.0), 0.0)
    nh = N(0.9)
    hit = _stinger_metal(nh, 8402, 470.0, 10, 0.22, 1.0)
    hit += highpass(white(nh, 8403), 300.0, order=2) * env_ar(nh, 0.0004, 0.04, 5.0) * 1.6
    drop = sine(glide(90.0, 34.0, nh, 2.4), nh) * env_ar(nh, 0.003, 0.16, 3.5) * 1.5
    scr = scrape(nh, 8404, 1800.0, 7000.0, segments([(0, 200.0), (1, 60.0)], nh), rough=0.9)
    scr *= env_ar(nh, 0.002, 0.12, 4.0) * 0.5
    place(out, norm_peak(softclip((hit + drop + scr) * 1.3, 2.2), -0.5), 0.32)
    out = room(out, dict(dur=0.45, decay=0.15, damp_hz=3600.0, predelay=0.012, seed=111), wet=0.28)
    return norm_peak(dc_kill(trim_tail(out, -54.0)), -0.5)


@reg("stinger_3")
def stinger_3():
    """短く、歪んだ悲鳴のような一撃。0.8 秒。"""
    n = N(0.95)
    scream = _stinger_metal(n, 8501, 1450.0, 8, 0.12, 1.0)
    scream += _stinger_metal(n, 8502, 2980.0, 6, 0.07, 0.8)
    nz = band(white(n, 8503), 1800.0, 9000.0, order=2) * env_ar(n, 0.0004, 0.022, 6.0) * 1.5
    body = sine(glide(220.0, 70.0, n, 2.6), n) * env_ar(n, 0.001, 0.07, 5.0) * 1.0
    x = softclip((scream + nz + body) * 2.0, 3.2)
    x = peaking(x, 3200.0, 1.2, 5.0)
    x = room(x, ROOM_TIGHT, wet=0.20)
    return norm_peak(dc_kill(trim_tail(x, -54.0)), -0.5)


# ==========================================================================
# 火車
# ==========================================================================
@reg("kasha_screech")
def kasha_screech():
    """猫の悲鳴を歪ませて引き伸ばした、耳に痛い音。"""
    n = N(2.8)
    f0 = segments([(0.0, 620.0), (0.15, 1150.0), (0.45, 1320.0), (0.72, 980.0), (1.0, 560.0)], n)
    src = voice_src(n, f0, 8601, jitter=0.05, width=0.07, breath=0.25, rough=0.45)
    v = 1.0 * svf_tv(src, segments([(0, 900.0), (0.4, 1500.0), (1, 800.0)], n), 5.0, "bp")
    v += 0.8 * svf_tv(src, segments([(0, 2600.0), (0.4, 3900.0), (1, 2400.0)], n), 6.0, "bp")
    v += 0.45 * bandpass(src, 5200.0, 6.0, 1)
    v = ring_mod(v, 43.0, 0.30)
    v = softclip(v * 3.0, 4.0)
    v += 0.30 * band(white(n, 8602), 2500.0, 10000.0, order=2) * segments([(0, 0.2), (0.4, 1.0), (1, 0.1)], n)
    v *= segments([(0.0, 0.0), (0.05, 1.0), (0.75, 0.9), (1.0, 0.0)], n)
    v = peaking(v, 3400.0, 1.1, 6.0)
    v = _moving_comb(v, 8603, rate=1.3, depth=0.25)
    v = room(v, ROOM_HALL, wet=0.32)
    return norm_peak(dc_kill(trim_tail(v, -66.0)), -0.5)


@reg("kasha_crawl")
def kasha_crawl():
    """天井/壁を這う爪の連続。こもり気味で、近づいたり遠ざかったりする。"""
    n = N(3.0)
    out = zeros(n)
    r = rng(8701)
    t = 0.02
    while t < 2.75:
        d = 0.05 + 0.08 * r.random()
        ns = N(d)
        sc = band(white(ns, int(r.random() * 1e6)), 900.0, 6500.0, order=2)
        sc *= grain_env(ns, 22, int(r.random() * 1e6), dur_sec=0.0016, jitter=0.9)
        sc *= segments([(0, 0.25), (0.2, 1.0), (1, 0.0)], ns)
        exc = white(ns, int(r.random() * 1e6)) * env_ar(ns, 0.0002, 0.002, 7.0)
        body = resonators(exc, [150.0, 268.0, 470.0], [20, 16, 12], [1.0, 0.5, 0.22])
        place(out, norm_peak(sc + 0.7 * body, -1.0 - 6.0 * r.random()), t)
        t += d * (0.5 + 0.7 * r.random())
    drag = lowpass(white(n, 8702), 260.0, order=3) * (0.2 + 0.8 * np.abs(smooth_noise(n, 3.5, 8703))) * 0.5
    out = out + drag
    out *= 0.45 + 0.55 * (0.5 + 0.5 * smooth_noise(n, 0.7, 8704))
    out = lowpass(out, 3200.0, order=2)
    out = room(out, ROOM_TIGHT, wet=0.25)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("kasha_growl")
def kasha_growl():
    n = N(3.0)
    f0 = segments([(0.0, 52.0), (0.3, 44.0), (0.65, 58.0), (1.0, 40.0)], n)
    src = voice_src(n, f0, 8801, jitter=0.08, width=0.15, breath=0.20, rough=0.55)
    v = formant(src, [(210.0, 4.0, 0.0), (520.0, 5.0, -5.0), (1150.0, 6.0, -12.0), (2200.0, 7.0, -20.0)])
    v = v * (0.55 + 0.45 * np.abs(smooth_noise(n, 9.0, 8802)))
    v = softclip(v * 2.4, 2.6)
    v += 0.10 * lowpass(white(n, 8803), 400.0, order=2)
    v *= segments([(0.0, 0.0), (0.08, 1.0), (0.8, 0.9), (1.0, 0.0)], n)
    v = peaking(v, 90.0, 0.8, 5.0)
    v = room(v, ROOM_HALL, wet=0.26)
    return norm_peak(dc_kill(trim_tail(v, -66.0)), -0.5)


@reg("body_rise")
def body_rise():
    """布と木の擦れ + 湿った音。ゆっくり起き上がる。"""
    n = N(3.0)
    cloth = band(white(n, 8901), 500.0, 5000.0, order=2)
    cloth *= grain_env(n, 70, 8902, dur_sec=0.02, jitter=0.9)
    cloth *= segments([(0.0, 0.0), (0.2, 0.6), (0.6, 1.0), (1.0, 0.25)], n)
    wood = creak(n, 78.0, 128.0, 8903, rate=segments([(0, 8.0), (0.5, 18.0), (1, 6.0)], n), q=28.0, sharp=45.0)
    wood *= segments([(0.0, 0.0), (0.25, 0.8), (0.7, 1.0), (1.0, 0.0)], n)
    r = rng(8904)
    wet = zeros(n)
    for _ in range(16):
        nc = N(0.05 + 0.05 * r.random())
        pos = 0.3 + r.random() * 2.4
        g = svf_tv(white(nc, int(r.random() * 1e6)), glide(300.0 + 500.0 * r.random(), 150.0, nc, 1.2), 4.0, "bp")
        g *= env_ar(nc, 0.003, 0.02, 4.0)
        place(wet, norm_peak(g, -4.0 - 9.0 * r.random()), pos)
    x = 0.75 * cloth + 0.9 * wood + 0.6 * wet
    x = lowpass(x, 6000.0, order=1)
    x = room(x, ROOM_HALL, wet=0.30)
    return norm_peak(dc_kill(trim_tail(x, -66.0)), -0.5)


# ==========================================================================
# 朝 / UI / VHS
# ==========================================================================
@reg("crow_morning")
def crow_morning():
    """鴉 2 声。遠い。"""
    total = N(2.4)
    out = zeros(total)
    for at, base, d, g in ((0.03, 430.0, 0.36, 1.0), (0.62, 395.0, 0.42, 0.78)):
        nb = N(d)
        f0 = segments([(0.0, base * 1.12), (0.2, base), (1.0, base * 0.84)], nb)
        src = voice_src(nb, f0, int(base * 10), jitter=0.035, width=0.09, breath=0.18, rough=0.55)
        v = formant(src, [(1150.0, 4.5, 0.0), (2350.0, 5.5, -4.0), (3600.0, 6.0, -12.0), (620.0, 4.0, -6.0)])
        v = v * (0.6 + 0.4 * (0.5 + 0.5 * sine(88.0, nb)))
        v = softclip(v * 1.8, 2.2)
        v *= segments([(0.0, 0.0), (0.06, 1.0), (0.55, 0.85), (1.0, 0.0)], nb)
        v = room(v, ROOM_OUT, wet=0.55)
        place(out, norm_peak(v, -0.5), at, g)
    out = lowpass(out, 6500.0, order=1)
    return norm_peak(dc_kill(trim_tail(out, -66.0)), -0.5)


@reg("chime_dawn")
def chime_dawn():
    """遠くの寺の鐘 1 打。長い減衰と唸り。"""
    n = N(9.0)
    f = [63.0, 126.0, 172.0, 214.0, 286.0, 349.0, 432.0, 546.0, 690.0, 861.0]
    dec = [4.6, 4.0, 3.0, 2.4, 1.8, 1.4, 1.05, 0.8, 0.55, 0.36]
    amp = [0.85, 1.0, 0.62, 0.48, 0.34, 0.26, 0.18, 0.12, 0.08, 0.05]
    # 位相を揃える: 撞いた瞬間が最大になり、そのあと唸りながら減衰する
    bell = partials(n, f, dec, amp, seed=9001, detune=0.0016, phase_rand=False)
    strike = white(n, 9002) * env_ar(n, 0.0008, 0.010, 6.0)
    strike = resonators(strike, [214.0, 432.0, 861.0, 1720.0], [18, 15, 12, 9], [1.0, 0.6, 0.3, 0.12]) * 0.55
    wood = lowpass(white(n, 9003) * env_ar(n, 0.002, 0.030, 5.0), 700.0, order=2) * 0.30
    x = bell + strike + wood
    x = lowpass(x, 2400.0, order=2)          # 遠いのでこもる
    x = highpass(x, 45.0, order=1)
    x = room(x, dict(dur=3.0, decay=1.1, damp_hz=1600.0, predelay=0.055, seed=109), wet=0.45)
    return norm_peak(dc_kill(trim_tail(x, -70.0)), -0.5)


reg("ui_select")(lambda: norm_peak(room(soft_click(9101, 2800.0, 3.5, 0.5, 0.045), ROOM_TIGHT, wet=0.10), -0.5))


@reg("ui_confirm")
def ui_confirm():
    total = N(0.35)
    out = zeros(total)
    place(out, norm_peak(soft_click(9201, 2400.0, 3.0, 0.7, 0.05), -0.5), 0.0)
    nt = N(0.16)
    tone = partials(nt, [880.0, 1760.0], [0.035, 0.020], [1.0, 0.35], seed=9202)
    place(out, norm_peak(tone, -7.0), 0.012)
    out = room(out, ROOM_TIGHT, wet=0.10)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("ui_back")
def ui_back():
    total = N(0.3)
    out = zeros(total)
    place(out, norm_peak(soft_click(9301, 1500.0, 3.0, 1.0, 0.05), -0.5), 0.0)
    nt = N(0.13)
    tone = partials(nt, [520.0, 1040.0], [0.030, 0.016], [1.0, 0.3], seed=9302)
    place(out, norm_peak(tone, -9.0), 0.010)
    out = lowpass(out, 5000.0, order=1)
    out = room(out, ROOM_TIGHT, wet=0.10)
    return norm_peak(trim_tail(out, -66.0), -0.5)


@reg("vhs_tracking")
def vhs_tracking():
    """テープのトラッキングノイズ 1 秒。"""
    n = N(1.0)
    base = highpass(white(n, 9401), 600.0, order=2)
    sweep = svf_tv(base, segments([(0, 5200.0), (0.3, 1400.0), (0.6, 6800.0), (1, 2200.0)], n), 1.6, "bp") * 1.8
    head = softclip(harm(59.94, n, square_amps(15, 1.1)), 6.0)
    head = bandpass(head, 1800.0, 1.2, 1) * 0.35
    burst = zeros(n)
    r = rng(9402)
    t = 0.0
    while t < 0.95:
        nb = N(0.008 + 0.05 * r.random())
        b = highpass(white(nb, int(r.random() * 1e6)), 900.0, order=2) * env_ar(nb, 0.0008, 0.02, 4.0)
        place(burst, norm_peak(b, -1.0 - 8.0 * r.random()), t)
        t += 0.02 + 0.13 * r.random()
    drop = 1.0 - 0.85 * grain_env(n, 5, 9403, dur_sec=0.03)
    x = (0.9 * sweep + head + 0.8 * burst) * drop
    x = bitcrush(x, 7, 2)
    x = band(x, 300.0, 9000.0, order=2)
    x *= segments([(0.0, 0.0), (0.03, 1.0), (0.85, 0.9), (1.0, 0.0)], n)
    return norm_peak(dc_kill(x), -0.5)
