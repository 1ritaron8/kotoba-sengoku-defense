extends RefCounted
## One canvas pass over real actors. This class only reads simulation data.

const DEFAULT_MANIFEST: String = "res://assets/characters/painted-v1/manifest.json"
const COMPILED_ASSET_SCHEMA: int = 4
const SkillMotion = preload("res://native/painted_skill_motion.gd")
const PREVIEW_SKILLS: Dictionary = {
	"archer":["archer_fire","archer_barrage","archer_double_shot"],
	"spear":["spear_pierce","spear_brace","spear_rear_rank"],
	"samurai":["samurai_parry","samurai_counter_combo","samurai_isshin"],
	"gunner":["gunner_pierce","gunner_armor_break","gunner_braced_shot"],
	"monk":["monk_talisman","monk_ward","monk_victory_prayer"],
	"commander":["commander_charge","commander_impact","commander_rally"],
	"ninja":["ninja_timed_charge","ninja_opening_combo","ninja_charge_shrapnel"]
}
const DIRECT_ROLES: Dictionary = {"spear":"spear","archer":"archer","gunner":"gunner","matchlock":"gunner","samurai":"samurai","monk":"monk","ninja":"ninja","commander":"commander","enemy_commander":"commander","enemy_archer":"archer","enemy_gunner":"gunner","enemy_samurai":"samurai","enemy_cavalry":"cavalry","raider":"spear","runner":"runner"}
static var texture_cache: Dictionary = {}
static var texture_stamps: Dictionary = {}
static var compiled_asset_cache: Dictionary = {}

class Pose extends RefCounted:
	var texture: Texture2D
	var texture_path: String = ""
	var region: Rect2
	var anchor: Vector2
	var offset: Vector2 = Vector2.ZERO
	var body_height: float = 1.0
	var tint: Color = Color.WHITE
	var cutout: AtlasTexture
	var landmarks: Dictionary = {}
	var contact: String = "unverified"
	var skill_polygon: PackedVector2Array = PackedVector2Array()
	var skill_geometry_key: String = ""

class DrawItem extends RefCounted:
	var actor: Dictionary
	var foot: Vector2
	var direction: Vector2
	var friendly: bool
	var dead: bool
	var type_name: String
	var sequence: int

var manifest: Dictionary = {}
var manifest_path: String = DEFAULT_MANIFEST
var body_height_screen: float = 44.0
var poses: Dictionary = {}
var aliases: Dictionary = {}
var asset_errors: Array = []
var asset_warnings: Array = []
var missing_types: Dictionary = {}
var alias_uses: Dictionary = {}
var last_actor_count: int = 0
var last_draw_count: int = 0
var last_skipped_count: int = 0
var _items: Array[DrawItem] = []
var _pool: Array[DrawItem] = []
var _loaded_paths: Dictionary = {}
var fortification_pose: Pose
var fortification_height_screen: float = 54.0
var fortification_crew_offset: Vector2 = Vector2.ZERO
var last_structure_count: int = 0
var missing_structure_asset: bool = false
var _actor_samples: Dictionary = {}
var _pending_actor_samples: Dictionary = {}
var _actor_samples_observed: bool = false
var actor_samples: Dictionary:
	get:
		# Expand only already-selected frames. Reading diagnostics must never
		# advance walking contacts or consume another release presentation.
		for key in _pending_actor_samples:
			_actor_samples[key]=_expand_animation_sample(_pending_actor_samples[key])
		_pending_actor_samples.clear()
		_actor_samples_observed=true
		return _actor_samples
	set(value):
		_actor_samples=value
		_pending_actor_samples.clear()
		_actor_samples_observed=true
var direction_fallbacks: Dictionary = {}
var _bound_battle: WeakRef
var _bound_generation: int = -1
var _shot_receipts: Dictionary = {}
var _enemy_by_id: Dictionary = {}
var _unit_by_id: Dictionary = {}
var _facing_cache: Dictionary = {}
var _render_height: float = 44.0
var _motion_tracks: Dictionary = {}
var missing_actions: Dictionary = {}
var rigs: Dictionary = {}
var _contact_tracks: Dictionary = {}
var capture_rig_diagnostics: bool = false
var asset_cache_hit: bool = false
var asset_prepare_microseconds: int = 0
var _bounds_cache: Dictionary = {}
var skill_motion = SkillMotion.new()
var _display_frame: int = -1
var _display_serial: int = 0
var _display_clock: float = -1.0
var _display_field: Rect2
var _display_mirrored: bool = false
var _display_units: Array = []
var _display_enemies: Array = []
var _display_unit_count: int = -1
var _display_enemy_count: int = -1
var _display_battle_id: int = 0
var _unit_slots: Dictionary = {}
var _enemy_slots: Dictionary = {}
var _frame_facing: Dictionary = {}
var _frame_facing_targets: Dictionary = {}
var _frame_actors: Dictionary = {}
var _mesh_lifecycle_dirty: bool = true
var _id_maps_dirty: bool = true
var _spatial_facing_draw: bool = false

func _init(path: String = DEFAULT_MANIFEST) -> void:
	if not FileAccess.file_exists(path): return
	var started: int=Time.get_ticks_usec()
	var cached: Dictionary=compiled_asset_cache.get(path,{})
	if not cached.is_empty() and int(cached.get("schema",0))==COMPILED_ASSET_SCHEMA and str(cached.digest)==FileAccess.get_sha256(path):
		manifest_path=path; manifest=cached.manifest; poses=cached.poses; rigs=cached.rigs; aliases=cached.aliases
		body_height_screen=float(cached.height)
		fortification_pose=cached.cover; fortification_height_screen=float(cached.coverHeight); fortification_crew_offset=cached.crewOffset
		_loaded_paths=cached.paths.duplicate(false); asset_warnings=cached.warnings.duplicate(false)
		asset_cache_hit=true
	else: reload_assets(path)
	asset_prepare_microseconds=Time.get_ticks_usec()-started

func _numbers(value: Variant, length: int) -> bool:
	if not value is Array or value.size()!=length: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

func reload_assets(path: String = DEFAULT_MANIFEST) -> bool:
	manifest_path = path
	invalidate_display_frame()
	skill_motion.reset()
	# Never clear dictionaries shared by other preview/render instances.
	poses={}; rigs={}; aliases={}; manifest={}; asset_errors=[]; asset_warnings=[]; _bounds_cache={}
	asset_cache_hit=false
	missing_types.clear(); alias_uses.clear(); _loaded_paths={}
	_clear_actor_samples(); direction_fallbacks.clear()
	_motion_tracks.clear(); missing_actions.clear(); _contact_tracks.clear()
	fortification_pose=null
	fortification_crew_offset=Vector2.ZERO
	missing_structure_asset=false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		asset_errors.append("Missing or invalid painted manifest: "+path)
		return false
	manifest = parsed
	var configured_height: float = float(manifest.get("bodyHeightScreen",44.0))
	body_height_screen = configured_height if is_finite(configured_height) and configured_height>0 else 44.0
	aliases = manifest.get("roleAliases",{}) if manifest.get("roleAliases",{}) is Dictionary else {}
	var common: Dictionary = manifest.get("frames",{}) if manifest.get("frames",{}) is Dictionary else {}
	_compile_faction("friendly",common,manifest)
	var faction_records: Dictionary = manifest.get("factions",{}) if manifest.get("factions",{}) is Dictionary else {}
	var hostile: Dictionary = faction_records.get("enemy",{}) if faction_records.get("enemy",{}) is Dictionary else {}
	var hostile_frames: Dictionary = hostile.get("frames",{}) if hostile.get("frames",{}) is Dictionary else {}
	# An absent hostile asset is reported; it never silently borrows navy armor.
	var hostile_context: Dictionary = manifest.duplicate(false)
	hostile_context.merge(hostile,true)
	_compile_faction("enemy",hostile_frames,hostile_context)
	var structures: Dictionary = manifest.get("structures",{}) if manifest.get("structures",{}) is Dictionary else {}
	var cover: Dictionary = structures.get("fortification",{}) if structures.get("fortification",{}) is Dictionary else {}
	if not cover.is_empty():
		var cover_path: String = str(cover.get("texture",""))
		if not cover_path.is_empty() and FileAccess.file_exists(cover_path):
			var cover_texture: Texture2D = _texture(cover_path)
			if cover_texture!=null:
				var settings: Dictionary = cover.duplicate(true)
				settings["rect"]=cover.get("rect",[0,0,cover_texture.get_width(),cover_texture.get_height()])
				fortification_pose=_compile_pose(settings,settings,"structure/fortification")
				fortification_height_screen=maxf(1.0,float(cover.get("bodyHeightScreen",54.0)))
				var crew_offset: Variant = cover.get("crewOffset",[0,0])
				if _numbers(crew_offset,2): fortification_crew_offset=Vector2(float(crew_offset[0]),float(crew_offset[1]))
		else:
			asset_warnings.append("Missing painted fortification texture: "+cover_path)
	if is_ready():
		compiled_asset_cache[path]={"schema":COMPILED_ASSET_SCHEMA,"digest":FileAccess.get_sha256(path),"manifest":manifest,"poses":poses,"rigs":rigs,"aliases":aliases,"height":body_height_screen,"cover":fortification_pose,"coverHeight":fortification_height_screen,"crewOffset":fortification_crew_offset,"paths":_loaded_paths.duplicate(false),"warnings":asset_warnings.duplicate(false)}
	return is_ready()

func _texture(path: String) -> Texture2D:
	if path.is_empty(): return null
	if not _loaded_paths.has(path):
		var stamp: int = FileAccess.get_modified_time(path)
		if int(texture_stamps.get(path,-1))!=stamp:
			texture_cache.erase(path)
		texture_stamps[path] = stamp
		_loaded_paths[path] = true
	if texture_cache.has(path): return texture_cache[path]
	var image: Image = Image.load_from_file(path)
	if image==null or image.is_empty():
		asset_errors.append("Painted texture cannot be decoded: "+path)
		return null
	var result: ImageTexture = ImageTexture.create_from_image(image)
	texture_cache[path] = result
	return result

func _compile_pose(value: Variant, context: Dictionary, note: String) -> Pose:
	var record: Dictionary = value if value is Dictionary else {"rect":value} if _numbers(value,4) else {}
	var rectangle: Variant = record.get("rect",context.get("rect",[]))
	if not _numbers(rectangle,4):
		asset_errors.append(note+": missing finite pixel rectangle")
		return null
	var region: Rect2 = Rect2(float(rectangle[0]),float(rectangle[1]),float(rectangle[2]),float(rectangle[3]))
	var texture_path: String = str(record.get("texture",context.get("texture",context.get("atlas",""))))
	var texture: Texture2D = _texture(texture_path)
	if texture==null: return null
	if not region.has_area() or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region):
		asset_errors.append(note+": frame rectangle outside actual atlas")
		return null
	var result: Pose = Pose.new()
	result.texture = texture
	result.texture_path = texture_path
	result.region = region
	result.skill_polygon=PackedVector2Array([Vector2.ZERO,Vector2(region.size.x,0),region.size,Vector2(0,region.size.y)])
	result.skill_geometry_key="pose:"+str(result.get_instance_id())
	var anchor: Variant = record.get("anchor",context.get("anchor",[]))
	if not _numbers(anchor,2):
		anchor = [region.size.x*.5,region.size.y*.9]
		asset_warnings.append(note+": estimated foot anchor")
	result.anchor = Vector2(float(anchor[0]),float(anchor[1]))
	var shift: Variant = record.get("offset",context.get("offset",[]))
	if _numbers(shift,2): result.offset = Vector2(float(shift[0]),float(shift[1]))
	var measured_height: float = float(record.get("bodyHeightPixels",context.get("bodyHeightPixels",0.0)))
	if not is_finite(measured_height) or measured_height<=0:
		measured_height = region.size.y*.72
		asset_warnings.append(note+": body height is estimated, not measured")
	result.body_height = measured_height
	result.tint = Color(str(record.get("modulate",context.get("modulate","ffffff"))))
	var landmarks: Variant = record.get("landmarks",{})
	if landmarks is Dictionary:
		for landmark in landmarks:
			if _numbers(landmarks[landmark],2):
				result.landmarks[str(landmark)]=Vector2(float(landmarks[landmark][0]),float(landmarks[landmark][1]))
	result.contact=str(record.get("contact","unverified"))
	result.cutout = AtlasTexture.new()
	result.cutout.atlas = texture
	result.cutout.region = region
	result.cutout.filter_clip = true
	return result

func _compile_faction(side: String, role_records: Dictionary, faction_context: Dictionary) -> void:
	for role in role_records:
		if not role_records[role] is Dictionary: continue
		var role_record: Dictionary = role_records[role]
		var context: Dictionary = faction_context.duplicate(false)
		context.merge(role_record,true)
		for direction in ["ne","se","sw","nw"]:
			var direction_value: Variant = role_record.get(direction,{})
			var direction_record: Dictionary = direction_value if direction_value is Dictionary else {"walk":direction_value} if direction_value is Array else {}
			if direction_record.is_empty(): continue
			var base: Dictionary = context.duplicate(false)
			base.merge(direction_record,true)
			if direction_record.get("rig",{}) is Dictionary and not direction_record.get("rig",{}).is_empty():
				var rig: Dictionary=_compile_rig(direction_record.rig,side+"/"+str(role)+"/"+direction)
				if not rig.is_empty(): rigs[side+"/"+str(role)+"/"+direction]=rig
			var animations: Dictionary = {}
			for state in ["idle","walk","aim","attack","recover","heal","death"]:
				var frame_values: Variant = direction_record.get(state,[])
				var fps: float = float(direction_record.get("fps",8.0))
				var state_context: Dictionary = base.duplicate(false)
				var release_frame: int = -1
				if frame_values is Dictionary:
					fps = float(frame_values.get("fps",fps))
					state_context.merge(frame_values,true)
					release_frame=int(frame_values.get("releaseFrame",-1))
					frame_values = frame_values.get("frames",[])
				if not frame_values is Array: frame_values = []
				if frame_values.is_empty() and state=="walk" and direction_record.has("rect"): frame_values = [direction_record]
				var compiled: Array[Pose] = []
				for index in range(frame_values.size()):
					var pose: Pose = _compile_pose(frame_values[index],state_context,side+"/"+str(role)+"/"+direction+"/"+state+"/"+str(index))
					if pose!=null:
						compiled.append(pose)
				if not compiled.is_empty():
					if release_frame>=compiled.size() or (state=="attack" and release_frame==0):
						asset_errors.append(side+"/"+str(role)+"/"+direction+": invalid release frame")
					animations[state] = {"frames":compiled,"fps":maxf(.1,fps),"releaseFrame":release_frame,"authored":true,"sourceState":state,"direction":direction,"strideBodyHeights":maxf(.1,float(state_context.get("strideBodyHeights",.75))),"gaitVerified":bool(state_context.get("gaitVerified",false))}
			if not animations.has("walk") and not animations.has("idle"): continue
			if not animations.has("idle"):
				animations["idle"] = {"frames":[animations.walk.frames[0]],"fps":1.0,"authored":false,"sourceState":"walk","direction":direction,"releaseFrame":-1}
			poses[side+"/"+str(role)+"/"+direction] = animations
		# Each authored atlas uses one measured role height. New action atlases
		# may have a different pixel resolution from the retained walk atlas;
		# their fixed metadata scale is never recomputed from individual frames.

func _compile_rig(record: Dictionary, note: String) -> Dictionary:
	var path: String=str(record.get("texture",""))
	var texture: Texture2D=_texture(path)
	if texture==null or not _numbers(record.get("rect",[]),4) or not _numbers(record.get("pelvis",[]),2):
		asset_errors.append(note+": invalid painted UV rig source")
		return {}
	var raw: Array=record.rect
	var region: Rect2=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
	if not region.has_area() or not Rect2(Vector2.ZERO,texture.get_size()).encloses(region) or not is_finite(float(record.get("bodyHeightPixels",0))) or float(record.get("bodyHeightPixels",0))<=0:
		asset_errors.append(note+": UV rig region outside source")
		return {}
	var parts: Dictionary={}
	var records: Dictionary=record.get("parts",{})
	var required_parts: Array=["torso"]
	for leg_name in record.get("legNames",["left","right"]):
		for kind in ["Thigh","Shin","Foot"]: required_parts.append(str(leg_name)+kind)
	for name in required_parts:
		var part: Dictionary=records.get(name,{})
		var points: Variant=part.get("polygon",[])
		if not points is Array or points.size()<3 or not _numbers(part.get("start",[]),2) or not _numbers(part.get("end",[]),2):
			asset_errors.append(note+": missing UV rig part "+name)
			return {}
		var polygon: PackedVector2Array=PackedVector2Array()
		var uv: PackedVector2Array=PackedVector2Array()
		for point in points:
			if not _numbers(point,2):
				asset_errors.append(note+": nonfinite UV point "+name)
				return {}
			var local: Vector2=Vector2(float(point[0]),float(point[1]))
			if local.x<0 or local.y<0 or local.x>region.size.x or local.y>region.size.y:
				asset_errors.append(note+": UV point outside registered cell "+name)
				return {}
			polygon.append(local)
			uv.append((region.position+local)/texture.get_size())
		var origin: Vector2=Vector2(float(part.start[0]),float(part.start[1]))
		var local_polygon: PackedVector2Array=PackedVector2Array()
		var vertices: PackedVector3Array=PackedVector3Array()
		for point in polygon:
			local_polygon.append(point-origin)
			vertices.append(Vector3(point.x-origin.x,point.y-origin.y,0.0))
		var indices: PackedInt32Array=Geometry2D.triangulate_polygon(local_polygon)
		if indices.is_empty():
			asset_errors.append(note+": UV part cannot be triangulated "+name)
			return {}
		var arrays: Array=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
		var mesh: ArrayMesh=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var endpoint: Vector2=Vector2(float(part.end[0]),float(part.end[1]))
		parts[name]={"polygon":polygon,"localPolygon":local_polygon,"mesh":mesh,"uv":uv,"start":origin,"end":endpoint,"restVector":endpoint-origin,"restLength":origin.distance_to(endpoint),"restAngle":(endpoint-origin).angle(),"skillGeometryKey":"rig:"+str(mesh.get_instance_id())}
	var neutral: Dictionary=record.get("neutralSoles",{})
	for side in record.get("legNames",["left","right"]):
		if not _numbers(neutral.get(side,[]),2) or parts[side+"Thigh"].end!=parts[side+"Shin"].start or parts[side+"Shin"].end!=parts[side+"Foot"].start:
			asset_errors.append(note+": disconnected source joints or missing neutral sole")
			return {}
		for kind in ["Thigh","Shin","Foot"]:
			if parts[side+kind].start.distance_to(parts[side+kind].end)<.001:
				asset_errors.append(note+": zero-length source limb")
				return {}
	var result: Dictionary=record.duplicate(true)
	result["registrationKey"]=note
	result["texturePath"]=path; result["texture"]=texture; result["region"]=region; result["parts"]=parts
	result["pelvis"]=Vector2(float(record.pelvis[0]),float(record.pelvis[1]))
	result["regionArray"]=[region.position.x,region.position.y,region.size.x,region.size.y]
	result["anchorPoint"]=Vector2(float(record.anchor[0]),float(record.anchor[1]))
	result["neutralOffsets"]={}
	result["hipOffsets"]={}
	result["boneLengths"]={}
	result["kneeBendSigns"]={}
	result["legNames"]=record.get("legNames",["left","right"]).duplicate()
	result["drawOrder"]=record.get("drawOrder",["left","right"]).duplicate()
	result["legPartNames"]={}
	for leg_name in result.legNames:
		var sole: Array=neutral[leg_name]
		result.neutralOffsets[leg_name]=Vector2(float(sole[0]),float(sole[1]))-result.anchorPoint
		result.hipOffsets[leg_name]=parts[leg_name+"Thigh"].start-result.pelvis
		result.boneLengths[leg_name]=Vector2(float(parts[leg_name+"Thigh"].restLength),float(parts[leg_name+"Shin"].restLength))
		# Each view is separately painted. Its knee branch belongs to the source
		# joints, not travel.x: flipping it would turn the shin across the shoe.
		var source_thigh: Dictionary=parts[leg_name+"Thigh"]
		var source_axis: Vector2=parts[leg_name+"Shin"].end-source_thigh.start
		var source_upper: Vector2=source_thigh.end-source_thigh.start
		var source_bend: float=source_upper.dot(Vector2(source_axis.y,-source_axis.x))
		result.kneeBendSigns[leg_name]=-1.0 if source_bend<0.0 else 1.0
		result.legPartNames[leg_name]=[leg_name+"Thigh",leg_name+"Shin",leg_name+"Foot"]
	if result.legNames.size()==2:
		result["walkSoles"]={}
		result["walkReach"]={}
		for name in result.legNames:
			var foot: Dictionary=parts[name+"Foot"]
			var hip: Vector2=parts[name+"Thigh"].start
			# A combat pose's wide toes are not walking lanes. Put each ankle
			# under its OWN hip, retaining its painted ground-depth/foreshortening.
			result.walkSoles[name]=Vector2(hip.x+foot.restVector.x,foot.end.y)
			var lengths: Vector2=result.boneLengths[name]
			result.walkReach[name]=lengths.x+lengths.y-minf(lengths.x,lengths.y)*.04
	return result

func is_ready() -> bool:
	return not poses.is_empty() and asset_errors.is_empty()

func _role(type_name: String) -> String:
	var role: String = str(aliases.get(type_name,DIRECT_ROLES.get(type_name,type_name)))
	if role!=type_name: alias_uses[type_name] = role
	return role

func _animation(type_name: String, friendly: bool, direction: String, state: String) -> Dictionary:
	var side: String = "friendly" if friendly else "enemy"
	var prefix: String = side+"/"+_role(type_name)+"/"
	var key: String = prefix+direction
	# NE/SW walk artwork remains limited. Select an available source without
	# mirroring equipment or claiming that it is a newly authored direction.
	if (not poses.has(key) or (state=="walk" and not poses[key].has("walk"))) and direction in ["se","nw"]:
		var available_direction: String = "ne" if direction=="se" else "sw"
		if poses.has(prefix+available_direction):
			direction_fallbacks[side+"/"+type_name+"/"+state+"/"+direction]=available_direction
			key=prefix+available_direction
	if not poses.has(key):
		missing_types[side+"/"+type_name+"/"+direction] = true
		return {}
	var animations: Dictionary = poses[key]
	if not animations.has(state) and not (state in ["hit","death"] and rigs.has(key)): missing_actions[side+"/"+type_name+"/"+direction+"/"+state]=true
	return animations.get(state,animations.get("idle",{}))

func _direction_name(direction: Vector2, friendly: bool) -> String:
	if direction.length_squared()<.000001: return "ne" if friendly else "sw"
	if direction.y<0: return "ne" if direction.x>=0 else "nw"
	return "se" if direction.x>=0 else "sw"

func _pose(animation: Dictionary, state: String, clock: float, phase: float) -> Pose:
	if animation.is_empty(): return null
	var frames: Array = animation.frames
	var frame: int = int(floor(maxf(0.0,clock+(phase if state=="walk" else 0.0))*float(animation.fps)))
	frame = frame%frames.size() if state in ["walk","idle"] else mini(frame,frames.size()-1)
	return frames[frame]

func _battle_ref() -> Node2D:
	if _bound_battle==null: return null
	var value: Object = _bound_battle.get_ref()
	return value as Node2D if is_instance_valid(value) else null

func bind_battle(battle: Node2D) -> void:
	var previous: Node2D = _battle_ref()
	_display_battle_id=battle.get_instance_id() if battle!=null else 0
	if previous!=battle:
		invalidate_display_frame()
		_mesh_lifecycle_dirty=true
		skill_motion.reset()
		if previous!=null and previous.presentation_event.is_connected(_on_battle_event): previous.presentation_event.disconnect(_on_battle_event)
		_bound_battle=weakref(battle) if battle!=null else null
		_bound_generation=-1
		if battle!=null and not battle.presentation_event.is_connected(_on_battle_event): battle.presentation_event.connect(_on_battle_event)
	if battle!=null and _bound_generation!=int(battle.battle_generation):
		invalidate_display_frame()
		_mesh_lifecycle_dirty=true
		skill_motion.reset()
		_bound_generation=int(battle.battle_generation)
		_shot_receipts.clear(); _facing_cache.clear(); _clear_actor_samples(); _motion_tracks.clear(); _contact_tracks.clear()
		_enemy_by_id.clear(); _unit_by_id.clear(); _enemy_slots.clear(); _unit_slots.clear()

func invalidate_display_frame(membership_changed: bool = true) -> void:
	# Events/layout changes invalidate preparation, never simulation state.
	_display_frame=-1
	if membership_changed: _id_maps_dirty=true

func display_frame_serial(battle: Node2D) -> int:
	_ensure_display_frame(battle)
	return _display_serial

func _ensure_display_frame(battle: Node2D) -> void:
	if battle==null: return
	if _display_battle_id!=battle.get_instance_id() or _bound_generation!=int(battle.battle_generation): bind_battle(battle)
	var frame: int=Engine.get_process_frames()
	var roster_changed: bool=_display_unit_count!=battle.units.size() or _display_enemy_count!=battle.enemies.size() or not is_same(_display_units,battle.units) or not is_same(_display_enemies,battle.enemies)
	if _display_frame==frame and _display_clock==float(battle.animation_time) and _display_field==battle.field_rect and _display_mirrored==bool(battle.presentation_mirrored) and not roster_changed and not _id_maps_dirty: return
	_display_frame=frame
	_display_serial+=1
	_display_clock=float(battle.animation_time)
	_display_field=battle.field_rect
	_display_mirrored=bool(battle.presentation_mirrored)
	_display_units=battle.units; _display_enemies=battle.enemies
	_display_unit_count=battle.units.size(); _display_enemy_count=battle.enemies.size()
	_frame_facing.clear(); _frame_facing_targets.clear(); _frame_actors.clear()
	if roster_changed or _id_maps_dirty:
		_enemy_by_id.clear(); _unit_by_id.clear(); _enemy_slots.clear(); _unit_slots.clear()
		for index in range(battle.units.size()):
			var actor: Dictionary=battle.units[index]
			_unit_by_id[int(actor.id)]=actor; _unit_slots[int(actor.id)]=index
		for index in range(battle.enemies.size()):
			var actor: Dictionary=battle.enemies[index]
			_enemy_by_id[int(actor.id)]=actor; _enemy_slots[int(actor.id)]=index
		_id_maps_dirty=false
	_render_height=body_height_screen*clampf(float(battle.field_rect.size.y)/620.0,.65,1.5)
	skill_motion.prune_actor_meshes(_unit_by_id,float(battle.animation_time),roster_changed or _mesh_lifecycle_dirty)
	_mesh_lifecycle_dirty=false

func _indexed_actor(id: int, friendly: bool, battle: Node2D) -> Dictionary:
	if id<0: return {}
	var roster: Array=battle.units if friendly else battle.enemies
	var indexed: Dictionary=_unit_by_id if friendly else _enemy_by_id
	var slots: Dictionary=_unit_slots if friendly else _enemy_slots
	var cached: Dictionary=indexed.get(id,{})
	var slot: int=int(slots.get(id,-1))
	if not cached.is_empty() and slot>=0 and slot<roster.size() and is_same(roster[slot],cached) and int(cached.get("id",-1))==id: return cached
	# A positive miss/replacement can occur between draws. Check the live
	# roster and repair that ID; never infer membership from array length.
	for index in range(roster.size()):
		var actor: Dictionary=roster[index]
		if int(actor.get("id",-1))!=id: continue
		indexed[id]=actor; slots[id]=index
		return actor
	indexed.erase(id); slots.erase(id)
	return {}

func _walk_projection(direction: Vector2) -> Vector2:
	# The source camera compresses ground depth 2:1. A screen perpendicular
	# is NOT a ground perpendicular, and a normalized screen vector loses it.
	var ground: Vector2=Vector2(direction.x,direction.y/.5).normalized()
	return Vector2(ground.x,ground.y*.5) if ground.length_squared()>.000001 else Vector2(.70710678,-.35355339)

func _walk_cycle_stride(rig: Dictionary, direction: Vector2) -> float:
	var profile: Dictionary=rig.get("locomotion",{})
	var body: float=float(rig.bodyHeightPixels)
	var stride: float=body*float(profile.get("cycleBodyHeights",.64))
	var projection: Vector2=_walk_projection(direction)
	var stance: float=float(profile.get("stanceFraction",.62))
	# Hermite swing can travel slightly beyond the contact endpoints. This
	# conservative envelope also contains both original endpoint derivatives.
	var envelope: float=stance*.5+(1.0-stance)*.10
	var maximum_drop: float=body*float(profile.get("maximumPelvisDropBodyHeights",.085))
	for name in rig.legNames:
		var foot: Dictionary=rig.parts[name+"Foot"]
		var hip: Vector2=rig.parts[name+"Thigh"].start
		var offset: Vector2=rig.walkSoles[name]-foot.restVector-hip-Vector2(0,maximum_drop)
		var radius: float=maxf(.001,float(rig.walkReach[name])-float(foot.restLength)*float(profile.get("footRotationRadians",.06)))
		var dot: float=absf(offset.dot(projection))
		var squared: float=projection.length_squared()
		var room: float=maxf(0.0,radius*radius-offset.length_squared())
		var reach: float=(sqrt(dot*dot+squared*room)-dot)/maxf(.000001,squared)
		stride=minf(stride,reach/maxf(.001,envelope))
	return maxf(.001,stride/body)

func _walk_phase(actor: Dictionary, friendly: bool, animation: Dictionary, direction: String = "") -> float:
	var rig_key: String=("friendly/" if friendly else "enemy/")+_role(str(actor.get("type",actor.get("kind","spear"))))+"/"+direction
	if not rigs.has(rig_key):
		rig_key=("friendly/" if friendly else "enemy/")+_role(str(actor.get("type",actor.get("kind","spear"))))+"/"+str(animation.get("direction",direction))
	var rig: Dictionary=rigs.get(rig_key,{})
	var biped: bool=rig.has("walkSoles")
	var facing: Vector2={"ne":Vector2(1,-.5),"se":Vector2(1,.5),"sw":Vector2(-1,.5),"nw":Vector2(-1,-.5)}.get(direction,Vector2(1,-.5))
	var stride: float=maxf(.1,float(rig.get("strideBodyHeights",animation.get("strideBodyHeights",.75))))
	if bool(actor.get("preview",false)):
		if biped: stride=_walk_cycle_stride(rig,facing)*_walk_projection(facing).length()
		return fposmod(float(actor.get("walkDistanceBodyHeights",0.0))/stride,1.0)
	var battle: Node2D=_battle_ref()
	if battle==null or int(actor.get("id",-1))<0: return 0.0
	var key: String=_actor_key(actor,friendly)
	var point: Vector2=_position(actor)
	var now: float=float(battle.animation_time)
	var previous: Dictionary=_motion_tracks.get(key,{})
	var cycles: float=float(previous.get("cycles",0.0))
	var measured_speed: float=float(previous.get("speedBodyHeightsPerSecond",0.0))
	var blend: float=float(previous.get("gaitBlend",0.0))
	var gait_forward: Vector2=previous.get("gaitForward",facing.normalized())
	var source_stride: float=stride
	if biped:
		source_stride=float(previous.sourceCycleBodyHeights) if str(previous.get("sourceRig",""))==rig_key else _walk_cycle_stride(rig,gait_forward)
		stride=source_stride*_walk_projection(gait_forward).length()
	if not previous.is_empty() and now>float(previous.get("time",now)):
		# Convert both positions through the CURRENT projection. Resizing or
		# moving the field cannot create a fictitious step. No actor writes.
		var displacement: Vector2=battle._screen(point)-battle._screen(previous.point)
		var distance: float=displacement.length()/maxf(1.0,_render_height)
		var delta: float=now-float(previous.time)
		measured_speed=distance/maxf(.000001,delta)
		var moving: bool=str(actor.get("animation","idle"))=="walk" and distance>.000001
		if distance>3.0 or delta>1.0:
			cycles=0.0 # generation/teleport/long discontinuity, never a sprint
			measured_speed=0.0
			blend=0.0
			_contact_tracks.erase(key+"/left"); _contact_tracks.erase(key+"/right")
		elif moving:
			# Gameplay aim turns gradually. Feet follow actual CURRENT projected
			# travel, while the source/weapon keep their existing facing owner.
			gait_forward=displacement.normalized()
			if biped:
				source_stride=_walk_cycle_stride(rig,gait_forward)
				stride=source_stride*_walk_projection(gait_forward).length()
			cycles+=distance/stride
		if biped:
			blend=move_toward(blend,1.0 if moving else 0.0,delta/maxf(.01,float(rig.get("locomotion",{}).get("transitionSeconds",.18))))
			if blend<=0.0:
				# No stale planted point may survive a completed settle/attack.
				for name in rig.legNames: _contact_tracks.erase(key+"/"+str(name))
	_motion_tracks[key]={"point":point,"time":now,"cycles":cycles,"gaitBlend":blend,"gaitForward":gait_forward,"sourceRig":rig_key,"sourceCycleBodyHeights":source_stride,"speedBodyHeightsPerSecond":measured_speed,"cyclesPerSimulationSecond":measured_speed/maxf(.001,stride),"strideBodyHeights":stride,"screenPixelsPerSimulationSecond":measured_speed*_render_height,"measurementClock":"simulation_time; last advanced step"}
	return fposmod(cycles,1.0)

func _actor_key(actor: Dictionary, friendly: bool) -> String:
	return ("friendly/" if friendly else "enemy/")+str(int(actor.get("id",-1)))

func _position(actor: Dictionary) -> Vector2:
	return actor.get("position",Vector2(float(actor.get("x",0)),float(actor.get("y",0))))

func _attack_plan(actor: Dictionary, friendly: bool) -> Dictionary:
	if friendly: return actor.get("attackPlan",{})
	var ranged: Dictionary = actor.get("rangedPlan",{})
	return ranged if not ranged.is_empty() else actor.get("counterPlan",{})

func _attack_token(actor: Dictionary, friendly: bool) -> String:
	if not friendly: return ""
	var plan: Dictionary = _attack_plan(actor,true)
	var meta: Dictionary = plan.get("skillMeta",actor.get("skillMeta",{}))
	var motion: String=str(meta.get("motionToken",""))
	return motion if not motion.is_empty() else str(meta.get("attackId",""))

func _receipt_for(actor: Dictionary, friendly: bool) -> Dictionary:
	if bool(actor.get("preview",false)): return {}
	var receipt: Dictionary = _shot_receipts.get(_actor_key(actor,friendly),{})
	var battle: Node2D = _battle_ref()
	if receipt.is_empty() or battle==null or int(receipt.get("generation",-1))!=int(battle.battle_generation): return {}
	var token: String = _attack_token(actor,friendly)
	if not token.is_empty():
		if token!=str(receipt.get("motionToken",receipt.get("attackId",""))): return {}
	else:
		var start: float = float(battle.elapsed)-float(actor.get("animationClock",0))
		if absf(start-float(receipt.get("cycleStart",-100)))>=.0001: return {}
	var result: Dictionary=receipt.duplicate(false)
	var commits: Array=receipt.get("commits",[])
	var index: int=int(receipt.get("presentedIndex",-1))
	if index>=0 and index<commits.size(): result.merge(commits[index],true)
	result["forceReleaseFrame"]=int(receipt.get("displayFrame",-1))==Engine.get_process_frames() and bool(receipt.get("displayNewRelease",false))
	result["releaseCount"]=commits.size()
	return result

func _stage_release_presentation(actor: Dictionary, friendly: bool) -> void:
	if bool(actor.get("preview",false)) or str(actor.get("animation","")) in ["death","hit"]: return
	var receipt: Dictionary=_receipt_for(actor,friendly)
	if receipt.is_empty(): return
	var track: Dictionary=_shot_receipts.get(_actor_key(actor,friendly),{})
	var frame: int=Engine.get_process_frames()
	if int(track.get("displayFrame",-1))==frame: return
	var next: int=int(track.get("presentedIndex",-1))+1
	var commits: Array=track.get("commits",[])
	track["displayNewRelease"]=next<commits.size()
	if next<commits.size(): track["presentedIndex"]=next
	track["displayFrame"]=frame

func _on_battle_event(event: Dictionary) -> void:
	var battle: Node2D = _battle_ref()
	if battle==null: return
	invalidate_display_frame(false)
	bind_battle(battle)
	skill_motion.consume_event(event,battle)
	var action: String=str(event.get("action",event.get("type","")))
	if action in ["deploy","placed","tower_placed","killed"] or (str(event.get("victimSide",""))=="friendly" and event.has("hpAfter") and float(event.hpAfter)<=0.0):
		_mesh_lifecycle_dirty=true
		_id_maps_dirty=true
	var event_meta: Dictionary=event.get("skillMeta",{})
	var staged_hit: bool=action in ["hit","skill_hit"] and str(event.get("skillId","")) in ["samurai_counter_combo","samurai_isshin","ninja_opening_combo"] and float(event.get("damage",0))>0 and (event.has("hitIndex") or event_meta.has("hitIndex"))
	if action!="shot" and not staged_hit: return
	var friendly: bool = str(event.get("side","friendly"))=="friendly"
	var actor_id: int = int(event.get("actorId",-1))
	var source: Dictionary = _indexed_actor(actor_id,friendly,battle)
	if source.is_empty(): return
	var plan: Dictionary = _attack_plan(source,friendly)
	var clock: float = float(source.get("animationClock",0))
	var victim: Variant = event.get("victimPosition",{})
	var target: Vector2 = Vector2(float(victim.get("x",0)),float(victim.get("y",0))) if victim is Dictionary else Vector2.ZERO
	var meta: Dictionary=event_meta
	var token: String=str(meta.get("motionToken",""))
	if token.is_empty(): token=str(meta.get("attackId",_attack_token(source,friendly)))
	var key: String=_actor_key(source,friendly)
	var track: Dictionary=_shot_receipts.get(key,{})
	var start: float=float(battle.elapsed)-clock
	if track.is_empty() or int(track.get("generation",-1))!=int(battle.battle_generation) or str(track.get("motionToken",""))!=token or (token.is_empty() and absf(float(track.get("cycleStart",-100))-start)>=.0001):
		track={"generation":int(battle.battle_generation),"motionToken":token,"attackId":str(meta.get("attackId",token)),"cycleStart":start,"releaseTimes":plan.get("releaseTimes",plan.get("ninjaImpactTimes",[])).duplicate(),"commits":[],"seenReleases":{},"presentedIndex":-1,"displayFrame":-1,"displayNewRelease":false}
	var hit_index: int=int(event.get("hitIndex",meta.get("hitIndex",-1)))
	var release_index: int=maxi(0,int(event.get("releaseIndex",meta.get("releaseIndex",hit_index if hit_index>=0 else 0))))
	# Simultaneous barrage arrows share a release; staged shots have indices.
	var release_key: String=str(release_index)
	if track.seenReleases.has(release_key):
		if staged_hit:
			var previous_commit: Dictionary=track.commits[int(track.seenReleases[release_key])]
			previous_commit["hitIndex"]=hit_index
		return
	track.seenReleases[release_key]=track.commits.size()
	var times: Array=track.get("releaseTimes",[])
	var scheduled: float=float(times[release_index]) if release_index<times.size() else float(event.get("releaseTime",plan.get("releaseTime",clock)))
	var commit: Dictionary={"clock":clock,"scheduledRelease":minf(clock,maxf(0.0,scheduled)),"targetPosition":target,"eventId":int(event.get("eventId",-1)),"releaseIndex":release_index,"hitIndex":hit_index,"skillId":str(event.get("skillId","")),"effectKind":str(event.get("effectKind",""))}
	track.commits.append(commit)
	track.merge(commit,true)
	_shot_receipts[key]=track

func _attack_context(actor: Dictionary, friendly: bool, animation: Dictionary) -> Dictionary:
	var battle: Node2D = null if bool(actor.get("preview",false)) else _battle_ref()
	var duration: float = float(actor.get("attackDuration",.5 if battle==null or not friendly else battle._animation_duration("attack")))
	duration=maxf(.001,duration)
	var receipt: Dictionary = _receipt_for(actor,friendly)
	var plan: Dictionary = _attack_plan(actor,friendly)
	var preview: bool = battle==null or bool(actor.get("preview",false))
	var explicit: Dictionary=actor.get("paintedSkillMotion",{}) if bool(actor.get("preview",false)) else {}
	var ratio: float = float(animation.get("releaseRatio",2.0/3.0 if _role(str(actor.get("type",actor.get("kind",""))))=="archer" else .5))
	var release_time: float = float(receipt.get("clock",explicit.get("releaseTime",plan.get("releaseTime",duration*ratio))))
	return {"duration":duration,"releaseTime":clampf(release_time,.0001,duration-.00001),"releaseTimes":explicit.get("releaseTimes",plan.get("releaseTimes",receipt.get("releaseTimes",[]))),"committed":bool(explicit.get("committed",false)) if not explicit.is_empty() else not receipt.is_empty(),"previewTiming":preview,"cancelled":not preview and receipt.is_empty() and plan.is_empty(),"eventId":int(receipt.get("eventId",-1)),"forceReleaseFrame":bool(receipt.get("forceReleaseFrame",false)),"releaseIndex":int(explicit.get("releaseIndex",receipt.get("releaseIndex",-1))),"releaseCount":int(explicit.get("releaseCount",receipt.get("releaseCount",0))),"displayClock":float(receipt.get("scheduledRelease",receipt.get("clock",0)))}

func _frame_index(animation: Dictionary, state: String, clock: float, phase: float, context: Dictionary = {}) -> int:
	var count: int = animation.get("frames",[]).size()
	if count<=0: return -1
	if state=="walk" and context.has("walkPhase"):
		return mini(count-1,int(floor(fposmod(float(context.walkPhase),1.0)*count)))
	var release: int = int(animation.get("releaseFrame",-1))
	if state=="attack" and release>0 and release<count:
		if bool(context.get("committed",false)) and bool(context.get("forceReleaseFrame",false)): return release
		var release_time: float = maxf(.0001,float(context.get("releaseTime",.25)))
		var times: Array=context.get("releaseTimes",[])
		if times.size()>1:
			var committed_count: int=clampi(int(context.get("releaseCount",0)),0,times.size())
			if committed_count==0:
				return mini(release-1,int(floor(clampf(clock/maxf(.0001,float(times[0])),0,1)*release)))
			var last_release: float=float(times[committed_count-1])
			if clock<last_release+.08: return release
			if committed_count<times.size():
				var preparation: float=clampf((clock-last_release-.08)/maxf(.0001,float(times[committed_count])-last_release-.08),0,1)
				return mini(release-1,int(floor(preparation*release)))
			release_time=last_release
		if not bool(context.get("committed",false)) and not bool(context.get("previewTiming",false)):
			return mini(release-1,int(floor(clampf(clock/release_time,0.0,1.0)*release)))
		if clock<release_time: return mini(release-1,int(floor(maxf(0,clock)/release_time*release)))
		var recovery: float = maxf(.0001,float(context.get("duration",.5))-release_time)
		return mini(count-1,release+int(floor(clampf((clock-release_time)/recovery,0,1)*(count-release))))
	var frame: int = int(floor(maxf(0,clock+(phase if state=="walk" else 0))*float(animation.get("fps",1))))
	return posmod(frame,count) if state in ["idle","walk"] else mini(frame,count-1)

func _sample_animation(actor: Dictionary, friendly: bool, view_direction: Vector2) -> Dictionary:
	var type_name: String = str(actor.get("type",actor.get("kind","spear")))
	var requested_state: String = str(actor.get("animation","idle"))
	var receipt: Dictionary=_receipt_for(actor,friendly)
	if requested_state not in ["death","hit"] and bool(receipt.get("forceReleaseFrame",false)): requested_state="attack"
	var direction: String = _direction_name(view_direction,friendly)
	var animation: Dictionary = _animation(type_name,friendly,direction,requested_state)
	if animation.is_empty(): return {}
	var context: Dictionary = _attack_context(actor,friendly,animation) if requested_state=="attack" else {}
	var walk_phase: float=_walk_phase(actor,friendly,animation,direction)
	if requested_state=="walk": context["walkPhase"]=walk_phase
	var state: String = "idle" if bool(context.get("cancelled",false)) else requested_state
	if state!=requested_state: animation=_animation(type_name,friendly,direction,state)
	var clock: float = maxf(0,float(context.get("displayClock",0))) if bool(context.get("forceReleaseFrame",false)) else maxf(0,float(actor.get("animationClock",0)))
	var frame: int = _frame_index(animation,state,clock,float(actor.get("animationPhase",0)),context)
	if frame<0: return {}
	var pose: Pose = animation.frames[frame]
	# The renderer needs this selection, not a full public diagnostic record.
	# Animation metadata and the newly-created attack context are retained so
	# later expansion describes this exact frame without sampling it again.
	return {"pose":pose,"_animation":animation,"_context":context,"requestedState":requested_state,"renderState":state,"requestedDirection":direction,"sourceDirection":str(animation.get("direction",direction)),"sourceFrame":frame,"authoredState":bool(animation.get("authored",false)) and str(animation.get("sourceState",""))==state,"releaseEventId":int(context.get("eventId",-1)),"walkPhase":walk_phase}

func _expand_animation_sample(sample: Dictionary) -> Dictionary:
	if sample.is_empty(): return {}
	var pose: Pose=sample.pose
	var animation: Dictionary=sample._animation
	var context: Dictionary=sample._context
	var result: Dictionary={"requestedState":sample.requestedState,"renderState":sample.renderState,"sourceState":str(animation.get("sourceState","idle")),"requestedDirection":sample.requestedDirection,"sourceDirection":sample.sourceDirection,"sourceFrame":sample.sourceFrame,"sourceTexture":pose.texture_path,"sourceRegion":[pose.region.position.x,pose.region.position.y,pose.region.size.x,pose.region.size.y],"authoredState":sample.authoredState,"releaseFrame":int(animation.get("releaseFrame",-1)),"releaseCommitted":bool(context.get("committed",false)),"releaseTime":float(context.get("releaseTime",0)),"releaseEventId":sample.releaseEventId,"previewTiming":bool(context.get("previewTiming",false)),"cancelled":bool(context.get("cancelled",false)),"walkPhase":sample.walkPhase,"gaitVerified":bool(animation.get("gaitVerified",false)),"contact":pose.contact,"landmarks":pose.landmarks.duplicate()}
	if sample.has("_skillMotionId"):
		result["skillMotionId"]=sample._skillMotionId
		result["skillMotionTechnique"]="painted shoulder/hand/weapon cage; actual event driven"
		result["skillMotionVerified"]=false
	if sample.has("_rig"):
		var rig: Dictionary=sample._rig
		result.merge({"renderTechnique":"painted-source-uv-rig","proceduralState":sample.renderState,"authoredState":false,"directionalMirror":false,"temporarySourceReuse":bool(rig.get("temporarySourceReuse",false)),"motionLimit":"procedural grounded torso/limb recoil only; no authored arm/weapon attack" if str(sample.renderState)=="attack" else "candidate source-specific UV motion; visual acceptance pending","sourceTexture":rig.texturePath,"sourceRegion":rig.regionArray,"gaitVerified":false},true)
		if sample.has("_rigJoints"): result["rigJoints"]=sample._rigJoints
	return result

func _clear_actor_samples() -> void:
	# Do not invoke the public getter while discarding the previous frame.
	_actor_samples.clear()
	_pending_actor_samples.clear()

func animation_sample(actor: Dictionary, friendly: bool, view_direction: Vector2) -> Dictionary:
	return _expand_animation_sample(_sample_animation(actor,friendly,view_direction))

func portrait_source(type_name: String, friendly: bool = true, direction: String = "sw") -> Dictionary:
	var pose: Pose = _pose(_animation(type_name,friendly,direction,"idle"),"idle",0.0,0.0)
	if pose==null: return {}
	return {"texture":pose.texture,"sourcePath":pose.texture_path,"region":pose.region,"anchor":pose.anchor,"offset":pose.offset,"bodyHeightPixels":pose.body_height,"atlasTexture":pose.cutout}

func portrait_texture(type_name: String, friendly: bool = true, direction: String = "sw") -> Texture2D:
	var source: Dictionary = portrait_source(type_name,friendly,direction)
	return source.get("atlasTexture")

func pose_bounds(type_name: String, friendly: bool = true) -> Rect2:
	# One framing over every real pose, including extended weapons. Previews
	# never resize the body at state changes or clip a long bow/thrust.
	var prefix: String=("friendly/" if friendly else "enemy/")+_role(type_name)+"/"
	if _bounds_cache.has(prefix): return _bounds_cache[prefix]
	var bounds: Rect2=Rect2()
	var first: bool=true
	for direction in ["ne","se","sw","nw"]:
		var animations: Dictionary=poses.get(prefix+direction,{})
		for state in animations:
			for value in animations[state].frames:
				var pose: Pose=value
				var relative: Rect2=Rect2((-pose.anchor+pose.offset)/pose.body_height,pose.region.size/pose.body_height)
				bounds=relative if first else bounds.merge(relative)
				first=false
	_bounds_cache[prefix]=bounds
	return bounds

func skill_preview_bounds(type_name: String, friendly: bool, level: int) -> Rect2:
	var bounds: Rect2=pose_bounds(type_name,friendly)
	if level<3 or not PREVIEW_SKILLS.has(_role(type_name)) or not bounds.has_area(): return bounds
	# Reserve articulated arm/weapon travel once, never resize during a stroke.
	return bounds.grow_individual(.32,.22,.32,.12)

func preview_state(type_name: String, time: float, direction: String = "", friendly: bool = true, level: int = -1) -> Dictionary:
	# Explicit deterministic PRESENTATION preview. No Battle, attacks, XP,
	# economy or saves are fabricated by this state generator.
	var elapsed: float=maxf(0.0,time) if is_finite(time) else 0.0
	var cycle: float=fposmod(elapsed,4.8)
	var directions: Array[String]=["sw","ne","se","nw"]
	var facing: String=direction if direction in directions else directions[int(floor(elapsed/4.8))%4]
	var vector: Vector2={"ne":Vector2(2,-1),"se":Vector2(2,1),"sw":Vector2(-2,1),"nw":Vector2(-2,-1)}[facing]
	var state: String="idle"
	var clock: float=cycle
	if cycle>=.5 and cycle<1.9:
		state="walk"; clock=cycle-.5
	elif cycle>=2.1 and cycle<2.45:
		state="aim"; clock=cycle-2.1
	elif cycle>=2.45 and cycle<3.05:
		state="heal" if type_name=="monk" else "attack"; clock=cycle-2.45
	elif cycle>=3.05 and cycle<3.4:
		state="recover"; clock=cycle-3.05
	elif cycle>=3.5 and cycle<3.68:
		state="hit"; clock=cycle-3.5
	elif cycle>=3.8 and cycle<4.45:
		state="death"; clock=cycle-3.8
	var result: Dictionary={"type":type_name,"animation":state,"animationClock":clock,"animationPhase":0.0,"attackDuration":.6,"healDuration":.6,"preview":true,"friendly":friendly,"viewDirection":vector,"previewDirection":facing,"walkDistanceBodyHeights":maxf(0.0,cycle-.5)*1.15 if state=="walk" else 0.0}
	if level<1: return result
	result["campaignLevel"]=clampi(level,1,10)
	result["presentationOnly"]=true
	if cycle>=3.7:
		result["animation"]="recover" if cycle<4.0 else "idle"
		result["animationClock"]=cycle-3.7 if cycle<4.0 else cycle-4.0
	var unlocked: Array=[]
	var role_skills: Array=PREVIEW_SKILLS.get(_role(type_name),[])
	for index in range(role_skills.size()):
		if level>=int([3,5,8][index]): unlocked.append(role_skills[index])
	result["skillIds"]=unlocked.duplicate()
	if unlocked.is_empty() or cycle<2.1 or cycle>=3.7: return result
	var skill_id: String=str(unlocked[int(floor(elapsed/4.8))%unlocked.size()])
	var motion_id: String=skill_id
	var skill_clock: float=cycle-2.1
	var duration: float=1.6
	var releases: Array=[.62]
	if skill_id=="archer_double_shot": releases=[duration*.42,duration*.76]
	elif skill_id=="samurai_counter_combo": releases=[duration*.35,duration*.72]
	elif skill_id=="samurai_isshin": releases=[duration*.65]
	elif skill_id=="gunner_braced_shot": releases=[duration*.72]
	elif skill_id=="ninja_opening_combo": releases=[.42,.80,1.18]
	var reaction: bool=skill_id in ["samurai_parry","spear_brace","monk_ward","commander_rally"]
	if skill_id=="samurai_parry":
		if skill_clock<.55:
			duration=.55; releases=[.25]
		else:
			motion_id="samurai_counter"; skill_clock-=.55; duration=1.05; releases=[duration*.50]; reaction=false
	elif skill_id=="ninja_charge_shrapnel":
		# The upgrade belongs to the planted charge, not a new actor attack.
		motion_id="ninja_timed_charge"
	var impacts: Array=releases.duplicate()
	var committed_count: int=0
	for release in releases:
		if skill_clock>=float(release): committed_count+=1
	var token: String="presentation:%s:%d:%s" % [type_name,int(floor(elapsed/4.8)),skill_id]
	var motion: Dictionary={"skillId":motion_id,"demonstratedSkillId":skill_id,"clock":skill_clock,"duration":duration,"releaseTime":float(releases[0]),"releaseTimes":releases,"releaseIndex":committed_count-1,"releaseCount":committed_count,"impactTimes":impacts,"hitIndex":committed_count-1,"hitCount":committed_count,"committed":committed_count>0,"token":token,"motionToken":token,"reaction":reaction,"presentationOnly":true,"campaignLevel":int(result.campaignLevel),"skillIds":unlocked.duplicate()}
	result.merge({"animation":"idle" if reaction else "attack","animationClock":skill_clock,"attackDuration":duration,"paintedSkillMotion":motion,"skillMeta":{"motionToken":token,"attackId":token,"campaignLevel":int(result.campaignLevel),"skillIds":unlocked.duplicate(),"presentationOnly":true},"previewSkillId":skill_id},true)
	return result

func weapon_socket(actor: Dictionary, friendly: bool, battle: Node2D, release_pose: bool = false) -> Dictionary:
	# Public read-only contract. position is in Battle canvas coordinates;
	# fieldPosition subtracts field_rect.position for the feedback canvas.
	# Missing registration returns {}, never a guessed body-centre muzzle.
	if battle==null: return {}
	bind_battle(battle)
	_render_height=body_height_screen*clampf(float(battle.field_rect.size.y)/620.0,.65,1.5)
	var facing: Vector2=visual_direction(actor,friendly,battle)
	var sample: Dictionary=_sample_animation(actor,friendly,facing)
	if sample.is_empty(): return {}
	var pose: Pose=sample.pose
	if release_pose:
		var animation: Dictionary=_animation(str(actor.get("type",actor.get("kind","spear"))),friendly,str(sample.requestedDirection),"attack")
		var index: int=int(animation.get("releaseFrame",-1))
		if index<0 or index>=animation.get("frames",[]).size(): return {}
		pose=animation.frames[index]
	if not pose.landmarks.has("weaponOrigin") or not pose.landmarks.has("weaponTip"): return {}
	var origin: Vector2=pose.landmarks.weaponOrigin
	var tip: Vector2=pose.landmarks.weaponTip
	var position: Vector2=battle._screen(_position(actor))+actor_visual_offset(actor,_render_height)+(origin-pose.anchor+pose.offset)*(_render_height/pose.body_height)
	return {"position":position,"fieldPosition":position-battle.field_rect.position,"direction":(tip-origin).normalized(),"targetDirection":facing.normalized(),"registered":true,"sourceTexture":pose.texture_path,"requestedDirection":sample.requestedDirection,"sourceDirection":sample.sourceDirection,"releaseEventId":sample.releaseEventId,"releasePose":release_pose}

func actor_visual_offset(actor: Dictionary, height: float) -> Vector2:
	if fortification_pose==null or not bool(actor.get("fortification",false)) or not bool(actor.get("stationaryEnemy",false)) or bool(actor.get("ingressActive",false)): return Vector2.ZERO
	var cover_scale: float = fortification_height_screen*(height/body_height_screen)/fortification_pose.body_height
	return fortification_crew_offset*cover_scale

func draw_production_previews(canvas: CanvasItem, field_rect: Rect2, snapshots: Array, mirrored: bool = false) -> Dictionary:
	# The producer owns time, pause, cancellation and the positions. These
	# ephemeral samples never enter actor/selection/collision/target lists.
	var height: float=body_height_screen*clampf(field_rect.size.y/620.0,.65,1.5)
	var drawn: int=0
	var jobs: Array=[]
	var preview_poses: Dictionary={}
	for value in snapshots:
		if not value is Dictionary: continue
		var job: Dictionary=value
		var progress: float=clampf(float(job.get("progress",job.get("progress01",0.0))),0.0,1.0)
		if progress>=1.0 or bool(job.get("cancelled",false)): continue
		var friendly: bool=bool(job.get("friendly",true))
		var facing: Vector2=Vector2(2,-1) if friendly else Vector2(-2,1)
		if mirrored: facing.x=-facing.x
		var type_name: String=str(job.get("type","spear"))
		var direction: String=_direction_name(facing,friendly)
		var pose_key: String=("friendly/" if friendly else "enemy/")+type_name+"/"+direction
		if not preview_poses.has(pose_key): preview_poses[pose_key]=_pose(_animation(type_name,friendly,direction,"idle"),"idle",0.0,0.0)
		var pose: Pose=preview_poses[pose_key]
		if pose==null: continue
		var scale_value: float=height/pose.body_height
		var preview_tint: Color=pose.tint
		preview_tint.a*=.36
		var positions: Variant=job.get("memberPositions",job.get("positions",[]))
		if not positions is Array: continue
		for raw_point in positions:
			var point: Vector2=Vector2(-1,-1)
			if raw_point is Vector2: point=raw_point
			elif raw_point is Dictionary: point=Vector2(float(raw_point.get("x",-1)),float(raw_point.get("y",-1)))
			if not point.is_finite() or not Rect2(0,0,1,1).has_point(point): continue
			if mirrored: point.x=1.0-point.x
			var foot: Vector2=field_rect.position+point*field_rect.size
			# Every production ghost is the same idle frame, with no hit, death,
			# attack clock or contact tracking. Share the immutable source pose.
			canvas.draw_set_transform(foot,0.0,Vector2.ONE*scale_value)
			canvas.draw_texture_rect_region(pose.texture,Rect2(-pose.anchor+pose.offset,pose.region.size),pose.region,preview_tint,false,true)
			canvas.draw_set_transform(Vector2.ZERO)
			drawn+=1
			var width: float=height*.72
			var top: float=foot.y+(-pose.anchor.y+pose.offset.y)*scale_value
			var center: Vector2=Vector2(clampf(foot.x,field_rect.position.x+width*.5+3,field_rect.end.x-width*.5-3),clampf(top-7,field_rect.position.y+5,field_rect.end.y-5))
			var bar: Rect2=Rect2(center-Vector2(width*.5,2.5),Vector2(width,5))
			canvas.draw_style_box(_production_bar_style(),bar.grow(1))
			var colour: Color=Color("71b6d0") if friendly else Color("c47d6e")
			canvas.draw_rect(Rect2(bar.position,Vector2(width*progress,bar.size.y)),colour)
			# Position comes ONLY from actual progress; pause cannot animate it.
			canvas.draw_circle(Vector2(bar.position.x+width*progress,bar.get_center().y),2.0,colour.lightened(.35),true,-1.0,true)
		jobs.append(int(job.get("jobId",-1)))
	return {"drawn":drawn,"jobIds":jobs,"clockSource":"producer snapshot progress only","positionSource":"memberPositions (actual spawn reservation)","gameplayWrites":false}

var _production_style: StyleBoxFlat

func _production_bar_style() -> StyleBoxFlat:
	if _production_style==null:
		_production_style=StyleBoxFlat.new()
		_production_style.bg_color=Color(.055,.065,.065,.80)
		_production_style.border_color=Color(.64,.64,.51,.75)
		_production_style.set_border_width_all(1)
		_production_style.set_corner_radius_all(2)
	return _production_style

func _rig_part(canvas: CanvasItem, rig: Dictionary, name: String, start: Vector2, rotation_value: float, scale_value: float, tint: Color) -> void:
	var part: Dictionary=rig.parts[name]
	canvas.draw_set_transform(start,rotation_value,Vector2.ONE*scale_value)
	canvas.draw_mesh(part.mesh,rig.texture,Transform2D.IDENTITY,tint)
	canvas.draw_set_transform(Vector2.ZERO)

func _rig_bone(canvas: CanvasItem, rig: Dictionary, name: String, start: Vector2, end: Vector2, tint: Color) -> void:
	var part: Dictionary=rig.parts[name]
	# Map BOTH source anchors to the solved joints. The fixed-length IK below
	# normally gives exactly height/bodyHeightPixels here, with no enlargement.
	_rig_part(canvas,rig,name,start,(end-start).angle()-float(part.restAngle),(end-start).length()/maxf(.001,float(part.restLength)),tint)

func _rig_stance_fraction(rig: Dictionary) -> float:
	if rig.has("walkSoles"): return clampf(float(rig.get("locomotion",{}).get("stanceFraction",.62)),.55,.70)
	return clampf(float(rig.get("stanceFraction",.60)),.30,.65)

func _rig_foot_rotation(rig: Dictionary, phase: float, forward: Vector2, weight: float = 1.0) -> float:
	var stance: float=_rig_stance_fraction(rig)
	var swing_curve: float=sin(clampf((phase-stance)/(1.0-stance),0.0,1.0)*PI) if phase>=stance else 0.0
	if rig.has("walkSoles"):
		return swing_curve*swing_curve*float(rig.get("locomotion",{}).get("footRotationRadians",.06))*signf(forward.x)*weight
	if bool(rig.get("smoothSwingTrajectory",false)): swing_curve*=swing_curve
	return swing_curve*float(rig.get("swingFootRotation",.08))*signf(forward.x)

func _rig_ankle(rig: Dictionary, name: String, sole: Vector2, phase: float, forward: Vector2, scale_value: float, weight: float = 1.0) -> Vector2:
	var foot: Dictionary=rig.parts[name+"Foot"]
	return sole-foot.restVector.rotated(_rig_foot_rotation(rig,phase,forward,weight))*scale_value

func _rig_lengths(rig: Dictionary, name: String, scale_value: float) -> Vector2:
	return rig.boneLengths[name]*scale_value

func _rig_pelvis_correction(rig: Dictionary, hips: Dictionary, feet: Dictionary, phases: Dictionary, forward: Vector2, scale_value: float) -> float:
	# Solve the smallest vertical translation that lets the ORIGINAL bones
	# reach the actual planted ankles. No constant crouch or enlarged limbs.
	var correction: float=0.0
	for name in rig.get("legNames",["left","right"]):
		var lengths: Vector2=_rig_lengths(rig,name,scale_value)
		var radius: float=maxf(.001,lengths.x+lengths.y-.0001)
		var ankle: Vector2=_rig_ankle(rig,name,feet[name],float(phases[name]),forward,scale_value)
		var offset: Vector2=ankle-hips[name]
		var vertical_reach: float=sqrt(maxf(0.0,radius*radius-offset.x*offset.x))
		correction=maxf(correction,offset.y-vertical_reach)
	return correction

func _rig_bone_transform(rig: Dictionary, name: String, start: Vector2, end: Vector2) -> Transform2D:
	var part: Dictionary=rig.parts[name]
	var rotation_value: float=(end-start).angle()-float(part.restAngle)
	var scale_value: float=(end-start).length()/maxf(.001,float(part.restLength))
	return Transform2D(rotation_value,Vector2.ONE*scale_value,0.0,start)

func _prepare_rig_leg(rig: Dictionary, name: String, hip: Vector2, sole: Vector2, phase: float, forward: Vector2, height: float, commands: Array[Transform2D], weight: float = 1.0) -> Dictionary:
	var foot: Dictionary=rig.parts[name+"Foot"]
	var foot_scale: float=height/float(rig.bodyHeightPixels)
	var airborne: bool=phase>=_rig_stance_fraction(rig)
	var rotation_value: float=_rig_foot_rotation(rig,phase,forward,weight)
	var ankle: Vector2=_rig_ankle(rig,name,sole,phase,forward,foot_scale,weight)
	var lengths: Vector2=_rig_lengths(rig,name,foot_scale)
	var upper: float=lengths.x
	var lower: float=lengths.y
	var offset: Vector2=ankle-hip
	var axis: Vector2=offset.normalized() if offset.length_squared()>.000001 else Vector2.DOWN
	var distance: float=clampf(offset.length(),absf(upper-lower)+.0001,upper+lower-.0001)
	var requested_sole: Vector2=sole
	# Defensive discontinuity handling must move the endpoint as well as the
	# scalar. Otherwise shin and foot are drawn at two different ankles.
	ankle=hip+axis*distance
	sole=ankle+(foot.end-foot.start).rotated(rotation_value)*foot_scale
	var along: float=(upper*upper-lower*lower+distance*distance)/(2.0*distance)
	var across: float=sqrt(maxf(0.0,upper*upper-along*along))
	var knee: Vector2=hip+axis*along+Vector2(axis.y,-axis.x)*across*float(rig.kneeBendSigns[name])
	commands.append(_rig_bone_transform(rig,name+"Thigh",hip,knee))
	commands.append(_rig_bone_transform(rig,name+"Shin",knee,ankle))
	commands.append(Transform2D(rotation_value,Vector2.ONE*foot_scale,0.0,ankle))
	if not capture_rig_diagnostics: return {"sole":sole}
	return {"hip":hip,"knee":knee,"ankle":ankle,"sole":sole,"requestedSole":requested_sole,"endpointCorrection":sole.distance_to(requested_sole),"upperLength":upper,"lowerLength":lower,"upperLengthError":absf(hip.distance_to(knee)-upper),"lowerLengthError":absf(knee.distance_to(ankle)-lower),"contact":not airborne,"phase":phase}

func _prepare_uv_rig(rig: Dictionary, actor: Dictionary, friendly: bool, screen_foot: Vector2, phase: float, moving: bool, height: float, view_direction: Vector2, allow_torso_gait: bool = true) -> Dictionary:
	# A walking reaction must not change the foot solver under its distance
	# clock. SkillMotion may own the upper body without replacing these legs.
	if rig.has("walkSoles") and str(actor.get("animation","idle")) in ["walk","idle"]:
		return _prepare_biped_rig(rig,actor,friendly,screen_foot,phase,moving,height,view_direction,allow_torso_gait)
	return _prepare_legacy_uv_rig(rig,actor,friendly,screen_foot,phase,moving,height,view_direction)

func _prepare_biped_rig(rig: Dictionary, actor: Dictionary, friendly: bool, screen_foot: Vector2, phase: float, moving: bool, height: float, view_direction: Vector2, allow_torso_gait: bool = true) -> Dictionary:
	var key: String=_actor_key(actor,friendly)
	var preview: bool=bool(actor.get("preview",false))
	var track: Dictionary={} if preview else _motion_tracks.get(key,{})
	var blend: float=(1.0 if moving else 0.0) if preview else float(track.get("gaitBlend",0.0))
	var state: String=str(actor.get("animation","idle"))
	# Actual attacks/hits/death retain their existing owner. We keep the cycle
	# clock through them, but never layer a gait over a committed attack pose.
	if state not in ["walk","idle"]: blend=0.0
	var forward: Vector2=track.get("gaitForward",view_direction)
	if blend<=0.0: forward=view_direction
	if forward.length_squared()<.000001: forward=Vector2(1,-.5)
	var projection: Vector2=_walk_projection(forward)
	var scale_value: float=height/float(rig.bodyHeightPixels)
	var source_cycle: float=float(track.sourceCycleBodyHeights) if str(track.get("sourceRig",""))==str(rig.registrationKey) and blend>0.0 else _walk_cycle_stride(rig,forward)
	var stride: float=source_cycle*height
	var profile: Dictionary=rig.get("locomotion",{})
	var stance_fraction: float=_rig_stance_fraction(rig)
	var walking: bool=moving and (preview or float(track.get("speedBodyHeightsPerSecond",0.0))>.000001)
	var battle: Node2D=null if preview else _battle_ref()
	var contacts: bool=battle!=null and int(actor.get("id",-1))>=0
	var point: Vector2=_position(actor)
	var feet: Dictionary={}
	var phases: Dictionary={}
	var travel_values: Dictionary={}
	var cycles: float=phase if preview else float(track.get("cycles",phase))
	var pivot_releases: int=0
	for name in rig.legNames:
		var phase_offset: float=float(rig.get("phaseOffsets",{"left":0.0,"right":.5}).get(name,0.0))
		var p: float=fposmod(phase+phase_offset,1.0)
		phases[name]=p
		var travel: float=(stance_fraction*.5-p)*stride
		var lift: float=0.0
		if p>=stance_fraction:
			var swing: float=(p-stance_fraction)/(1.0-stance_fraction)
			# Cubic Hermite endpoints have the SAME -stride derivative as the
			# planted contact. Squared sine clears toes with zero endpoint speed.
			travel=lerpf(-stance_fraction*.5*stride,stance_fraction*.5*stride,smoothstep(0.0,1.0,swing))-(1.0-stance_fraction)*stride*(2.0*swing*swing*swing-3.0*swing*swing+swing)
			lift=pow(sin(swing*PI),2.0)*height*float(profile.get("clearanceBodyHeights",.025))
		travel_values[name]=travel
		var rest: Vector2=screen_foot+rig.neutralOffsets[name]*scale_value
		var tread: Vector2=screen_foot+(rig.walkSoles[name]-rig.anchorPoint)*scale_value+projection*travel-Vector2(0,lift)
		feet[name]=rest.lerp(tread,smoothstep(0.0,1.0,blend))
		if contacts:
			var contact_key: String=key+"/"+str(name)
			var previous: Dictionary=_contact_tracks.get(contact_key,{})
			if str(previous.get("solver",""))!="biped" or not previous.has("drawnPoint") or not previous.has("drawnOffset"): previous={}
			var stance: bool=walking and p<stance_fraction
			var cycle: int=int(floor(cycles+phase_offset))
			if not walking and blend>0.0 and not previous.is_empty():
				if bool(previous.get("moving",false)):
					previous["settlePoint"]=previous.get("drawnPoint",point)
					previous["settleOffset"]=previous.get("drawnOffset",Vector2.ZERO)
					previous["settleBlend"]=maxf(blend,float(previous.get("blend",blend)))
				if previous.has("settlePoint") and previous.has("settleOffset") and previous.has("settleBlend"):
					var start: Vector2=battle._screen(previous.settlePoint)+previous.settleOffset*height
					feet[name]=rest.lerp(start,clampf(blend/maxf(.001,float(previous.settleBlend)),0.0,1.0))
			elif stance:
				# Keep the physical planted point across view switches, pause and
				# resize. The offset is body-height based, never stretched by aspect.
				var retain_plant: bool=bool(previous.get("stance",false)) and int(previous.get("cycle",cycle))==cycle and previous.has("plantPoint") and previous.has("plantOffset")
				if retain_plant:
					var planted: Vector2=battle._screen(previous.plantPoint)+previous.plantOffset*height
					var hip: Vector2=screen_foot+(rig.parts[name+"Thigh"].start-rig.anchorPoint)*scale_value
					var ankle: Vector2=planted-rig.parts[name+"Foot"].restVector*scale_value
					var reach: float=float(rig.walkReach[name])*scale_value
					var offset: Vector2=ankle-hip
					var required_drop: float=offset.y-sqrt(maxf(0.0,reach*reach-offset.x*offset.x))
					retain_plant=absf(offset.x)<=reach and required_drop<=height*float(profile.get("maximumPelvisDropBodyHeights",.085))
					if retain_plant: feet[name]=planted
					else: pivot_releases+=1
				if not retain_plant:
					# A new painted view can have different depth/anchor. Release an
					# unreachable old contact BEFORE IK, rather than stretching it or
					# letting the defensive endpoint clamp drag a planted shoe.
					previous["plantPoint"]=point
					previous["plantOffset"]=(feet[name]-battle._screen(point))/height
			previous.merge({"solver":"biped","stance":stance,"cycle":cycle,"moving":walking,"blend":blend,"phase":p,"rig":rig.registrationKey,"drawnPoint":point,"drawnOffset":(feet[name]-battle._screen(point))/height},true)
			_contact_tracks[contact_key]=previous
	var support: float=(float(travel_values[rig.legNames[0]])-float(travel_values[rig.legNames[1]]))/maxf(.001,stride)
	var lean: float=float(profile.get("forwardLeanRadians",.012))*signf(forward.x)*blend if allow_torso_gait else 0.0
	# Shoulder/held-arm/weapon counterrotation is one coherent painted island
	# around the anatomical pelvis. No free-arm mask or detached weapon grip.
	var shoulder: float=-support*float(profile.get("shoulderCounterRadians",.025))*blend if allow_torso_gait else 0.0
	var pelvis: Vector2=screen_foot+(rig.pelvis-rig.anchorPoint)*scale_value
	var hips: Dictionary={}
	for name in rig.legNames: hips[name]=pelvis+rig.hipOffsets[name]*scale_value
	var correction: float=0.0
	for name in rig.legNames:
		var ankle: Vector2=_rig_ankle(rig,name,feet[name],float(phases[name]) if blend>0.0 else 0.0,forward,scale_value,blend)
		var offset: Vector2=ankle-hips[name]
		var lengths: Vector2=rig.boneLengths[name]*scale_value
		var radius: float=lerpf(lengths.x+lengths.y-.0001,float(rig.walkReach[name])*scale_value,blend)
		correction=maxf(correction,offset.y-sqrt(maxf(0.0,radius*radius-offset.x*offset.x)))
	var maximum_drop: float=height*float(profile.get("maximumPelvisDropBodyHeights",.085))
	correction=clampf(correction,0.0,maximum_drop)
	pelvis.y+=correction
	for name in hips: hips[name]=pelvis+rig.hipOffsets[name]*scale_value
	var order: Array=rig.drawOrder
	if feet[order[0]].y>feet[order[1]].y:
		order=order.duplicate(); order.reverse()
	var commands: Array[Transform2D]=[]
	var result: Dictionary={}
	for name in order:
		var leg: Dictionary=_prepare_rig_leg(rig,str(name),hips[name],feet[name],float(phases[name]) if blend>0.0 else 0.0,forward,height,commands,blend)
		if contacts:
			var foot_track: Dictionary=_contact_tracks[key+"/"+str(name)]
			foot_track["drawnOffset"]=(leg.sole-battle._screen(point))/height
		if capture_rig_diagnostics: result[name]=leg
	# Preserve the existing hit recoil on the upper island. It must not drag
	# planted feet sideways or force the legacy stride during an ongoing walk.
	var reaction: float=sin(clampf(float(actor.get("hitClock",0.0))/.18,0.0,1.0)*PI)
	var reaction_sign: float=signf(view_direction.x)
	lean-=reaction_sign*.06*reaction
	var torso_origin: Vector2=pelvis+Vector2(-reaction_sign*height*.014*reaction,0)
	var prepared: Dictionary={"commands":commands,"legOrder":order,"pelvis":pelvis,"torsoOrigin":torso_origin,"anchor":rig.anchorPoint,"lean":lean+shoulder,"forward":forward if allow_torso_gait else view_direction,"torsoTransform":Transform2D(lean+shoulder,Vector2.ONE*scale_value,0.0,torso_origin),"diagnostics":result}
	if capture_rig_diagnostics:
		result.merge({"pelvis":pelvis,"pelvisReachCorrection":correction,"maximumPelvisCorrection":maximum_drop,"pivotContactReleases":pivot_releases,"gaitBlend":blend,"stanceFraction":stance_fraction,"sourceCycleBodyHeights":stride/height,"projectedCycleBodyHeights":stride*projection.length()/height,"travelDirection":forward,"bothFeetAirborne":walking and float(phases[rig.legNames[0]])>=stance_fraction and float(phases[rig.legNames[1]])>=stance_fraction,"torsoCounterRadians":shoulder,"motionMeasurement":track.duplicate(false)},true)
	return prepared

func _prepare_legacy_uv_rig(rig: Dictionary, actor: Dictionary, friendly: bool, screen_foot: Vector2, phase: float, moving: bool, height: float, view_direction: Vector2) -> Dictionary:
	var forward: Vector2=view_direction.normalized() if view_direction.length_squared()>.000001 else Vector2(2,-1).normalized()
	var scale_value: float=height/float(rig.bodyHeightPixels)
	var anchor: Vector2=rig.anchorPoint
	var pelvis: Vector2=screen_foot+(rig.pelvis-anchor)*scale_value
	var torso_lean: float=float(rig.get("forwardLeanRadians",0.0))*signf(forward.x) if moving else 0.0
	var stance_fraction: float=_rig_stance_fraction(rig)
	var feet: Dictionary={}
	var hips: Dictionary={}
	var phases: Dictionary={}
	var battle: Node2D=_battle_ref()
	var track_contacts: bool=battle!=null and not bool(actor.get("preview",false)) and int(actor.get("id",-1))>=0
	var actor_key: String=_actor_key(actor,friendly)
	var actor_point: Vector2=_position(actor)
	var actor_screen: Vector2=Vector2.ZERO
	var actor_screen_ready: bool=false
	for leg_name in rig.legNames:
		phases[leg_name]=fposmod(phase+float(rig.get("phaseOffsets",{"left":0.0,"right":.5}).get(leg_name,0.0)),1.0) if moving else 0.0
	var state: String=str(actor.get("animation","idle"))
	var reaction: float=sin(clampf(float(actor.get("hitClock",0.0))/.18,0.0,1.0)*PI)
	if state=="hit": reaction=sin(clampf(float(actor.get("animationClock",0.0))/.18,0.0,1.0)*PI)
	var collapse: float=smoothstep(0.0,1.0,clampf(float(actor.get("animationClock",0.0))/.65,0.0,1.0)) if state=="death" else 0.0
	var strike: float=sin(clampf(float(actor.get("animationClock",0.0))/maxf(.1,float(actor.get("attackDuration",.6))),0.0,1.0)*PI) if state=="attack" else 0.0
	torso_lean+=signf(forward.x)*(-.06*reaction+.23*collapse+.08*strike)
	pelvis+=forward*height*.025*strike
	pelvis+=Vector2(-signf(forward.x)*height*.014*reaction,height*.10*collapse)
	for name in rig.legNames:
		var lateral: Vector2=rig.neutralOffsets[name]*scale_value
		var p: float=float(phases[name])
		var travel: float=0.0
		var lift: float=0.0
		if moving:
			var stride: float=height*float(rig.get("strideBodyHeights",.60))
			# During contact, d(relative foot)/d(phase) == -stride.
			# Since phase advances by rootDistance/stride, the world foot stays
			# planted at every speed. The shorter contact creates a jog flight.
			if p<stance_fraction: travel=(stance_fraction*.5-p)*stride
			else:
				var swing: float=(p-stance_fraction)/(1.0-stance_fraction)
				travel=lerpf(-stance_fraction*.5*stride,stance_fraction*.5*stride,smoothstep(0.0,1.0,swing))
				lift=sin(swing*PI)*height*float(rig.get("swingLiftBodyHeights",.055))
				if bool(rig.get("smoothSwingTrajectory",false)):
					# Match the planted foot derivative at toe-off and touchdown.
					# Metadata enables this only for the registered enemy walk.
					travel-=(1.0-stance_fraction)*stride*(2.0*swing*swing*swing-3.0*swing*swing+swing)
					lift*=sin(swing*PI)
		feet[name]=screen_foot+lateral+forward*travel-Vector2(0,lift)
		hips[name]=pelvis+rig.hipOffsets[name].rotated(torso_lean)*scale_value
		if track_contacts:
			var key: String=actor_key+"/"+name
			var previous: Dictionary=_contact_tracks.get(key,{})
			if str(previous.get("solver",""))!="legacy" or not previous.has("point") or not previous.has("offset"): previous={}
			var stance: bool=not moving or p<stance_fraction
			var new_contact: bool=previous.is_empty() or not bool(previous.get("stance",false)) or p<float(previous.get("phase",p)) or moving!=bool(previous.get("moving",moving)) or str(previous.get("rig",""))!=str(rig.registrationKey) or forward.dot(previous.get("forward",forward))<.75
			if moving and stance and not new_contact:
				feet[name]=battle._screen(previous.point)+previous.offset*battle.field_rect.size
			else:
				if not actor_screen_ready:
					actor_screen=battle._screen(actor_point)
					actor_screen_ready=true
				previous={"point":actor_point,"offset":(feet[name]-actor_screen)/battle.field_rect.size}
			previous["solver"]="legacy"; previous["stance"]=stance; previous["phase"]=p; previous["moving"]=moving; previous["rig"]=rig.registrationKey; previous["forward"]=forward
			_contact_tracks[key]=previous
	var pelvis_correction: float=_rig_pelvis_correction(rig,hips,feet,phases,forward,scale_value)
	pelvis.y+=pelvis_correction
	for name in hips:
		var hip: Vector2=hips[name]
		hip.y+=pelvis_correction
		hips[name]=hip
	var result: Dictionary={}
	var commands: Array[Transform2D]=[]
	var leg_order: Array=rig.drawOrder
	if bool(rig.get("dynamicLegDepth",false)) and leg_order.size()==2:
		if feet[leg_order[0]].y>feet[leg_order[1]].y:
			leg_order=leg_order.duplicate()
			leg_order.reverse()
	for name in leg_order:
		var leg_result: Dictionary=_prepare_rig_leg(rig,str(name),hips[name],feet[name],float(phases[name]) if moving else 0.0,forward,height,commands)
		if capture_rig_diagnostics: result[name]=leg_result
	var prepared: Dictionary={"commands":commands,"legOrder":leg_order,"pelvis":pelvis,"anchor":anchor,"lean":torso_lean,"forward":forward,"torsoTransform":Transform2D(torso_lean,Vector2.ONE*scale_value,0.0,pelvis),"diagnostics":result}
	if not capture_rig_diagnostics: return prepared
	result["pelvis"]=pelvis
	result["pelvisReachCorrection"]=pelvis_correction
	result["stanceFraction"]=stance_fraction
	result["strideBodyHeights"]=float(rig.get("strideBodyHeights",.60))
	result["torsoLeanRadians"]=torso_lean
	result["bothFeetAirborne"]=moving and phase>=stance_fraction and fposmod(phase+.5,1.0)>=stance_fraction
	result["motionMeasurement"]=_motion_tracks.get(_actor_key(actor,friendly),{}).duplicate(false) if not bool(actor.get("preview",false)) else {"source":"explicit preview distance; natural speed not measured"}
	return prepared

func _draw_prepared_rig(canvas: CanvasItem, rig: Dictionary, prepared: Dictionary, height: float, tint: Color, skill_data: Dictionary, actor_key: String, mounted: bool) -> void:
	var commands: Array[Transform2D]=prepared.commands
	var index: int=0
	# The caller may leave a shadow transform. Keep the canvas transform at
	# identity and attach the same prepared transform directly to each mesh.
	canvas.draw_set_transform(Vector2.ZERO)
	for leg_name in prepared.legOrder:
		for part_name in rig.legPartNames[leg_name]:
			canvas.draw_mesh(rig.parts[part_name].mesh,rig.texture,commands[index],tint)
			index+=1
	var torso: Dictionary=rig.parts.torso
	var torso_origin: Vector2=prepared.get("torsoOrigin",prepared.pelvis)
	if not skill_motion.draw(canvas,rig.texture,rig.region,prepared.anchor,torso.start,torso.polygon,torso_origin,height,float(rig.bodyHeightPixels),tint,skill_data,actor_key+"/rig",prepared.forward,mounted,float(prepared.lean),str(torso.skillGeometryKey)):
		canvas.draw_mesh(torso.mesh,rig.texture,prepared.torsoTransform,tint)

func _prepare_actor_frame(actor: Dictionary, screen_foot: Vector2, friendly: bool, height: float, view_direction: Vector2) -> Dictionary:
	_stage_release_presentation(actor,friendly)
	var displayed_release: Dictionary=_receipt_for(actor,friendly)
	var sample: Dictionary = _sample_animation(actor,friendly,view_direction)
	if sample.is_empty(): return {}
	var state: String = str(sample.renderState)
	var clock: float = maxf(0.0,float(actor.get("animationClock",0.0)))
	var pose: Pose = sample.pose
	var target_height: float = height if height>0 else body_height_screen
	var scale_value: float = target_height/pose.body_height
	var rotation_value: float = 0.0
	var tint: Color = pose.tint
	tint.a*=clampf(float(actor.get("presentationAlpha",1.0)),0.0,1.0)
	var custom_state: bool = bool(sample.authoredState)
	# Limb/body lift belongs to the authored gait. A generic sine or a rotated
	# idle image must not masquerade as an authored walk/attack.
	if state=="death":
		var progress: float = clampf(clock/.65,0,1)
		if not custom_state: rotation_value = (1.0 if friendly else -1.0)*progress*.42
		tint.a *= 1.0-smoothstep(.35,1.0,progress)
	if float(actor.get("hitClock",0.0))>0:
		tint = tint.lerp(Color(1.0,.91,.83,tint.a),.14)
	if bool(actor.get("consumed",false)):
		tint.a *= clampf(float(actor.get("departureAlpha",1.0)),0,1)
	var body_foot: Vector2 = screen_foot+actor_visual_offset(actor,target_height)
	var motion_actor: Dictionary=actor
	var motion_battle: Node2D=null if bool(actor.get("preview",false)) else _battle_ref()
	if bool(displayed_release.get("forceReleaseFrame",false)) and str(actor.get("animation","")) not in ["death","hit"]:
		motion_actor=actor.duplicate(false)
		motion_actor["animation"]="attack"
		if motion_battle!=null: motion_actor["animationClock"]=maxf(0.0,float(motion_battle.elapsed)-float(displayed_release.cycleStart))
	var skill_data: Dictionary=skill_motion.request(motion_actor,friendly,motion_battle)
	var matching_motion: bool=str(skill_data.get("skillId",""))==str(displayed_release.get("skillId","")) or (str(skill_data.get("skillId",""))=="samurai_counter" and str(displayed_release.get("skillId",""))=="samurai_parry" and str(displayed_release.get("effectKind",""))=="counter")
	if bool(displayed_release.get("forceReleaseFrame",false)) and not skill_data.is_empty() and str(skill_data.get("motionToken",skill_data.get("token","")))==str(displayed_release.get("motionToken","")) and matching_motion:
		skill_data=skill_data.duplicate(false)
		skill_data["clock"]=float(displayed_release.scheduledRelease)
		skill_data["releaseIndex"]=int(displayed_release.releaseIndex)
		skill_data["releaseCount"]=int(displayed_release.releaseIndex)+1
		skill_data["committed"]=true
		skill_data["displayReleaseEventId"]=int(displayed_release.eventId)
		skill_data["displayReleaseIndex"]=int(displayed_release.releaseIndex)
		if int(displayed_release.get("hitIndex",-1))>=0:
			skill_data["hitIndex"]=int(displayed_release.hitIndex)
			skill_data["hitCount"]=int(displayed_release.hitIndex)+1
	if not skill_data.is_empty():
		sample["_skillMotionId"]=str(skill_data.skillId)
	var mounted: bool=str(actor.get("type",""))=="commander"
	skill_data=skill_motion.prepare_draw(skill_data,view_direction,mounted)
	var prepared: Dictionary={"actor":actor,"foot":screen_foot,"direction":view_direction,"height":target_height,"stateStamp":str(actor.get("animation","idle")),"clockStamp":float(actor.get("animationClock",0.0)),"hitStamp":float(actor.get("hitClock",0.0)),"alphaStamp":float(actor.get("presentationAlpha",1.0)),"departureStamp":float(actor.get("departureAlpha",1.0)),"consumedStamp":bool(actor.get("consumed",false)),"captureStamp":capture_rig_diagnostics,"pose":pose,"bodyFoot":body_foot,"scale":scale_value,"rotation":rotation_value,"tint":tint,"skillData":skill_data,"mounted":mounted,"rig":{},"rigPose":{},"sample":sample,"cover":bool(actor.get("fortification",false)) and bool(actor.get("stationaryEnemy",false)) and not bool(actor.get("ingressActive",false))}
	var rig_key: String=("friendly/" if friendly else "enemy/")+_role(str(actor.get("type",actor.get("kind","spear"))))+"/"+str(sample.requestedDirection)
	if not rigs.has(rig_key):
		rig_key=("friendly/" if friendly else "enemy/")+_role(str(actor.get("type",actor.get("kind","spear"))))+"/"+str(sample.sourceDirection)
	var idle_transition: bool=state=="idle" and rigs.get(rig_key,{}).has("walkSoles") and float(_motion_tracks.get(_actor_key(actor,friendly),{}).get("gaitBlend",0.0))>0.0
	var grounded_idle: bool=state=="idle" and (bool(rigs.get(rig_key,{}).get("groundedIdle",false)) or idle_transition)
	if (state in ["walk","hit","death"] or (state=="attack" and not bool(sample.authoredState)) or (state=="idle" and float(actor.get("hitClock",0.0))>0.0) or grounded_idle) and rigs.has(rig_key):
		var rig: Dictionary=rigs[rig_key]
		var display_actor: Dictionary=actor
		if bool(displayed_release.get("forceReleaseFrame",false)):
			display_actor=actor.duplicate(false)
			display_actor["animation"]=state
			display_actor["animationClock"]=float(displayed_release.scheduledRelease)
		var rig_pose: Dictionary=_prepare_uv_rig(rig,display_actor,friendly,body_foot,float(sample.walkPhase),state=="walk",target_height,view_direction,skill_data.is_empty())
		prepared["rig"]=rig; prepared["rigPose"]=rig_pose
		sample["_rig"]=rig
		if capture_rig_diagnostics: sample["_rigJoints"]=rig_pose.diagnostics
	return prepared

func _actor_frame_matches(prepared: Dictionary, actor: Dictionary, screen_foot: Vector2, height: float, direction: Vector2) -> bool:
	return not prepared.is_empty() and is_same(prepared.actor,actor) and prepared.foot==screen_foot and float(prepared.height)==height and prepared.direction==direction and str(prepared.stateStamp)==str(actor.get("animation","idle")) and float(prepared.clockStamp)==float(actor.get("animationClock",0.0)) and float(prepared.hitStamp)==float(actor.get("hitClock",0.0)) and float(prepared.alphaStamp)==float(actor.get("presentationAlpha",1.0)) and float(prepared.departureStamp)==float(actor.get("departureAlpha",1.0)) and bool(prepared.consumedStamp)==bool(actor.get("consumed",false)) and bool(prepared.captureStamp)==capture_rig_diagnostics

func draw_actor(canvas: CanvasItem, actor: Dictionary, screen_foot: Vector2, friendly: bool, height: float = -1.0, view_direction: Vector2 = Vector2.ZERO, contact_shadow: bool = false) -> bool:
	if not screen_foot.is_finite(): return false
	var battle: Node2D=null if bool(actor.get("preview",false)) else _battle_ref()
	var cacheable: bool=battle!=null and int(actor.get("id",-1))>=0
	if battle!=null: _ensure_display_frame(battle)
	var key: String=_actor_key(actor,friendly)
	var target_height: float=height if height>0 else body_height_screen
	var prepared: Dictionary=_frame_actors.get(key,{}) if cacheable else {}
	if not _actor_frame_matches(prepared,actor,screen_foot,target_height,view_direction):
		prepared=_prepare_actor_frame(actor,screen_foot,friendly,target_height,view_direction)
		if prepared.is_empty(): return false
		if cacheable: _frame_actors[key]=prepared
	if int(actor.get("id",-1))>=0:
		# Once published, callers can retain the Dictionary itself. Keep that
		# live reference populated on later draws just as the old field was.
		if _actor_samples_observed: _actor_samples[key]=_expand_animation_sample(prepared.sample)
		else: _pending_actor_samples[key]=prepared.sample
	var tint: Color=prepared.tint
	var body_foot: Vector2=prepared.bodyFoot
	var pose: Pose=prepared.pose
	var skill_data: Dictionary=prepared.skillData
	if bool(prepared.cover):
		if fortification_pose!=null:
			var cover_scale: float=fortification_height_screen*(target_height/body_height_screen)/fortification_pose.body_height
			var cover_tint: Color=fortification_pose.tint
			cover_tint.a*=tint.a
			canvas.draw_set_transform(screen_foot,0.0,Vector2.ONE*cover_scale)
			canvas.draw_texture_rect_region(fortification_pose.texture,Rect2(-fortification_pose.anchor+fortification_pose.offset,fortification_pose.region.size),fortification_pose.region,cover_tint,false,true)
			last_structure_count+=1
		else: missing_structure_asset=true
	if contact_shadow:
		canvas.draw_set_transform(body_foot,0.0,Vector2(target_height*.15,target_height*.0325))
		canvas.draw_circle(Vector2.ZERO,1.0,Color(.17,.16,.13,.06*tint.a),true,-1.0,true)
		canvas.draw_circle(Vector2.ZERO,.68,Color(.17,.16,.13,.10*tint.a),true,-1.0,true)
	if not prepared.rig.is_empty():
		_draw_prepared_rig(canvas,prepared.rig,prepared.rigPose,target_height,tint,skill_data,key,bool(prepared.mounted))
		return true
	if not skill_data.is_empty() and skill_motion.draw(canvas,pose.texture,pose.region,pose.anchor,pose.anchor-pose.offset,pose.skill_polygon,body_foot,target_height,pose.body_height,tint,skill_data,key+"/pose",view_direction,bool(prepared.mounted),0.0,pose.skill_geometry_key): return true
	canvas.draw_set_transform(body_foot,float(prepared.rotation),Vector2.ONE*float(prepared.scale))
	canvas.draw_texture_rect_region(pose.texture,Rect2(-pose.anchor+pose.offset,pose.region.size),pose.region,tint,false,true)
	canvas.draw_set_transform(Vector2.ZERO)
	return true

func _visual_target_valid(actor: Dictionary, target: Dictionary, friendly: bool, battle: Node2D) -> bool:
	if target.is_empty() or float(target.get("hp",0))<=0 or bool(target.get("escaped",false)) or bool(target.get("consumed",false)): return false
	var point: Vector2 = _position(target)
	if not Rect2(0,0,1,1).has_point(point): return false
	var distance: float = _position(actor).distance_to(point)
	if friendly:
		var type_name: String = str(actor.get("type",""))
		if type_name=="monk": return false
		var ranged: bool = type_name in ["archer","gunner"]
		var reach: float = float(battle._read_stats(actor).range) if ranged else battle.ground_combat.reach(actor)*1.1
		if distance>reach: return false
		if not battle._enemy_visible(target): return false
		if not battle.ground_combat.primary_target_allowed(actor,target,"prepare"): return false
		if type_name!="archer" and (not battle.ground_combat.shares_contact_front(actor,target) or not battle.ground_combat.land_segment_safe(_position(actor),point)): return false
		return true
	if distance>float(actor.get("attackRange",actor.get("meleeRange",.032)))*1.05: return false
	if not battle.can_enemy_engage_unit(actor,target,true): return false
	return battle.ground_combat.land_segment_safe(_position(actor),point)

func _lookup_target(id: int, friendly: bool, battle: Node2D) -> Dictionary:
	if id<0: return {}
	_ensure_display_frame(battle)
	return _indexed_actor(id,not friendly,battle)

func _visual_facing_candidates(actor: Dictionary, friendly: bool, battle: Node2D) -> Array:
	var roster: Array=battle.enemies if friendly else battle.units
	# Normal draws run after a completed simulation step under a read scope.
	# External/mid-step observers retain the authoritative full-array query.
	if not _spatial_facing_draw or battle.unit_skills.read_query_context().is_empty() or not is_instance_valid(battle.ground_combat): return roster
	var radius: float
	if friendly:
		var type_name: String=str(actor.get("type",""))
		if type_name=="monk": return []
		radius=float(battle._read_stats(actor).range) if type_name in ["archer","gunner"] else battle.ground_combat.reach(actor)*1.1
	else:
		radius=float(actor.get("attackRange",actor.get("meleeRange",.032)))*1.05
	if not is_finite(radius) or radius<0.0: return roster
	battle.ground_combat._ensure_crowd_index()
	# This is the unchanged validity predicate's exact reach, padded only at
	# its floating-point boundary; the original predicate still decides below.
	var candidates: Array=battle.ground_combat.crowd.nearby(_position(actor),radius+.0000001,not friendly)
	var slots: Dictionary=_enemy_slots if friendly else _unit_slots
	for candidate in candidates:
		var id: int=int(candidate.get("id",-1))
		if not slots.has(id) or not is_same(_indexed_actor(id,not friendly,battle),candidate): return roster
	# Spatial cells have their own order. Restore the original first-roster
	# tie behavior, including the order of the remaining validity checks.
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(slots[int(first.id)])<int(slots[int(second.id)]))
	return candidates

func _screen_direction(actor: Dictionary, target_position: Vector2, battle: Node2D, target: Dictionary = {}, facing_key: String = "") -> Vector2:
	if not target.is_empty() and not facing_key.is_empty(): _frame_facing_targets[facing_key]=target
	var origin: Vector2 = battle._screen(_position(actor))+actor_visual_offset(actor,_render_height)
	var destination: Vector2 = battle._screen(target_position)
	if not target.is_empty(): destination+=actor_visual_offset(target,_render_height)
	return destination-origin

func _road_facing(actor: Dictionary, friendly: bool, battle: Node2D) -> Vector2:
	var point: Vector2 = _position(actor)
	var nearest: Vector2 = point
	var lane_direction: Vector2 = Vector2.ZERO
	var best: float = INF
	var path_index: int = int(actor.get("postPathIndex",actor.get("pathIndex",-1)))
	for index in range(battle.paths.size()):
		if path_index>=0 and index!=path_index: continue
		var points: Array = battle.paths[index].points
		for segment in range(points.size()-1):
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(point,points[segment],points[segment+1])
			var distance: float = point.distance_squared_to(candidate)
			if distance<best:
				best=distance; nearest=candidate
				lane_direction=(points[segment]-points[segment+1]) if friendly else (points[segment+1]-points[segment])
	if best>.000001: return _screen_direction(actor,nearest,battle)
	if lane_direction.length_squared()>.000001: return _screen_direction(actor,point+lane_direction.normalized()*.03,battle)
	return Vector2(1,-1) if friendly else Vector2(-1,1)

func visual_direction(actor: Dictionary, friendly: bool, battle: Node2D) -> Vector2:
	_ensure_display_frame(battle)
	var key: String=_actor_key(actor,friendly)
	var point: Vector2=_position(actor)
	var state: String=str(actor.get("animation","idle"))
	var clock: float=float(actor.get("animationClock",0.0))
	var aim: Vector2=actor.get("aim",Vector2(float(actor.get("aimX",0)),float(actor.get("aimY",0))))
	var plan_target: int=int(_attack_plan(actor,friendly).get("targetId",-1))
	var saved: Dictionary=_frame_facing.get(key,{})
	if not saved.is_empty() and is_same(saved.actor,actor) and saved.point==point and str(saved.state)==state and float(saved.clock)==clock and saved.aim==aim and int(saved.planTarget)==plan_target:
		var cached_target: Dictionary=saved.target
		if cached_target.is_empty() or (not bool(cached_target.get("escaped",false)) and not bool(cached_target.get("consumed",false)) and saved.targetPoint==_position(cached_target) and float(saved.targetHp)==float(cached_target.get("hp",0.0)) and is_same(_indexed_actor(int(cached_target.get("id",-1)),not friendly,battle),cached_target)): return saved.direction
	_frame_facing_targets.erase(key)
	var direction: Vector2=_calculate_visual_direction(actor,friendly,battle)
	var resolved_target: Dictionary=_frame_facing_targets.get(key,{})
	_frame_facing[key]={"actor":actor,"point":point,"state":state,"clock":clock,"aim":aim,"direction":direction,"planTarget":plan_target,"target":resolved_target,"targetPoint":_position(resolved_target) if not resolved_target.is_empty() else Vector2.ZERO,"targetHp":float(resolved_target.get("hp",0.0))}
	return direction

func _calculate_visual_direction(actor: Dictionary, friendly: bool, battle: Node2D) -> Vector2:
	var state: String = str(actor.get("animation","idle"))
	var point: Vector2 = _position(actor)
	var aim: Vector2 = actor.get("aim",Vector2(float(actor.get("aimX",0)),float(actor.get("aimY",0))))
	if state in ["walk","death"]: return _screen_direction(actor,point+aim*.03,battle)
	if not friendly and str(actor.get("kind","")) in ["enemy_archer","enemy_gunner"]:
		# The real attack owner also owns its idle/recovery facing. A nearer
		# unrelated ally must not replace the hunter's committed shooter.
		var owned_target: Dictionary=battle.enemy_facing_target(actor)
		if not owned_target.is_empty(): return _screen_direction(actor,_position(owned_target),battle,owned_target,_actor_key(actor,friendly))
		if state=="idle": return _screen_direction(actor,point+aim*.03,battle)
	if state=="attack":
		var plan: Dictionary = _attack_plan(actor,friendly)
		var committed_target: Dictionary = _lookup_target(int(plan.get("targetId",-1)),friendly,battle)
		if _visual_target_valid(actor,committed_target,friendly,battle): return _screen_direction(actor,_position(committed_target),battle,committed_target,_actor_key(actor,friendly))
		var receipt: Dictionary = _receipt_for(actor,friendly)
		if not receipt.is_empty(): return _screen_direction(actor,receipt.targetPosition,battle)
		return _screen_direction(actor,point+aim*.03,battle)
	if friendly and state=="idle" and str(actor.get("type","")) in ["archer","gunner"]:
		# Gameplay sets aim when preparing a real attack and keeps it after
		# recovery. Choosing a different nearest enemy between shots made fixed
		# shooters turn away, then snap back to their real target every cycle.
		var meta: Dictionary=actor.get("skillMeta",{})
		var has_attack_facing: bool=not str(meta.get("attackId","")).is_empty() or _shot_receipts.has(_actor_key(actor,true))
		if has_attack_facing and aim.length_squared()>.000001: return _screen_direction(actor,point+aim*.03,battle)
		return _road_facing(actor,true,battle)
	# Idle actors face an actual nearby legal opponent or their guarded road.
	# This selection is presentation only and never writes targetId/aim/plan.
	var key: String = _actor_key(actor,friendly)
	var cached: Dictionary = _facing_cache.get(key,{})
	var target: Dictionary = _lookup_target(int(cached.get("targetId",-1)),friendly,battle)
	var clock: float = float(battle.animation_time)
	if cached.is_empty() or clock-float(cached.get("checkedAt",-1))>=.12 or (not target.is_empty() and not _visual_target_valid(actor,target,friendly,battle)):
		var nearest: float = INF
		target={}
		for candidate in _visual_facing_candidates(actor,friendly,battle):
			var distance: float = point.distance_squared_to(_position(candidate))
			# The strict comparison preserves the original first-candidate tie rule.
			# A farther actor cannot replace the selected legal visual target.
			if distance>=nearest: continue
			if not _visual_target_valid(actor,candidate,friendly,battle): continue
			if distance<nearest: target=candidate; nearest=distance
		_facing_cache[key]={"targetId":int(target.get("id",-1)),"checkedAt":clock}
	if not target.is_empty(): return _screen_direction(actor,_position(target),battle,target,key)
	return _road_facing(actor,friendly,battle)

func _append(actor: Dictionary, friendly: bool, dead: bool, battle: Node2D) -> void:
	if not dead and float(actor.get("hp",1.0))<=0: return
	var point: Vector2 = actor.get("position",Vector2(float(actor.get("x",0)),float(actor.get("y",0))))
	if not point.is_finite(): return
	var screen_foot: Vector2 = battle._screen(point)
	var margin: float = body_height_screen*2.5
	if not battle.field_rect.grow(margin).has_point(screen_foot): return
	var aim: Vector2 = visual_direction(actor,friendly,battle)
	var index: int = _items.size()
	if index>=_pool.size(): _pool.append(DrawItem.new())
	var item: DrawItem = _pool[index]
	item.actor = actor
	item.foot = screen_foot
	item.direction = aim
	item.friendly = friendly
	item.dead = dead
	item.type_name = str(actor.get("type",actor.get("kind","spear")))
	item.sequence = index
	_items.append(item)

func _sort_items(a: DrawItem, b: DrawItem) -> bool:
	if a.foot.y!=b.foot.y: return a.foot.y<b.foot.y
	var a_id: int = int(a.actor.get("id",0))
	var b_id: int = int(b.actor.get("id",0))
	return a_id<b_id if a_id!=b_id else a.sequence<b.sequence

func render(canvas: Node2D, battle: Node2D) -> bool:
	last_actor_count = 0; last_draw_count = 0; last_skipped_count = 0
	last_structure_count=0
	if not is_ready(): return false
	bind_battle(battle)
	_ensure_display_frame(battle)
	_clear_actor_samples()
	for key in _shot_receipts.keys():
		var live_index: Dictionary = _unit_by_id if str(key).begins_with("friendly/") else _enemy_by_id
		if not live_index.has(int(str(key).get_slice("/",1))): _shot_receipts.erase(key)
	for key in _facing_cache.keys():
		var live_index: Dictionary = _unit_by_id if str(key).begins_with("friendly/") else _enemy_by_id
		if not live_index.has(int(str(key).get_slice("/",1))): _facing_cache.erase(key)
	for key in _motion_tracks.keys():
		var live_index: Dictionary=_unit_by_id if str(key).begins_with("friendly/") else _enemy_by_id
		if not live_index.has(int(str(key).get_slice("/",1))): _motion_tracks.erase(key)
	for key in _contact_tracks.keys():
		var live_index: Dictionary=_unit_by_id if str(key).begins_with("friendly/") else _enemy_by_id
		if not live_index.has(int(str(key).get_slice("/",1))): _contact_tracks.erase(key)
	_render_height=body_height_screen*clampf(float(battle.field_rect.size.y)/620.0,.65,1.5)
	_items.clear()
	var facing_started: int=Time.get_ticks_usec() if bool(battle.performance_profiling_enabled) else 0
	_spatial_facing_draw=true
	for unit in battle.units: _append(unit,true,false,battle)
	for enemy in battle.enemies:
		if battle._enemy_visible(enemy): _append(enemy,false,false,battle)
	for dead in battle.death_actors: _append(dead,bool(dead.get("friendly",false)),true,battle)
	for support in battle.battle_support.actor_states(): _append(support,true,false,battle)
	_spatial_facing_draw=false
	battle._profile_elapsed("paintedFacing",facing_started,_items.size())
	_items.sort_custom(_sort_items)
	var height: float = _render_height
	last_actor_count = _items.size()
	var draw_started: int=Time.get_ticks_usec() if bool(battle.performance_profiling_enabled) else 0
	for item in _items:
		if draw_actor(canvas,item.actor,item.foot,item.friendly,height,item.direction,true): last_draw_count += 1
		else: last_skipped_count += 1
	battle._profile_elapsed("paintedDraw",draw_started,_items.size())
	return true

func diagnostics() -> Dictionary:
	return {"assetCacheHit":asset_cache_hit,"assetPrepareMicroseconds":asset_prepare_microseconds,"compiledAssetBundles":compiled_asset_cache.size(),"captureRigDiagnostics":capture_rig_diagnostics,"meshCompilation":"once per manifest digest; per-draw mesh reused","poseBoundsCached":_bounds_cache.size(),"manifest":manifest_path,"ready":is_ready(),"poseSets":poses.size(),"loadedTextures":_loaded_paths.keys(),"bodyHeightScreenAt620":body_height_screen,"actors":last_actor_count,"drawnActors":last_draw_count,"skippedActors":last_skipped_count,"structures":last_structure_count,"fortificationArtReady":fortification_pose!=null,"missingStructureAsset":missing_structure_asset,"structureHealth":"existing real enemy id/hp; no decorative target","missingTypes":missing_types.keys(),"resolvedRoleAliases":alias_uses.duplicate(),"errors":asset_errors.duplicate(),"warnings":asset_warnings.duplicate(),"actorFrames":actor_samples.duplicate(true),"directionFallbacks":direction_fallbacks.duplicate(),"pendingAuthoredActions":manifest.get("pendingAuthoredActions",[]),"oneQuadPerRealActor":rigs.is_empty(),"uvRigSets":rigs.size(),"missingActions":missing_actions.keys(),"pendingWalkDirections":manifest.get("pendingWalkDirections",[]),"contactShadow":"two soft ellipses at actual foot; combined center alpha .154, death/departure fade","primitiveCharacterFallback":false,"gameplayWrites":false,"automaticPerFrameBodyRescale":false,"animation":"Four screen-space diagonal action directions when authored; attack release follows actual shot event. Distance-driven alternating limb UV rigs for registered roles; actual rendered gait acceptance remains pending. Unregistered walks retain explicit source limits."}
