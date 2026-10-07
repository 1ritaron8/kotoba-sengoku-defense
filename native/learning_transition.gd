extends Control
## A real-time presentation clock shared by the two learning card screens.
## The battle stays visible underneath until the new screen becomes opaque.

signal phase_changed(value: String)
signal presented
signal return_finished

const UIStyle = preload("res://native/sengoku_ui.gd")
const PREVIEW_TIME: float = .22
const CARD_START: float = .30
const CARD_STAGGER: float = .065
const CARD_TIME: float = .27
const RETURN_TIME: float = .36

var font: Font
var phase: String = "idle"
var shade: ColorRect
var banner: Panel
var heading: Label
var caption: Label
var animation: Tween
var last_ui_tick_usec: int = 0
var surface: Control
var cards: Array = []
var footer: Control
var visuals: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade = ColorRect.new()
	shade.color = Color(.06,.04,.015,0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	banner = Panel.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel",UIStyle.frame(UIStyle.SURFACE,UIStyle.BRASS,true))
	add_child(banner)
	UIStyle.texture_layer(banner,"lacquer",.8)
	heading = _label(29,Color(UIStyle.BRASS))
	caption = _label(20,Color(UIStyle.TEXT))
	resized.connect(_arrange)
	_arrange()
	hide()

func _label(point_size: int, ink: Color) -> Label:
	var node = Label.new()
	node.add_theme_font_override("font",font)
	node.add_theme_font_size_override("font_size",point_size)
	node.add_theme_color_override("font_color",ink)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(node)
	return node

func _arrange() -> void:
	if banner == null:
		return
	var width: float = minf(580,size.x-64)
	banner.position = Vector2((size.x-width)*.5,size.y*.36)
	banner.size = Vector2(width,112)
	heading.position = Vector2(16,15)
	heading.size = Vector2(width-32,42)
	caption.position = Vector2(16,66)
	caption.size = Vector2(width-32,30)

func accepts_answers() -> bool:
	return phase == "choice"

func accepts_actions() -> bool:
	return phase in ["choice","result"]

func is_busy() -> bool:
	return phase in ["preview","entering","revealing","exiting"]

func covers_battle() -> bool:
	return phase in ["choice","revealing","result"]

func _set_phase(value: String) -> void:
	phase = value
	phase_changed.emit(phase)

func _new_tween() -> Tween:
	animation = create_tween()
	animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	animation.set_ignore_time_scale(true)
	# A wave-end callback can construct this UI partway through a long frame.
	# Start its own clock here rather than consuming the frame's earlier delta.
	animation.pause()
	last_ui_tick_usec = Time.get_ticks_usec()
	return animation

func _stop_tween() -> void:
	if animation != null and animation.is_valid():
		animation.kill()
	animation = null

func _remember(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	for value in visuals:
		if value.node == control:
			return
	visuals.append({"node":control,"color":control.modulate,"scale":control.scale,"pivot":control.pivot_offset})

func _restore_visuals() -> void:
	for value in visuals:
		if is_instance_valid(value.node):
			value.node.modulate = value.color
			value.node.scale = value.scale
			value.node.pivot_offset = value.pivot
	visuals.clear()

func _saved_alpha(control: Control) -> float:
	for value in visuals:
		if value.node == control:
			return float(value.color.a)
	return 1.0

func cancel() -> void:
	_stop_tween()
	_restore_visuals()
	surface = null
	cards.clear()
	footer = null
	if shade != null:
		shade.color.a = 0
		banner.modulate.a = 1
		banner.hide()
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_phase("idle")

func present(screen: Control, choices: Array, actions: Control, title: String, already_resolved: bool = false) -> void:
	cancel()
	surface = screen
	cards = choices.duplicate()
	footer = actions
	_remember(surface)
	_remember(footer)
	for card in cards:
		_remember(card)
		card.pivot_offset = card.size*.5
		card.modulate.a = 0
		card.scale = Vector2(.94,.94)
	surface.modulate.a = 0
	surface.show()
	footer.modulate.a = 0
	heading.text = title
	caption.text = "전투 잠시 멈춤 · 카드를 선택하십시오" if not already_resolved else "전투 잠시 멈춤 · 임무 결과 확인"
	shade.color.a = 0
	banner.modulate.a = 0
	banner.show()
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_phase("preview")
	var tween = _new_tween().set_parallel(true)
	tween.tween_property(shade,"color:a",.62,PREVIEW_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner,"modulate:a",1.0,.12)
	tween.tween_callback(_set_phase.bind("entering")).set_delay(PREVIEW_TIME)
	tween.tween_property(surface,"modulate:a",1.0,.24).set_delay(PREVIEW_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(shade,"color:a",0.0,.24).set_delay(PREVIEW_TIME)
	tween.tween_property(banner,"modulate:a",0.0,.14).set_delay(PREVIEW_TIME)
	for index in range(cards.size()):
		var card: Control = cards[index]
		var delay: float = CARD_START+CARD_STAGGER*index
		tween.tween_property(card,"modulate:a",_saved_alpha(card),.23).set_delay(delay)
		tween.tween_property(card,"scale",Vector2.ONE,CARD_TIME).from(Vector2(.94,.94)).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(footer,"modulate:a",1.0,.20).set_delay(.50)
	tween.chain().tween_callback(_finish_present.bind(already_resolved))

func _finish_present(already_resolved: bool) -> void:
	banner.hide()
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_phase("result" if already_resolved else "choice")
	presented.emit()

func reveal_result(focus_card: Control, feedback: Control) -> void:
	_stop_tween()
	# Result styles and translations are applied by the owning screen first.
	# Keep those colors when a later navigation interrupts this emphasis.
	for value in visuals:
		if is_instance_valid(value.node):
			value.color = value.node.modulate
	_remember(feedback)
	feedback.modulate.a = .25
	_set_phase("revealing")
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tween = _new_tween().set_parallel(true)
	tween.tween_property(feedback,"modulate:a",1.0,.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if focus_card != null:
		focus_card.pivot_offset = focus_card.size*.5
		tween.tween_property(focus_card,"scale",Vector2(1.035,1.035),.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(focus_card,"scale",Vector2.ONE,.17).set_delay(.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tween.tween_interval(.30)
	tween.chain().tween_callback(_finish_result)

func _finish_result() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_phase("result")

func begin_return() -> void:
	if phase == "exiting" or surface == null:
		return
	_stop_tween()
	banner.hide()
	shade.color.a = 0
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_set_phase("exiting")
	var tween = _new_tween().set_parallel(true)
	tween.tween_property(surface,"modulate:a",0.0,RETURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for card in cards:
		if is_instance_valid(card):
			tween.tween_property(card,"scale",Vector2(.97,.97),.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(footer,"modulate:a",0.0,.18)
	tween.chain().tween_callback(_finish_return)

func _finish_return() -> void:
	cancel()
	return_finished.emit()

func _process(_delta: float) -> void:
	# Containers and window resize may change card dimensions during a tween.
	# A center pivot remains valid without storing stale layout positions.
	if phase != "idle":
		for card in cards:
			if is_instance_valid(card):
				card.pivot_offset = card.size*.5
	if animation != null and animation.is_valid() and is_visible_in_tree():
		var now: int = Time.get_ticks_usec()
		var real_delta: float = maxf(0.0,(now-last_ui_tick_usec)/1000000.0)
		last_ui_tick_usec = now
		animation.custom_step(real_delta)
