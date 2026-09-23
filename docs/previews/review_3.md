# review_3 — 新機能の確認と review_2 所見の再検証

レビュー担当。実装はしていない(新規ファイルはこの 1 本だけ)。
対象は `work/v1` の `b256262`。作業ツリーは models の `assets/models/npc_*.glb` と
`tools/blender/build_humans_mpfb.py` だけ変更あり(メッシュ更新中のため、人物の見た目は判定対象から外した)。

`review_2.md` の所見を同じ手順で回し直し、そのあと `209dddc..HEAD` で入った機能を読んだ。

**review_2 の N1〜N7・N9 は解消。** 未解消は N8(事務所の描画量)と L5(終了時のリーク)。
新規は High 1 件・Medium 2 件・Low 5 件。

---

## 1. review_2 の所見の再検証

| # | 所見 | 判定 | 根拠 |
|---|---|---|---|
| N1 | 終盤のタスクが「線香を立てる」になる | **解消** | `director.gd:563-566` に `finale_running()` ガード。`--time=04:05` のスクリーンショット(`out/review3/t0405.png`)左上が「□ マッチを取って灯明を灯す」 |
| N2 | ナビの `agent_radius` が体より小さい | **ほぼ解消** | `building.gd:671-672` が `agent_radius 0.2 → 0.3`、`agent_height 1.6 → 1.8`。人物(0.26〜0.28)は収まった。火車の 0.33 だけ 3cm はみ出す → R4 |
| N3 | 経路キャッシュが目標切替で無効化されない | **解消** | `npc_base.gd:729-731` に `_reset_steer_cache()`、`:271`(`walk_to`)と `:283`(`retarget`)から呼ぶ |
| N4 | 猫が棺まで到達できない | **解消** | kasha で `ON_COFFIN` 3 回、`23:50 cat_crossed_coffin` が 1 回。異変度が 9 → 12 に上がっている(猫の +3 が入った) |
| N5 | autoplay が毎 tick `flee()` を呼ぶ | **解消** | substitute の `SHOOED` が 47 回 → **3 回** |
| N6 | `shoo()`/`flee()` に同一状態ガードが無い | **解消** | `cat.gd:143-144` / `:151-152` |
| N7 | ポーズを無視するタイマーが 2 件残る | **解消** | `door.gd` / `building.gd` の raw `create_timer` が消えた。残る 11 件は `main.gd` の CLI フックと `dialogue.gd` の `auto_advance` / UI 無しフォールバックのみ |
| N8 | 事務所がいちばん重い | **未解消** | draw calls 2873(1 回目 2805 / 2 回目 2839 と同水準)。下の注意書きを参照 |
| N9 | `Sink.already_line` が到達不能 | **解消** | `sink.gd:25-29` の `_blocked_by_other_item()` で「水以外を持っているとき」だけ弾く形になった |
| L5 | 終了時のリーク | **未解消** | resources still in use: kasha 9 / morning 8 / portrait 2 / substitute 1。substitute は 8 → 1 に減ったが、ばらつきの範囲 |

### N8 の計測についての注意

| 視点 | review_2 draw calls | review_3 draw calls |
|---|---|---|
| トイレで壁を向く | 988 | 1009 |
| 事務所からモニター | 2839 | 2873 |
| 式場から祭壇 | 539 | 532 |
| 玄関の外から建物 | — | 851 |

**fps は今回すべて 120 に張り付いたが、これは比較に使えない。**
review_2 を測ったときは別のエージェントの Godot が 1 プロセス 99% CPU を占有していた。
判断材料になるのは draw calls のほうで、事務所は前回と同水準のまま。

---

## 2. 新機能の確認

### 設定(`src/ui/settings.gd` / `user://settings.cfg`)

- 起動時に `HUD._ready`(`hud.gd:140`)と `Title._ready`(`title.gd:41`)が `Settings.load_all()` → `apply()`。
  `static var` なのでシーン再読み込みをまたいで値が残り、`--reload-test` でも毎回 `apply()` が走る。
- 値はすべて `clampf` を通してから入る(`settings.gd:44-52`)ので、範囲外の数値で壊れない。
- 変更は `_nudge_setting()` のたびに `Settings.apply()` + `Settings.save()`(`hud.gd:1158-1159`)。
  ポーズ中でも HUD は `PROCESS_MODE_ALWAYS` なので操作でき、音量はその場で反映される。
- **VHS の強さだけ効いていない** → R1。

### 壊れた設定ファイルでの起動

`settings.cfg` にバイナリ混じりのゴミ、`progress.cfg` に構文エラーを書いて起動した。

```
ERROR: ConfigFile parse error at user://progress.cfg:2: Expected value, got '']''.
AUTOPLAY START mode=portrait speed=20.0
AUTOPLAY RESULT ending=portrait dread=0 minutes=91
AUTOPLAY OK portrait
```

- クラッシュせず既定値で起動する。`ConfigFile.load()` が OK 以外を返したら早期 return する作りが効いている。
- そのあと両ファイルとも正しい内容で**上書きされて自己修復**した。
- 残るのはエンジンが出す `ConfigFile parse error` の 1 行だけ(握りつぶす手はあるが害はない)→ R7。

### クレジット(`src/director/credits.gd`)

```bash
godot --path . -- --skip-title --credits --screenshot=out/review3/credits.png --wait=6
```
黒地に明朝で下から上へ流れ、右下に「[Space] とばす」が出る(`out/review3/credits.png`)。

- 二重再生は起きない。`Endings.run()` の `_running` ガード、`Game.end_night()` の
  `state == ENDING` 早期 return、`Credits._done` の 3 重で守られている。
- スキップは `Credits._process`(`:110-114`)。`INPUT_DELAY` 0.8 秒あるので、
  エンディング画面を送った E/Space がそのまま貫通することはない。
- スキップしても流れている tween は kill されない(`:89-93`)。0.6 秒のフェードアウト中も
  文字が動き続けるが、見た目だけ。

### E を押しても反応しないときの理由文

- `Interactable.get_blocked_text()`(`interact/interactable.gd:41-44`)を 13 個の systems が上書きしている。
- 表示経路は `Player._update_interact` → `_report_no_response()`(`player.gd:448-454`)→ `HUD.show_toast()`。
- **会話中・手紙中には出ない。** `_update_interact` 自体が `_blocked()` のとき呼ばれず(`player.gd:206` 付近)、
  閉じた直後の 1 押しは `_interact_gate`(`:403-411`)が食う。`_report_no_response()` はゲートの内側にある。
- トーストと独白は画面下でほぼ同じ矩形を使う(`_toast` = y -64..-28 / `_mono` = y -78..-24)が、
  `hud.gd:644` の `_toast.visible = not hide_reticle` が `Dialogue.busy` で隠すので重ならない。

### ゲームパッド

`project.godot` の割り当て:

| アクション | キーボード | パッド |
|---|---|---|
| `move_*` | WASD / 矢印 | 左スティック(axis 0/1) |
| `look_*` | (マウス) | 右スティック(axis 2/3) |
| `interact` | E / 左クリック | ボタン 0(A) |
| `advance` | Space / Enter / E / 左クリック | ボタン 0(A) |
| `pause` | Esc | ボタン 6(Back) |
| `ui_cancel` | Esc | ボタン 1(B) |
| `clipboard` | Tab | ボタン 3(Y) |

- 視点は `_apply_pad_look()`(`player.gd:150-167`)。`_process` から呼ぶが `if not _blocked()` で囲ってあるので、
  会話・手紙・ポーズ中にスティックで視点が動くことはない(`player.gd:280-281`)。
- プロンプト表記は `UiTheme.note_input()` が最後に触った入力機器を覚え(`ui_theme.gd:118-126`)、
  切り替わった瞬間に HUD が `_interact_key` と操作ヒントを作り直す(`hud.gd:626-631`)。
  キーボード → パッドの持ち替えで `[E]` が `[A]` になる。
- `Esc` は `pause` と `ui_cancel` の両方に入っているが、HUD は
  「閉じるのは Esc / B / Start、開くのは Esc / Start だけ」と分けてある(`hud.gd:662-663`、
  `:759-762` は `pause_just` だけを見る)ので、1 回の Esc で閉じて即開き直すことはない。
- 選択肢(`_choice_open`)は `back` を見ない(`hud.gd:729-741`)。息子の選択を B でキャンセルできない。正しい。

### タイトルの到達エンディング

`title.gd:184-195` の `_endings_text()` が `Settings.reached_endings()` を読み、
「終 n/4」と到達した名前(未到達は「？」)を出す。書き込みは `Endings.save_progress()`
(`endings.gd:144-153`)で、既存を読んでから足すので周回で消えない。
壊れた `progress.cfg` でも `cfg.load()` の戻り値を見て空配列を返す(`settings.gd:130-131`)。

**画像での確認はできなかった** → R3。

---

## 3. 新規の所見

### R1(High)ポーズ設定の「VHS の強さ」が効かない

**ファイル**: `src/ui/settings.gd:90-92`、`src/director/director.gd:392-393` / `:715-716`、
`src/director/timeline.gd:543-544` / `:581-582`

**何が起きるか**
設定画面で VHS の強さを変えても、夜が始まった瞬間に director が上書きする。

- `Settings.apply()` → `v.set_intensity(Settings.vhs_intensity)`
- `Director._setup_static()` → `v.set_intensity(0.32)` ← **設定を見ない固定値**
- `Director.refresh_dread_ambient()` → `v.set_intensity(0.32 + 0.15 * lvl)`
- `Timeline.ev_ushimitsu` → `0.62` → `0.32 + 0.15 * Dread.level()`

HUD は `_ready` で `Settings.apply()` を呼ぶが(`hud.gd:149`)、director の `_boot` は
`call_deferred` で**その後**に走るので必ず director が勝つ。
以降も異変度が動くたび・丑三つ時のたびに 0.32 系へ戻る。

**再現**(`user://settings.cfg` の `vhs_intensity` を書き換えて同じ画を撮る)
```bash
# vhs_intensity=0.95 にして
godot --path . -- --skip-title --time=21:30 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review3/vhs_095.png --wait=4
# vhs_intensity=0.05 にして
godot --path . -- --skip-title --time=21:30 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review3/vhs_005.png --wait=4
```
`out/review3/vhs_095.png` と `out/review3/vhs_005.png` は**見分けがつかない**。
どちらも既定の 0.32 相当のノイズ量で、走査線も色にじみも同じ。
設定ファイル側の値は書き換わったまま残っているので、読めていないのではなく上書きされている。

**直し方の案**
`VhsLayer` に「台本が動かす分」と「ユーザーの基準値」を分ける。

```gdscript
# vhs_layer.gd
var user_base: float = 0.32          # 設定から入れる
func set_story_level(f: float) -> void:   # director はこちらを使う
    set_intensity(clampf(user_base + (f - 0.32), 0.0, 1.0))
```
director の 4 か所(`director.gd:393` / `:716`、`timeline.gd:544` / `:582`)を
`set_story_level()` に置き換え、`Settings.apply()` は `user_base` を更新して再適用する。
`ScreenFX.set_intensity()` も同じ入口に寄せる。

**担当**: player(`vhs_layer.gd` と `settings.gd`)+ director(呼び出しの置き換え)

---

### R2(Medium)QA 実行が `user://progress.cfg` を汚す

**ファイル**: `src/director/director.gd:926-928`

```gdscript
func _on_night_ended(id: StringName) -> void:
	endings.save_progress(id)
	endings.run(id)
```
`--ending=morning|kasha|substitute|portrait`(`director.gd:114-119`)も `--autoplay=<mode>` も
最終的に `Game.end_night()` を通るので、**QA を一通り回すと 4 つ全部が「到達済み」になる**。

実際に今回のレビューでも、もともと `progress.cfg` が無かった環境に
自動プレイ 4 本で 4 種が書き込まれた。タイトルの「終 n/4」が QA の回数で埋まってしまう。

**確認**
```
$ cat "…/寝ずの番 - The Wake/progress.cfg"
[endings]
portrait=true
last="portrait"
```
(`--autoplay=portrait` を 1 本走らせただけの状態)

**直し方の案**
`save_progress()` の手前で QA フラグを見る。

```gdscript
func _on_night_ended(id: StringName) -> void:
	if not (args.has("autoplay") or args.has("ending") or args.has("credits")):
		endings.save_progress(id)
	endings.run(id)
```
`--no-progress` のような明示フラグでもよい。

**なお**: レビュー後、`progress.cfg` は元どおり(存在しない状態)に戻した。
退避先は `…/scratchpad/r3/backup/progress_made_by_qa.cfg`。

**担当**: director

---

### R3(Medium)タイトル画面を撮影する手段が無い

**ファイル**: `src/main.gd:36`

```gdscript
if args.has("skip-title") or args.has("screenshot") or args.has("tour") or not ResourceLoader.exists(TITLE_PATH):
	start_game()
else:
	_show_title()
```
`--screenshot` が付いていると**必ず**タイトルを飛ばす。`--auto-start` は `_show_title()` の中
(`main.gd:48-52`)にあるので、`--auto-start` と `--screenshot` を同時に指定しても
タイトルは一度も出ない。

結果として、今回入った**タイトルの到達エンディング表示・TRACKING の導入・メニュー**を
画像で確認する手段が無い。コードを読んで正しいことは確かめたが、
「必ずスクリーンショットを撮って画像を目で見る」(CLAUDE.md)を満たせていない。

**直し方の案**
`--title-shot=<path>` を足すか、`--screenshot` のときでも `--auto-start` があれば
タイトルを出す(`args.has("screenshot") and not args.has("auto-start")`)ようにして、
`--auto-start` の待ち時間中に撮る。

**担当**: 監督(`main.gd`)

---

### R4(Low)火車の体半径だけナビの想定より 3cm 太い

`building.gd:671` の `nm.agent_radius = 0.3` に対し `kasha.gd:58` の `body_radius = 0.33`。
人物(0.26〜0.28)と猫(0.13)は収まったので N2 は実質解決だが、火車だけ残っている。
今回の自動プレイで火車の打ち切りは 0 件だったので実害は観測していない。
`agent_radius` を 0.35 にするか、火車の半径を 0.29 まで絞るか。

**担当**: level / npc

---

### R5(Low)入力機器を切り替えても更新されない表記が 2 か所ある

- `Credits._hint`(`credits.gd:97`)はクレジット開始から 0.8 秒後に 1 回だけ設定する。
  流している途中でパッドに持ち替えても `[Space] とばす` のまま。
- `HUD._note_hint`(`hud.gd` の `show_note` 内)は手紙を開いた時点の表記で固定。

HUD のプロンプトと操作ヒントは `hud.gd:626-631` でちゃんと追従しているので、この 2 か所だけ抜けている。
`_process` で `UiTheme.using_joypad` の変化を見て貼り直せば揃う。

**担当**: director(クレジット)+ player(HUD)

---

### R6(Low)ポーズ中にクレジットが始まると「とばす」が出ない

`Credits.play()` は `await Events.wait(INPUT_DELAY)`(`credits.gd:95`)でスキップ入力を解禁する。
`Events.wait()` はポーズを尊重する(`process_always=false`)ので、ポーズ中はここで止まり、
`_accept_input` が立たず、ヒントも出ない。`Credits` 自体は `PROCESS_MODE_ALWAYS` なので
スクロールの tween だけが進み、30 秒後に勝手に終わる。

いまは `Game.end_night()` が `get_tree().paused = false` にする(`game.gd:53`)ので到達しない。
`Credits` は最初から最後までポーズの外に居る想定なら、ここは `create_timer(x, true)` のほうが筋が通る。

**担当**: director

---

### R7(Low)`progress.cfg` が壊れているとエンジンのエラーが 1 行出る

```
ERROR: ConfigFile parse error at user://progress.cfg:2: Expected value, got '']''.
```
`ConfigFile.load()` の戻り値はちゃんと見ていて動作に影響はないが、
起動ログに ERROR が出ること自体が他のエラーを埋もれさせる。
`FileAccess.file_exists()` で存在を見てから読む、あるいは壊れていたら消す、で黙らせられる。

**担当**: player(`settings.gd`)

---

### R8(Low)`Settings.reset_to_defaults()` が `seen_hint` を戻さない

`settings.gd:68-76` は `show_hints = true` に戻すが `seen_hint` はそのまま。
「既定に戻す」を選んでも初回ヒントは再表示されない。
HUD の `_set_show_hints()`(`hud.gd:1215-1219`)は off→on のときに `seen_hint = false` にしているので、
挙動が 2 系統ある。どちらかに揃えたい。

**担当**: player

---

## 4. autoplay 4 本の結果(1 本ずつ順に実行)

```bash
godot --headless --path . -- --skip-title --autoplay=<mode> --speed=8
```

| mode | exit | 結果 | SCRIPT ERROR | 打ち切り | resources at exit |
|---|---|---|---|---|---|
| morning | 0 | `ending=morning dread=0 minutes=480` **AUTOPLAY OK** | 0 | 1 件 | 8 |
| kasha | 0 | `ending=kasha dread=12 minutes=444` **AUTOPLAY OK** | 0 | 0 件 | 9 |
| substitute | 0 | `ending=substitute dread=0 minutes=480` **AUTOPLAY OK** | 0 | 0 件 | 1 |
| portrait | 0 | `ending=portrait dread=0 minutes=91` **AUTOPLAY OK** | 0 | 0 件 | 2 |

kasha の異変度が 9 → 12 に増えたのは、猫が棺をまたげるようになって `cat_crossed_coffin` の +3 が
入ったため(`23:50 cat_crossed_coffin`)。火車エンドの 2 条件のうち、これまで通っていなかった
ほうの経路がようやく踏めた。

### 猫の状態遷移(4 本合計)

| 状態 | review_1 | review_2 | review_3 |
|---|---|---|---|
| `OUTSIDE_IDLE` | 47 | 36 | 39 |
| `APPROACH` | 27 | 23 | 23 |
| `ENTERING` | 0 | 6 | 7 |
| `INSIDE_WANDER` | 0 | 6 | 6 |
| `TO_COFFIN` | 0 | 3 | 3 |
| `ON_COFFIN` | 0 | 0 | **3** |
| `SHOOED` | 0 | 47 | **3** |
| `cat_crossed_coffin` | 0 | 0 | **1** |

### 唯一残った打ち切り(morning)

```
[npc] Cat2 が (0.700000, 0.100000, 5.000000) へ到達できないので打ち切り(残り 16.45m)
      pos=(-15.506155, -0.019058, 2.164966) reason=move next=(-11.400000, 0.100000, 10.200001)
      nav_ready=true reachable=true path=23.7m
```
建物の外、玄関の西側。直線 16.45m に対し経路が 23.7m の迂回になっている。
外周ナビの遠回りで時間切れになった形で、猫の半径(0.13)は関係ない。頻度は 4 本で 1 件。

---

## 5. CLI フックの確認(各 1 回)

### `--credits`
```bash
godot --path . -- --skip-title --credits --screenshot=out/review3/credits.png --wait=6
```
```
screenshot saved: out/review3/credits.png (fps=120, draw_calls=607, objects=726)
```
黒地・明朝・右下に「[Space] とばす」。ERROR / SCRIPT ERROR なし。

### `--qa-restart`
```
qa-restart: reloading scene (boot_count=1, clock=21:01)
screenshot saved: out/review3/qa_restart.png (fps=120, draw_calls=415, objects=455)
```
SCRIPT ERROR なし。

### `--auto-start=2`(タイトル経由)
`--screenshot` と併用できない(→ R3)ので自動プレイと組み合わせた。
```bash
godot --headless --path . -- --auto-start=2 --autoplay=portrait --speed=12
```
```
[dir] 21:00 intro
[dir] 21:00 intro_done
AUTOPLAY RESULT ending=portrait dread=0 minutes=91
AUTOPLAY OK portrait
```
タイトル → 自動開始 → 導入 → エンディングまで通る。SCRIPT ERROR 0 件。

### `--time=23:30` / `--time=04:05`
```
screenshot saved: out/review3/t2330.png (fps=120, draw_calls=284, objects=326)
screenshot saved: out/review3/t0405.png (fps=120, draw_calls=145, objects=209)
```
どちらも ERROR 0 件。`t0405.png` の左上が「□ マッチを取って灯明を灯す」で N1 の解消を確認。

### `--reload-test=4`(30 秒)
```
reload 回数: 6
SCRIPT ERROR: 0
ERROR: Parameter "material" is null ×14 のみ
```

---

## 6. 観測したエラーログ(全文)

### 起動だけ(`godot --headless --path . --quit`)
```
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 1 resources still in use at exit (run with --verbose for details).
   at: clear (core/io/resource.cpp:822)
```
review_1 / review_2 と同じ。

### 壊れた `progress.cfg` での起動(→ R7)
```
ERROR: ConfigFile parse error at user://progress.cfg:2: Expected value, got '']''.
```

### `Parameter "material" is null`(headless のみ、未解消)
```
ERROR: Parameter "material" is null.
   at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)
```
出現数: morning 7 / substitute 7 / portrait 4 / kasha 2 / reload-test 14。
ウィンドウモードでは今回も 0 件。`servers/rendering/dummy/` なので headless 固有という判断は変えていない。

### SCRIPT ERROR

**今回の全実行(autoplay 4 本 + auto-start + reload-test + 撮影 10 本以上)で 0 件。**

---

## 7. 判定の対象外にしたもの

- **人物モデルの見た目**。`assets/models/npc_*.glb` が作業ツリーで更新中(`56be513` / `2bd6f36` が
  「(途中)」)。リグとアニメ名が確定しているのは確認したが、顔と服の出来は models の作業が
  終わってから見るべきなので触れていない。
- **音**。ヘッドレスとスクリーンショットでは聞こえない。`8db3d50`(心音・囁き・stinger の揺れ)と
  `241f9ef`(夜明けの音)はコードとして `Audio.play*` の呼び出しが正しい名前を使っていることだけ確認した。
  `screen_shake = false` のときに揺れが止まるのは `player.gd:651` のガードで担保されている。
- **室名札と扉の作り分け**。`c3f9c6a` / `58356db` は level の見た目で、
  タイトル同様に撮影して目で見るべきだが、今回は動作側を優先した。
