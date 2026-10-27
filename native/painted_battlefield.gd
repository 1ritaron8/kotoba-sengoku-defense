extends RefCounted
## A static map texture in the same normalized rectangle used by live actors.
## This renderer owns no input, camera, navigation, simulation or HUD state.

const FOREGROUND_PATH: String="res://assets/painted-battlefield/stage01-foreground.png"
const DEFAULT_TEXTURE_PATH: String = "res://assets/painted-battlefield/stage01.png"
const SCENERY_SHIFT_SHADER = preload("res://native/painted_scenery_shift.gdshader")
static var scenery_material_cache: Dictionary={}
var texture: Texture2D
var active: bool = false
var texture_path: String = ""
var last_draw_rect: Rect2 = Rect2()
var draw_count: int = 0
var load_error: String = ""
var foreground_texture: Texture2D
var presentation_layer: Node2D
var background_layer: Node2D
var background_material: ShaderMaterial
var south_deck_shift: Vector2=Vector2.ZERO
var occlusion_patch_count: int=0
var foreground_material: ShaderMaterial
var _record_frame: int=-1
var _record_cache: Array=[]
var _candidate_serial: int=-1
var _front_candidate_cache: Dictionary={}
var _occlusion_cache: Array=[]
var _occlusion_shift: Vector2=Vector2(INF,INF)
var foreground_path: String=FOREGROUND_PATH
var art_size: Vector2=Vector2(1831,859)
var authored_occlusion: Array=[]
var uses_authored_occlusion: bool=false
var presentation_signature: String=""
var _occlusion_cache_signature: String=""

func configure(stage: Dictionary) -> bool:
	_record_frame=-1; _candidate_serial=-1
	active = false
	load_error = ""
	var composition: Dictionary=stage.get("paintedComposition",{})
	var dimensions: Dictionary=composition.get("artSize",{})
	art_size=Vector2(maxf(1.0,float(dimensions.get("width",1831))),maxf(1.0,float(dimensions.get("height",859))))
	uses_authored_occlusion=composition.has("occlusionPatches")
	authored_occlusion=composition.get("occlusionPatches",[]).duplicate(true)
	var requested_foreground: String=str(stage.get("paintedForeground",FOREGROUND_PATH if str(stage.get("id",""))=="basic-forest" else ""))
	if requested_foreground!=foreground_path:
		foreground_path=requested_foreground
		foreground_texture=_load_texture(foreground_path) if not foreground_path.is_empty() else null
	var move: Dictionary=composition.get("southDeckArtMove",{})
	south_deck_shift=Vector2(float(move.get("pixelOffset",{}).get("x",0)),float(move.get("pixelOffset",{}).get("y",0)))/Vector2(1831,859)
	presentation_signature=JSON.stringify([stage.get("id",""),stage.get("paintedBackground",""),foreground_path,composition])
	_occlusion_cache_signature=""
	_front_candidate_cache.clear()
	background_material=scenery_material_for(stage)
	if is_instance_valid(background_layer): background_layer.material=background_material
	if not bool(stage.get("paintedPresentation",false)):
		texture = null
		texture_path = ""
		return false
	var requested_path: String = str(stage.get("paintedBackground",DEFAULT_TEXTURE_PATH))
	if requested_path != texture_path:
		texture = null
	texture_path = requested_path
	if texture == null:
		if ResourceLoader.exists(texture_path,"Texture2D"):
			texture = load(texture_path) as Texture2D
		elif FileAccess.file_exists(texture_path):
			# A freshly generated PNG may precede its first editor import.
			var source: Image = Image.load_from_file(texture_path)
			if source != null and not source.is_empty():
				texture = ImageTexture.create_from_image(source)
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		load_error = "Painted map texture is missing or unreadable: " + texture_path
		return false
	if foreground_material!=null: foreground_material.set_shader_parameter("original_map",texture)
	active = true
	return true

static func scenery_material_for(stage: Dictionary) -> ShaderMaterial:
	var move: Dictionary=stage.get("paintedComposition",{}).get("southDeckArtMove",{})
	if move.is_empty(): return null
	var raw: Array=move.get("sourceRect",[])
	if raw.size()!=4: return null
	if float(raw[2])<=0.0 or float(raw[3])<=0.0: return null
	var mask_path: String=str(move.get("objectMaskTexture",""))
	var restoration_path: String=str(move.get("restorationTexture",""))
	if mask_path.is_empty() or restoration_path.is_empty(): return null
	var key: String=JSON.stringify(move)
	if scenery_material_cache.has(key): return scenery_material_cache[key]
	var object_mask: Texture2D=_load_texture(mask_path)
	var restoration_texture: Texture2D=_load_texture(restoration_path)
	if object_mask==null or restoration_texture==null: return null
	var dimensions: Vector2=Vector2(1831,859)
	var offset: Dictionary=move.get("pixelOffset",{})
	var shift: Vector2=Vector2(float(offset.get("x",0)),float(offset.get("y",0)))/dimensions
	if shift==Vector2.ZERO: return null
	var material: ShaderMaterial=ShaderMaterial.new()
	material.shader=SCENERY_SHIFT_SHADER
	material.set_shader_parameter("source_region",Vector4(float(raw[0])/dimensions.x,float(raw[1])/dimensions.y,float(raw[2])/dimensions.x,float(raw[3])/dimensions.y))
	material.set_shader_parameter("object_mask",object_mask)
	material.set_shader_parameter("restoration_map",restoration_texture)
	material.set_shader_parameter("source_shift",shift)
	scenery_material_cache[key]=material
	return material

func is_ready() -> bool:
	return active and texture != null

static func valid_rect(field_rect: Rect2) -> bool:
	return field_rect.position.is_finite() and field_rect.size.is_finite() and field_rect.size.x > 0.0 and field_rect.size.y > 0.0

static func texture_rect(field_rect: Rect2, mirrored: bool = false) -> Rect2:
	if mirrored:
		return Rect2(Vector2(field_rect.end.x,field_rect.position.y),Vector2(-field_rect.size.x,field_rect.size.y))
	return field_rect

func draw_to(canvas: Node2D, field_rect: Rect2, mirrored: bool = false) -> bool:
	if not is_ready() or not is_instance_valid(canvas) or not valid_rect(field_rect):
		return false
	# The whole art uses the whole field. Cropping, cover-fit, dark washes and
	# perspective transforms would disconnect painted decks from live positions.
	last_draw_rect = texture_rect(field_rect,mirrored)
	# An unmounted caller must also get the composed map, rather than raw art
	# behind already shifted slots. Keep the scenery material off live actors.
	if not is_instance_valid(background_layer): attach_to(canvas)
	draw_count += 1
	return true

func diagnostics() -> Dictionary:
	return {
		"ready":is_ready(), "texturePath":texture_path,
		"textureSize":texture.get_size() if texture != null else Vector2.ZERO,
		"coordinateSpace":"canonical_normalized_map", "crop":"none",
		"colorTreatment":"authored_texture_unchanged", "drawCount":draw_count,
		"lastDrawRect":last_draw_rect, "error":load_error,
		"foregroundPath":foreground_path,"foregroundPatches":occlusion_patch_count,"artSize":art_size,
		"southDeckGroundRepair":"source-registered object alpha; native underlay inside old island; original RGB translated; no rectangular grass move",
		"occlusion":"clipped foreground and front actor redraw; no extra simulation actors",
	}

# These controls own presentation pixels only. The Game keeps every actor,
# production job, slot reservation, navigation path and mission condition.
class BackgroundLayer extends Node2D:
	var presenter: RefCounted
	var battle: Node2D
	var drawn_rect: Rect2
	var drawn_texture: Texture2D
	var drawn_mirrored: bool=false
	func _process(_delta: float) -> void:
		visible=presenter.is_ready() and is_instance_valid(battle) and not battle.three_d_enabled
		if not visible: return
		if drawn_rect!=battle.field_rect or drawn_texture!=presenter.texture or drawn_mirrored!=battle.presentation_mirrored:
			drawn_rect=battle.field_rect
			drawn_texture=presenter.texture
			drawn_mirrored=battle.presentation_mirrored
			queue_redraw()
	func _draw() -> void:
		if not presenter.is_ready() or not presenter.valid_rect(battle.field_rect): return
		draw_texture_rect(presenter.texture,presenter.texture_rect(battle.field_rect,battle.presentation_mirrored),false,Color.WHITE)

class ForegroundPatch extends Node2D:
	var presenter: RefCounted
	var battle: Node2D
	var data: Dictionary={}
	var patch_rect: Rect2
	var drawn_texture: Texture2D
	var drawn_mirrored: bool=false
	func _draw() -> void:
		presenter._draw_occlusion_patch(self,battle,data,patch_rect)

class PresentationLayer extends Node2D:
	var presenter: RefCounted
	var battle: Node2D
	var patches: Array=[]
	var signature: String=""
	func _process(_delta: float) -> void:
		visible=presenter.is_ready() and is_instance_valid(battle) and not battle.three_d_enabled
		if not visible: return
		var next_signature: String=presenter.presentation_signature
		if signature!=next_signature:
			signature=next_signature
			for patch in patches:
				remove_child(patch)
				patch.queue_free()
			patches.clear()
			for item in presenter._occlusion_data():
				var clip: Control=Control.new()
				clip.name="ForegroundClip_"+str(item.id)
				clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
				clip.clip_contents=true
				var drawing: ForegroundPatch=ForegroundPatch.new()
				drawing.presenter=presenter
				drawing.battle=battle
				drawing.data=item
				add_child(clip)
				clip.add_child(drawing)
				var front: FrontActorPass=FrontActorPass.new()
				front.presenter=presenter
				front.battle=battle
				drawing.add_child(front)
				patches.append(clip)
			presenter.occlusion_patch_count=patches.size()
		for clip in patches:
			var drawing: ForegroundPatch=clip.get_child(0)
			var rect: Rect2=presenter._map_rect(drawing.data.bounds,battle.field_rect,battle.presentation_mirrored)
			clip.position=rect.position
			clip.size=rect.size
			var scenery_changed: bool=drawing.patch_rect!=rect or drawing.drawn_texture!=presenter.texture or drawing.drawn_mirrored!=battle.presentation_mirrored
			drawing.patch_rect=rect
			if scenery_changed:
				drawing.drawn_texture=presenter.texture
				drawing.drawn_mirrored=battle.presentation_mirrored
				drawing.queue_redraw()
			var front: FrontActorPass=drawing.get_child(0)
			front.data=drawing.data
			front.patch_rect=rect
			# Keep the clip at the scenery bounds, but cancel its translation
			# for actors so shared pose/contact caches always use Battle space.
			front.position=-rect.position
			front.queue_redraw()

static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path,"Texture2D"): return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var source: Image=Image.load_from_file(path)
		if source!=null and not source.is_empty(): return ImageTexture.create_from_image(source)
	return null

func attach_to(battle: Node2D) -> void:
	if not is_instance_valid(background_layer):
		var backdrop: BackgroundLayer=BackgroundLayer.new()
		backdrop.name="PaintedStaticBackground"
		backdrop.presenter=self
		backdrop.battle=battle
		backdrop.z_index=-1
		backdrop.material=background_material
		battle.add_child(backdrop)
		background_layer=backdrop
		if is_ready(): backdrop.queue_redraw()
	if is_instance_valid(presentation_layer): return
	foreground_texture=_load_texture(foreground_path) if not foreground_path.is_empty() else null
	var layer: PresentationLayer=PresentationLayer.new()
	layer.name="PaintedSceneryPresentation"
	layer.presenter=self
	layer.battle=battle
	layer.z_index=1
	battle.add_child(layer)
	presentation_layer=layer

static func _flipped_rect(rect: Rect2, mirrored: bool) -> Rect2:
	return Rect2(Vector2(rect.end.x,rect.position.y),Vector2(-rect.size.x,rect.size.y)) if mirrored else rect

static func _map_rect(canonical: Rect2, field: Rect2, mirrored: bool) -> Rect2:
	var left: float=1.0-canonical.end.x if mirrored else canonical.position.x
	return Rect2(field.position+Vector2(left,canonical.position.y)*field.size,canonical.size*field.size)

func _occlusion_data() -> Array:
	if _occlusion_cache_signature==presentation_signature: return _occlusion_cache
	if uses_authored_occlusion:
		var authored: Array=[]
		for entry in authored_occlusion:
			var raw: Array=entry.get("sourceRect",[])
			if raw.size()!=4: continue
			var source: Rect2=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
			if not source.has_area(): continue
			authored.append({"id":str(entry.get("id","scenery")),"bounds":Rect2(source.position/art_size,source.size/art_size),"source":source,"baseline":float(entry.get("baseline",source.end.y))/art_size.y})
		authored.sort_custom(func(a,b): return float(a.baseline)<float(b.baseline))
		_occlusion_cache=authored
		_occlusion_cache_signature=presentation_signature
		return authored
	# Rectangles are source-art pixels, with a ground baseline at each trunk
	# or front railing. Sampling the original color preserves exact alignment.
	var definitions: Array=[
		["tree-north",Rect2(1110,0,195,170),164.0],
		["tree-west",Rect2(180,165,247,214),374.0],
		["tree-east",Rect2(1643,170,188,177),343.0],
		["tree-southwest",Rect2(0,374,185,190),561.0],
		["tree-southeast",Rect2(1520,509,286,229),734.0],
		["north-front-rail",Rect2(728,198,180,100),290.0],
		["south-front-rail",Rect2(1090,591,190,103),687.0],
		["fort-front-palisade",Rect2(0,640,459,219),850.0],
		["fort-gate-post",Rect2(255,509,63,136),637.0]
	]
	var result: Array=[]
	for entry in definitions:
		var pixel_rect: Rect2=entry[1]
		var offset: Vector2=south_deck_shift if str(entry[0])=="south-front-rail" else Vector2.ZERO
		result.append({"id":entry[0],"bounds":Rect2(pixel_rect.position/Vector2(1831,859)+offset,pixel_rect.size/Vector2(1831,859)),"source":pixel_rect,"baseline":float(entry[2])/859.0+offset.y})
	result.sort_custom(func(a,b): return float(a.baseline)<float(b.baseline))
	_occlusion_shift=south_deck_shift
	_occlusion_cache=result
	_occlusion_cache_signature=presentation_signature
	return result

func _front_records(battle: Node2D) -> Array:
	var frame: int=battle.painted_actors.display_frame_serial(battle)
	if frame==_record_frame: return _record_cache
	_record_frame=frame
	var result: Array=[]
	for unit in battle.units: result.append({"actor":unit,"friendly":true})
	for enemy in battle.enemies:
		if battle._enemy_visible(enemy): result.append({"actor":enemy,"friendly":false})
	for dead in battle.death_actors: result.append({"actor":dead,"friendly":bool(dead.get("friendly",false))})
	for support in battle.battle_support.actor_states(): result.append({"actor":support,"friendly":true})
	for objective_actor in battle.withdrawal_mission.actor_states(): result.append({"actor":objective_actor,"friendly":true})
	result.sort_custom(func(a,b):
		var ay: float=_actor_point(a.actor).y
		var by: float=_actor_point(b.actor).y
		return ay<by if ay!=by else int(a.actor.get("id",0))<int(b.actor.get("id",0))
	)
	_record_cache=result
	return result

func _front_candidates(battle: Node2D, data: Dictionary) -> Array:
	var serial: int=battle.painted_actors.display_frame_serial(battle)
	if _candidate_serial!=serial:
		_candidate_serial=serial
		_front_candidate_cache.clear()
		var definitions: Array=_occlusion_data()
		var rectangles: Array[Rect2]=[]
		for item in definitions:
			_front_candidate_cache[str(item.id)]=[]
			rectangles.append(_map_rect(item.bounds,battle.field_rect,battle.presentation_mirrored))
		var height: float=battle.painted_actors.body_height_screen*clampf(battle.field_rect.size.y/620.0,.65,1.5)
		for record in _front_records(battle):
			var actor: Dictionary=record.actor
			if float(actor.get("hp",1))<=0 and str(actor.get("animation",""))!="death": continue
			var point: Vector2=_actor_point(actor)
			var foot: Vector2=battle._screen(point)
			var friendly: bool=bool(record.friendly)
			var type_name: String=str(actor.get("type",actor.get("kind","spear")))
			var bounds: Rect2=battle.painted_actors.pose_bounds(type_name,friendly)
			var actor_rect: Rect2=Rect2(foot+bounds.position*height,bounds.size*height).grow(height*.6)
			var candidate: Dictionary={"actor":actor,"friendly":friendly,"foot":foot}
			for index in range(definitions.size()):
				var item: Dictionary=definitions[index]
				if point.y<float(item.baseline): break # Definitions retain baseline order.
				if actor_rect.intersects(rectangles[index]): _front_candidate_cache[str(item.id)].append(candidate)
	return _front_candidate_cache.get(str(data.get("id","")),[])

static func _actor_point(actor: Dictionary) -> Vector2:
	return actor.get("position",Vector2(float(actor.get("x",0)),float(actor.get("y",0))))

func _draw_occlusion_patch(canvas: Node2D, battle: Node2D, data: Dictionary, rect: Rect2) -> void:
	if not is_ready() or not rect.has_area(): return
	var source: Texture2D=foreground_texture
	if source==null: return
	if foreground_material==null:
		var shader: Shader=Shader.new()
		shader.code="shader_type canvas_item; uniform sampler2D original_map : source_color, filter_linear; void fragment(){ vec4 cut=texture(TEXTURE,UV); vec3 authored=texture(original_map,UV).rgb; COLOR=vec4(authored,cut.a); }"
		foreground_material=ShaderMaterial.new()
		foreground_material.shader=shader
		foreground_material.set_shader_parameter("original_map",texture)
	canvas.material=foreground_material
	canvas.draw_texture_rect_region(source,_flipped_rect(Rect2(Vector2.ZERO,rect.size),battle.presentation_mirrored),data.source,Color.WHITE,false,true)

class FrontActorPass extends Node2D:
	var presenter: RefCounted
	var battle: Node2D
	var data: Dictionary
	var patch_rect: Rect2
	func _draw() -> void:
		if data.is_empty() or not patch_rect.has_area(): return
		var height: float=battle.painted_actors.body_height_screen*clampf(battle.field_rect.size.y/620.0,.65,1.5)
		for record in presenter._front_candidates(battle,data):
			var actor: Dictionary=record.actor
			var foot: Vector2=record.foot
			var friendly: bool=bool(record.friendly)
			# Shared preparation keeps every pass at the same Battle-space pose.
			battle.painted_actors.draw_actor(self,actor,foot,friendly,height,battle.painted_actors.visual_direction(actor,friendly,battle),false)
