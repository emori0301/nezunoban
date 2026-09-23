# systems 引き継ぎメモ

`src/systems/` 担当からの申し送り。最終報告の途中で切れた「他担当への依頼」と「未解決」の全文。
API と使い方の例はスクリプト冒頭の doc コメントに書いてあるので、そちらを正とする。

## 前提: モデルは +Z が正面

`assets/models/*.glb` は **+Z が正面**。監視モニターの画面、TV の画面、遺影の写真はすべて +Z を向く。
プレハブ側の `screen_offset` / `photo_offset` もその前提で入っている。
アンカーの向きもこれに合わせること(式場のスクリーンショットで確認済み)。

## プレハブの向き(2026-09-23 の向き監査で対応)

アンカーの規約は「-Z がプレイヤーの立つ側」、models のモデルは多くが前面 +Z。
ただし **一律 +180 では合わない**(棺・供花・線香立て・流し・布団・マッチは 0 が正しい)。

systems 側で表を二重に持つとずれるので、**level のプレースホルダ
`"<Anchor 名>_Prop"` の向きをそのまま踏襲する**ようにした
(`SystemsInstaller._facing_for()`)。level が `add_anchor_prop(..., prop_yaw)` を
変えれば systems も自動で追従する。プレースホルダが無いアンカー
(`Anchor_BossDesk` / `Anchor_Candle`)だけ既定の +180 を当てている。

19個すべてについて、置いたノードの yaw が level のプレースホルダと一致することを
数値で確認済み(`Anchor_BossDesk` は `Desk_Boss` の yaw 0 と一致、`Anchor_Candle` は
祭壇まわりと同じ -90)。

## level への依頼

- アンカーは 19 個すべて見つかった。`Anchor_Cam_Shikijo` / `Anchor_Cam_Genkan` も解決済みで、
  監視モニターに式場と玄関が映っている。
- `Building.hide_anchor_prop()` は systems 側から呼ぶようにした。プレハブを置いた 19 個の
  アンカーについて、**配置から 2 フレーム後**にまとめて呼んでいる。
  即時に呼ぶとレンダラが解放済みマテリアルを参照して
  `Parameter "material" is null`(`material_casts_shadows` ほか)を 8 件出すため、
  2 フレーム待ってから消している。level 側で直せるなら `queue_free()` の前に
  `MeshInstance3D` の `material_override` を null にしてから消すと根治すると思われる。
- **式場の天井に大きな暗い帯が出る**(下記「未解決」参照)。照明とシャドウは level の担当なので調査をお願いしたい。

## npc への依頼

- 棺の上面に `CatZone`(Area3D、`collision_mask = 12`)がある。**group `cat`** に入っている
  ノードが入ると `cat_crossed_coffin` + 異変度 +3 + 棺が軋む、が自動で走る。
  猫の当たり判定が Area3D でも CharacterBody3D でも拾えるようにしてある
  (`body_entered` / `area_entered` の両方、親を 3 段までたどって group を見る)。
  マスクは npc レイヤー(値 8)と player レイヤー(値 4)の両方を見ているが、
  group `cat` でフィルタしているのでプレイヤーが跨いでも発火しない。
- 猫を置くときは `collision_layer` に 8 か 4 のどちらかを入れて `monitorable = true` にすること。

## director への依頼(review_1 の修正に伴うもの)

- **`Clock.speed` は systems 側で掛けるようにした。** 線香とロウソクの残量は
  `delta * burn_multiplier * Clock.speed` で減る(review_1 L2)。
  autoplay が `burn_seconds` を速度で割って辻褄を合わせていたはずなので、
  **その割り算を外してほしい**。外さないと二重に効いて線香が一瞬で尽きる。
  `docs/previews/director_notes.md` の autoplay の記述も直してほしい。
- **監視モニターは事務所にいるときだけ描くようにした**(review_1 M3)。
  `--cctv-shot` のようにプレイヤーが事務所に居なくても映像が要るときは
  `mon.set_force_update(true)` を呼んでから撮り、終わったら false に戻すこと。
  `mon.is_feed_updating()` で今描いているか確認できる。
- 電話は受話器が上がっていても `ring()` が通るようにした(review_1 M1)。
  勝手に `hang_up()` してから鳴るので、呼び出し側は今までどおりでよい。

## director への依頼・使い方

- 取り出しは `SystemsInstaller.find(&"coffin")`。供花だけ左右 2 つあるので `find_all(&"flower_stand")`。
- 日本語の台詞(「線香が無い。」「……開けてはいけない。」「少し休むか」など)は全部 `@export` にしてある。
  director 側から差し替えられる。CLAUDE.md の「日本語文字列は director 以外にハードコードしない」に
  抵触しないようにするため。
- `Coffin.allow_open_window` は **既定 false**。掟4「棺の小窓を開けぬこと」があるので、
  自発的に覗こうとすると独白で拒否する。ドライアイス交換のときだけ顔が見える
  (design.md の「顔を見る唯一の機会」)。00:30 に息子へ開けさせたら true にする。
- `Phone` は `await ph.answered` だと取り逃したときに永久に待つ。
  `var ok: bool = await ph.call_ended` を使うこと。
- `Candle.require_matches = true` にすると `required_item = &"matches"` と長押し 1.2 秒に自動で切り替わる。
  `fail_next = true` で次の 1 回だけ必ず失敗する(火車エンドの詰み演出)。
- モニターにだけ映す脅かしは `mi.layers = SystemUtil.LAYER_CCTV_ONLY`(1 << 9)。
  逆にモニターに映したくないものは `LAYER_PLAYER_HIDDEN`(1 << 10)。詳細は `monitor.gd` の冒頭コメント。
- 確認用に `godot --path . -- --skip-title --systems-demo` を用意した。
  線香とロウソクを点け、TV をつけ、`set_all_lights(true)` を呼ぶ。director ができたら不要。

## models との取り決め(2026-09-23 の追加分その3 で対応済み)

依頼した可動部はすべて入った。systems 側は名前で拾って動かしている。**名前を変えないでほしい。**

| モデル | ノード | systems 側の使い道 |
|---|---|---|
| `coffin` | `Lid` | `set_lid_ajar()` は `position.x += 0.10`、`set_open()` は X 回転 62 度 |
| 同上 | `Window`(Lid の子) | `set_window_open()` / `show_face()` で `visible = false` にして小窓を開ける |
| `freezer_chest` | `Lid` | X 回転 -74 度で開く |
| `safe` | `Door` | Y 回転 -108 度で開く |
| `breaker_box` | `Lever` | `trip()` で X 回転 38 度に倒す |
| `phone` | `Handset` | 受話器を取ると持ち上がる |

`body_face.glb` は棺ローカル (0.64, 0.275, 0) に立体のまま置いている(`Coffin.face_model_offset`)。
庫内が空洞になったので、冷凍庫には `dry_ice_box.glb` を (0, 0.30, 0) に置き、
`set_empty(true)` で消えるようにした。金庫の台帳は棚板の上 (0, 0.315, 0)。
`coffin_lid_open.glb` は `Lid` を回せるようになったので使っていない。

マテリアル名でも拾っているので、こちらも変えないでほしい。
   `Screen`(monitor_crt / tv_crt)`Flame`(candle_stand)`Ember`(incense_stand)
   `Photo`(iei_frame)`Face`(body_face)`Flower` / `Leaf`(flower_stand)。

## player への依頼

- `give_item(name)` / `give_item(name, carried)` のどちらの実装でも動くようにしてある
  (`Callable.get_argument_count()` で分岐)。今のところ 2 引数版として呼んでいる。
- `teleport(pos, yaw, pitch)` の pos は**目の高さ**として扱っている(`docs/viewpoints.json` と同じ)。

## 未解決

1. **式場の天井に大きな暗い帯が出る。**
   再現: `godot --path . -- --skip-title --pos=16.0,1.6,-0.5 --yaw=-90 --pitch=32`
   systems のプレハブを置くと出て、`src/systems/installer.tscn` を外すと消える。
   ただし切り分けた結果、**systems 側の原因は否定された**:
   - 置いたノードの `cast_shadow` を全部 OFF にしても消えない
   - 置いたノードの Light3D を全部 `visible = false` にしても消えない
   - 監視モニターの SubViewport を `UPDATE_DISABLED` にしても消えない
   - `hide_anchor_prop` を呼ばなくても出る
   - 棺 / 祭壇 / 供花 / モニターを 1 つだけ置いた場合はほぼ出ない(全部置くと出る)
   置いた物の数が増えると出るので、式場の照明のシャドウマップ(positional shadow atlas)の
   解像度不足を疑っている。project.godot の `lights_and_shadows/*` か、
   式場のライト構成の見直しで直る可能性が高い。level と監督で確認してほしい。
2. **金庫が in-game では暗くて見えない。** 事務所奥の隅に照明が届いておらず、
   `--systems-demo`(全照明 on)でも扉が開いたかどうか画面では判別できない。
   動作自体はロジックテストで確認済み。照明は level の担当なので確認してほしい。
   再現: `godot --path . -- --skip-title --systems-demo --pos=-9.7,0.75,8.5 --yaw=142 --pitch=-19`
3. モニターは本体を `player_hidden`(レイヤー11)へ移していたため、
   プレイヤーのカメラからも見えなくなっていた。既定をやめ、`hide_from_cctv`
   という export にした(既定 false)。式場/玄関のカメラは事務所を映さないので
   入れ子にはならない。監視カメラの `cull_mask` も「11 以外すべて」に広げた。
   level が別のレンダーレイヤーを使っても映像が真っ暗にならないようにするため。
4. `godot --headless --path . --quit` が終了時に `1 resources still in use at exit` を出す。
   `src/systems/installer.tscn` を外しても同じメッセージが出るので systems 由来ではない。

## 検証の落とし穴(全担当向け)

`godot --headless --path . --import` と `--quit` は、**どこからも参照されていないスクリプトの
パースエラーを検出しない**。実際 `system_util.gd` の型推論エラーを両方とも素通りした。
自分のディレクトリの `.gd` / `.tscn` / `.gdshader` を全部 `ResourceLoader.load` する
小さなスクリプトを併用しないと見落とす。
