# review_1 — 統合後レビュー(実プレイで起きる不具合)

レビュー担当。実装はしていない。対象は `src/` 全体(autoload / main / player / ui / fx / level / systems / npc / director)。
スナップショットは 2026-09-23、`work/v1` の `3659be4` + `src/npc/` の未コミット変更。
レビュー中に npc の 5 ファイルが更新されたので、npc の行番号だけは作業ツリーの現物を見ている。

再現に使ったコマンドはすべて所見の中に書いた。検証結果と実際に観測したログは末尾にまとめてある。

---

## High

### H1. ポーズ中も台本が進む(`get_tree().create_timer()` は既定でポーズを無視する)

**ファイル**: `src/autoload/events.gd:34-36`、`src/director/timeline.gd`(25 箇所)、`src/director/director.gd`(14 箇所)、ほか非テストで計 88 箇所

**何が起きるか**
`SceneTree.create_timer(time_sec, process_always := true, ...)` の第2引数は既定が `true`、つまり**ポーズを無視して進む**。
ゲーム内の待ちはほぼ全部この形で書かれているので、ポーズメニューを開いているあいだも台本は走り続ける。

- `timeline.gd:668` — 終盤の灯し直しの猶予 18 秒。ポーズ中に経過して灯明が消え、火車が `resume()` する。
- `timeline.gd:541-562` — 丑三つ時の 4 回の消火がポーズ中に全部進む。
- `director.gd:793` — `kasha_catches()` の 1.6 秒後に `finish(ENDING_KASHA)`。**ポーズメニューの上にエンディングが始まる**(→ H2 に続く)。
- `timeline.gd:351-355` — 息子のノックと入場。
- `door.gd:98` — `auto_close_after` の自動閉扉。

`Clock` は autoload(`PROCESS_MODE_INHERIT` = pausable)なので時刻は止まる。
つまり「時計は止まっているのにイベントだけ進む」という一番ややこしい壊れ方をする。

**根拠**(別プロジェクトで Godot 4.7.1 の挙動を確認)
```
paused=true
create_timer(0.5) returned after 423 ms while paused=true
```
`src/ui/hud.gd:563` では `if not get_tree().paused:` で明示的にタイプライタを止めているので、
作者は HUD の `_process` がポーズ中も回ることは把握している。待ちのほうには同じ手当てが無い。

**直し方の案**
`Events` にポーズを尊重するヘルパを足し、台本側の `await get_tree().create_timer(x).timeout` を全部そこへ通す。

```gdscript
# events.gd
func wait(seconds: float) -> Signal:
    return get_tree().create_timer(seconds, false).timeout   # process_always = false
```
演出用(フェード、エンディング)だけは今のまま `true` にしておく。

**担当**: 監督(autoload に `Events.wait()` を追加)→ director / systems / npc が差し替え

---

### H2. ポーズ中にエンディングへ入ると、再開後もゲームがポーズしたままになる

**ファイル**: `src/ui/hud.gd:870` / `:875`、`src/director/endings.gd:144`、`src/autoload/game.gd:56-76`

**何が起きるか**
`get_tree().paused` を `false` に戻すのは `hud.gd:875` の `_close_pause()` だけ。
`Game.reset()` も `main.gd` の `_ready()` / `start_game()` もこのフラグを触らない。

H1 のせいでポーズ中にエンディングが始まりうる。`ending.tscn` は `PROCESS_MODE_ALWAYS`(`ending.gd:29`)なので
ポーズ中でも最後まで再生され、`endings.gd:144` の `get_tree().reload_current_scene()` まで到達する。
このとき `paused` は `true` のまま。再読込後のタイトル→「はじめる」で始まった夜は、
プレイヤーもクロックも NPC も動かない。Esc を2回押せば復帰できるが、そこに気づける作りではない。

**再現手順**
1. 04:00 の終盤に入り、火車に捕まる(`caught` が出る)。
2. `director.gd:793` の `await get_tree().create_timer(1.6).timeout` のあいだに Esc を押す。
3. ポーズメニューの上でエンディングが再生され、タイトルへ戻る。
4. 「はじめる」を選ぶ。操作を受け付けない。

**直し方の案**
`Game.reset()` の先頭で `get_tree().paused = false` を入れる(reset は `main.start_game()` の最初に必ず走る)。
併せて `Endings.run()` の入口でも落とす。H1 を直せばこの経路自体が塞がる。

**担当**: 監督(`game.gd`)+ player(`hud.gd`)

---

### H3. 独白が2つ同時に走ると、片方が画面に出ないまま消える(04:00 で必ず起きる)

**ファイル**: `src/autoload/dialogue.gd:24-37`、`src/ui/hud.gd:663-684`、`src/director/timeline.gd:622` / `:649`、`src/director/director.gd:511-515`

**何が起きるか**
`Dialogue` にはキューが無い。`say()` は `busy` を立てるだけで、既に表示中かどうかを見ない。
`hud.show_line()` は `_dlg_active` / `_mono` / `_dlg_total` という**1組しか無い状態**を書き換えるので、
2本目の `show_line` が始まると1本目の文字列は描画される前に上書きされ、
送りキー1回で両方のループが同時に抜ける。結果、**1行まるごと表示されずに消える**。

04:00 の終盤で確定的に起きる:

```gdscript
# timeline.gd:621-622
if inc:
    dir.quench(&"incense_stand")        # → incense_out → director._on_incense_out()
                                        #   → Dialogue.monologue(M_INCENSE_OUT)  ← 1本目
...
# timeline.gd:649
await Dialogue.monologue(ScriptText.M_LIGHTS_OUT)   ← 2本目(同じフレームで上書き)
```

**再現手順**
```bash
godot --path . -- --skip-title --time=04:00 \
  --screenshot=out/review/finale_w0.35.png --pos=15.2,1.6,-0.5 --yaw=-90 --wait=0.35
```
`--wait` を 0.35 / 1.0 / 2.5 のどれにしても画面に出るのは「灯りが全部落ちた。」だけで、
`docs/script.md` にある「線香が消えた。」は一度も描画されない(送り入力はしていない)。
自動プレイのログでも同じ順で2行が同一ゲーム分に出ている:

```
[dir] 04:00 ev_finale
[event] 04:00 incense_out {  }
[say] : 線香が消えた。
[event] 04:00 candle_out {  }
[say] : 灯りが全部落ちた。
```
(自動プレイは `auto_advance = true` で `show_line` を通らないため、ここでは両方 print される)

同じ衝突は `on_blackout_reveal`(`timeline.gd:337` の消火 → `M_IEI`)、
`ev_phone_wet`(`:518` の消火 → `M_PHONE_WET_AFTER`)、丑三つ時の4連続消火でも起きる。

**直し方の案**
`Dialogue` に 1 本のキューを持たせ、`say()` は前の行が終わるまで待ってから `ui.show_line()` を呼ぶ。

```gdscript
var _queue_tail: Signal   # あるいは単純に  while busy: await finished
func say(speaker: String, text: String) -> void:
    while busy:
        await finished
    busy = true
    ...
```
`ev_finale` のように「状態変更を先に済ませてから独白」という今の書き方はそのままでよくなる。

**担当**: 監督(`dialogue.gd`)

---

### H4. 字幕が出たままプレイヤーが動ける / E で別の Interactable を押せる

**ファイル**: `src/autoload/dialogue.gd:36`、`src/ui/hud.gd:944-945`、`src/player/player.gd:132-138`

**何が起きるか**
プレイヤーのロック判定は
`player.gd:133` の `Dialogue.busy` と `hud.blocks_player()`(= `_note_open or _clip_open or _paused or _choice_open`)の2つだけで、
**HUD の `_dlg_active` を見ていない**。

H3 のとおり 2 つの `Dialogue` 呼び出しが重なると、先に終わったほうが `busy = false` にしてしまう。
`show_note` と `show_line` が重なった場合が分かりやすい:

1. 宿直日誌(`Note`)を読む → `show_note` が `_note_open = true`、`Dialogue.busy = true`。
2. 読んでいる最中に `Director._process` のランダム脅かしが発火する。
   `_can_scare()`(`director.gd:722-730`)は `Dialogue.busy` を**見ていない**ので、
   `ceiling_steps`(`scares.gd:405`)や `clock_reverse`(`scares.gd:475`)が `Dialogue.monologue()` を撃つ。
   `ceiling` は `random_scare()` の「どこでも出るもの」プール(`scares.gd:732`)に常に入っている。
   宿直日誌は事務所(`POS_OFFICE_NOTE`)にあり 01:30 から読める。`clock` は 02:00 から事務所プールに入る(`scares.gd:746`)ので、
   「事務所で日誌を読んでいる最中に独白が割り込む」は普通に起きる状況。
3. 送りキーを1回押す。`hud.gd:601-609` は `_note_open` を先に処理するので手紙だけ閉じる。
   → `note()` が返って `busy = false`。`_dlg_active` は true のまま字幕が残る。
4. `blocks_player()` は全部 false なので**プレイヤーが歩き出せる**。
   `advance` と `interact` はどちらも E に割り当たっている(`project.godot`)ので、
   字幕を送るつもりの E が目の前の Interactable を押す。

**直し方の案**
- `hud.blocks_player()` / `wants_cursor()` に `_dlg_active` を足す。
- `Director._can_scare()` に `if Dialogue.busy: return false` を足す(手紙を読んでいる最中に脅かしを撃たない)。
- 根治は H3 のキュー化。

**担当**: player(`hud.gd`)+ director(`_can_scare`)+ 監督(`dialogue.gd`)

---

### H5. `--time=23:20` 以降で起動すると NavigationServer のエラーが必ず出る

**ファイル**: `src/director/timeline.gd:76-80`(`apply_past` の `_activate_cats()`)、`src/director/director.gd:453`、`src/npc/npc_util.gd:170`

**何が起きるか**
`apply_past(m)` は `m > 140`(= 23:20)で `_activate_cats()` を呼ぶ。
これは `Director._boot()` の中、つまり**起動 1 フレーム目**に走る。
`NavigationRegion3D` のマップはまだ 1 度も同期されていないので `NavigationServer3D.map_get_closest_point()` が失敗し、
猫の最初の目的地が不正な値になる。

**再現手順**(ウィンドウ / headless どちらでも出る)
```bash
godot --path . -- --skip-title --time=23:30 --screenshot=out/review/t_23-30.png --wait=1.0
```
`--time=22:00` では出ない。`23:30` / `01:00` / `03:30` / `04:00` で毎回出る。

```
ERROR: NavigationServer navigation map query failed because it was made before first map synchronization.
	NavigationServer 'map_changed' signal can be used to receive update notifications.
	NavigationServer 'map_get_iteration_id()' can be used to check if a map has finished its newest iteration.
   at: get_closest_point (modules/navigation_3d/nav_map_3d.cpp:197)
   GDScript backtrace (most recent call first):
       [0] snap (res://src/npc/npc_util.gd:170)
       [1] walk_to (res://src/npc/npc_base.gd:222)
       [2] go_to (res://src/npc/npc_base.gd:258)
       [3] _state_approach (res://src/npc/cat.gd:257)
       [4] _run_state (res://src/npc/cat.gd:209)
       [5] _set_state (res://src/npc/cat.gd:190)
       [6] set_target_entry (res://src/npc/cat.gd:117)
       [7] _activate_cats (res://src/director/timeline.gd:241)
       [8] apply_past (res://src/director/timeline.gd:80)
       [9] apply_state_for_time (res://src/director/director.gd:453)
       [10] _boot (res://src/director/director.gd:93)
```

`--time` は撮影と QA の主要経路なので、ここが毎回赤いと本物のエラーが埋もれる。

**直し方の案**
`apply_past` の猫の起動だけ `await NavigationServer3D.map_changed` か、
最低でも `await get_tree().physics_frame` を 1 回挟んでから呼ぶ。
`NpcUtil.snap()`(`npc_util.gd:167-173`)のガードは
```gdscript
var p := NavigationServer3D.map_get_closest_point(world.navigation_map, pos)   # ← ここで既にエラーが出る
if p.is_equal_approx(Vector3.ZERO) and pos.length() > 1.0:
	return pos
```
と**問い合わせた結果**を見ているので、エンジンのエラー出力は止まらない。
問い合わせる前に `NavigationServer3D.map_get_iteration_id(world.navigation_map) > 0` を確かめる形に変える。

**担当**: director(呼ぶ側)+ npc(`NpcUtil.snap`)

---

### H6. 「朝」エンドが灯し直しの成功を条件にしていない

**ファイル**: `src/director/endings.gd:18-25`、`src/director/timeline.gd:770-774`

**何が起きるか**
`docs/design.md` v0.2「エンディング条件」は

| 名 | 条件 |
|---|---|
| 朝 | **04:40 の灯し直しに成功。** 異変度 < 6 |

だが `decide()` は灯し直しを一切見ない:

```gdscript
func decide() -> StringName:
	if Game.get_flag(&"kasha_took_son", false):  return Game.ENDING_SUBSTITUTE
	if Game.get_flag(&"caught_by_kasha", false): return Game.ENDING_KASHA
	if Dread.is_doomed() or Game.get_flag(&"cat_crossed_coffin", false): return Game.ENDING_KASHA
	return Game.ENDING_MORNING
```

04:00 の終盤でマッチを取りに行かず、火車から逃げ回るだけで 05:00 を迎えると、
`ev_dawn` → `decide()` → **朝エンド**になる。
04:00→05:00 は 60 ゲーム分 = 実 3 分。`_on_hour`(`director.gd:543-550`)は
`finale_running()` のあいだ異変度を足さないので、異変度も上がらない。
山場2を丸ごと飛ばして最良エンドに入れてしまう。

**再現方法**
`--time=04:00` で起動し、事務所へ行かずに 3 分逃げる。
火車は**見られていない間は 1.2 m/s**(`kasha.gd:23` `unseen_speed`)、プレイヤーは 2.5 m/s(`player.gd:30`)なので、
振り返らずに歩き続けるだけで距離は開く一方になる。捕まらずに 05:00 を迎えれば朝エンド。
灯し直し 0 回のまま最良エンドに入れる。

**直し方の案**
`decide()` に `_finale_relights >= 3`(または `Game.get_flag(&"relight_done")`)を条件として足す。
満たしていないときは火車エンドに倒す。`ev_finale` が始まる前に夜が終わる経路は無いので、
「終盤に入ったのに灯し直していない」は常に失敗として扱ってよい。

**担当**: director

---

### H7. 猫が開口部まで到達できず、23:20 以降の「猫」がまるごと起きない

**ファイル**: `src/npc/cat.gd:244-277`(`_state_approach`)、`src/level/furnish_b.gd:400-404`(`Spawn_Cat1..5`)、
`src/npc/npc_util.gd:19-23`(`OPENINGS` の `Door_Backyard`)

**何が起きるか**
猫は `APPROACH` で開口部の外側へ歩くが、スポーンから 1〜3m しか進まずに打ち切られる。
`cat.gd:275-277` は

```gdscript
# 開口部の外側に着けていないなら、遠くの扉の音を鳴らさずに引き返す
if _flat_distance(global_position, entry["outside"]) > 1.6:
	_set_state(State.OUTSIDE_IDLE)
	return
```
なので、**引っ掻き音すら鳴らずに黙って引き返す**。
design.md v0.2 の 23:20「勝手口に猫。開いていれば侵入。追い出しを教える」が画面にも音にも出ない。

**根拠**(自動プレイ 8 本 = 修正前 4 本 + 修正後 4 本の合計)

| 状態遷移 | 修正前 4 本 | 修正後 4 本 |
|---|---|---|
| `OUTSIDE_IDLE` | 44 | 47 |
| `APPROACH` | 25 | 27 |
| `ENTERING` 以降 | 0 | 0 |

`cat_entered` / `cat_shooed` / `cat_crossed_coffin` は 8 本すべてで **0 回**。

打ち切りログ(修正後 4 本):
```
[npc] Cat1 が (0.000000, 0.100000, -9.000000) へ到達できないので打ち切り(残り 17.10m / 20.16m×2 / 21.33m / 21.35m / 23.24m)
[npc] Cat2 が (0.700000, 0.100000, 5.000000) へ到達できないので打ち切り(残り 24.61m)
[npc] Cat2 が (13.000000, 0.100000, 4.900000) へ到達できないので打ち切り(残り 36.04m)
[npc] Cat3 が (0.700000, 0.100000, 5.000000) へ到達できないので打ち切り(残り 16.66m)
[npc] Cat5 が (0.000000, 0.100000, -9.000000) へ到達できないので打ち切り(残り 22.70m)
```
`Spawn_Cat1` は `(-13.4, 0, 7.4)`、勝手口の外側は `(0, 0, -9)` で直線 21.2m。
残り 20.16m で打ち切っているので、**1m ほどしか進んでいない**。
`Spawn_Cat3` は `(1.4, 0, -9.2)` で勝手口の真ん前(1.4m)なのに、
トイレ窓 `(0.7, 0, 5)` へ向かわせると 16.66m 残して止まる(直線 14.2m なので目標から遠ざかっている)。

レビュー中に npc 担当が代替開口部への切り替えを入れたので、いまは
```
[cat] Cat1: Door_Backyard へ行けないので Window_Shikijo に切り替え   ×5
[cat] Cat2: Window_Shikijo へ行けないので Door_Genkan に切り替え
```
のように目標を変えるが、どれも同じく届かないので結果は変わらない。

**未確認**: 自動プレイのボットは 21:20 に勝手口、22:00 に式場の窓を閉めるので、
「開口部が全部閉まっているから入れない」のは仕様どおりでもある。
開口部を開けたままにした状態で猫が `ENTERING` まで行けるかは未検証。
ただし**開口部まで届かないこと自体**は上のログのとおり確定している。

**確かめ方**
```bash
godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=cat_enter
```
このテストシーンでは猫が棺まで行けている(npc 申し送りのスクリーンショット)ので、
差は本番の外周ナビメッシュか `Spawn_Cat*` の位置にある。

**効いてくる範囲**
- 掟3「猫を入れぬこと」と「猫を追い出す」タスクが一度も発生しない。
- `cat_crossed_coffin` は火車エンドの 2 条件のうちの片方(design.md v0.2 の表)。この経路が通っていない。

**担当**: level(外周ナビメッシュと `Spawn_Cat*`)+ npc

---

## Medium

### M1. 受話器を置き忘れると 22:30 / 02:30 の電話が丸ごと飛ぶ

`src/systems/phone.gd:87-89`

```gdscript
func ring(timeout: float = 30.0) -> void:
	if is_ringing or off_hook:
		return
```

鳴っていない受話器は `_interact` → `pick_up()` で上げられる(`phone.gd:121-127`)。
上げたまま放置すると `ev_phone_silent` / `ev_phone_wet` の `ph.call(&"ring", 30.0)` が無言で帰る。
呼び出し側(`timeline.gd:164-172` / `:499-507`)は戻り値を見ずに `dir.pending_call` を立てるだけなので、
ベルも鳴らず `phone_missed` も出ず、02:30 の「線香が消える」演出ごと消える。

直し方: `ring()` が `off_hook` のときは `hang_up()` してから鳴らす。もしくは `ring()` を bool にして
呼び出し側でリトライする。

**担当**: systems(+ director)

---

### M2. 運搬物が黙って消える(「両手が塞がる」が効いていない)

`src/player/player.gd:397-403`、`src/systems/sink.gd:16-22`、`src/systems/freezer.gd:115-132`

`give_item(name, carried := true)` は `carried_item` を無条件に上書きする。
`Sink._can_interact` は未オーバーライドで常に true、`Freezer._can_interact` は
「そのアイテムを持っていないか」しか見ない。したがって

- ドライアイスを持ったまま流しで水を汲む → ドライアイスが消える
- 水を持ったまま冷凍庫を開ける → 水が消える

`docs/design.md` §3「運搬中は両手が塞がり他の操作不可」と食い違う。
03:40 以降は冷凍庫が空になるので、取り直しが効かない時間帯がある。

直し方: `Player.give_item(carried = true)` を `carried_item == &""` のときだけ通し、
`Interactable` 側は `player.is_carrying()` で `_can_interact` を落とす。

**担当**: player(+ systems)

---

### M3. 監視モニターの SubViewport が常時描画

`src/systems/monitor.gd:78`

```gdscript
_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
```

256×192 とはいえ式場と玄関のジオメトリを毎フレーム描き直す。
同じシーンで視点だけ変えて計測した値:

| 視点 | fps | draw calls | objects |
|---|---|---|---|
| トイレで壁を向く(21:00) | 67 | 2695 | 2735 |
| トイレで壁を向く(04:00・全消灯) | 65 | 2695 | 2735 |
| 事務所からモニター | 80 | 2805 | 2845 |
| 式場から祭壇 | 95 | 2158 | 2198 |

何も見えない壁を向いていても draw call が 2700 出ている(`RENDERING_INFO_TOTAL_*` は全ビューポートの合計)。
**未確認**: この定数ぶんがモニターのぶんかどうかは切り分けていない。
確かめるには `monitor.gd:78` を一時的に `UPDATE_DISABLED` にして同じコマンドを回し、差分を見るのが早い。

```bash
godot --path . -- --skip-title --pos=0.2,1.6,3.2 --yaw=0 --screenshot=out/review/perf.png --wait=3
```

直し方の案: `Events.on(&"player_entered_room", ...)` で `Room_Office` に居るときだけ
`UPDATE_ALWAYS`、それ以外は `UPDATE_DISABLED` にする。`--cctv-shot` のときだけ常時 on に戻す。

**担当**: systems

---

### M4. 導入で孫娘が式場から一歩も動かずに消える

`src/npc/npc_base.gd:459-480`(`leave_via`)、`src/director/director.gd:976-984`(`face_off` の `teleport_to`)、
`src/npc/npc_base.gd:382-390`(`teleport_to`)

**何が起きるか**
21:10 の孫娘は台詞のあと `leave_via_genkan()` で玄関から帰るはずが、
玄関内側 `(-9.6, 0, 0)` への経路が作れずに打ち切られ、**式場の後列に立ったまま `despawn()` でフェードアウトする**。
扉の開閉音だけが遠くで鳴り、`npc_left{granddaughter}` はそのまま出る。

**根拠**(自動プレイ 4 本すべてで再現。`morning` のログ抜粋)
```
[say] ひかり: 今夜、よろしくお願いします。
[say] ひかり: 猫が来ても、叩かないであげてください。
[npc] Granddaughter が (-9.600000, 0.200000, 0.000000) へ到達できないので打ち切り(残り 21.77m)
[event] 21:00 door_opened { "door": &"Door_Genkan" }
[event] 21:00 door_closed { "door": &"Door_Genkan" }
[event] 21:00 npc_left { "name": &"granddaughter" }
```
社長の `leave_via_genkan` は同じ夜で成功している(`21:57 npc_left {boss}`、打ち切りログ無し)ので、
`leave_via` 自体ではなく孫娘の**立ち位置**の問題。

`Spawn_Granddaughter` は `(10.35, 0, 1.1)`(`furnish_b.gd:163`)で、玄関内側までは約 19.98m。
打ち切り時の残りが 21.77m なので、**目標から遠ざかった位置から歩き出して 1m ほどで詰まっている**。
台詞の直前に `Director.face_off()` が走り、プレイヤー(このとき棺の前に居る)から 1.8m の点へ
`teleport_to` する(`director.gd:984`)。`NpcBase.teleport_to()` は

```gdscript
func teleport_to(pos: Vector3, yaw_deg: float = NAN) -> void:
	global_position = pos      # ← ナビメッシュに寄せていない
```
と**スナップせずに座標を入れる**だけなので、祭壇まわりのナビメッシュの外に降りると
以後 `walk_to()` が経路を作れない。`Director._walk()`(`director.gd:1015`)の保険も同じ `teleport_to` を使う。

**直し方の案**
`NpcBase.teleport_to()` の中で `NpcUtil.snap(get_world_3d(), pos)` を通してから代入する。
`face_off` / `_walk` の目標点も同じく snap してから渡す。

**未確認**: 祭壇の手前がナビメッシュから抜けているかは level 側で要確認。
`_test_tour.gd:278` に `Spawn_Granddaughter → Anchor_Coffin` の経路チェックがあるので、そこに
「棺の前 1.8m → 玄関内側」を足すと切り分けられる。

**担当**: npc(`teleport_to`)+ director(`face_off`)+ level(ナビメッシュ)

**担当**: npc + level

---

### M5. 終盤に控室の戸が調べられなくなったまま戻らない

`src/director/timeline.gd:718-727` / `:697-712`

```gdscript
func _install_hikaeshitsu_choice() -> void:
	...
	d.enabled = false                       # Door の Interactable を殺す
	_hikaeshitsu_spot = Scares.Spot.make(...)
```

`_finish_finale()` は `_hikaeshitsu_spot` を消さず、`Door_Hikaeshitsu.enabled` も戻さない。
04:40 の収束後(線香を最後に1本立てるあいだ)、控室の戸は開けられず、
選択肢用の `Spot` だけが残る。息子が寝ていない夜だと `_ask_hikaeshitsu` は
`i == 1` でも何もせずに返る(`:742-744`)ので、何度も同じ選択肢が出る。

直し方: `_finish_finale()` で `_hikaeshitsu_spot.queue_free()` と `d.enabled = true` を戻す。

**担当**: director

---

### M6. 待ちヘルパが接続を外さない

`src/director/director.gd:1028-1035`(`_wait_event`)、`:824-831`(`_wait_signal_or_timeout`)

```gdscript
func _wait_event(name: StringName, timeout: float = 120.0) -> void:
	var done := [false]
	var cb := func(_d): done[0] = true
	Events.on(name, cb)          # ← 外さない
```

`Events.on()` は `Events.event` にラムダを繋ぎっぱなしにする API なので、
`_wait_event` を呼ぶたびに購読が1つ増え、以後すべてのイベントでそのラムダが回る。
導入の `_wait_event(&"incense_lit", 600.0)` は1回だけなので今は実害が小さいが、
`Game.reset()` の一括解除に頼る設計になっているぶん、増えると気づけない。
`_wait_signal_or_timeout` はタイムアウト側で `CONNECT_ONE_SHOT` の接続が残る。

直し方: `Events` に `once(name, callable)` を足し、発火時に自分で `disconnect` する。

**担当**: 監督(`events.gd`)+ director

---

### M7. HUD 既定の掟が `docs/script.md` と違う

`src/ui/hud.gd:20-27`

```gdscript
@export var rules: PackedStringArray = [
	"一、線香を絶やさぬこと",
	"二、灯明を絶やさぬこと",        # 正本は「一、」
	"三、猫を建物に入れぬこと",      # 正本は「一、猫を入れぬこと」
	"四、棺の小窓を開けぬこと",
	"五、眠らぬこと",
]
@export var clipboard_title: String = "やすらぎ会館　宿直心得"   # 正本は「寝ずの番 心得」
```

実行時は `Director._setup_static()` が `hud.set_rules(ScriptText.rules())` で必ず上書きするので
画面には出ない。ただしクリップボードの見出しは上書きされないので
`clipboard_title` はそのまま表示される。`docs/script.md` の掟ブロックは
見出しが「寝ずの番 心得」、末尾に「やすらぎ会館」。

`ScriptText` 側の5行は `docs/script.md` と一字一句一致していることを確認済み(下の検証結果を参照)。

**担当**: player(`hud.gd`)

---

## Low

### L1. `hud.gd:124` が headless でエラーを出す

```
ERROR: Not supported by this display server.
   at: keyboard_get_keycode_from_physical (servers/display/display_server.cpp:1224)
   GDScript backtrace (most recent call first):
       [0] _key_for (res://src/ui/hud.gd:124)
       [1] _ready (res://src/ui/hud.gd:111)
```
自動プレイ 4 本すべてで 1 回ずつ出る。`DisplayServer.get_name() == "headless"` のときは
`OS.get_keycode_string(kc)` にフォールバックすればよい。CI のログが汚れるだけなので Low。
**担当**: player

### L2. 線香 / ロウソクのタイマーが `Clock.speed` を見ない

`src/systems/incense_stand.gd:117-128`、`src/systems/candle.gd:123-133` は素の `delta` で減る。
`--debug` の F2/F3(`main.gd:196-197`)で時計だけ 10倍・60倍になるので、
デバッグ中は線香が1ゲーム時間どころか丸一夜もつ。自動プレイは `burn_seconds` を速度で割って辻褄を合わせている。
デバッグ専用の不整合なので Low。**担当**: systems

### L3. `Interactable.interact()` が `one_shot` でなくても `_used` を立てる

`src/interact/interactable.gd:45-50`。今は害が無いが、あとから `one_shot = true` に変えると
「すでに1回押したことがある」扱いで最初から使えなくなる。`if one_shot: _used = true` にしておくほうが安全。
**担当**: 監督

### L4. クリップボードと字幕が重なって表示される

`src/ui/hud.gd:745-759`(`show_note`)と `:809-817`(`toggle_clipboard`)はお互いを閉じない。
クリップボードを開いている最中にランダム脅かしの独白が出ると、クリップボードの上に字幕が重なる。
送りキーは `_clip_open` を先に処理する(`:625-630`)ので進行は詰まらない。表示だけの問題。
**担当**: player

### L5. 終了時のリーク

```
WARNING: 28 ObjectDB instances were leaked at exit   (kasha)
WARNING: 25 ObjectDB instances were leaked at exit   (substitute)
WARNING: 22 ObjectDB instances were leaked at exit   (morning)
WARNING: 12 ObjectDB instances were leaked at exit   (portrait)
ERROR: 6〜8 resources still in use at exit
```
`godot --headless --path . --quit`(何も遊ばない)の時点で `ObjectDB 2 / resources 1` が出ているので、
下地は systems / npc より前からある(models 申し送り 2 番、systems 申し送り 4 番)。
夜を通すと 12〜28 まで増えるので、`Scares._spawned` や `Coffin` の自作マテリアルなど
夜の途中で生成するノードが残っている可能性がある。**未確認**。
**担当**: 監督(切り分け)

---

## 確認して問題なかったところ

- **タイトルへ戻って再開する経路にエラーは無い**。`--qa-restart` でシーンを再読込しても
  SCRIPT ERROR は 0 件、再読込後の描画負荷も同一(下の検証結果を参照)。
  `Game.reset()` の autoload シグナル一括解除(`game.gd:62-86`)は意図どおり効いている。
  ただし `get_tree().paused` だけは対象外(→ H2)。
- **`docs/script.md` と `src/director/script_text.gd` のテキストは一致**している。
  収集物4件(本文)、エンディング4種(本文・見出し)、社長・孫娘・息子の全台詞、独白20行、芳名帳を
  Python で機械的に突き合わせて差分ゼロ。`ADDED_BOSS_LIGHTS` は script.md 側にも `0ebc634` で追記済み。
  script_text に無いのは布団の選択肢(`futon.gd:9-11` の `@export`)とタイトル画面の文字列(`title.gd`)だけで、
  どちらも `@export` なので director から差し替えられる形になっている。
- **線香 180 秒 / ロウソク 720 秒**(`incense_stand.gd:17` / `candle.gd:17`)は design.md v0.2 と一致。
- **走れない**: `project.godot` の InputMap に走る操作が無く、`Player.walk_speed = 2.5` のみ(`player.gd:30`)。
  運搬中は `carry_speed = 2.0` に落ちる。
- **追いかけっこは1回**: `Kasha.activate()` は `ev_finale`(`timeline.gd:642-645`)からしか呼ばれない。
  灯し直しのあいだの `retreat()` / `resume()` は design.md の「各回の間に火車が追跡」に沿っている。
- **レイヤー/マスク**は仕様どおり。world=1 / interact=2 / player=4(`player.gd:82-83`)/ npc=8。
  部屋の `Area3D` は layer 0 / mask 4(`building.gd:577-578`)。
  `Interactable` は `_ready` で layer 2 / mask 0 を強制(`interactable.gd:24-27`)。
  プレイヤーのレイキャストは mask 2 + `collide_with_areas`(`player.gd:317-319`)で、
  そのあと mask 1 で遮蔽を確かめている(`player.gd:335-342`)ので壁越しには掴めない。
- **猫が棺をまたぐ判定**は `Coffin._on_cat_zone_entered`(`coffin.gd:210-231`)が group `cat` でフィルタしており、
  `cat_crossed_coffin` フラグも立つ。`Endings.decide()` の火車条件(`endings.gd:23`)はここで担保されている。
- **線香の在庫切れ**で詰むことは無い。`Director.enable_stock_box()`(`director.gd`)は
  `is_instance_valid` を見て毎回置き直すので、10本使い切るたびに裏の棚へ補充が出る。
- **`Coffin.allow_open_window` は既定 false**。00:30 に息子へ開けさせたときだけ true にして、
  `_son_allowed`(`timeline.gd:403-415`)がすぐ false に戻す。掟4は守られている。
- **マウスキャプチャ**は `Player._sync_mouse_mode()`(`player.gd:548-556`)が毎フレーム
  `hud.wants_cursor()` と突き合わせるので、手紙/選択肢/クリップボード/ポーズから戻れなくなることは無い。

---

## autoplay 4 本の結果

```bash
godot --headless --path . -- --skip-title --autoplay=morning|kasha|substitute|portrait --speed=8
```
レビュー中に npc 担当が `src/npc/` を更新したので、**修正前と修正後で 2 回**回した。
どちらも 4 本同時実行・全部 exit code 0・SCRIPT ERROR 0 件。

### 1 回目(`src/npc/` 更新前)

```
AUTOPLAY RESULT ending=morning    dread=0 minutes=480   AUTOPLAY OK morning
AUTOPLAY RESULT ending=kasha      dread=7 minutes=440   AUTOPLAY OK kasha
AUTOPLAY RESULT ending=substitute dread=0 minutes=480   AUTOPLAY OK substitute
AUTOPLAY RESULT ending=portrait   dread=0 minutes=90    AUTOPLAY OK portrait
```

### 2 回目(`src/npc/` 更新後)

```
AUTOPLAY RESULT ending=morning    dread=0 minutes=480   AUTOPLAY OK morning
AUTOPLAY RESULT ending=kasha      dread=7 minutes=445   AUTOPLAY OK kasha
AUTOPLAY RESULT ending=substitute dread=0 minutes=480   AUTOPLAY OK substitute
AUTOPLAY RESULT ending=portrait   dread=0 minutes=90    AUTOPLAY OK portrait
```

`director_notes.md` の記録(portrait が minutes=91)とほぼ一致。

**この 4 本が緑でも、この レビューの High はどれも拾えない。** 理由:

- `Autoplay` は `Dialogue.auto_advance = true` にするので `hud.show_line()` を通らない。
  → H3 / H4 は原理的に検出できない。
- `_decide()` は `Interactable.interact()` を直接呼び、`Player.teleport` で移動する(`autoplay.gd:114-124`)。
  → レイキャスト、プロンプト、長押し、持ち物の上書き(M2)を通らない。
- ポーズを一度も開かない。→ H1 / H2 を通らない。
- `--time` を使わない。→ H5 を通らない。
- `mode == "morning"` は毎回まじめに灯し直す。→ H6 の抜け道を通らない。
- 勝手口と窓を律儀に閉めるので、猫が開口部に着いたかどうかを見ていない。→ H7 を「OK」のまま通す。

UI と入力を通す経路は、いまのところ人の手でしか確かめられない。
`AUTOPLAY OK` は「台本の状態機械が最後まで回る」ことの証明であって、遊べることの証明ではない。

---

## レビュー中に npc 担当が直したもの(再検証済み)

`src/npc/` の深掘りを別に走らせたところ、返ってきた所見 10 件のうち 8 件は
**返ってきた時点ですでに作業ツリーで直っていた**。現物を読んで確認した結果は次のとおり。

| 指摘 | 現物 | 状態 |
|---|---|---|
| `stop()` が `arrived` を出さず `await go_to()` が返らない | `npc_base.gd:265-268` が `_cancel_move()` → `:283` で `arrived.emit()`。`last_move_cancelled` も追加 | 修正済み |
| `Kasha.caught` の二重発火 | `kasha.gd:249` で `_catch()` 冒頭に `is_chasing = false`、`:267` で復帰 | 修正済み |
| 猫がスポーンで詰まる回避策が無い | `cat.gd:248` に `walk_spawn_exit_route()`、`:254-271` に代替開口部への切り替え | 緩和のみ(→ H7) |
| `_state_shooed` が `last_move_failed` を見ずに壁抜けワープ | `cat.gd:463` が `last_move_blocked or last_move_failed or last_move_cancelled` | 修正済み |
| 遠くから引っ掻き音だけ鳴る | `cat.gd:273-277` で 1.6m 以内でないと鳴らさない | 修正済み(音が完全に消えた → H7) |
| 状態遷移で tween を kill しない | `cat.gd:42` に `_move_tween`、`:183-185` で kill | 修正済み |
| `_update_eyes` が毎フレーム `find_children` | `_eye_mats` をキャッシュして `NpcUtil.apply_emission` | 修正済み |
| `all_doors()` を毎物理フレーム duplicate | `npc_base.gd:656-664` で扉参照をキャッシュ | 修正済み |
| `despawn()` の `await` 後に生存確認が無い | `npc_base.gd:349` に `is_instance_valid(self)` | 修正済み |
| `leave_via` が await 跨ぎの `door` を無検査で使う | `npc_base.gd:465` で取得 → `:469-476` で使用。ガード無し | **未修正**(Low。Door は常設なので実害は小さい) |

残っているのは最後の 1 件と、H7 / M4 の経路探索そのもの。

---

## レビュー中に実際に観測したエラーログ(全文)

### 1. 起動だけ(`godot --headless --path . --quit`)

```
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 1 resources still in use at exit (run with --verbose for details).
   at: clear (core/io/resource.cpp:822)
```
SCRIPT ERROR は無し。

### 2. `--time=23:20` 以降での起動(ウィンドウ / headless 共通)

```
ERROR: NavigationServer navigation map query failed because it was made before first map synchronization.
	NavigationServer 'map_changed' signal can be used to receive update notifications.
	NavigationServer 'map_get_iteration_id()' can be used to check if a map has finished its newest iteration.
   at: get_closest_point (modules/navigation_3d/nav_map_3d.cpp:197)
   GDScript backtrace (most recent call first):
       [0] snap (res://src/npc/npc_util.gd:170)
       [1] walk_to (res://src/npc/npc_base.gd:222)
       [2] go_to (res://src/npc/npc_base.gd:258)
       [3] _state_approach (res://src/npc/cat.gd:257)
       [4] _run_state (res://src/npc/cat.gd:209)
       [5] _set_state (res://src/npc/cat.gd:190)
       [6] set_target_entry (res://src/npc/cat.gd:117)
       [7] _activate_cats (res://src/director/timeline.gd:241)
       [8] apply_past (res://src/director/timeline.gd:80)
       [9] apply_state_for_time (res://src/director/director.gd:453)
       [10] _boot (res://src/director/director.gd:93)
```

### 3. HUD のキー名取得(headless のみ、1回)

```
ERROR: Not supported by this display server.
   at: keyboard_get_keycode_from_physical (servers/display/display_server.cpp:1224)
   GDScript backtrace (most recent call first):
       [0] _key_for (res://src/ui/hud.gd:124)
       [1] _ready (res://src/ui/hud.gd:111)
       [2] start_game (res://src/main.gd:80)
       [3] _ready (res://src/main.gd:37)
```

### 4. `Parameter "material" is null`(headless のみ)

```
ERROR: Parameter "material" is null.
   at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)
```
自動プレイ中の出現数: morning 13 / substitute 11 / kasha 9 / portrait 2。
`[systems] level のプレースホルダ 19 個を消した` の直後と、式場に入った直後にまとまって出る。
**ウィンドウモード(Metal / Forward+)では一度も出ない。** 出所が
`servers/rendering/dummy/`(headless のダミーレンダラ)なので、headless 固有の症状。
systems 申し送りが書いている `hide_anchor_prop` の件とは出る条件が違う(2フレーム待ちを入れた後も出ている)。

### 5. ナビ到達失敗(自動プレイ)

```
[npc] Cat1 が (0.000000, 0.100000, -9.000000) へ到達できないので打ち切り(残り 20.16m)
[npc] Cat1 が (0.000000, 0.100000, -9.000000) へ到達できないので打ち切り(残り 21.05m)
[npc] Cat1 が (0.000000, 0.100000, -9.000000) へ到達できないので打ち切り(残り 22.42m)
[npc] Cat2 が (0.700000, 0.100000, 5.000000) へ到達できないので打ち切り(残り 16.33m)
[npc] Cat2 が (13.000000, 0.100000, 4.900000) へ到達できないので打ち切り(残り 31.78m)
[npc] Cat2 が (13.000000, 0.100000, 4.900000) へ到達できないので打ち切り(残り 37.34m)
[npc] Granddaughter が (-9.600000, 0.200000, 0.000000) へ到達できないので打ち切り(残り 21.77m)
[npc] Son が (0.898081, 0.200000, -6.957912) へ到達できないので打ち切り(残り 6.23m)
```

### 6. 終了時のリーク(自動プレイ)

```
kasha:      WARNING: 28 ObjectDB instances were leaked at exit / ERROR: 8 resources still in use at exit
substitute: WARNING: 25 ObjectDB instances were leaked at exit / ERROR: 8 resources still in use at exit
morning:    WARNING: 22 ObjectDB instances were leaked at exit / ERROR: 7 resources still in use at exit
portrait:   WARNING: 12 ObjectDB instances were leaked at exit / ERROR: 6 resources still in use at exit
```

---

## そのほかに回したコマンドと結果

### 再開(タイトルへ戻る)の検証

```bash
godot --path . -- --skip-title --qa-restart --screenshot=out/review/restart.png \
  --pos=15.2,1.6,-0.5 --yaw=-90 --wait=8
godot --path . -- --skip-title            --screenshot=out/review/norestart.png \
  --pos=15.2,1.6,-0.5 --yaw=-90 --wait=8
```

```
qa-restart: reloading scene (boot_count=1, clock=21:01)
screenshot saved: out/review/restart.png   (fps=103, draw_calls=1883, objects=1923)
screenshot saved: out/review/norestart.png (fps=103, draw_calls=1883, objects=1923)
```
再読込の前後でノード数も描画負荷も完全に同じ。ハンドラやノードの二重生成は起きていない。
SCRIPT ERROR も 0 件。

### `create_timer` がポーズを無視することの確認(別プロジェクト)

`/private/tmp/.../scratchpad/pausetest` に最小プロジェクトを作って確認した(本プロジェクトは触っていない)。

```gdscript
func _ready() -> void:
    get_tree().paused = true
    var t0 := Time.get_ticks_msec()
    await get_tree().create_timer(0.5).timeout
    print("create_timer(0.5) returned after ", Time.get_ticks_msec() - t0, " ms while paused=", get_tree().paused)
```
```
paused=true
create_timer(0.5) returned after 423 ms while paused=true
```

### H3 の撮影

```bash
godot --path . -- --skip-title --time=04:00 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review/finale_w0.35.png --wait=0.35
godot --path . -- --skip-title --time=04:00 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review/finale_w1.0.png  --wait=1.0
godot --path . -- --skip-title --time=04:00 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review/finale_dialogue.png --wait=2.5
```
3枚とも「灯りが全部落ちた。」だけ。送り入力をしていないので、
キューがあれば 1 行目の「線香が消えた。」が残っているはず。

### 描画負荷の計測

```bash
godot --path . -- --skip-title <pose> --screenshot=out/review/perf.png --wait=3
```
M3 の表のとおり。
