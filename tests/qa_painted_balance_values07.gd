extends SceneTree
## Controlled value/target-selection fixture; separate from actual-input review.
const Battle=preload("res://native/game.gd")
const BeforeBattle=preload("res://tests/profiles/painted-balance-07/source-before/game.gd")
const Duration=preload("res://native/battle_duration.gd")
const BeforeDuration=preload("res://tests/profiles/painted-balance-07/source-before/battle_duration.gd")
const Growth=preload("res://native/unit_growth.gd")
const ActualReview=preload("res://tests/qa_painted_balance07.gd")
var failures: Array=[]
var evidence: Dictionary={}
var catalog: Array=[]

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label_value: String) -> void:
	if not ok: failures.append(label_value);push_error(label_value)

func make_game(script: Script,map_config: Dictionary) -> Node2D:
	var game: Node2D=script.new()
	root.add_child(game)
	game.set_process(false)
	game.hide()
	game.configure_roster(catalog,["archer","spear","gunner"],{})
	game.load_map(map_config,10)
	game.start_battle()
	game.set_seed(707)
	return game

func ranges(game: Node2D) -> Dictionary:
	var result: Dictionary={}
	for kind in ["archer","gunner"]:
		for high in [false,true]:
			var unit: Dictionary=game._deployment_template(kind)
			unit["elevation"]=2 if high else 0
			unit["postRangeBonusPercent"]=60.0 if high else 25.0
			result[kind+("High" if high else "Grass")]=game._stats(unit).range
	return result

func enemy_values(game: Node2D) -> Array:
	var result: Array=[]
	for spec in [["raider",1,{}],["runner",2,{}],["shield",3,{}],["heavy",6,{}],["enemy_archer",3,{"originKind":"raider"}]]:
		var enemy: Dictionary=game._spawn_enemy(spec[0],spec[1],spec[2])
		result.append({"kind":enemy.kind,"hp":enemy.maxHp,"armor":enemy.armor,"speed":enemy.speed,"damage":enemy.damage,"reward":enemy.reward,"counterDamage":enemy.get("counterDamage",null)})
	return result

func spawn_values(game: Node2D) -> Array:
	var result: Array=[]
	for index in range(8):
		game.wave=index+1
		result.append(game._spawn_interval())
	game.wave=1
	return result

func run() -> void:
	catalog=JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")).units
	var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var before_maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/profiles/painted-balance-07/source-before/maps.json"))
	var current: Node2D=make_game(Battle,maps[0])
	var before: Node2D=make_game(BeforeBattle,before_maps[0])
	var current_range: Dictionary=ranges(current)
	var before_range: Dictionary=ranges(before)
	check(is_equal_approx(current_range.archerHigh,.284704) and is_equal_approx(current_range.archerGrass,.179375),"Stage01 real stats use high/grass range .284704/.179375")
	check(is_equal_approx(current_range.archerHigh/before_range.archerHigh,.7) and is_equal_approx(current_range.archerGrass/before_range.archerGrass,.7),"Both archer post types are reduced by30 percent")
	check(current_range.gunnerHigh==before_range.gunnerHigh and current_range.gunnerGrass==before_range.gunnerGrass,"Gunner range is unchanged")
	var current_enemies: Array=enemy_values(current)
	var before_enemies: Array=enemy_values(before)
	for index in range(current_enemies.size()):
		var a: Dictionary=current_enemies[index]
		var b: Dictionary=before_enemies[index]
		check(is_equal_approx(float(a.hp)/float(b.hp),1.10/.95),"Enemy HP factor ratio: "+str(a.kind))
		for key in ["speed","damage","reward","counterDamage"]: check(a[key]==b[key],"Unchanged "+str(a.kind)+" "+key)
		check(is_equal_approx(float(a.armor),.08 if index in [0,1,4] else float(b.armor)),"Light armor only: "+str(a.kind))
	var damage: float=16.5
	check(ceili(float(before_enemies[0].hp)/(damage*(1.0-float(before_enemies[0].armor))))==3 and ceili(float(current_enemies[0].hp)/(damage*(1.0-float(current_enemies[0].armor))))==4,"Opening normal enemy now requires4 rather than3 unsupported level1 archer hits")
	var caps: Array=[]
	for row in current.battle_plan.waves: caps.append(row.activeCap)
	check(caps.slice(0,8)==[10,14,18,22,25,29,32,36],"Stage01 timed cap grows to existing36")
	var intervals: Array=spawn_values(current)
	check(is_equal_approx(intervals[0],1.2) and is_equal_approx(intervals[1],1.1) and is_equal_approx(intervals[2],1.0) and is_equal_approx(intervals[-1],.62),"Stage01 timed ingress intervals use requested opening and same late bound")
	var control_config: Dictionary=before_maps[0].duplicate(true)
	control_config.id="balance07-control";control_config.stageNumber=2
	var control: Node2D=make_game(Battle,control_config)
	var before_control: Node2D=make_game(BeforeBattle,control_config)
	check(ranges(control)==ranges(before_control),"Other-stage ranges unchanged")
	check(enemy_values(control)==enemy_values(before_control),"Other-stage enemies unchanged")
	check(spawn_values(control)==spawn_values(before_control),"Other-stage timed ingress unchanged")
	var schedule: Array=control._build_base_wave_schedule(10)
	check(Duration.build(control_config,schedule,10)==BeforeDuration.build(control_config,schedule,10),"Other-stage complete timed plan unchanged")
	for level in [1,4,8]: check(Growth.recruit_quantity("spear",level)=={1:1,4:3,8:5}[level],"Spear squad quantity preserved")
	check(Growth.recruit_quantity("archer",4)==1 and Growth.recruit_quantity("archer",5)==2,"Archer level5 two-soldier quantity preserved")
	evidence={"beforeRanges":before_range,"currentRanges":current_range,"beforeEnemies":before_enemies,"currentEnemies":current_enemies,"caps":caps,"intervals":intervals,"scope":"Controlled numeric/scoping fixture, not difficulty acceptance or performance benchmark"}
	for game in [current,before,control,before_control]: game.free()
	var file: FileAccess=FileAccess.open("res://tests/profiles/painted-balance-07/values-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"pass" if failures.is_empty() else "failed","failures":failures,"evidence":evidence},"  "));file.close()
	print("BALANCE07 VALUES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
