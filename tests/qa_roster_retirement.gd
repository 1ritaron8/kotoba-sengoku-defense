extends SceneTree
const Progress=preload("res://native/progress.gd")
const Battle=preload("res://native/game.gd")
const Training=preload("res://native/unit_training.gd")
const Barracks=preload("res://native/barracks.gd")
const Main=preload("res://native/main.gd")
var checks: int=0
var failures: Array=[]

func check(value: bool, note: String) -> void:
	checks+=1
	if not value: failures.append(note);push_error(note)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var progress=Progress.new()
	for index in range(40): progress.data.maps[str(index)]={}
	progress.data.army.levels.naginata=8
	progress.data.army.training={"naginata":true,"gunner":true}
	progress.data.army.selected="naginata"
	progress._sanitize_army()
	check(progress.unit_catalog.size()==8,"legacy definitions preserved")
	check(progress.unlocked_units().size()==7,"seven playable units")
	check("gunner" in progress.unlocked_units(),"matchlock retained")
	check(not "naginata" in progress.unlocked_units(),"naginata retired")
	check(int(progress.data.army.levels.naginata)==8,"legacy level preserved")
	check(bool(progress.data.army.training.naginata),"legacy training preserved")
	check(str(progress.data.army.selected)=="naginata","legacy stored selection preserved")
	var battle=Battle.new()
	battle.config={"id":"roster-retirement"}
	battle.gold=999
	check(not battle.begin_placement("naginata"),"unconfigured legacy click cannot recruit retired role")
	check(battle._deployment_template("naginata").is_empty(),"unconfigured drag cannot recruit retired role")
	battle.configure_roster(progress.unit_catalog,["naginata","gunner"],progress.data.army.levels)
	check(not battle.unlocked_roster.has("naginata"),"explicit obsolete unlock filtered")
	check(battle.unlocked_roster.has("gunner"),"gunner still recruitable")
	check(not battle._deployment_template("gunner").is_empty(),"gunner deployment template preserved")
	check(battle._deployment_template("naginata").is_empty(),"configured retired drag rejected")
	check(battle.gold==999 and battle.units.is_empty() and battle.recruitment_queue.is_empty(),"retired calls cannot spend or create units")
	var training=Training.new()
	training.catalog=progress.unit_catalog
	training.progress=progress
	check(not training._unlocked("naginata") and training._unlocked("gunner"),"training admits matchlock and rejects retired role")
	check(Training.UNIT_ORDER.size()==7 and not "naginata" in Training.UNIT_ORDER,"training roster has seven roles")
	var barracks=Barracks.new()
	barracks.progress=progress
	check(barracks._active_catalog().size()==7,"barracks filters inactive role")
	check(Main!=null,"main and rendering dependencies parse after rejected asset removal")
	var result={"checks":checks,"failures":failures,"scope":"In-memory roster and legacy progression only; no player save write, visible game launch or performance measurement."}
	var output=FileAccess.open("res://tests/qa_roster_retirement.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"  "));output.close()
	print("ROSTER_RETIREMENT ",JSON.stringify(result))
	training.free();barracks.free();battle.free()
	quit(0 if failures.is_empty() else 1)
