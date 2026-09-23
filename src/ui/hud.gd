extends CanvasLayer
## HUD。SubViewport 640x360 の中に描かれるので、文字は 16px 前後・要素は小さく控えめに。
## _ready で Dialogue.register_ui(self) を呼ぶので、Dialogue.say/choose/note がそのままここに出る。
##
## Dialogue から使う(すべて await 可):
##   show_line(speaker: String, text: String)
##   show_choice(prompt: String, options: Array) -> int
##   show_note(title: String, body: String)
## Player から使う:
##   show_prompt(text: String, available := true) / hide_prompt() / set_hold_progress(r: float)
##   blocks_player() -> bool / wants_cursor() -> bool
## 演出:
##   fade_out(dur) / fade_in(dur) / flash(color, dur) / blackout(dur) / darken(amount, dur)
##   toggle_clipboard() / set_rec(bool)

signal title_requested
signal quit_requested

## 画面に出る日本語。director が差し替えられるように export / const にまとめてある。
## 既定は docs/script.md「掟(クリップボード)」と同じ。director から set_rules() で差し替え可。
@export var rules: PackedStringArray = [
	"一、線香を絶やさぬこと",
	"一、灯明を絶やさぬこと",
	"一、猫を入れぬこと",
	"一、棺の小窓を開けぬこと",
	"一、眠らぬこと",
]
@export var clipboard_title: String = "寝ずの番 心得"
@export var clipboard_footer: String = "やすらぎ会館"
@export var clipboard_tasks_header: String = "今夜のこと"
@export var note_close_hint: String = "閉じる"
@export var pause_items: PackedStringArray = ["再開", "タイトルへ", "終了"]
@export var typewriter_cps: float = 34.0

const W := 640.0
const H := 360.0
const MARGIN := 12.0

var _root: Control
var _darken: ColorRect
var _game: Control
var _rec_dot: Control
var _rec_label: Label
var _time_label: Label
var _task_label: Label
var _task_mark: Label
var _crosshair: Control
var _ring: Control
var _prompt: Label
var _cam_label: Label
var _toast: Label
var _toast_tween: Tween = null
var _cam_row: HBoxContainer
var _task_row: HBoxContainer

var _dlg: Control
var _dlg_panel: PanelContainer
var _dlg_speaker: Label
var _dlg_body: Label
var _dlg_next: Label
var _mono: Label

var _choice: Control
var _choice_panel: PanelContainer
var _choice_prompt: Label
var _choice_rows: VBoxContainer

var _note: Control
var _note_title: Label
var _note_body: Label
var _note_scroll: ScrollContainer
var _note_hint: Label

var _clip: Control
var _clip_tasks: VBoxContainer
var _clip_rules: VBoxContainer = null

var _pause: Control
var _pause_rows: VBoxContainer

var _flash: ColorRect
var _fade: ColorRect

var _hold: float = 0.0
var _focused: bool = false
var _rec_t: float = 0.0

var _dlg_active: bool = false
var _dlg_chars: float = 0.0
var _dlg_total: int = 0
var _adv_latch: bool = true

var _choice_open: bool = false
var _choice_index: int = 0
var _choice_result: int = -1
var _choice_count: int = 0

var _note_open: bool = false
var _clip_open: bool = false
var _paused: bool = false
var _pause_index: int = 0

var _nav_latch: int = 0        # -1 上 / 1 下 / 0 なし
var _clip_latch: bool = true
var _pause_latch: bool = true

var _all_tasks: Array = []
var _interact_key: String = "E"
var _latch: Dictionary = {}

func _ready() -> void:
	add_to_group(&"hud")
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interact_key = _key_for(&"interact")
	_build()
	Dialogue.register_ui(self)
	Tasks.changed.connect(_on_tasks_changed)
	_on_tasks_changed(Tasks.current(), [])

func _key_for(action: StringName) -> String:
	return UiTheme.key_name(action, "E")

# ================================================================ 組み立て

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	UiTheme.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_darken = ColorRect.new()
	_darken.name = "Darken"
	UiTheme.full_rect(_darken)
	_darken.color = Color(0, 0, 0, 0)
	_darken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_darken)

	_build_game_layer()
	_build_dialogue()
	_build_choice()
	_build_note()
	_build_clipboard()
	_build_pause()

	_flash = ColorRect.new()
	_flash.name = "Flash"
	UiTheme.full_rect(_flash)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	UiTheme.full_rect(_fade)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)

func _build_game_layer() -> void:
	_game = Control.new()
	_game.name = "Game"
	UiTheme.full_rect(_game)
	_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_game)

	# --- 右上: ● REC   PM 11:32
	var rec := HBoxContainer.new()
	rec.name = "Rec"
	rec.anchor_left = 1.0
	rec.anchor_right = 1.0
	rec.offset_left = -MARGIN
	rec.offset_right = -MARGIN
	rec.offset_top = MARGIN - 4.0
	rec.offset_bottom = MARGIN - 4.0
	rec.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rec.grow_vertical = Control.GROW_DIRECTION_END
	rec.add_theme_constant_override("separation", 5)
	rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(rec)

	_rec_dot = Control.new()
	_rec_dot.name = "RecDot"
	_rec_dot.custom_minimum_size = Vector2(9, 18)
	_rec_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_dot.draw.connect(func() -> void:
		_rec_dot.draw_circle(Vector2(4.5, 10.0), 3.5, Color(0, 0, 0, 0.7))
		_rec_dot.draw_circle(Vector2(4.0, 9.0), 3.0, UiTheme.REC))
	rec.add_child(_rec_dot)

	_rec_label = UiTheme.gothic_label("REC", 14, UiTheme.TEXT)
	rec.add_child(_rec_label)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec.add_child(gap)

	_time_label = UiTheme.gothic_label("PM 9:00", 16, UiTheme.TEXT)
	rec.add_child(_time_label)

	# --- 左上: いまやること
	var task := HBoxContainer.new()
	task.name = "Task"
	task.offset_left = MARGIN
	task.offset_right = MARGIN
	task.offset_top = MARGIN - 3.0
	task.offset_bottom = MARGIN - 3.0
	task.grow_horizontal = Control.GROW_DIRECTION_END
	task.grow_vertical = Control.GROW_DIRECTION_END
	task.add_theme_constant_override("separation", 5)
	task.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(task)
	_task_row = task

	_task_mark = UiTheme.gothic_label("□", 14, UiTheme.TEXT_WARN)
	task.add_child(_task_mark)
	_task_label = UiTheme.gothic_label("", 16, UiTheme.TEXT)
	task.add_child(_task_label)

	# --- 左下: カムコーダー表記
	var cam := HBoxContainer.new()
	cam.name = "Camcorder"
	cam.anchor_top = 1.0
	cam.anchor_bottom = 1.0
	cam.offset_left = MARGIN
	cam.offset_right = MARGIN
	cam.offset_top = -MARGIN - 18.0
	cam.offset_bottom = -MARGIN - 18.0
	cam.grow_horizontal = Control.GROW_DIRECTION_END
	cam.grow_vertical = Control.GROW_DIRECTION_END
	cam.add_theme_constant_override("separation", 6)
	cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game.add_child(cam)
	_cam_row = cam

	var tri := Control.new()
	tri.custom_minimum_size = Vector2(9, 16)
	tri.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tri.draw.connect(func() -> void:
		var pts := PackedVector2Array([Vector2(1, 4), Vector2(8, 8), Vector2(1, 12)])
		tri.draw_colored_polygon(pts, UiTheme.TEXT))
	cam.add_child(tri)
	_cam_label = UiTheme.gothic_label("PLAY    SP", 13, UiTheme.TEXT_DIM)
	cam.add_child(_cam_label)

	# --- 中央: クロスヘアと長押しリング
	_ring = Control.new()
	_ring.name = "HoldRing"
	UiTheme.full_rect(_ring)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_game.add_child(_ring)

	_crosshair = Control.new()
	_crosshair.name = "Crosshair"
	UiTheme.full_rect(_crosshair)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	_game.add_child(_crosshair)

	# 独白の字幕と同じ位置・同じ見た目(画面下・中央寄せ)
	_toast = UiTheme.gothic_label("", 16, UiTheme.TEXT)
	_toast.name = "Toast"
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 60.0
	_toast.offset_right = -60.0
	_toast.offset_top = -64.0
	_toast.offset_bottom = -28.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	_game.add_child(_toast)

	_prompt = UiTheme.gothic_label("", 16, UiTheme.TEXT)
	_prompt.name = "Prompt"
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = H * 0.5 + 20.0
	_prompt.offset_bottom = H * 0.5 + 42.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_game.add_child(_prompt)

func _draw_crosshair() -> void:
	var c := Vector2(W, H) * 0.5
	if _focused:
		_crosshair.draw_circle(c, 3.0, Color(0, 0, 0, 0.55))
		_crosshair.draw_circle(c, 2.5, UiTheme.TEXT, false, 1.0)
	else:
		_crosshair.draw_rect(Rect2(c + Vector2(-1.5, -1.5), Vector2(3, 3)), Color(0, 0, 0, 0.6))
		_crosshair.draw_rect(Rect2(c + Vector2(-1, -1), Vector2(2, 2)), UiTheme.TEXT)

func _draw_ring() -> void:
	if _hold <= 0.001:
		return
	var c := Vector2(W, H) * 0.5
	_ring.draw_arc(c, 12.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 3.0, false)
	_ring.draw_arc(c, 12.0, -PI * 0.5, -PI * 0.5 + TAU * _hold, 40, UiTheme.SELECT, 2.0, false)

func _build_dialogue() -> void:
	_dlg = Control.new()
	_dlg.name = "Dialogue"
	UiTheme.full_rect(_dlg)
	_dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg.visible = false
	_root.add_child(_dlg)

	_dlg_panel = PanelContainer.new()
	_dlg_panel.name = "Box"
	_dlg_panel.anchor_top = 1.0
	_dlg_panel.anchor_bottom = 1.0
	_dlg_panel.offset_left = 44.0
	_dlg_panel.offset_right = -44.0
	_dlg_panel.anchor_right = 1.0
	_dlg_panel.offset_top = -100.0
	_dlg_panel.offset_bottom = -18.0
	_dlg_panel.add_theme_stylebox_override("panel", UiTheme.box_style())
	_dlg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg.add_child(_dlg_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg_panel.add_child(v)

	_dlg_speaker = UiTheme.gothic_label("", 15, UiTheme.SPEAKER)
	v.add_child(_dlg_speaker)

	_dlg_body = UiTheme.gothic_label("", 16, UiTheme.TEXT)
	_dlg_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dlg_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_dlg_body.label_settings.line_spacing = 4
	v.add_child(_dlg_body)

	_dlg_next = UiTheme.gothic_label("▼", 12, UiTheme.TEXT_DIM)
	_dlg_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_dlg_next)

	# 話者なし(独白)は箱を出さず中央寄せの字幕
	_mono = UiTheme.gothic_label("", 16, UiTheme.TEXT)
	_mono.name = "Monologue"
	_mono.anchor_right = 1.0
	_mono.anchor_top = 1.0
	_mono.anchor_bottom = 1.0
	_mono.offset_left = 70.0
	_mono.offset_right = -70.0
	_mono.offset_top = -78.0
	_mono.offset_bottom = -24.0
	_mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mono.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mono.label_settings.line_spacing = 4
	_mono.visible = false
	_dlg.add_child(_mono)

func _build_choice() -> void:
	_choice = Control.new()
	_choice.name = "Choice"
	UiTheme.full_rect(_choice)
	_choice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice.visible = false
	_root.add_child(_choice)

	_choice_panel = PanelContainer.new()
	_choice_panel.anchor_left = 0.5
	_choice_panel.anchor_right = 0.5
	_choice_panel.anchor_top = 1.0
	_choice_panel.anchor_bottom = 1.0
	_choice_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choice_panel.offset_top = -110.0
	_choice_panel.offset_bottom = -110.0
	_choice_panel.custom_minimum_size = Vector2(300, 0)
	_choice_panel.add_theme_stylebox_override("panel", UiTheme.box_style(Color(0.012, 0.014, 0.018, 0.88)))
	_choice.add_child(_choice_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_choice_panel.add_child(v)

	_choice_prompt = UiTheme.gothic_label("", 15, UiTheme.TEXT_DIM)
	_choice_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_choice_prompt)

	_choice_rows = VBoxContainer.new()
	_choice_rows.add_theme_constant_override("separation", 2)
	v.add_child(_choice_rows)

func _build_note() -> void:
	_note = Control.new()
	_note.name = "Note"
	UiTheme.full_rect(_note)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.visible = false
	_root.add_child(_note)

	var dim := ColorRect.new()
	UiTheme.full_rect(dim)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.add_child(dim)

	var paper := PanelContainer.new()
	paper.name = "Paper"
	paper.anchor_left = 0.5
	paper.anchor_right = 0.5
	paper.anchor_top = 0.5
	paper.anchor_bottom = 0.5
	paper.grow_horizontal = Control.GROW_DIRECTION_BOTH
	paper.grow_vertical = Control.GROW_DIRECTION_BOTH
	paper.custom_minimum_size = Vector2(304, 312)
	paper.add_theme_stylebox_override("panel", UiTheme.paper_style())
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.add_child(paper)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(v)

	_note_title = UiTheme.mincho_label("", 19, UiTheme.INK, false)
	_note_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note_title)

	var rule := ColorRect.new()
	rule.color = Color(0.45, 0.42, 0.36, 0.6)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)

	_note_scroll = ScrollContainer.new()
	_note_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_note_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(_note_scroll)

	_note_body = UiTheme.mincho_label("", 16, UiTheme.INK, false)
	_note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note_body.label_settings.line_spacing = 7
	_note_scroll.add_child(_note_body)

	# スクロールバーは紙に馴染む細い色に(既定の明るいバーは紙らしさを壊す)
	var vs := _note_scroll.get_v_scroll_bar()
	if vs:
		vs.custom_minimum_size = Vector2(4, 0)
		var sb_bg := StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.20, 0.17, 0.13, 0.25)
		var sb_gr := StyleBoxFlat.new()
		sb_gr.bg_color = Color(0.26, 0.22, 0.16, 0.85)
		vs.add_theme_stylebox_override("scroll", sb_bg)
		vs.add_theme_stylebox_override("grabber", sb_gr)
		vs.add_theme_stylebox_override("grabber_highlight", sb_gr)
		vs.add_theme_stylebox_override("grabber_pressed", sb_gr)

	_note_hint = UiTheme.gothic_label("", 12, UiTheme.INK_DIM, false)
	_note_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_note_hint)

func _build_clipboard() -> void:
	_clip = Control.new()
	_clip.name = "Clipboard"
	UiTheme.full_rect(_clip)
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.visible = false
	_root.add_child(_clip)

	var dim := ColorRect.new()
	UiTheme.full_rect(dim)
	dim.color = Color(0, 0, 0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(dim)

	var paper := PanelContainer.new()
	paper.anchor_left = 0.5
	paper.anchor_right = 0.5
	paper.anchor_top = 0.5
	paper.anchor_bottom = 0.5
	paper.grow_horizontal = Control.GROW_DIRECTION_BOTH
	paper.grow_vertical = Control.GROW_DIRECTION_BOTH
	paper.custom_minimum_size = Vector2(296, 306)
	paper.add_theme_stylebox_override("panel", UiTheme.paper_style())
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(paper)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(v)

	var t := UiTheme.mincho_label(clipboard_title, 17, UiTheme.INK, false)
	v.add_child(t)
	var rule := ColorRect.new()
	rule.color = Color(0.45, 0.42, 0.36, 0.7)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)

	var sp1 := Control.new()
	sp1.custom_minimum_size = Vector2(0, 3)
	v.add_child(sp1)

	_clip_rules = VBoxContainer.new()
	_clip_rules.add_theme_constant_override("separation", 2)
	v.add_child(_clip_rules)
	for r in rules:
		_clip_rules.add_child(UiTheme.gothic_label(r, 16, UiTheme.INK, false))

	var footer := UiTheme.gothic_label(clipboard_footer, 14, UiTheme.INK_DIM, false)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(footer)

	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 8)
	v.add_child(sp2)
	var rule2 := ColorRect.new()
	rule2.color = Color(0.45, 0.42, 0.36, 0.5)
	rule2.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule2)
	var th := UiTheme.mincho_label(clipboard_tasks_header, 15, UiTheme.INK_DIM, false)
	v.add_child(th)

	_clip_tasks = VBoxContainer.new()
	_clip_tasks.add_theme_constant_override("separation", 2)
	_clip_tasks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_clip_tasks)

func _build_pause() -> void:
	_pause = Control.new()
	_pause.name = "Pause"
	UiTheme.full_rect(_pause)
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.visible = false
	_root.add_child(_pause)

	var dim := ColorRect.new()
	UiTheme.full_rect(dim)
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(dim)

	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_top = 0.5
	v.anchor_bottom = 0.5
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause.add_child(v)

	_pause_rows = VBoxContainer.new()
	_pause_rows.add_theme_constant_override("separation", 4)
	v.add_child(_pause_rows)

# ================================================================ 毎フレーム

func _process(delta: float) -> void:
	_rec_t += delta
	_rec_dot.modulate.a = 1.0 if fmod(_rec_t, 1.0) < 0.55 else 0.0
	_time_label.text = Clock.time_string()

	var modal := _note_open or _clip_open or _paused or _choice_open
	var hide_reticle: bool = modal or Dialogue.busy or _dlg_active
	_crosshair.visible = not hide_reticle
	_ring.visible = not hide_reticle
	if hide_reticle:
		_prompt.visible = false
	_cam_row.visible = not hide_reticle
	_task_row.visible = not hide_reticle
	if hide_reticle:
		_toast.visible = false
	else:
		_toast.visible = true

	_handle_input()
	if not get_tree().paused:
		_advance_typewriter(delta)

func _just(action: StringName) -> bool:
	var p := Input.is_action_pressed(action)
	var was: bool = bool(_latch.get(action, true))
	_latch[action] = p
	return p and not was

func _handle_input() -> void:
	var adv := _just(&"advance")
	var pause_just := _just(&"pause")
	var clip_just := _just(&"clipboard")
	var u1 := _just(&"ui_up")
	var u2 := _just(&"move_forward")
	var d1 := _just(&"ui_down")
	var d2 := _just(&"move_back")
	var up: bool = u1 or u2
	var down: bool = d1 or d2

	if _paused:
		var n := _pause_rows.get_child_count()
		if n > 0:
			if up:
				_pause_index = (_pause_index - 1 + n) % n
				_update_pause_rows()
				Audio.play(&"ui_select", -8.0)
			if down:
				_pause_index = (_pause_index + 1) % n
				_update_pause_rows()
				Audio.play(&"ui_select", -8.0)
			if adv:
				_activate_pause(_pause_index)
				return
		if pause_just:
			_close_pause()
		return

	if _note_open:
		if up:
			_note_scroll.scroll_vertical -= 28
		if down:
			_note_scroll.scroll_vertical += 28
		if adv or pause_just:
			_note_open = false
			Audio.play(&"page_turn", -8.0)
		return

	if _choice_open:
		var c := maxi(_choice_count, 1)
		if up:
			_choice_index = (_choice_index - 1 + c) % c
			_update_choice_rows()
			Audio.play(&"ui_select", -8.0)
		if down:
			_choice_index = (_choice_index + 1) % c
			_update_choice_rows()
			Audio.play(&"ui_select", -8.0)
		if adv:
			_choice_result = _choice_index
		return

	if _clip_open:
		if clip_just or pause_just or adv:
			_clip_open = false
			_clip.visible = false
			Audio.play(&"paper_rustle", -10.0)
		return

	if _dlg_active:
		if adv:
			if _dlg_chars < float(_dlg_total):
				_dlg_chars = float(_dlg_total)
				_set_visible_chars(_dlg_total)
			else:
				_dlg_active = false
		return

	if clip_just:
		toggle_clipboard()
	elif pause_just:
		_open_pause()

func _advance_typewriter(delta: float) -> void:
	if not _dlg_active:
		return
	if _dlg_chars < float(_dlg_total):
		_dlg_chars = minf(float(_dlg_total), _dlg_chars + typewriter_cps * delta)
		_set_visible_chars(int(_dlg_chars))
	_dlg_next.visible = _dlg_chars >= float(_dlg_total) and fmod(_rec_t, 0.9) < 0.55

func _set_visible_chars(n: int) -> void:
	_dlg_body.visible_characters = n
	_mono.visible_characters = n

# ================================================================ Dialogue の受け口

func is_dialogue_open() -> bool:
	return _dlg_active

func show_line(speaker: String, text: String) -> void:
	await get_tree().process_frame
	_close_clipboard()
	var mono := speaker.strip_edges().is_empty()
	_dlg.visible = true
	_dlg_panel.visible = not mono
	_mono.visible = mono
	if mono:
		_mono.text = text
	else:
		_dlg_speaker.text = speaker
		_dlg_body.text = text
	_dlg_total = text.length()
	_dlg_chars = 0.0
	_set_visible_chars(0)
	_dlg_next.visible = false
	_latch[&"advance"] = true
	_dlg_active = true
	while _dlg_active and is_inside_tree():
		await get_tree().process_frame
	_dlg.visible = false
	_dlg_panel.visible = false
	_mono.visible = false

func show_choice(prompt: String, options: Array) -> int:
	await get_tree().process_frame
	_close_clipboard()
	_choice_count = options.size()
	if _choice_count == 0:
		return 0
	_choice_prompt.text = prompt
	_choice_prompt.visible = not prompt.strip_edges().is_empty()
	_build_choice_rows(options)
	_choice_index = 0
	_choice_result = -1
	_update_choice_rows()
	_choice.visible = true
	_choice_open = true
	_latch[&"advance"] = true
	while _choice_result < 0 and is_inside_tree():
		await get_tree().process_frame
	_choice_open = false
	_choice.visible = false
	Audio.play(&"ui_confirm", -6.0)
	return maxi(_choice_result, 0)

func _build_choice_rows(options: Array) -> void:
	for c in _choice_rows.get_children():
		c.queue_free()
	for i in options.size():
		var idx := i
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		row.add_theme_stylebox_override("panel", sb)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var l := UiTheme.gothic_label(String(options[i]), 16, UiTheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(l)
		row.mouse_entered.connect(func() -> void:
			if _choice_open and _choice_index != idx:
				_choice_index = idx
				_update_choice_rows())
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_choice_index = idx
				_choice_result = idx)
		_choice_rows.add_child(row)

func _update_choice_rows() -> void:
	for i in _choice_rows.get_child_count():
		var row := _choice_rows.get_child(i) as PanelContainer
		var l := row.get_child(0) as Label
		var on := i == _choice_index
		var sb := row.get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.bg_color = Color(0.85, 0.88, 0.92, 0.14) if on else Color(0, 0, 0, 0)
		l.label_settings.font_color = UiTheme.SELECT if on else UiTheme.TEXT_DIM
		l.text = ("＞ " if on else "　 ") + String(l.text).lstrip("＞　 ")

func show_note(title: String, body: String) -> void:
	await get_tree().process_frame
	_close_clipboard()
	_note_title.text = title
	_note_body.text = body
	_note_body.visible_characters = -1
	_note_hint.text = "[%s] %s" % [_key_for(&"advance"), note_close_hint]
	_note_scroll.scroll_vertical = 0
	_note.visible = true
	_note_open = true
	_latch[&"advance"] = true
	_latch[&"pause"] = true
	Audio.play(&"paper_rustle", -10.0)
	while _note_open and is_inside_tree():
		await get_tree().process_frame
	_note.visible = false

# ================================================================ プロンプト / 長押し

func show_prompt(text: String, available: bool = true) -> void:
	if Dialogue.busy or _note_open or _clip_open or _paused or _choice_open:
		_prompt.visible = false
		_focused = false
		_crosshair.queue_redraw()
		return
	_prompt.text = "[%s] %s" % [_interact_key, text]
	_prompt.label_settings.font_color = UiTheme.TEXT if available else UiTheme.TEXT_DIM
	_prompt.visible = true
	if not _focused:
		_focused = true
		_crosshair.queue_redraw()

## 画面下に短く出る一言。「今は何もできない。」「両手が塞がっている」など、
## 会話にするほどでもないもの。表示中に呼ばれたら上書きする(連打で重ならない)。
func show_toast(text: String, duration: float = 1.5) -> void:
	if text.is_empty():
		return
	_toast.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(maxf(duration, 0.1))
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.45)

func get_toast_text() -> String:
	return _toast.text

func is_toast_visible() -> bool:
	return _toast.visible and _toast.modulate.a > 0.5

func hide_prompt() -> void:
	_prompt.visible = false
	if _focused:
		_focused = false
		_crosshair.queue_redraw()

func set_hold_progress(r: float) -> void:
	var v := clampf(r, 0.0, 1.0)
	if is_equal_approx(v, _hold):
		return
	_hold = v
	_ring.queue_redraw()

# ================================================================ タスク / クリップボード

func _on_tasks_changed(current: Dictionary, all: Array) -> void:
	_all_tasks = all.duplicate()
	var text := String(current.get("text", "")) if not current.is_empty() else ""
	_task_label.text = text
	_task_mark.visible = not text.is_empty()
	_task_label.visible = not text.is_empty()
	if not text.is_empty():
		_flash_task()
	if _clip_open:
		_refresh_clip_tasks()

func _flash_task() -> void:
	var tw := create_tween()
	tw.tween_property(_task_label, "modulate:a", 0.15, 0.10)
	tw.tween_property(_task_label, "modulate:a", 1.0, 0.14)
	tw.tween_property(_task_label, "modulate:a", 0.25, 0.10)
	tw.tween_property(_task_label, "modulate:a", 1.0, 0.18)

func toggle_clipboard() -> void:
	if Dialogue.busy or _dlg_active or _note_open or _paused or _choice_open:
		return
	_clip_open = not _clip_open
	if _clip_open:
		_refresh_clip_tasks()
		_latch[&"clipboard"] = true
		Audio.play(&"paper_rustle", -10.0)
	_clip.visible = _clip_open

## 字幕・選択肢・手紙を出すときは必ずクリップボードを畳む(重なって読めなくなるため)
func _close_clipboard() -> void:
	if not _clip_open:
		return
	_clip_open = false
	_clip.visible = false

func _refresh_clip_tasks() -> void:
	for c in _clip_tasks.get_children():
		c.queue_free()
	if _all_tasks.is_empty():
		_clip_tasks.add_child(UiTheme.gothic_label("　―", 15, UiTheme.INK_DIM, false))
		return
	for t in _all_tasks:
		var done := bool(t.get("done", false))
		var mark := "■" if done else "□"
		var l := UiTheme.gothic_label("%s %s" % [mark, String(t.get("text", ""))], 15, UiTheme.INK_DIM if done else UiTheme.INK, false)
		_clip_tasks.add_child(l)

func set_rules(list: PackedStringArray) -> void:
	rules = list
	if _clip_rules == null:
		return
	for c in _clip_rules.get_children():
		c.queue_free()
	for r in rules:
		_clip_rules.add_child(UiTheme.gothic_label(r, 16, UiTheme.INK, false))

# ================================================================ ポーズ

func _build_pause_rows() -> void:
	for c in _pause_rows.get_children():
		c.queue_free()
	for i in pause_items.size():
		var l := UiTheme.gothic_label(String(pause_items[i]), 19, UiTheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size = Vector2(132, 0)
		_pause_rows.add_child(l)

func _update_pause_rows() -> void:
	for i in _pause_rows.get_child_count():
		var l := _pause_rows.get_child(i) as Label
		var on := i == _pause_index
		l.label_settings.font_color = UiTheme.SELECT if on else UiTheme.TEXT_DIM
		l.text = ("＞ " if on else "　 ") + String(l.text).lstrip("＞　 ")

func _open_pause() -> void:
	if Dialogue.busy or _note_open or _choice_open:
		return
	_clip_open = false
	_clip.visible = false
	_paused = true
	_pause_index = 0
	_build_pause_rows()
	_update_pause_rows()
	_pause.visible = true
	_latch[&"pause"] = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _close_pause() -> void:
	_paused = false
	_pause.visible = false
	get_tree().paused = false
	_latch[&"pause"] = true

func _activate_pause(index: int) -> void:
	Audio.play(&"ui_confirm", -6.0)
	match index:
		0:
			_close_pause()
		1:
			_close_pause()
			title_requested.emit()
			Clock.stop()
			Clock.skip_to(0)
			Tasks.clear()
			Audio.stop_all_ambient(0.2)
			get_tree().call_deferred("reload_current_scene")
		2:
			quit_requested.emit()
			get_tree().quit()

func is_paused() -> bool:
	return _paused

# ================================================================ フェード / 画面演出

func fade_out(dur: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, maxf(dur, 0.01))
	await tw.finished

func fade_in(dur: float = 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, maxf(dur, 0.01))
	await tw.finished

func set_fade(a: float) -> void:
	_fade.color.a = clampf(a, 0.0, 1.0)

func flash(color: Color = Color.WHITE, dur: float = 0.1) -> void:
	_flash.color = Color(color.r, color.g, color.b, 1.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, maxf(dur, 0.01))

## 一瞬だけ真っ暗にする(脅かし用)。await 可。
func blackout(dur: float = 0.6) -> void:
	_fade.color.a = 1.0
	await get_tree().create_timer(maxf(dur, 0.01), false).timeout
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.25)
	await tw.finished

## 世界だけ暗くする(UI は読める)。
func darken(amount: float, dur: float = 0.5) -> void:
	var a := clampf(amount, 0.0, 1.0)
	if dur <= 0.0:
		_darken.color.a = a
		return
	var tw := create_tween()
	tw.tween_property(_darken, "color:a", a, dur)

func set_rec(on: bool) -> void:
	_rec_dot.visible = on
	_rec_label.visible = on

func set_camcorder_text(text: String) -> void:
	_cam_label.text = text

# ================================================================ 状態問い合わせ(Player が使う)

## 移動・視点・インタラクトを止めるべきか。
## 字幕(_dlg_active)も含める: advance と interact がどちらも E なので、
## 字幕を送るつもりの E が目の前の Interactable を押してしまうため(review H4)。
## Dialogue.busy に頼らないのは、say と note が重なると先に終わった側が busy を落とすから。
func blocks_player() -> bool:
	return _dlg_active or _note_open or _clip_open or _paused or _choice_open

## マウスカーソルを出すべきか。字幕は含めない(会話のたびにカーソルが湧くのを避ける)。
func wants_cursor() -> bool:
	return _note_open or _clip_open or _paused or _choice_open
