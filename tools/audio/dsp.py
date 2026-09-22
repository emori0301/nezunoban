"""寝ずの番 | The Wake — 音合成のための DSP プリミティブ群.

Blender 同梱 python (numpy あり) で動かす前提。scipy は使わない。
すべて mono / 44.1kHz / float64 の 1 次元 ndarray で扱い、最後に 16bit PCM で書く。
"""

import math
import os
import struct
import zlib

import numpy as np

SR = 44100
TWO_PI = 2.0 * math.pi


# --------------------------------------------------------------------------
# 基本ユーティリティ
# --------------------------------------------------------------------------
def N(sec):
    """秒 -> サンプル数"""
    return int(round(float(sec) * SR))


def secs(n):
    return float(n) / SR


def rng(seed):
    return np.random.default_rng(int(seed) & 0x7FFFFFFF)


def db2lin(d):
    return 10.0 ** (float(d) / 20.0)


def lin2db(v):
    return 20.0 * math.log10(max(float(v), 1e-12))


def as_array(v, n):
    """スカラ or 配列を長さ n の配列にする。配列長が違えば線形補間で伸縮。"""
    if np.isscalar(v):
        return np.full(n, float(v))
    a = np.asarray(v, dtype=np.float64)
    if a.size == n:
        return a
    if a.size == 1:
        return np.full(n, float(a[0]))
    return np.interp(np.linspace(0.0, 1.0, n), np.linspace(0.0, 1.0, a.size), a)


def zeros(n):
    return np.zeros(int(n), dtype=np.float64)


def pad_to(x, n):
    n = int(n)
    if len(x) >= n:
        return x[:n].copy()
    out = zeros(n)
    out[: len(x)] = x
    return out


def mix(*layers):
    """長さの違う信号を 0 詰めして加算。"""
    layers = [np.asarray(l, dtype=np.float64) for l in layers if l is not None and len(l)]
    if not layers:
        return zeros(1)
    n = max(len(l) for l in layers)
    out = zeros(n)
    for l in layers:
        out[: len(l)] += l
    return out


def place(base, x, at_sec, gain=1.0):
    """base の at_sec の位置に x を加算 (はみ出しは切る)。破壊的。"""
    i = N(at_sec)
    if i >= len(base):
        return base
    j = min(len(base), i + len(x))
    base[i:j] += gain * x[: j - i]
    return base


def snap(freq, loop_sec):
    """loop_sec の中で整数周期になるように周波数を丸める (ループの継ぎ目対策)。"""
    k = max(1.0, round(float(freq) * float(loop_sec)))
    return k / float(loop_sec)


# --------------------------------------------------------------------------
# 発振器
# --------------------------------------------------------------------------
def phase(freq, n, phase0=0.0):
    f = as_array(freq, n)
    return phase0 + TWO_PI * np.cumsum(f) / SR


def sine(freq, n, phase0=0.0):
    return np.sin(phase(freq, n, phase0))


def harm(freq, n, amps, phase0=0.0, phases=None, stretch=1.0):
    """倍音加算。amps[i] が第 (i+1) 倍音の振幅。stretch で非整数倍音 (金属的) にできる。"""
    ph = phase(freq, n, phase0)
    out = zeros(n)
    for i, a in enumerate(amps):
        if a == 0.0:
            continue
        k = (i + 1) ** stretch if stretch != 1.0 else (i + 1)
        p0 = 0.0 if phases is None else phases[i]
        out += a * np.sin(k * ph + p0)
    return out


def saw_amps(k, rolloff=1.0):
    return [((-1.0) ** (i)) / ((i + 1) ** rolloff) for i in range(k)]


def square_amps(k, rolloff=1.0):
    return [0.0 if (i + 1) % 2 == 0 else 1.0 / ((i + 1) ** rolloff) for i in range(k)]


def pulse_train(freq, n, width=0.06, phase0=0.0):
    """帯域がそこそこ抑えられたパルス列 (声門音源やパーの元)。width は周期に対する比。"""
    p = (phase(freq, n, phase0) / TWO_PI) % 1.0
    w = max(1e-4, float(width))
    out = zeros(n)
    m = p < w
    out[m] = 0.5 * (1.0 + np.cos(math.pi * p[m] / w))
    return out - out.mean()


def glide(f0, f1, n, curve=1.0):
    """f0 -> f1 のピッチグライド。curve>1 で最初が速い。"""
    u = np.linspace(0.0, 1.0, n)
    u = u ** float(curve)
    return f0 * (float(f1) / float(f0)) ** u


def segments(points, n):
    """[(位置0..1, 値), ...] を線形補間して長さ n の配列にする。"""
    xs = np.array([p[0] for p in points], dtype=np.float64)
    ys = np.array([p[1] for p in points], dtype=np.float64)
    return np.interp(np.linspace(0.0, 1.0, n), xs, ys)


# --------------------------------------------------------------------------
# ノイズ
# --------------------------------------------------------------------------
def white(n, seed=0):
    return rng(seed).standard_normal(int(n))


def _spectral_noise(n, slope, seed):
    """1/f^(slope/2) で整形したノイズ。slope=0 白, 1 ピンク, 2 ブラウン。"""
    n = int(n)
    nf = 1 << int(math.ceil(math.log2(max(2, n))))
    r = rng(seed)
    spec = r.standard_normal(nf // 2 + 1) + 1j * r.standard_normal(nf // 2 + 1)
    f = np.arange(nf // 2 + 1, dtype=np.float64)
    f[0] = 1.0
    spec *= f ** (-slope / 2.0)
    spec[0] = 0.0
    x = np.fft.irfft(spec, nf)[:n]
    p = np.max(np.abs(x))
    return x / p if p > 0 else x


def pink(n, seed=0):
    return _spectral_noise(n, 1.0, seed)


def brown(n, seed=0):
    return _spectral_noise(n, 2.0, seed)


def smooth_noise(n, cutoff_hz, seed=0):
    """ゆっくり揺れるランダム値 (LFO 代わり)。-1..1 程度。"""
    x = white(n, seed)
    x = lowpass(x, cutoff_hz, q=0.7, order=2)
    p = np.max(np.abs(x))
    return x / p if p > 0 else x


def loop_noise(n, slope, seed=0):
    """長さ n で完全に周期的なノイズ (FFT 合成なので端が繋がる)。環境ループ用。"""
    n = int(n)
    r = rng(seed)
    half = n // 2 + 1
    spec = r.standard_normal(half) + 1j * r.standard_normal(half)
    f = np.arange(half, dtype=np.float64)
    f[0] = 1.0
    spec *= f ** (-slope / 2.0)
    spec[0] = 0.0
    if n % 2 == 0:
        spec[-1] = spec[-1].real
    x = np.fft.irfft(spec, n)
    p = np.max(np.abs(x))
    return x / p if p > 0 else x


# --------------------------------------------------------------------------
# フィルタ (RBJ biquad を IR に落として FFT 畳み込み)
# --------------------------------------------------------------------------
def biquad(kind, fc, q=0.70710678, gain_db=0.0, sr=SR):
    """RBJ Audio EQ Cookbook。(b, a) を返す。"""
    fc = float(np.clip(fc, 1.0, sr * 0.49))
    q = max(1e-3, float(q))
    w0 = TWO_PI * fc / sr
    cw = math.cos(w0)
    sw = math.sin(w0)
    alpha = sw / (2.0 * q)
    A = 10.0 ** (gain_db / 40.0)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":  # 定ピーク (ピーク 0dB)
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "notch":
        b = [1.0, -2 * cw, 1.0]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "ap":
        b = [1 - alpha, -2 * cw, 1 + alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        s = 2.0 * math.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + s), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - s)]
        a = [(A + 1) + (A - 1) * cw + s, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - s]
    elif kind == "highshelf":
        s = 2.0 * math.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + s), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - s)]
        a = [(A + 1) - (A - 1) * cw + s, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - s]
    else:
        raise ValueError("unknown biquad kind: %s" % kind)
    b = np.array(b, dtype=np.float64) / a[0]
    a = np.array([1.0, a[1] / a[0], a[2] / a[0]], dtype=np.float64)
    return b, a


def _run_biquad(x, b, a):
    """時間領域の差分方程式 (短い信号 / IR 生成用)。"""
    y = np.empty(len(x), dtype=np.float64)
    b0, b1, b2 = b[0], b[1], b[2]
    a1, a2 = a[1], a[2]
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = xi
        y2 = y1
        y1 = yi
        y[i] = yi
    return y


_IR_CACHE = {}


def biquad_ir(kind, fc, q=0.70710678, gain_db=0.0):
    """biquad のインパルス応答 (減衰時間から長さを自動決定、末尾は窓で落とす)。"""
    key = (kind, round(float(fc), 4), round(float(q), 4), round(float(gain_db), 3))
    got = _IR_CACHE.get(key)
    if got is not None:
        return got
    fcl = float(np.clip(fc, 1.0, SR * 0.49))
    tau = max(q, 0.5) / (math.pi * max(fcl, 20.0))
    n = int(np.clip(12.0 * tau * SR, 512, 1 << 16))
    n = 1 << int(math.ceil(math.log2(n)))
    imp = zeros(n)
    imp[0] = 1.0
    b, a = biquad(kind, fcl, q, gain_db)
    ir = _run_biquad(imp, b, a)
    tail = n // 4
    w = 0.5 * (1.0 + np.cos(np.linspace(0.0, math.pi, tail)))
    ir[-tail:] *= w
    _IR_CACHE[key] = ir
    return ir


def _wrap_ir(ir, n):
    """円状畳み込み用に IR を周期 n で折り返す (n より長い IR でも厳密)。"""
    if len(ir) <= n:
        return pad_to(ir, n)
    h = np.array(ir[:n], dtype=np.float64)
    for k in range(n, len(ir), n):
        seg = ir[k : k + n]
        h[: len(seg)] += seg
    return h


def loop_smooth(n, cutoff_hz, seed=0, slope=1.0):
    """周期 n で厳密に繰り返す、ゆっくりしたランダム変調 (-1..1)。環境ループの揺れ用。"""
    n = int(n)
    r = rng(seed)
    half = n // 2 + 1
    dur = n / float(SR)
    kmax = max(1, min(half - 1, int(round(float(cutoff_hz) * dur))))
    spec = np.zeros(half, dtype=np.complex128)
    k = np.arange(1, kmax + 1, dtype=np.float64)
    spec[1 : kmax + 1] = (k ** (-slope * 0.5)) * np.exp(1j * r.random(kmax) * TWO_PI)
    x = np.fft.irfft(spec, n)
    p = float(np.max(np.abs(x)))
    return x / p if p > 0 else x


def fftconv(x, h):
    """線形畳み込み (末尾は残す)。"""
    nx, nh = len(x), len(h)
    n = nx + nh - 1
    nf = 1 << int(math.ceil(math.log2(max(2, n))))
    y = np.fft.irfft(np.fft.rfft(x, nf) * np.fft.rfft(h, nf), nf)[:n]
    return y


def filt(x, kind, fc, q=0.70710678, gain_db=0.0, order=1, circular=False):
    """biquad を order 段。circular=True は円状畳み込み (ループ素材の周期性を壊さない)。"""
    ir = biquad_ir(kind, fc, q, gain_db)
    y = np.asarray(x, dtype=np.float64)
    for _ in range(int(order)):
        if circular:
            n = len(y)
            h = _wrap_ir(ir, n)
            y = np.fft.irfft(np.fft.rfft(y, n) * np.fft.rfft(h, n), n)
        else:
            y = fftconv(y, ir)[: len(x)]
    return y


def lowpass(x, fc, q=0.70710678, order=1, circular=False):
    return filt(x, "lp", fc, q, 0.0, order, circular)


def highpass(x, fc, q=0.70710678, order=1, circular=False):
    return filt(x, "hp", fc, q, 0.0, order, circular)


def bandpass(x, fc, q=2.0, order=1, circular=False):
    return filt(x, "bp", fc, q, 0.0, order, circular)


def peaking(x, fc, q=1.0, gain_db=6.0, circular=False):
    return filt(x, "peak", fc, q, gain_db, 1, circular)


def band(x, lo, hi, order=2, circular=False):
    """lo..hi の帯域に絞る (電話の 300-3400Hz など)。"""
    y = highpass(x, lo, 0.707, order, circular)
    y = lowpass(y, hi, 0.707, order, circular)
    return y


def resonators(x, freqs, qs, gains=None, circular=False):
    """複数の共鳴 (bandpass) を並列に足す。金属/木の胴鳴り用。"""
    gains = gains if gains is not None else [1.0] * len(freqs)
    out = zeros(len(x))
    for f, q, g in zip(freqs, qs, gains):
        out += g * bandpass(x, f, q, 1, circular)
    return out


def svf_tv(x, fc, q=1.0, mode="bp"):
    """時変フィルタ (TPT state variable)。fc/q は配列可。python ループなので短い音に使う。"""
    n = len(x)
    fca = np.clip(as_array(fc, n), 20.0, SR * 0.45)
    qa = np.clip(as_array(q, n), 0.05, 60.0)
    g = np.tan(math.pi * fca / SR)
    k = 1.0 / qa
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    out = np.empty(n, dtype=np.float64)
    ic1 = 0.0
    ic2 = 0.0
    if mode == "lp":
        sel = 0
    elif mode == "bp":
        sel = 1
    else:
        sel = 2
    for i in range(n):
        v0 = x[i]
        v3 = v0 - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v2 if sel == 0 else (v1 if sel == 1 else (v0 - k[i] * v1 - v2))
    return out


# --------------------------------------------------------------------------
# エンベロープ / LFO
# --------------------------------------------------------------------------
def env_ar(n, atk_sec, dec_sec, curve=3.0, hold_sec=0.0):
    """立ち上がり + (保持) + 指数減衰。n に足りない分は 0。"""
    n = int(n)
    e = zeros(n)
    a = min(n, max(1, N(atk_sec)))
    h = min(n - a, max(0, N(hold_sec)))
    d = max(1, n - a - h)
    e[:a] = np.linspace(0.0, 1.0, a) ** 0.6
    if h:
        e[a : a + h] = 1.0
    tail = np.linspace(0.0, 1.0, d)
    e[a + h :] = np.exp(-float(curve) * tail * (d / float(max(1, N(dec_sec)))))
    return e


def env_exp(n, tau_sec):
    return np.exp(-np.arange(int(n), dtype=np.float64) / (float(tau_sec) * SR))


def env_adsr(n, a, d, s, r):
    n = int(n)
    na, nd, nr = N(a), N(d), N(r)
    ns_ = max(0, n - na - nd - nr)
    parts = [
        np.linspace(0.0, 1.0, max(1, na)),
        np.linspace(1.0, s, max(1, nd)),
        np.full(ns_, s),
        np.linspace(s, 0.0, max(1, nr)),
    ]
    return pad_to(np.concatenate(parts), n)


def env_hann(n):
    return np.hanning(max(2, int(n)))


def env_gauss(n, center=0.5, width=0.25):
    u = np.linspace(0.0, 1.0, int(n))
    return np.exp(-0.5 * ((u - center) / max(1e-4, width)) ** 2)


def lfo(n, rate, depth=1.0, center=0.0, phase0=0.0, shape="sine"):
    p = phase(rate, int(n), phase0)
    if shape == "sine":
        w = np.sin(p)
    elif shape == "tri":
        w = 2.0 / math.pi * np.arcsin(np.sin(p))
    elif shape == "up":
        w = 2.0 * ((p / TWO_PI) % 1.0) - 1.0
    else:
        w = np.sign(np.sin(p))
    return center + depth * w


def stick_slip(n, rate, seed=0, jitter=0.5, sharp=40.0):
    """軋み (stick-slip) の振幅変調: 不規則な微小インパルスの連なり。0..1"""
    r = rng(seed)
    out = zeros(n)
    rate_a = as_array(rate, n)
    i = 0.0
    while i < n:
        idx = int(i)
        if idx >= n:
            break
        amp = 0.45 + 0.55 * r.random()
        dec = max(4, int(SR / (sharp * max(0.2, rate_a[idx] / 40.0))))
        seg = min(n - idx, dec * 4)
        out[idx : idx + seg] += amp * np.exp(-np.arange(seg) / float(dec))
        step = SR / max(1.0, rate_a[idx])
        i += step * (1.0 + jitter * (r.random() - 0.5))
    p = np.max(np.abs(out))
    return out / p if p > 0 else out


def grain_env(n, count, seed=0, spread=1.0, dur_sec=0.02, jitter=0.6):
    """粒状の振幅 (紙の擦れ、爪の引っ掻きなど)。0..1"""
    r = rng(seed)
    out = zeros(n)
    for _ in range(int(count)):
        pos = int(r.random() * spread * n)
        d = max(8, int(N(dur_sec) * (0.4 + 1.4 * r.random())))
        if pos >= n:
            continue
        seg = min(n - pos, d)
        out[pos : pos + seg] += (0.3 + 0.7 * r.random()) * np.hanning(max(2, d))[:seg]
    p = np.max(np.abs(out))
    return out / p if p > 0 else out


# --------------------------------------------------------------------------
# エフェクト
# --------------------------------------------------------------------------
def comb_ir(delay_sec, feedback, max_sec=2.0):
    """フィードバックコムの IR。"""
    d = max(1, N(delay_sec))
    n = N(max_sec)
    ir = zeros(n)
    g = 1.0
    i = 0
    while i < n and abs(g) > 1e-4:
        ir[i] += g
        g *= feedback
        i += d
    return ir


def allpass_ir(delay_sec, g, max_sec=1.0):
    d = max(1, N(delay_sec))
    n = N(max_sec)
    ir = zeros(n)
    ir[0] = -g
    gg = 1.0 - g * g
    i = d
    k = 0
    while i < n and abs(gg * (g ** k)) > 1e-4:
        ir[i] += gg * (g ** k)
        i += d
        k += 1
    return ir


_REV_CACHE = {}


def reverb_ir(dur=1.2, decay=0.45, damp_hz=4000.0, predelay=0.012, seed=7, er=True, lo_decay_mul=1.9):
    """指数減衰ノイズ + 初期反射の簡易 IR。高域だけ速く減衰させて「部屋」らしくする。"""
    key = (round(dur, 3), round(decay, 3), round(damp_hz, 1), round(predelay, 4), seed, er, lo_decay_mul)
    got = _REV_CACHE.get(key)
    if got is not None:
        return got
    n = N(dur)
    r = rng(seed)
    noise = r.standard_normal(n)
    t = np.arange(n) / float(SR)
    hi = noise * np.exp(-t / max(0.02, decay * 0.4))
    lo = noise * np.exp(-t / max(0.02, decay * lo_decay_mul))
    ir = lowpass(lo, damp_hz * 0.35, order=2) + highpass(hi, damp_hz * 0.35, order=2) * 0.55
    ir = highpass(ir, 90.0, order=1)
    if er:
        for _ in range(9):
            pos = int((0.004 + 0.055 * r.random()) * SR)
            if pos < n:
                ir[pos] += (0.5 - r.random()) * 0.9
    pd = N(predelay)
    if pd:
        ir = np.concatenate([zeros(pd), ir])[:n]
    ir[: max(2, N(0.0008))] *= np.linspace(0.0, 1.0, max(2, N(0.0008)))
    p = np.max(np.abs(ir))
    if p > 0:
        ir /= p
    _REV_CACHE[key] = ir
    return ir


def reverb(x, wet=0.25, dur=1.2, decay=0.45, damp_hz=4000.0, predelay=0.012, seed=7, dry=1.0, tail=True):
    ir = reverb_ir(dur, decay, damp_hz, predelay, seed)
    w = fftconv(x, ir)
    p = np.max(np.abs(w))
    if p > 0:
        w = w / p * max(1e-9, np.max(np.abs(x)))
    if not tail:
        w = w[: len(x)]
    return mix(dry * np.asarray(x, dtype=np.float64), wet * w)


def softclip(x, drive=3.0, mix_amt=1.0):
    d = max(1e-3, float(drive))
    y = np.tanh(x * d) / math.tanh(d)
    return (1.0 - mix_amt) * x + mix_amt * y


def asym_drive(x, drive=3.0, bias=0.15):
    y = np.tanh((x + bias) * drive)
    return y - math.tanh(bias * drive)


def bitcrush(x, bits=8, hold=1):
    y = np.asarray(x, dtype=np.float64)
    if hold > 1:
        n = len(y)
        idx = (np.arange(n) // int(hold)) * int(hold)
        y = y[np.clip(idx, 0, n - 1)]
    if bits < 24:
        step = 2.0 ** (1 - int(bits))
        y = np.round(y / step) * step
    return y


def ring_mod(x, freq, depth=1.0):
    return x * (1.0 - depth + depth * sine(freq, len(x)))


def tremolo(x, rate, depth=0.5, phase0=0.0, shape="sine"):
    return x * (1.0 - depth + depth * 0.5 * (1.0 + lfo(len(x), rate, 1.0, 0.0, phase0, shape)))


def delay_taps(x, taps):
    """taps = [(秒, ゲイン), ...]"""
    n = len(x) + N(max(t for t, _ in taps)) + 1
    out = zeros(n)
    out[: len(x)] += x
    for t, g in taps:
        place(out, x, t, g)
    return out


def haas_widen(x, *_a, **_k):
    """mono 出力なので何もしない (API 互換のためだけ)。"""
    return x


# --------------------------------------------------------------------------
# 仕上げ
# --------------------------------------------------------------------------
def dc_kill(x, circular=False):
    """DC オフセット除去。ループ素材は circular=True で周期性を壊さない。"""
    y = np.asarray(x, dtype=np.float64) - float(np.mean(x))
    return highpass(y, 22.0, 0.707, 1, circular=circular)


def norm_peak(x, dbfs=-3.0):
    p = float(np.max(np.abs(x)))
    if p < 1e-12:
        return np.asarray(x, dtype=np.float64)
    return np.asarray(x, dtype=np.float64) * (db2lin(dbfs) / p)


def fade(x, in_sec=0.003, out_sec=0.01):
    y = np.array(x, dtype=np.float64, copy=True)
    a = min(len(y), N(in_sec))
    b = min(len(y) - a, N(out_sec))
    if a > 1:
        y[:a] *= np.linspace(0.0, 1.0, a) ** 0.5
    if b > 1:
        y[-b:] *= np.linspace(1.0, 0.0, b) ** 0.5
    return y


def trim_tail(x, thresh_db=-72.0, min_sec=0.05):
    """末尾の無音を落とす (ただし min_sec は残す)。"""
    th = db2lin(thresh_db) * max(1e-9, np.max(np.abs(x)))
    idx = np.nonzero(np.abs(x) > th)[0]
    if len(idx) == 0:
        return x
    end = min(len(x), max(idx[-1] + N(min_sec), N(min_sec)))
    return x[:end]


def place_wrap(base, x, at_sec, gain=1.0):
    """ループ素材用: はみ出した分を先頭に回り込ませる (周期性を保つ)。"""
    n = len(base)
    i = N(at_sec) % n
    m = len(x)
    for k in range(0, m, n):
        seg = x[k : k + n]
        j = (i + k) % n
        e = min(n, j + len(seg))
        base[j:e] += gain * seg[: e - j]
        rest = len(seg) - (e - j)
        if rest > 0:
            base[:rest] += gain * seg[e - j :]
    return base


# --------------------------------------------------------------------------
# WAV 書き出し (ループ音には smpl チャンクを入れて Godot に検出させる)
# --------------------------------------------------------------------------
def write_wav(path, x, loop=False, loop_start=0, loop_end=None):
    x = np.asarray(x, dtype=np.float64)
    if np.max(np.abs(x)) > 1.0:
        x = np.clip(x, -1.0, 1.0)
    pcm = np.round(x * 32767.0).astype("<i2").tobytes()
    n = len(x)
    if loop_end is None:
        loop_end = n - 1
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = [b"fmt " + struct.pack("<I", len(fmt)) + fmt]
    if loop:
        smpl = struct.pack(
            "<9I",
            0, 0, int(round(1e9 / SR)), 60, 0, 0, 0, 1, 0,
        ) + struct.pack("<6I", 0, 0, int(loop_start), int(loop_end), 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    data = pcm + (b"\x00" if len(pcm) % 2 else b"")
    chunks.append(b"data" + struct.pack("<I", len(pcm)) + data)
    body = b"WAVE" + b"".join(chunks)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    return n


def read_wav(path):
    with open(path, "rb") as f:
        raw = f.read()
    pos = 12
    data = None
    loop = False
    while pos + 8 <= len(raw):
        cid = raw[pos : pos + 4]
        csz = struct.unpack("<I", raw[pos + 4 : pos + 8])[0]
        if cid == b"data":
            data = np.frombuffer(raw[pos + 8 : pos + 8 + csz], dtype="<i2").astype(np.float64) / 32768.0
        elif cid == b"smpl":
            loop = struct.unpack("<I", raw[pos + 8 + 28 : pos + 8 + 32])[0] > 0
        pos += 8 + csz + (csz % 2)
    return data, loop


# --------------------------------------------------------------------------
# 解析
# --------------------------------------------------------------------------
def analyze(x, block=2048):
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    peak = float(np.max(np.abs(x))) if n else 0.0
    rms = float(np.sqrt(np.mean(x * x))) if n else 0.0
    b = min(block, n // 2 if n >= 4 else n)
    head = x[:b]
    tail = x[-b:]
    joined = np.concatenate([tail, head])
    d = np.diff(joined)
    drms = float(np.sqrt(np.mean(d * d))) if len(d) else 0.0
    step = float(abs(x[0] - x[-1])) if n else 0.0
    return {
        "samples": n,
        "seconds": n / float(SR),
        "peak": peak,
        "peak_db": lin2db(peak),
        "rms": rms,
        "rms_db": lin2db(rms),
        "head_rms_db": lin2db(float(np.sqrt(np.mean(head * head)))),
        "tail_rms_db": lin2db(float(np.sqrt(np.mean(tail * tail)))),
        "seam_step": step,
        "seam_ratio": (step / drms) if drms > 1e-12 else 0.0,
        "seam_vs_p99": (step / float(np.percentile(np.abs(d), 99))) if len(d) and np.percentile(np.abs(d), 99) > 1e-12 else 0.0,
        "clipped": int(np.sum(np.abs(x) >= 0.9995)),
        "dc": float(np.mean(x)),
    }


# --------------------------------------------------------------------------
# PNG 出力 (PIL 無しで書く)
# --------------------------------------------------------------------------
def write_png(path, rgb):
    rgb = np.asarray(rgb, dtype=np.uint8)
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag, payload):
        c = tag + payload
        return struct.pack(">I", len(payload)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


_CMAP = np.array(
    [
        [0, 0, 8], [12, 8, 38], [40, 11, 84], [78, 14, 108],
        [119, 28, 109], [160, 42, 99], [199, 63, 77], [228, 98, 53],
        [246, 142, 35], [252, 190, 60], [252, 233, 133], [255, 255, 224],
    ],
    dtype=np.float64,
)


def _apply_cmap(v):
    v = np.clip(v, 0.0, 1.0) * (len(_CMAP) - 1)
    i0 = np.floor(v).astype(int)
    i1 = np.clip(i0 + 1, 0, len(_CMAP) - 1)
    f = (v - i0)[..., None]
    return (_CMAP[i0] * (1 - f) + _CMAP[i1] * f).astype(np.uint8)


def spectrogram_rows(x, cols=512, rows=140, nfft=1024, fmin=30.0, fmax=20000.0):
    n = len(x)
    if n < nfft:
        x = pad_to(x, nfft)
        n = nfft
    starts = np.linspace(0, n - nfft, cols).astype(int)
    win = np.hanning(nfft)
    frames = np.stack([x[s : s + nfft] * win for s in starts])
    mag = np.abs(np.fft.rfft(frames, axis=1))
    sdb = 20.0 * np.log10(mag + 1e-7)
    binf = np.arange(nfft // 2 + 1) * (SR / float(nfft))
    edges = np.geomspace(fmin, min(fmax, SR / 2 - 1), rows + 1)
    out = np.empty((rows, cols), dtype=np.float64)
    for r in range(rows):
        lo = np.searchsorted(binf, edges[r], "left")
        hi = max(lo + 1, np.searchsorted(binf, edges[r + 1], "right"))
        out[r] = sdb[:, lo:hi].max(axis=1)
    return out  # rows: 低域 -> 高域


def plot_wave_spec(path, x, title_bar=True, wave_h=110, gap=6, width=512, height=256):
    x = np.asarray(x, dtype=np.float64)
    img = np.zeros((height, width, 3), dtype=np.uint8)
    img[:, :] = (10, 11, 14)
    n = len(x)
    # --- 波形 (列ごとの min/max) ---
    edges = np.linspace(0, n, width + 1).astype(int)
    mid = wave_h // 2
    for c in range(width):
        a, b = edges[c], max(edges[c] + 1, edges[c + 1])
        seg = x[a:b]
        lo, hi = float(seg.min()), float(seg.max())
        y0 = int(mid - hi * (mid - 2))
        y1 = int(mid - lo * (mid - 2))
        y0 = max(0, min(wave_h - 1, y0))
        y1 = max(0, min(wave_h - 1, y1))
        if y1 < y0:
            y0, y1 = y1, y0
        clip = max(abs(lo), abs(hi)) >= 0.9995
        col = (255, 70, 60) if clip else (120, 230, 160)
        img[y0 : y1 + 1, c] = col
    img[mid, :] = np.maximum(img[mid, :], (45, 55, 50))
    # -3dBFS / -12dBFS の目安線
    for dbv, col in ((-3.0, (70, 70, 90)), (-12.0, (48, 48, 62))):
        g = db2lin(dbv)
        for s in (-1, 1):
            yy = int(mid - s * g * (mid - 2))
            if 0 <= yy < wave_h:
                img[yy, ::4] = col
    # --- スペクトログラム ---
    spec_h = height - wave_h - gap
    sdb = spectrogram_rows(x, cols=width, rows=spec_h)
    top = float(np.max(sdb))
    v = (sdb - (top - 78.0)) / 78.0
    rgbs = _apply_cmap(v)
    img[wave_h + gap :, :] = rgbs[::-1]  # 上が高域になるよう反転
    if title_bar:
        img[wave_h : wave_h + gap, :] = (26, 28, 34)
    write_png(path, img)
    return path
