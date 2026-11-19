class_name Hud
extends CanvasLayer

const MARGIN: float = 16.0
const PIP_SIZE: Vector2 = Vector2(22.0, 12.0)
const PIP_GAP: int = 4
const BAR_SIZE: Vector2 = Vector2(320.0, 14.0)

const PIP_FILLED: Color = Color(0.35, 1.0, 0.45)
const PIP_EMPTY: Color = Color(0.16, 0.19, 0.24, 0.9)
const BOSS_BACK: Color = Color(0.22, 0.08, 0.1, 0.9)
const BOSS_FILL: Color = Color(0.95, 0.25, 0.3)
const DIM: Color = Color(0.0, 0.0, 0.0, 0.7)

var _pip_row: HBoxContainer
var _pips: Array[ColorRect] = []
var _pip_max: int = 0
var _wave_label: Label
var _boss_box: VBoxContainer
var _boss_fill: ColorRect
var _end_overlay: Control
var _end_title: Label


func _ready() -> void:
	# Keep the HUD (and its restart input) alive while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build()
	call_deferred(&"_bind_scene")


func _build() -> void:
	var root := _make_control()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# HP pips, top-left.
	_pip_row = HBoxContainer.new()
	_pip_row.name = "HealthPips"
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_row.add_theme_constant_override(&"separation", PIP_GAP)
	_pip_row.offset_left = MARGIN
	_pip_row.offset_top = MARGIN
	root.add_child(_pip_row)

	# Wave counter, top-centre.
	_wave_label = _make_label("WAVE 1 / ?", 28)
	_wave_label.name = "WaveLabel"
	_wave_label.anchor_right = 1.0
	_wave_label.offset_top = MARGIN
	_wave_label.offset_bottom = MARGIN + 34.0
	root.add_child(_wave_label)

	# Boss bar, hidden until the director announces a boss.
	_boss_box = VBoxContainer.new()
	_boss_box.name = "BossBox"
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_boss_box.add_theme_constant_override(&"separation", 4)
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -BAR_SIZE.x * 0.5
	_boss_box.offset_right = BAR_SIZE.x * 0.5
	_boss_box.offset_top = 56.0
	root.add_child(_boss_box)

	var boss_label := _make_label("BOSS", 18)
	boss_label.add_theme_color_override(&"font_color", BOSS_FILL)
	_boss_box.add_child(boss_label)

	var bar := Control.new()
	bar.name = "BossBar"
	bar.clip_contents = true
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = BAR_SIZE
	_boss_box.add_child(bar)

	var back := ColorRect.new()
	back.color = BOSS_BACK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(back)

	_boss_fill = ColorRect.new()
	_boss_fill.color = BOSS_FILL
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_fill.anchor_bottom = 1.0
	_boss_fill.offset_right = BAR_SIZE.x
	bar.add_child(_boss_fill)

	# End-of-run overlay, hidden until the run finishes.
	_end_overlay = _make_control()
	_end_overlay.name = "EndOverlay"
	_end_overlay.visible = false
	_end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_end_overlay)

	var dim := ColorRect.new()
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.name = "EndBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 16)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_overlay.add_child(box)

	_end_title = _make_label("GAME OVER", 72)
	box.add_child(_end_title)
	box.add_child(_make_label("Press R to restart", 22))


func _bind_scene() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player != null:
		player.health_changed.connect(_on_player_health_changed)
		_rebuild_pips(player.max_health, player.health)

	var director := get_tree().get_first_node_in_group(&"director")
	if director != null:
		if director.has_signal(&"wave_changed"):
			director.connect(&"wave_changed", _on_wave_changed)
		if director.has_signal(&"boss_spawned"):
			director.connect(&"boss_spawned", _on_boss_spawned)
		if director.has_signal(&"run_finished"):
			director.connect(&"run_finished", _on_run_finished)

		# The director starts wave 1 before this deferred bind runs, so its
		# first wave_changed is already gone: seed the label from its state.
		var wave_value: Variant = director.get(&"wave")
		var total_value: Variant = director.get(&"total_waves")
		if wave_value is int and total_value is int and wave_value > 0:
			_on_wave_changed(int(wave_value), int(total_value))


func _unhandled_input(event: InputEvent) -> void:
	if not _end_overlay.visible:
		return
	if event.is_action_pressed(&"restart"):
		# Mark the event handled before reloading: reload frees this HUD.
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		get_tree().paused = false
		get_tree().reload_current_scene()


func _on_player_health_changed(current: int, maximum: int) -> void:
	if maximum != _pip_max:
		_rebuild_pips(maximum, current)
		return
	_set_pip_fill(current)


func _on_wave_changed(wave: int, total: int) -> void:
	_wave_label.text = "WAVE %d / %d" % [wave, total]


func _on_boss_spawned(boss: Node) -> void:
	if not is_instance_valid(boss):
		return
	if boss.has_signal(&"health_changed"):
		boss.connect(&"health_changed", _on_boss_health_changed)
	_boss_box.visible = true

	var current: Variant = boss.get(&"health")
	var maximum: Variant = boss.get(&"max_health")
	if current is int and maximum is int:
		_on_boss_health_changed(int(current), int(maximum))


func _on_boss_health_changed(current: int, maximum: int) -> void:
	if maximum <= 0:
		return
	_boss_fill.offset_right = BAR_SIZE.x * clampf(float(current) / float(maximum), 0.0, 1.0)
	if current <= 0:
		_boss_box.visible = false


func _on_run_finished(victory: bool) -> void:
	_end_title.text = "VICTORY" if victory else "GAME OVER"
	_boss_box.visible = false
	_end_overlay.visible = true


func _rebuild_pips(maximum: int, current: int) -> void:
	_pip_max = maxi(maximum, 0)
	for pip in _pips:
		_pip_row.remove_child(pip)
		pip.queue_free()
	_pips.clear()

	for i in _pip_max:
		var pip := ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = PIP_EMPTY
		_pip_row.add_child(pip)
		_pips.append(pip)

	_set_pip_fill(current)


func _set_pip_fill(current: int) -> void:
	for i in _pips.size():
		_pips[i].color = PIP_FILLED if i < current else PIP_EMPTY


func _make_control() -> Control:
	var control := Control.new()
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", ThemeDB.fallback_font)
	label.add_theme_font_size_override(&"font_size", font_size)
	return label
