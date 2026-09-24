class_name ScriptText
extends RefCounted
## docs/script.md のテキストを定数にしたもの。**ここが唯一の日本語テキストの置き場**。
## 台詞・収集物・エンディング文は docs/script.md から一字も変えずに写している。
##
## 例外(docs/script.md に無い追加行)は ADDED_* に分けてある。監督の指示で足した行なので、
## docs/script.md 側にも追記してもらう必要がある。最終報告に書くこと。

# ============================================================ 掟(クリップボード)

const RULE_LINES := [
	"一、線香を絶やさぬこと",
	"一、灯明を絶やさぬこと",
	"一、猫を入れぬこと",
	"一、棺の小窓を開けぬこと",
	"一、眠らぬこと",
]

## HUD の set_rules(PackedStringArray) に渡す形。
## (PackedStringArray(...) は const にできないので static func にしてある)
static func rules() -> PackedStringArray:
	return PackedStringArray(RULE_LINES)

const SPEAKER_BOSS := "社長"
const SPEAKER_HIKARI := "ひかり"
const SPEAKER_SON := "誠"

# ============================================================ 21:00 社長

## 受付で最初に話しかけたとき
const BOSS_RECEPTION := [
	"来たか。昨日言った通り、今夜は寝ずの番だ。",
	"故人は春日キヨさん。八十八。家で亡くなった。",
	"火葬場が友引で埋まっててな。出棺は明日の朝。それまで誰かがついてなきゃならん。",
]

## 事務所(クリップボードを渡す)
const BOSS_OFFICE := [
	"これを持ってろ。掟は五つ。読んどけ。",
]

## 式場、棺の前(ここで線香を立てさせる)
const BOSS_INCENSE := [
	"線香だ。一本で一時間もたない。切らすな。",
]

## 線香を立てたあとの残りの掟
const BOSS_RULES := [
	"灯明もだ。こっちは長い。日付が変わる頃に替えろ。",
	"猫を入れるな。この辺は野良が多い。",
	"棺の小窓は開けるな。遺族が開けろと言っても、だ。",
	"一時と五時にドライアイス。裏の冷凍庫だ。",
	"何かあったら事務所の電話に俺の番号が貼ってある。まあ、何もない。",
	"あと、寝るな。寝ずの番だからな。",
]

## 21:20 玄関で帰るとき
const BOSS_LEAVE := [
	"勝手口の鍵、閉めとけよ。開いてる。",
	"じゃあな。五時に来る。",
]

## docs/script.md に無い追加行(監督の指示)。式場の蛍光灯を消す動機づけ。
const ADDED_BOSS_LIGHTS := [
	"式場の蛍光灯は消しとけ。灯明があれば十分だ。",
]

# ============================================================ 21:10 孫娘

const HIKARI := [
	"……お疲れさまです。ひかりです。孫の。",
	"おばあちゃん、猫を飼ってたんです。二十匹くらい。",
	"父が全部、保健所に。先月。",
	"おばあちゃんは、その次の週に。",
	"これ、おばあちゃんの日記です。最後のページ。",
	"読んでもらえますか。私は、怖くて。",
]

## 日記を読んだあと
const HIKARI_AFTER := [
	"今夜、よろしくお願いします。",
	"猫が来ても、叩かないであげてください。",
]

# ============================================================ 00:30 息子

const SON_KNOCK := [
	"開けろ。喪主だ。",
]

const SON_ENTER := [
	"顔を見せろ。最後だ。",
]

const SON_CHOICE_PROMPT := "小窓を開けさせるか"
const SON_CHOICE_OPTIONS := ["断る", "開けさせる"]

const SON_REFUSED := [
	"……チッ。真面目だな。",
	"いい。控室で待つ。朝まで飲む。",
]

const SON_ALLOWED := [
	"……目が。",
	"目が開いてる。昨日は閉じてただろ。",
	"もういい。帰る。朝には来る。燃やす。さっさと燃やす。",
]

# ============================================================ 収集物

const PAGE1_TITLE := "日記 — 最後のページ"
const PAGE1_BODY := """十月九日
猫がまた増えた。十九になった。
誠は気味が悪いと言う。保健所に電話していた。
猫は私を見ている。夜、枕元に座って、寝ずの番をしてくれる。
猫は知っている。誰が悪いことをしたか。
私が死んだら、誰が番をしてくれるだろう。
線香だけは、絶やさないでほしい。"""

const PAGE2_TITLE := "宿直日誌 — 十月十四日"
const PAGE2_BODY := """十月十四日 春日家 仮通夜
猫を入れるな。
棺の中で音がしても開けるな。
線香を切らした。三十分だけ。
戻ったら椅子が全部、棺の方を向いていた。
社長に言ったら笑われた。
今夜で辞める。"""

const PAGE3_TITLE := "納棺師のメモ"
const PAGE3_BODY := """春日キヨ様 処置記録
首に索状痕のような痣。頸部に鬱血。
社長に報告。
「検案は済んでいる。余計なことを言うな」
化粧で隠すよう指示された。
隠した。
私は何も見ていない。"""

const PAGE4_TITLE := "台帳 — 春日家"
const PAGE4_BODY := """春日 誠 様
基本料金　　　　　¥380,000
検案書手配(特)　¥300,000
火葬　最短　友引明け
備考: 警察不要。本人了承。"""

# ============================================================ クレジット

## [文字列, 文字サイズ]。空文字は余白(サイズが高さ)。
## 文面は docs/script.md「クレジット(エンディング後)」のまま。
## 「(あなたの名前)」は指示どおりそのまま置いてある。
const CREDITS := [
	["寝ずの番 | The Wake", 26],
	["", 34],
	["企画・制作: (あなたの名前)", 18],
	["", 20],
	["Made with Godot", 18],
	["", 20],
	["フォント: DotGothic16, Shippori Mincho (SIL OFL)", 15],
]


# ============================================================ 芳名帳

const GUEST_BOOK := [
	"春日 誠",
	"春日 ひかり",
	"田中 良一",
	"佐々木 ふみ",
	"山本 清",
	"村田 とし",
	"――――――",
]

# ============================================================ 独白

const M_INCENSE_OUT := "線香が消えた。"
const M_INCENSE_NONE := "線香が無い。裏の在庫棚か。"
const M_WINDOW := "窓が開いている。閉めたはずだ。"
## docs/script.md に無い追加行(監督の指示)。式場の戸が独りでに開く脅かし用。
const ADDED_M_DOOR := "戸が開いている。閉めたはずだ。"
## docs/script.md に無い追加行(監督の指示)。
const ADDED_M_LID := "蓋が、ずれている。"
const ADDED_M_FIGURE := "祭壇の前に、誰か居た。"
const ADDED_M_CANDLE_OUT := "灯明が消えた。祭壇が真っ暗だ。"
const M_CHAIR := "椅子が一つ、引き出されている。"
const M_ZABUTON := "座布団が棺の前に並べてある。誰が。"
const M_IEI := "遺影が伏せてある。"
const M_FOOTSTEPS := "後ろに、もう一つ足音がする。"
const M_YUKAN := "白装束が揺れている。風はない。"
const M_CAT := "猫だ。追い出さないと。"
const M_FREEZER_EMPTY := "空だ。昨日は一杯だったのに。"
const M_FACE1 := "口が、少し開いている。"
const M_FACE2 := "目が開いている。"
const M_FACE3 := "こちらを向いている。"
const M_PAW := "濡れた足跡。廊下から式場へ。猫の足跡だ。"
const M_GUEST_BOOK := "最後の行に、自分の名前があった。書いた覚えはない。"
const M_CEILING := "天井裏を、何かが歩いている。"
const M_CLOCK := "時計が逆に回っている。"
const M_LIGHTS_OUT := "灯りが全部落ちた。"
const M_MATCHES := "マッチ。事務所にマッチがあった。"
const M_RELIGHT_OK := "ついた。"
const M_RELIGHT_FAIL := "消えた。まだ、いる。"

## 電話(22:30)
const M_PHONE_HELLO := "……もしもし。"
const M_PHONE_CUT := "切れた。"
## 電話(02:30)
const PHONE_WET_LINE := "……か……え……し……て……"
const M_PHONE_WET_AFTER := "線香が消えた音がした。"

## 選択肢
const CHOICE_HIKAESHITSU := "控室の戸を開けるか"
const CHOICE_HIKAESHITSU_OPTIONS := ["開けない", "開ける"]
## 控室の戸に置く「調べる」点の prompt
const CHOICE_HIKAESHITSU_SPOT := "控室の戸を調べる"

# ============================================================ タスク文言

const TASK_INCENSE := "線香を立てる"
const TASK_BACKDOOR := "勝手口を閉めて鍵をかける"
const TASK_LID := "棺の蓋を戻す"
## 玄関が施錠されているときの表示(00:00 まで)
const GENKAN_LOCKED := "鍵がかかっている。社長が持っている。"
const TASK_FLOWERS := "供花の水を替える"
const TASK_WINDOW := "式場の窓を閉める"
const TASK_CANDLE := "灯明を替える"
const TASK_CAT := "猫を追い出す"
const TASK_BREAKER := "ブレーカーを上げる"
const TASK_DRY_ICE := "ドライアイスを交換する"
const TASK_INCENSE_STOCK := "線香の在庫を取ってくる"
const TASK_RELIGHT := "マッチを取って灯明を灯す"
const TASK_LAST_INCENSE := "線香を最後に一本立てる"

# ============================================================ エンディング

const ENDING_MORNING_TITLE := "— 朝 —"
const ENDING_MORNING_LINES := [
	"五時。鴉が鳴いている。",
	"社長の車が駐車場に入ってきた。",
	"線香は、朝まで絶えなかった。",
	"出棺のとき、霊柩車の屋根に黒い猫が一匹、座っていた。",
	"猫は、最後まで見ていた。",
]

const ENDING_KASHA_TITLE := "— 火車 —"
const ENDING_KASHA_LINES := [
	"五時。鴉が鳴いている。",
	"棺の中は空だった。",
	"社長は何も言わなかった。書類の日付だけを書き換えた。",
	"火葬場で、息子は空の棺の前に立ち続けた。",
	"火車は、罪のある者の亡骸しか奪わないという。",
	"では、あれは誰を迎えに来たのか。",
]

const ENDING_SUBSTITUTE_TITLE := "— 代わり —"
const ENDING_SUBSTITUTE_LINES := [
	"控室の戸を開けた。",
	"悲鳴は、長くは続かなかった。",
	"五時。鴉が鳴いている。線香は絶えなかった。",
	"警察が来た。息子は見つからなかった。",
	"ひかりさんは、猫を一匹だけ連れて帰った。",
	"猫は、罪のある者を知っている。",
]

const ENDING_PORTRAIT_TITLE := "— 遺影 —"
const ENDING_PORTRAIT_LINES := [
	"目が覚めた。五時だった。",
	"線香は絶えていた。",
	"棺の蓋は開いていた。中は空だった。",
	"祭壇の遺影を見た。",
	"それは、私の顔だった。",
]


# ============================================================ v0.3 追加(推奨セット)
# docs/script.md「v0.3 追加(推奨セット)」が正本。一字も変えない。

## 導入の追加(21)
const ADDED_BOSS_CATS := ["キヨさんは村じゃ猫婆で通ってた。二十匹も飼ってな。"]
const ADDED_HIKARI_FATHER := ["……父は、おばあちゃんが死んだ日のこと、何も言わないんです。"]
## 施錠の場所を教える 1 行(docs/script.md にあるものをそのまま)
const BOSS_LOCK := ["閉めるだけじゃ駄目だ。扉の横の金具で鍵をかけろ。猫は器用だからな。"]

## E-1 金庫
const SAFE_CODE := "1009"
const MEMO_DESK_TITLE := "社長の机のメモ"
const MEMO_DESK_BODY := "金庫の番号は婆さんの命日。忘れるな。"
const IEI_BACK_TITLE := "遺影の裏"
const IEI_BACK_BODY := """春日 キヨ
令和七年十月九日 没
行年八十八"""
const M_SAFE_WRONG := "違う。"
const M_SAFE_WRONG3 := "……急かされている。"

## E-2 分電盤
const M_BREAKER_WRONG := "跳ねた。順番がある。"

## E-3 電話(発信)
const PHONE_BOSS := "0246"
const PHONE_HIKARI := "3175"
const PHONE_KIYO := "4419"
const PHONE_VOICEMAIL_LINE := "ただいま電話に出ることができません。"
const M_PHONE_BOSS_AFTER := "……誰かが、聞いている。"
const PHONE_HIKARI_1 := [
	"……はい。",
	"……父は、まだそこに居ますか。",
	"父は、猫を……いえ。何でもないです。",
	"線香、切らさないでください。",
]
const PHONE_HIKARI_LATE := ["……父は、まだそこに?"]
const PHONE_KIYO_VOICE := "……かえして……"
const M_PHONE_KIYO_AFTER := "誰も住んでいない家だ。"
const PHONE_UNAVAILABLE_LINE := "おかけになった電話番号は、現在使われておりません。"

## E-4 押入れ・障子
const PAGE5_TITLE := "前任者の走り書き"
const PAGE5_BODY := """猫は誠を見ている。
俺は見なかったことにする。
三時の電話には出るな。"""
const M_SHOJI_CATS := "全部、こっちを見ている。"

## E-5 血の手形
const M_BLOOD_FIRST := "手形だ。……小さい。"
const M_BLOOD_SAFE := "金庫の前で途切れている。"

## E-6 ラジオ
const M_RADIO_1 := "ラジオ。つけた覚えはない。"
const M_RADIO_2 := "また、ついている。"

## E-7 冷凍庫の袋
const PAGE6_TITLE := "収容票"
const PAGE6_BODY := """動物愛護センター 収容票
種別 猫　頭数 十九
依頼者 春日 誠
受付 十月九日"""

## 収集物を読んだ後の独白(22)。索引は収集番号。
const PAGE_AFTER := {
	1: "猫は、誰が悪いか知っている。",
	2: "前の人も、猫を見ている。",
	3: "首に痣。事故じゃない。",
	4: "金で通した。警察は来ない。",
	5: "三時の電話。",
	6: "十月九日。おばあちゃんが死んだ日だ。",
}

## 息子の寝言(23、順に)
const SON_SLEEP_TALK := [
	"……違う……俺じゃ……猫が……",
	"……婆さん……そんな目で……見るな……",
	"……燃やせば……終わる……",
]

## 「かえして」の後(24)
const M_CATS_RETURN := "猫を、返せと言っている。"

## 真相の回想(25)。[画像, 文, 必要な収集番号]
const RECAP := [
	["recap_truck", "十月九日。十九匹の猫が、軽トラで運ばれた。", 6],
	["recap_cats", "その週、キヨは首を絞められて死んだ。", 3],
	["recap_ledger", "息子は金を払い、社長は日付を書き換えた。", 4],
]
const RECAP_UNREAD := "……"

## 追加タスク
const TASK_BREAKER_ORDER := "分電盤のレバーを順に上げる"
const TASK_RADIO := "ラジオを消す"
