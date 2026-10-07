extends SceneTree
## Fixed genuine battle: original funds pay for three Lv1 troops. No edited
## HP/positions/spawns/rewards. Class unlocks and hidden learning banner are
## explicitly visual fixtures. Seed, paid posts and sixteen simulated seconds
## match; the separately revised wave curve may change hostile composition.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var captures: Array = []
var variant: String = "before"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		push_error("PREMIUM BATTLE: "+note)

func run() -> void:
	variant = "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/premium-models/") or DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size=Vector2i(1440,900)
	var fixture=Store.new()
	fixture.save_path="user://premium-battle.json"
	for stage in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(stage.id)]={"wins":1}
	fixture.data.settings={"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Isolated visual unlock fixture stores")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.combat_feedback.set_process(false)
	app.troops_3d.set_process(false)
	app.player.stop()
	for stage_info in [{"index":0,"name":"forest"},{"index":8,"name":"night"}]:
		app._select_tier(0)
		app._select_map(int(stage_info.index))
		app.game.set_seed(42)
		app._begin_battle()
		app.game.set_process(false)
		app.learning_field.clear()
		var start: int=app.game.gold
		var paid: Array=[]
		for type_name in ["spear","commander","archer"]:
			var cost: int=int(app.game.recruit_catalog[type_name].cost)
			check(app.game.recruit(type_name),"Original funds recruit "+type_name)
			var chosen: Vector2=Vector2(-1,-1)
			var best: float=INF
			for point in app.game.placement_hints:
				if point.x<0: continue
				var score: float=point.distance_to(app.game.paths[0].points[mini(2,app.game.paths[0].points.size()-1)])
				if score<best:
					best=score
					chosen=point
			check(chosen.x>=0 and app.game.place_unit(chosen.x,chosen.y),"Actual legal post "+type_name)
			paid.append({"type":type_name,"cost":cost,"position":{"x":chosen.x,"y":chosen.y}})
		check(app.game.gold==start-int(paid[0].cost)-int(paid[1].cost)-int(paid[2].cost),"Exact initial supply paid")
		# 16 genuine combat seconds; all game/feedback ticks share the same dt.
		for tick in range(960):
			if app.game.between_waves:
				app._continue_battle()
			app.game.advance_simulation(1.0/60.0)
			app._process(1.0/60.0)
			app.combat_feedback._process(1.0/60.0)
			app.learning_field.clear()
			if tick%6==0:
				app.troops_3d.sync_actor_states(app.game.actor_states())
				await process_frame
		app.game.select_unit(int(app.game.units[0].id))
		app.game._emit_state()
		app.troops_3d.sync_actor_states(app.game.actor_states())
		app.learning_field.clear()
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var path: String="C:/JP_DF/dist/premium-"+variant+"-"+stage_info.name+".png"
		check(root.get_texture().get_image().save_png(path)==OK,"Actual battlefield image saves")
		check(int(app.combat_feedback.event_counts.get("hit",0))>0,"Genuine combat produced damage events")
		check(not app.game.finished and int(app.game.snapshot().hp)>0,"Objective still alive at fixed time")
		var states: Array=app.game.actor_states()
		captures.append({"path":path,"stageId":app.current_map.id,"seed":42,"simulationTicks":960,"startingSupply":start,"paid":paid,"elapsed":app.game.elapsed,"wave":app.game.wave,"gold":app.game.gold,"hp":app.game.snapshot().hp,"kills":app.game.kills,"enemies":app.game.enemies.size(),"actorStates":states,"render":app.troops_3d.diagnostics(),"feedback":app.combat_feedback.diagnostics()})
		if variant=="after":
			# A second explicitly unmatched-time shot proves genuine close combat
			# after the wave-curve revision; no extra units/rewards are injected.
			var contact_saved: bool=false
			for tick in range(2400):
				if app.game.between_waves: app._continue_battle()
				app.game.advance_simulation(1.0/60.0)
				app._process(1.0/60.0)
				app.combat_feedback._process(1.0/60.0)
				app.learning_field.clear()
				if tick%6!=0: continue
				app.troops_3d.sync_actor_states(app.game.actor_states())
				await process_frame
				if app.game.enemies.size()>=3 and not app.combat_feedback.marks.is_empty() and int(app.combat_feedback.event_counts.get("hit",0))>0:
					app.game._emit_state()
					await process_frame
					await RenderingServer.frame_post_draw
					var contact_path: String="C:/JP_DF/dist/premium-after-"+stage_info.name+"-contact.png"
					check(root.get_texture().get_image().save_png(contact_path)==OK,"Natural revised-curve engagement captures")
					captures.append({"path":contact_path,"stageId":app.current_map.id,"comparison":"Additional natural contact, not a matched-time before-after image","startingSupply":start,"paid":paid,"elapsed":app.game.elapsed,"wave":app.game.wave,"gold":app.game.gold,"hp":app.game.snapshot().hp,"kills":app.game.kills,"enemies":app.game.enemies.size(),"actorStates":app.game.actor_states(),"render":app.troops_3d.diagnostics(),"feedback":app.combat_feedback.diagnostics()})
					contact_saved=true
					break
				if app.game.finished: break
			check(contact_saved,"Natural nonempty fight shown under revised wave curve")
	var result: Dictionary={"variant":variant,"checks":checks,"failures":failures,"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Fixed seed42, three Lv1 units paid270 from the actual per-stage starting supply, 960 real game ticks; visual unlock-only profile and hidden banner. No gameplay mutation. The independently revised wave curve can change enemy composition between versions; this is a matched setup/time visual comparison, not an identical combat-state comparison."}
	var file=FileAccess.open("user://qa_premium_models_"+variant+".json",FileAccess.WRITE)
	check(file!=null,"Isolated report opens")
	result.checks=checks
	if file!=null:
		file.store_string(JSON.stringify(result,"  "))
		file.close()
	print("PREMIUM_FIXED_BATTLE ",JSON.stringify({"variant":variant,"checks":checks,"failures":failures,"captures":captures.size()}))
	app.player.stream=null
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
