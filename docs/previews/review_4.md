# review_4 — v0.3 の難易度と推奨セットの確認

レビュー担当。実装はしていない(新規ファイルはこの 1 本だけ)。

自動プレイと撮影は `70acf00`(v0.3 台本の統合)で回し、そのあと director の
`841d61f`(電話の発信と第二の顔の整合)が入ったので、**難易度の 2 本は HEAD で取り直した**。
結論は同じだった。コードの行番号はすべて `841d61f` で当て直してある。

High 2 件・Medium 3 件・Low 4 件。難易度そのものは妥当だと判断した。

---

## 1. 難易度の実測

### 掟を守るプレイヤー

`--autoplay=morning`(ボットは線香を絶やさず、電話に出て、用事をこなす)を HEAD で実行。

```
AUTOPLAY RESULT ending=morning dread=3 minutes=480   AUTOPLAY OK morning
```

異変度の推移(`[scare]` 行から初出だけ拾ったもの):

| 時刻 | 異変度 |
|---|---|
| 21:46 | 0 |
| 00:06 | 1 |
| 01:08 | 2 |
| 02:39 | 3 |

**3 点はすべて時刻の下限(`director.gd:750` の `DREAD_FLOOR`)から来ている。**
23:30 で 1、01:00 で 2、02:30 で 3。プレイヤーの失敗ぶんは 1 点も乗っていない。
ログには `incense_out` が 9 回出ているが、これは全部 `Director.quench()` の台本消火なので
異変度は動いていない(`quench` が `dread_on_out` を一時的に 0 にする)。

朝エンドの条件は異変度 6 未満なので、**余地は 2 点**。

### 何もしないプレイヤー

`--autoplay=kasha`(導入のあと線香を放置し、勝手口と式場の窓を開けたままにする)を HEAD で実行。

```
AUTOPLAY RESULT ending=kasha dread=12 minutes=442   AUTOPLAY OK kasha
```

| 時刻 | 異変度 |
|---|---|
| 21:46 | 1 |
| 22:44 | 2 |
| **23:56** | **7** |
| 00:38 | 8 |
| 01:06 | 9 |
| 02:07 | 10 |
| 03:14 | 11 |

**23:56、つまり夜の 3 時間目には 6 を超えて火車エンドが確定する。** 実時間では 9 分ほど。
内訳は `phone_missed` ×2、`coffin_window_opened`、`cat_crossed_coffin`(+3)と、
線香放置ぶんの `incense_out` / `incense_neglect`。

### 判定

**妥当だと思う。** 守れば 3 で終わり 2 点の余地が残り、放置すれば夜の前半で確定する。
分離ははっきりしている。ただし余地の 2 点は薄い。理由は M1。

---

## 2. High

### H1. 03:40 の蓋を戻さないと、04:01 に即・火車エンドになる

**ファイル**: `src/director/timeline.gd:772-774`、`:829-836`、`src/systems/candle.gd:191-199`

**何が起きるか**
03:40 に棺の蓋が独りでに 10cm ずれる(`ev_lid_slides`)。戻さないまま 04:00 を迎えると:

```gdscript
# timeline.gd:772-774  ev_finale の中
if Game.get_flag(&"lid_slid", false) and not Game.get_flag(&"lid_restored", false):
	if cnd:
		cnd.set(&"fail_next", true)
```
`fail_next` が立った状態で最初の灯し直しをすると

```gdscript
# candle.gd:191-199
if fail_next:
	...
	relight_failed.emit()
```
→ `Timeline.on_relight_failed()`(`:829-836`)→ `dir.kasha_catches()` → **火車エンド確定**。

`docs/design.md` の v0.3 表は

> 03:40 **棺の蓋が独りでに 10cm ずれる**。戻せば異変度は上がらない。放置すると 04:00 の最初の灯し直しが**空振りする**

と書いてある。「空振り」なら擦り直せばよいはずだが、実装は**1 回の空振りがそのままゲームオーバー**。
異変度がいくつでも、それまでの夜がどれだけ完璧でも関係ない。

**効いてくる条件**
- 猶予は 03:40 → 04:00 の 20 ゲーム分 = **実 1 分**。
- そのあいだにランダムな脅かしの独白が挟まると、送るだけで数秒取られる
  (03:45 に撮った `out/review4/t_03-45.png` では「手形だ。……小さい。」が出ていた)。
- 04:00 の `ev_finale` は `Tasks.complete(&"lid")` と `_lid_spot.queue_free()` を通る
  (`timeline.gd:765-768`)ので、**04:00 を過ぎたら戻す手段は消える**。
- 告知は独白「蓋が、ずれている。」(`script_text.gd:181`)とタスク「棺の蓋を戻す」だけ。
  戻さないと死ぬ、とは分からない。

**QA では一度も踏まれていない**
`Autoplay._do_task` は `&"lid"` を扱い(`autoplay.gd:277-281`)、morning のログでは
03:40 に蓋がずれて **03:41 に `task_completed {id: lid}`** と 1 ゲーム分で戻している。
4 つのモードすべてで戻すので、この経路は自動プレイでは検証されない。

**再現手順**
`--time=03:45` で起動し、蓋に触らずに 04:00 を待ってマッチで灯明を灯す。
最初の 1 回で `M_RELIGHT_FAIL`(「消えた。まだ、いる。」)が出て 2.2 秒後に火車エンドへ入る。

**直し方の案**
`on_relight_failed()` に「台本の詰み演出」と「蓋の罰」を区別させる。

```gdscript
func on_relight_failed() -> void:
	if not _finale_running:
		return
	dir.monologue(ScriptText.M_RELIGHT_FAIL)
	scares.glitch(1.0)
	Audio.play(&"kasha_screech", 0.0)
	if not _doomed_fail:        # 蓋の罰なら空振りで済ませる
		return
	await Events.wait(2.2 / maxf(Clock.speed, 0.01))
	dir.kasha_catches()
```
`_doomed_fail` は `on_relight(n)` の `n == 2` で異変度 6 以上のときに立てる側だけ true にする
(`timeline.gd:817` のほう)。蓋の罰は「マッチを 1 本無駄にする + 火車が一歩寄る」くらいが
design.md の「空振り」に合う。

**担当**: director

---

### H2. エンディング前の回想で、画像が 1 枚も出ない

**ファイル**: `src/director/endings.gd:161-168`、`src/ui/ending.gd:202-206`

**何が起きるか**
回想は「画像 + 文」を 3 枚出す作りだが、director が渡しているのは**テクスチャ名の文字列**で、
受け取る側は `Texture2D` しか通さない。

```gdscript
# endings.gd:161-168
var images: Array = []
for row in ScriptText.RECAP:
	images.append(String(row[0]))        # ← "recap_truck" という String
```
```gdscript
# ending.gd:203
var tex: Texture2D = images[i] if i < images.size() and images[i] is Texture2D else null
```
`String is Texture2D` は常に false なので `tex` は必ず null。
`_recap_frame.visible = tex != null` で額縁ごと消え、文だけが中央に出る。

`79b79ab`(models 担当)で `recap_truck` / `recap_cats` / `recap_ledger` の 3 枚を
用意してあるのに、**どのエンディングでも一度も表示されない**。

**根拠**
`ScriptText.RECAP`(`script_text.gd:355-359`)の 1 列目は `"recap_truck"` のような名前で、
`endings.gd` にも `ending.gd` にもテクスチャをロードする箇所が無い
(`grep -n "load_texture" src/director/endings.gd` → 0 件)。

**直し方の案**
```gdscript
images.append(SystemUtil.load_texture(String(row[0])))
```
`SystemUtil.load_texture()` は見つからなければ null を返すので、
画像が無い環境でも今と同じ「文だけ」に落ちる。

**未読分岐のほうは正しい。** `page_read_%d` フラグは `director.gd:972` で立ち、
`endings.gd:166` が読んで未読なら `RECAP_UNREAD`(「……」)に差し替える。
収集物は 1〜6 まで実在し(`director.gd` の `_setup_static` / `play_intro`)、
回想が要求する 6 / 3 / 4 はすべて取得可能。

**担当**: director

---

## 3. Medium

### M1. 線香を 1 回切らすと、条件しだいで異変度が 2 上がる

**ファイル**: `src/systems/incense_stand.gd:21` / `:213`、`src/director/director.gd:786-793`

- 燃え尽きた瞬間に `Dread.add(dread_on_out = 1, &"incense_out")`。
- そのあと**正時をまたいでまだ消えていれば**、`_on_hour` がさらに `Dread.add(1, &"incense_neglect")`。

時刻の下限で 3 は確定するので、余地は 2 点しかない。
「立て直しに手間取って正時をまたいだ」が 1 回あると、それだけで 5。
さらに電話を 1 本取り逃すと 6 に届いて火車エンドになる。

自動プレイの morning はこれを 1 度も踏んでいない(異変度が下限どおりに動いている)ので、
**まじめに遊んだときに実際どれくらい踏むかは未計測**。
21:40 の窓イベント中は `burn_multiplier` が 4.0(基礎 1.0 + 窓 3.0)になり、
線香 1 本が実 45 秒しかもたないので、ここが最初の関門になる。

判断は監督に委ねるが、案としては
- 下限を 3 ではなく 2 で止める
- `incense_out` と `incense_neglect` の二重取りをやめて、正時のチェックだけにする

のどちらか。**担当**: director

---

### M2. headless の `Parameter "material" is null` が大きく増えた

| 実行 | review_3 | review_4 |
|---|---|---|
| morning | 7 | **48** |
| substitute | 7 | **34** |
| portrait | 4 | **11** |
| kasha | 2 | 2 |
| reload-test 30 秒 | 14 | 14 |

```
ERROR: Parameter "material" is null.
   at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)
```
ウィンドウモード(Metal / Forward+)では今回も 0 件なので、headless のダミーレンダラ固有という
判断は変えていない。ただし **7 → 48 は 7 倍**で、v0.3 で増えた小物
(ラジオ・袋・血の手形・家族写真・非常口・新しい猫)のどれかが
`material_override` を持ったまま解放されている可能性がある。

**未確認**: 発生源は特定していない。`--verbose` で出るノード名を 1 つ拾えば絞れる。
CI のログが埋まるので、増えたタイミングで一度見ておいたほうがよい。

**担当**: systems / models(切り分けは監督)

---

### M3. 03:40 の蓋タスクの猶予が実 1 分しかない

H1 を直しても残る設計上の話。`ev_lid_slides` は 03:40、`ev_finale` は 04:00 で、
あいだは 20 ゲーム分 = 実 1 分。このあいだにプレイヤーが式場に居るとは限らず、
03:50 には `ev_cat_crowd` も挟まる。

「戻せば異変度は上がらない」という報酬設計なら猶予が短くても構わないが、
H1 のように罰が重い設計のままなら 03:20 開始にするか、04:00 を過ぎても戻せるようにしたい。

**担当**: director

---

## 4. Low

### L1. 金庫のダイヤルは何回外しても詰まない(仕様確認)
`safe.gd:153-168`。`wrong_count` を数えて `safe_wrong` を出すだけで、ロックアウトは無い。
director は `_on_safe_wrong()`(`director.gd:835`)でヒントを出す。
正解 `1009` は収集①の日記「十月九日」から引ける。**詰みは無い。**

### L2. 分電盤のレバーは誤順でも詰まない(仕様確認)
`breaker.gd:128-149`。順が違うと火花が出て**そのレバーが上がらないだけ**で、
すでに上がったレバーは落ちない。`next_expected()` は毎回 `required_order` から引き直すので、
何度でもやり直せる。全部上がった時だけ `breaker_on` が出て director が照明を戻す
(`timeline.gd:356-363`)。**誤順で部屋が消えたまま戻らないことは無い。**

### L3. 受話器の上げっぱなしは自動で戻る(仕様確認)
`phone.gd:96-102`。`ring()` が `off_hook` を見て先に `hang_up()` する(review_2 M1 の修正が健在)。
台本の電話が飛ぶことは無い。発信側も `_on_phone_dialed` の最後で必ず `hang_up()` する
(`director.gd:878-879`)ので、受話器が上がったままにはならない。

### L4. 数字入力中はポーズを開けない(仕様確認)
`hud.gd:1183` の `_open_pause()` が `_code_open` で早期 return する。
`blocks_player()`(`:1449`)と `wants_cursor()`(`:1453`)にも入っている。
パッドは上下で桁を回し、左右で桁を移り、A で確定・B で取り消し(`hud.gd:777-794`)。
`up/down/left/right` は `ui_*` と `move_*` の OR なので、スティックでも十字でも動く。**問題なし。**

---

## 5. autoplay 4 本の結果(1 本ずつ順に実行)

`70acf00` で 4 本、`841d61f`(HEAD)で morning と kasha を取り直し。

| mode | exit | 結果 | SCRIPT ERROR | 打ち切り |
|---|---|---|---|---|
| morning | 0 | `ending=morning dread=3 minutes=480` **OK** | 0 | 0 |
| kasha | 0 | `ending=kasha dread=12 minutes=442` **OK** | 0 | 1 |
| substitute | 0 | `ending=substitute dread=3 minutes=480` **OK** | 0 | 0 |
| portrait | 0 | `ending=portrait dread=0 minutes=90` **OK** | 0 | 1 |

HEAD での取り直し:
```
AUTOPLAY RESULT ending=morning dread=3 minutes=480   AUTOPLAY OK morning
AUTOPLAY RESULT ending=kasha   dread=12 minutes=442  AUTOPLAY OK kasha
```

### 猫の状態遷移(4 本合計)

| 状態 | review_2 | review_3 | review_4 |
|---|---|---|---|
| `APPROACH` | 23 | 23 | 24 |
| `ENTERING` | 6 | 7 | **18** |
| `INSIDE_WANDER` | 6 | 6 | **17** |
| `TO_COFFIN` | 3 | 3 | **6** |
| `ON_COFFIN` | 0 | 3 | **4** |
| `SHOOED` | 47 | 3 | 15 |

猫が扉を押し開けるようになったぶん、侵入が 7 → 18 に増えている。
「猫を入れるな」の掟が実際に機能する密度になった。

### 残った打ち切り 2 件

```
[npc] Cat3 が (-2.000000, 0.200000, 0.000000) へ到達できないので打ち切り(残り 8.20m)
      pos=(6.153650, 0.000940, 0.913213) reason=move next=(-1.465982, 0.200000, …)
[npc] Cat2 が (0.700000, 0.100000, 5.000000) へ到達できないので打ち切り(残り 17.00m)
      pos=(-15.934422, -0.019056, 1.494440) reason=move next=(-11.400000, 0.1…)
```
どちらも「経路はあるが時間内に着かない」型。4 本で 2 件なので前回(1 件)と同水準。

---

## 6. CLI フックと撮影

### 時刻指定の起動(5 本)

```bash
godot --path . -- --skip-title --time=<HH:MM> --pos=15.2,1.6,-0.5 --yaw=-90 \
  --screenshot=out/review4/t_<HH-MM>.png --wait=3
```

| 時刻 | fps | draw calls | objects | エラー |
|---|---|---|---|---|
| 22:35 | 922 | 135 | 177 | なし |
| 23:35 | 879 | 135 | 177 | なし |
| 01:35 | 927 | 133 | 178 | なし |
| 03:45 | 915 | 133 | 172 | なし |
| 03:55 | 910 | 133 | 172 | なし |

**式場の draw calls が 532(review_3)→ 133 に落ちた。** `8da49de`(メッシュ統合)と
`48c495b`(監視モニターを 160×120 / 15fps 相当)が効いている。review_2 で挙げた N8 は
これで解消と見てよい。`Parameter "material" is null` はウィンドウモードでは 1 件も出ない。

### `--qa-restart`
```
qa-restart: reloading scene (boot_count=1, clock=21:01)
screenshot saved: out/review4/qa_restart.png (fps=120, draw_calls=407, objects=447)
```
SCRIPT ERROR なし。

### `--reload-test=4`(30 秒)
```
reload 回数: 6
SCRIPT ERROR: 0
ERROR: Parameter "material" is null ×14 のみ
```

---

## 7. 観測したエラーログ(全文)

### 起動だけ
```
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org

WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).
   at: cleanup (core/object/object.cpp:2536)
ERROR: 1 resources still in use at exit (run with --verbose for details).
   at: clear (core/io/resource.cpp:822)
```

### `Parameter "material" is null`(headless のみ。→ M2)
```
ERROR: Parameter "material" is null.
   at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)
```

### 終了時のリーク
```
morning 1 / kasha 9 / substitute 1 / portrait 6 resources still in use at exit
```
review_1 から続く下地のまま。

### SCRIPT ERROR

**今回の全実行(autoplay 6 本 + 撮影 7 本 + reload-test)で 0 件。**

---

## 8. 最後に見た 2 点(director が修正中と聞いていたもの)

`841d61f` で両方入っていた。読んだかぎり問題は見つからなかった。

- **電話の発信**: `Phone` は `phone_dialed{number}` を出すだけ(`phone.gd:154`)で、
  応答は全部 director の `_on_phone_dialed()`(`director.gd:863-879`)に集約された。
  番号は 社長 `0246` / ひかり `3175` / キヨ `4419`(`script_text.gd:296-298`)。
  未登録の番号は `phone_unavailable` + 「おかけになった電話番号は、現在使われておりません。」に落ち、
  どの分岐でも最後に `hang_up()` するので受話器が上がったままにはならない。
  キヨの番号は `Dread.add(1, &"phone_kiyo")`(`director.gd:932`)を払う。
  探索して見つけた報酬に 1 点払う設計なので、余地 2 点のうち 1 点を使うことになる。M1 と併せて監督の判断待ち。
- **第二の顔**: `Coffin.set_second_face()`(`coffin.gd:322-`)。
  `second_face_delay` 1.2 秒 → `second_face_seconds` 0.5 秒だけ出す。
  `eba1f8d` で位置を実アセットに合わせ、`2178097` でテクスチャをアルファ付きにしてある。
  小窓を覗いている最中だけの演出で、進行には関わらない。

## 9. 判定の対象外にしたもの

- **音**。ヘッドレスと静止画では聞けない。`c0b00aa`(ラジオ・応答・猫の合唱・火花・ダイヤル外れ)と
  `ebc82f0`(引き戸と開き戸)は、呼んでいる音名が `CLAUDE.md` の一覧と一致することだけ確認した。
- **室名札・非常口・新しい猫モデルの見た目**。撮って目で見るべきだが、今回は難易度とギミックの
  詰みを優先した。次回に回したい。
