extends SceneTree
## Independent saved campaign -> UI selection -> deployment -> 3D renderer checks.
## Uses an isolated save path and never overwrites player progress or native sources.

const Store = preload("res://native/progress.gd")
const Ruby = preload("res://native/ruby_label.gd")
const LEVELS = {"archer":1,"spear":3,"samurai":4,"gunner":7,"naginata":8,"monk":9,"commander":8,"ninja":10}
var app: Node
var checks: int = 0
var failures: Array = []
var observations: Array = []
var isolated_path: String

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("ROSTER INTEGRATION "+message)

func key_event(code: int) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func card_word(card: Node) -> Control:
	for child in card.get_children():
		if child.get_script() == Ruby:
			return child
	return null

func placement_point() -> Vector2:
	app.game._refresh_placement_hints()
	for point in app.game.placement_hints:
		if point.x >= 0:
			return point
	return Vector2(-1,-1)

func model_signature(actor: Node3D) -> Dictionary:
	var mesh_hashes: Array = []
	var materials: Array = []
	var vertices: int = 0
	var triangles: int = 0
	for instance in actor.meshes:
		for surface in range(instance.mesh.get_surface_count()):
			var arrays = instance.mesh.surface_get_arrays(surface)
			vertices += arrays[Mesh.ARRAY_VERTEX].size()
			triangles += arrays[Mesh.ARRAY_INDEX].size()/3
			mesh_hashes.append(hash(arrays[Mesh.ARRAY_VERTEX]))
		var material = instance.material_override
		if material is StandardMaterial3D:
			materials.append(material.albedo_color.to_html(true))
	return {"vertices":vertices,"triangles":triangles,"geometry":hash(mesh_hashes),"appearance":hash(materials)}

func deploy(id: String) -> Dictionary:
	app._choose_unit(id)
	check(app.chosen_unit_id==id and str(app.progress.data.army.selected)==id,id+": selected UI and saved selection agree")
	var before_gold: int = app.game.gold
	var before_wallet: int = app.progress.data.army.currency
	app._recruit()
	check(str(app.game.pending.get("type",""))==id,id+": recruit chooses this specific class")
	if app.game.pending.is_empty():
		return {}
	check(int(app.game.pending.campaignLevel)==app.progress.army_level(id),id+": recruitment retains saved training level")
	check(int(app.game.pending.evolution)==int(app.progress.army_evolution(id).stage),id+": recruitment uses the displayed evolution")
	check(before_gold-app.game.gold==int(app.progress.unit_definition(id).cost),id+": displayed supply cost is debited once")
	check(app.progress.data.army.currency==before_wallet,id+": recruitment does not spend permanent army funds")
	var point: Vector2 = placement_point()
	check(point.x>=0,id+": actual stage has another legal deployment position")
	if point.x<0:
		app.game.cancel_recruit()
		return {}
	check(app.game.place_unit(point.x,point.y),id+": selected class places on a legal stage hint")
	var deployed: Dictionary = app.game.units.back()
	check(str(deployed.type)==id and int(deployed.campaignLevel)==app.progress.army_level(id),id+": placed unit keeps selected class and training")
	check(app.selected_label.text.contains("Lv.%d" % app.progress.army_level(id)),id+": actual selected-unit HUD shows permanent level")
	var displayed: Dictionary=app.progress.army_evolution(id)
	check(str(app.selected_word.word.jp)==str(displayed.jp) and str(app.selected_word.word.reading)==str(displayed.reading) and str(app.selected_word.word.ko)==str(displayed.name),id+": actual selected HUD retains evolution ruby and Korean name")
	return deployed

func check_rendered(deployed: Dictionary) -> Dictionary:
	if deployed.is_empty():
		return {}
	var id: String = str(deployed.type)
	var source: Dictionary = {}
	for state in app.game.actor_states():
		if int(state.id)==int(deployed.id) and bool(state.friendly):
			source=state
			break
	check(not source.is_empty(),id+": deployed unit is supplied to the real renderer")
	if source.is_empty():
		return {}
	check(int(source.get("campaignLevel",-1))==int(deployed.campaignLevel),id+": renderer receives permanent training level")
	check(int(source.get("evolution",-1))==int(deployed.evolution),id+": renderer receives evolution stage")
	check(float(source.get("attackDuration",0.0))>0.0,id+": renderer receives actual attack duration")
	app.troops_3d.sync_actor_states(app.game.actor_states())
	var model_key: String = "%d:0" % int(deployed.id)
	check(app.troops_3d.actors.has(model_key),id+": real 3D model exists for deployed actor")
	if not app.troops_3d.actors.has(model_key):
		return {}
	var actor: Node3D = app.troops_3d.actors[model_key]
	check(str(actor.unit_type)==id,id+": model retains the eight-class identity")
	check(int(actor.evolution_stage)==int(deployed.evolution),id+": model actually selects the saved evolution geometry")
	check(actor.meshes.size()>0,id+": model has rendered geometry")
	return model_signature(actor)

func check_navigation_guard(context: String) -> void:
	var supply: int = app.game.gold
	var wallet: int = app.progress.data.army.currency
	var unit_count: int = app.game.units.size()
	var pending: String = JSON.stringify(app.game.pending)
	var selected: String = JSON.stringify(app.game._selected())
	for code in [KEY_R,KEY_U,KEY_M,KEY_SPACE]:
		app._input(key_event(code))
		app._unhandled_key_input(key_event(code))
	check(app.game.gold==supply and app.game.units.size()==unit_count and JSON.stringify(app.game.pending)==pending,context+": hidden combat shortcuts cannot recruit or mutate units")
	check(app.progress.data.army.currency==wallet and JSON.stringify(app.game._selected())==selected,context+": navigation shortcuts cannot debit either wallet or alter hidden selection")

func run() -> void:
	root.size=Vector2i(1440,900)
	isolated_path="user://roster-integration-%d.json" % Time.get_ticks_usec()
	var fixture=Store.new()
	fixture.save_path=isolated_path
	for stage in JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json")):
		fixture.data.maps[str(stage.id)]={"wins":1}
	fixture.data.army.currency=100000
	fixture.data.army.levels=LEVELS.duplicate(true)
	fixture.data.army.selected="gunner"
	fixture.data.settings={"music":false,"voice":false}
	check(fixture.write_save(),"Isolated integration fixture is persisted")
	app=load("res://native/main.tscn").instantiate()
	app.progress.save_path=isolated_path
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.game.set_process(false)
	app.player.stop()
	check(app.progress.unlocked_units().size()==8 and app.army_grid.get_child_count()==8,"Actual UI exposes exactly eight unlocked classes")
	check(app.chosen_unit_id=="gunner","Saved specific class is restored by the actual application")
	check_navigation_guard("home")
	for definition in app.progress.unit_catalog:
		var id: String = str(definition.id)
		var card: Node = app.army_grid.get_node("DeployCard_%s" % id)
		var evolution: Dictionary = app.progress.army_evolution(id)
		var displayed_name: bool=false
		var displayed_cost: bool=false
		for label in card.find_children("*","Label",true,false):
			var compact: String=label.text.replace(" ","")
			displayed_name=displayed_name or (not compact.is_empty() and str(definition.name).replace(" ","").begins_with(compact))
			displayed_cost=displayed_cost or label.text=="%d 補" % int(definition.cost)
		check(displayed_name and displayed_cost,id+": actual redesigned command card displays class name and real supply cost")
		var portrait: TextureRect=card.get_node("UnitPortrait_%s" % id)
		var expected_source: String = "res://assets/units-animated/%s.png" % id if id in ["archer","spear","samurai","commander"] else "res://assets/units-standing/idle-support-v1.png"
		check(portrait.texture is AtlasTexture and portrait.texture.atlas.resource_path==expected_source and str(portrait.get_meta("unit_id",""))==id,id+": command card displays the saved class's approved authored portrait")
		check(not bool(portrait.get_meta("visual_evolution",true)),id+": class artwork does not claim separate evolution poses; actual evolution remains in name, stats and battlefield equipment")
	app._choose_stage(0,0)
	app._begin_battle()
	app.game.gold=10000
	app.game._emit_state()
	for definition in app.progress.unit_catalog:
		var deployed: Dictionary = deploy(str(definition.id))
		var signature: Dictionary = check_rendered(deployed)
		observations.append({"class":definition.id,"level":app.progress.army_level(str(definition.id)),"evolution":app.progress.army_evolution(str(definition.id)).stage,"model":signature})
	app._show_home()
	check(app.game.paused and not app.game.input_enabled,"Home pauses the live battle and disables field input")
	check_navigation_guard("home with active battle")
	app._show_barracks()
	await process_frame
	check(app.barracks.visible and not app.barracks.can_train,"Active battle disables permanent training")
	check_navigation_guard("barracks with active battle")
	for node in app.barracks.find_children("Train_*","Button",true,false):
		check(node.disabled,"Active-battle barracks cannot use training buttons")
	app.barracks.hide()
	app._return_from_barracks()
	app._resume_from_navigation()
	check(not app.game.paused and app.game.input_enabled,"Return from barracks/home restores the previously running field")
	app._show_catalog()
	check_navigation_guard("catalog")
	app._resume_from_navigation()
	# Same stage, seed and pose: growth must alter the real model, not only a label.
	var evolution_geometry: Dictionary = {}
	for level in [1,4,8]:
		for id in LEVELS:
			app.progress.data.army.levels[id]=level
		app._choose_stage(0,0)
		app._begin_battle()
		app.game.gold=10000
		app.game._emit_state()
		for definition in app.progress.unit_catalog:
			var id: String=str(definition.id)
			var deployed: Dictionary=deploy(id)
			var signature: Dictionary=check_rendered(deployed)
			if not evolution_geometry.has(id): evolution_geometry[id]=[]
			evolution_geometry[id].append(signature)
	for id in evolution_geometry:
		var forms: Array=evolution_geometry[id]
		for stage in [1,2]:
			if forms[stage].is_empty() or forms[stage-1].is_empty(): continue
			check(forms[stage].geometry!=forms[stage-1].geometry,id+": evolution changes actual equipment/mesh geometry")
			check(forms[stage].appearance!=forms[stage-1].appearance or forms[stage].vertices!=forms[stage-1].vertices,id+": evolution has a rendered appearance difference")
	# Duplicate end-event delivery must not become repeat-clear farming.
	app.answers_correct=2
	var before_wallet: int=app.progress.data.army.currency
	var before_wins: int=int(app.progress.data.maps[str(app.current_map.id)].wins)
	app._on_battle_finished({"victory":true})
	var after_wallet: int=app.progress.data.army.currency
	check(after_wallet-before_wallet==52,"One repeat-stage victory credits its clear and two-answer rewards once")
	app._on_battle_finished({"victory":true})
	check(app.progress.data.army.currency==after_wallet and int(app.progress.data.maps[str(app.current_map.id)].wins)==before_wins+1,"Duplicate victory delivery changes neither wallet nor win count")
	var reopened=Store.new()
	reopened.save_path=isolated_path
	reopened.read_save()
	check(reopened.data.army.currency==after_wallet and reopened.data.army.selected==app.chosen_unit_id,"Real completion persists the wallet and selected class")
	check(reopened.data.army.levels==app.progress.data.army.levels,"Deployed permanent levels survive reopen")
	app._show_home()
	app._show_barracks()
	await process_frame
	check(app.barracks.can_train,"Completed battle re-enables permanent training")
	var before_level: int=app.progress.army_level("archer")
	var before_training_wallet: int=app.progress.data.army.currency
	var training_cost: int=app.progress.army_upgrade_cost("archer")
	app.barracks._train("archer")
	await process_frame
	check(app.progress.army_level("archer")==before_level+1 and app.progress.data.army.currency==before_training_wallet-training_cost,"Actual barracks training charges once and updates saved level")
	var report={"checks":checks,"failures":failures,"classes":observations,"evolutionGeometry":evolution_geometry,"savePath":isolated_path,"scope":"Real Main/Progress/Battle/Troops integration using an isolated campaign save; low-detail geometry/material changes are observed. Screen layout legibility is verified by root GPU capture separately."}
	var file=FileAccess.open("user://qa_roster_integration.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ROSTER_INTEGRATION_QA ",JSON.stringify({"checks":checks,"failures":failures,"classes":observations.size()}))
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
