extends SceneTree

const Battle = preload("res://native/game.gd")
var failures: Array = []
var assertions: int = 0
var distinct_frames: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func map_fixture() -> Dictionary:
	return {"id":"animation-test","theme":"forest","initialGold":2000,"totalWaves":3,"tierIndex":0,"level":1,"difficulty":1.0,"recruitCost":60,"unitLimit":14,"objectives":[{"id":"main","x":0.95,"y":0.5,"hp":30}],"paths":[{"points":[[0.01,0.5],[0.5,0.5],[0.95,0.5]],"objectiveId":"main"}],"buildZones":[{"x":0.4,"y":0.36,"r":0.1},{"x":0.7,"y":0.36,"r":0.1}]}

func make_game() -> Node2D:
	var game: Node2D = Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.set_seed(42)
	game.load_map(map_fixture())
	game.start_battle()
	game.spawn_queue = ["raider"]
	game.spawn_clock = 10000.0
	return game

func assert_pixel_frames() -> void:
	for key in Battle.ANIMATED_UNIT_KEYS:
		var image: Image = Image.new()
		var result: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/units-animated/%s.png" % key))
		check(result == OK, "%s animated PNG is readable" % key)
		if result != OK:
			continue
		check(image.get_size() == Vector2i(1536,1024), "%s uses exact 6 by 4 frame grid" % key)
		var hashes: Dictionary = {}
		for row in range(4):
			for column in range(6):
				var pixels: Image = image.get_region(Rect2i(column*256,row*256,256,256))
				var digest: String = pixels.get_data().hex_encode().sha256_text()
				check(not hashes.has(digest), "%s row %d frame %d has a distinct actual pose" % [key,row,column])
				hashes[digest] = true
				distinct_frames += 1

func run() -> void:
	assert_pixel_frames()
	for unit_type in ["archer","spear","samurai","commander"]:
		var timing: Node2D = make_game()
		check(timing.recruit() and timing.place_unit(0.4,0.36), "%s timing fixture deploys" % unit_type)
		var soldier: Dictionary = timing.units[0]
		soldier.type = unit_type
		timing._spawn_enemy("raider")
		var target: Dictionary = timing.enemies[0]
		target.position = Vector2(0.45,0.36)
		target.speed = 0.0
		target.hp = 10000.0
		timing.advance_simulation(0.01)
		var release_time: float = timing._impact_time(unit_type)
		var expected_frame: int = 4 if unit_type in ["archer","samurai"] else 3
		check(is_equal_approx(release_time,float(expected_frame)/12.0), "%s uses its actual weapon impact pose" % unit_type)
		timing.advance_simulation(release_time-0.02)
		check(float(target.hp) == 10000.0 and timing.projectiles.is_empty(), "%s cannot damage before its impact frame" % unit_type)
		timing.advance_simulation(0.03)
		check(float(target.hp) < 10000.0 or not timing.projectiles.is_empty(), "%s attacks when its impact frame appears" % unit_type)
		timing.queue_free()
	var game: Node2D = make_game()
	check(game.animated_textures.size() == 6, "All six animated textures load; static atlas is not used")
	check(game.animation_manifest.get("baselineY",0) == 228, "Animation manifest loads actual frame baseline")
	for state in ["idle","walk","attack","death"]:
		var actor: Dictionary = {"type":"archer","animation":state,"animationClock":0.0,"animationPhase":0.0}
		var first: Dictionary = game.animation_frame_data(actor)
		actor.animationClock = 0.25
		var next: Dictionary = game.animation_frame_data(actor)
		check(first.source == "animated", "%s selects real animated sheet" % state)
		check(first.region.x != next.region.x and first.row == next.row, "%s changes crop frame within its own row" % state)
		check(first.row == int(Battle.ANIMATION_ROWS[state]), "%s uses correct frame row" % state)
	check(game.recruit() and game.place_unit(0.4,0.36), "Deploy a real animated friendly unit")
	var unit: Dictionary = game.units[0]
	check(game.snapshot().selected.animation == "walk", "Newly deployed unit uses walk sequence")
	var deploy_frame: int = int(game.snapshot().selected.animationFrame)
	game.advance_simulation(0.15)
	check(int(game.snapshot().selected.animationFrame) != deploy_frame, "Deployment plays consecutive walk frames")
	game.advance_simulation(0.25)
	check(str(unit.animation) == "idle", "Deployment ends in idle sequence")
	var idle_frame: int = int(game.snapshot().selected.animationFrame)
	game.advance_simulation(0.25)
	check(int(game.snapshot().selected.animationFrame) != idle_frame, "Friendly idle uses changing actual poses")
	game._spawn_enemy("raider")
	var enemy: Dictionary = game.enemies[0]
	enemy.position = Vector2(0.48,0.36)
	enemy.speed = 0.0
	enemy.hp = 10000.0
	enemy.maxHp = 10000.0
	unit.cooldown = 0.0
	game.advance_simulation(0.01)
	check(str(unit.animation) == "attack", "Target acquisition starts attack sequence")
	check(int(game.snapshot().selected.animationRow) == 2, "Attack renders actual attack row")
	var before_hp: float = float(enemy.hp)
	game.advance_simulation(0.25)
	check(enemy.hp == before_hp and game.projectiles.is_empty(), "Archer does not fire before draw-and-release frame")
	game.advance_simulation(0.09)
	check(int(game.snapshot().selected.animationFrame) == 4, "Archer reaches manifest release frame four")
	check(game.projectiles.size() == 1 or enemy.hp < before_hp, "Projectile releases at real bow-release frame")
	game.advance_simulation(0.2)
	check(str(unit.animation) == "idle", "Once-only attack returns to idle after six frames")
	check(enemy.hp < before_hp, "Released projectile damages its target")
	game.units.clear()
	enemy.speed = 0.02
	var walk_frame: int = int(game.animation_frame_data(enemy,0.0,true).frame)
	var previous_pos: Vector2 = enemy.position
	game.advance_simulation(0.15)
	check(str(enemy.animation) == "walk" and enemy.position != previous_pos, "Enemy path movement uses actual walk state")
	check(int(game.animation_frame_data(enemy,0.0,true).frame) != walk_frame, "Moving enemy advances real walk frames")
	game._damage_enemy(enemy,1.0,"archer")
	check(float(enemy.hitClock) > 0.0, "Damage triggers visible hit flash")
	var gold_before: int = game.gold
	var kills_before: int = game.kills
	game._damage_enemy(enemy,20000.0,"samurai")
	game.advance_simulation(0.01)
	check(game.enemies.is_empty() and game.death_actors.size() == 1, "Dead enemy leaves combat while death actor remains visible")
	check(game.gold == gold_before+int(enemy.reward) and game.kills == kills_before+1, "Kill gold and counter are credited once")
	var death_first: Dictionary = game.snapshot().deathActors[0]
	game.advance_simulation(0.2)
	check(game.death_actors.size() == 1, "Death animation survives multiple simulation ticks")
	check(int(game.snapshot().deathActors[0].animationFrame) != int(death_first.animationFrame), "Death actor advances through actual death crops")
	var death_clock: float = float(game.death_actors[0].animationClock)
	game.pause_battle()
	game._process(0.1)
	game.advance_simulation(0.1)
	check(float(game.death_actors[0].animationClock) == death_clock, "Pause freezes death sequence and simulation")
	game.pause_battle()
	var elapsed_before: float = game.elapsed
	game.set_speed(2.0)
	game._process(0.1)
	check(is_equal_approx(game.elapsed-elapsed_before,0.2), "Two-times speed advances simulation by two-times delta")
	check(is_equal_approx(float(game.death_actors[0].animationClock)-death_clock,0.2), "Two-times speed advances death frames by the same game delta")
	game.advance_simulation(0.4)
	check(game.death_actors.is_empty(), "Completed death sequence exits the field")
	check(game.gold == gold_before+int(enemy.reward) and game.kills == kills_before+1, "Death animation cannot grant duplicate kill reward")
	check(game.recruit() and game.place_unit(0.7,0.36), "Place second friendly for pause and enhancement checks")
	var selected: Dictionary = game.units[0]
	game.advance_simulation(0.4)
	var friendly_clock: float = float(selected.animationClock)
	game.pause_battle()
	game._process(0.1)
	check(float(selected.animationClock) == friendly_clock, "Pause freezes friendly idle frames")
	game.pause_battle()
	game.set_speed(1.0)
	game._process(0.1)
	check(is_equal_approx(float(selected.animationClock)-friendly_clock,0.1), "One-times idle animation follows game time")
	var parsed = JSON.parse_string(JSON.stringify(game.snapshot()))
	check(parsed is Dictionary and parsed.animationAssets.size() == 6, "Snapshot serializes actual animation assets and state")
	var loaded_textures: Dictionary = game.animated_textures
	game.animated_textures = {}
	check(game.animation_frame_data(selected).source == "static-fallback", "Missing sheet uses safe fallback before imports are available")
	game.animated_textures = loaded_textures
	game.load_map(map_fixture())
	check(game.death_actors.is_empty() and game.animation_time == 0.0, "Stage reset removes corpses and animation clocks")
	game.queue_free()
	print("ANIMATION_QA assertions=",assertions," distinct_actual_frames=",distinct_frames," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
