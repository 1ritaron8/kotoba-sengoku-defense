extends RefCounted

# Presentation only. The caller supplies live game data and owns every command.
const Style = preload("res://native/sengoku_ui.gd")
const BUTTON_STATES: Array[String] = ["normal","hover","pressed","hover_pressed","disabled","focus"]
static var _field_surfaces: Array[WeakRef] = []
static var _overlay_surfaces: Array[WeakRef] = []

# Keep presentation bounds tied to the actual controls, including later changes
# to their visibility, annotated-text height, queue size and canvas transform.
static func register_surface(surface: Control, field_boundary: bool = false) -> void:
	var surfaces: Array[WeakRef] = _field_surfaces if field_boundary else _overlay_surfaces
	for reference in surfaces:
		if reference.get_ref()==surface: return
	surfaces.append(weakref(surface))

static func _surface_rect(surface: Control, target: CanvasItem) -> Rect2:
	var transform: Transform2D = target.get_global_transform_with_canvas().affine_inverse()*surface.get_global_transform_with_canvas()
	var rect: Rect2 = Rect2(transform*Vector2.ZERO,Vector2.ZERO)
	for corner in [Vector2(surface.size.x,0),surface.size,Vector2(0,surface.size.y)]:
		rect = rect.expand(transform*corner)
	return rect

static func visible_field_rect(target: CanvasItem, fallback: Rect2) -> Rect2:
	var retained: Array[WeakRef] = []
	var result: Rect2 = fallback
	for reference in _field_surfaces:
		var surface: Control = reference.get_ref() as Control
		if not is_instance_valid(surface): continue
		retained.append(reference)
		if surface.is_visible_in_tree() and surface.get_viewport()==target.get_viewport():
			result = _surface_rect(surface,target)
	_field_surfaces = retained
	return result

static func visible_occupied_rects(target: CanvasItem, field: Rect2) -> Array[Rect2]:
	var retained: Array[WeakRef] = []
	var result: Array[Rect2] = []
	for reference in _overlay_surfaces:
		var surface: Control = reference.get_ref() as Control
		if not is_instance_valid(surface): continue
		retained.append(reference)
		if not surface.is_visible_in_tree() or surface.get_viewport()!=target.get_viewport(): continue
		var rect: Rect2 = _surface_rect(surface,target).intersection(field)
		if rect.has_area(): result.append(rect)
	_overlay_surfaces = retained
	return result

static func layout(viewport: Vector2) -> Dictionary:
	var compact: bool = viewport.x < 1360.0
	var dock_height: float = 128.0 if compact else 144.0
	var dock: Rect2 = Rect2(12,viewport.y-dock_height-8,viewport.x-24,dock_height)
	var field: Rect2 = Rect2(12,112,viewport.x-24,maxf(1,dock.position.y-118))
	# Leave a control column for learning, route choice and interaction guidance.
	var controls_width: float = 196.0 if compact else 212.0
	var card_area_width: float = dock.size.x-controls_width-24.0
	return {
		"compact":compact,
		"hud":Rect2(0,0,viewport.x,108),
		"field":field,
		"roster":dock,
		"inspectorWidth":312.0 if compact else 330.0,
		"rosterCardWidth":floorf((card_area_width-42.0)/8.0),
		"rosterCardHeight":100.0 if compact else 112.0,
		"controlsWidth":controls_width,
		"queue":Rect2(field.position.x,field.end.y-108,field.size.x,104)
	}

static func apply_panel(panel: Panel, role: String = "dock") -> void:
	if role=="field": register_surface(panel,true)
	elif role in ["selection","queue","hint"]: register_surface(panel)
	var box: StyleBoxFlat = Style.frame(Style.SURFACE,Style.LINE)
	box.shadow_size = 0
	match role:
		"hud":
			box.bg_color = Color(Style.INK)
			box.set_border_width_all(0)
			box.border_width_bottom = 1
			box.border_color = Color(Style.BRASS)
			box.set_corner_radius_all(0)
		"field":
			box.bg_color = Color.TRANSPARENT
			box.border_color = Color("4a4d44")
			box.set_corner_radius_all(0)
		"selection":
			box.border_color = Color(Style.BLUE)
			box.border_width_left = 2
		"queue":
			box.bg_color = Color("202728f5")
			box.border_width_top = 2
		"hint":
			box.bg_color = Color("141819d9")
			box.set_border_width_all(0)
		"portrait":
			box.bg_color = Color("121719")
			box.border_color = Color("414b4e")
	panel.add_theme_stylebox_override("panel",box)
	if role in ["hud","dock","selection","queue"] and panel.get_node_or_null("HUDMaterialSurface")==null:
		var texture: Control=Style.texture_layer(panel,"lacquer",.42,1.0)
		texture.name="HUDMaterialSurface"

static func apply_label(label: Label, role: String = "body") -> void:
	var colour: Color = Color(Style.TEXT)
	var font_size: int = 20
	match role:
		"title": font_size = 26
		"value": colour = Color(Style.BRASS)
		"muted": colour = Color(Style.MUTED)
		"warning": colour = Color(Style.WARNING)
		"error": colour = Color(Style.DANGER)
	label.add_theme_color_override("font_color",colour)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_constant_override("outline_size",0)

static func apply_button(button: BaseButton, is_selected: bool = false) -> void:
	for state in BUTTON_STATES:
		var source_state: String = "pressed" if state=="hover_pressed" else state
		var box: StyleBoxFlat = Style.selected() if is_selected and source_state=="normal" else Style.button(source_state)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		button.add_theme_stylebox_override(state,box)
	button.add_theme_color_override("font_color",Color(Style.TEXT))
	button.add_theme_color_override("font_hover_color",Color("fff6df"))
	button.add_theme_color_override("font_pressed_color",Color(Style.BLUE))
	button.add_theme_color_override("font_focus_color",Color(Style.TEXT))
	button.add_theme_color_override("font_disabled_color",Color(Style.DISABLED))
	button.add_theme_font_size_override("font_size",20)

static func apply_roster_card(card: Button, is_selected: bool = false, locked: bool = false) -> void:
	apply_button(card,is_selected)
	for state in BUTTON_STATES:
		var box: StyleBoxFlat = card.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		box.set_border_width_all(1)
		box.content_margin_left = 4
		box.content_margin_right = 4
		box.border_color = Color(Style.BLUE if is_selected and not locked else "424b4c" if locked else Style.LINE)
		if state=="focus":
			box.border_color = Color(Style.BLUE)
			box.set_border_width_all(2)
		elif is_selected and not locked:
			box.border_width_bottom = 3
		card.add_theme_stylebox_override(state,box)
	card.set_meta("hud_selected",is_selected)
	card.set_meta("hud_locked",locked)

static func apply_queue_card(card: Button, waiting_capacity: bool = false) -> void:
	# A completed order waiting for actor space is an accepted order, not an error.
	apply_button(card)
	for state in BUTTON_STATES:
		var box: StyleBoxFlat = card.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		box.content_margin_left = 47
		box.content_margin_bottom = 14
		box.border_width_bottom = 2
		box.border_color = Color(Style.WARNING if waiting_capacity else Style.LINE)
		if state=="focus": box.border_color = Color(Style.BLUE)
		card.add_theme_stylebox_override(state,box)
	card.add_theme_color_override("font_color",Color(Style.WARNING if waiting_capacity else Style.TEXT))
	card.set_meta("hud_waiting_capacity",waiting_capacity)

static func apply_progress(bar: ProgressBar, role: String = "production") -> void:
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("111719")
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(Style.BRASS if role=="production" else Style.WARNING if role=="waiting_capacity" else "75bd80")
	bar.add_theme_stylebox_override("background",background)
	bar.add_theme_stylebox_override("fill",fill)
	bar.show_percentage = false

static func queue_text(job: Dictionary) -> String:
	var timing: String = "정원 대기" if str(job.get("status",""))=="waiting_capacity" else "%.1f초" % float(job.get("remainingSeconds",0))
	return "%s ×%d\n%s" % [str(job.get("name",job.get("type",""))),int(job.get("quantity",1)),timing]

static func queue_tooltip(job: Dictionary) -> String:
	var status: String = "소집 완료 · 이 주문의 병력이 함께 출진할 정원을 기다립니다." if str(job.get("status",""))=="waiting_capacity" else "각 주문을 동시에 준비합니다."
	return "%s\n클릭: 이 주문 취소 · 보급 %d 전액 환불" % [status,int(job.get("cost",0))]
