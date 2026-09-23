# -*- coding: utf-8 -*-
"""音の生成ドライバ.

    /opt/homebrew/bin/blender --background --python tools/audio/gen_audio.py
    /opt/homebrew/bin/blender --background --python tools/audio/gen_audio.py -- --only=door_open --png

やること:
  1. voices.VOICES を全部生成 -> assets/audio/<name>.wav (44.1kHz mono 16bit)
  2. CLAUDE.md の「音名一覧」と照合して過不足を 0 にする
  3. docs/previews/audio_report.md に秒数/ピーク/RMS/ループ可否/継ぎ目を表で出す
  4. 代表音の波形+スペクトログラムを docs/previews/audio_<name>.png に出す
"""

import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import dsp  # noqa: E402
import voices  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "audio")
PREVIEW_DIR = os.path.join(ROOT, "docs", "previews")
CLAUDE_MD = os.path.join(ROOT, "CLAUDE.md")

# 波形を目で見る音 (依頼された 5 つ + 各系統から代表)
PNG_NAMES = [
    "radio_talk", "phone_dial", "phone_ringback", "phone_voicemail",
    "phone_unavailable", "cat_chorus", "spark", "safe_wrong",
    "door_swing_close",
    "door_lock", "door_unlock",
    "amb_morning", "car_arrive",
    "door_swing_open", "cat_meow_2", "cat_meow_3", "stinger_3",
    "snore_1", "snore_2", "cat_jump", "cloth_drop",
    "stinger_2", "amb_shikijo", "door_close", "cat_scratch_1", "coffin_knock",
    "phone_ring", "door_open", "cat_meow_1", "stinger_1", "amb_room",
    "amb_outside", "amb_tatami", "step_lino_1", "kasha_screech", "chime_dawn",
    "heartbeat", "incense_light", "whisper_1", "water_pour", "amb_drone_low",
]

# 再生時の推奨ゲイン。ファイル自体はピーク正規化されているので、
# 実際のミックスではこの値を Audio.play(name, volume_db) に渡すことを想定している。
RECOMMENDED_DB = {
    "ui_select": -18.0, "ui_confirm": -16.0, "ui_back": -18.0,
    "whisper_1": -20.0, "whisper_2": -20.0, "whisper_3": -20.0,
    "breath_close": -12.0, "incense_hiss": -24.0, "heartbeat": -10.0,
    "cat_purr": -16.0, "tv_static": -14.0, "paper_rustle": -10.0,
    "page_turn": -10.0, "phone_breath": -8.0, "coffin_scratch": -6.0,
    "footstep_ceiling_1": -8.0, "footstep_ceiling_2": -8.0, "footstep_ceiling_3": -8.0,
    "amb_morning": 0.0, "car_arrive": -4.0,
    "radio_talk": -12.0, "radio_on": -6.0, "radio_off": -6.0,
    "phone_dial": -6.0, "phone_ringback": -6.0,
    "phone_voicemail": -6.0, "phone_unavailable": -6.0,
    "snore_1": -14.0, "snore_2": -14.0, "cat_jump": -6.0, "cloth_drop": -6.0,
}
for _pfx in ("step_lino_", "step_tatami_", "step_concrete_"):
    for _i in range(1, 5):
        RECOMMENDED_DB["%s%d" % (_pfx, _i)] = -14.0


# --------------------------------------------------------------------------
def expected_names():
    """CLAUDE.md「音名一覧」から納品すべき音名を読む。`a_1..4` は展開する。"""
    with open(CLAUDE_MD, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"^## 音名一覧.*?$(.*?)^## ", text, re.S | re.M)
    if not m:
        raise SystemExit("CLAUDE.md に「## 音名一覧」が見つからない")
    body = m.group(1)
    names = []
    for tok in re.findall(r"`([^`]+)`", body):
        tok = tok.strip()
        rng_m = re.match(r"^([A-Za-z0-9_]+?)_(\d+)\.\.(\d+)$", tok)
        if rng_m:
            stem, a, b = rng_m.group(1), int(rng_m.group(2)), int(rng_m.group(3))
            names.extend("%s_%d" % (stem, i) for i in range(a, b + 1))
        elif re.match(r"^[A-Za-z0-9_]+$", tok):
            names.append(tok)
    seen = set()
    ordered = []
    for n in names:
        if n not in seen:
            seen.add(n)
            ordered.append(n)
    return ordered


def render(name):
    fn, loop, target = voices.VOICES[name]
    x = np.asarray(fn(), dtype=np.float64)
    x = dsp.norm_peak(x, target)
    if not loop:
        # 単発は末尾を必ず 0 に落として、切り口のプチを消す
        x = dsp.fade(x, 0.00012, 0.008)
        x = dsp.norm_peak(x, target)
    x = np.clip(x, -1.0, 1.0)
    return x, loop, target


def main(argv):
    only = None
    want_png = True
    for a in argv:
        if a.startswith("--only="):
            only = [s for s in a.split("=", 1)[1].split(",") if s]
        elif a == "--no-png":
            want_png = False
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)

    exp = expected_names()
    have = list(voices.VOICES.keys())
    missing = [n for n in exp if n not in voices.VOICES]
    extra = [n for n in have if n not in exp]

    targets = only if only else exp
    rows = []
    t0 = time.time()
    for i, name in enumerate(targets, 1):
        if name not in voices.VOICES:
            continue
        t = time.time()
        x, loop, target = render(name)
        path = os.path.join(OUT_DIR, name + ".wav")
        dsp.write_wav(path, x, loop=loop)
        a = dsp.analyze(x)
        a["name"] = name
        a["loop"] = loop
        a["target_db"] = target
        a["bytes"] = os.path.getsize(path)
        rows.append(a)
        print("[%3d/%3d] %-22s %6.2fs peak %6.2f dBFS  rms %6.2f dBFS  %s  (%.2fs)"
              % (i, len(targets), name, a["seconds"], a["peak_db"], a["rms_db"],
                 "LOOP" if loop else "    ", time.time() - t))
    print("--- 生成 %d 本 / %.1f 秒 ---" % (len(rows), time.time() - t0))

    if want_png:
        for name in PNG_NAMES:
            if name not in voices.VOICES:
                continue
            p = os.path.join(OUT_DIR, name + ".wav")
            if not os.path.exists(p):
                continue
            data, _ = dsp.read_wav(p)
            dsp.plot_wave_spec(os.path.join(PREVIEW_DIR, "audio_%s.png" % name), data)
        print("PNG: %d 枚 -> docs/previews/" % len(PNG_NAMES))

    # --- 照合 ---
    files = sorted(f[:-4] for f in os.listdir(OUT_DIR) if f.endswith(".wav"))
    not_written = [n for n in exp if n not in files]
    orphan = [n for n in files if n not in exp]
    print("\n=== 音名の照合 ===")
    print("CLAUDE.md の音名: %d / 登録された生成関数: %d / 出力された wav: %d" % (len(exp), len(have), len(files)))
    print("欠け(CLAUDE.md にあって wav が無い): %d %s" % (len(not_written), not_written if not_written else ""))
    print("余り(wav があって CLAUDE.md に無い): %d %s" % (len(orphan), orphan if orphan else ""))
    if missing:
        print("!! 生成関数が未実装: %s" % missing)
    if extra:
        print("!! 一覧に無い生成関数: %s" % extra)

    if not only:
        write_report(rows, exp, not_written, orphan)
    return 0 if not (not_written or orphan) else 1


def write_report(rows, exp, not_written, orphan):
    by_name = {r["name"]: r for r in rows}
    loops = [r for r in rows if r["loop"]]
    singles = [r for r in rows if not r["loop"]]
    total_sec = sum(r["seconds"] for r in rows)
    total_mb = sum(r["bytes"] for r in rows) / 1048576.0

    def table(items):
        out = ["| 名前 | 秒 | ピーク dBFS | RMS dBFS | ループ | 継ぎ目の段差 | 段差/p99 | クリップ | 推奨 volume_db |",
               "|---|---:|---:|---:|:--:|---:|---:|---:|---:|"]
        for r in items:
            rec = RECOMMENDED_DB.get(r["name"])
            out.append("| `%s` | %.2f | %.1f | %.1f | %s | %.5f | %.2f | %d | %s |" % (
                r["name"], r["seconds"], r["peak_db"], r["rms_db"],
                "○" if r["loop"] else "—", r["seam_step"], r["seam_vs_p99"],
                r["clipped"], ("%.0f" % rec) if rec is not None else "0"))
        return "\n".join(out)

    worst = sorted(loops, key=lambda r: -r["seam_vs_p99"])[:3]
    lines = []
    lines.append("# 音アセット レポート\n")
    lines.append("`tools/audio/gen_audio.py` が自動生成する。手で編集しない。\n")
    lines.append("- 形式: WAV 44.1kHz / mono / 16bit。素材は一切使わず numpy で合成している。")
    lines.append("- 本数 **%d**、合計 **%.1f 秒**、**%.1f MB**(ループ %d / 単発 %d)。"
                 % (len(rows), total_sec, total_mb, len(loops), len(singles)))
    lines.append("- ピーク正規化: 単発 -3 dBFS / 環境ループ -12 dBFS / ドローン -15 dBFS。全ファイル DC 除去済み。")
    lines.append("- ループ音には WAV の `smpl` チャンクを書いてある。インポータの `edit/loop_mode` は"
                 " 既定の `Detect From WAV` のままでよく、ループ点は自動で付く。\n")
    lines.append("## 作り直す手順\n")
    lines.append("```bash")
    lines.append("/opt/homebrew/bin/blender --background --python tools/audio/gen_audio.py  # wav + PNG + このレポート")
    lines.append("godot --headless --path . --import          # 1 回目: .import ファイルが作られる")
    lines.append("python3 tools/audio/fix_imports.py          # compress/mode を PCM に戻す")
    lines.append("godot --headless --path . --import          # 2 回目: PCM で入れ直す")
    lines.append("godot --headless --path . --script res://tools/audio/verify_audio.gd      # 名前/形式/ループの照合")
    lines.append("godot --headless --path . --script res://tools/audio/make_bus_layout.gd   # バス構成を作り直すとき")
    lines.append("```\n")
    lines.append("`fix_imports.py` が要るのは、Godot 4.7 の wav インポータの既定が **QOA(非可逆)**")
    lines.append("だから。この作品の環境音はほぼ無音に近いところで鳴るので、非可逆の粗が出ると困る。")
    lines.append("`compress/mode=0`(PCM 非圧縮)に固定している。それでも全部で %.0fMB 程度。" % total_mb)
    lines.append("**順序に注意**: `.import` ファイルは Godot が import したときに初めて作られるので、")
    lines.append("新しい wav を足した直後に `fix_imports.py` を先に走らせても効かない。")
    lines.append("必ず **import -> fix_imports -> import** の順で回すこと。\n")
    lines.append("また Godot は `.import` の params だけが変わっても再インポートしない"
                 "(ソース wav の md5 が同じなので「最新」と判断する)。そのため `fix_imports.py` は")
    lines.append("設定を書き換えたファイルについて `.godot/imported/` の変換済みデータも捨てる。")
    lines.append("`verify_audio.gd` が `format=3` を報告したら QOA のまま入っているということなので、")
    lines.append("`fix_imports.py` -> `--import` をもう一度回せば直る。\n")

    lines.append("## 照合結果\n")
    lines.append("- CLAUDE.md「音名一覧」: **%d** 個" % len(exp))
    lines.append("- 欠け: **%d** %s" % (len(not_written), "`" + "` `".join(not_written) + "`" if not_written else ""))
    lines.append("- 一覧に無い余分な wav: **%d** %s\n" % (len(orphan), "`" + "` `".join(orphan) + "`" if orphan else ""))

    lines.append("## 継ぎ目(ループ)\n")
    lines.append("先頭 2048 サンプルと末尾 2048 サンプルを繋いだ窓で測る。")
    lines.append("- **継ぎ目の段差** = `|x[0] - x[-1]|`(絶対値、フルスケール 1.0)")
    lines.append("- **段差/p99** = その段差が、同じ窓の中の隣接サンプル差の 99 パーセンタイルの何倍か。")
    lines.append("  **1.0 以下なら、継ぎ目は波形が普段動く幅の中に収まっている = 段差として聞こえない。**")
    lines.append("")
    lines.append("環境ループは正弦の周波数をループ長の整数倍に丸め、ノイズは周期ノイズ("
                 "FFT 合成)、フィルタは円状畳み込みで掛けてあるので、数学的に周期関数になっている。"
                 "クロスフェードは使っていない(使うとノイズ層に -3dB の谷ができるため)。")
    lines.append("")
    lines.append("| ループ音 | 段差 | 段差/p99 | 判定 |")
    lines.append("|---|---:|---:|---|")
    for r in sorted(loops, key=lambda r: r["name"]):
        ok = "OK" if r["seam_vs_p99"] <= 1.0 else ("許容" if r["seam_vs_p99"] <= 2.0 else "要確認")
        lines.append("| `%s` | %.6f | %.2f | %s |" % (r["name"], r["seam_step"], r["seam_vs_p99"], ok))
    lines.append("")
    if worst:
        lines.append("最も段差が大きいループ: " + "、".join("`%s`(%.2f)" % (r["name"], r["seam_vs_p99"]) for r in worst) + "\n")

    lines.append("## バス構成\n")
    lines.append("`default_bus_layout.tres`(`tools/audio/make_bus_layout.gd` が生成)\n")
    lines.append("| # | バス | 送り先 | エフェクト |")
    lines.append("|---:|---|---|---|")
    lines.append("| 0 | `Master` | — | `AudioEffectLowPassFilter` cutoff 600Hz / **既定は disabled**。`Audio.set_muffled(true)` で有効になる |")
    lines.append("| 1 | `SFX` | Master | なし |")
    lines.append("| 2 | `Ambient` | Master | `AudioEffectReverb` 薄め(wet 0.12 / room 0.55 / damping 0.55 / predelay 20ms) |")
    lines.append("| 3 | `UI` | Master | なし |\n")

    lines.append("## 推奨 volume_db\n")
    lines.append("ファイルはすべてピーク正規化してあるので、`ui_select` と `stinger_1` の"
                 "ピークが同じになっている。実際のミックスでは下の値を `Audio.play(name, volume_db)` に"
                 "渡す前提で作った(表の最終列)。0 のものはそのままでよい。\n")

    lines.append("## 全ファイル\n")
    lines.append("### 環境ループ\n")
    lines.append(table(sorted(loops, key=lambda r: r["name"])))
    lines.append("\n### 単発\n")
    lines.append(table(sorted(singles, key=lambda r: r["name"])))

    lines.append("\n## 波形プレビュー\n")
    lines.append("上半分が波形(横線は -3 dBFS と -12 dBFS の目安、クリップした列は赤)、"
                 "下半分がスペクトログラム(縦軸は 30Hz〜20kHz の対数、上が高域、ダイナミックレンジ 78dB)。\n")
    for n in PNG_NAMES:
        if n in by_name:
            lines.append("- `%s` — ![%s](audio_%s.png)" % (n, n, n))
    lines.append("")

    path = os.path.join(PREVIEW_DIR, "audio_report.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("レポート -> %s" % path)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sys.exit(main(args))
