# tools/blender

モデルとテクスチャの生成スクリプト。すべて Blender 5.2 の python で動かす。

```bash
bash tools/blender/build_all.sh               # 全部作り直し + プレビュー + Godot 取り込み
bash tools/blender/build_all.sh --no-render   # プレビューを撮らない(速い)
```

## スクリプトの役割

| ファイル | 役割 |
|---|---|
| `common.py` | テクスチャ生成・メッシュ組み立て・マテリアル・glTF 出力・リグとアニメの共通処理 |
| `gen_textures.py` | `assets/textures/*.png` を全部生成 |
| `build_ritual.py` | 棺・祭壇・遺影・香炉・燭台・供花・回転灯籠 |
| `build_furniture.py` | 家具と設備(椅子・机・冷凍庫・金庫・自販機・便器など) |
| `build_props.py` | 小物(やかん・線香箱・掲示板・白装束など) |
| `build_arch.py` | 建具と外構(扉・窓・霊柩車・木・塀・提灯) |
| `build_chars.py` | 猫・火車・故人。**人物 3 体のアニメの定義もここ**(MPFB 版が読み替えて使う) |
| `build_humans_mpfb.py` | **人物 3 体**(社長・息子・孫娘)を MPFB2 の人体から作る |
| `render_previews.py` | `docs/previews/*.png`、`contact_sheet.png`、`anim_sheet.png` |
| `render_faces.py` | `docs/previews/npc_*_face.png` と `npc_faces.png` |
| `decal_sheet.py` | デカール(足跡・手形)を下地に重ねた確認用シート |
| `coffin_window_test.py` | 棺の小窓が貫通しているかの証拠画像 |
| `check_in_godot.gd` | Godot 側でノード名・アニメ名・頂点数を検証 |

## MPFB2(MakeHuman Plugin for Blender)の導入

人物 3 体は **MPFB2 が入っていないと作れない**。ほかのモデルには不要。

```bash
# 1. 配布 zip を取る(Blender Extensions から。約 45MB)
curl -sS -L -o /tmp/mpfb.zip \
  "https://extensions.blender.org/download/sha256:4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87/add-on-mpfb-v2.0.17.zip"

# 2. Blender に入れる(1 回だけ)
blender --background --python-expr \
  'import bpy; bpy.ops.extensions.package_install_files(filepath="/tmp/mpfb.zip", repo="user_default", enable_on_install=True)'

# 3. 人物を作る
blender --background --python tools/blender/build_humans_mpfb.py
blender --background --python tools/blender/build_humans_mpfb.py -- npc_boss   # 1 体だけ
```

最新版の URL は `https://extensions.blender.org/api/v1/extensions/` の `id == "mpfb"`
の `archive_url` で取れる。**headless では毎回 `addon_utils.enable()` が要る**
(スクリプト側でやっている)。

### ライセンス

| もの | ライセンス |
|---|---|
| MPFB2 本体 | GPL-3.0-or-later(Joel Palmius ほか) |
| MakeHuman のベースメッシュ・ターゲット(生成される素体の形) | CC0 |
| 生成した glb | CC0 の素体由来なので配布に制限なし |

出典: https://github.com/makehumancommunity/mpfb2 /
http://www.makehumancommunity.org/

### MPFB を使うときの落とし穴(はまったもの)

1. `create_human(feet_on_ground=True)` は**メッシュだけ**持ち上げてリグを動かさず、
   両者が 0.8m ズレる。`False` で作り、足を床に乗せるのは**アーマチュアの
   location** でやる。
2. マクロは**シェイプキー**として乗るので、素の頂点座標から身長は測れない。
   一度作って `bake_targets` してから実身長を測り、生成スケールを直して作り直す。
3. `add_builtin_rig` の一部の骨(頭など)は素体のスケールに追従しない。
   **服の着丈などはメッシュの部位から測る**(骨基準にすると背の低い人物で浮く)。
4. リグを付けたあとに頂点を動かすと、アーマチュアモディファイアが元へ引き戻す。
5. 素体は A ポーズ。自作アニメは腕が真下の前提なので、`straighten_rest()` で
   ポーズを正立させてからレストポーズに焼く。`pose_bone.matrix` へ代入するときは
   **骨の頭を中心に回す**(そのまま掛けるとアーマチュア原点まわりの回転になる)。

## 出力先

- `assets/models/*.glb` — モデル
- `assets/textures/*.png` — テクスチャ
- `docs/previews/` — プレビューと申し送り(`models_notes.md`)
