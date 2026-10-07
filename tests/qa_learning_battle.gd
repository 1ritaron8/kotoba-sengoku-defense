extends SceneTree
## Verifies observable combat, support lifetime and map-local attempt boundaries.
const Battle = preload("res://native/game.gd")
var checks: int = 0
var failures: Array = []
var observations: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func fixture(id: String = "qa-learning-lane") -> Dictionary:
	return {"id":id,"theme":"forest","initialGold":280,"recruitCost":60,"unitLimit":14,"totalWaves":2,"level":1,"tierIndex":0,"difficulty":1.0,"objectives":[{"id":"main","x":.9,"y":.5,"hp":25}],"paths":[{"id":"lane","objectiveId":"main","points":[{"x":.1,"y":.5},{"x":.5,"y":.5},{"x":.9,"y":.5}]}],"buildZones":[{"x":.3,"y":.35,"r":.08},{"x":.75,"y":.30,"r":.08}],"trait":{}}

func make_battle(id: String) -> Node2D:
	var battle: Node2D = Battle.new()
	root.add_child(battle)
	battle.set_process(false)
	battle.set_seed(731)
	battle.load_map(fixture(id))
	check(battle.recruit("archer") and battle.place_unit(.3,.35),"Paid real archer placement succeeds in the lane fixture")
	return battle

func run() -> void:
	var workspace: String = ProjectSettings.globalize_path("res://").replace("\\","/").to_lower()
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with(workspace):
		push_error("Learning battle QA requires workspace-isolated APPDATA")
		quit(2)
		return
	var control: Node2D = make_battle("qa-learning-control")
	var supported: Node2D = make_battle("qa-learning-supported")
	var starts: Array = []
	supported.wave_started.connect(func(info: Dictionary):
		starts.append(info.duplicate(true))
		check(supported.wave==int(info.wave) and supported.running and not supported.spawn_queue.is_empty() and str(info.mapId)==str(supported.config.id),"Wave-start signal sees a complete valid wave state")
	)
	check(not bool(supported.apply_learning_support(Vector2(.3,.35),false,"before-start").ok),"Support rejects inactive battles without consuming an attempt")
	control.start_battle()
	supported.start_battle()
	check(starts.size()==1 and int(starts[0].wave)==1,"The first wave publishes its map and wave number")
	var unit: Dictionary = supported.units[0]
	var base: Dictionary = supported._stats(unit)
	var before_gold: int = supported.gold
	var result: Dictionary = supported.apply_learning_support(Vector2(.3,.35),false,"understood-1")
	check(bool(result.ok) and is_equal_approx(float(result.duration),12.0) and is_equal_approx(float(result.r),.17),"Unhinted understanding activates the specified twelve-second area")
	check(supported.gold==before_gold,"Support itself never duplicates or grants a gold reward")
	check(is_equal_approx(float(supported._stats(unit).damage),float(base.damage)*1.15),"The placed nearby archer receives the real fifteen-percent damage boost")
	check(is_equal_approx(float(supported._stats(unit).range),float(base.range)) and is_equal_approx(float(supported._stats(unit).interval),float(base.interval)),"Support preserves actual weapon range and attack interval")
	var far_unit: Dictionary = unit.duplicate(true)
	far_unit.position = Vector2(.75,.30)
	check(is_equal_approx(float(supported._stats(far_unit).damage),float(base.damage)),"A real position outside the support radius receives no boost")
	var edge_unit: Dictionary = unit.duplicate(true)
	edge_unit.position = Vector2(.47,.35)
	check(is_equal_approx(float(supported._stats(edge_unit).damage),float(base.damage)*1.15),"The exact supported radius edge is included")
	edge_unit.position.x += .0001
	check(is_equal_approx(float(supported._stats(edge_unit).damage),float(base.damage)),"A position beyond the radius is excluded")
	check(not bool(supported.apply_learning_support(Vector2(.3,.35),false,"understood-1").ok) and supported.learning_supports.size()==1,"The same attempt cannot issue a second support")
	for bad in [Vector2(-.01,.5),Vector2(.5,1.01),Vector2(INF,.5)]:
		check(not bool(supported.apply_learning_support(bad,false,"invalid-"+str(bad)).ok),"Invalid or non-finite target coordinates are rejected")
	check(not bool(supported.apply_learning_support(Vector2(.3,.35),false," ").ok),"Blank attempt identity is rejected")
	var first_hit: Dictionary = {}
	for step in range(1000):
		control.advance_simulation(.025)
		supported.advance_simulation(.025)
		if not control.enemies.is_empty() and not supported.enemies.is_empty():
			var a: Dictionary = control.enemies[0]
			var b: Dictionary = supported.enemies[0]
			if float(a.hp)<float(a.maxHp):
				first_hit = {"unassisted":float(a.maxHp)-float(a.hp),"supported":float(b.maxHp)-float(b.hp),"time":control.elapsed}
				break
	check(not first_hit.is_empty(),"An actual projectile reaches a live enemy in both identical seeded battles")
	if not first_hit.is_empty():
		check(absf(float(first_hit.supported)/float(first_hit.unassisted)-1.15)<.0001,"A real enemy hit deals fifteen-percent more damage, not just a changed UI statistic")
	observations["firstLiveHit"] = first_hit
	check(control.learning_supports.is_empty(),"A second campaign battle does not share another instance's support")
	var frozen: float = float(supported.snapshot().learningSupports[0].remaining)
	supported.pause_battle()
	supported.advance_simulation(20)
	check(is_equal_approx(float(supported.snapshot().learningSupports[0].remaining),frozen),"Paused simulation freezes support duration")
	supported.pause_battle()
	supported.advance_simulation(.25)
	check(absf(float(supported.snapshot().learningSupports[0].remaining)-(frozen-.25))<.0001,"Resumed support duration follows simulation delta")
	check(bool(supported.apply_learning_support(Vector2(.3,.35),true,"hinted-1").ok),"A distinct hinted understanding creates support")
	check(is_equal_approx(float(supported._stats(unit).damage),float(base.damage)*1.15),"Overlapping support uses the strongest effect and never multiplies bonuses")
	for step in range(600):
		supported.advance_simulation(.025)
		if supported.learning_supports.is_empty():
			break
	check(supported.learning_supports.is_empty() and is_equal_approx(float(supported._stats(unit).damage),float(base.damage)),"Expired support is removed and actual damage returns to normal")
	check(not bool(supported.apply_learning_support(Vector2(.3,.35),false,"understood-1").ok),"Expiration does not make a consumed attempt reusable")
	var hint_only: Dictionary = supported.apply_learning_support(Vector2(.3,.35),true,"hint-only")
	check(bool(hint_only.ok) and is_equal_approx(float(hint_only.duration),6.0) and is_equal_approx(float(supported._stats(unit).damage),float(base.damage)*1.08),"Hint-only support has the actual six-second, eight-percent strength")
	var exposed: Dictionary = supported.snapshot()
	exposed.learningSupports[0].remaining = 999
	check(float(supported.snapshot().learningSupports[0].remaining)<=6.0,"Public support snapshots cannot mutate the engine's live duration")
	for step in range(8000):
		supported.advance_simulation(.05)
		if supported.between_waves or supported.finished:
			break
	check(supported.between_waves,"The genuine first wave reaches its between-wave boundary")
	if supported.between_waves:
		check(bool(supported.apply_learning_support(Vector2(.3,.35),false,"between-wave").ok),"A selected support can be prepared at the real wave boundary")
		frozen = float(supported.snapshot().learningSupports[0].remaining)
		supported.advance_simulation(30)
		check(is_equal_approx(float(supported.snapshot().learningSupports[0].remaining),frozen),"Between-wave learning pauses duration until battle resumes")
		supported.continue_wave()
		check(starts.size()==2 and int(starts[1].wave)==2,"Continuing publishes the next complete wave once")
	var wallet: int = supported.gold
	supported.grant_reward("correct")
	check(supported.gold==wallet+70,"Existing unhinted reward remains seventy gold")
	wallet = supported.gold
	supported.grant_reward("hinted")
	check(supported.gold==wallet+25,"Existing hinted reward remains twenty-five gold")
	supported.load_map(fixture("qa-next-campaign-map"))
	check(supported.learning_supports.is_empty() and supported.learning_attempts.is_empty(),"Loading another map resets both effects and consumed attempt identities")
	supported.start_battle()
	check(bool(supported.apply_learning_support(Vector2(.3,.35),false,"understood-1").ok),"A new map may legitimately use a new session's previously named attempt")
	check(str(supported.snapshot().learningSupports[0].mapId)=="qa-next-campaign-map","Registered support belongs to the current map, not the prior campaign")
	var report: Dictionary = {"checks":checks,"failures":failures,"observations":observations,"scope":"Actual placed soldier stats and seeded live projectile damage; exact area, duration, pause, deduplication and map-local boundaries."}
	var file: FileAccess = FileAccess.open("res://tests/qa_learning_battle.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	control.free()
	supported.free()
	print("LEARNING_BATTLE_QA ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
