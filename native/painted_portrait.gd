extends Control
## Current painted battlefield assets only, shared with barracks and previews.
const Actors = preload("res://native/painted_actor_renderer.gd")
var renderer = Actors.new()
var unit_id: String = "archer"
var evolution: int = 0
var available: bool = true
var friendly: bool = true
var animate_poses: bool = false
var elapsed: float = 0.0
var direction: String = "sw"
var skill_preview_level: int = -1
var _layout: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout_art)
	visibility_changed.connect(_sync_activity)
	_layout_art()
	_sync_activity()

func configure(id: String, stage: int = 0, _standing: bool = true) -> void:
	unit_id=id
	evolution=clampi(stage,0,2)
	elapsed=0.0
	if is_node_ready(): _layout_art()
	queue_redraw()

func set_faction(value: bool) -> void:
	friendly=value
	_layout_art()

func set_demo_time(value: float) -> void:
	elapsed=maxf(0.0,value) if is_finite(value) else 0.0
	queue_redraw()

func set_skill_preview_level(level: int) -> void:
	var next_level: int=clampi(level,1,10) if level>=1 else -1
	if skill_preview_level==next_level: return
	skill_preview_level=next_level
	elapsed=0.0
	if is_node_ready(): _layout_art()
	_sync_activity()
	queue_redraw()

func _layout_art() -> void:
	_layout.clear()
	var bounds: Rect2=renderer.skill_preview_bounds(unit_id,friendly,skill_preview_level)
	if bounds.has_area() and size.x>1 and size.y>1:
		var height: float=minf(size.x*.90/bounds.size.x,size.y*.86/bounds.size.y)
		_layout={"height":height,"foot":size*.5-bounds.get_center()*height,"bounds":Rect2(size*.5-bounds.size*height*.5,bounds.size*height)}
	queue_redraw()

func _sync_activity() -> void:
	set_process(is_inside_tree() and is_visible_in_tree())

func _process(delta: float) -> void:
	if animate_poses or skill_preview_level>=1:
		elapsed+=maxf(0.0,delta)
		queue_redraw()

func _state() -> Dictionary:
	if animate_poses or skill_preview_level>=1: return renderer.preview_state(unit_id,elapsed,direction,friendly,skill_preview_level)
	return {"type":unit_id,"animation":"idle","animationClock":0.0,"preview":true,"viewDirection":{"ne":Vector2(2,-1),"se":Vector2(2,1),"sw":Vector2(-2,1),"nw":Vector2(-2,-1)}.get(direction,Vector2(-2,1))}

func _draw() -> void:
	if not renderer.is_ready() or _layout.is_empty(): return
	var state: Dictionary=_state()
	state["evolution"]=evolution
	state["presentationAlpha"]=1.0 if available else .55
	renderer.draw_actor(self,state,_layout.foot,friendly,float(_layout.height),state.viewDirection,false)

func diagnostics() -> Dictionary:
	var state: Dictionary=_state()
	return {"ready":renderer.is_ready() and not _layout.is_empty(),"unitId":unit_id,"visibleBounds":_layout.get("bounds",Rect2()),"cellSize":size,"source":"painted-v1","sourceKind":"painted-v1","manifestPath":renderer.manifest_path,"evolution":evolution,"friendly":friendly,"unlocked":available,"animation":state.animation,"animationClock":elapsed,"animatePoses":animate_poses,"skillPreviewLevel":skill_preview_level,"previewSkillId":str(state.get("previewSkillId","")),"sample":renderer.animation_sample(state,friendly,state.viewDirection),"world3D":false,"previewTimingOnly":true}
