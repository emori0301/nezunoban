# systems 引き継ぎメモ

`src/systems/` 担当からの申し送り。最終報告の途中で切れた「他担当への依頼」と「未解決」の全文。
API と使い方の例はスクリプト冒頭の doc コメントに書いてあるので、そちらを正とする。

## 前提: モデルは +Z が正面

`assets/models/*.glb` は **+Z が正面**。監視モニターの画面、TV の画面、遺影の写真はすべて +Z を向く。
プレハブ側の `screen_offset` / `photo_offset` もその前提で入っている。
アンカーの向きもこれに合わせること(式場のスクリーンショットで確認済み)。

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

## models への依頼(優先度順)

1. **`coffin.glb` の蓋に小窓の穴が無い。** `Window` は枠メッシュだけで、その下は蓋の板が塞いでいる。
   そのため `body_face.glb` を棺の中に置いても見えない。いまは顔を**薄い板**として
   小窓のガラス面のすぐ上(`Coffin.face_lift = 0.0012`)に重ねて代用している。
   穴を開けてもらえれば `Coffin.use_face_model = true` で立体の `body_face.glb` に切り替えられる
   (コードは残してある)。
2. **蓋・扉の独立ノードが無い。** `coffin.glb` / `freezer_chest.glb` / `safe.glb` に
   名前へ `Lid` / `Door` を含む Node3D を切ってほしい。あれば `Coffin.set_lid_ajar()`、
   `Freezer` の開閉、`Safe.open()` の扉アニメが見た目にも出せる(名前で自動的に拾う実装済み)。
   いまは音と状態だけ変わって見た目は動かない。
3. `breaker_box.glb` に `Lever` ノードがあるとブレーカーの上下を見た目で出せる。
   いまはモデルがある場合、自前の仮レバーを非表示にしている。
4. マテリアル名で拾っている箇所があるので、名前は変えないでほしい。
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
2. **棺の小窓に穴が無い件**(models 依頼 1)。回避策で成立しているが、
   浅い角度から見ると顔が平面だとわかる。
3. `godot --headless --path . --quit` が終了時に `1 resources still in use at exit` を出す。
   `src/systems/installer.tscn` を外しても同じメッセージが出るので systems 由来ではない。

## 検証の落とし穴(全担当向け)

`godot --headless --path . --import` と `--quit` は、**どこからも参照されていないスクリプトの
パースエラーを検出しない**。実際 `system_util.gd` の型推論エラーを両方とも素通りした。
自分のディレクトリの `.gd` / `.tscn` / `.gdshader` を全部 `ResourceLoader.load` する
小さなスクリプトを併用しないと見落とす。
