# director ノート — 夜の台本・QA・判断したこと

担当: director(`src/director/`)。最終更新 2026-09-23。
正本は `docs/design.md` の「v0.2 変更」、テキストの正本は `docs/script.md`。
ここには**実装の対応表と、台本どおりにできなかったところの判断**を書く。

## ファイル

| ファイル | 行 | 中身 |
|---|---|---|
| `src/director/director.tscn` / `director.gd` | 794 | 組み立て、導入(21:00)、イベント購読、線香ループ、異変度連動、火車の代役、`apply_state_for_time` |
| `src/director/timeline.gd` | 739 | 17 個の時刻イベント(1 イベント = 1 関数)と `apply_past` |
| `src/director/scares.gd` | 750 | 脅かし部品 25 個、`random_scare()`、部屋の環境音、月明かり、インタラクト用 `Spot` |
| `src/director/script_text.gd` | 244 | `docs/script.md` のテキスト定数。**日本語の文字列はここだけ** |
| `src/director/endings.gd` | 141 | 4 エンディングの判定と演出 |
| `src/director/autoplay.gd` | 323 | QA 用の自動プレイ |

組み立ての順序は `Director._ready` で子(Scares / Timeline / Endings / Autoplay)を作り、
`call_deferred("_boot")` で main の `--time` スキップが終わった次のフレームに本体を走らせる。
`_boot` は `apply_state_for_time` → `timeline.register` → イベント購読 → 導入 → `Clock.start()`。

## 台本の実装表

| 時刻 | 関数 | 使った systems / npc / level API |
|---|---|---|
| 21:00 | `Director.play_intro` | `NpcBase.set_talkable/go_to/leave_via_genkan`、`hud.set_rules`、`Note.read`、`IncenseStand.light`、`Candle.light`、`Building.set_room_lights(&"Room_Shikijo", false)` |
| 21:40 | `Timeline.ev_flowers` | `FlowerStand.set_wilted`、`Sink.fill`、イベント `flowers_watered` |
| 22:00 | `ev_window` | `WindowPane.open`、`IncenseStand.burn_multiplier = 3.0`、`set_wind`、閉めたら `Cat.sit_at` + `cat_meow_1` |
| 22:30 | `ev_phone_silent` | `Phone.ring(30)` / `hang_up`、`phone_breath`、`GuestBook.rustle` |
| 23:00 | `ev_monitor_figure` | `Scares.spawn_figure(cctv_only)` = render layer 10、`Monitor.switch_feed/set_static/glitch`、`chair_pulled_out()` で椅子を 0.4m 移動 |
| 23:20 | `ev_cats_begin` | `Cat.activate` / `set_target_entry`。以後 20〜25 ゲーム分おきに 3〜5 回、開いている開口部へ |
| 23:40 | `ev_tv` | `TV.turn_on` → 控室に入ると `flash_face(0.4)` → `turn_off` |
| 00:00 | `ev_blackout` | `Building.flicker(&"Room_Hall")`、`Breaker.trip`、復旧後の式場で `Iei.set_face_down(true)` と火を消す |
| 00:30 | `ev_son` | `door_knock_1..3`、`NpcSon.enter_from_genkan`、`Dialogue.choose`、`Coffin.allow_open_window` + `show_face`、`NpcSon.sleep`(01:30) |
| 01:00 | `ev_dry_ice` | `Freezer.take` → `Coffin`、運搬中は 1.5m 後ろに `step_lino_*` と `breath_close` |
| 01:30 | `ev_office_note` | `Note`(収集②)、`page_read{n:2}` で `Door_Office.slam()` |
| 02:00 | `ev_yukan` | `door_locked` → `door_open`、`Door_Yukan.set_locked(false)`、`Yukan_Robe` の `sway` / 最後は `drop` |
| 02:30 | `ev_phone_wet` | `phone_voice_wet`、式場の線香を消す |
| 03:00 | `ev_ushimitsu` | 4 回の消火 + `Coffin.scratch` + `Building.flicker` + `amb_drone_high` + 猫 3 匹 |
| 03:20 | `ev_safe` | `BossDesk.enable_key(true)`、`Safe.set_note`(収集④)、読了で廊下突き当たりに `kasha` |
| 03:40 | `ev_freezer_empty` | `Freezer.set_empty(true)`、`Coffin.set_face_state(3)`、`paw_prints()` |
| 04:00 | `ev_finale` | `Building.set_all_lights(false)` + 月明かり、`Candle.require_matches = true`、`matches` Pickup 有効化、`Kasha.activate`、灯し直し 3 回 |
| 04:40 | `_finish_finale` | `Kasha.stop_chase`、`Clock.skip_to(460)`、タスク「線香を最後に一本立てる」 |
| 04:45 | `ev_dawn_light` | `Scares.start_dawn()`。窓の外に青白い光を 15 ゲーム分かけて上げ、月明かりを引き、VHS を寒色へ。`crow_morning` を 3 回 |
| 05:00 | `ev_dawn` | `Endings.decide()` → `Game.end_night()` |

追加の脅かし(`docs/design.md` の一覧)は全部 `scares.gd` に実装してある。
`random_scare()` が異変度・時刻・居場所を見て、80〜160 秒おきに 1 つ選んで撃つ。

## autoplay の使い方

```bash
godot --headless --path . -- --skip-title --autoplay=morning|kasha|substitute|portrait [--speed=8]
```

- `Dialogue.auto_advance = true`、`Clock.speed = speed`。
  **`burn_seconds` はいじらない。** 線香とロウソクの減りは systems が `delta * Clock.speed` で
  進めるので、ここで speed で割ると二重に効いて一瞬で尽きる。
- 3 秒 / speed ごとに判断する。優先順は 布団 → 控室の戸 → 電話 → 線香 → 猫 → タスク → ロウソク。
- タスクは `Tasks.current()`(先頭固定)ではなく優先順表 `TASK_ORDER` から選ぶ。
  先頭に居座るタスクで以後の用事に進めなくなるのを避けるため。
- モードごとに触らないタスクがある。猫の経路(`cat_entered` → `cat_crossed_coffin` → `cat_shooed`)を
  QA で通すための仕込み(reviewer H7)。

| モード | 無視するタスク | ねらい |
|---|---|---|
| `kasha` | 線香3種 / `backdoor` / `window` / `cat` | 線香を絶やし、勝手口と窓を開けたままにして猫を入れ、棺をまたがせる |
| `substitute` | `backdoor` | 猫を入れてから追い払う(`cat_shooed` を通す) |
- 歩かせず `Player.teleport` + `Interactable.interact()` で用事をこなす。経路探索に依存しない。
- 終了時に `AUTOPLAY RESULT ending=<id> dread=<n> minutes=<n>` を出し、
  期待と違えば exit code 1。ログは `user://autoplay_<mode>.log`。
- speed 8 なら 1 本およそ 3 分。4 本同時に走らせても干渉しない。

最後の実行結果:

```
AUTOPLAY RESULT ending=morning    dread=0 minutes=480   AUTOPLAY OK morning
AUTOPLAY RESULT ending=kasha      dread=7 minutes=440   AUTOPLAY OK kasha
AUTOPLAY RESULT ending=substitute dread=0 minutes=480   AUTOPLAY OK substitute
AUTOPLAY RESULT ending=portrait   dread=0 minutes=91    AUTOPLAY OK portrait
```

## QA 用のコマンドライン引数(director が読む)

| 引数 | 効果 |
|---|---|
| `--time=HH:MM` | `apply_state_for_time` でその時刻の状態を作り、導入を飛ばして即 `Clock.start()` |
| `--screenshot` / `--tour` | 同上(撮影フックが真っ黒にならないように導入を飛ばす) |
| `--intro` | 上の 3 つが付いていても導入を流す。導入の撮影用 |
| `--dread=N` | 異変度を先に積む。座布団や遺影の追従など異変度で出るものを撮るため |
| `--ending=morning\|kasha\|substitute\|portrait` | 前口上を飛ばしてエンディング画面だけ出す |
| `--autoplay=<mode>` `--speed=N` | 自動プレイ |
| `--shots=<dir>` `--shot-interval=<sec>` | 自動プレイ中、既定 20 秒おきに `<dir>/HHMM_<n>.png` を保存。夜全体の目視用。**`--headless` では撮れない** |
| `--cctv-shot=<path>` | 監視モニターの SubViewport(256x192)をそのまま PNG に保存して終了。画面内のモニターは小さすぎて人影が判別できないため |
| `--cctv-feed=<0\|1>` | `--cctv-shot` と併用。撮る前にチャンネルを式場(0)/玄関(1)に切り替える |
| `--scare=<関数名>` | `scares.gd` の脅かしを 1 つだけ発火させる。`--screenshot` / `--cctv-shot` と組み合わせて使う |
| `--scare=body_rises` | 火車エンド直前の起き上がりカットだけ出す |
| `--credits` | クレジットだけ流す |
| `--reload-test=<sec>` | 数秒ごとに `reload_current_scene()` を繰り返す。`Game.reset()` のシグナル一括解除との二重解除を確かめる用 |

夜を通しで目で見るとき:

```bash
godot --path . -- --skip-title --autoplay=morning --speed=8 \
  --shots=out/director/night --shot-interval=9
```

撮影の例:

```bash
godot --path . -- --skip-title --time=21:30 --screenshot=out/director/shikijo.png \
  --pos=12.0,1.6,-0.5 --yaw=-90 --wait=3.5
godot --path . -- --skip-title --time=23:10 --dread=4 --screenshot=out/director/zabuton.png \
  --pos=13.6,1.6,-0.5 --yaw=-90 --pitch=-18 --wait=4.0
godot --path . -- --skip-title --ending=portrait --screenshot=out/director/ending.png --wait=9.0
```

`--screenshot` は **`--headless` では固まる**(`RenderingServer.frame_post_draw` が来ない)。
撮影は必ず通常モードで走らせること。

## 目視したスクリーンショット(`out/director/`)

| ファイル | 判断 |
|---|---|
| `01_2100_genkan.png` | 21:00 の受付。タイムスタンプと REC が出ている |
| `02_2130_shikijo.png` | 蛍光灯が消え、灯明と線香の火だけ。狙いどおりの暗さ |
| `04_2310_zabuton.png` | 棺の前に座布団 + 独白。最初は暗黒で見えず、x を 15.45 に寄せて解決 |
| `05_0030_son.png` | 00:30 の受付まわり |
| `06_0300_ushimitsu.png` | 丑三つ時の明滅を捉えている |
| `07_0345_paws.png` | 濡れた足跡が廊下から式場へ連なる。emission を足して見えるようにした |
| `08_0400_kasha_7.0.png` | 全消灯後。VHS トラッキング帯と月明かりだけ。最初は完全な黒で歩けなかった |
| `09_ending_*.png` | 4 種とも `docs/script.md` の文がそのまま出る。遺影エンドは `iei_photo_player` の写真つき |
| `11_intro_6s.png` | 導入のフェードイン直後。会話順はログで確認 |

## 自動プレイのスクショが単調になる問題

ボットは用事が無いと焼香台の前に立ち続けるので、`--shots` の連番が同じ画ばかりになっていた。
撮る瞬間だけ「直近に発火したイベントの見どころ」へテレポートし、撮ってから元の位置と向きに戻す
(`Autoplay.EVENT_VIEWS` / `_goto_view` / `_save_pose` / `_restore_pose`)。

見どころは `Director.event_log()` の最後の行(`HH:MM ev_xxx`)で引く。
表に無いイベントのときはテレポートしない。

## 会話の立ち位置

NPC がカメラに密着して顔が画面いっぱいになる問題があったので、
`Director.face_off(npc)` を台詞の前に必ず通すようにした。

1. プレイヤーから見た NPC の方向へ `TALK_DISTANCE`(1.8m)の点を計算して `go_to`
2. 歩いているあいだにプレイヤーが動いていたら、現在位置から測り直して `teleport_to`
3. `face_player()` で NPC を向き合わせる
4. `Player.look_at_point(npc.head_position())` でプレイヤーの視線を顔へ向ける

`NpcBase` に `stop_distance` は無いので、目的地を director 側で計算している
(`walk_to(pos, tolerance)` の tolerance は経由点用なので使っていない)。

autoplay(speed 8)で測った実際の距離:

```
[dir] face_off boss dist=1.80m
[dir] face_off boss dist=2.11m
[dir] face_off boss dist=1.40m
[dir] face_off granddaughter dist=2.02m
[dir] face_off boss dist=2.25m
[dir] face_off son dist=3.13m
```

`Game.debug` か autoplay が有効なときだけこの行を出す。

## ランダム脅かしの出し方(時刻と異変度で締める)

「前半は静かで日常的、後半に向けて密度を上げる」という台本の方針に合わせて、
`random_scare()` の発火間隔を時刻で変えている(`Director._scare_interval`)。
間隔は速度 1 のときの実秒。`Clock.speed` を上げても夜全体での回数は変わらない。

| 時間帯 | 間隔 | 中身 |
|---|---|---|
| 〜22:30 | 出さない | 導入と最初の用事だけにする |
| 22:30〜00:00 | 4〜6 分 | **音だけの系統に限定**(`Scares.QUIET_SCARES`)。物は動かさない |
| 00:00〜03:00 | 2〜4 分 | 全種類 |
| 03:00〜 | 1〜2 分 | 全種類 |

異変度が上がるほど間隔を詰める(level 1 で -20%、level 2 で -40%)。
終盤(`ev_finale` 中)は出さない。

台本イベントと重ならないように、**前後 7 ゲーム分(速度 1 で約 20 秒)** は出さない
(`Director.SCARE_GAP_MINUTES` と `Timeline.next_event_minute`)。
窓が閉じているあいだは 20 秒ごとに再判定するので、開いた直後に出る。

speed 8 の自動プレイ 1 本で実測した発火(`--debug` で `[scare]` 行が出る):

```
[scare] 22:43 whisper     room=Room_Office     dread=0
[scare] 00:18 door_behind room=Room_Hall       dread=0
[scare] 01:21 chairs      room=Room_Shikijo    dread=0
[scare] 02:22 smoke       room=Room_Shikijo    dread=0
[scare] 03:53 attic_meow  room=Room_Backyard   dread=0
[scare] 04:44 ceiling     room=Room_Shikijo    dread=0
```

異変度 0 の「まじめに遊んだ」一夜でこの密度。放置して異変度が上がると間隔が詰まる。
03:00 以降が 1 回しか出ていないのは、03:00 / 03:20 / 03:40 の台本イベントが
前後 7 分ずつ窓を塞ぐため。台本の山場が続く時間帯なので、これでよいと判断した。

## 脅かしチェックリスト

`--scare=<関数名>` で 1 つだけ発火させて撮った。画像は `out/director/scares/`。
撮り方の例:

```bash
godot --path . -- --skip-title --time=23:30 --scare=zabuton_in_hall \
  --screenshot=out/director/scares/zabuton_in_hall.png --pos=3.2,1.6,0.0 --yaw=90 --pitch=-30 --wait=3
godot --path . -- --skip-title --time=23:00 --scare=monitor_figure \
  --cctv-shot=out/director/scares/monitor_figure_cctv.png --wait=5
```

`--scare` は `scares.gd` の関数名をそのまま受ける。引数が要るものは `Director.SCARE_ARGS`、
systems 側を動かすものは `Director._fire_scare` の `match` に別名を用意してある
(`monitor_figure` `tv_face` `coffin_peek` `coffin_face3` `lid_ajar` `iei_face_down` `genkan_figure_visible`)。

| # | 名前 | 発火条件 | 画像 | 判定 |
|---|---|---|---|---|
| 1 | `door_behind` | 廊下で、視界の外にある開いた扉。22:00 以降、異変度で重みが増す | なし | **音のみ**(振り向くと閉まっている演出。`Door.slam()` + VHS グリッチ) |
| 2 | `zabuton_in_hall` | 廊下、22:30 以降。1 夜 1 回 | `zabuton_in_hall.png` | 見える。廊下に赤い座布団が 1 枚 |
| 3 | `zabuton_before_coffin` | 式場、23:00 以降かつ異変度 1 以上。1 夜 1 回 | `zabuton_before_coffin.png` | 見える。棺の前に 3 枚 + 独白 |
| 4 | `chairs_turn_to_coffin` | 式場。異変度で重みが増す。1 回 4 脚 | `chairs_turn_to_coffin.png` | 見える(祭壇の灯りに対するシルエットとして)。**引きの画では向きの差が分かりにくい** |
| 5 | `chair_pulled_out` | 23:00 のモニター後、式場に入ったとき | `chair_pulled_out.png` | 見える。1 脚だけ列から外れている |
| 6 | `whisper` | どこでも。異変度で重みが増す | なし | **音のみ**(背後 0.9m で `whisper_1..3`) |
| 7 | `ceiling_steps` | どこでも | なし | **音のみ** + 独白「天井裏を、何かが歩いている。」 |
| 8 | `attic_meow` | 23:20 以降 | なし | **音のみ**(頭上 2.7m の `cat_meow_*`) |
| 9 | `smoke_sideways` | 式場、線香が燃えているとき。9 秒 | `smoke_sideways.png` | **要調整**。煙の gravity は横向きになるが、暗所では粒子が薄く静止画で判別できない |
| 10 | `handprint` | 式場、00:00 以降かつ異変度 1 以上 | `coffin_peek.png` | **仕様上、小窓を覗いたときだけ見える**。手形は棺の内側にあるので通常視点では出ない。覗きの画は撮れている(顔が見える) |
| 11 | `clock_reverse` | 事務所、02:00 以降。8 秒 | `clock_reverse.png` | 見える。壁掛け時計に針を足して逆回転させている + 独白 |
| 12 | `hall_flicker_shadow` | 廊下、23:00 以降 | `hall_flicker_shadow.png` | 明滅と人影の点滅。**静止画では当たり外れがある**(撮った瞬間が明側だと影が出ない) |
| 13 | `hall_figure` | 03:20 の台帳読了後 | `hall_figure.png` | よく見える。非常灯の緑の下、廊下突き当たりに火車 |
| 14 | `robe_sway` | 湯灌室に入るたび。回を追うごとに速くなる | `robe_sway.png` | よく見える。白装束 + 独白 |
| 15 | `robe_drop` | 湯灌室、03:20 以降の最初の 1 回 | `robe_drop.png` | 見える。ハンガーが空になり、床に装束が落ちている |
| 16 | `paw_prints` | 03:40 | `paw_prints.png` | よく見える。廊下から式場へ約 30 枚 |
| 17 | `paw_prints_outside` | `monitor_ghost_genkan` の後 | `paw_prints_outside.png` | 玄関の外に 5 枚 |
| 18 | `set_second_footsteps` | ドライアイス運搬中 | なし | **音のみ**(1.5m 後ろで歩調に合わせた `step_lino_*`) |
| 19 | `breath_behind` | 同上、独白のあと 1 回 | なし | **音のみ**(`breath_close`) |
| 20 | `tv_player_back` | 控室、23:40 以降 | `tv_player_back.png` | TV はつく。**後ろ姿のオーバーレイは 2 秒で消えるので撮影タイミングがシビア** |
| 21 | `monitor_ghost_genkan` | 事務所、23:00 以降 | `monitor_ghost_genkan.png` | 見える。明るくなったポーチに、こちらへ背を向けた人影。level の 3659be4 で解決 |
| 22 | `vending_cats` | 外、03:00 以降。猫が居るとき | なし | 未撮影(自販機前に猫 5 匹。`Cat.sit_at` 任せ) |
| 23 | `guest_book_self_name` | 受付の芳名帳を 00:00 以降に見たとき | なし | **テキストのみ**(最後の行 + 独白) |
| 24 | `spawn_figure`(23:00 のモニター) | 23:00 | `monitor_figure_cctv.png` | 見える。CCTV に座った人影 |
| 25 | `set_moonlight` | 04:00 の全消灯と同時 | `set_moonlight.png` | 見える。非常灯の緑 + 月明かりで「暗いが輪郭は追える」 |
| 26 | `_body_rises`(director) | 火車エンド直前(灯し直し失敗 / 火車に捕まった瞬間) | `body_rises.png` | 見える。棺が開いて故人が上体を起こす 2 秒のカット |

音のみのものは画面に出ないのが仕様なので、直す対象からは外してある。

## クレジットと到達エンディングの記録

### クレジット

エンディング文の「タイトルへ」を押したあと、`src/director/credits.gd`(`Credits`)が
黒地に明朝で 30 秒かけて下から上へ流す。`advance` で飛ばせる(押しっぱなしで即スキップに
ならないよう、開始 0.8 秒は入力を受けない)。流し終わると `reload_current_scene()`。

文面は `ScriptText.CREDITS`。`docs/script.md`「クレジット(エンディング後)」のままで、
`(あなたの名前)` も指示どおりそのまま置いてある。`[文字列, 文字サイズ]` の配列で、
空文字は余白(サイズが高さ)。

QA は `--credits` でクレジットだけ流せる。

```bash
godot --path . -- --skip-title --credits --screenshot=out/director/credits.png --wait=13
```

### user://progress.cfg(タイトル画面が読む)

`Game.night_ended` で `Endings.save_progress(id)` が書く(`Director._on_night_ended`)。
実体は `~/Library/Application Support/Godot/app_userdata/寝ずの番 - The Wake/progress.cfg`。

```ini
[endings]

portrait=true
kasha=true
morning=true
last="morning"
```

- キーはエンディング ID(`morning` / `kasha` / `substitute` / `portrait`)、値は `true`。
- `last` は最後に到達した ID(文字列)。
- 書く前に `ConfigFile.load()` で既存を読むので、周回しても前の記録は消えない。
- まだ 1 度も到達していないエンディングはキーごと存在しない。
  タイトル側は `cfg.get_value("endings", "morning", false)` のように既定値つきで読むこと。

## 夜明け(04:45〜05:00)

終盤で全消灯したまま朝を迎えると、エンディングのフェードが真っ暗から始まって
落差が出ない。04:45 から 15 ゲーム分かけて夜明けを入れている(`Scares.start_dawn`)。

- 窓とガラス戸の外に青白い `OmniLight3D` を 4 つ置き、energy を 0 から上げる
  (式場の南窓・玄関のガラス戸・事務所の窓・トイレの窓)。定数は `Scares.DAWN_LIGHTS`。
- 月明かりは同時に引いていく。
- VHS の tint を少し寒色(0.88, 0.94, 1.08)へ。
- `crow_morning` を外の位置から 3 回、だんだん大きく。

灯明の暖色と朝の寒色が同じ画に乗るので、式場の色の対比が出る。
`out/director/dawn/shikijo_0444.png`(まだ暗い)と `shikijo_0458.png`(明るい)、
`genkan_0458.png` で確認した。

遺影エンドは 22:30 に 05:00 へ飛ばすので、`Endings._portrait_prologue` で
`dawn_now()` を呼んで即座に朝の光にしている。空の棺が見えないと台本が成立しないため。

## 火車エンド直前の起き上がり

`Director.kasha_catches()` の頭で `_body_rises()` を呼び、棺の蓋が開いて故人が
上体を起こす 2 秒のカットを挟んでから火車エンドへ行く。
プレイヤーの視線は `look_at_point` で棺へ向ける。

**yaw は 90(棺と同じ)が正しい。** npc からは「棺と同じ yaw 90 だと祭壇を向くので -90 に」と
聞いていたが、-90 にすると体が棺の頭側からはみ出す(足が棺の外に出る)。
90 にすると体は棺の中に収まり、起き上がった上体は部屋側を向く
(`body_risen` は起き上がった先で自分の足元を向くので、頭が祭壇側 = +X なら顔は部屋側)。
`out/director/scares/body_rises.png` で確認した。npc の覚え書きと食い違うので共有したい。

QA は `--scare=body_rises` で単体発火できる。

## シグナルの後始末

`Game.reset()` が autoload のシグナル接続をまとめて外すようになったので、director 側で
外す必要は無い。ただし二重に外しても落ちないよう、`Director._exit_tree` で
`Signal.is_connected()` を見てから `disconnect()` している
(`night_ended` / `flag_changed` / `Dread.level_changed` / `Clock.hour_passed`)。

`--reload-test=4` で 30 秒走らせて 6 回再読み込みし、エラーも警告も出ないことを確認した。

## review_1.md の指摘への対応(director 分)

| 番号 | 直したこと |
|---|---|
| H1 | `get_tree().create_timer()` 56 か所を `Events.wait()`(ポーズを尊重)に置換。終盤の灯し直し猶予、丑三つ時の連続消火、エンディングの間、autoplay の待ちがポーズ中に進まなくなった |
| H5 | `apply_past` の猫の起動を `_activate_cats_when_ready()` に変更。物理フレームを 2 回待ってからナビを使う。`--time=23:30` / `04:00` で NavigationServer エラーが出ないことを確認 |
| H6 | `Endings.decide()` に `relight_done` を条件追加。終盤の灯し直しを 3 回終えていないまま 05:00 を迎えたら火車エンド。`_finish_finale()` でフラグを立てる |
| M5 | `_finish_finale()` と代わりエンドで `Door_Hikaeshitsu.enabled` を戻し `Spot` を解放。息子が寝ていない夜は `_install_hikaeshitsu_choice()` 自体を打ち切る |
| M6 | `_wait_event` を `Events.wait_event()` に、`_wait_signal_or_timeout` を接続を必ず外す実装に変更 |
| M4 | `face_off` / `_walk` の `teleport_to` を `NpcUtil.snap()` 経由に。孫娘と息子は teleport せず(`face_off(who, false)`)、式場から館の西側へ行くときは廊下の合流点 `(3, 0, 0)` を経由(`Director.walk_via_hall`)。それでも着けなかったときだけ位置を合わせる。自動プレイ 4 本で「到達できないので打ち切り」が 0 件になった |
| 補足 | `--time=` で過去のイベントの結果を組み立てるあいだ独白を出さない(`Director.monologue()` と `set_quiet()`)。04:58 のスクショに「灯りが全部落ちた。」が残っていた件 |

### ついでに直したもの: 導入中の線香で異変度が溜まる

導入のあいだ `Clock` は止まっているが線香は実時間で燃えるので、会話が長引くほど
`incense_out` が積み上がって異変度が上がっていた(自動プレイの kasha で 54 まで行った)。
`_setup_static()` で `IncenseStand.dread_on_out = 0` にしておき、導入が終わった時点
(`_arm_incense_dread()`)で 1 に戻す。`--time=` 起動時も同じ場所で戻している。

あわせて autoplay のタスク選択を `Tasks.current()`(先頭固定)から優先順表
`Autoplay.TASK_ORDER` に変えた。kasha モードは導入後の線香タスクを飛ばすので、
先頭に居座る線香タスクで以後の用事に進めなくなる問題が出ていた。

## 未解決・判断したこと

### 丑三つ時の長さを 2 分から 20 ゲーム分に変えた

`docs/design.md` の「2 分間、30 秒ごとに線香が消える」をそのまま**実時間 2 分**でやると、
03:00 から 03:40 までを占有して 03:20(金庫)と 03:40(冷凍庫が空)のイベントと重なる。
**20 ゲーム分(speed 1 なら実 60 秒)のあいだに 4 回**へ圧縮した。
実秒は `Clock.seconds_per_game_minute` と `Clock.speed` から計算しているので、倍速でも比率は崩れない。

### 台本による消火は異変度を上げないことにした

停電の復旧後、02:30 の電話、丑三つ時、04:00 の終盤で director が線香を消す。
`IncenseStand.force_out()` は `dread_on_out` ぶん異変度を足すので、
そのまま数えると**まじめに遊んでも朝エンドに到達できなかった**(最初の autoplay で dread=7 → 火車エンド)。

`Director.quench(&"incense_stand")` を用意し、台本の消火のあいだだけ `dread_on_out` を 0 にする。
代わりに掟「線香を絶やさぬこと」の判定を **1 ゲーム時間ごとに線香が消えていれば異変度 +1**
(`Director._on_hour`、22:00 から、終盤は除外)にした。
これで放置すると 03:00 までに 6 に届き、まじめに立て続ければ 0 のままになる。

火車エンドの条件(異変度 6 以上、または猫が棺をまたいだ)はここで担保している。

### 04:00 の全照明消灯に非常灯と月明かりを足した

仕様どおり `Building.set_all_lights(false)` だけにすると画面が完全な黒になり、
「怖い」ではなく「見えない」になって廊下を歩けない。終盤は次の 2 つを足している。

- `Building.set_emergency_lights(true)`(緑の非常灯)。**level が入れたら効く**ように
  `has_method` で守ってある。現時点の `building.gd` にはまだ無いので呼ばれない。
- `Scares.set_moonlight(true)`。窓 7 か所(玄関・事務所・トイレ・廊下 2 か所・勝手口・式場)に
  弱い青い `OmniLight3D`(energy 0.38)。定数は `Scares.MOONLIGHT`。灯し直しに成功したら消す。

非常灯が入ったら月明かりを下げる方向で再調整したほうがよい。

### `Dialogue.say` はプレイヤーが送るまで返らない

`src/ui/hud.gd` の `show_line` はキー入力を待つループなので、独白を `await` すると
そこで台本が止まる。`ev_finale` で `await Dialogue.monologue(...)` を先に書いていたため、
**プレイヤーが独白を送るまで火車が出てこなかった**(撮影で発覚)。
状態変更(消灯・マッチ・火車の起動)を全部済ませてから独白を流す順に直した。
他のイベントを足すときも同じ注意が要る。イベントの結果を独白の後ろに置かないこと。

### CCTV 限定の人影(検証済み)

23:00 の「後列の椅子に座る人影」は render layer 10(`SystemUtil.LAYER_CCTV_ONLY`)に置いてある。
systems の b5db815(`hide_from_cctv` を既定 false にした)でモニター本体が見えるようになり、
**モニターに人影が映ることを確認した**。

- `out/director/18_cctv_feed.png` … `--cctv-shot` で撮った監視映像そのもの。
  灯明に照らされた祭壇の右手前に、椅子に座った人影が写っている。
- `out/director/03_2300_monitor.png` … 事務所から見たゲーム画面。CRT に映像が出ている。
  画面が小さいので人影の判別には上のフィードを使うこと。

調整したこと:

- 人影は `npc_son.glb` の `sit` アニメで座らせ、`Chair_2_3` の席(12.9, 0.2)に置いた。
  あとで引き出される椅子と同じ席なので話がつながる。
- 完全な黒だと灯明だけの式場で消えるので albedo 0.16 + 自発光 0.55 にした
  (`Scares.spawn_figure` の `brightness`)。白く光りすぎないところに合わせてある。
- `Monitor.set_static` を 0.3 から 0.16 に下げた。ノイズが強いと人影が埋もれる。

### そのほか

- **人影の明るさ**: 真っ黒(albedo 0.015)だと灯明だけの式場で何も見えないので、
  CCTV 用の人影だけ albedo 0.16 + わずかな自発光にしてある(`Scares.spawn_figure` の `brightness`)。
- **濡れた足跡**: `Decal` をそのまま置くと暗い床で完全に見えなかった。
  `texture_emission` + `emission_energy = 1.1` + `modulate` で「濡れて光る」ようにし、
  間隔も 1m から 0.42m に詰めて trail に見えるようにした(`Scares._paw_decal`)。
- **祭壇の線香箱**: `Anchor_IncenseBox` の Pickup は `enabled = false` にして飾りにしてある。
  在庫 10 本は director が `Game.set_flag(&"incense_sticks", 10)` で持ち、
  0 になったらバックヤードの棚 `(2.4, 0.95, -6.95)` に補充用の箱を出す。
- **`docs/script.md` に無い行を 1 つ足した**: 社長「式場の蛍光灯は消しとけ。灯明があれば十分だ。」。
  監督の指示で入れたもの。`ScriptText.ADDED_BOSS_LIGHTS` に分けてある。script.md 側にも追記が要る。
- `src/director/_test_director.tscn` は作っていない(任意のため)。
- director はコミットしていない。

## 他担当への依頼

### 0. level — 祭壇スポットの件は解決済み

21:30 の式場で遺影が黒い板に見えた件は、`Light_AltarSpot`(aux 系統)が入った最新の
コミットで撮り直したところ**解決していた**。`out/director/12_iei_close.png` で
遺影の写真(白髪の女性)が見える。`out/director/02_2130_shikijo.png` の引きの画では
遺影が 10px ほどにしかならないので暗い矩形に見えるが、これは 640x360 の解像度の話で不具合ではない。

### 1. player / systems — モニターが見えない(解決済み)

プレイヤーのカメラが layer 10 と 11 を見ないのは仕様で、原因は systems がモニター本体を
layer 11 に置いていたことだった。systems の b5db815 で `hide_from_cctv` が既定 false になり解決。

### 2. npc / level — 社長が受付台の裏から出られない(解決済み)

`Spawn_Boss` が受付台と壁の 0.74m の隙間にあり `NavigationAgent3D` が経路を作れなかった。
level の 40b9d0b でスポーンを受付台の手前へ移し、ナビメッシュが家具を迂回するようになった。
director 側の保険(`_walk` / `face_off` の `teleport_to` フォールバック)はそのまま残してある。

### 3. 監督 — `docs/script.md` への追記(対応済み)

社長の 1 行は 0ebc634 で script.md に追記された。

### 5. level — 玄関の監視カメラが庇の中に埋まっている(解決済み)

level の 3659be4 でカメラを庇の下へ移し、ポーチを明るくしてもらった。
玄関チャンネルに人影が映ることを確認済み(`out/director/scares/monitor_ghost_genkan.png`)。
ポーチが明るくなったぶん人影は暗くしてよくなったので、明るさを 0.42 から 0.2 に下げた。

### 旧: level — 玄関の監視カメラが庇の中に埋まっている

`Anchor_Cam_Genkan (-11.4, 2.56, 2.4)` は玄関ポーチの庇の内側にあるらしく、
モニターの玄関チャンネルは画面の大半が黒い庇で埋まる。
そこへ人影を置いても映らない(`out/director/scares/monitor_ghost_genkan.png`)。
人影自体は正しい場所に出ている(`out/director/scares/_diag_genkan.png` で確認)。

カメラを庇より下(y = 2.2 くらい)へ下げるか、狙いを玄関の内側へ振ってほしい。
ついでにポーチに弱い灯りが欲しい。外が真っ暗なので、そこに立つ人影が映っても分からない。

### 4. level — 非常灯が入ったら月明かりを下げる

971f77c で非常口サインの緑灯が第 3 系統として入った。director は 04:00 で
`set_emergency_lights(true)` を呼ぶようにしてある(`has_method` で守ってある)。
非常灯が入ったので月明かりは 0.38 に戻した(`out/director/scares/set_moonlight.png` で確認)。
