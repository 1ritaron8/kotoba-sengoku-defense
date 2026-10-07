extends SceneTree
## Presentation-only fixtures verify committed metadata, never battle balance.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Troops = preload("res://native/troops_3d.gd")
const Feedback = preload("res://native/combat_feedback.gd")
const Battle = preload("res://native/game.gd")
var checks: int = 0
var failures: Array[String] = []
var observations: Array = []

class BattleStub extends Node2D:
	var selected_id: int = -1
	var field_rect: Rect2 = Rect2(0,0,1100,620)
	var speed: float = 1.0
	var paused: bool = false
	var three_d_enabled: bool = false
	var three_d_actor_scale: float = .70
	var projectiles: Array = []
	func _depth_scale(_y: float) -> float: return 1.0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		if failures.size()<25: push_error(note)

func pose(animation: String, clock: float, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"animation":animation,"animationClock":clock,"animationPhase":0.0,"aimX":0.0,"aimY":-1.0,"attackDuration":.5,"healDuration":.6}
	result.merge(extra,true)
	return result

func sole_minimum(actor: Node3D) -> float:
	var value: float = INF
	for instance in actor.meshes:
		if str(instance.get_parent().name) not in ["footL","footR"]: continue
		for surface in range(instance.mesh.get_surface_count()):
			for vertex in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				value = minf(value,(instance.global_transform*vertex).y)
	return value

func marker_count(fx: Node2D, kind: String) -> int:
	return int(fx.diagnostics().activeKinds.get(kind,0))

func event(id: int, action: String, skill_id: String = "", effect: String = "", flags: Dictionary = {}, level: int = 8) -> Dictionary:
	return {"eventId":id,"mapId":"skill-presentation-fixture","action":action,"type":action,"side":"friendly","unitType":"archer","actorId":1,"weapon":"bow","victimSide":"enemy","victimType":"shield","victimId":20,"damage":10.0,"armor":.2,"sourcePosition":{"x":.43,"y":.55},"position":{"x":.5,"y":.55},"victimPosition":{"x":.5,"y":.55},"skillId":skill_id,"skillIds":[skill_id] if not skill_id.is_empty() else [],"effectKind":effect,"flags":flags,"campaignLevel":level}

func test_effects() -> void:
	var game: BattleStub = BattleStub.new()
	root.add_child(game)
	var fx: Node2D = Feedback.new()
	fx.battle = game
	root.add_child(fx)
	fx.set_process(false)
	var id: int = 1
	for skill in ["archer_volley","archer_fire","archer_barrage","spear_pierce","spear_pair","spear_poison","gunner_pierce","gunner_reload","gunner_armor_break","samurai_armor","samurai_spear_aura","samurai_flash","naginata_sweep","naginata_guard_charge","naginata_charge_guard","commander_charge","commander_formation","commander_break"]:
		fx.reset()
		var forged: Dictionary = event(id,"hit",skill,"fire_arrow",{"fireArrow":true,"poisonTip":true,"pierce":true,"armorWeakened":true},1)
		fx.consume_event(forged)
		check(marker_count(fx,"ember")==0 and marker_count(fx,"poison")==0 and marker_count(fx,"pierce")==0 and marker_count(fx,"armor_break")==0,"Explicit Lv1 cannot show locked special effects: "+skill)
		id += 1
	fx.reset()
	fx.consume_event(event(id,"shot","","fire_arrow",{"fireArrow":true},8)); id += 1
	check(marker_count(fx,"fire_release")==0,"An unlock level or a loose flag cannot invent the fire-arrow skill")
	fx.reset()
	var fire: Dictionary = event(id,"shot","archer_fire","fire_arrow",{"fireArrow":true},5); id += 1
	fx.consume_event(fire)
	check(marker_count(fx,"fire_release")==1 and marker_count(fx,"ember")==0,"Real fire-arrow release has only a source ember, no fabricated contact")
	var duplicate_size: int = fx.marks.size()
	fx.consume_event(fire)
	check(fx.marks.size()==duplicate_size and fx.duplicate_events==1,"The committed shot receipt cannot duplicate a release")
	for spec in [["archer_fire","fire_arrow","ember",5],["spear_poison","poison_tick","poison",8],["spear_pierce","pierce","pierce",3],["gunner_pierce","pierce","pierce",3],["gunner_armor_break","armor_break","armor_break",8],["naginata_sweep","sweep","sweep",3],["samurai_flash","flash","decisive_cut",8]]:
		fx.reset()
		var hit: Dictionary = event(id,"hit",str(spec[0]),str(spec[1]),{},int(spec[3])); id += 1
		fx.consume_event(hit)
		check(marker_count(fx,str(spec[2]))==1,"Positive committed HP loss displays the exact skill contact: "+str(spec[0]))
		fx.reset(); hit.eventId=id; hit.damage=0; id += 1; fx.consume_event(hit)
		check(fx.marks.is_empty(),"No damage fabricates a contact: "+str(spec[0]))
	for spec in [["samurai_armor","guard","guard",3],["naginata_guard_charge","guard_charge","dash",5],["naginata_charge_guard","invulnerable","guard",8],["commander_formation","formation","formation",5],["commander_break","disrupt","disrupt",8]]:
		fx.reset(); fx.consume_event(event(id,"skill",str(spec[0]),str(spec[1]),{},int(spec[3]))); id += 1
		check(marker_count(fx,str(spec[2]))==1,"Actual activation creates a restrained, bounded mark: "+str(spec[0]))
	for spec in [["status_tick","archer_fire","burn_tick","ember",5],["status_tick","spear_poison","poison_tick","poison",8],["skill_hit","spear_pierce","pierce","pierce",3],["skill_hit","naginata_sweep","sweep","sweep",3],["skill_hit","archer_barrage","barrage","barrage_contact",8]]:
		fx.reset(); var committed: Dictionary=event(id,str(spec[0]),str(spec[1]),str(spec[2]),{},int(spec[4])); id+=1
		fx.consume_event(committed)
		check(marker_count(fx,str(spec[3]))==1,"Exact canonical backend action renders its real secondary/tick effect: "+str(spec[0])+str(spec[1]))
		fx.reset(); committed.eventId=id; id+=1; committed.campaignLevel=1; fx.consume_event(committed)
		check(marker_count(fx,str(spec[3]))==0,"Canonical action still refuses explicit locked-level special visual: "+str(spec[1]))
	fx.reset(); var flash: Dictionary=event(id,"hit","samurai_flash","",{"flash":true},8); id+=1; fx.consume_event(flash)
	check(marker_count(fx,"decisive_cut")==1,"True RNG flash receipt remains readable even if only actual flag+skillId arrives")
	for spec in [["gunner_armor_break","armor_break","armor_break",8],["naginata_charge_guard","invulnerable","guard",8],["commander_break","disrupt","disrupt",8]]:
		fx.reset(); var status: Dictionary=event(id,"status",str(spec[0]),str(spec[1]),{},int(spec[3])); id+=1; status.duration=1.0; fx.consume_event(status)
		check(marker_count(fx,str(spec[2]))==1,"Real committed status event uses the intended state mark: "+str(spec[0]))
	fx.reset()
	var heal: Dictionary = event(id,"heal","monk_heal","heal",{},1); id += 1
	heal.unitType="monk"; heal.victimSide="friendly"; heal.victimType="spear"; heal.healAmount=0
	fx.consume_event(heal)
	check(fx.marks.is_empty(),"Full-health/no-op healing cannot create a talisman link")
	for spec in [["monk_talisman","talisman_tick",3],["monk_victory_prayer","victory_prayer",8]]:
		fx.reset(); var advanced_heal: Dictionary=heal.duplicate(true)
		advanced_heal.merge({"eventId":id,"healAmount":2.0,"skillId":str(spec[0]),"skillIds":[spec[0]],"effectKind":str(spec[1]),"campaignLevel":int(spec[2])},true); id+=1
		fx.consume_event(advanced_heal); check(marker_count(fx,"heal")==1,"Positive actual advanced HP gain displays one support link: "+str(spec[0]))
		fx.reset(); advanced_heal.eventId=id; id+=1; advanced_heal.campaignLevel=1; fx.consume_event(advanced_heal)
		check(fx.marks.is_empty(),"Explicit Lv1 cannot invent a locked talisman/prayer: "+str(spec[0]))
	fx.reset()
	for index in range(12):
		heal.eventId=id; id += 1; heal.healAmount=7; fx.consume_event(heal)
	check(marker_count(fx,"heal")==6,"Mass support caps actual healing links at six")
	var frozen: String = JSON.stringify(fx.marks)
	game.paused=true; fx._process(.2)
	check(JSON.stringify(fx.marks)==frozen,"Explicit battle pause freezes all new skill marks")
	game.paused=false; fx.paused=true; fx._process(.2)
	check(JSON.stringify(fx.marks)==frozen,"Learning/menu pause freezes support and status effects")
	fx.paused=false
	for index in range(9): fx._process(.25)
	check(fx.marks.is_empty(),"Support links expire completely rather than becoming an always-on aura")
	fx.reset()
	for index in range(1000): fx.consume_event(event(id+index,"hit","archer_fire","fire_arrow",{"fireArrow":true},8))
	check(fx.marks.size()<=96 and fx._seen_events.size()<=512,"Special-effect bursts preserve particle and receipt-history ceilings")
	fx.reset(); check(fx.diagnostics().activeMarks==0,"New map/reset clears every effect")
	observations.append({"feedback":fx.diagnostics(),"healLinkCap":fx.MAX_HEAL_LINKS})
	fx.free(); game.free()

func test_backend_bridge() -> void:
	# This controlled component fixture isolates real native APIs and receipts;
	# gold/unlocks/HP are not evidence about ordinary campaign difficulty.
	var game: Node2D=Battle.new(); root.add_child(game); game.set_process(false)
	var catalog: Array=(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")) as Dictionary).get("units",[])
	game.configure_roster(catalog,["archer","spear","samurai","gunner","naginata","monk","commander","ninja"],{"archer":8,"spear":8,"samurai":8,"gunner":8,"naginata":8,"monk":8,"commander":8,"ninja":8})
	var map: Dictionary={"id":"skill-renderer-component","theme":"farm","stageNumber":20,"initialGold":4000,"unitLimit":14,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.68,"r":.18,"elevation":1}],"tactics":{"groundPosts":[{"id":"road","nameKo":"전선","pathIndex":0,"segmentIndex":0,"t":.55,"r":.22,"guardRadius":.2,"mobilityFactor":1.0}]}}
	game.load_map(map,20); game.start_battle(); game.spawn_queue=["raider"]; game.spawn_clock=100000
	var fx: Node2D=Feedback.new(); fx.battle=game; root.add_child(fx); fx.set_process(false)
	var receipts: Array=[]
	game.game_event.connect(func(value: Dictionary): receipts.append(value.duplicate(true)); fx.consume_event(value))
	var first_id: int=game.next_id
	var budget_before: int=int(game.gold)
	check(game.begin_placement("spear",0),"Native skill fixture queues paid spear with current progression")
	var paid: bool=game.pending.is_empty() and int(game.gold)<budget_before and not game.recruitment_queue.is_empty()
	for hint in game.placement_hints:
		if bool(game.placement_preview(hint).get("valid",false)):
			paid=game.place_unit(hint.x,hint.y); if paid: break
	check(paid,"Native skill fixture pays through the current marching-dispatch or placement contract")
	for count in range(200):
		if game.recruitment_queue.is_empty(): break
		game.advance_simulation(.025)
	var spear: Dictionary={}
	for unit in game.units:
		if int(unit.id)==first_id: spear=unit
	check(not spear.is_empty(),"Paid spear arrives through actual recruitment queue")
	if spear.is_empty(): fx.free(); game.free(); return
	var enemy: Dictionary=game._spawn_enemy("enemy_samurai",1,{"pathIndex":0})
	check(not enemy.is_empty(),"Actual enemy_samurai uses native enemy budget/model identity")
	var source: Dictionary={"id":spear.id,"type":"spear","position":spear.position,"campaignLevel":8}
	var before_hp: float=float(enemy.hp)
	game._damage_enemy(enemy,5.0,"spear",source)
	check(float(enemy.hp)<before_hp and bool(game.unit_skills.enemy_state(enemy).flags.poisoned),"Actual HP loss applies native poison and public status")
	var status_receipt: bool=false
	for value in receipts:
		if str(value.type)=="status" and str(value.get("skillId",""))=="spear_poison": status_receipt=true
	check(status_receipt,"Actual poison status crosses Game event boundary")
	fx.reset(); receipts.clear()
	game.unit_skills.clock+=.51
	game.unit_skills._tick_enemy_statuses(enemy)
	var tick_receipt: bool=false
	for value in receipts:
		if str(value.type)=="status_tick" and float(value.get("damage",0))>0: tick_receipt=true
	check(tick_receipt and marker_count(fx,"poison")>0,"Real native positive DOT tick reaches feedback without fabricating a projectile")
	# A controlled native healing fixture changes actual HP first, then observes
	# real helper receipts, actor state metadata and presentation-only pose.
	var monk: Dictionary={"id":777,"type":"monk","position":spear.position+Vector2(.02,0),"aim":Vector2(0,-1),"evolution":2,"campaignLevel":8,"animation":"idle","animationClock":0.0,"hp":30.0,"maxHp":30.0}
	game.unit_skills.initialize_unit(monk); game.units.append(monk)
	spear.hp=maxf(1,float(spear.maxHp)-10)
	fx.reset(); receipts.clear(); var before_heal: float=float(spear.hp)
	var actual_heal: float=game.unit_skills._heal(monk,spear,6.0,"monk_heal","heal")
	check(actual_heal>0 and float(spear.hp)==before_heal+actual_heal and marker_count(fx,"heal")==1,"Real helper HP gain/event creates exactly one warm support link")
	var monk_state: Dictionary={}
	var enemy_state: Dictionary={}
	for value in game.actor_states():
		if int(value.id)==777 and bool(value.friendly): monk_state=value
		elif int(value.id)==int(enemy.id) and not bool(value.friendly): enemy_state=value
	check(bool(monk_state.get("healing",false)) and str(monk_state.get("animation",""))=="heal" and float(monk_state.get("healDuration",0))>0,"Actual healing snapshot carries pose/duration/active flag")
	check(str(enemy_state.get("type",""))=="enemy_samurai" and bool(enemy_state.get("flags",{}).get("poisoned",false)),"Native hostile samurai/status snapshot preserves renderer contract")
	var renderer: Control=Troops.new(); root.add_child(renderer); renderer.set_process(false)
	var terrain: Dictionary=(JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")) as Array)[0]
	renderer.set_stage(terrain); renderer.sync_actor_states([monk_state,enemy_state])
	check(renderer.actors.has("777:0") and str(renderer.actors["777:0"].motion_debug.mode)=="heal","Native backend healing state reaches the original articulated support stance")
	var enemy_key: String=str(enemy.id)+":0"
	check(renderer.actors.has(enemy_key) and renderer.actors[enemy_key].unit_type=="samurai" and renderer.actors[enemy_key].hostile,"Actual hostile samurai keeps red faction while reusing samurai mesh")
	fx.troop_renderer=renderer; game.three_d_enabled=true; game.field_rect=Rect2(0,0,1100,620)
	var contact: Vector2=Vector2(.5,.5)
	var mounted: Vector2=fx._body(contact,{"victimType":"enemy_cavalry","victimSide":"enemy"})
	var footed: Vector2=fx._body(contact,{"victimType":"enemy_samurai","victimSide":"enemy"})
	check(mounted.y<footed.y-5,"Actual enemy cavalry feedback projects to the rider rather than pedestrian waist")
	observations.append({"backendReceipts":receipts,"nativeMonkState":monk_state,"nativeEnemyState":enemy_state})
	renderer.free(); fx.free(); game.free()

func test_poses() -> void:
	for type_name in ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]:
		for evolution in range(3):
			var actor: Node3D = Actor.new(); root.add_child(actor); actor.configure(type_name,false,7,false,evolution)
			var batches: int = actor.diagnostics().meshBatches
			actor.apply_state(pose("idle",0))
			check(actor.scale.is_equal_approx(Vector3.ONE),"Actor rig/approved portrait base stays unchanged: "+type_name+str(evolution))
			if type_name=="monk":
				actor.apply_state(pose("idle",.3))
				var guard: Transform3D = actor.bones.weapon.global_transform
				actor.apply_state(pose("attack",.3))
				check(str(actor.motion_debug.mode)=="idle" and actor.bones.weapon.global_transform.is_equal_approx(guard),"Legacy monk attack cannot swing or fabricate healing")
				var last: Vector3 = actor.bones.handL.global_position
				var largest_step: float = 0.0
				for frame in range(61):
					actor.apply_state(pose("heal",float(frame)/60*.6,{"healing":true}))
					var hand: Vector3 = actor.bones.handL.global_position
					largest_step=maxf(largest_step,hand.distance_to(last)); last=hand
					check(actor.rig.position.is_finite() and hand.is_finite(),"Support whole-body/hand transforms remain finite")
					check(sole_minimum(actor)>=-.0005,"Support action keeps both actual shoe meshes above ground")
					check(actor.bones.weapon.global_basis.y.normalized().y>.98,"Offering retains a vertical staff without an attack sweep")
				check(largest_step<.045,"Support hand moves continuously instead of snapping")
				actor.apply_state(pose("walk",.2,{"healing":true})); check(str(actor.motion_debug.mode)=="walk","Retreat/walk remains locomotion even if a stale heal flag survives")
				actor.apply_state(pose("death",.2,{"healing":true})); check(str(actor.motion_debug.mode)=="death","Death always overrides support")
				actor.apply_state(pose("idle",.2,{"healing":true,"sailing":true})); check(str(actor.motion_debug.mode)=="rowing","Sailing remains rowing rather than healing on deck")
			elif type_name=="naginata":
				var ordinary: float = actor.bones.weapon.global_basis.y.normalized().y
				actor.apply_state(pose("idle",0,{"supportState":"guard"}))
				check(actor.bones.weapon.global_basis.y.normalized().y>ordinary+.10,"Guard visibly holds the blade higher at rest")
				actor.apply_state(pose("attack",.25,{"supportState":"guard"}))
				check(str(actor.motion_debug.mode)=="attack" and is_equal_approx(float(actor.motion_debug.drive),1.0),"Guard preserves its existing real attack impact frame")
			check(actor.diagnostics().meshBatches==batches,"Skills add no 3D model draw batches: "+type_name+str(evolution))
			actor.free()

func test_renderer() -> void:
	var renderer: Control = Troops.new(); root.add_child(renderer); renderer.set_process(false)
	var map: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")) as Array)[0]
	renderer.set_stage(map)
	var ordinary: float = renderer.render_scale_for(Vector2(.5,.5),{"type":"spear","friendly":true})
	var samurai: float = renderer.render_scale_for(Vector2(.5,.5),{"type":"samurai","friendly":true})
	check(is_equal_approx(samurai/ordinary,1.07),"Only samurai gets the approved seven-percent body-scale difference")
	for type_name in ["archer","gunner","naginata","monk","commander","ninja"]:
		check(is_equal_approx(renderer.render_scale_for(Vector2(.5,.5),{"type":type_name,"friendly":true}),ordinary),"Other bodies, mounted horse and weapons keep their original parent scale: "+type_name)
	var base: Dictionary = {"id":1,"type":"spear","friendly":true,"x":.5,"y":.5,"aimX":0.0,"aimY":-1.0,"animation":"idle","animationClock":0.0,"motionTime":0.0,"campaignLevel":1,"skillIds":[],"flags":{}}
	renderer.sync_actor_states([base])
	check(not renderer.side_markers[0].has("poisonTipPoint") and not renderer.side_markers[0].has("statusPoint"),"Basic Lv1 renders no unlocked/status ornament")
	base.flags={"poisonTip":true}; renderer.sync_actor_states([base])
	check(not renderer.side_markers[0].has("poisonTipPoint"),"Loose poison flag without actual skill receipt cannot tint a weapon")
	base.campaignLevel=8; base.skillIds=["spear_poison"]; renderer.sync_actor_states([base])
	check(renderer.side_markers[0].has("poisonTipPoint") and renderer.side_markers[0].poisonTipPoint.is_finite(),"Actual unlocked poison coats the real articulated weapon tip")
	base.flags={"poisoned":true,"burning":true,"armorWeakened":true,"invulnerable":true}; renderer.sync_actor_states([base])
	check(renderer.side_markers[0].statusFlags.size()==4,"Only actual public status flags add the four small state markers")
	base.animation="death"; base.dead=true; renderer.sync_actor_states([base])
	check(renderer.side_markers.is_empty(),"Death removes faction/status/weapon markers immediately")
	base.animation="idle"; base.dead=false; base.sailing=true; renderer.sync_actor_states([base])
	check(not renderer.side_markers[0].has("statusPoint"),"Sailing suppresses land skill markers")
	base.type="samurai"; base.sailing=false; base.flags={}; renderer.sync_actor_states([base])
	var actual_actor: Node3D = renderer.actors["1:0"]
	check(actual_actor.scale.is_equal_approx(renderer.contact_shadows["1:0"].scale),"Samurai contact shadow uses the same new body scale")
	renderer.sync_placement_preview({"active":true,"visible":true,"type":"samurai","evolution":0,"position":{"x":.5,"y":.5}})
	check(renderer.placement_actor.scale.is_equal_approx(actual_actor.scale),"Free preview remains the exact committed samurai model scale")
	check(renderer.actors.size()==1 and renderer.side_markers.size()==1,"Preview never joins combat actors or markers")
	var state_before: String=JSON.stringify(base)
	renderer.sync_actor_states([base]); check(JSON.stringify(base)==state_before,"Renderer never mutates HP/mana/flags/paid or simulation coordinates")
	renderer.sync_actor_states([]); check(renderer.side_markers.is_empty() and renderer.actors.is_empty(),"Removed actors clean all presentation markers")
	renderer.sync_placement_preview({}); check(not renderer.placement_actor.visible,"Cancel/reset hides the preview as before")
	observations.append({"ordinaryScale":ordinary,"samuraiScale":samurai,"renderer":renderer.diagnostics()})
	renderer.free()

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/unit-skill-visual/").to_lower()):
		push_error("Skill presentation QA refuses a player profile"); quit(2); return
	test_effects(); test_poses(); test_renderer(); test_backend_bridge()
	await process_frame
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"gpuExecuted":false,"scope":"CPU presentation fixtures: eight original classes and 24 evolution mesh batches, actual shoe/hand poses, public skill receipts/statuses, explicit low-level denial, precise samurai/ghost/shadow scale, event deduplication and bounded expiry/pause/reset. A controlled real-Game fixture verifies paid recruitment, native poison HP/status/tick, actual healing HP/event/actor state and hostile-samurai/support-model binding. Fixture gold/unlocks/manual injury/source calls isolate component boundaries; they are not campaign difficulty or GPU-quality evidence."}
	var file: FileAccess = FileAccess.open("user://qa_unit_skill_visuals.json",FileAccess.WRITE)
	if file==null: check(false,"Isolated report is writable")
	else: file.store_string(JSON.stringify(report,"  ")); file.close()
	print("UNIT_SKILL_VISUAL_QA ",JSON.stringify({"checks":checks,"failures":failures,"gpuExecuted":false}))
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
