extends Node
## One transform for terrain, troops, atmosphere and logical battlefield input.
signal changed(state: Dictionary)
const MIN_ZOOM: float=1.0
const MAX_ZOOM: float=1.6
const ZOOM_STEP: float=.1
var field_clip: Control
var content: Control
var zoom: float=1.0
var pan: Vector2=Vector2.ZERO
var enabled: bool=false
var input_enabled: bool=true
var dragging: bool=false
var previous_pointer: Vector2=Vector2.ZERO
var stage_id: String=""

func configure(clip: Control, shared_content: Control, stage: Dictionary) -> void:
	var changed_stage: bool=str(stage.get("id",""))!=stage_id
	field_clip=clip
	content=shared_content
	stage_id=str(stage.get("id",""))
	var authored: Dictionary=stage.get("camera",{})
	enabled=bool(authored.get("allowZoom",stage.get("cameraEnabled",false)))
	if changed_stage or not enabled: zoom=MIN_ZOOM;pan=Vector2.ZERO;dragging=false
	if is_instance_valid(content): content.pivot_offset=Vector2.ZERO
	_apply()
	set_process_input(enabled and input_enabled)
	changed.emit(diagnostics())

func set_input_enabled(value: bool) -> void:
	input_enabled=value
	if not value: dragging=false
	set_process_input(enabled and input_enabled)

func screen_to_content(point: Vector2) -> Vector2:
	return content.get_global_transform_with_canvas().affine_inverse()*point if is_instance_valid(content) else point

func content_to_screen(point: Vector2) -> Vector2:
	return content.get_global_transform_with_canvas()*point if is_instance_valid(content) else point

func screen_to_clip(point: Vector2) -> Vector2:
	return field_clip.get_global_transform_with_canvas().affine_inverse()*point if is_instance_valid(field_clip) else point

func clip_to_screen(point: Vector2) -> Vector2:
	return field_clip.get_global_transform_with_canvas()*point if is_instance_valid(field_clip) else point

func contains_screen_point(point: Vector2) -> bool:
	return is_instance_valid(field_clip) and Rect2(Vector2.ZERO,field_clip.size).has_point(screen_to_clip(point))

func reset() -> void:
	zoom=MIN_ZOOM
	pan=Vector2.ZERO
	dragging=false
	_apply()
	changed.emit(diagnostics())

func zoom_at(screen_point: Vector2, requested_zoom: float) -> bool:
	if not enabled or not is_instance_valid(content) or not contains_screen_point(screen_point) or not is_finite(requested_zoom): return false
	var next_zoom: float=clampf(requested_zoom,MIN_ZOOM,MAX_ZOOM)
	if is_equal_approx(next_zoom,zoom): return false
	var before: Vector2=screen_to_content(screen_point)
	zoom=next_zoom
	pan=screen_to_clip(screen_point)-before*zoom
	_apply()
	changed.emit(diagnostics())
	return true

func set_zoom(requested_zoom: float) -> bool:
	return zoom_at(clip_to_screen(field_clip.size*.5),requested_zoom) if is_instance_valid(field_clip) else false

func pan_by_clip_delta(delta: Vector2) -> bool:
	if not enabled or not delta.is_finite(): return false
	var before: Vector2=pan
	pan+=delta
	_apply()
	if pan==before: return false
	changed.emit(diagnostics())
	return true

func _apply() -> void:
	if not is_instance_valid(field_clip) or not is_instance_valid(content): return
	zoom=clampf(zoom,MIN_ZOOM,MAX_ZOOM) if enabled else MIN_ZOOM
	var lower: Vector2=-field_clip.size*(zoom-1.0)
	pan=pan.clamp(lower,Vector2.ZERO) if enabled else Vector2.ZERO
	content.scale=Vector2.ONE*zoom
	content.position=pan
	content.size=field_clip.size

func _input(event: InputEvent) -> void:
	if not enabled or not input_enabled or not is_instance_valid(field_clip) or not field_clip.is_visible_in_tree(): dragging=false;return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:
			if event.pressed and contains_screen_point(event.position): dragging=true;previous_pointer=screen_to_clip(event.position);get_viewport().set_input_as_handled()
			elif not event.pressed and dragging: dragging=false;get_viewport().set_input_as_handled()
		elif event.pressed and contains_screen_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position,zoom+(ZOOM_STEP if event.button_index==MOUSE_BUTTON_WHEEL_UP else -ZOOM_STEP))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		var current: Vector2=screen_to_clip(event.position)
		pan_by_clip_delta(current-previous_pointer)
		previous_pointer=current
		get_viewport().set_input_as_handled()

func diagnostics() -> Dictionary:
	return {"enabled":enabled,"inputEnabled":input_enabled,"stageId":stage_id,"zoom":zoom,"minZoom":MIN_ZOOM,"maxZoom":MAX_ZOOM,"pan":{"x":pan.x,"y":pan.y},"dragging":dragging,"canZoomIn":enabled and zoom<MAX_ZOOM-.0001,"canZoomOut":enabled and zoom>MIN_ZOOM+.0001,"sharedTransform":true}
