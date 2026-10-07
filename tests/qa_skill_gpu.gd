extends SceneTree
## Native HP/projectile receipts in a controlled visual fixture, not campaign balance.
const Battle=preload("res://native/game.gd")
const Troops=preload("res://native/troops_3d.gd")
const Feedback=preload("res://native/combat_feedback.gd")
var game: Node2D
var troops: Control
var feedback: Node2D
var checks: int=0
var failures: Array=[]
var receipts: Array=[]
var images: Array=[]

func _initialize() -> void: call_deferred("run")

func check(ok: bool,note: String) -> void:
	checks+=1
	if not ok:
		failures.append(note)
		push_error("SKILL_GPU: "+note)

func capture(name: String) -> void:
	# Review the live effect and pose after its onset instead of its zero-time edge.
	feedback._process(0)
	feedback._process(.14)
	game._advance_actor_animations(.14)
	troops.sync_actor_states(game.actor_states())
	troops.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	feedback.queue_redraw()
	game.queue_redraw()
	for unused in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var path: String="user://skill-"+name+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"Actual GPU frame saved: "+name)
	images.append(ProjectSettings.globalize_path(path))

func buy(id: String) -> Dictionary:
	var first_id: int=game.next_id
	var before: int=game.gold
	check(game.begin_placement(id,0),"Native parallel order starts: "+id)
	if not game.pending.is_empty():
		var paid: bool=false
		for zone in game.zones:
			var hint: Vector2=game._zone_placement_hint(zone,id)
			if hint.x>=0 and bool(game.placement_preview(hint).valid):
				paid=game.place_unit(hint.x,hint.y)
				if paid: break
		check(paid,"A valid paid post is reserved: "+id)
	check(game.gold<before,"The visual fixture consumes the native price: "+id)
	for unused in range(240):
		if game.recruitment_queue.is_empty(): break
		game.advance_simulation(.025)
	for unit in game.units:
		if int(unit.id)==first_id: return unit
	check(false,"Paid actor is produced: "+id)
	return {}

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/skill-gpu/").to_lower()):
		quit(2)
		return
	root.size=Vector2i(1440,900)
	root.content_scale_size=root.size
	game=Battle.new()
	root.add_child(game)
	game.set_process(false)
	game.field_rect=Rect2(0,0,1440,900)
	var catalog: Array=(JSON.parse_string(FileAccess.get_file_as_string("res://native/units.json")) as Dictionary).units
	game.configure_roster(catalog,["archer","spear","gunner","monk"],{"archer":8,"spear":8,"gunner":8,"monk":8})
	var stage: Dictionary=(JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")) as Array)[0].duplicate(true)
	var fixture: Dictionary={"id":"skill-gpu-component","theme":"farm","stageNumber":20,"initialGold":4000,"unitLimit":14,"totalWaves":10,"difficulty":1.0,"paths":[{"id":"road","objectiveId":"main","points":[{"x":.05,"y":.5},{"x":.95,"y":.5}]}],"objectives":[{"id":"main","x":.95,"y":.5,"hp":100}],"buildZones":[{"id":"wall","x":.5,"y":.68,"r":.18,"elevation":1}],"tactics":{"groundPosts":[{"id":"road","nameKo":"전선","pathIndex":0,"segmentIndex":0,"t":.55,"r":.22,"guardRadius":.2,"mobilityFactor":1.0}]}}
	game.load_map(fixture,20)
	game.start_battle()
	game.spawn_queue=["raider"]
	game.spawn_clock=100000
	troops=Troops.new()
	root.add_child(troops)
	troops.set_process(false)
	troops.set_field_size(Vector2(1440,900))
	troops.set_stage(stage)
	troops.bind_battle(game)
	game.three_d_enabled=true
	feedback=Feedback.new()
	feedback.battle=game
	feedback.troop_renderer=troops
	feedback.font=load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	root.add_child(feedback)
	feedback.set_process(false)
	game.game_event.connect(func(event: Dictionary): receipts.append(event.duplicate(true)); feedback.consume_event(event))
	var archer: Dictionary=buy("archer")
	var gunner: Dictionary=buy("gunner")
	var monk: Dictionary=buy("monk")
	var spear: Dictionary=buy("spear")
	if archer.is_empty() or gunner.is_empty() or monk.is_empty() or spear.is_empty():
		quit(1)
		return
	# Keep this component tableau legible; these positions/HP are fixture inputs.
	archer.position=Vector2(.40,.62)
	gunner.position=Vector2(.53,.56)
	monk.position=Vector2(.59,.62)
	spear.position=Vector2(.63,.5)
	var enemy: Dictionary=game._spawn_enemy("shield",1,{"pathIndex":0})
	enemy.position=Vector2(.49,.5)
	enemy.hp=1000.0
	enemy.maxHp=1000.0
	var plan: Dictionary=game.unit_skills.prepare_attack(archer,enemy,float(game._stats(archer).damage),0.0)
	archer.animation="attack"
	archer.animationClock=.23
	archer.attackDuration=.56
	archer.aim=(enemy.position-archer.position).normalized()
	game._release_unit_attack(archer,plan)
	check(game.projectiles.size()==3,"Native Lv8 barrage commits three separate projectiles")
	game._update_projectiles(.10)
	await capture("fire-barrage")
	var before_hp: float=float(enemy.hp)
	for unused in range(12): game._update_projectiles(.05)
	check(float(enemy.hp)<before_hp and bool(game.unit_skills.enemy_state(enemy).flags.burning),"Real projectile impact damages HP and applies the fire status")
	var gun_plan: Dictionary=game.unit_skills.prepare_attack(gunner,enemy,float(game._stats(gunner).damage),0.0)
	game._release_unit_attack(gunner,gun_plan)
	game._update_projectiles(.1)
	check(bool(game.unit_skills.enemy_state(enemy).flags.armorWeakened),"Real gunner impact applies its native armor debuff")
	game._damage_enemy(enemy,5.0,"spear",game._attack_source(spear))
	check(bool(game.unit_skills.enemy_state(enemy).flags.poisoned),"Actual spear HP hit applies poison without fabricated effect flags")
	await capture("status-impact")
	feedback.reset()
	archer.hp=float(archer.maxHp)-24.0
	var before_heal: float=float(archer.hp)
	var healed: float=game.unit_skills._heal(monk,archer,6.0,"monk_heal","heal")
	check(healed==6 and float(archer.hp)==before_heal+6 and str(monk.animation)=="heal","Native healing updates HP, emits a receipt and sets the real support pose")
	await capture("support-heal")
	var report: FileAccess=FileAccess.open("user://qa_skill_gpu.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"images":images,"receipts":receipts,"scope":"Controlled native skill HP/projectile/pose visual fixture. Fixture HP/positions/unlocks are not ordinary campaign or balance evidence."},"\t"))
	report.close()
	feedback.queue_free()
	troops.queue_free()
	game.queue_free()
	for unused in range(8): await process_frame
	print("SKILL_GPU checks=%d failures=%d images=%d" % [checks,failures.size(),images.size()])
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
