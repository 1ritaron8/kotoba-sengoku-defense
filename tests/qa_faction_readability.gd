extends SceneTree
## Tests faction dye on 26 actual battle variants; --gpu adds real PBR capture.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Troops = preload("res://native/troops_3d.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array = []
var images: Array = []
var variants: Array = []
var gpu: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		push_error("FACTION QA: "+note)

func frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/faction-readability/").to_lower()):
		push_error("Faction QA refuses the player's profile")
		quit(2)
		return
	gpu = "--gpu" in OS.get_cmdline_user_args()
	if gpu and DisplayServer.get_name()=="headless":
		quit(2)
		return
	var world = Node3D.new()
	root.add_child(world)
	for type_name in TYPES:
		for evolution in range(3):
			await inspect_actor(world,type_name,false,evolution)
	for type_name in ["enemy_light","enemy_heavy"]:
		await inspect_actor(world,type_name,true,0)
	check(variants.size()==26,"All 24 friendly evolutions and both hostile silhouettes checked")
	world.queue_free()
	await process_frame
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var troops = Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1440,900))
	troops.set_stage(maps[0])
	check(is_equal_approx(troops.actor_base_scale(),.70),"Existing .70 battlefield scale preserved")
	check(troops.side_overlay.z_index<2048,"Faction glyphs do not cover game HP/placement feedback")
	var states: Array = []
	for index in range(24):
		states.append({"id":index+1,"type":TYPES[index%8],"evolution":index/8,"friendly":true,"x":.12+float(index%8)*.105,"y":.28+float(index/8)*.205,"animation":"idle","animationClock":.4,"motionTime":.4,"aimX":0,"aimY":1})
	for index in range(2):
		states.append({"id":100+index,"type":"enemy_light" if index==0 else "enemy_heavy","friendly":false,"x":.38+index*.23,"y":.865,"animation":"idle","animationClock":.4,"motionTime":.4,"aimX":0,"aimY":1})
	var baseline: Image
	if gpu:
		root.size = Vector2i(1440,900)
		await frames(8)
		await RenderingServer.frame_post_draw
		baseline = troops.viewport.get_texture().get_image()
	troops.sync_actor_states(states)
	check(troops.side_markers.size()==26,"One glyph per living rendered actor")
	for index in range(states.size()):
		var marker: Dictionary = troops.side_markers[index]
		var expected: Vector2 = Vector2(states[index].x,states[index].y)*troops.field_size
		check((marker.position as Vector2).distance_to(expected)<.08,"Glyph uses exact camera projection "+str(index))
		check(bool(marker.friendly)==bool(states[index].friendly),"Glyph shape follows actual side "+str(index))
	var paused_pose: Transform3D = troops.actors["1:0"].bones.torso.transform
	troops.sync_actor_states(states)
	check(paused_pose.is_equal_approx(troops.actors["1:0"].bones.torso.transform),"Render synchronization preserves pause pose")
	if gpu:
		await frames(8)
		await RenderingServer.frame_post_draw
		var rendered: Image = root.get_texture().get_image()
		var actor_frame: Image = troops.viewport.get_texture().get_image()
		check(rendered.save_png(qa_project_path("dist/preview-faction-variants.png"))==OK,"Real 26-variant battlefield-size GPU image saved")
		images.append(qa_project_path("dist/preview-faction-variants.png"))
		for source in states:
			var point: Vector2 = Vector2(source.x,source.y)*troops.field_size
			var colored: int = count_team_pixels(actor_frame,baseline,point,bool(source.friendly))
			check(colored>=8,"Actual odoshi/binding/cloth accents visible on GPU id="+str(source.id)+" pixels="+str(colored))
			troops.actors["%s:0"%str(source.id)].set_meta("gpuFactionPixels",colored)
		# A dark battlefield must preserve body dye too; flat foot glyphs alone
		# are insufficient proof that the original PBR actor is distinguishable.
		troops.sync_actor_states([])
		troops.set_stage(maps[8])
		await frames(8)
		await RenderingServer.frame_post_draw
		baseline = troops.viewport.get_texture().get_image()
		troops.sync_actor_states(states)
		await frames(8)
		await RenderingServer.frame_post_draw
		actor_frame = troops.viewport.get_texture().get_image()
		check(root.get_texture().get_image().save_png(qa_project_path("dist/preview-faction-variants-night.png"))==OK,"All 26 actual night-lit battle variants captured")
		images.append(qa_project_path("dist/preview-faction-variants-night.png"))
		for source in states:
			var point: Vector2 = Vector2(source.x,source.y)*troops.field_size
			var colored: int = count_team_pixels(actor_frame,baseline,point,bool(source.friendly))
			check(colored>=8,"Night-lit dyed body visible id="+str(source.id)+" pixels="+str(colored))
	states[0]["animation"] = "walk"
	states[0]["animationClock"] = .05
	states[0]["deploying"] = true
	troops.sync_actor_states(states)
	check((troops.side_markers[0].position as Vector2).distance_to(troops.camera.unproject_position(troops.actors["1:0"].position))<.08,"Deploying unit's glyph follows visible foot anchor rather than reserved post")
	states[0]["deploying"] = false
	states[0]["dead"] = true
	states[0]["animation"] = "death"
	troops.sync_actor_states(states)
	check(troops.side_markers.size()==25,"Dead actor loses living-side glyph")
	states[0]["dead"] = false
	states[0]["animation"] = "idle"
	states[0]["friendly"] = false
	troops.sync_actor_states(states)
	check(troops.actors["1:0"].hostile,"Reused identity with changed side refreshes material cache")
	check(not bool(troops.side_markers[0].friendly),"Reused identity changes side glyph")
	troops.sync_actor_states([])
	check(troops.side_markers.is_empty() and troops.actors.is_empty(),"Empty/reset battle clears all live side glyphs")
	troops.hide()
	check(not troops.side_overlay.is_visible_in_tree(),"Hidden battle hides its faction glyphs")
	troops.queue_free()
	await process_frame
	var result: Dictionary = {"checks":checks,"failures":failures,"variantCount":variants.size(),"variants":variants,"images":images,"gpu":RenderingServer.get_video_adapter_name() if gpu else "headless","scope":"Original geometry, scale, portraits and weighty animation retained; dark lacquer, differentiated cloth/leather, faction accents and shape-distinct foot glyphs only."}
	var file = FileAccess.open("user://qa_faction_readability.json",FileAccess.WRITE)
	check(file!=null,"Isolated QA report opens")
	result.checks=checks
	if file!=null:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	print("FACTION_READABILITY ",JSON.stringify({"checks":checks,"failures":failures,"variants":variants.size(),"gpu":gpu,"images":images}))
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)

func inspect_actor(world: Node3D, type_name: String, hostile: bool, evolution: int) -> void:
	var actor = Actor.new()
	world.add_child(actor)
	actor.configure(type_name,hostile,13,false,evolution)
	var context: String = "%s/%d/%s"%[type_name,evolution,"enemy" if hostile else "friendly"]
	var colour: Color = actor.materials.faction_binding.albedo_color
	check(colour.r>colour.b*1.6 if hostile else colour.b>colour.r*1.8,context+" clear team binding hue")
	check(bool(actor.materials.faction_binding.get_meta("surface_recipe").teamSurface),context+" team cloth recipe reaches shader")
	var iron: Color = actor.materials.battle_lacquer.albedo_color
	check(iron.s<.30 and iron.v<.30 and actor.materials.battle_lacquer.roughness>=.58,context+" lacquer is dark restrained iron rather than a saturated plastic uniform")
	check(actor.materials.skin.albedo_color==actor.materials.skin.get_meta("surface_recipe").colour,context+" skin recipe unaffected")
	check(actor._faction_material_name("head","cloth")=="cloth",context+" head covering retains class identity")
	check(actor._faction_material_name("torso","cloth")=="faction_cloth",context+" uniform torso receives team dye")
	check(actor._faction_material_name("thighL","cloth")=="cloth",context+" trousers retain separate natural fabric material")
	var info: Dictionary = actor.diagnostics()
	check(info.unreferencedVertices==0 and info.triangleEstimate>1000,context+" indexed original mesh intact")
	var team_vertices: int = 0
	var dark_plate_vertices: int = 0
	for mesh_node in actor.meshes:
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var recipes: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
			for index in range(colors.size()):
				var vertex_colour: Color = colors[index]
				if recipes.size()==colors.size()*4 and is_equal_approx(recipes[index*4+2],.10) and vertex_colour.v<.4:
					dark_plate_vertices+=1
				if vertex_colour.r>vertex_colour.b*1.6 if hostile else vertex_colour.b>vertex_colour.r*1.8:
					team_vertices+=1
	check(team_vertices>200,context+" real odoshi/waist/cloth team accents are baked into mesh")
	check(dark_plate_vertices>500,context+" real dark lacquer plates retain their distinct shader response")
	actor.apply_state({"animation":"attack","animationClock":.25,"attackDuration":.5,"aimX":-.7,"aimY":.7})
	check(actor.rotation.y>=-PI and actor.rotation.y<=PI,context+" safe signed attack yaw unchanged")
	actor.apply_state({"animation":"walk","animationClock":.2,"sailing":true})
	check(actor.boat.visible and not actor.bones.weapon.visible,context+" rowing state unchanged")
	actor.apply_state({"animation":"death","animationClock":.4,"sailing":true})
	check(actor.boat.visible,context+" marine death keeps hull")
	var hero = Actor.new()
	world.add_child(hero)
	hero.configure(type_name,hostile,13,true,evolution)
	check(not hero.materials.has("faction_lacquer"),context+" portrait palette remains original")
	check(hero._faction_material_name("torso","lacquer")=="lacquer",context+" hero palette not overridden")
	variants.append({"type":type_name,"evolution":evolution,"hostile":hostile,"teamVertices":team_vertices,"darkPlateVertices":dark_plate_vertices,"meshBatches":info.meshBatches,"triangles":info.triangleEstimate})
	actor.queue_free()
	hero.queue_free()
	await process_frame

func count_team_pixels(image: Image, baseline: Image, point: Vector2, friendly: bool) -> int:
	var count: int = 0
	for y in range(maxi(0,int(point.y)-65),mini(image.get_height(),int(point.y)-7)):
		for x in range(maxi(0,int(point.x)-23),mini(image.get_width(),int(point.x)+23)):
			var c: Color = image.get_pixel(x,y)
			var old: Color = baseline.get_pixel(x,y)
			if absf(c.r-old.r)+absf(c.g-old.g)+absf(c.b-old.b)<.12:
				continue
			if (c.b>c.r*1.25 and c.b>c.g*1.03 and c.b>.17) if friendly else (c.r>c.b*1.25 and c.r>c.g*1.15 and c.r>.17):
				count+=1
	return count

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
