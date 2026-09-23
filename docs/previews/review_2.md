# review_2 — 修正後の再検証

レビュー担当。実装はしていない(新規ファイルはこの 1 本だけ)。
対象は `work/v1` の `4f169bb`。実行検証はすべてこのコミットで回した。
(書いている途中に `cb71b47`「詰まり脱出の押し出し先をナビへ吸着」が入ったが、
autoplay とスクリーンショットは取り直していない。行番号は `cb71b47` で当て直して確認済み。)
`review_1.md` の所見を 1 件ずつ**同じ再現手順で回し直し**、そのあと新しく入ったコードを読んだ。

結論から言うと、**review_1 の High 7 件・Medium 7 件・Low 4 件は解消**。
残っているのは L5(終了時のリーク)と、H7 が形を変えて残った「猫が棺まで届かない」だけ。
代わりに新規で High 2 件・Medium 3 件・Low 4 件を見つけた。

---

## 1. review_1 の所見の再検証

| # | 所見 | 判定 | 根拠(実行結果 / 現物) |
|---|---|---|---|
| H1 | ポーズ中も台本が進む | **解消** | `Events.after/wait/once/wait_event` が `create_timer(s, false)` に(`events.gd:34-56`)。非テストに残る pause 無視のタイマーは 13 件だが、うち 11 件は CLI フックと `auto_advance` 専用。残り 2 件は → N7 |
| H2 | ポーズ中にエンディングへ入ると再開後も止まる | **解消** | `game.gd:53`(`end_night`)と `:58`(`reset`)で `get_tree().paused = false` |
| H3 | 独白が2つ同時に走ると片方が消える | **解消** | `--time=04:00 --wait=0.35 / 1.0 / 2.5` の3枚すべてで「線香が消えた。」が出る(1回目は3枚とも「灯りが全部落ちた。」だった)。送り入力をしていないので順番待ちが効いている |
| H4 | 字幕が出たままプレイヤーが動ける | **解消** | `hud.blocks_player()` に `_dlg_active` を追加(`hud.gd:987`)。`player.gd:199/362-370` の `_interact_gate` で閉じた瞬間の E を握りつぶす |
| H5 | `--time=23:20` 以降で NavigationServer エラー | **解消** | `--time=23:30` / `04:00` とも ERROR 0 件。`timeline.gd:236-241` で物理フレーム2回待ち、`npc_util.gd:196-199` の `is_nav_ready()` が `map_get_iteration_id` を**問い合わせる前に**見る形になった |
| H6 | 朝エンドが灯し直しを条件にしていない | **解消** | `endings.gd:27-28` に `relight_done` 判定。`timeline.gd:714` の `_finish_finale` で立つ |
| H7 | 猫が開口部まで到達できない | **別の問題に変化** | 打ち切りは 4 本で 1 件まで減り、`ENTERING` 6 回 / `INSIDE_WANDER` 6 回 / `TO_COFFIN` 3 回、`cat_entered` 5 回(kasha 4 / substitute 1)。ただし `ON_COFFIN` と `cat_crossed_coffin` は**まだ 0 回** → N4 |
| M1 | 受話器放置で電話が飛ぶ | **解消** | `phone.gd:87-93` で `off_hook` なら `hang_up()` してから鳴らす |
| M2 | 運搬物が黙って消える | **解消** | `player.gd:415-428` の `give_item` が両手塞がりで `false` を返し `give_refused` を出す。`sink.gd:23-24` / `freezer.gd:144-151` / `pickup.gd` が `is_carrying` で弾く |
| M3 | モニターの SubViewport が常時描画 | **解消** | `monitor.gd` に `only_update_in_room`。実測値は下の表 |
| M4 | 孫娘が式場から動かずに消える | **解消** | 4 本すべてで `Granddaughter が … 到達できない` が消え、`21:00 npc_left {granddaughter}` だけが残る |
| M5 | 控室の戸が戻らない | **解消** | `timeline.gd:715` の `_restore_hikaeshitsu_door()` |
| M6 | 待ちヘルパが接続を外さない | **解消** | `Events.once` / `Events.wait_event`(`events.gd:44-56`)に寄せ、`director.gd:1099-1100` がそれを呼ぶだけになった |
| M7 | HUD 既定の掟が正本と違う | **解消** | `hud.gd:21-29` が `docs/script.md` と一致。`clipboard_title = "寝ずの番 心得"`、`clipboard_footer = "やすらぎ会館"` |
| L1 | headless でキーコード取得エラー | **解消** | `hud.gd:121-122` が `UiTheme.key_name()` 経由に。autoplay 4 本で当該 ERROR 0 件 |
| L2 | 線香/ロウソクが `Clock.speed` を見ない | **解消** | `incense_stand.gd:122` / `candle.gd:128` |
| L3 | `one_shot` でなくても `_used` が立つ | **解消** | `interactable.gd:48-49` |
| L4 | クリップボードと手紙が重なる | **解消** | `hud.gd:764` の `show_note` が `_close_clipboard()` を呼ぶ |
| L5 | 終了時のリーク | **未解消** | 値はほぼ同じ(kasha 9 / substitute 8 / morning 7 / portrait 4 resources)。`--quit` だけの素の状態で ObjectDB 2 / resources 1 が出る下地も変わらず |

### M3 の実測(同じ視点・同じコマンド)

```bash
godot --path . -- --skip-title <pose> --screenshot=out/review2/perf.png --wait=3
```

| 視点 | 1 回目 fps / draw calls | 2 回目 fps / draw calls |
|---|---|---|
| トイレで壁を向く(21:00) | 67 / 2695 | **121 / 988** |
| トイレで壁を向く(04:00・全消灯) | 65 / 2695 | **113 / 988** |
| 事務所からモニター | 80 / 2805 | 79 / 2839 |
| 式場から祭壇 | 95 / 2158 | **120 / 539** |

事務所以外は draw call が 1/4 前後まで落ちた。1 回目に「壁を向いても 2700 出る」と書いた定数ぶんは、
**やはり監視モニターの SubViewport だった**ことが数字で確定した。
事務所だけ据え置きなのは仕様どおり(その部屋にいるときだけ描く)。→ ただし N8。

---

## 2. 新規の所見

### N1(High)終盤のタスク表示が「線香を立てる」のままになる

**ファイル**: `src/director/director.gd:536-540`(`_on_incense_out`)、`src/director/timeline.gd:634` / `:649`

**何が起きるか**
`ev_finale` は

```gdscript
# timeline.gd:634
dir.quench(&"incense_stand")          # → incense_out → _on_incense_out()
...
# timeline.gd:649
Tasks.set_task(&"relight", ScriptText.TASK_RELIGHT)
```
の順に走る。`_on_incense_out()` は

```gdscript
func _on_incense_out() -> void:
	if Game.state == Game.State.ENDING:
		return
	monologue(ScriptText.M_INCENSE_OUT)
	Tasks.set_task(&"incense", ScriptText.TASK_INCENSE)
```
で、隣の `_on_candle_out()`(`director.gd:548-551`)と違って **`timeline.finale_running()` を見ていない**。
`Tasks.current()` は `_tasks[0]`(登録順の先頭)を返すので、HUD 左上には
終盤のあいだずっと「□ 線香を立てる」が出る。design.md v0.2 の 04:00 は
「事務所のマッチで祭壇のロウソクを灯し直す×3」で、線香は 04:40 の収束後に 1 本立てる段取り。

唯一のタイムアタック区間で、プレイヤーに**逆のことを指示している**。

**再現**
```bash
godot --path . -- --skip-title --time=04:05 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review2/lights_04-05.png --wait=3.0
```
`out/review2/lights_04-05.png` の左上が「□ 線香を立てる」。
自動プレイのログでも 04:00 に `incense` → `relight` の順で並び、
ボットは先に線香を立ててから(`04:00 incense_lit` / `task_completed {id: incense}`)マッチを取りに行っている。

**付随**: 線香の在庫が 0 のまま終盤に入ると、この `incense` タスクは終盤中に消せない
(在庫箱はバックヤード。火車に追われながら取りに行くことになる)。

**直し方の案**
`_on_incense_out()` の先頭に `_on_candle_out()` と同じガードを足す。

```gdscript
if timeline.finale_running() or Game.state == Game.State.ENDING:
	return
```
04:40 の `_finish_finale()` は既に `Tasks.set_task(&"last_incense", …)` を出しているので、
終盤中に `incense` を出す必要はない。

**担当**: director

---

### N2(High)ナビメッシュの `agent_radius` が体の半径より小さい

**ファイル**: `src/level/building.gd:658`、`src/npc/npc_base.gd:49`、`src/npc/kasha.gd:58`、`src/npc/son.gd:50`

**何が起きるか**
ナビメッシュは

```gdscript
nm.agent_radius = 0.2
nm.agent_height = 1.6
```
で焼かれているのに、実際の当たり判定カプセルは

| NPC | `body_radius` | `body_height` |
|---|---|---|
| `NpcBase` 既定(社長・孫娘) | 0.28 | 1.70 |
| `NpcSon` | 0.27 | 1.75 |
| `Kasha` | 0.33 | 0.90 |
| `Cat` | 0.13 | 0.36 |

猫以外は**ナビメッシュが想定している体より太い**。
ナビメッシュは壁から 0.2m のところまで歩けることになっているので、
半径 0.28〜0.33 の体は「経路はあるのに物理的に通れない」場所を目指すことになる。
`agent_height` 1.6 も人物の 1.70/1.75 より低い。

**根拠**(kasha モードの自動プレイ 1 本で観測。新しい診断つきログ)
```
[npc] Cat1 が (2.000000, 0.200000, -4.000000) へ到達できないので打ち切り(残り 3.54m)
      pos=(5.505377, 0.000822, -3.486291) reason=move next=(5.299999, 0.200000, -3.900000)
      nav_ready=true reachable=true path=3.9m
```
`nav_ready=true` `reachable=true` `path=3.9m`、次の経由点は 0.46m 先。
つまり**経路も同期も問題なく、物理的に進めていない**。
猫は半径 0.13 なので当たり判定では通れるはずで、この 1 件は狭所の別要因も混じっているが、
半径の不一致は人物と火車でそのまま効く。

**直し方の案**
`nm.agent_radius` を実際の最大体半径 + 余裕(0.33 + 0.05 = 0.38 くらい)まで上げて焼き直す。
そのぶん通路が細ると通れない場所が出るので、`--api` の経路チェックか
`_test_tour.gd` の経路テストで前後を比較してから決める。
`nm.agent_height` も 1.8 に上げる。

**未確認**: 上げた結果どの通路が塞がるかは測っていない。level 側で要計測。

**担当**: level(+ npc と数値を合わせる)

---

### N3(Medium)経路キャッシュが目標の切り替えで無効化されない

**ファイル**: `src/npc/npc_base.gd:688-708`(`_steer_point`)、`:225-243`(`walk_to`)、`:248-255`(`retarget`)

**何が起きるか**
`_steer_point()` は操舵先を 0.25 秒キャッシュする。

```gdscript
func _steer_point(delta: float) -> Vector3:
	var next := agent.get_next_path_position()
	_repath_t2 -= delta
	if _repath_t2 > 0.0 and _steer_cache != Vector3.INF:
		return _steer_cache
```
ところが `walk_to()` も `retarget()` も `_steer_cache` / `_repath_t2` を**リセットしていない**。
目標を変えた直後、最大 0.25 秒は**前の経路の経由点**へ向かって歩く。
歩行 2.5m/s で約 0.6m、火車の 3.0m/s で約 0.75m。

いちばん効くのは火車で、追跡中は毎フレーム `retarget(player)` を呼ぶため、
向きの更新が実質 4Hz になる。L 字廊下の角で「プレイヤーが曲がったのに火車が直進する」形で出る。
猫が開口部を切り替えた直後(`_pick_entry`)にも、一瞬だけ前の開口部の方向へ歩く。

**直し方の案**
`walk_to()` と `retarget()` の中で

```gdscript
_steer_cache = Vector3.INF
_repath_t2 = 0.0
```
を入れる。`walk_to` には既に `_nudge_angle` や `_best_progress` のリセットが並んでいるので、そこへ足すだけ。

**担当**: npc

---

### N4(Medium)猫が棺まで到達できず、`cat_crossed_coffin` が一度も起きない

**ファイル**: `src/npc/cat.gd:360-375`(`_state_to_coffin`)

**何が起きるか**
`TO_COFFIN` は `NpcUtil.COFFIN_ROUTE` を順に歩き、途中で `last_move_blocked` になると
引っ掻いて `INSIDE_WANDER` に戻る。猫は扉を開けられない仕様なので、
**式場の戸が閉まっているかぎり棺には永久に届かない**。

**根拠**(kasha モードの自動プレイ)
```
[cat] Cat1 -> TO_COFFIN      (01:00)
...
[cat] Cat1 -> INSIDE_WANDER  (戻っている)
[cat] Cat3 -> TO_COFFIN      (01:2x)
[cat] Cat1 -> TO_COFFIN      (03:5x)
```
`TO_COFFIN` は 3 回出るが `ON_COFFIN` は 0 回。
`cat_crossed_coffin` は review_1 の 8 本 + 今回の 4 本、**計 12 本すべてで 0 回**。

**効いてくる範囲**
`cat_crossed_coffin` は異変度 +3 と、火車エンドの 2 条件のうちの片方
(`endings.gd:23` / design.md v0.2 の表)。この経路が一度も通っていない。

**未確認**
自動プレイのボットは `Player.teleport` で移動するので扉を一切開けない。
人間が式場の戸を開けっぱなしにして遊べば猫は棺まで行けるはずだが、そこは未検証。
`_test_npc.tscn --scenario=cat_enter` では棺まで行けている(npc 申し送りのスクリーンショット)ので、
ロジック自体は動く。

**確かめ方の案**
autoplay に「式場の戸を開けたままにする」モードを足すか、
`--scenario=cat_enter` を本編のレベルで走らせる QA フックを用意する。
少なくとも `cat_crossed_coffin` → 火車エンドの経路は人手で 1 回通しておきたい。

**担当**: director(QA フック)+ npc

---

### N5(Medium)`Autoplay._shoo_cat` が毎 tick `flee()` を呼び、猫の退出をリセットし続ける

**ファイル**: `src/director/autoplay.gd`(`_shoo_cat`)、`src/npc/cat.gd:490-516`(`_state_shooed`)

**何が起きるか**
`_state_shooed` は入口で `set_talkable(false)` する(`cat.gd:491`)ので、
ボットの `_use(target)` は失敗する。するとフォールバックの

```gdscript
if c.has_method(&"flee"):
	c.call(&"flee")
	return true
```
が走り、`flee()` → `_set_state(State.SHOOED)` で**退出の歩きが最初からやり直しになる**。
ボットは 3秒/speed ごとに判断するので、これが延々と続く。

**根拠**(substitute モードの自動プレイ)
```
[event] 03:07 cat_entered { "entry": &"Door_Backyard" }
[cat] Cat3 -> INSIDE_WANDER
[cat] Cat3 -> SHOOED          ← ここから
...                            (SHOOED が計 47 回)
[event] 04:02 cat_shooed { "exit": &"Door_Backyard" }   ← 55 ゲーム分後
```
`SHOOED` への遷移が 47 回、`cat_shooed` は 1 回だけ。
この 55 ゲーム分、ボットは `_act()` の 5 番で止まるので他の用事も見ていない。

**これはボット側の問題**で、人間は `set_talkable(false)` のおかげで追い払い直せない。
ただし QA としては「猫を追い出す」が一度も正常な時間で回っていないことになる。

**直し方の案**
`_shoo_cat()` の中で、すでに `SHOOED`(または `state != INSIDE_WANDER / TO_COFFIN / ON_COFFIN`)なら
何もせず `false` を返す。ついでに `Cat.shoo()` / `flee()` にも同一状態ガードを入れる(→ N6)。

**担当**: director(autoplay)

---

### N6(Low)`Cat.shoo()` / `flee()` に同一状態ガードが無い

**ファイル**: `src/npc/cat.gd:138-146`

```gdscript
func flee() -> void:
	_shoo_hiss = false
	_set_state(State.SHOOED)

func shoo() -> void:
	_shoo_hiss = true
	_set_state(State.SHOOED)
```
`_set_state()`(`:181-193`)は `state == s` でも `_gen` を進めて tween を kill し `_run_state` を回し直す。
いまはプレイヤー経路が `set_talkable(false)` で塞がっているので実害は autoplay だけだが、
director や scares から `flee()` を撃つと同じことが起きる。
`if state == State.SHOOED: return` を入れておくのが安い。

**担当**: npc

---

### N7(Low)ポーズを無視するタイマーが 2 件残っている

| ファイル:行 | 中身 | 影響 |
|---|---|---|
| `src/level/door.gd:98` | `auto_close_after` の自動閉扉 | 開けた直後にポーズすると、ポーズ中に扉が閉まる |
| `src/level/building.gd:244` | `flicker()` の明滅 | ポーズ中も照明が明滅し続ける |

ほかの 11 件は `main.gd` の CLI フックと `dialogue.gd` の `auto_advance` / UI 無しフォールバックなので、
ポーズを無視して問題ない。上の 2 件も `Events.wait()` に寄せておくと約束が揃う。

**担当**: level

---

### N8(Low)事務所がゲーム中いちばん重い

M3 の表のとおり、事務所だけ 79fps / draw calls 2839 で 1 回目とほぼ同じ。
式場(120fps / 539)の 5 倍以上を描いている。仕様どおりではあるが、
モニターの 2ch を交互に描くのではなく**現在の ch だけ**にする、
`viewport_size` を 256×192 から下げる、`auto_switch` の間隔を延ばす、あたりで軽くできる。

**未確認**: 内訳(式場チャンネルのジオメトリがどれだけ効いているか)は測っていない。
`monitor.gd:78` を一時的に `UPDATE_DISABLED` にして同じ視点で撮れば切り分けられる。

**担当**: systems

---

### N9(Low)`Sink.already_line` が到達不能になった

**ファイル**: `src/systems/sink.gd:23-29`

```gdscript
func _can_interact(player: Node3D) -> bool:
	return not SystemUtil.is_carrying(player)

func fill(player: Node3D) -> void:
	if SystemUtil.has_item(player, item_name):
		Dialogue.monologue(already_line)     # ← ここへ来る経路が無くなった
		return
```
水は `carried = true` なので、水を持っていれば `is_carrying` が true になり `_can_interact` で弾かれる。
「もう汲んである。」は出ない。死にコードなので消すか、
`_can_interact` を `not is_carrying or has_item(water)` にして台詞を残すか、どちらかに寄せたい。

**担当**: systems

---

## 3. autoplay 4 本の結果(1 本ずつ順に実行)

```bash
godot --headless --path . -- --skip-title --autoplay=<mode> --speed=8
```

| mode | exit | 結果 | SCRIPT ERROR | 打ち切り |
|---|---|---|---|---|
| morning | 0 | `ending=morning dread=0 minutes=480` **AUTOPLAY OK** | 0 | 0 件 |
| kasha | 0 | `ending=kasha dread=9 minutes=444` **AUTOPLAY OK** | 0 | 1 件 |
| substitute | 0 | `ending=substitute dread=0 minutes=480` **AUTOPLAY OK** | 0 | 0 件 |
| portrait | 0 | `ending=portrait dread=0 minutes=90` **AUTOPLAY OK** | 0 | 0 件 |

review_1 のときの「Granddaughter ×4 / Cat ×12」が**合計 1 件**まで減った。

### 猫の状態遷移(4 本合計)

| 状態 | review_1(4本) | review_2(4本) |
|---|---|---|
| `OUTSIDE_IDLE` | 47 | 36 |
| `APPROACH` | 27 | 23 |
| `ENTERING` | 0 | **6** |
| `INSIDE_WANDER` | 0 | **6** |
| `TO_COFFIN` | 0 | **3** |
| `SHOOED` | 0 | 47(→ N5) |
| `ON_COFFIN` | 0 | **0**(→ N4) |

`cat_entered` は kasha で 4 回、substitute で 1 回(計 5 回)。`cat_crossed_coffin` は 0 回のまま。

### 唯一残った打ち切り(kasha)

```
[npc] Cat1 が (2.000000, 0.200000, -4.000000) へ到達できないので打ち切り(残り 3.54m)
      pos=(5.505377, 0.000822, -3.486291) reason=move next=(5.299999, 0.200000, -3.900000)
      nav_ready=true reachable=true path=3.9m
```
診断が増えたおかげで「経路も同期もあるのに物理的に進めていない」と読めるようになった(→ N2)。

---

## 4. CLI フックの確認(各 1 回)

### `--qa-restart`

```bash
godot --path . -- --skip-title --qa-restart --screenshot=out/review2/qa_restart.png \
  --pos=15.2,1.6,-0.5 --yaw=-90 --wait=8
```
```
qa-restart: reloading scene (boot_count=1, clock=21:01)
screenshot saved: out/review2/qa_restart.png (fps=120, draw_calls=425, objects=465)
```
SCRIPT ERROR 0 件。

### `--auto-start=2`

`--screenshot` を付けると `main.gd:36` の分岐でタイトルを通らない(`start_game()` が直接呼ばれる)ので、
タイトル経由を確かめるには撮影フックと併用できない。自動プレイと組み合わせて通した。

```bash
godot --headless --path . -- --auto-start=2 --autoplay=portrait --speed=12
```
```
[dir] 21:00 intro
[event] 21:00 task_completed { "id": &"talk_boss" }
[dir] 21:00 intro_done
AUTOPLAY RESULT ending=portrait dread=0 minutes=90
AUTOPLAY OK portrait
```
タイトル → 自動開始 → 導入 → 一夜 → エンディングまで通る。SCRIPT ERROR 0 件。

### `--time=23:30` / `--time=04:00`

```bash
godot --path . -- --skip-title --time=23:30 --screenshot=out/review2/t_2330.png --wait=1.5
godot --path . -- --skip-title --time=04:00 --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review2/finale_w25.png --wait=2.5
```
```
screenshot saved: out/review2/t_2330.png (fps=120, draw_calls=253, objects=295)
screenshot saved: out/review2/finale_w25.png (fps=120, draw_calls=151, objects=184)
```
どちらも ERROR 0 件(review_1 の H5 で出ていた NavigationServer のエラーは消えた)。

### `--reload-test=4`(30 秒)

```bash
godot --headless --path . -- --skip-title --reload-test=4    # 30 秒で kill
```
```
reload-test: reload_current_scene  ×6
SCRIPT ERROR: 0
ERROR/WARNING: Parameter "material" is null ×14 のみ
```
6 回再読み込みしてエラー 0 件。`director_notes.md:290` の記録と一致。

### `--cctv-shot`(M3 の修正で壊れていないかの確認)

```bash
godot --path . -- --skip-title --time=23:00 --cctv-shot=out/review2/cctv.png --wait=5
```
```
CCTV saved: out/review2/cctv.png (feed=0)
```
部屋限定描画を入れても QA フックは動いている。

---

## 5. 観測したエラーログ(全文)

### 起動だけ

```
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 1 resources still in use at exit (run with --verbose for details).
   at: clear (core/io/resource.cpp:822)
```
review_1 と同じ。SCRIPT ERROR は無し。

### `Parameter "material" is null`(headless のみ、未解消)

```
ERROR: Parameter "material" is null.
   at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)
```
出現数: morning 13 / substitute 13 / portrait 4 / kasha 2 / reload-test 14。
ウィンドウモード(Metal / Forward+)では今回も一度も出ていない。
`servers/rendering/dummy/` = headless のダミーレンダラなので、review_1 の判断どおり headless 固有。

### 終了時のリーク(未解消。L5)

```
kasha:      ERROR: 9 resources still in use at exit
substitute: ERROR: 8 resources still in use at exit
morning:    ERROR: 7 resources still in use at exit
portrait:   ERROR: 4 resources still in use at exit
```

### SCRIPT ERROR

**今回の全実行(autoplay 4 本 + auto-start 1 本 + reload-test + 撮影 10 本以上)で 0 件。**

---

## 6. 新しいコードを読んだ所感(不具合以外)

- **`Director.set_quiet()` / `monologue()`**(`director.gd:313-320`)
  `_applying_past` を `apply_state_for_time` と `ev_finale(quiet)` の両方で使い回しているが、
  `apply_state_for_time` は同期関数のままで(`timeline.apply_past` に `await` が無い)、
  `ev_finale(true)` は自分で立てて自分で下ろすので、フラグの取り違えは起きない。
  `_activate_cats_when_ready()` だけがコルーチンだが `await` せず撃ちっぱなしなので影響しない。確認済み。
- **`main.start_game()` がコルーチンになった**(`main.gd:70` の `await get_tree().process_frame`)
  player / HUD / director の生成が 1 フレーム後ろへずれた。
  この窓で level と systems / npc だけが存在するが、`Game.player` を使う側は
  `Interactable._player_has` も `SystemUtil.is_carrying` も null ガードがあり、
  `NpcBase._physics_process` も `Game.player` を見てから使っている。autoplay 4 本と
  `--auto-start` / `--qa-restart` / `--reload-test` が全部通るので、実害は出ていない。
- **`NavigationAgent3D` の設定**(`npc_base.gd:179-192`)
  `avoidance_enabled = false` なので `agent.radius` は経路探索に効かない。
  効くのは焼くときの `nm.agent_radius` のほうで、そこが N2。
- **`Events.once()`**(`events.gd:44-51`)
  `holder` 配列でラムダの自己参照を作って `disconnect` している。
  `Game.reset()` の一括解除と二重に外れても `is_connected` で守られているので安全。
