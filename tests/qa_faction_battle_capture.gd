extends SceneTree
## Paid Lv1 troops, genuine engine spawns and natural combat clocks. Only
## class unlocks are a rendering fixture; no extra supply, HP, damage or pose.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var captures: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		push_error("FACTION BATTLE: "+note)

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/faction-readability/") or DisplayServer.get_name()=="headless":
		push_error("Faction battlefield capture requires isolated GPU profile")
		quit(2)
		return
	root.size=Vector2i(1440,900)
	var fixture=Store.new()
	fixture.save_path="user://faction-battle-%d.json"%Time.get_ticks_msec()
	for map in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(map.id)]={"wins":1}
	fixture.data.settings={"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Isolated unlock fixture stores")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.combat_feedback.set_process(false)
	app.player.stop()
	for map_info in [{"index":0,"name":"forest"},{"index":4,"name":"harbor"},{"index":8,"name":"night"}]:
		app._select_tier(0)
		app._select_map(int(map_info.index))
		app._begin_battle()
		app.game.set_process(false)
		app.learning_field.clear()
		var starting_supply: int=app.game.gold
		var paid: Array=[]
		for type_name in ["spear","commander","archer"]:
			var price: int=int(app.game.recruit_catalog[type_name].get("cost",60))
			check(app.game.recruit(type_name),"Initial supply recruits "+map_info.name+"/"+type_name)
			var chosen: Vector2=Vector2(-1,-1)
			var best: float=INF
			for point in app.game.placement_hints:
				if point.x<0:
					continue
				# Choose the valid position nearest the first approach route.
				var score: float=point.distance_to(app.game.paths[0].points[mini(2,app.game.paths[0].points.size()-1)])
				if score<best:
					best=score
					chosen=point
			check(chosen.x>=0 and app.game.place_unit(chosen.x,chosen.y),"Legal actual post placement "+map_info.name+"/"+type_name)
			paid.append({"type":type_name,"cost":price,"position":{"x":chosen.x,"y":chosen.y}})
		check(app.game.gold==starting_supply-int(paid[0].cost)-int(paid[1].cost)-int(paid[2].cost),"No invented supply for "+map_info.name)
		await create_timer(.7).timeout
		var captured: bool=false
		for frame in range(700):
			for step in range(6):
				app.game.advance_simulation(1.0/60.0)
				app._process(1.0/60.0)
				app.combat_feedback._process(1.0/60.0)
			app.troops_3d.sync_actor_states(app.game.actor_states())
			app.game._emit_state()
			app.learning_field.clear()
			if app.game.between_waves:
				app._continue_battle()
				app.learning_field.clear()
			var fighting: bool=false
			var selected: int=-1
			for unit in app.game.units:
				if str(unit.get("animation",""))=="attack" and str(unit.type) in ["spear","commander"]:
					fighting=true
					selected=int(unit.id)
			await process_frame
			if fighting and app.game.enemies.size()>=2 and int(app.combat_feedback.event_counts.get("hit",0))>0 and not app.combat_feedback.marks.is_empty():
				app.game.select_unit(selected)
				app.game._emit_state()
				await process_frame
				await RenderingServer.frame_post_draw
				var image: Image=root.get_texture().get_image()
				var path: String="C:/JP_DF/dist/preview-faction-battle-"+map_info.name+".png"
				check(image.save_png(path)==OK,"Natural engagement GPU capture saves "+map_info.name)
				var living: int=0
				for state in app.game.actor_states():
					if not bool(state.dead): living+=1
				check(app.troops_3d.side_markers.size()==living,"Actual living actor count equals side glyph count")
				check(app.combat_feedback.marks.size()<=96,"Actual feedback remains bounded")
				captures.append({"path":path,"stageId":app.current_map.id,"startingSupply":starting_supply,"paid":paid,"elapsed":app.game.elapsed,"wave":app.game.wave,"enemies":app.game.enemies.size(),"kills":app.game.kills,"selected":app.game.snapshot().selected,"render":app.troops_3d.diagnostics(),"feedback":app.combat_feedback.diagnostics()})
				captured=true
				break
			if app.game.finished:
				break
		check(captured,"Naturally spawned hostile meets actual paid friendly in "+map_info.name)
	var report: Dictionary={"checks":checks,"failures":failures,"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Visual-unlock-only fixture; paid Lv1 troops with original initial supply and natural spawns, paths, HP, attacks, animation clocks and damage. Learning banner hidden for capture only."}
	var file=FileAccess.open("user://qa_faction_battle_capture.json",FileAccess.WRITE)
	check(file!=null,"Isolated battle report opens")
	report.checks=checks
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("FACTION_BATTLE_GPU ",JSON.stringify({"checks":checks,"failures":failures,"captures":captures.size(),"gpu":RenderingServer.get_video_adapter_name()}))
	app.player.stream=null
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
