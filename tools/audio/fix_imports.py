#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""assets/audio/*.wav.import の import 設定を揃える。

Godot 4.7 の wav インポータは既定で QOA (非可逆、compress/mode=2) に圧縮する。
この作品の環境音はほぼ無音に近い所で鳴らすので、非可逆圧縮のノイズが出ると困る。
PCM 非圧縮 (compress/mode=0) に固定する。95 本 320 秒で合計 27MB 程度にしかならない。

edit/loop_mode は 0 (Detect From WAV) のままにする。
ループ音の wav には smpl チャンクを書いてあるので、これで自動的にループになる。

    godot --headless --path . --import     # 1 回目: .import が作られる
    python3 tools/audio/fix_imports.py     # ここで PCM に直す
    godot --headless --path . --import     # 2 回目: PCM で入れ直す

.import は Godot が import して初めて作られる。新しい wav を足した直後にこれを先に
走らせても対象が無くて効かないので、必ず import を挟んでから掛けること。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO = os.path.join(ROOT, "assets", "audio")

WANT = {
    "compress/mode": "0",      # PCM 非圧縮
    "edit/loop_mode": "0",     # Detect From WAV (smpl チャンクを見る)
    "force/mono": "false",
    "force/8_bit": "false",
    "force/max_rate": "false",
    "edit/normalize": "false", # 正規化は生成側でやっている
    "edit/trim": "false",
}


def main():
    if not os.path.isdir(AUDIO):
        print("assets/audio が無い", file=sys.stderr)
        return 1
    changed = 0
    total = 0
    dropped = 0
    for f in sorted(os.listdir(AUDIO)):
        if not f.endswith(".wav.import"):
            continue
        total += 1
        path = os.path.join(AUDIO, f)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        orig = text
        for key, val in WANT.items():
            pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
            if pat.search(text):
                text = pat.sub("%s=%s" % (key, val), text)
        if text != orig:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            changed += 1
            dropped += _drop_cache(text)
    print("import 設定: %d / %d 件を更新 (compress/mode=0 PCM)、キャッシュ破棄 %d 件"
          % (changed, total, dropped))
    return 0


def _drop_cache(import_text):
    """.godot/imported/ の古い変換結果を消す。

    Godot は .import の params だけが変わっても再インポートしてくれない
    (ソース wav の md5 が同じなので「最新」と判断する)。
    変換済みファイルと md5 を消しておけば、次の --import で作り直される。
    .godot/ は生成物なので消して問題ない。
    """
    n = 0
    targets = set(re.findall(r'res://(\.godot/imported/[^"\]]+)', import_text))
    for rel in targets:
        f = os.path.join(ROOT, rel)
        for cand in (f, os.path.splitext(f)[0] + ".md5"):
            if os.path.exists(cand):
                os.remove(cand)
                n += 1
    return n


if __name__ == "__main__":
    sys.exit(main())
