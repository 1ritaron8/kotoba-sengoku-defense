extends SceneTree
## CPU semantic differential fixture only. HQ executes; no save/UI/GPU/FPS claim.
## Immutable original Game/Skills/Ground/Crowd are the oracle, not copied formulas.
const Battle = preload("res://native/game.gd")
const BeforeBattle = preload("res://tests/profiles/painted-perf-04/source-before/game.gd")
const BeforeSkills = preload("res://tests/profiles/painted-perf-04/source-before/unit_skills.gd")
const BeforeGround = preload("res://tests/profiles/painted-perf-04/source-before/ground_combat.gd")
const BeforeCrowd = preload("res://tests/profiles/painted-perf-04/source-before/crowd_melee.gd")
const Renderer = preload("res://native/painted_actor_renderer.gd")
const BeforeRenderer = preload("res://tests/profiles/painted-perf-04/source-before/painted_actor_renderer.gd")
const OUTPUT = "res://tests/profiles/painted-perf-04"
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var game: Node2D
var original: Node2D
var catalog: Array = []
var failures: Array = []
var rows: Array = []
var checks: int = 0
var started: int = 0
var sources: Dictionary = {}
var stopped: bool = false
var production_events: Array = []
var next_fixture_id: int = 1000
var fixture_valid: bool = true
var scoped_restore: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label_value: String, detail: Dictionary = {}) -> bool:
	checks += 1
	if not ok:
		failures.append({"check":label_value,"detail":detail})
		if failures.size() <= 20: push_error("PERF04 " + label_value)
	return ok

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b)) <= .00001*maxf(1.0,absf(float(b)))
	if a is Vector2 and b is Vector2:
		return a == b if not a.is_finite() or not b.is_finite() else a.distance_to(b) <= .000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in b:
			if not a.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in range(a.size()):
			if not equivalent(a[index],b[index]): return false
		return true
	return a == b

func compare(a: Variant, b: Variant, label_value: String) -> void:
	check(equivalent(a,b),label_value,{"current":a,"original":b} if not equivalent(a,b) else {})

func hashes() -> Dictionary:
	var result: Dictionary = {}
	for directory in ["res://native",OUTPUT+"/source-before"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.get_extension() in ["gd","json"]:
				var path: String = directory.path_join(filename)
				result[path] = FileAccess.get_sha256(path)
	for path in ["res://project.godot","res://tests/qa_painted_perf04.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func fixture() -> Dictionary:
	return {"id":"perf04-semantic-fixture","theme":"farm","stageNumber":20,"initialGold":100000,"trainingOnly":true,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]},{"id":"other","objectiveId":"main","points":[{"x":.05,"y":.35},{"x":.95,"y":.35}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.68,"r":.16,"elevation":1}],"tactics":{"groundPosts":[{"id":"road","pathIndex":0,"segmentIndex":0,"t":.55,"r":.19,"guardRadius":.2}]}}

func setup() -> void:
	game = Battle.new()
	original = BeforeBattle.new()
	# The saved Game preloads live paths. Explicitly replace every changed oracle
	# component with its immutable original before either battle is configured.
	original.unit_skills = BeforeSkills.new()
	original.ground_combat = BeforeGround.new()
	original.ground_combat.crowd = BeforeCrowd.new()
	for value in [game,original]:
		root.add_child(value)
		value.set_process(false)
		value.hide()
		value.configure_roster(catalog,TYPES,{})
		value.load_map(fixture(),10)
		value.set_seed(4004)
		value.start_battle()
		value.spawn_queue.clear()
		value.spawn_source_waves.clear()
		value.spawn_metadata.clear()
		value.spawn_clock = 100000.0
	game.game_event.connect(func(event: Dictionary):
		if str(event.get("type","")) in ["recruitment_queued","recruited","placed"]: production_events.append(event.duplicate(true)))
	for type_name in TYPES:
		var template: Dictionary = game._deployment_template(str(type_name))
		if not check(not template.is_empty() and str(template.get("type",""))==str(type_name) and template.has("definition"),"Fixture has a complete unlocked template: "+str(type_name)):
			fixture_valid = false

func sync_oracle() -> void:
	# Read-only oracle queries see exactly the current supported battle inputs.
	# No native optimization/index invalidation method is called by this test.
	for property in ["config","units","enemies","paths","zones","recruit_catalog","unlocked_roster","campaign_levels","roster_configured","elapsed","storm_active","learning_supports","bridge_index","running","paused","between_waves","finished","battle_closed"]:
		original.set(property,game.get(property))
	original.unit_skills.clock = game.unit_skills.clock
	original.unit_skills.generation = game.unit_skills.generation
	original.rng.state = game.rng.state

func actor(type_name: String, level_value: int, point: Vector2, lane: int = 0) -> Dictionary:
	var value: Dictionary = game._deployment_template(type_name)
	if not check(not value.is_empty() and str(value.get("type",""))==type_name and value.has("definition"),"Actor construction starts with a complete native template: "+type_name):
		fixture_valid = false
		return {}
	value.merge({"id":next_fixture_id,"campaignLevel":level_value,"preview":false,"position":point,"homePosition":point,"spawnPosition":point,"hp":100.0,"maxHp":100.0,"aim":Vector2.LEFT,"formationLane":lane,"postPathIndex":0,"routeDistance":point.x-.05,"homeDistance":point.x-.05,"routeMin":0.0,"routeMax":.9,"guardRadius":.2,"mobilityFactor":1.0,"animation":"idle","animationClock":0.0,"cooldown":1000.0,"combatState":"engaged","chargeCooldown":5.0,"attackPlan":{},"elevation":0,"postRangeBonusPercent":0.0,"deploying":false},true)
	next_fixture_id += 1
	game.unit_skills.initialize_unit(value)
	game.units.append(value)
	return value

func sample(label_value: String, extras: Array = []) -> void:
	var before_frame: int = Engine.get_process_frames()
	sync_oracle()
	var values: Array = game.units.duplicate()
	values.append_array(extras)
	for unit in values:
		# Definition-free probes deliberately exercise catalog fallback below.
		if not check(unit.has("type"),label_value+" input actor has a type",{"actor":unit}):
			fixture_valid = false
			return
		var key: String = label_value+"/"+str(unit.get("id","preview"))+"/"+str(unit.type)
		var actual: Dictionary = game._stats(unit)
		var expected: Dictionary = original._stats(unit)
		compare(actual,expected,key+" stats")
		compare(game.unit_skills.public_state(unit),original.unit_skills.public_state(unit),key+" public skills")
		compare(game.movement_search_range(unit),expected.range,key+" movement range equals original full range")
		# Public actor snapshots require an ID in both original and current
		# Game. ID-less previews exercise the stats/skills APIs above only.
		if unit.has("id"):
			var published: Dictionary = game._unit_public(unit)
			for field in ["damage","range","interval","health","armor","healAmount","healInterval"]:
				compare(published[field],expected[field],key+" published "+field)
	check(before_frame == Engine.get_process_frames(),label_value+" comparisons stay within one engine frame")
	rows.append({"scenario":label_value,"actors":game.units.size(),"processFrame":before_frame,"clock":game.elapsed})

func damage_sample(unit: Dictionary, label_value: String) -> void:
	sync_oracle()
	var target: Dictionary = {"id":90000,"kind":"heavy","hp":1000.0,"maxHp":1000.0,"armor":.2,"pathIndex":0,"pointIndex":1,"position":Vector2(.525,.5)}
	var before_target: Dictionary = target.duplicate(true)
	var loss: float = game._damage_enemy(target,float(game._stats(unit).damage),str(unit.type),unit)
	var before_loss: float = original._damage_enemy(before_target,float(original._stats(unit).damage),str(unit.type),unit)
	compare(loss,before_loss,label_value+" actual damage receipt")
	compare(target.hp,before_target.hp,label_value+" actual enemy HP")
	check(loss>0.0 and float(target.hp)<1000.0,label_value+" really changes enemy HP")

func skill_transitions() -> void:
	var spear: Dictionary = actor("spear",1,Vector2(.55,.5),1)
	sample("setup_no_provider")
	damage_sample(spear,"No-provider spear")
	var samurai: Dictionary = actor("samurai",5,Vector2(.57,.5),-1)
	sample("same_frame_source_spawn")
	check(bool(game.unit_skills.public_state(spear).flags.spearAura),"Fixture actually exercises live spear aura")
	damage_sample(spear,"Live samurai aura")
	samurai.hp = 0.0
	sample("source_HP_zero_before_array_removal")
	check(not bool(game.unit_skills.public_state(spear).flags.spearAura),"Dead source immediately stops aura")
	damage_sample(spear,"Dead samurai source")
	samurai.hp = 100.0
	sample("source_HP_restored")
	samurai.position = Vector2(.9,.5)
	sample("source_moved_out")
	check(not bool(game.unit_skills.public_state(spear).flags.spearAura),"Out-of-range source actually stops aura")
	samurai.position = Vector2(.57,.5)
	samurai.campaignLevel = 4
	sample("source_level_below_unlock")
	samurai.campaignLevel = 5
	sample("source_level_restored")
	samurai.type = "archer"
	sample("same_identity_source_type_changed")
	samurai.type = "samurai"
	sample("source_type_restored")
	var commander: Dictionary = actor("commander",5,Vector2(.55,.52),0)
	sample("mixed_role_formation_created")
	check(bool(game.unit_skills.public_state(spear).flags.formation),"Fixture actually exercises three-lane formation")
	damage_sample(spear,"Live mixed formation")
	samurai.aim = Vector2.RIGHT
	sample("formation_direction_reversed")
	check(not bool(game.unit_skills.public_state(spear).flags.formation),"Direction reversal actually removes formation")
	damage_sample(spear,"Formation member reversed")
	samurai.aim = Vector2.LEFT
	samurai.formationLane = 1
	sample("formation_duplicate_lane")
	samurai.formationLane = -1
	samurai.postPathIndex = 1
	sample("formation_other_path")
	samurai.postPathIndex = 0
	commander.hp = 0.0
	sample("formation_commander_dead")
	commander.hp = 100.0
	var saved: Array = game.units.duplicate(true)
	game.units.erase(samurai)
	sample("source_removed_from_owned_array")
	# Supported training/QA restore replaces dictionaries, even at the same size.
	game.units = saved.duplicate(true)
	sample("owned_array_restored_with_new_dictionaries")
	game.units[1].type = "archer"
	sample("restored_owned_source_type_mutated")
	game.units = saved.duplicate(true)
	game.units.reverse()
	sample("owned_array_order_reversed")

func monk_and_growth() -> void:
	game.units.clear()
	var guard: Dictionary = actor("naginata",5,Vector2(.58,.5),1)
	actor("commander",3,Vector2(.6,.5))
	var weak: Dictionary = actor("monk",5,Vector2(.52,.5))
	var strong: Dictionary = actor("monk",8,Vector2(.54,.5))
	sample("mixed_monk_levels")
	check(float(game.unit_skills.public_state(guard).manaChargeFactor)>1.0,"Fixture actually exercises mantra")
	strong.hp = 0.0
	sample("strong_monk_dead_weak_fallback")
	weak.campaignLevel = 4
	sample("all_live_mantra_sources_locked")
	check(not bool(game.unit_skills.public_state(guard).flags.mantra),"No unlocked live monk means no mantra")
	weak.campaignLevel = 5
	strong.hp = 100.0
	strong.position = Vector2(.95,.5)
	sample("strong_monk_moved_out")
	strong.position = Vector2(.54,.5)
	guard.hp = 40.0
	sync_oracle()
	# Separate outcome arrays prevent the first pulse from altering the oracle's
	# input. Both branches execute their real healer logic and produce HP/statuses.
	original.units = game.units.duplicate(true)
	game.unit_skills._heal_pulse()
	original.unit_skills._heal_pulse()
	for index in range(game.units.size()):
		compare(game.units[index].hp,original.units[index].hp,"Actual non-stacking heal HP "+str(index))
		compare(game.units[index].get("friendlySkillStatuses",{}),original.units[index].get("friendlySkillStatuses",{}),"Actual talisman snapshot "+str(index))
	check(float(guard.hp)>40.0,"Pulse causes actual HP gain")
	sample("post_heal_public_state")
	var preview: Dictionary = game._deployment_template("archer")
	preview.erase("id")
	sample("idless_preview",[preview])
	preview["elevation"] = 2
	preview["postRangeBonusPercent"] = 60.0
	sample("preview_elevation_and_post_range_changed",[preview])
	for level_value in [1,3,5,8]:
		guard.campaignLevel = level_value
		weak.campaignLevel = level_value
		sample("same_actor_level_"+str(level_value))
	game.configure_roster(catalog,TYPES,{"archer":8,"monk":1})
	sample("roster_reconfigured",[game._deployment_template("archer"),game._deployment_template("monk")])
	var modified_catalog: Array = catalog.duplicate(true)
	for definition in modified_catalog:
		if str(definition.id)=="monk": definition.range = float(definition.range)*.7
	game.configure_roster(modified_catalog,TYPES,{"monk":5})
	var no_definition: Dictionary = weak.duplicate(true)
	no_definition.erase("definition")
	sample("catalog_definition_changed_without_actor_definition",[no_definition])

func world_stat_transitions() -> void:
	game.units.clear()
	actor("spear",1,Vector2(.5,.5))
	actor("archer",8,Vector2(.5,.5))
	game.config["trait"] = {"unitBonuses":[{"type":"all","damageFactor":1.1,"rangeFactor":1.2,"intervalFactor":.9}],"auras":[{"x":.5,"y":.5,"r":.12,"period":2.0,"activeSeconds":1.0,"unitDamageFactor":1.3,"unitRangeFactor":1.1,"unitIntervalFactor":.8}]}
	for clock_value in [.99999,1.0,1.00001,2.0]:
		game.elapsed = clock_value
		sample("periodic_aura_boundary_"+str(clock_value))
	game.units[0].position = Vector2(.8,.5)
	sample("aura_position_outside")
	game.storm_active = true
	sample("storm_range_changed")
	game.storm_active = false
	game.learning_supports.append({"x":.5,"y":.5,"r":.15,"remaining":1.0,"unitDamageFactor":1.4})
	sample("learning_support_active")
	game.learning_supports[0].remaining = 0.0
	sample("learning_support_expired_same_frame")

func production_and_reset() -> void:
	game.load_map(fixture(),10)
	game.configure_roster(catalog,TYPES,{"spear":1})
	game.start_battle()
	game.spawn_queue.clear(); game.spawn_source_waves.clear(); game.spawn_metadata.clear()
	game.spawn_clock = 100000.0
	sample("reset_empty_roster")
	var accepted: Dictionary = game.submit_deployment("spear",Vector2(.55,.5))
	check(bool(accepted.get("ok",false)),"Native production accepts a real paid spear order",accepted)
	for index in range(100):
		if game.recruitment_queue.is_empty(): break
		game.advance_simulation(.025)
	check(game.units.size()==1 and game.recruitment_queue.is_empty(),"Native production creates one actual actor")
	sample("after_real_production")
	if game.units.is_empty(): return
	var reused_id: int = int(game.units[0].id)
	var retained: Array = game.units.duplicate(true)
	game.units[0].hp = 0.0
	sample("actual_actor_dies_before_pruning")
	game._remove_fallen_units()
	sample("after_native_fallen_removal")
	game.units = retained.duplicate(true)
	sample("training_restore_after_native_removal")
	game.load_map(fixture(),10)
	game.start_battle()
	next_fixture_id = reused_id
	actor("monk",8,Vector2(.5,.5))
	sample("new_map_reuses_old_actor_id_as_different_role")

func segment(label_value: String, a: Vector2, b: Vector2, margin: float) -> void:
	sync_oracle()
	compare(game.ground_combat.land_segment_safe(a,b,margin),original.ground_combat.land_segment_safe(a,b,margin),label_value)

func geometry_and_motion() -> void:
	game.config["obstacles"] = [{"x":.5,"y":.5,"r":.05,"blockPlacement":true}]
	for margin in [0.0,.002,.008]:
		for epsilon in [-.000002,0.0,.000002]:
			var y: float = .5+.05+margin+epsilon
			segment("circle tangent/inside/outside "+str(margin)+"/"+str(epsilon),Vector2(.3,y),Vector2(.7,y),margin)
	segment("point inside circle",Vector2(.5,.5),Vector2(.5,.5),0.0)
	check(not game.ground_combat.land_segment_safe(Vector2(.5,.5),Vector2(.5,.5),0.0),"Geometry fixture actually contains a blocking circle")
	game.config.obstacles[0].x = .9
	segment("live obstacle dictionary moved",Vector2(.3,.5),Vector2(.7,.5),.008)
	game.config.obstacles[0].x = .5
	game.config.obstacles[0].blockPlacement = false
	segment("live obstacle blocking disabled",Vector2(.3,.5),Vector2(.7,.5),.008)
	game.config.obstacles[0].blockPlacement = true
	game.config.obstacles[0].r = .001
	segment("live obstacle radius changed",Vector2(.3,.52),Vector2(.7,.52),.008)
	game.config["water"] = {"x":.44,"y":.4,"w":.12,"h":.2}
	sync_oracle()
	game.ground_combat.reset(); original.ground_combat.reset()
	segment("water crosses segment",Vector2(.3,.5),Vector2(.7,.5),0.0)
	segment("water endpoint outside",Vector2(.2,.2),Vector2(.3,.3),0.0)
	check(not game.ground_combat.land_segment_safe(Vector2(.3,.5),Vector2(.7,.5),0.0) and game.ground_combat.land_segment_safe(Vector2(.2,.2),Vector2(.3,.3),0.0),"Water fixture exercises both blocked and legal segments")
	game.ground_combat.structure_segment_clear = func(_a: Vector2,_b: Vector2,_margin: float) -> bool: return false
	original.ground_combat.structure_segment_clear = game.ground_combat.structure_segment_clear
	segment("structure callback vetoes otherwise legal route",Vector2(.2,.2),Vector2(.3,.3),0.0)
	check(not game.ground_combat.land_segment_safe(Vector2(.2,.2),Vector2(.3,.3),0.0),"Structure callback really vetoes a clear segment")
	game.ground_combat.structure_segment_clear = Callable()
	original.ground_combat.structure_segment_clear = Callable()
	game.config.erase("water")
	sync_oracle()
	game.ground_combat.reset(); original.ground_combat.reset()
	var seeded: RandomNumberGenerator = RandomNumberGenerator.new()
	seeded.seed = 4004
	for index in range(160):
		var a: Vector2 = Vector2(seeded.randf_range(.1,.9),seeded.randf_range(.1,.9))
		var b: Vector2 = Vector2(seeded.randf_range(.1,.9),seeded.randf_range(.1,.9))
		game.config.obstacles[0].x = seeded.randf_range(.2,.8)
		game.config.obstacles[0].y = seeded.randf_range(.2,.8)
		game.config.obstacles[0].r = seeded.randf_range(.005,.12)
		segment("seeded live geometry "+str(index),a,b,seeded.randf_range(0.0,.012))
	for index in range(48):
		crowded_case(index,seeded)

func crowded_case(index: int, seeded: RandomNumberGenerator) -> void:
	game.units.clear(); game.enemies.clear()
	var type_name: String = "spear" if index%2==0 else "naginata"
	var unit: Dictionary = actor(type_name,1,Vector2(.55,.5))
	unit["guardZone"] = {"center":Vector2(.55,.5),"radius":.2}
	for friend_index in range(6): actor("spear",1,unit.position+Vector2(seeded.randf_range(-.035,.035),seeded.randf_range(-.035,.035)))
	for enemy_index in range(7):
		game.enemies.append({"id":enemy_index+1,"kind":"heavy","hp":100.0,"maxHp":100.0,"armor":0.0,"pathIndex":0,"pointIndex":1,"position":unit.position+Vector2(-.03-float(enemy_index%3)*.015,float(enemy_index/3-1)*.012),"aim":Vector2.RIGHT})
	game.config["obstacles"] = [] if index%3==0 else [{"x":.525,"y":.5,"r":.006 if index%3==1 else .018,"blockPlacement":true}]
	sync_oracle()
	for ground in [game.ground_combat,original.ground_combat]:
		ground.crowd.rebuild(game.units,game.enemies)
		ground.crowd.claim_target(1)
	var target: Dictionary = game.enemies[0]
	compare(game.ground_combat._nearest_enemy(unit).get("id",-1),original.ground_combat._nearest_enemy(unit).get("id",-1),"Seeded nearest target "+str(index))
	compare(game.ground_combat._melee_point(unit,target,index%2==1),original.ground_combat._melee_point(unit,target,index%2==1),"Seeded legal melee point "+str(index))
	var desired: Vector2 = unit.position+Vector2(-.006,0)
	var current_legal: Callable = func(a: Vector2,b: Vector2) -> bool: return game.ground_combat.land_segment_safe(a,b,.008)
	var original_legal: Callable = func(a: Vector2,b: Vector2) -> bool: return original.ground_combat.land_segment_safe(a,b,.008)
	for detour in [false,true]:
		compare(game.ground_combat.crowd.move_point(unit,desired,true,current_legal,target.position,detour),original.ground_combat.crowd.move_point(unit,desired,true,original_legal,target.position,detour),"Seeded crowded move/detour "+str(index)+"/"+str(detour))

func visual_enemy(id_value: int, point: Vector2, role: String = "path_assault") -> Dictionary:
	return {"id":id_value,"type":"heavy","kind":"heavy","hp":100.0,"maxHp":100.0,"armor":0.0,"pathIndex":0,"pointIndex":1,"position":point,"aim":Vector2.RIGHT,"animation":"idle","animationClock":0.0,"combatRole":role,"attackRange":.1,"meleeRange":.041,"ingressActive":false,"counterPlan":{}}

func renderer_probe(current: RefCounted, before: RefCounted, value: Dictionary, friendly: bool, label_value: String, require_legal: bool = false) -> int:
	# Both renderers query the SAME battle inputs: this isolates renderer changes
	# from Game/Skills/Ground changes, whose original oracles are tested above.
	var snapshot: Array = [value.duplicate(true),game.units.duplicate(true),game.enemies.duplicate(true)]
	var valid_count: int = 0
	compare(current._visual_target_valid(value,{},friendly,game),before._visual_target_valid(value,{},friendly,game),label_value+" empty target")
	for target in (game.enemies if friendly else game.units):
		var valid: bool = current._visual_target_valid(value,target,friendly,game)
		compare(valid,before._visual_target_valid(value,target,friendly,game),label_value+" target "+str(target.id))
		if valid: valid_count += 1
	var current_direction: Vector2 = current.visual_direction(value,friendly,game)
	check(snapshot==[value,game.units,game.enemies],label_value+" current renderer never mutates actor state")
	var before_direction: Vector2 = before.visual_direction(value,friendly,game)
	check(snapshot==[value,game.units,game.enemies],label_value+" original renderer never mutates actor state")
	compare(current_direction,before_direction,label_value+" original visual direction")
	if require_legal: check(valid_count>0,label_value+" actually has a legal visual target")
	rows.append({"scenario":"renderer/"+label_value,"friendly":friendly,"legalTargets":valid_count,"direction":str(current_direction),"originalDirection":str(before_direction),"processFrame":Engine.get_process_frames()})
	return valid_count

func renderer_semantics() -> void:
	game.load_map(fixture(),10)
	game.configure_roster(catalog,TYPES,{})
	game.start_battle()
	var current: RefCounted = Renderer.new()
	var before: RefCounted = BeforeRenderer.new()
	current.bind_battle(game); before.bind_battle(game)
	for type_name in ["spear","archer","gunner","monk"]:
		game.units.clear(); game.enemies.clear()
		var value: Dictionary = actor(str(type_name),1,Vector2(.5,.5))
		value["emplacementShooter"] = type_name=="gunner"
		var first: Dictionary = visual_enemy(2001,Vector2(.53,.5))
		var second: Dictionary = visual_enemy(2002,Vector2(.5,.53))
		game.enemies = [first,second,visual_enemy(2003,Vector2(.9,.8))]
		game.animation_time += .13
		var legal: int = renderer_probe(current,before,value,true,str(type_name)+" near/far/equal-distance",type_name!="monk")
		if type_name=="monk": check(legal==0,"Monk has no visual attack target")
		game.enemies.reverse(); game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" reversed equal-distance order")
		second.hp = 0.0; game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" cached target death")
		first.hp = 100.0; first["escaped"] = true; game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" escaped target")
		first.erase("escaped"); first["consumed"] = true; game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" consumed target")
		first.erase("consumed"); first.position = Vector2(1.07,-.05); first.ingressActive = true; game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" ingress outside field")
		first.position = Vector2(.53,.5); first.ingressActive = false; first.combatRole = "emplacement_assault"; game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" emplacement raider target")
		first["fortification"] = true; first["stationaryEnemy"] = true; game.animation_time += .13
		renderer_probe(current,before,value,true,str(type_name)+" stationary fortification target")
		value.animation = "attack"; value.attackPlan = {"targetId":2001}
		renderer_probe(current,before,value,true,str(type_name)+" committed attack facing")
		value.animation = "walk"
		renderer_probe(current,before,value,true,str(type_name)+" walking aim")
		value.hp = 0.0; value.animation = "death"
		renderer_probe(current,before,value,true,str(type_name)+" death aim")
	game.units.clear(); game.enemies.clear()
	var bow: Dictionary = actor("archer",1,Vector2(.3,.5))
	bow.postRangeBonusPercent = 150.0
	var hidden: Dictionary = visual_enemy(2101,Vector2(.6,.5))
	game.enemies = [hidden]
	game.config["historicalBattlefield"] = {"timeOfDay":"night"}
	game.config["torches"] = []
	game.animation_time += .13
	check(renderer_probe(current,before,bow,true,"night hidden enemy")==0,"Night fixture actually hides an in-range enemy")
	game.config.torches.append({"x":.6,"y":.5}); game.animation_time += .13
	renderer_probe(current,before,bow,true,"night torch reveals enemy",true)
	game.config.erase("historicalBattlefield"); game.config.erase("torches")
	for role in ["path_assault","emplacement_assault"]:
		game.units.clear(); game.enemies.clear()
		actor("spear",1,Vector2(.53,.5))
		actor("spear",1,Vector2(.5,.53))
		actor("archer",1,Vector2(.47,.5))
		actor("monk",5,Vector2(.8,.8))
		var hostile: Dictionary = visual_enemy(2201,Vector2(.5,.5),str(role))
		game.enemies = [hostile]; game.animation_time += .13
		renderer_probe(current,before,hostile,false,str(role)+" hostile near/far/target roles",true)
		game.units.reverse(); game.animation_time += .13
		renderer_probe(current,before,hostile,false,str(role)+" hostile reversed equal-distance order",true)
		game.units[1].hp = 0.0; game.units[2].hp = 0.0; game.animation_time += .13
		renderer_probe(current,before,hostile,false,str(role)+" hostile cached victim death",true)
		hostile.animation = "attack"; hostile.counterPlan = {"targetId":game.units[-1].id}
		renderer_probe(current,before,hostile,false,str(role)+" hostile committed attack")
		hostile.animation = "walk"
		renderer_probe(current,before,hostile,false,str(role)+" hostile walking aim")
		hostile.hp = 0.0; hostile.animation = "death"
		renderer_probe(current,before,hostile,false,str(role)+" hostile death aim")
	current.bind_battle(null); before.bind_battle(null)

func membership_sample(label_value: String) -> void:
	sync_oracle()
	for id_value in [501,502,503,504]:
		compare(game._enemy(id_value),original._enemy(id_value),label_value+" enemy membership "+str(id_value))
	if not game.enemies.is_empty():
		check(is_same(game._enemy(int(game.enemies[0].id)),game.enemies[0]),label_value+" lookup returns the currently owned dictionary")

func mutate_scoped(_payload: Dictionary, stage: String) -> void:
	match stage:
		"role_level_position":
			game.units[1].type = "archer"
			game.units[1].definition = game.recruit_catalog.archer.duplicate(true)
			game.units[1].campaignLevel = 3
			game.units[1].position = Vector2(.9,.5)
		"source_death":
			game.units[2].hp = 0.0
			game.units[3].hp = 0.0
		"same_length_restore":
			game.units = scoped_restore.duplicate(true)
		"same_length_enemy_replace":
			game.enemies = [visual_enemy(501,Vector2(.7,.5)),visual_enemy(503,Vector2(.72,.5))]
		"dead_enemy":
			game.enemies[0].hp = 0.0
		"removed_enemy_same_length":
			game.enemies[0] = visual_enemy(504,Vector2(.74,.5))
	sample("inside_suspended_callback/"+stage)
	membership_sample("inside_suspended_callback/"+stage)

func scoped_semantics() -> void:
	for read_only in [false,true]:
		game.load_map(fixture(),10)
		game.configure_roster(catalog,TYPES,{})
		game.start_battle()
		actor("spear",1,Vector2(.55,.5),1)
		actor("samurai",5,Vector2(.57,.5),-1)
		actor("commander",5,Vector2(.55,.52),0)
		actor("monk",5,Vector2(.52,.5))
		actor("naginata",5,Vector2(.58,.5))
		game.enemies = [visual_enemy(501,Vector2(.53,.5)),visual_enemy(502,Vector2(.52,.51))]
		scoped_restore = game.units.duplicate(true)
		var mode: String = "readonly" if read_only else "live"
		var scope: Dictionary = game.unit_skills.begin_query_scope(read_only)
		sample(mode+"/scope_warm")
		membership_sample(mode+"/membership_warm")
		var returned: Dictionary = game._stats(game.units[3])
		returned.damage = 999.0
		returned.supportStats.healAmount = 999.0
		var published: Dictionary = game.unit_skills.public_state(game.units[2])
		published.flags.formation = not bool(published.flags.formation)
		published.skillIds.clear()
		sample(mode+"/returned_dictionary_changes_do_not_poison_next_read")
		for stage in ["role_level_position","source_death","same_length_restore","same_length_enemy_replace","dead_enemy","removed_enemy_same_length"]:
			var callback: Callable = Callable(self,"mutate_scoped").bind(str(stage))
			# Alternate actual public notification routes. Do not directly mutate
			# type/roster inside the implementation's declared stable batch.
			if stage in ["source_death","same_length_enemy_replace","removed_enemy_same_length"]:
				game.state_changed.connect(callback)
				game._emit_state()
				game.state_changed.disconnect(callback)
			else:
				game.game_event.connect(callback)
				game._event("perf04_callback_probe","",{})
				game.game_event.disconnect(callback)
			sample(mode+"/after_callback/"+str(stage))
			membership_sample(mode+"/after_callback/"+str(stage))
		check(game._enemy(501).is_empty(),mode+" removed enemy ID cannot survive in membership index")
		var old_generation: int = int(game.unit_skills.generation)
		game.load_map(fixture(),10)
		check(int(game.unit_skills.generation)>old_generation and game.unit_skills.read_query_context().is_empty(),mode+" reset discards old generation and read cache scope")
		game.unit_skills.end_query_scope(scope)
		actor("monk",8,Vector2(.5,.5))
		sample(mode+"/new_generation_after_retired_scope")
		membership_sample(mode+"/new_generation_after_retired_scope")

func finish() -> void:
	if stopped: return
	stopped = true
	var ending: Dictionary = hashes()
	check(sources==ending,"All observed native/test/oracle sources stay unchanged during execution")
	check(Time.get_ticks_usec()-started<60000000,"Focused CPU fixture completes within sixty seconds")
	# Include cleanup errors before reading the engine log. HQ's process receipt
	# must also reject any engine error emitted after this in-process check.
	if is_instance_valid(original):
		original.units = []; original.enemies = []
	if is_instance_valid(game): game.free()
	if is_instance_valid(original): original.free()
	var arguments: PackedStringArray = OS.get_cmdline_args()
	var log_index: int = arguments.find("--log-file")
	var log_path: String = arguments[log_index+1] if log_index>=0 and log_index+1<arguments.size() else ""
	# Godot consumes --log-file in some launches. tools/run.ps1 assigns this
	# exact isolated APPDATA directory and writes its godot.log directly there.
	if log_path.is_empty(): log_path = OS.get_environment("APPDATA").path_join("godot.log")
	var normalized_log: String = log_path.replace("\\","/").simplify_path().to_lower()
	var allowed_root: String = ProjectSettings.globalize_path(OUTPUT).replace("\\","/").simplify_path().trim_suffix("/").to_lower()
	var log_parent: String = normalized_log.get_base_dir()
	var log_constrained: bool = normalized_log.is_absolute_path() and normalized_log.get_file()=="godot.log" and log_parent.get_base_dir()==allowed_root and log_parent.get_file().begins_with("run-") and log_parent.get_file().length()>4
	var log_available: bool = log_constrained and FileAccess.file_exists(log_path)
	check(log_available,"Explicit engine log is available for runtime error verification")
	var engine_errors: int = FileAccess.get_file_as_string(log_path).count("ERROR:") if log_available else -1
	check(engine_errors==0,"No script or engine errors before report",{"engineErrors":engine_errors,"log":log_path})
	var directory: String = OUTPUT.path_join("semantics-"+str(int(Time.get_unix_time_from_system()))+"-"+str(started))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var report: Dictionary = {"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures,"fixtureValid":fixture_valid,"engineErrors":engine_errors,"engineLog":log_path,"fixtureOnlyActivatedRoles":["naginata"],"scenarios":rows,"productionEvents":production_events,"sources":sources,"sourcesAtEnd":ending,"wallMs":float(Time.get_ticks_usec()-started)/1000.0,"engine":Engine.get_version_info(),"scope":"CPU differential semantics against immutable original Game/Skills/Ground/Crowd. Explicit isolated roster/funds/actors/state mutation and one native paid production. Naginata is activated only in the test-owned in-memory catalog to exercise its preserved skills; product catalog and availability are unchanged. Same-frame skill/stats/public state transitions; heal HP/talisman outcomes; seeded live geometry/target/melee/crowd movement. No UI, player save, natural gameplay, rendering or performance acceptance."}
	report["declaredQueryScopes"] = ["live","readOnly"]
	report["scopeCallbacks"] = "Actual game_event/state_changed suspension; callback and resumed reads; owned units/enemies replacement, role/level/HP/position changes, returned dictionary isolation and generation reset"
	report["rendererScope"] = "Original/current visual target validity and visual direction on the same battle; both sides, near/far/ties/dead/night/ingress/roles/attack/walk/death; exact actor-state immutability. CPU queries only, no render or art acceptance."
	var file: FileAccess = FileAccess.open(directory.path_join("perf04-semantics.json"),FileAccess.WRITE)
	if file==null: push_error("PERF04 cannot write report"); quit(2); return
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("PERF04_SEMANTICS ",JSON.stringify({"status":report.status,"checks":checks,"failures":failures.size(),"report":ProjectSettings.globalize_path(directory.path_join("perf04-semantics.json"))}))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	started = Time.get_ticks_usec()
	sources = hashes()
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units.duplicate(true)
	# This disabled product role is still part of the requested skill semantics.
	# Enable only the private fixture definition; never edit the source catalog.
	for definition in catalog:
		if str(definition.id)=="naginata": definition["active"] = true
	setup()
	if not fixture_valid: finish(); return
	skill_transitions()
	monk_and_growth()
	world_stat_transitions()
	production_and_reset()
	geometry_and_motion()
	renderer_semantics()
	scoped_semantics()
	finish()
