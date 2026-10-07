extends SceneTree
## Actual Game convoy marker and Troops3D scene; no convoy art is faked here.
const Game=preload("res://native/game.gd")
const Troops=preload("res://native/troops_3d.gd")
var checks: int=0
var failures: Array=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label);push_error(label)
func run() -> void:
	var allowed: String="c:/jp_df/tests/profiles/casual-actor-materials/"
	for name in ["APPDATA","LOCALAPPDATA"]:
		if not OS.get_environment(name).replace("\\","/").to_lower().begins_with(allowed): quit(2);return
	if DisplayServer.get_name()=="headless" or OS.get_environment("JP_CASUAL_DUMMY_AUDIO")!="1" or not ProjectSettings.globalize_path("user://").replace("\\","/").to_lower().begins_with(allowed): quit(2);return
	root.size=Vector2i(1440,900)
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-rendered/manifest.json"))
	var expected_art: Dictionary={}
	for entry in manifest.get("stages",[]):
		if str(entry.get("stageId",""))==str(maps[5].id): expected_art=entry.duplicate(true);break
	check(not expected_art.is_empty() and str(expected_art.get("artDirection","")).to_lower().contains("casual"),"Approved casual stage6 artwork is registered before actual Game starts")
	var field: Control=Control.new()
	root.add_child(field)
	field.position=Vector2(16,64)
	var game=Game.new()
	root.add_child(game)
	game.set_process(false)
	game.three_d_enabled=bool(ProjectSettings.get_setting("application/config/use_3d_units",false))
	check(game.three_d_enabled,"Actual Main 3D rendering flag is applied before map loading")
	game.set_field_rect(Rect2(Vector2(16,64),Vector2(1408,784)))
	var troops=Troops.new()
	field.add_child(troops)
	await process_frame
	troops.set_process(false)
	troops.bind_battle(game)
	troops.set_field_size(Vector2(1408,784))
	game.load_map(maps[5],10)
	troops.set_stage(maps[5])
	game.start_battle()
	for tick in range(720):
		game.advance_simulation(1.0/60.0)
		if tick%12==0: troops.sync_actor_states(game.actor_states());await process_frame
	troops.sync_actor_states(game.actor_states())
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var shot: Image=root.get_texture().get_image()
	check(shot.save_png("user://actual-convoy-cart.png")==OK,"Actual convoy scene saves")
	check(troops.mobile_objectives.size()==1,"Actual source convoy has exactly one 3D mobile cart")
	var cart: Node3D=troops.mobile_objectives.values()[0]
	var anchor: Vector2=troops.get_global_transform_with_canvas()*troops.camera.unproject_position(cart.position)
	var region: Rect2i=Rect2i(Vector2i(anchor)-Vector2i(100,145),Vector2i(200,185)).intersection(Rect2i(Vector2i.ZERO,shot.get_size()))
	check(shot.get_region(region).save_png("user://actual-convoy-cart-crop.png")==OK,"Unretouched actual cart source pixels save")
	check(cart.wheel_distance>0.0 and cart.wheels.size()==2,"Real convoy movement visibly rolls both wheels")
	check(not game.finished and game.units.is_empty(),"Native clock and existing objective run with no army/HP injection")
	# Observe the actual visible cart pixels at the unchanged combat time.
	# The hidden diagnostic frame is not a gameplay state or saved illustration.
	cart.hide()
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var hidden: Image=root.get_texture().get_image()
	var visible_cart_pixels: int=0
	for row in range(region.position.y,region.end.y):
		for column in range(region.position.x,region.end.x):
			var first: Color=shot.get_pixel(column,row)
			var second: Color=hidden.get_pixel(column,row)
			if absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)>.08: visible_cart_pixels+=1
	check(visible_cart_pixels>50,"Actual cart has visible source pixels above the battlefield artwork and below its objective label")
	cart.show()
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for frame in range(4): await process_frame
	var shadow_modes: Array=[]
	for piece in cart.pieces:
		shadow_modes.append(piece.cast_shadow)
		piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var shadow_off: Image=root.get_texture().get_image()
	var real_shadow_pixels: int=0
	for row in range(region.position.y,region.end.y):
		for column in range(region.position.x,region.end.x):
			var first: Color=shot.get_pixel(column,row)
			var second: Color=shadow_off.get_pixel(column,row)
			if absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)>.035: real_shadow_pixels+=1
	check(real_shadow_pixels>5,"Actual cart caster changes local sun-shadow pixels at the frozen real convoy position")
	for index in range(cart.pieces.size()): cart.pieces[index].cast_shadow=shadow_modes[index]
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	for frame in range(4): await process_frame
	var layer_contract: Dictionary=troops.battlefield.render_layer_contract()
	check(str(layer_contract.get("artPath",""))==str(expected_art.get("path","")),"Actual stage6 uses its registered approved casual artwork")
	check(str(layer_contract.get("artSha256",""))==str(expected_art.get("sha256","")),"Actual stage6 uses the precise reviewed art revision")
	var actual_marker: Dictionary={}
	for marker in game.field_markers():
		if bool(marker.get("mobile",false)) and str(marker.get("id",""))==cart.marker_id: actual_marker=marker;break
	check(not actual_marker.is_empty() and cart.position.distance_to(troops.normalized_to_world(Vector2(float(actual_marker.get("x",0.0)),float(actual_marker.get("y",0.0)))))<.00001,"Actual cart remains centered on the real moving objective anchor")
	var report: Dictionary={"checks":checks,"failures":failures,"game":game.snapshot(),"marker":game.field_markers(),"cart":cart.diagnostics(),"render":troops.diagnostics(),"layerContract":layer_contract,"expectedArt":expected_art,"anchor":anchor,"visibleCartPixels":visible_cart_pixels,"realShadowPixels":real_shadow_pixels,"scope":"Actual Game stage6 at12s plus Troops3D render on its approved casual artwork with Main's actual 3D rendering flag. This is a renderer diagnostic scene, with the actual mobile objective anchor, height, rotation and wheel spin; no army, HP, income or navigation state is injected, and this is not a Main UI or battle balance completion test."}
	var file: FileAccess=FileAccess.open("user://actual-convoy-cart.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  "));file.close()
	print("MOBILE_OBJECTIVE_CART_GPU ",JSON.stringify({"checks":checks,"failures":failures}))
	game.queue_free();field.queue_free()
	await process_frame
	Troops.Battlefield.release_shared_resources()
	await create_timer(.1).timeout
	quit(0 if failures.is_empty() else 1)
