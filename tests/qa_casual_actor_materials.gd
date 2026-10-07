extends SceneTree
## Compare the same authored geometry before and after a surface-only style
## change. The reference images are art direction, not rendered gameplay.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Materials = preload("res://native/actor_materials.gd")
const Field = preload("res://native/terrain_light_field.gd")
const PROFILE_ROOT: String = "c:/jp_df/tests/profiles/casual-actor-materials/"
const BASELINE: String = "res://tests/profiles/casual-actor-materials/baseline/Godot/app_userdata/말의 전장/geometry-baseline.json"
const TYPES: Array[String] = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array = []
var actors: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func isolated() -> bool:
	for name in ["APPDATA","LOCALAPPDATA"]:
		if not OS.get_environment(name).replace("\\","/").to_lower().begins_with(PROFILE_ROOT): return false
	return ProjectSettings.globalize_path("user://").replace("\\","/").to_lower().begins_with(PROFILE_ROOT)

func run() -> void:
	if DisplayServer.get_name()!="headless" or not isolated(): quit(2);return
	var baseline_mode: bool = "--baseline" in OS.get_cmdline_user_args()
	var reference: Dictionary = {}
	if not baseline_mode:
		if not FileAccess.file_exists(BASELINE): quit(2);return
		reference = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	var world: Node3D = Node3D.new()
	root.add_child(world)
	for type_name in TYPES:
		for side in [false,true]:
			for detail in [false,true]:
				var actor: Node3D = Actor.new()
				world.add_child(actor)
				actor.configure(type_name,side,7,detail,0)
				var observation: Dictionary = geometry_observation(actor)
				actors.append(observation)
				if not baseline_mode: verify_actor(actor,observation,reference)
				actor.queue_free()
				await process_frame
		for evolution in [1,2]:
			var actor: Node3D = Actor.new()
			world.add_child(actor)
			actor.configure(type_name,false,7,false,evolution)
			var observation: Dictionary = geometry_observation(actor)
			actors.append(observation)
			if not baseline_mode: verify_actor(actor,observation,reference)
			actor.queue_free()
			await process_frame
		print("CASUAL_GEOMETRY_PROGRESS ",type_name," ",actors.size())
	if not baseline_mode: verify_local_light()
	var report: Dictionary = {"baseline":baseline_mode,"checks":checks,"failures":failures,"actors":actors,"scope":"CPU actual authored soldiers, both teams, full-detail standing and field meshes, all friendly evolution variants. Position/normal/UV triangle streams and original rig poses compared with pre-style source. No gameplay or geometry changes are made by the fixture."}
	var file: FileAccess = FileAccess.open("user://geometry-baseline.json" if baseline_mode else "user://casual-material-contract.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	print("CASUAL_MATERIAL_CONTRACT ",JSON.stringify({"baseline":baseline_mode,"checks":checks,"failures":failures,"actors":actors.size()}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func geometry_observation(actor: Node3D) -> Dictionary:
	var geometry: HashingContext = HashingContext.new()
	geometry.start(HashingContext.HASH_SHA256)
	var triangle_count: int = 0
	var vertices: int = 0
	for instance in actor.meshes:
		geometry.update(str(instance.get_parent().name).to_utf8_buffer())
		for surface in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var expanded: PackedFloat32Array = PackedFloat32Array()
			expanded.resize(indices.size()*8)
			for cursor in range(indices.size()):
				var index: int = indices[cursor]
				var p: Vector3 = positions[index]
				var n: Vector3 = normals[index]
				var uv: Vector2 = uvs[index]
				var offset: int = cursor*8
				for channel in range(3): expanded[offset+channel]=p[channel];expanded[offset+3+channel]=n[channel]
				expanded[offset+6]=uv.x;expanded[offset+7]=uv.y
			geometry.update(expanded.to_byte_array())
			triangle_count += indices.size()/3
			vertices += positions.size()
	var poses: Dictionary = {}
	for animation in ["idle","walk","attack","death"]:
		actor.apply_state({"animation":animation,"animationClock":.43,"animationPhase":.21,"aimX":.2,"aimY":-.8,"locomotionPhase":.6,"groundMotion":true,"motionTime":.43,"travelSpeed":1.0,"localTravelSpeed":1.4,"runBlend":.6})
		var bones: Dictionary = {}
		for key in actor.bones: bones[key]=var_to_str(actor.bones[key].transform)
		poses[animation]=bones
	return {"key":"%s:%s:%s:%s"%[actor.unit_type,actor.hostile,actor.hero_detail,actor.evolution_stage],"triangles":triangle_count,"vertices":vertices,"geometryHash":geometry.finish().hex_encode(),"poses":poses,"jointNames":Array(actor.bones.keys()),"skinned":actor.skinned_renderer!=null}

func verify_actor(actor: Node3D, observation: Dictionary, reference: Dictionary) -> void:
	var prior: Dictionary = {}
	for entry in reference.actors:
		if str(entry.key)==str(observation.key): prior=entry;break
	check(not prior.is_empty(),"Pre-change authored actor exists: "+str(observation.key))
	if not prior.is_empty():
		for key in ["triangles","geometryHash","poses","jointNames","skinned"]: check(observation[key]==prior[key],"Original "+key+" preserved: "+str(observation.key))
	var material: ShaderMaterial = actor.materials.combined
	check(material.get_meta("art_direction","")=="clean_casual_3d_v1","Approved actual surface style: "+str(observation.key))
	check(bool(material.get_shader_parameter("hostile_team"))==actor.hostile,"Actual team shader matches allegiance: "+str(observation.key))
	check(material.get_meta("actor_type","")==actor.unit_type,"Species/role identity preserved: "+str(observation.key))
	if actor.skinned_renderer!=null:
		for group in actor.skinned_renderer.groups:
			var mesh: ArrayMesh=actor.skinned_renderer.groups[group].mesh
			var arrays: Array=mesh.surface_get_arrays(0)
			check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()==int(mesh.get_meta("authored_vertex_count",-1)),"Full original vertices retained: "+str(observation.key)+" "+group)
			check((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3==int(mesh.get_meta("authored_triangle_count",-1)),"Full authored triangles retained: "+str(observation.key)+" "+group)
	var left: ShaderMaterial=Materials.material().duplicate(false)
	var right: ShaderMaterial=Materials.material().duplicate(false)
	Materials.configure_actor_material(left,false,actor.unit_type)
	Materials.configure_actor_material(right,true,actor.unit_type)
	check(left.get_rid()!=right.get_rid() and not bool(left.get_shader_parameter("hostile_team")) and bool(right.get_shader_parameter("hostile_team")),"Team material state remains private: "+str(observation.key))

func verify_local_light() -> void:
	var image: Image=Image.create(48,32,false,Image.FORMAT_RGB8)
	for y in range(32):
		for x in range(48): image.set_pixel(x,y,Color(.04,.06,.035) if x<24 else Color(.7,.74,.62))
	var field=Field.new()
	field.configure({"background":"casual-shade-fixture"},image)
	var shade: Dictionary=field.sample(Vector2(.15,.5))
	var sun: Dictionary=field.sample(Vector2(.85,.5))
	check(shade.exposure>=.80 and shade.exposure<sun.exposure and sun.exposure<=1.16,"Broad shade retains team readability while responding to artwork")
	check(shade.saturation>=.99 and sun.saturation<=1.0,"Readable dyed colors remain saturated under local shade")
	check(Materials.material().shader.code.contains("NORMAL_MAP_DEPTH = normal_depth;"),"Placement preview retains opaque shader anchor")
	var preview: ShaderMaterial=Materials.placement_preview_material().duplicate(false)
	Materials.configure_actor_material(preview,false,"archer")
	check(preview.shader.code.contains("ALPHA = 0.75;"),"Existing placement ghost remains a transparent counterpart")
