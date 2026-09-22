# npc 担当 申し送り

`src/npc/` の中身、公開 API、director 向けの使い方、未解決の問題。
動作確認シーンは `src/npc/_test_npc.tscn`、スクリーンショットは `out/npc/`(生成物・コミットしない)。

---

## ファイル

| ファイル | 中身 |
|---|---|
| `npc_base.gd` | `NpcBase`(CharacterBody3D)。移動・会話・姿勢・扉判定の土台 |
| `npc_util.gd` | `NpcUtil`。開口部の表、経由点、ナビ/視線/マテリアルの static ヘルパ |
| `npc_talk.gd` | `NpcTalk`(`Interactable` 派生)。話しかけ判定。`NpcBase` が子として自動生成 |
| `boss.gd` / `boss.tscn` | `NpcBoss` 社長 |
| `granddaughter.gd` / `.tscn` | `NpcGranddaughter` 孫娘 |
| `son.gd` / `son.tscn` | `NpcSon` 息子 |
| `cat.gd` / `cat.tscn` | `Cat` 黒猫。8 状態のステートマシン |
| `kasha.gd` / `kasha.tscn` | `Kasha` 火車 |
| `body_risen.gd` / `.tscn` | `BodyRisen` 起き上がった故人(演出専用) |
| `installer.gd` / `.tscn` | `NpcInstaller`。`Spawn_*` に 9 体を置く |
| `_test_npc.gd` / `.tscn` | 動作確認シーン |

## 当たり判定とグループ

- `NpcBase` は **layer 4 (npc) = 値 8 / mask 1 (world)**。`project.godot` の `3d_physics/layer_4="npc"`。
- 棺の `CatZone`(mask 12 = player + npc)が猫を拾うので、猫は本体カプセルに加えて
  体の中心に `CrossMarker`(Area3D, layer 8, monitorable)を持つ。
- グループ: 全員 `npc`。加えて `npc_boss` / `npc_granddaughter` / `npc_son` / `npc_cat` / `npc_kasha`。
  猫は `cat`、火車は `kasha`、人物は `npc_human` にも入る。
- 正面は **-Z**。ただし `cat.glb` だけ頭が +Z 側なので、`Cat` は `model_yaw_offset_deg = 180` で
  **見た目だけ**回している(当たり判定とナビはノード本体のまま)。

---

## 起動時に置かれるもの

`main.gd` が `src/npc/installer.tscn` を World に足した時点で `NpcInstaller` が動く。

| Spawn | プレハブ | 最初の状態 |
|---|---|---|
| `Spawn_Boss` | `boss` | 表示・有効 |
| `Spawn_Granddaughter` | `granddaughter` | 表示・有効 |
| `Spawn_Son` | `son` | 非表示・無効 |
| `Spawn_Cat1`〜`Cat5` | `cat` | 非表示・無効 |
| `Spawn_Kasha` | `kasha` | 非表示・無効 |

非表示のものは director が `activate()`(猫・火車)か `set_active(true)`(息子)で出す。

```gdscript
NpcInstaller.find(&"boss")            # -> NpcBoss
NpcInstaller.find(&"cat", 2)          # -> Spawn_Cat3 に置いた Cat(Spawn の並び順)
NpcInstaller.find_all(&"cat")         # -> Array[Node] 5 匹
NpcInstaller.all()                    # -> 置かれている NPC 全部
```

---

## 公開 API

### `NpcBase`

シグナル

| 名前 | 意味 |
|---|---|
| `arrived` | `walk_to` / `go_to` の到着(詰まって打ち切ったときも出る) |
| `talked(player)` | 話しかけられた。**会話の中身は director が持つ** |
| `despawned` | `despawn()` が終わった |
| `door_blocked(door_name)` | 閉まった扉の前で止まった |

移動

| メソッド | 備考 |
|---|---|
| `walk_to(pos, tolerance := -1.0) -> Signal` | 撃ちっぱなし。返り値は `arrived` なので `await npc.walk_to(p)` でも待てる |
| `go_to(pos, tolerance := -1.0)` | 到着まで待つコルーチン。`await npc.go_to(p)` |
| `retarget(pos)` | 追跡中に目標だけ差し替える(詰まり判定をリセットしない) |
| `walk_route(points, tolerance := -1.0)` | 経由点を順に歩く |
| `stop()` | その場で止まる |
| `teleport_to(pos, yaw_deg := NAN)` | 位置と向きを直接入れる |
| `set_speed_override(v)` / `current_speed()` | 一時的な速度上書き。負で解除 |

`tolerance` は狭い通路の経由点用。既定の到着判定は `arrive_distance`(0.45)。

向きと会話

| メソッド | 備考 |
|---|---|
| `face(target)` / `face_now(target)` / `face_player()` | `Node3D` でも `Vector3` でもよい |
| `set_talkable(on)` | `[E] 話す` の出し入れ。prompt は `talk_prompt` |
| `head_position()` | 子の `Head`(Marker3D)のワールド座標。`player.look_at_point()` 用 |

姿勢(人物モデルは `idle` / `walk` / `sit` / `sit_floor` / `sleep` の 5 種)

| メソッド | 備考 |
|---|---|
| `sit_on_chair(pos := INF, yaw_deg := NAN)` | パイプ椅子・事務椅子 |
| `sit_on_floor(pos, yaw_deg)` | 座布団にあぐら |
| `lie_down(pos, yaw_deg, speed := 1.0)` | 横になる。**体は正面(-Z)側へ伸びる** |
| `stand_up()` | 立つ |
| `posture` | `stand` / `sit` / `sit_floor` / `sleep`。`stand` 以外は歩行アニメの自動切替を止める |

表示と出入り

| メソッド | 備考 |
|---|---|
| `set_active(on)` | 表示 + 処理 + 当たり判定をまとめて入/切 |
| `despawn(fade := true)` | 0.6 秒で透過して非表示。**ノードは残す**ので後から `set_active(true)` で戻せる |
| `play_anim(name, speed := 1.0)` / `current_anim()` | |
| `leave_via(door_name := &"Door_Genkan", emit_left := true)` | 扉を開けて外へ出て `npc_left{name}` |
| `leave_via_genkan()` | 上の玄関版 |
| `enter_from_genkan(to_pos)` | 玄関の外から入ってきて `to_pos` まで歩く |

詰まりの検知(director が「歩かせたのに着かない」を拾うため)

| 変数 | 意味 |
|---|---|
| `last_move_blocked` | 直前の移動が**閉まった扉**に阻まれて終わった |
| `last_move_failed` | 直前の移動が**家具などで詰まって**打ち切られた |
| `blocked_door_name` | 阻んだ扉の名前 |
| `last_steer_reason` / `last_desired` | デバッグ用。直近の操舵の理由と目標速度 |

### `Cat`

```gdscript
enum State { OUTSIDE_IDLE, APPROACH, ENTERING, INSIDE_WANDER, TO_COFFIN, ON_COFFIN, SHOOED, HIDING, POSED }
```

| メソッド | 備考 |
|---|---|
| `activate()` | 外に出して `OUTSIDE_IDLE`。20〜40 秒おきに `cat_meow_*` |
| `set_target_entry(opening)` | その開口部の外へ歩く。開いていれば侵入、閉まっていれば `cat_scratch_*` 3 回 + `window_tap` |
| `go_inside_now(opening := &"")` | 瞬間侵入(デバッグ・演出用) |
| `shoo()` / `flee()` | 外へ走る(3.0 m/s)。`shoo()` は `cat_hiss` 付き |
| `sit_at(pos, face_target := null)` | その場に座らせる演出。自販機の前に並べる、駐車場で見ている |
| `set_eye_glow(f)` | `Eyes` マテリアルの emission。既定 3.2 |
| `meow()` / `purr()` | |
| `state` / `state_name()` | 現在の状態 |
| `coffin_position()` / `coffin_top_y()` | 棺の座標と蓋の上面(実測 0.884) |

状態遷移: `OUTSIDE_IDLE` → `APPROACH` → (開いていれば)`ENTERING` → `INSIDE_WANDER` → `TO_COFFIN`
→ `ON_COFFIN`(蓋の上へ 0.4 秒で飛び乗って `sit`)。
プレイヤーが `[E] 追い払う` で `SHOOED` → 最寄りの開いた開口部から外へ。
全部閉まっていたら `HIDING`(室内の隅に 20 秒)→ また `TO_COFFIN`。

出すイベント: `cat_entered{entry}` / `cat_shooed{exit}`。
`cat_crossed_coffin` は systems の `CatZone` が出す(異変度 +3)。

### `Kasha`

| メソッド / シグナル | 備考 |
|---|---|
| `activate()` | 湯灌室の戸を開けて出現 → `chase_started` |
| `start_chase()` / `stop_chase()` | 停止で `chase_ended` |
| `retreat()` / `resume()` | 退却は `kasha_screech` → 最寄りの暗がりへ 4.0 m/s → 10 秒 idle → 再追跡 |
| `set_ceiling_mode(on)` | 天井を這う。y = `ceiling_height - body_height`(廊下で 1.60)、モデルを上下反転 |
| `go_to_and_take(target)` | 真エンド。到着で `took_target(target)` |
| `set_eye_glow(f)` / `distance_to_player()` | 目は距離で自動的に強まる(既定 5.0 × 1.0〜2.6) |
| `caught` | 1.2m 以内に入った。火車は 1 秒止まる。**演出は director** |
| `player_sees_me` | 視界(FOV 100°・遮蔽なし)に入っているか |

速さは見られている間 3.0 m/s、見失われている間 1.2 m/s(プレイヤーは 2.5)。
`relight_success` を受けると自動で `retreat()` する。
一度掴んだあとは `catch_rearm_distance`(2.4m)まで離れるまで掴み直さない。

### `NpcSon` / `NpcBoss` / `NpcGranddaughter`

社長と孫娘は `NpcBase` のまま(モデルと寸法だけ違う)。息子は追加で:

| メソッド / 変数 | 備考 |
|---|---|
| `go_to_hikaeshitsu()` | 控室の座布団の脇まで歩く |
| `drink_on_zabuton()` | 座卓の向こう側の座布団にあぐら(`sit_floor`) |
| `sleep()` | 横になっていびき。`Game` フラグ `son_asleep`、シグナル `fell_asleep` |
| `wake()` | 起こす |
| `is_sleeping` / `is_drinking` | |
| `drunk = true` | 歩行がわずかに蛇行する(`NpcBase.drunk`) |

いびきは `breath_close` をピッチ 0.72 で 4 秒周期。`snore_sound` で差し替えられる。

### `BodyRisen`

```gdscript
var br: BodyRisen = load("res://src/npc/body_risen.tscn").instantiate()
world.add_child(br)
br.global_position = coffin.global_position
br.rotation.y = coffin.rotation.y        # 棺の頭側 +X に合わせる
await br.rise()                          # rise アニメ 1 回 + body_rise 音 → risen
```

### `NpcUtil`(static)

| メソッド | 備考 |
|---|---|
| `OPENINGS` | 外から入れる 5 つの開口部(扉 2・窓 3)の内外の代表点、敷居の高さ、幅 |
| `is_opening_open(name)` / `opening_node(name)` / `opening_center(name)` | |
| `nearest_open_opening(from, only_open := true)` | |
| `snap(world, pos)` | ナビメッシュ上の最寄り点 |
| `clear_line(world, a, b, exclude)` / `visible_through_openings(...)` | 視線判定。後者は閉じた窓のガラス越しも「見えている」扱い |
| `set_emission(root, material_name, energy, color)` | マテリアルを複製してから emission を差し替える |
| `COFFIN_ROUTE` / `WANDER_POINTS` / `HIDE_SPOTS` / `DARK_SPOTS` | 経由点の表 |

---

## director 向けの使用例

### 猫を勝手口から入れる

```gdscript
var cat := NpcInstaller.find(&"cat", 2) as Cat   # Spawn_Cat3 = 勝手口のそば
cat.activate()
cat.set_target_entry(&"Door_Backyard")
Events.on(&"cat_entered", func(d): Tasks.set_task(&"shoo_cat", "猫を追い出す"))
Events.on(&"cat_crossed_coffin", func(_d): Game.set_flag(&"cat_crossed", true))
```

### 猫を演出で並べる

```gdscript
var cats := NpcInstaller.find_all(&"cat")
for i in cats.size():
    (cats[i] as Cat).sit_at(Vector3(-12.5, 0.0, 4.9 + i * 0.62),
        Vector3(-11.5, 0.2, 4.9 + i * 0.62))     # 自販機の前に 5 匹
```

### 火車の追跡開始と退却

```gdscript
var k := NpcInstaller.find(&"kasha") as Kasha
k.caught.connect(func(): Game.end_night(Game.ENDING_KASHA))
k.activate()                     # 湯灌室から出現 → chase_started
k.set_ceiling_mode(true)         # 廊下だけ天井を這う
Events.emit_event(&"relight_success", {"n": 1})   # 火車が自動で退く
k.stop_chase()                   # 完全停止 → chase_ended
```

### 火車が息子を連れて行く(真エンド)

```gdscript
var son := NpcInstaller.find(&"son") as NpcSon
if son.is_sleeping:
    building.get_door(&"Door_Hikaeshitsu").open()
    k.took_target.connect(func(_t): Game.end_night(Game.ENDING_SUBSTITUTE))
    k.go_to_and_take(son)
```

### 社長を帰らせる

```gdscript
var boss := NpcInstaller.find(&"boss") as NpcBoss
boss.set_talkable(true)
boss.talked.connect(func(_p): await Dialogue.say("社長", "線香は絶やすなよ。"))
await boss.go_to(Vector3(9.0, 0.0, -0.5))   # 式場へ同行
await boss.leave_via_genkan()               # 実測 5.7 秒 → npc_left{name:"boss"}
```

### 息子の来館から就寝まで

```gdscript
var son := NpcInstaller.find(&"son") as NpcSon
await son.enter_from_genkan(Vector3(9.0, 0.0, -0.5))
son.set_talkable(true)
# 「断る」を選んだあと
await son.go_to_hikaeshitsu()
son.drink_on_zabuton()
Events.after(180.0, func(): son.sleep())
```

### 孫娘を式場の後列に座らせる

```gdscript
var gd := NpcInstaller.find(&"granddaughter") as NpcGranddaughter
gd.sit_on_chair(Vector3(10.9, 0.0, 1.1), -90.0)
gd.set_talkable(true)
```

---

## 検証

```bash
godot --path . res://src/npc/_test_npc.tscn -- --no-capture --scenario=cat_enter
#   cat_enter / cat_shoo / boss_leave / kasha_chase / son_sleep / api / facing / free
```

状態遷移とイベントを print しながら `out/npc/` にスクリーンショットを残す。
`--out=<dir>` で出力先、`--scenario=free` で自由に見回せる。

目視して合格と判断したもの:

| スクリーンショット | 判断 |
|---|---|
| `03_cat_03_on_coffin.png` `04_cat_04_coffin_wide.png` | 猫が蓋の上に座り、頭が部屋側を向いている。`cat_crossed_coffin` 発火 |
| `03_shoo_03_outside.png` | 追い払われた猫が勝手口の外に出ている |
| `02_boss_02_walking.png` `03_boss_03_gone.png` | 社長が歩き、玄関のガラス戸が閉まって消えている |
| `02_kasha_02_hall_near.png` `03_kasha_03_ceiling.png` | 火車が廊下を這い、天井に逆さで張り付いている |
| `04_kasha_04_caught.png` `05_kasha_05_retreat.png` | 追いつき → 退却 |
| `02_son_02_drinking.png` `03_son_02b_drinking_side.png` | 息子が座卓の向こうの座布団であぐら。TV 台と重ならない |
| `04_son_03_sleeping.png` `06_son_05_sleeping_top.png` | 畳に伏せて寝ている。座卓・布団・TV 台のどれとも当たらない |
| `07_son_05_granddaughter_sit.png` | 孫娘がパイプ椅子に座っている |
| `01_api_01_cats_vending.png` | 猫 5 匹が自販機の前に並び、目が光っている |
| `02_api_02_kasha_takes_son.png` | 火車が寝ている息子の上に立っている |

`godot --headless --path . --import` ×2 と `--quit` はエラーなし。
`--quit` に残る `ObjectDB 2 件` の警告は npc を作る前から出ているもの(models 申し送り 2 番)。

---

## 他担当への依頼

1. **models**: `cat.glb` だけ頭が **+Z** 側で、ほかのキャラ(-Z 正面)と逆向きです。
   `--scenario=facing` で「+X を向け」と指示して両側から撮り、確定しました。
   いまは `Cat._init` の `model_yaw_offset_deg = 180` で見た目だけ回しています。
   glb を直すなら、この 1 行を消してください。

2. **audio**: いびきの音がありません。`breath_close` をピッチ 0.72 で代用しています。
   専用の `snore`(2〜3 秒・ループ可)があれば `NpcSon.snore_sound` を差し替えるだけです。

3. **level**(対応済みなので記録のみ): 受付台の内側に居た社長のスポーンと、ナビメッシュが
   家具を迂回しない件は `40b9d0b` で直していただきました。

---

## 未解決の問題

1. **ナビメッシュは扉を障害物にしていない**ので、閉扉の通り抜け防止は `NpcBase` 側で
   線分と扉の開口面の交差を毎フレーム見ています。人間は扉を開けて進み、猫は
   `blocked_give_up`(6 秒)待って引き返します。扉がナビに入るなら、この判定は外せます。

2. **式場の椅子(4 列 × 5 脚)がナビメッシュに入っているか未確認。**
   猫が棺へ向かうときだけは、椅子を避けるために中央通路(z = -0.5)と焼香台の南(z = -1.35)を
   通る固定ルート `NpcUtil.COFFIN_ROUTE` を歩かせています。
   確かめるには `_test_npc.tscn` の `cat_enter` で `COFFIN_ROUTE` を空にして走らせ、
   `[npc] … へ到達できないので打ち切り` が出ないかを見るのが早いです。

3. **湯灌室のステンレス台と棚に挟まれた火車のスポーン。**
   `Spawn_Kasha (7.3, -11.0)` は台(x 6.25〜8.35)と棚(x 5.45〜5.85)の間にあり、
   まっすぐ戸へ向かうと詰まります。`Kasha.spawn_exit_route` で台の東(x 8.82)を
   回って出る経路を持たせて回避しています。level 側で台の位置か spawn が動いたら、
   この 2 点も直す必要があります。

4. **`Kasha.catch_rearm_distance`(2.4m)。** 一度掴んだあと、プレイヤーがこの距離まで
   離れるまで掴み直しません。director が `caught` でそのままエンディングに入るなら
   関係ありませんが、「掴まれても続く」演出にするならここを詰めてください。

5. **猫の `sit` は尻が床から数 cm 浮いています**(models 申し送り 4 番)。
   棺の蓋の上ではほとんど分かりません。

6. **`despawn()` はノードを残します。** メモリより「あとから戻せる」ことを優先しました。
   完全に消したい場合は director 側で `queue_free()` してください
   (そのあと `NpcInstaller.find()` は null を返すようになります)。
