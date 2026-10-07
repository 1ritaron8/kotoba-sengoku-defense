extends SceneTree
## Headless controller checks. Only real engine hits can complete a drill.
const Training = preload("res://native/unit_training.gd")
const Progress = preload("res://native/progress.gd")
const Battle = preload("res://native/game.gd")
const ORDER: Array = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array[String] = []
var maps: Array = []
var account: RefCounted
var account_before: String = ""
var map_bytes: String = ""
var controller: Control
var face: Font
var completion_count: Dictionary = {}
var closed_count: int = 0
var campaign: Node2D
var campaign_before: Dictionary = {}
var lessons: Array = []
var layouts: Array = []
var footer_layouts: Array = []
var save_before: String = ""
var save_existed: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		if failures.size() <= 24:
			push_error("TRAINING: " + message)

func make_controller(player: RefCounted) -> Control:
	var drill: Control = Training.new()
	drill.render_enabled = false
	root.add_child(drill)
	drill.configure(player,maps,face)
	drill.completed.connect(func(id: String): completion_count[id] = int(completion_count.get(id,0)) + 1)
	drill.closed.connect(func(): closed_count += 1)
	return drill

func settle() -> void:
	await process_frame
	await process_frame

func buttons(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button and child.has_meta("trainingUnit"):
			result.append(child)
		result.append_array(buttons(child))
	return result

func check_text(node: Node) -> void:
	for child in node.get_children():
		if child is Label or child is Button:
			check(int(child.get_theme_font_size("font_size")) >= 20,"training UI text is at least 20px: " + str(child.get("text")))
		check_text(child)

func check_isolation(label: String) -> void:
	check(JSON.stringify(account.data) == account_before,label + " leaves the account, language SRS and permanent currency unchanged")
	check(FileAccess.get_file_as_string("res://native/maps.json") == map_bytes,label + " leaves all 40 authored maps unchanged")
	var public: Dictionary = campaign.snapshot()
	check(public.gold == campaign_before.gold and public.wave == campaign_before.wave and public.units == campaign_before.units and public.battleElapsedSeconds == campaign_before.battleElapsedSeconds,label + " cannot advance or spend the separate campaign battle")
	check(FileAccess.file_exists(account.save_path) == save_existed,label + " does not create an account save")
	if save_existed:
		check(FileAccess.get_file_as_string(account.save_path) == save_before,label + " does not rewrite an existing account save")

func menu_and_gate() -> void:
	var new_player: RefCounted = Progress.new()
	var before: String = JSON.stringify(new_player.data)
	var first: Control = make_controller(new_player)
	first.open_menu()
	await settle()
	var choices: Array = buttons(first)
	check(first.view == "menu" and first.battle == null,"a separate menu does not create or start a battle")
	check(choices.size() == 8,"menu offers exactly the eight campaign classes")
	var available: Array = []
	for button in choices:
		if not button.disabled:
			available.append(str(button.get_meta("trainingUnit")))
	check(available == ["archer","spear"],"a new account can train only the initially unlocked classes")
	check(not first.open("ninja",maps[14]),"locked ninja training is refused")
	check(first.view == "menu" and first.battle == null,"a refused lesson does not replace the menu with a battle")
	check(not first.open("not-a-class",maps[0]),"unknown classes are refused")
	check(not first.open("archer",{}),"missing source geometry is refused")
	check_text(first)
	check(JSON.stringify(new_player.data) == before,"menu and rejected actions do not change a new account")
	var count: int = closed_count
	first.close()
	first.close()
	check(closed_count == count + 1,"closing a menu emits exactly one closed signal")
	first.queue_free()
	await settle()

func lesson(id: String, stage: Dictionary, representative: bool) -> void:
	var label: String = str(stage.id) + "/" + id
	var before_completion: int = int(completion_count.get(id,0))
	check(controller.open(id,stage),label + " opens an isolated lesson on the source geometry")
	controller.set_process(false)
	await settle()
	if not is_instance_valid(controller.battle):
		return
	var battle: Node2D = controller.battle
	check(not bool(controller.diagnostics().rendererActive),label + " does not start a GPU renderer in CPU QA")
	check(not battle.is_processing() and not battle.is_processing_input() and not battle.is_processing_unhandled_input(),label + " keeps native automatic/input callbacks disabled")
	check(battle.config.paths == stage.paths and battle.config.objectives == stage.objectives and battle.config.buildZones == stage.buildZones and battle.config.tactics == stage.tactics,label + " preserves authored paths, objectives and placement zones")
	check(int(battle.config.stageNumber) == int(stage.stageNumber) and float(battle.config.difficulty) == float(stage.difficulty),label + " preserves source stage and native difficulty")
	check(battle.battle_minutes == 0 and battle.elapsed == 0 and battle.enemies.is_empty(),label + " is independent of timed campaign schedules")
	var role: String = str(battle.placement_contract(id).deploymentKind)
	var wallet: int = battle.gold
	var needed: int = int(account.unit_definition(id).cost)
	check(wallet == needed,label + " provides exactly one native class cost in its isolated fixture")
	check(controller.recommended.x >= 0,label + " highlights an existing legal class location")
	controller.advance_training(30)
	check(controller.elapsed_seconds == 0 and battle.elapsed == 0,label + " does not run before deployment")
	check(controller.deploy(),label + " accepts the native deploy/dispatch action")
	if role != "marching":
		check(controller.phase == "placing" and battle.gold == wallet,label + " prepares a placement without spending")
		check(not controller.place_at(Vector2(-1,-1)),label + " refuses an invalid placement")
		check(battle.gold == wallet and battle.units.is_empty(),label + " invalid placement cannot spend currency or create a unit")
		check(controller.deploy() and battle.gold == wallet,label + " repeated placement preparation cannot debit twice")
		check(controller.place_at(controller.recommended),label + " commits the highlighted native placement")
	check(controller.phase=="producing" and battle.units.is_empty() and battle.snapshot().recruitmentQueue.size()==1,label + " queues a paid order before creating an actor")
	check(battle.gold==wallet-needed,label + " production pays exactly once at accepted order time")
	var recruit_seconds: float = float(account.unit_definition(id).recruitSeconds)
	controller.advance_training(recruit_seconds-.05)
	check(battle.units.is_empty() and controller.phase=="producing",label + " an unfinished production cannot create its actor early")
	controller.advance_training(.05)
	if battle.units.is_empty():
		check(false,label + " created no actor after the complete generation time")
		controller.close()
		await settle()
		return
	var actor: Dictionary = battle.units[0]
	check(battle.gold == wallet - needed and battle.recruits == 1,label + " charges the real unit cost exactly once")
	check(int(actor.campaignLevel) == 1,label + " learns the native starting class without injecting training upgrades")
	check(actor.definition == account.unit_definition(id),label + " does not rewrite the unit's combat definition")
	check(controller.current_goal().step == 2 and not controller.current_goal().completed,label + " actual attack remains required after deployment")
	check(not controller.deploy(),label + " cannot recruit an extra paid unit during the one-unit drill")
	var targets: Array = []
	var hp_before: float = 0
	if id=="monk":
		targets.append(controller._patient)
		hp_before=float(controller._patient.hp)
		check(battle.enemies.is_empty() and battle.units.size()==2,label + " pure support practices with an actual injured ally")
	else:
		for enemy in battle.enemies:
			targets.append(enemy)
			hp_before += float(enemy.hp)
		check(targets.size() == 1 and hp_before > 0,label + " uses one real live practice enemy")
	var events: Array = []
	battle.game_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	if id == "ninja":
		check(not targets.is_empty() and bool(targets[0].get("fortification",false)),label + " uses a native stationary enemy fort")
		var command: Dictionary = controller.issue_assassination()
		check(bool(command.accepted),label + " accepts an actual native assassination order: " + str(command.get("reasonKo","")))
		var duplicate: Dictionary = controller.issue_assassination()
		check(not bool(duplicate.accepted) and bool(duplicate.get("duplicate",false)),label + " refuses duplicate assassination orders")
		check(int(controller.observations.orders) == 1,label + " counts only an accepted order")
	if representative:
		battle.paused = true
		var frozen: Vector2 = actor.position
		var frozen_time: float = controller.elapsed_seconds
		controller.advance_training(120)
		check(actor.position == frozen and controller.elapsed_seconds == frozen_time and is_equal_approx(battle.elapsed,frozen_time),label + " pause freezes both the drill and the native battlefield")
		battle.paused = false
		controller.advance_training(0)
		controller.advance_training(-1)
		controller.advance_training(NAN)
		controller.advance_training(INF)
		check(controller.elapsed_seconds == frozen_time and is_equal_approx(battle.elapsed,frozen_time),label + " nonpositive/nonfinite deltas cannot advance the drill")
	for tick in range(1600):
		if controller.phase != "combat":
			break
		controller.advance_training(.05)
	var data: Dictionary = controller.diagnostics()
	var hp_after: float = 0
	for enemy in targets:
		hp_after += maxf(0,float(enemy.hp))
	var hit_count: int = 0
	var native_damage: float = 0
	var heal_count: int = 0
	var native_healing: float = 0
	for event in events:
		if str(event.type) == "hit" and str(event.get("side","")) == "friendly" and str(event.get("unitType","")) == id:
			hit_count += 1
			native_damage += float(event.damage)
			check(float(event.hpBefore) > float(event.hpAfter),label + " a recorded hit lowers actual target health")
		if str(event.type)=="heal" and str(event.get("unitType",""))==id and float(event.get("healAmount",0))>0:
			heal_count+=1
			native_healing+=float(event.healAmount)
			check(float(event.hpAfter)>float(event.hpBefore),label + " actual support events increase living ally HP")
	check(data.status == "success",label + " finishes from actual combat within the practice limit: " + str(data.goal.errorKo))
	if id=="monk":
		check(hit_count==0 and native_damage==0 and heal_count>=2 and native_healing>=12 and hp_after>hp_before,label + " support success requires real recovery and no enemy attacks")
		check(int(data.heals)==heal_count and absf(float(data.healingAmount)-native_healing)<.001,label + " observed healing equals live HP/event evidence")
	else:
		check(hit_count > 0 and native_damage > 0 and hp_before > hp_after,label + " success is backed by native hit events and real HP reduction")
		check(int(data.hits) == hit_count and absf(float(data.damage) - native_damage) < .001,label + " observed hit/damage totals match actual engine events")
	check(int(data.deployments) == 1,label + " observes one actual deployed actor")
	check(controller.elapsed_seconds <= Training.TRAINING_LIMIT_SECONDS and absf(controller.elapsed_seconds - battle.elapsed) < .00001,label + " keeps its clock equal to pure native practice time")
	if role == "marching":
		check(float(data.distanceAdvanced) > .015,label + " marching completion requires real forward movement")
	if id == "ninja":
		check(bool(data.fortDestroyed) and bool(data.returnObserved) and float(targets[0].hp) <= 0,label + " requires fort destruction and an actual return to cover")
		check(actor.position.distance_to(actor.homePosition) < .008 and str(actor.combatState) == "ambush_wait",label + " stops at the original cover after assassination")
	check(int(completion_count.get(id,0)) == before_completion + 1,label + " emits one completion signal after actual success")
	controller.advance_training(200)
	controller._evaluate_completion()
	check(int(completion_count.get(id,0)) == before_completion + 1,label + " cannot duplicate completion after the lesson ends")
	if representative:
		check_text(controller)
		check(controller.retry(),label + " allows retry without a campaign reward")
		controller.set_process(false)
		await settle()
		check(controller.phase == "ready" and controller.actor_id == -1 and controller.elapsed_seconds == 0 and int(controller.observations.hits) == 0,label + " retry resets the actor, time and observed hit evidence")
	lessons.append({"stageId":str(stage.id),"unitId":id,"status":str(data.status),"elapsedSeconds":float(data.elapsedSeconds),"hits":int(data.hits),"damage":float(data.damage),"distanceAdvanced":float(data.distanceAdvanced),"returnObserved":bool(data.returnObserved),"errorKo":str(data.goal.errorKo)})
	check_isolation(label)
	controller.close()
	await settle()

func lifecycle_failures() -> void:
	check(controller.open("archer",maps[0]),"failure-path practice opens")
	controller.set_process(false)
	await settle()
	var live: Node2D = controller.battle
	check(not controller.open("archer",{}),"invalid source is refused while a lesson is open")
	check(controller.battle == live and controller.phase == "ready","a refused open preserves the existing independent lesson")
	controller.deploy()
	controller.place_at(controller.recommended)
	controller.advance_training(float(account.unit_definition("archer").recruitSeconds))
	live.enemies.clear()
	var completion: int = int(completion_count.get("archer",0))
	controller.advance_training(80)
	check(controller.phase == "failed" and not controller.current_goal().completed,"absence of actual hits fails rather than fabricating completion")
	check(absf(controller.elapsed_seconds - Training.TRAINING_LIMIT_SECONDS) < .00001 and live.paused and not live.running,"a failed lesson stops at its finite training time")
	check(int(completion_count.get("archer",0)) == completion,"failure emits no completion or reward")
	check(controller.retry(),"failed lessons can be retried")
	controller.set_process(false)
	check(controller.phase == "ready" and controller.battle != live,"retry creates a fresh independent battlefield")
	controller.close()
	await settle()
	controller.completed.connect(func(_id: String): controller.close(),CONNECT_ONE_SHOT)
	controller.open("archer",maps[0])
	controller.set_process(false)
	await settle()
	controller.deploy()
	controller.place_at(controller.recommended)
	controller.advance_training(20)
	check(controller.phase == "closed" and controller.battle == null,"a completion callback may synchronously close the drill safely")
	await settle()
	check_isolation("failure/retry/close")

func menu_layout() -> void:
	for screen in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = screen
		root.content_scale_size = screen
		controller.open_menu("ninja")
		await settle()
		var logical_width: float = controller.get_viewport_rect().size.x
		check(absf(logical_width - screen.x) < .01,"CPU layout samples the requested canvas width " + str(screen))
		check_footer(screen,"menu")
		var available: int = 0
		for button in buttons(controller):
			if not button.disabled:
				available += 1
			check(button.size.x >= 120 and button.size.y >= 48,"menu control stays usable at " + str(screen))
			check(button.get_global_rect().position.x >= 0 and button.get_global_rect().end.x <= logical_width + 1,"menu control fits the canvas width at " + str(screen))
		check(available == 8,"all legitimately unlocked classes are available at " + str(screen))
		layouts.append({"width":screen.x,"height":screen.y,"available":available})
		for id in ORDER:
			controller.open(id,maps[clampi(int(account.unit_definition(id).unlockClears),0,maps.size()-1)])
			controller.set_process(false)
			await settle()
			check_footer(screen,id + "/ready")
			controller.deploy()
			if controller.phase == "placing":
				controller.place_at(controller.recommended)
			await settle()
			check_footer(screen,id + "/combat")
	controller.close()
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	await settle()

func rect_data(rect: Rect2) -> Dictionary:
	return {"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y}

func check_footer(screen: Vector2i, context: String) -> void:
	var label: String = str(screen) + "/" + context
	var footer: HBoxContainer = controller.footer_box
	var help: Label = controller.footer_hint
	var bounds: Rect2 = controller.get_global_rect()
	var footer_rect: Rect2 = footer.get_global_rect()
	var help_rect: Rect2 = help.get_global_rect()
	var help_font: Font = help.get_theme_font("font")
	var help_size: int = help.get_theme_font_size("font_size")
	var help_glyph: Vector2 = help_font.get_string_size(help.text,HORIZONTAL_ALIGNMENT_LEFT,-1,help_size)
	check(footer_rect.size.y >= 48 and footer_rect.size.y <= 60,label + " footer stays between 48px and 60px tall")
	check(bounds.grow(1).encloses(footer_rect),label + " footer stays inside the screen")
	check(footer_rect.grow(1).encloses(help_rect),label + " help fits inside the footer")
	check(help_rect.size.x >= help_glyph.x - .01 and help_rect.size.y >= help_glyph.y - .01,label + " help owns enough width and height for its actual font glyphs")
	check(help.get_line_count() == 1 and help.get_visible_line_count() == 1,label + " help remains one fully visible horizontal line")
	check(help.size_flags_horizontal == Control.SIZE_EXPAND_FILL,label + " help fills the available horizontal space")
	var controls: Array = []
	var previous_end: float = footer_rect.position.x
	for child in footer.get_children():
		if not child is Control or not child.visible:
			continue
		var rect: Rect2 = child.get_global_rect()
		check(footer_rect.grow(1).encloses(rect),label + " footer child stays within its row")
		check(rect.position.x >= previous_end - .01,label + " footer controls cannot overlap")
		previous_end = rect.end.x
		if child is Button:
			var button_font: Font = child.get_theme_font("font")
			var button_size: int = child.get_theme_font_size("font_size")
			var glyph: Vector2 = button_font.get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button_size)
			var padding: Vector2 = child.get_theme_stylebox("normal").get_minimum_size()
			check(rect.size.x >= glyph.x + padding.x - .1 and rect.size.y >= glyph.y + padding.y - .1,label + " button fits its actual glyphs and style padding: " + str(child.text))
			controls.append({"text":child.text,"rect":rect_data(rect),"glyph":{"w":glyph.x,"h":glyph.y}})
	var goal: Dictionary = {}
	if controller.view == "training":
		var title: Label = controller.goal_label
		var goal_glyph: Vector2 = title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size"))
		var goal_rect: Rect2 = title.get_global_rect()
		check(title.get_line_count() == 1 and title.get_visible_line_count() == 1,label + " side goal stays on one fully visible line")
		check(goal_rect.size.x >= goal_glyph.x - .01 and goal_rect.size.y >= goal_glyph.y - .01,label + " side goal fits the actual font glyphs")
		check(bounds.grow(1).encloses(goal_rect) and bounds.grow(1).encloses(controller.field_clip.get_global_rect()),label + " goal and battlefield stay within the screen")
		if controller.phase == "combat" and controller.unit_id != "ninja":
			check(title.text == "2 / 2 · 실제 명중 확인",label + " combat goal uses the concise approved wording")
		goal = {"text":title.text,"rect":rect_data(goal_rect),"glyph":{"w":goal_glyph.x,"h":goal_glyph.y}}
	footer_layouts.append({"width":screen.x,"height":screen.y,"context":context,"footer":rect_data(footer_rect),"help":rect_data(help_rect),"helpGlyph":{"w":help_glyph.x,"h":help_glyph.y},"helpLines":help.get_line_count(),"buttons":controls,"goal":goal})

func run() -> void:
	map_bytes = FileAccess.get_file_as_string("res://native/maps.json")
	maps = JSON.parse_string(map_bytes)
	face = load("res://assets/fonts/NotoSansCJKjp-Regular.otf")
	root.size = Vector2i(1440,900)
	check(DisplayServer.get_name() == "headless","training verification uses no GPU window")
	await menu_and_gate()
	account = Progress.new()
	account.save_path = "user://unit-training-never-write.json"
	for stage in maps:
		account.data.maps[str(stage.id)] = {"cleared":true}
	account_before = JSON.stringify(account.data)
	save_existed = FileAccess.file_exists(account.save_path)
	if save_existed:
		save_before = FileAccess.get_file_as_string(account.save_path)
	campaign = Battle.new()
	root.add_child(campaign)
	campaign.set_process(false)
	campaign.load_map(maps[0],5)
	campaign_before = campaign.snapshot().duplicate(true)
	controller = make_controller(account)
	for id in ORDER:
		var stage: Dictionary = maps[clampi(int(account.unit_definition(id).unlockClears),0,maps.size()-1)]
		await lesson(id,stage,true)
	print("TRAINING representative lessons verified; checking all authored terrain contexts")
	for stage in maps:
		for id in ORDER:
			if id == "ninja" and int(stage.stageNumber) < 15:
				continue
			await lesson(id,stage,false)
	await lifecycle_failures()
	await menu_layout()
	controller.queue_free()
	campaign.queue_free()
	await settle()
	var report: Dictionary = {"checks":checks,"failed":failures.size(),"failures":failures,"lessons":lessons,"layouts":layouts,"footerLayouts":footer_layouts,"scope":"CPU/headless: actual native deployment, movement, HP loss, ninja assassination/return, UI layout including actual footer/button/font glyph bounds, unlocks, retry and account/campaign isolation; no GPU visual validation or new counter/synergy design"}
	var file: FileAccess = FileAccess.open("res://tests/qa_unit_training.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify({"checks":checks,"failed":failures.size(),"actualLessons":lessons.size(),"layouts":layouts,"footerContexts":footer_layouts.size()}))
	quit(0 if failures.is_empty() else 1)
