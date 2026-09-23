# 寝ずの番 | The Wake

チラズアート型の一人称 3D ジャパニーズホラー。田舎の家族葬ホールで、出棺までの一夜(実時間 約24分)を宿直として過ごす。

## 遊び方

```bash
./play.sh            # 起動(タイトル画面から)
./play.sh -- --skip-title --time=01:00   # デバッグ: 途中の時刻から
```

| 操作 | キーボード・マウス | ゲームパッド |
|---|---|---|
| 移動 | W A S D / 矢印 | 左スティック |
| 視点 | マウス | 右スティック |
| 調べる・使う | E / 左クリック(長押しあり) | A / × |
| 会話を進める | Space / Enter / E | A / × |
| クリップボード(掟とタスク) | Tab | Y / △ |
| ポーズ・設定 | Esc | Start |
| メニューで戻る | Esc | B / ○ |

設定(マウス感度・音量・VHS の強さ)はポーズメニューから。初回起動時に操作ヒントが出る。

## 掟

一、線香を絶やさぬこと　一、灯明を絶やさぬこと　一、猫を入れぬこと　一、棺の小窓を開けぬこと　一、眠らぬこと

エンディングは4種。周回前提。

## アプリとして書き出す

```bash
./build.sh      # out/build/NezuNoBan.app(macOS universal、ad-hoc 署名)
```

初回は Godot の export テンプレート(4.7.1)が `~/Library/Application Support/Godot/export_templates/4.7.1.stable/` に必要。

## 開発

設計は `docs/design.md`、台本は `docs/script.md`、実装の約束事は `CLAUDE.md`。
素材(3D モデル・テクスチャ・効果音)はすべてスクリプトで生成している(`tools/`)。
フォント: DotGothic16 / Shippori Mincho(SIL OFL)。
