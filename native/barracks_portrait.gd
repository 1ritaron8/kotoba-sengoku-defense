extends Control
## Compatibility surface for the barracks; all pixels use the live 2D renderer.
const Portrait = preload("res://native/painted_portrait.gd")
const Actors = preload("res://native/painted_actor_renderer.gd")
static var _shared_renderer: RefCounted
var unit_id: String = "archer"
var evolution_stage: int = 0
var available: bool = true
var animate_poses: bool = false
var smooth_blending: bool = false
var elapsed: float = 0.0
var friendly: bool = true
var skill_preview_level: int = -1
var portrait: Control

static func _assets() -> RefCounted:
	if _shared_renderer==null: _shared_renderer=Actors.new()
	return _shared_renderer

static func source_for(id: String, evolution: int = 0) -> Dictionary:
	var source: Dictionary=_assets().portrait_source(id,true,"sw")
	if source.is_empty(): return {}
	return {"path":source.sourcePath,"manifestPath":_assets().manifest_path,"sourceKind":"painted-v1","region":source.region,"anchor":source.anchor,"bodyHeightPixels":source.bodyHeightPixels,"evolution":clampi(evolution,0,2),"visualEvolution":false}

static func resolve_source(id: String, evolution: int = 0) -> Dictionary:
	return source_for(id,evolution)

static func frame_texture(id: String, _evolution: int = 0) -> AtlasTexture:
	return _assets().portrait_texture(id,true,"sw") as AtlasTexture

static func first_frame_texture(id: String, evolution: int = 0) -> AtlasTexture:
	return frame_texture(id,evolution)

func configure(id: String, evolution: int = 0, unlocked: bool = true) -> void:
	unit_id=id
	evolution_stage=clampi(evolution,0,2)
	available=unlocked
	elapsed=0.0
	if is_node_ready(): _configure_portrait()

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	portrait=Portrait.new()
	portrait.name="CurrentPaintedUnit"
	add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_configure_portrait()
	visibility_changed.connect(_sync_activity)
	_sync_activity()

func _configure_portrait() -> void:
	portrait.configure(unit_id,evolution_stage,true)
	portrait.available=available
	portrait.set_faction(friendly)
	portrait.set_skill_preview_level(skill_preview_level)
	portrait.animate_poses=animate_poses
	portrait.direction="" if animate_poses or skill_preview_level>=1 else "sw"
	portrait.queue_redraw()

func set_demo_time(value: float) -> void:
	elapsed=maxf(0.0,value) if is_finite(value) else 0.0
	if portrait!=null: portrait.set_demo_time(elapsed)

func set_skill_preview_level(level: int) -> void:
	skill_preview_level=clampi(level,1,10) if level>=1 else -1
	if portrait!=null:
		portrait.set_skill_preview_level(skill_preview_level)
		portrait.direction="" if animate_poses or skill_preview_level>=1 else "sw"
		elapsed=portrait.elapsed

func _sync_activity() -> void:
	set_process(is_inside_tree() and is_visible_in_tree())

func _process(_delta: float) -> void:
	if portrait==null: return
	portrait.animate_poses=animate_poses
	portrait.direction="" if animate_poses or skill_preview_level>=1 else "sw"
	elapsed=portrait.elapsed

func diagnostics() -> Dictionary:
	var result: Dictionary=portrait.diagnostics() if portrait!=null else {"ready":false}
	result["sourceKind"]="painted-v1"
	result["sourcePath"]=str(source_for(unit_id,evolution_stage).get("path",""))
	result["active"]=is_visible_in_tree() and (animate_poses or skill_preview_level>=1)
	result["smoothBlending"]=false
	return result
