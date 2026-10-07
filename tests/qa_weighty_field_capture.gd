extends SceneTree
## Captures a naturally scheduled paid Lv1 spear attack; no pose swaps.
const Store=preload("res://native/progress.gd")
var app: Node
var failures: Array=[]
var images: Array=[]
var observations: Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("WEIGHTY FIELD "+message)

func save_frame(label: String,unit: Dictionary) -> void:
	app.game.select_unit(int(unit.id))
	app.game._emit_state()
	app.learning_field.clear()
	app.troops_3d.sync_actor_states(app.game.actor_states())
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String="C:/JP_DF/dist/preview-weighty-field-"+label+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"GPU screenshot saves "+label)
	images.append(path)
	observations.append({"phase":label,"simulationTime":app.game.elapsed,"clock":unit.get("animationClock",0),"duration":unit.get("attackDuration",.5),"position":{"x":unit.position.x,"y":unit.position.y},"health":unit.get("hp",0),"combatState":unit.get("combatState",""),"enemyStates":app.game.snapshot().enemies})

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/weighty-field/") or DisplayServer.get_name()=="headless":
		push_error("Weighty field requires the isolated GPU profile")
		quit(2)
		return
	var fixture=Store.new()
	fixture.save_path="user://weighty-field-%d.json"%Time.get_ticks_msec()
	for map in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(map.id)]={"wins":1}
	fixture.data.settings={"music":false,"voice":false}
	check(fixture.write_save(),"Isolated visual-unlock fixture saves")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await process_frame
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	var original_supply: int=app.game.gold
	var spear_id: int=-1
	for definition in [{"type":"spear","zone":-2},{"type":"commander","zone":-1},{"type":"archer","zone":0}]:
		check(app.game.recruit(str(definition.type)),"Normal starting supply pays for "+str(definition.type))
		var candidates: Array=[]
		for index in range(app.game.zones.size()):
			if str(app.game.zones[index].get("placementRole",""))==("ranged" if definition.type=="archer" else "ground"):
				candidates.append(index)
		var index: int=candidates[int(definition.zone)] if int(definition.zone)<0 else candidates[0]
		var point: Vector2=app.game.placement_hints[index]
		check(point.x>=0 and app.game.place_unit(point.x,point.y),"Actual legal paid placement "+str(definition.type))
		if definition.type=="spear": spear_id=int(app.game.units.back().id)
	var begun: bool=false
	var captured_release: bool=false
	var last_clock: float=0.0
	for frame in range(3600):
		if begun: app.game.advance_simulation(1.0/120.0)
		else:
			for unused in range(4): app.game.advance_simulation(.025)
		app.troops_3d.sync_actor_states(app.game.actor_states())
		if frame%5==0: app.game._emit_state()
		app.learning_field.clear()
		if app.game.between_waves: app._continue_battle()
		var unit: Dictionary={}
		for candidate in app.game.units:
			if int(candidate.id)==spear_id: unit=candidate
		if not unit.is_empty() and str(unit.get("animation",""))=="attack":
			var clock: float=float(unit.animationClock)
			if not begun and clock<.10:
				begun=true
				await save_frame("preparation",unit)
			elif begun and not captured_release and clock>=.25:
				captured_release=true
				await save_frame("release",unit)
			elif captured_release and clock>=.40:
				await save_frame("recovery",unit)
				break
			if begun and clock+.001<last_clock:
				check(false,"One uninterrupted naturally scheduled attack supplies all frames")
				break
			last_clock=clock
		elif begun:
			check(false,"The attack recovery persists after impact")
			break
		if app.game.finished: break
		await process_frame
	check(images.size()==3,"All three natural engine attack phases were observed")
	var report={"images":images,"failures":failures,"observations":observations,"startingSupply":original_supply,"scope":"Paid Lv1 troops; isolated visual-unlock fixture; natural simulation attack clocks and enemy spawns, no forced animation or actor positions."}
	var file=FileAccess.open("res://tests/qa_weighty_field_capture.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("WEIGHTY_FIELD_CAPTURE ",JSON.stringify({"images":images,"failures":failures,"adapter":RenderingServer.get_video_adapter_name()}))
	app.player.stream=null
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
