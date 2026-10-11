extends "C:/JP_DF/tests/profiles/reference-scene-01/art-coherence-01/qa_art_coherence.gd"

const ASSET_WORK: String = "C:/JP_DF/tools/art-authoring-pilot/work/20261010T050221Z-581667a1"
const ISOLATED_CANDIDATE: String = ASSET_WORK+"/godot-candidate"
const ASSET_PATH: String = "res://assets/blender-pilot/asset.glb"
const ASSET_ROOTS: Array = ["Broadleaf_A","Broadleaf_B","Broadleaf_C","Shrub_A","Shrub_B","FiringPad","Palisade","GroundSample"]
var asset_gate: Dictionary = {}
var asset_contract: Dictionary = {}
var asset_bindings: Dictionary = {}
var asset_import_rows: Array = []
var asset_runtime_rows: Array = []
var asset_showcase: Dictionary = {}
var asset_selection: Array = []
var asset_selection_attempted: Dictionary = {}
var asset_enemy_frame: int = -1
var asset_ingress_complete: bool = false
var asset_offscreen_capture: bool = false
var asset_approach_capture: bool = false
var asset_captured_enemy_id: String = ""
var asset_finished: bool = false
var asset_game_freeze: String = ""
var asset_frozen_count: int = 0
var asset_isolated_count: int = 0
var asset_packed: PackedScene
var asset_floor_material: BaseMaterial3D

func bounded() -> bool:
	return int(Time.get_unix_time_from_system())<deadline_unix-15 and Time.get_ticks_usec()-qa_started<345000000

func journal(kind: String, detail: Dictionary = {}) -> void:
	var path: String = "user://blender-assets-progress.jsonl"
	var file: FileAccess = FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file!=null:
		file.seek_end()
		file.store_line(JSON.stringify({"kind":kind,"detail":detail,"eligible_seconds":eligible_seconds,"wall_seconds":float(Time.get_ticks_usec()-qa_started)/1000000.0}))
		file.close()

func load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func prepare_asset_guard() -> bool:
	qa_started=Time.get_ticks_usec()
	asset_gate=load_json_file(ASSET_WORK+"/BLENDER_PRODUCTION_GATE.json")
	asset_contract=load_json_file(ASSET_WORK+"/FUN_ASSET_CONTRACT.json")
	deadline_unix=int(Time.get_unix_time_from_datetime_string(str(asset_gate.get("hard_stop_utc","")).trim_suffix("Z")))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	if not check(canonical(ProjectSettings.globalize_path("res://"))==canonical(ISOLATED_CANDIDATE) and roaming.begins_with(canonical(ASSET_WORK)+"/evidence/game") and canonical(OS.get_environment("LOCALAPPDATA"))==roaming and canonical(ProjectSettings.globalize_path("user://")).begins_with(roaming+"/") and DisplayServer.get_name()!="headless","Exact isolated Blender asset candidate and private HQ native profile"): return false
	if not check(str(asset_gate.get("task",""))=="BLENDER-ASSET-PRODUCTION-01" and str(asset_gate.get("hard_stop_utc",""))=="2026-10-10T06:16:08Z" and deadline_unix>int(Time.get_unix_time_from_system())+30,"Current Blender asset gate and finite hard stop"): return false
	var asset_freeze: Dictionary = load_json_file(ASSET_WORK+"/ASSET_SOURCE_FREEZE.json")
	for path in asset_freeze.get("sources",{}): frozen_sources[path]=str(asset_freeze.sources[path])
	asset_frozen_count=frozen_sources.size()
	asset_game_freeze=ASSET_WORK+"/GAME_SOURCE_FREEZE.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--game-source-freeze="): asset_game_freeze=argument.trim_prefix("--game-source-freeze=").replace("\\","/")
	if not check(canonical(asset_game_freeze).begins_with(canonical(ASSET_WORK)+"/"),"Isolated source freeze belongs to this work"): return false
	var game_freeze: Dictionary = load_json_file(asset_game_freeze)
	var sources: Dictionary = game_freeze.get("sources",{})
	for path in sources:
		var entry: Variant = sources[path]
		frozen_sources[path]=str(entry.get("sha256","")) if entry is Dictionary else str(entry)
	asset_isolated_count=sources.size()
	if game_freeze.has("qa_sha256"):
		check(str(game_freeze.qa_sha256)==FileAccess.get_sha256(get_script().resource_path),"Current external asset QA matches HQ source freeze")
	initial_hashes=source_snapshot()
	if not check(asset_frozen_count>0 and asset_isolated_count>0 and initial_hashes==frozen_sources,"Frozen authored assets and critical isolated game sources match before actual run"): return false
	var covered: Dictionary = {}
	for path in sources: covered[canonical(str(path))]=true
	for critical in ["res://native/main.gd","res://native/game.gd","res://native/troops_3d.gd","res://native/actor_materials.gd","res://native/remaster_surface_materials.gd","res://native/remaster_visual_slice.gd",QA_SOURCE,ASSET_PATH,"res://assets/blender-pilot/bindings.json"]:
		check(covered.has(canonical(critical)) or covered.has(canonical(ProjectSettings.globalize_path(critical))),"Critical isolated source included in HQ freeze: "+critical)
	check(FileAccess.get_sha256(QA_SOURCE)==FileAccess.get_sha256(ASSET_WORK+"/source_stage.json"),"Isolated world/route/physical anchors remain exact prepared stage bytes")
	source_data=load_json_file(QA_SOURCE)
	asset_bindings=load_json_file("res://assets/blender-pilot/bindings.json")
	root.size=Vector2i(1440,900)
	root.content_scale_size=root.size
	return failures.is_empty()

func relative_import_transform(node: Node3D, library: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var cursor: Node = node
	while cursor is Node3D:
		result=(cursor as Node3D).transform*result
		if cursor==library: break
		cursor=cursor.get_parent()
	return result

func inspect_imported_assets() -> void:
	asset_packed=load(ASSET_PATH) as PackedScene
	if not check(asset_packed!=null,"Actual imported GLB loads as PackedScene"): return
	var library: Node3D = asset_packed.instantiate() as Node3D
	if not check(library!=null,"Actual GLB instantiates Node3D library"): return
	for root_name in ASSET_ROOTS:
		var matches: Array = []
		if str(library.name)==root_name: matches.append(library)
		for node in library.find_children("*","Node3D",true,false):
			if str(node.name)==root_name: matches.append(node)
		if not check(matches.size()==1,"Actual GLB has exactly one named root "+str(root_name)): continue
		var source: Node3D = matches[0]
		var row: Dictionary = {"root":root_name,"export_basis":str(relative_import_transform(source,library)),"surfaces":[],"triangles":0,"vertices":0,"normal_vertices":0,"UV_vertices":0,"tangent_vertices":0}
		check(relative_import_transform(source,library).origin.length()<.002,"Actual imported root origin at module base: "+str(root_name))
		var mesh_nodes: Array = source.find_children("*","MeshInstance3D",true,false)
		if source is MeshInstance3D: mesh_nodes.push_front(source)
		var box: AABB = AABB()
		var have_box: bool = false
		for mesh_node in mesh_nodes:
			var mesh: Mesh = mesh_node.mesh
			if not check(mesh!=null,"Actual imported mesh exists under "+str(root_name)): continue
			var transform: Transform3D = relative_import_transform(mesh_node,library)
			for corner in range(8):
				var point: Vector3 = transform*mesh.get_aabb().get_endpoint(corner)
				if not have_box: box=AABB(point,Vector3.ZERO);have_box=true
				else: box=box.expand(point)
			for surface in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null else PackedVector3Array()
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				var material: BaseMaterial3D = mesh_node.get_active_material(surface) as BaseMaterial3D
				check(normals.size()==vertices.size() and uv.size()==vertices.size() and vertices.size()>0,"Actual imported normals/UV cover all mesh vertices: "+str(root_name))
				var images: Dictionary = {}
				if check(material!=null,"Actual imported PBR material bound: "+str(root_name)):
					if str(root_name)=="FiringPad" and material.resource_name=="CompactedDirt_ImagePBR": asset_floor_material=material.duplicate(true) as BaseMaterial3D
					for channel in ["albedo_texture","normal_texture","roughness_texture"]:
						var texture: Texture2D = material.get(channel) as Texture2D
						if texture!=null: images[channel]={"width":texture.get_width(),"height":texture.get_height(),"resource":texture.resource_path}
					check(images.has("albedo_texture") and int(images.albedo_texture.width)>0,"Actual imported image-backed albedo: "+str(root_name))
				row.surfaces.append({"mesh":str(mesh_node.name),"surface":surface,"vertices":vertices.size(),"normal_count":normals.size(),"UV_count":uv.size(),"tangent_count":tangents.size(),"material":material.resource_name if material!=null else "missing","images":images,"normal_enabled":material.normal_enabled if material!=null else false})
				row.vertices+=vertices.size()
				row.normal_vertices+=normals.size()
				row.UV_vertices+=uv.size()
				row.tangent_vertices+=int(tangents.size()/4)
				row.triangles+=int((indices.size() if not indices.is_empty() else vertices.size())/3)
		row["actual_bounds"]={"min":str(box.position),"max":str(box.end),"size":str(box.size)}
		var expected: Dictionary = asset_bindings.get("roots",{}).get(root_name,{})
		row["contract_bounds"]=expected
		var low: Array = expected.get("min",[])
		var high: Array = expected.get("max",[])
		if low.size()==3 and high.size()==3:
			check(box.position.distance_to(Vector3(float(low[0]),float(low[1]),float(low[2])))<.005 and box.end.distance_to(Vector3(float(high[0]),float(high[1]),float(high[2])))<.005,"Actual Godot-Y-up bounds match GLB contract without second axis conversion: "+str(root_name))
		if str(root_name)=="FiringPad": check(box.size.y>.3,"Actual FiringPad imported geometry has real raised side height")
		check(int(row.triangles)>0 and int(row.triangles)==int(expected.get("triangles",-1)),"Actual imported triangles equal frozen GLB contract: "+str(root_name))
		asset_import_rows.append(row)
	library.free()
	write_art_report(false)

func bootstrap_normal_game() -> bool:
	var store: RefCounted = Store.new()
	store.save_path="user://blender-assets-fresh.json"
	if not check(not FileAccess.file_exists(store.save_path),"Fresh isolated asset account has no previous save"): return false
	store.read_save()
	store.data.settings.voice=false
	store.data.settings.music=false
	store.data.settings.effects=false
	app=load("res://native/main.tscn").instantiate()
	app.progress=store
	root.add_child(app)
	await settle(4)
	app.game.game_event.connect(on_real_event)
	app.learning_field.target_chosen.connect(on_context_target_signal)
	app.learning_transition.phase_changed.connect(on_context_transition_phase)
	check(app.maps.size()==1 and not app.isolated_candidate and store.data.maps.is_empty(),"Normal Main retains canonical catalog in isolated asset candidate")
	if not await desktop_click(app.front_end.get_node_or_null("HomeSortie") as Button,"Asset actual Home sortie") or not await desktop_wait_catalog_entry(): return false
	if not await desktop_click(app.front_end.find_child("Stage_basic-forest",true,false) as Button,"Asset actual canonical stage") or not await desktop_click(app.front_end.get_node_or_null("CatalogSortie") as Button,"Asset actual catalog sortie"): return false
	if not check(app.modal_context=="briefing","Actual asset normal briefing") or not await desktop_click(desktop_button(app.modal_footer,"출진"),"Asset actual briefing 출진"): return false
	provider=app.troops_3d.battlefield
	return check(app.game.running and app.battle_started,"Normal real UI starts isolated asset game")

func save_actual_capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var texture: Texture2D = root.get_texture()
	if not check(texture!=null,"Asset actual root texture exists"):
		review_abort=true
		return
	var image: Image = texture.get_image()
	if not check(image!=null and not image.is_empty(),"Asset actual root image nonempty"):
		review_abort=true
		return
	var path: String = "user://blender-assets-"+label+".png"
	if check(image.save_png(path)==OK,"Immediate raw asset pixels saved: "+label): captures.append({"label":label,"path":ProjectSettings.globalize_path(path),"size":[image.get_width(),image.get_height()],"clock":app.game.elapsed if is_instance_valid(app) else 0,"scope":"ISOLATED ASSET SHOWCASE; no gameplay claim" if label.begins_with("showcase") else "Actual normal game, full HUD/learning frame"})
	write_art_report(false)

func show_asset_library() -> void:
	measurement_epoch+=1
	layout_capture_active=true
	if not await desktop_click(app.pause_button,"Actual pause before isolated asset showcase") or not check(app.game.paused,"Actual game paused during separate asset showcase"):
		review_abort=true
		layout_capture_active=false
		measurement_epoch+=1
		return
	var clock: float = app.game.elapsed
	var viewport: SubViewport = SubViewport.new()
	viewport.size=Vector2i(1440,900)
	viewport.own_world_3d=true
	viewport.msaa_3d=app.troops_3d.viewport.msaa_3d
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: Node3D = Node3D.new()
	viewport.add_child(world)
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment=app.troops_3d.environment.duplicate(true)
	world.add_child(holder)
	world.add_child(app.troops_3d.sun.duplicate())
	if is_instance_valid(app.troops_3d.fill): world.add_child(app.troops_3d.fill.duplicate())
	var camera: Camera3D = app.troops_3d.camera.duplicate() as Camera3D
	world.add_child(camera)
	camera.current=true
	var library: Node3D = asset_packed.instantiate() as Node3D
	world.add_child(library)
	library.hide()
	var placements: Array = asset_contract.get("showcase_for_QA",{}).get("positions_godot_x_y_z",[])
	var modules: Array = []
	for index in range(ASSET_ROOTS.size()):
		var root_name: String = str(ASSET_ROOTS[index])
		var source: Node3D = library.find_child(root_name,true,false) as Node3D
		if source==null: continue
		var model: Node3D = source.duplicate() as Node3D
		model.transform=relative_import_transform(source,library)
		model.show()
		var wrapper: Node3D = Node3D.new()
		world.add_child(wrapper)
		var position_value: Array = placements[index]
		wrapper.position=Vector3(float(position_value[0]),float(position_value[1]),float(position_value[2]))
		wrapper.add_child(model)
		modules.append({"root":root_name,"origin":str(wrapper.position),"origin_xyz":position_value,"preserved_export_transform":str(model.transform)})
	# Context receiver belongs only to this disposable isolated showcase.
	# It never replaces the authoritative game floor or changes product light.
	var receiver: MeshInstance3D = MeshInstance3D.new()
	receiver.name="QA_ShowcaseOnly_ContactShadowReceiver"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size=Vector2(20,14)
	receiver.mesh=plane
	receiver.position.y=-.03
	receiver.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if check(asset_floor_material!=null,"Showcase receiver clones actual imported CompactedDirt material"):
		asset_floor_material.uv1_scale=Vector3(20*.31,14*.31,1)
		receiver.material_override=asset_floor_material
	world.add_child(receiver)
	var display: TextureRect = TextureRect.new()
	display.texture=viewport.get_texture()
	display.size=Vector2(1440,900)
	display.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	var labels: Control = Control.new()
	labels.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(labels)
	var title: Label = Label.new()
	title.text="ISOLATED ASSET SHOWCASE - actual imported GLB / common game camera and cloned lighting / NOT GAMEPLAY"
	title.position=Vector2(24,20)
	labels.add_child(title)
	for module in modules:
		var label: Label = Label.new()
		label.text=module.root
		label.position=camera.unproject_position(Vector3(float(module.origin_xyz[0]),float(module.origin_xyz[1]),float(module.origin_xyz[2])))+Vector2(-50,30)
		labels.add_child(label)
	await settle(5)
	asset_showcase={"scope":"Isolated original-scale asset library only; FiringPad/GroundSample full mesh never overlays gameplay floor","modules":modules,"camera":observed_properties(camera,["projection","size","position","rotation_degrees"]),"environment":observed_properties(holder.environment,["tonemap_mode","tonemap_exposure","ambient_light_color","ambient_light_energy","ssao_enabled","glow_enabled"]),"source_environment_cloned":true,"source_sun_cloned":true,"game_clock":clock}
	asset_showcase["context_receiver"]={"name":str(receiver.name),"size":[20,14],"y":-.03,"material":"cloned imported CompactedDirt_ImagePBR","UV_cycles_per_world_unit":.31,"cast_shadow":int(receiver.cast_shadow),"scope":"QA-only contact-shadow display receiver; no gameplay floor change"}
	check(modules.size()==8 and is_equal_approx(camera.size,23.5),"All8 actual imported roots shown at common ortho23.5 camera")
	await take_capture("showcase-all8-common-camera-1440x900")
	check(app.game.elapsed==clock,"Asset showcase does not advance paused gameplay clock")
	display.queue_free()
	labels.queue_free()
	viewport.queue_free()
	await settle(3)
	if not await desktop_click(app.pause_button,"Actual resume after isolated asset showcase") or not check(not app.game.paused,"Native game resumes after showcase"): review_abort=true
	layout_capture_active=false
	measurement_epoch+=1

func asset_mount_readback(label: String) -> void:
	var visuals: Node = app.remaster_visuals
	var diagnostics: Dictionary = visuals.diagnostics()
	var pilot: Dictionary = diagnostics.get("blenderPilot",{})
	var errors: Array = []
	for issue in pilot.get("errors",[]):
		if str(issue).contains("Palisade base terrain differs >.12"):
			journal("contract_palisade_showcase_only",{"reason":issue})
		else: errors.append(issue)
	check(errors.is_empty() and int(pilot.get("treeInstances",0))==6 and int(pilot.get("shrubInstances",0))==3,"Actual imported representative6trees/3shrubs bind without unexpected errors")
	check(bool(pilot.get("groundAlbedoBound",false)) and not bool(pilot.get("floorGeometryChanged",true)),"Actual baked base soil bound while sole gameplay floor retained")
	var anchors: Array = []
	for wrapper in visuals.find_children("BlenderPilot_*","Node3D",true,false):
		if not wrapper.has_meta("source_anchor_id"): continue
		var id: String = str(wrapper.get_meta("source_anchor_id"))
		var expected: Dictionary = asset_bindings.get("trees",{}).get(id,asset_bindings.get("shrubs",{}).get(id,{}))
		var source_point: Array = expected.get("anchor_xz",[])
		var legal: bool = true
		if source_point.size()==2:
			legal=Vector2(wrapper.position.x,wrapper.position.z).distance_to(Vector2(float(source_point[0]),float(source_point[1])))<.002
			check(legal,"Actual imported representative root retains authored XZ: "+id)
			var floor_point: Vector3 = provider.world_point(point_xz(source_point))
			check(wrapper.global_position.distance_to(floor_point)<.002,"Actual imported representative root touches existing provider Y: "+id)
		anchors.append({"id":id,"world_position":str(wrapper.global_position),"scale":str(wrapper.scale),"XZ_match":legal,"source":expected})
	asset_runtime_rows.append({"label":label,"clock":app.game.elapsed,"diagnostics":diagnostics,"imported_anchors":anchors,"floor_shadow_states":mounted_shadow_readback(label),"camera":observed_properties(app.troops_3d.camera,["projection","size","position","rotation_degrees"]),"full_FiringPad":"showcase-only;no second floor","GroundSample":"showcase-only;no tiled baked road"})

func perform_pause_layout_capture() -> void:
	if not await desktop_click(app.pause_button,"Native pause for asset paid layouts") or not check(app.game.paused,"Actual native asset battle paused"):
		review_abort=true
		return
	var clock: float = app.game.elapsed
	for dimensions in [Vector2i(1440,900),Vector2i(1280,800)]:
		if root.size!=dimensions: await desktop_resize(dimensions)
		text_visibility("actual asset battle "+str(dimensions))
		asset_mount_readback("paid battle "+str(dimensions))
		await take_capture("paid-battle-"+str(dimensions.x)+"x"+str(dimensions.y))
	check(app.game.elapsed==clock,"Asset paid battle layouts share same native paused clock")
	await desktop_resize(Vector2i(1440,900))
	if not await desktop_click(app.pause_button,"Native resume after asset paid layouts") or not check(not app.game.paused,"Actual asset battle resumed"): review_abort=true
	battle_capture_done=not review_abort

func write_art_report(complete: bool) -> void:
	var frames: Array = []
	var gpu: Array = []
	var draws: Array = []
	var actors: Array = []
	var allies: Array = []
	var enemies: Array = []
	var stalls: int = 0
	for row in measured_rows:
		if not bool(row.eligible): continue
		frames.append(row.frame_ms)
		draws.append(row.shared_draw_calls)
		actors.append(row.actor_nodes)
		allies.append(row.allies)
		enemies.append(row.enemies)
		if row.shared_gpu_ms!=null: gpu.append(row.shared_gpu_ms)
		if float(row.frame_ms)>50: stalls+=1
	var report: Dictionary = {"task":"BLENDER-ASSET-PRODUCTION-01","status":"RUNNING_PARTIAL" if not complete else ("FAIL" if not failures.is_empty() else ("PENDING" if not pending.is_empty() else "FUNCTIONAL_PASS_VISUAL_REVIEW_PENDING")),"checks":check_rows,"failures":failures,"pending":pending,"captures":captures,"imported_GLB_roots":asset_import_rows,"isolated_showcase":asset_showcase,"mounted_game_assets":asset_runtime_rows,"native_input_trace":native_input_trace,"native_drag_trace":native_drag_trace,"context_input_trace":context_input_trace,"selection":asset_selection,"events":natural_events,"paid_orders":paid_orders,"paid_produced":paid_produced,"paid_ids":paid_ids,"paid_attacks":paid_attacks,"natural_hit_seen":natural_hit_seen,"context_returns":context_returns,"quiz_returns":quiz_returns,"ingress_trace":ingress_trace,"same_enemy_ingress":asset_ingress_complete,"eligible_seconds":eligible_seconds,"metrics":{"frame_ms":metrics_summary(frames),"shared_gpu_ms":metrics_summary(gpu),"shared_draw_calls":metrics_summary(draws),"actor_nodes_min":actors.min() if not actors.is_empty() else null,"actor_nodes_max":actors.max() if not actors.is_empty() else null,"stalls_over50ms":stalls,"rows":measured_rows},"metric_scope":"Inherited actual rendered both-endpoint flags and measurement epoch; screenshots/resize/pause/learning/showcase excluded; positive shared viewport GPU times only; no full60FPS or matched-condition improvement claim","asset_frozen_count":asset_frozen_count,"isolated_frozen_count":asset_isolated_count,"game_freeze":asset_game_freeze,"source_hashes_before":initial_hashes,"source_hashes_after":source_snapshot(),"source_unchanged":source_snapshot()==initial_hashes,"hardware":{"engine":Engine.get_version_info(),"GPU":RenderingServer.get_video_adapter_name(),"CPU":OS.get_processor_name(),"method":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name()},"deadline_unix":deadline_unix,"wall_seconds":float(Time.get_ticks_usec()-qa_started)/1000000.0,"review_aborted":review_abort,"visual_acceptance":"Separate UX review of actual full captures required; final reference approval remains with user","scope_limits":["No old658/full205/full150 repetition","No controlled colour/ninja fixtures","No product source/render/light/renderer changes from QA","Showcase is isolated;fullFiringPad andGroundSample are not gameplay integration proof","Inherited1280tooltip not closed"]}
	report.metrics["ally_count_min"]=allies.min() if not allies.is_empty() else null
	report.metrics["ally_count_max"]=allies.max() if not allies.is_empty() else null
	report.metrics["enemy_count_min"]=enemies.min() if not enemies.is_empty() else null
	report.metrics["enemy_count_max"]=enemies.max() if not enemies.is_empty() else null
	report["tangent_scope"]="Actual Godot ARRAY_TANGENT availability recorded per imported surface; exporter tangent warnings alone are not classified as functional failure. Normal-map shading still requires actual visual review."
	var file: FileAccess = FileAccess.open("user://QA_BLENDER_RESULT.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()

func finish_art() -> void:
	monitoring=false
	asset_finished=true
	if eligible_seconds<30: pending.append("Natural eligible combat below30seconds")
	if not readiness_captures_done or not battle_capture_done: pending.append("Actual READY/paid full layouts incomplete")
	if asset_import_rows.size()!=8 or asset_showcase.is_empty(): pending.append("Actual8root import/showcase incomplete")
	if context_returns<1 or quiz_returns<1: pending.append("Natural context/quiz answer and return incomplete")
	if int(paid_produced.archer)<2 or int(paid_produced.spear)<2: pending.append("Actual paid2archer2spear incomplete")
	if not paid_attacks.has("archer") or not paid_attacks.has("spear") or not natural_hit_seen: pending.append("Paid attacks or natural damage evidence incomplete")
	if asset_selection_attempted.size()<2: pending.append("Actual paid archer/spear first selection incomplete")
	if not asset_ingress_complete or not asset_offscreen_capture or not asset_approach_capture: pending.append("Actual sameID offscreen-to-approach trace/captures incomplete")
	check(initial_hashes==frozen_sources and source_snapshot()==frozen_sources,"Frozen authored assets and isolated critical sources unchanged before/after")
	write_art_report(true)
	quit(1 if not failures.is_empty() else 0)

func finish_map_camera() -> void:
	await finish_art()

func run() -> void:
	if not prepare_asset_guard():
		write_art_report(true)
		quit(2)
		return
	inspect_imported_assets()
	if not failures.is_empty():
		await finish_art()
		return
	process_frame.connect(observe_enemies)
	if not await bootstrap_normal_game():
		await finish_art()
		return
	await capture_ready_layouts()
	await show_asset_library()
	if review_abort:
		await finish_art()
		return
	asset_mount_readback("actual ready after isolated showcase")
	monitoring=true
	call_deferred("monitor_rendered_frames")
	for pad in ["left-shoulder-pad","right-shoulder-pad"]:
		if not await paid_pad_order(pad): pending.append("Actual paid archer unavailable: "+pad)
	for index in range(2):
		var gold: int = app.game.gold
		var id: int = app.game.next_recruitment_id
		var accepted: bool = await desktop_paid_order("spear")
		paid_orders.append({"type":"spear","accepted":accepted,"job_id":id,"gold_before":gold,"gold_after":app.game.gold})
	var natural_started: int = Time.get_ticks_usec()
	while bounded() and not review_abort and Time.get_ticks_usec()-natural_started<300000000 and not app.game.finished:
		await process_frame
		await service_natural_learning()
		if review_abort: break
		if eligible_now():
			for type_name in ["archer","spear"]:
				await asset_select_paid_unit(type_name)
				if review_abort: break
		if review_abort: break
		for id in ingress_trace:
			var trace: Dictionary = ingress_trace[id]
			if bool(trace.first_body_offscreen) and not bool(trace.entered_frame) and not asset_offscreen_capture:
				var body: Rect2 = enemy_body_rect(int(id))
				if body.has_area() and not Rect2(Vector2.ZERO,app.troops_3d.field_size).intersects(body):
					asset_captured_enemy_id=id
					asset_offscreen_capture=true
					await take_capture("same-enemy-"+id+"-offscreen-1440x900")
			if id==asset_captured_enemy_id and bool(trace.approach_seen) and not asset_approach_capture:
				asset_approach_capture=true
				await take_capture("same-enemy-"+id+"-visible-approach-1440x900")
		if not battle_capture_done and eligible_now() and app.game.elapsed>10: await pause_layout_capture()
		if eligible_seconds>=40 and context_returns>0 and quiz_returns>0 and battle_capture_done and paid_attacks.has("archer") and paid_attacks.has("spear") and natural_hit_seen and asset_ingress_complete and asset_selection_attempted.size()==2: break
		if eligible_seconds>=60: break
	await finish_art()

func observe_enemies() -> void:
	if not is_instance_valid(app) or not app.battle_started or not is_instance_valid(app.troops_3d.battlefield): return
	var frame: int = Engine.get_process_frames()
	if frame==asset_enemy_frame: return
	asset_enemy_frame=frame
	var field: Rect2 = Rect2(Vector2.ZERO,app.troops_3d.field_size)
	for enemy in app.game.enemies:
		var id: String = str(enemy.id)
		if not ingress_trace.has(id) and ingress_trace.size()>=2: continue
		var world: Vector3 = app.troops_3d.battlefield.world_point(enemy.position)
		var screen: Vector2 = app.troops_3d.project_world_to_field(world)
		if not ingress_trace.has(id):
			ingress_trace[id]={"id":enemy.id,"first_observed_clock":app.game.elapsed,"first_observed_frame":frame,"first_world":str(world),"first_normalized":str(enemy.position),"first_outside_core":enemy.position.x<0 or enemy.position.x>1 or enemy.position.y<0 or enemy.position.y>1,"first_body_observed":false,"first_body_offscreen":false,"entered_frame":false,"approach_seen":false,"last_position":enemy.position,"max_observed_step":0.0,"samples":[]}
		var trace: Dictionary = ingress_trace[id]
		trace.max_observed_step=maxf(float(trace.max_observed_step),Vector2(trace.last_position).distance_to(enemy.position))
		trace.last_position=enemy.position
		if not bool(trace.first_body_observed):
			var body: Rect2 = enemy_body_rect(int(enemy.id))
			if body.has_area():
				trace.first_body_observed=true
				trace.first_body_offscreen=not field.intersects(body)
				trace.first_body_clock=app.game.elapsed
				trace.first_body_rect=str(body)
				trace.first_body_delay_frames=frame-int(trace.first_observed_frame)
				trace.first_body_layout=str(root.size)
		if bool(trace.first_body_offscreen) and not bool(trace.entered_frame) and field.has_point(screen):
			var body: Rect2 = enemy_body_rect(int(enemy.id))
			if body.has_area() and field.intersects(body):
				trace.entered_frame=true
				trace.entered_clock=app.game.elapsed
				trace.entered_body_rect=str(body)
		if bool(trace.entered_frame) and enemy.position.x>=0 and enemy.position.x<=1 and enemy.position.y>=0 and enemy.position.y<=1:
			trace.approach_seen=true
			asset_ingress_complete=asset_ingress_complete or (bool(trace.first_outside_core) and bool(trace.first_body_offscreen))
		if trace.samples.is_empty() or app.game.elapsed-float(trace.samples[-1].clock)>=.5:
			trace.samples.append({"clock":app.game.elapsed,"world":str(world),"normalized":str(enemy.position),"screen":str(screen),"point_index":enemy.get("pointIndex",-1),"animation":enemy.get("animation",""),"layout":str(root.size)})

func asset_select_paid_unit(type_name: String) -> void:
	if asset_selection_attempted.has(type_name): return
	for unit in app.game.units:
		if str(unit.get("type",""))!=type_name or not paid_ids.has(str(unit.id)): continue
		var point: Vector2 = app.game.field_point_to_screen(unit.position)
		if not point.is_finite() or not app.game.screen_point_in_field(point): continue
		asset_selection_attempted[type_name]=true
		var id: int = int(unit.id)
		var before: int = app.game.selected_id
		await mouse(point,true)
		await mouse(point,false)
		await RenderingServer.frame_post_draw
		var actual: int = app.game.selected_id
		asset_selection.append({"type":type_name,"expected_paid_id":id,"before_id":before,"after_id":actual,"point":str(point),"first_attempt":true,"accepted":actual==id,"clock":app.game.elapsed,"selected_HUD":observed_properties(app.selected_label,["text","visible"])})
		if not check(actual==id,"First native field click selects actual paid "+type_name): review_abort=true
		return

