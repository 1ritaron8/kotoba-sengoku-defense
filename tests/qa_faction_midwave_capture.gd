extends SceneTree
## Actual mid-wave density. Start with paid Lv1 spear+archer; all later units
## are paid from deduplicated, committed kill rewards. Original unused supply
## is held in reserve, so it cannot masquerade as earned reinforcement funds.
const Store = preload("res://native/progress.gd")
var app: Node
var checks: int = 0
var failures: Array = []
var killed_receipts: Dictionary = {}
var kill_income: int = 0
var reinforcement_spend: int = 0
var initial_reserve: int = 0
var purchases: Array = []
var samples: Array = []
var dry_run: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		push_error("MIDWAVE QA: "+note)

func observe_event(event: Dictionary) -> void:
	if str(event.get("action",event.get("type","")))!="killed":
		return
	var receipt: String=str(event.get("eventId",-1))
	if killed_receipts.has(receipt):
		return
	killed_receipts[receipt]=event.duplicate(true)
	kill_income+=maxi(0,int(event.get("reward",0)))

func placement_score(point: Vector2, zone: Dictionary, candidate: Dictionary) -> float:
	var stats: Dictionary=app.game._stats(candidate)
	if str(zone.get("placementRole",""))=="ground":
		var route_index: int=int(zone.pathIndex)
		var segment: int=int(zone.segmentIndex)
		var distance: float=app.game.ground_combat.point_distance(route_index,segment,point)
		var total: float=float(app.game.ground_combat.cumulative[route_index][-1])
		var coverage: float=1.0-absf(distance/maxf(.001,total)-.42)
		var same_route: int=0
		var archers_near: int=0
		for unit in app.game.units:
			if int(unit.get("postPathIndex",-1))==route_index:
				same_route+=1
			if unit.type=="archer" and unit.position.distance_to(point)<float(app.game._stats(unit).range):
				archers_near+=1
		return coverage*3.0/(1.0+same_route)+float(archers_near)*.45
	var score: float=0.0
	for path in app.game.paths:
		for index in range(path.points.size()-1):
			var start: Vector2=path.points[index]
			var end: Vector2=path.points[index+1]
			for sample in range(8):
				var p: Vector2=start.lerp(end,(float(sample)+.5)/8.0)
				var distance: float=point.distance_to(p)
				if distance<float(stats.range):
					score+=start.distance_to(end)*(1.0-distance/float(stats.range))*float(stats.damage)/float(stats.interval)
	return score

func buy(type_name: String, starter: bool = false) -> bool:
	var cost: int=int(app.game.recruit_catalog[type_name].get("cost",60))
	if not starter and (kill_income-reinforcement_spend<cost or app.game.gold<initial_reserve+cost):
		return false
	var before: int=app.game.gold
	if not app.game.recruit(type_name):
		return false
	var best: Vector2=Vector2(-1,-1)
	var best_score: float=-INF
	for point in app.game.placement_hints:
		if point.x<0:
			continue
		var zone: Dictionary=app.game._eligible_zone(point,type_name)
		if zone.is_empty():
			continue
		var candidate: Dictionary=app.game.pending.duplicate(true)
		candidate.position=point
		candidate.elevation=int(zone.get("elevation",0))
		var score: float=placement_score(point,zone,candidate)
		if score>best_score:
			best_score=score
			best=point
	if best.x<0 or not app.game.place_unit(best.x,best.y):
		app.game.cancel_recruit()
		return false
	var unit: Dictionary=app.game.units.back()
	check(app.game.gold==before-cost,"Actual recruit debit for "+type_name)
	check(int(unit.campaignLevel)==1,"Actual reinforcement remains untrained Lv1")
	if not starter:
		reinforcement_spend+=cost
		check(reinforcement_spend<=kill_income,"Reinforcement cost never exceeds actual deduplicated kill rewards")
		check(app.game.gold>=initial_reserve,"Original unspent starter supply remains untouched")
	purchases.append({"id":unit.id,"type":type_name,"cost":cost,"starter":starter,"wave":app.game.wave,"elapsed":app.game.elapsed,"killIncome":kill_income,"spentOnReinforcements":reinforcement_spend,"supplyAfter":app.game.gold,"legalPosition":{"x":unit.position.x,"y":unit.position.y}})
	return true

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/faction-readability/").to_lower()):
		push_error("Mid-wave QA refuses the player's profile")
		quit(2)
		return
	dry_run="--dry-run" in OS.get_cmdline_user_args()
	if not dry_run and DisplayServer.get_name()=="headless":
		quit(2)
		return
	root.size=Vector2i(1440,900)
	var fixture=Store.new()
	fixture.save_path="user://faction-midwave-%d.json"%Time.get_ticks_msec()
	# Unlocks are a declared visual fixture. Neither levels nor army money nor
	# battle supply is changed. The opening uses only the genuine starter pair.
	for map in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(map.id)]={"wins":1}
	fixture.data.settings={"music":false,"voice":false,"effects":false}
	check(fixture.write_save(),"Workspace-only visual-unlock fixture saves")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=fixture.save_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.troops_3d.set_process(false)
	app.combat_feedback.set_process(false)
	app.game.game_event.connect(observe_event)
	app._select_tier(0)
	app._select_map(0)
	app._begin_battle()
	app.game.set_process(false)
	app.player.stop()
	app.learning_field.clear()
	var original_supply: int=app.game.gold
	check(buy("archer",true),"Paid Lv1 starter archer legally placed")
	check(buy("spear",true),"Paid Lv1 starter spear legally placed")
	initial_reserve=app.game.gold
	check(original_supply-initial_reserve==125,"Only original starter costs60+65 are spent initially")
	if not dry_run:
		await create_timer(.7).timeout
	var capture: Dictionary={}
	var rotation: Array=["archer","spear","samurai","archer","naginata","spear"]
	var next_type: int=0
	var skipped_waves: Array=[]
	for frame in range(3600):
		if app.game.between_waves:
			skipped_waves.append(app.game.wave)
			app._continue_battle()
			app.learning_field.clear()
		if frame%5==0 and app.game.units.size()<int(app.game.config.get("unitLimit",14)):
			var type_name: String=rotation[next_type%rotation.size()]
			if buy(type_name):
				next_type+=1
		for step in range(6):
			app.game.advance_simulation(1.0/60.0)
			app._process(1.0/60.0)
			app.combat_feedback._process(1.0/60.0)
		app.game._emit_state()
		app.learning_field.clear()
		if not dry_run:
			app.troops_3d.sync_actor_states(app.game.actor_states())
		var active_enemies: int=0
		for enemy in app.game.enemies:
			if float(enemy.hp)>0 and app.game._enemy_visible(enemy):
				active_enemies+=1
		var living_allies: int=0
		var attacking_id: int=-1
		var melee_id: int=-1
		for unit in app.game.units:
			if float(unit.get("hp",0))>0:
				living_allies+=1
			if str(unit.get("animation",""))=="attack":
				attacking_id=int(unit.id)
				if str(unit.type) in ["spear","samurai","naginata","commander"]:
					melee_id=int(unit.id)
		var hit_visible: bool=false
		for mark in app.combat_feedback.marks:
			if str(mark.kind) in ["hit","number","charge"]:
				hit_visible=true
		var state: Dictionary=app.game.snapshot()
		if frame%50==0:
			samples.append({"elapsed":app.game.elapsed,"wave":app.game.wave,"enemies":active_enemies,"allies":living_allies,"hp":state.hp,"killIncome":kill_income,"reinforcementSpend":reinforcement_spend})
		await process_frame
		if active_enemies>=5 and living_allies>=3 and attacking_id>=0 and hit_visible and int(state.hp)>0:
			app.game.select_unit(melee_id if melee_id>=0 else attacking_id)
			app.game._emit_state()
			var image_path: String=qa_project_path("dist/preview-combat-feel.png")
			if not dry_run:
				await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(image_path)==OK,"Actual dense mid-wave GPU screenshot saves")
			capture={"path":image_path if not dry_run else "","elapsed":app.game.elapsed,"wave":app.game.wave,"activeEnemies":active_enemies,"livingAllies":living_allies,"hp":state.hp,"kills":app.game.kills,"gold":app.game.gold,"selected":app.game.snapshot().selected,"feedback":app.combat_feedback.diagnostics()}
			break
		if app.game.finished:
			break
	check(not capture.is_empty(),"Naturally earned mid-wave scene meets>=5enemies,>=3living allies, actual attack/hit, positive objectiveHP")
	check(reinforcement_spend>0 and reinforcement_spend<=kill_income,"Extra allied units are genuinely funded by kill rewards only")
	check(app.answers_correct==0,"No quiz or hint correctness rewards used")
	check(app.game.learning_supports.is_empty(),"No fabricated learning support damage aura")
	var report: Dictionary={"checks":checks,"failures":failures,"dryRun":dry_run,"capture":capture,"startingSupply":original_supply,"starterCosts":125,"reservedOriginalSupply":initial_reserve,"actualKillIncome":kill_income,"reinforcementSpend":reinforcement_spend,"killReceipts":killed_receipts.values(),"purchases":purchases,"skippedWaves":skipped_waves,"samples":samples,"finalState":app.game.snapshot(),"adapter":RenderingServer.get_video_adapter_name() if not dry_run else "headless","scope":"Actual Main with visual-only class unlock fixture. Original HP, locations, spawn numbers, route, wave and attack clocks. Starter Lv1 spear+archer paid normally; untouched original leftover funds; reinforcements paid only by committed kill rewards. Natural wave completion, actual skip callback, no quiz reward/forced pose/forced enemies. Screenshot proves density/readability, not 1x real-time campaign duration."}
	var file=FileAccess.open("user://qa_faction_midwave_capture.json",FileAccess.WRITE)
	check(file!=null,"Isolated density report opens")
	report.checks=checks
	if file!=null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("FACTION_MIDWAVE ",JSON.stringify({"checks":checks,"failures":failures,"dryRun":dry_run,"capture":capture,"killIncome":kill_income,"reinforcementSpend":reinforcement_spend}))
	if app.battle_audio!=null:
		app.battle_audio.shutdown()
	app.player.stream=null
	app.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
