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
| 05:00 | `ev_dawn` | `Endings.decide()` → `Game.end_night()` |

追加の脅かし(`docs/design.md` の一覧)は全部 `scares.gd` に実装してある。
`random_scare()` が異変度・時刻・居場所を見て、80〜160 秒おきに 1 つ選んで撃つ。

## autoplay の使い方

```bash
godot --headless --path . -- --skip-title --autoplay=morning|kasha|substitute|portrait [--speed=8]
```

- `Dialogue.auto_advance = true`、`Clock.speed = speed`、`IncenseStand.burn_seconds` と
  `Candle.burn_seconds` を speed で割る(ゲーム内の長さを保つため)。
- 3 秒 / speed ごとに判断する。優先順は 布団 → 控室の戸 → 電話 → 線香 → 猫 → 現在タスク → ロウソク。
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

### 04:00 の全照明消灯に月明かりを足した

仕様どおり `Building.set_all_lights(false)` だけにすると画面が完全な黒になり、
「怖い」ではなく「見えない」になって廊下を歩けない。
`Scares.set_moonlight(true)` で窓 7 か所(玄関・事務所・トイレ・廊下 2 か所・勝手口・式場)に
ごく弱い青い `OmniLight3D`(energy 0.38)を足している。輪郭が分かる下限に合わせたつもりだが、
**明るさは調整の余地がある**。定数は `Scares.MOONLIGHT`。灯し直しに成功したら消す。

### `Dialogue.say` はプレイヤーが送るまで返らない

`src/ui/hud.gd` の `show_line` はキー入力を待つループなので、独白を `await` すると
そこで台本が止まる。`ev_finale` で `await Dialogue.monologue(...)` を先に書いていたため、
**プレイヤーが独白を送るまで火車が出てこなかった**(撮影で発覚)。
状態変更(消灯・マッチ・火車の起動)を全部済ませてから独白を流す順に直した。
他のイベントを足すときも同じ注意が要る。イベントの結果を独白の後ろに置かないこと。

### CCTV 限定の人影は未検証

23:00 の「後列の椅子に座る人影」は render layer 10(`SystemUtil.LAYER_CCTV_ONLY`)に置いてある。
式場へ行っても見えないことは確認したが、**モニターに映っているかは確認できていない**。
`src/player/player.tscn` の `cull_mask` が layer 11 も落としており、
`src/systems/monitor.gd` がモニター本体を layer 11 に置くので、
CRT モニターそのものがプレイヤーから見えないため(下の「他担当への依頼」1 を参照)。

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

### 1. player(至急) — モニターが見えない

`src/player/player.tscn:24` の `cull_mask = 1047039` が layer 10(`cctv_only`)と
**layer 11(`player_hidden`)の両方**を落としている。
`src/systems/monitor.gd` はモニター本体と画面を layer 11 に置く仕様なので、
**事務所の CRT モニターがプレイヤーの目に映らない**。`1047551`(layer 10 だけ落とす)が正しい。

再現:

```bash
godot --path . -- --skip-title --time=23:00 --screenshot=out/x.png \
  --pos=-6.4,1.35,7.1 --yaw=0 --pitch=-16 --wait=5
```

机の上にモニターが写らない。これが直ると 23:00 の人影も確認できる。

### 2. npc / level — 社長が受付台の裏から出られない

`Spawn_Boss (-8.0, 0, -3.7)` が受付台(z = -2.95、奥行 0.62)と壁(z = -4)のあいだの
0.74m の隙間にある。`NavigationAgent3D` が経路を作れず、導入で一歩も動かない。

```
[npc] Boss が (-7, 0.2, 5.2) へ到達できないので打ち切り(残り 10.96m)
[npc] Boss が (15.2, 0.2, -1.9) へ到達できないので打ち切り(残り 22.35m)
[npc] Boss が (-9.6, 0.2, 0) へ到達できないので打ち切り(残り 4.52m)
```

`(-8.0, 0, -2.2)` あたり(受付台の手前)へ移すか、ナビメッシュを隙間まで通してほしい。
director 側は `Director._walk` に「到達できなければ `teleport_to` で位置だけ合わせる」保険を入れてあるが、
社長が瞬間移動するので本来は直したい。

### 3. 監督 — `docs/script.md` への追記

上に書いた社長の 1 行を script.md に足してほしい。
