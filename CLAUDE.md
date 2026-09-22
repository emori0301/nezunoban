# 寝ずの番 | The Wake

チラズアート(Chilla's Art)型の一人称 3D ジャパニーズホラー。Godot 4.7.1 / GDScript / Forward+。
設計の正本は `docs/design.md`。ここには**実装の約束事**だけを書く。

## 環境とコマンド

- Godot: `/opt/homebrew/bin/godot`(4.7.1)。C# は使わない。
- Blender: `/opt/homebrew/bin/blender`(5.2)。モデルは `tools/blender/*.py` で生成し `assets/models/*.glb` に出力する。Blender の python には numpy がある。
- システム python3 (3.9) には numpy/PIL が**無い**。画像や音の生成は `blender --background --python <script>` で行う。

```bash
godot --headless --path . --import          # 新規ファイル追加後は必ず(.uid と import 生成)。初回だけ落ちることがあるので2回叩く
godot --headless --path . --quit            # スクリプトエラーの最短チェック(出力にエラーが無いこと)
godot --path . -- --screenshot=out/x.png --pos=0,1.6,3 --yaw=180 --pitch=-5 --time=23:00 --wait=1.5
godot --path . -- --tour=out/tour           # docs/viewpoints.json の視点を全部撮る
godot --path . -- --skip-title --time=01:00 --debug   # デバッグ: F2/F3 で時間倍速, F4 で+1h, F5 でスクショ
```

**「テストが通る」は品質の証明にならない。必ずスクリーンショットを撮って画像を目で見る。**
`.godot/` `out/` は生成物、コミットしない。

## ディレクトリと担当(所有権)

並列で作業するので、**自分の担当ディレクトリ以外は編集しない**。他担当に必要な変更は、依頼内容を最終報告に書く。

| ディレクトリ | 内容 | 担当 |
|---|---|---|
| `src/autoload/` | Game / Clock / Dread / Events / Audio / Dialogue / Tasks | 監督(変更は依頼) |
| `src/interact/` | `Interactable` 基底 | 監督 |
| `src/main.gd` `src/main.tscn` | 起動と組み立て、CLI フック | 監督 |
| `src/player/` | 一人称コントローラ、視線インタラクト、持ち物、足音 | player |
| `src/ui/` | HUD(タイムスタンプ/タスク/プロンプト/字幕/選択肢/手紙リーダ/クリップボード/フェード)、タイトル、エンディング画面 | player |
| `src/fx/` | VHS ポストエフェクト、画面演出(ノイズ増幅、暗転、ズーム) | player |
| `src/level/` | 建物、部屋、床/壁/天井、照明、扉、窓、アンカー、外周、ナビメッシュ | level |
| `src/systems/` | 線香、ロウソク、電話、モニター、冷凍庫/ドライアイス、棺、分電盤、金庫、布団、手紙、供花/流し、芳名帳、TV、マッチ、線香箱 | systems |
| `src/npc/` | NPC(社長/息子/孫娘)、猫 AI、火車 AI、会話トリガー | npc |
| `src/director/` | 夜の台本(時刻イベント)、会話テキスト、脅かしの発火、エンディング分岐 | director |
| `assets/models/` `assets/textures/` `tools/blender/` | 3D モデルとテクスチャ | models |
| `assets/audio/` `tools/audio/` | 効果音・環境音の生成 | audio |
| `assets/fonts/` | DotGothic16(UI), ShipporiMincho(タイトル/手紙) | 監督 |

## 共通 API(autoload)

- `Game.set_flag(&"son_refused")` / `Game.get_flag(&"pages", 0)` / `Game.add_flag(&"pages")` / `Game.end_night(Game.ENDING_MORNING)` / `Game.player`
- `Clock.game_minutes`(21:00 = 0)/ `Clock.time_string()` → `"PM 11:32"` / `Clock.hhmm()` / `Clock.skip_to(min)` / `Clock.start()`
- `Dread.add(1, &"incense_out")` / `Dread.value` / `Dread.level()` 0..2 / `Dread.is_doomed()`
- `Events.at("23:00", callable)` / `Events.after(sec, callable)` / `Events.emit_event(&"name", {})` / `Events.on(&"name", callable)`
- `Audio.play(&"door_open")` / `Audio.play_at(&"cat_meow", pos)` / `Audio.ambient(&"amb_room")` / `Audio.stop_ambient(&"amb_room")` / `Audio.set_muffled(true)`
- `await Dialogue.say("社長", "…")` / `var i := await Dialogue.choose("…", ["断る", "開けさせる"])` / `await Dialogue.note("日記 1", body)` / `await Dialogue.monologue("…")`
- `Tasks.set_task(&"incense", "線香を立てる")` / `Tasks.complete(&"incense")`

## Interactable の約束

- `Interactable extends Area3D`(layer 2)。子に `CollisionShape3D` を必ず持つ。派生は `_can_interact(player)` と `_interact(player)` を実装。
- `prompt` は日本語の動詞句(「線香を立てる」「小窓を開ける」)。HUD が `[E] 線香を立てる` と表示する。
- `hold_time > 0` で長押し(HUD がリングを出す)。`required_item` で持ち物条件。
- プレイヤーは `has_item(name) -> bool` / `give_item(name)` / `take_item(name)` / `carried_item: StringName` / `teleport(pos, yaw_deg, pitch_deg)` / `set_locked(bool)`(操作ロック)/ `look_at_point(pos, dur)` を持つ。

## イベント名(Events バス)

`incense_out` `incense_lit` `candle_out` `candle_lit` `cat_entered` `cat_shooed` `cat_crossed_coffin` `phone_ring` `phone_answered` `phone_missed` `door_opened{door}` `door_closed{door}` `window_opened{window}` `window_closed{window}` `breaker_off` `breaker_on` `page_read{n}` `dry_ice_replaced` `flowers_watered` `coffin_window_opened` `futon_rest` `task_completed{id}` `player_entered_room{room}` `npc_left{name}` `chase_started` `chase_ended` `relight_success{n}`

## レベルのアンカー名(level が置き、systems/npc/director が使う)

`Spawn_Player` `Spawn_Boss` `Spawn_Granddaughter` `Spawn_Son` `Spawn_Cat1..Spawn_Cat5` `Spawn_Kasha`
`Anchor_Coffin` `Anchor_Altar` `Anchor_Iei` `Anchor_IncenseStand` `Anchor_Candle` `Anchor_FlowerL` `Anchor_FlowerR` `Anchor_Sink` `Anchor_Phone` `Anchor_Monitor` `Anchor_Freezer` `Anchor_Breaker` `Anchor_Safe` `Anchor_Futon` `Anchor_TV` `Anchor_GuestBook` `Anchor_IncenseBox` `Anchor_Matches` `Anchor_BossDesk` `Anchor_Cam_Shikijo` `Anchor_Cam_Genkan`
部屋: `Room_Genkan`(玄関/受付) `Room_Office`(事務所) `Room_Hall`(廊下) `Room_Shikijo`(式場) `Room_Hikaeshitsu`(控室・和室) `Room_Toilet` `Room_Backyard`(バックヤード) `Room_Yukan`(湯灌室) `Room_Outside`(外周)
各 Room_* は `Area3D`(layer 0 / mask 4=player) を持ち、プレイヤー侵入で `Events.emit_event(&"player_entered_room", {"room": name})`。
照明: `Building.set_room_lights(room: StringName, on: bool)` / `Building.set_all_lights(on)` / `Building.flicker(room, duration)`。
扉: `Door`(Interactable)`open()` `close()` `locked` `is_open`、名前 `Door_Genkan` `Door_Backyard`(勝手口) `Door_Shikijo` `Door_Office` `Door_Hikaeshitsu` `Door_Toilet` `Door_Yukan`。窓: `Window_Shikijo` `Window_Toilet` `Window_Office`。
ナビ: `NavigationRegion3D` を持ち、起動時に bake 済み(猫/火車/NPC が NavigationAgent3D で歩く)。

## 音名一覧(audio が生成、他はこの名前で呼ぶ)

環境ループ: `amb_room`(冷蔵庫の唸り+空調)`amb_outside`(晩秋の夜、風、遠い国道)`amb_shikijo`(式場の静けさ+微かな線香の燃える音)`amb_tatami`(控室、時計の秒針)`amb_freezer` `amb_vending` `amb_fluorescent`(蛍光灯のジー)`amb_drone_low`(不穏ドローン)`amb_drone_high`(危険ドローン)`amb_static`(モニターのノイズ)
単発: `step_lino_1..4` `step_tatami_1..4` `step_concrete_1..4` `door_open` `door_close` `door_locked` `door_steel_open` `door_steel_close` `door_knock_1..3` `window_open` `window_close` `window_tap` `incense_light` `incense_hiss` `candle_light` `candle_blow` `match_strike` `match_fail` `phone_ring` `phone_pickup` `phone_hangup` `phone_breath` `phone_voice_wet`(「かえして」の代わりの濡れた低い唸り)`cat_meow_1..3` `cat_hiss` `cat_scratch_1..3` `cat_purr` `coffin_knock` `coffin_creak` `coffin_scratch` `coffin_lid_slide` `breaker_click` `lights_off` `lights_on` `fluorescent_flicker` `freezer_open` `freezer_close` `dry_ice_sizzle` `water_pour` `paper_rustle` `page_turn` `book_close` `safe_dial` `safe_open` `tv_on` `tv_static` `tv_off` `chair_drag` `tatami_creak` `footstep_ceiling_1..3` `whisper_1..3` `breath_close` `heartbeat` `stinger_1..3`(短いショック音)`kasha_screech` `kasha_crawl` `kasha_growl` `body_rise` `crow_morning` `chime_dawn` `ui_select` `ui_confirm` `ui_back` `vhs_tracking`
すべて WAV 44.1kHz mono 16bit(環境ループは 8〜20 秒でシームレス)。

## モデル名一覧(models が生成、level が `Prop` の model_name で置く)

`coffin`(棺、蓋に小窓)`coffin_lid_open`(蓋ずれ版)`body_face`(白布と顔、小窓越し用)`altar`(三段祭壇、白布)`iei_frame`(遺影・黒縁・リボン)`incense_stand`(香炉)`candle_stand`(燭台)`flower_stand`(供花スタンド)`folding_chair` `low_table` `zabuton` `futon` `tv_crt` `office_desk` `office_chair` `phone` `monitor_crt` `freezer_chest` `dry_ice_box` `vending_machine` `breaker_box` `safe` `door_wood` `door_steel` `window_frame` `sink` `shelf` `cabinet` `kettle` `guest_book_stand` `umbrella_stand` `slippers` `wall_clock` `fire_extinguisher` `notice_board` `sake_bottle` `beer_can` `matches` `incense_box` `coil_incense` `hearse` `tree` `fence` `lantern` `cat`(アニメ: idle/walk/sit)`kasha`(アニメ: crawl/idle)`npc_boss` `npc_son` `npc_granddaughter`(アニメ: idle/walk)`body_risen`(起き上がった故人)`hanging_robe`(湯灌室の白装束。アニメ: sway/drop)
デカール: `assets/textures/paw_print.png`(濡れた猫の足跡)`handprint.png`(小窓の内側の手形)
各モデルの使い方の注意(小窓の `Window` メッシュ、扉の原点、発光マテリアル名、顔テクスチャの対応表)は `docs/previews/models_notes.md`。
単位: メートル、Y-up、原点は接地面の中心。テクスチャは 128〜256px、`assets/textures/`。PSX 風(ローポリ、頂点数は小物 50〜400、人物 600〜1500)。

## コーディング規約

- 4.7 の型付き GDScript。`@export` と `class_name` を使う。シグナル/グループで疎結合。直接パス参照は同一シーン内のみ。
- ノード名は PascalCase、シグナルとメソッドは snake_case。日本語文字列は director 以外にハードコードしない(prompt は例外)。
- 画面上の文字は DotGothic16。`SubViewport` 640×360 で描画されるので UI は 16px 前後で設計する。
- 新規ファイルを作ったら `godot --headless --path . --import` を2回。最後に `godot --headless --path . --quit` でエラーが出ないこと。
- 各担当は自分のディレクトリ内に `_test_<name>.tscn`(動作確認用の単体シーン)を置いてよい。撮影は `godot --path . -- --screenshot=...` か、自分のテストシーンを main に指定して `godot --path . res://src/<dir>/_test_x.tscn` で起動する。

## git

- ブランチ `work/v1` で作業。コミットは「1つの意図 = 1コミット」、メッセージは日本語で「何のために」。
- 担当エージェントはコミットしない(監督がまとめてコミットする)。

## 起動時の組み立て順(main.gd)

1. `src/level/building.tscn` を World に追加
2. `src/systems/installer.tscn` と `src/npc/installer.tscn` があれば World に追加(それぞれ `Anchor_*` / `Spawn_*` を `find_child` で探し、自分のプレハブを置く)
3. `src/player/player.tscn` を `Spawn_Player` に置き `Game.register_player`
4. `src/ui/hud.tscn` を SubViewport 内に、`src/fx/vhs_layer.tscn` を Main 直下に(`attach(container)`)
5. `src/director/director.tscn` を Main 直下に。director が `Clock.start()` する(無ければ main が始動)
