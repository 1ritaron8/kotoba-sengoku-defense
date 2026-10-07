extends SceneTree

const Actor = preload("res://native/sengoku_actor_3d.gd")
const Troops = preload("res://native/troops_3d.gd")
const Game = preload("res://native/game.gd")
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("3D QA: "+message)
		quit(1)
		assert(value,message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for type_name in ["archer","spear","samurai","commander","enemy_light","enemy_heavy"]:
		var actor = Actor.new()
		root.add_child(actor)
		actor.configure(type_name,type_name.begins_with("enemy"),13)
		var info: Dictionary = actor.diagnostics()
		check(info.unreferencedVertices == 0,type_name+" has undrawn shell vertices")
		check(info.triangleEstimate > 1000,type_name+" real geometry missing")
		check(info.realNormalMaps,type_name+" PBR normal texture missing")
		check(actor.bones.head.position.y < 0.35,type_name+" floating head pivot")
		actor.apply_state({"animation":"walk","animationClock":0.1,"aimX":0.0,"aimY":-1.0})
		var walking_joint: Node3D = actor.bones.horse_leg0 if type_name == "commander" else actor.bones.thighL
		var earlier: float = walking_joint.rotation.x
		actor.apply_state({"animation":"walk","animationClock":0.3,"aimX":0.0,"aimY":-1.0})
		check(not is_equal_approx(earlier,walking_joint.rotation.x),type_name+" walk is not articulated")
		actor.apply_state({"animation":"attack","animationClock":0.25,"aimX":1.0,"aimY":0.0})
		check(absf(actor.bones.armR.rotation.x)>0.35,type_name+" attack arm does not swing")
		check(is_equal_approx(actor.rotation.y,-PI/2),type_name+" world direction missing")
		actor.apply_state({"animation":"death","animationClock":0.6})
		check(absf(actor.rig.rotation.x) > 1.0,type_name+" death pose missing")
		actor.apply_state({"animation":"walk","animationClock":0.2,"sailing":true})
		check(actor.boat.visible,type_name+" landing boat missing")
		check(not actor.bones.weapon.visible,type_name+" holds a combat weapon while rowing")
		if type_name=="commander": check(not actor.mount.visible,"horse is placed inside a personal rowboat")
		check(actor.motion_debug.mode == "rowing",type_name+" walks across water")
		check(actor.meshes[0].cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,type_name+" casts ground shadow on water")
		actor.apply_state({"animation":"walk","animationClock":0.2,"sailing":false})
		check(not actor.boat.visible and actor.meshes[0].cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,type_name+" landing state does not restore ground shadow")
		check(actor.bones.weapon.visible,type_name+" combat equipment does not return after landing")
		print("MODEL_QA ",JSON.stringify(info))
		actor.queue_free()
		await process_frame
	var maps = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var game = Game.new()
	root.add_child(game)
	game.load_map(maps[0])
	game.set_field_rect(Rect2(0,0,1100,620))
	check(not game.three_d_enabled,"unapproved 3D default enabled")
	var hint: Vector2 = game.placement_hints[0]
	check(hint.x>=0 and not game._eligible_zone(hint).is_empty(),"ordinary placement baseline")
	game.config.obstacles = [{"x":hint.x,"y":hint.y,"r":0.01}]
	check(not game._eligible_zone(hint).is_empty(),"unflagged decorative obstacle blocks gameplay")
	game.config.obstacles[0].blockPlacement = true
	check(game._eligible_zone(hint).is_empty(),"flagged roof obstacle accepts soldier placement")
	game._refresh_placement_hints()
	for legal_hint in game.placement_hints:
		check(legal_hint.x<0 or not game._eligible_zone(legal_hint).is_empty(),"drawn hint ignores roof obstacle")
	game.load_map(maps[0])
	var troops = Troops.new()
	root.add_child(troops)
	troops.set_field_size(Vector2(1100,620))
	troops.set_stage(maps[0])
	await process_frame
	check(troops.camera.far == 45.0,"orthographic far-plane shadow regression")
	check(troops.ground.layers == 1 and troops.fill.light_cull_mask == 2,"photo is affected by actor fill light")
	check(troops.ground_material.get_shader_parameter("photo") is Texture2D,"stage photograph missing")
	check(troops.z_index < 0,"photo viewport hides game overlay")
	for point in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1),Vector2(0.37,0.61)]:
		var projected: Vector2 = troops.camera.unproject_position(troops.normalized_to_world(point))
		check(projected.distance_to(point*troops.field_size)<0.08,"normalized camera projection mismatch")
	var sample: Dictionary = {"id":41,"type":"samurai","friendly":true,"x":0.37,"y":0.61,"animation":"idle","animationClock":0.1,"aimX":0.0,"aimY":-1.0}
	troops.sync_actor_states([sample])
	check(troops.actors.size()==1,"actor state bridge count")
	check(troops.contact_shadows.size()==1 and troops.contact_shadows["41:0"].visible,"standing actor lacks ground contact")
	check(troops.contact_shadows["41:0"].cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"ground contact casts an extra silhouette shadow")
	var actor = troops.actors["41:0"]
	var first_pose: Vector3 = actor.bones.torso.rotation
	troops.sync_actor_states([sample])
	check(actor.bones.torso.rotation==first_pose,"paused state clock changed pose")
	sample.animationClock = 0.5
	troops.sync_actor_states([sample])
	check(actor.bones.torso.rotation!=first_pose,"simulation clock does not animate pose")
	check(actor.meshes[0].layers==3,"actor-only fill does not reach meshes")
	var clone = Actor.new()
	root.add_child(clone)
	clone.configure("samurai",false,99,false)
	check(not actor.hero_detail and not clone.hero_detail,"battlefield uses portrait face LOD")
	check(clone.meshes[0].mesh == actor.meshes[0].mesh,"actor geometry is duplicated per unit")
	check(clone.materials.lacquer == actor.materials.lacquer,"PBR materials duplicated per unit")
	clone.queue_free()
	sample.motionTime=0.0
	sample.animationClock=0.0
	sample.animation="walk"
	sample.animationPhase=0.3
	sample.x=0.38
	troops.sync_actor_states([sample])
	check(bool(actor.current_state.motionReset),"reused battle ID retains previous foot anchors after clock reset")
	check(is_equal_approx(float(actor.current_state.locomotionPhase),0.3),"fresh battle deployment inherits old locomotion phase")
	sample.evolution=2
	troops.sync_actor_states([sample])
	check(troops.actors["41:0"]!=actor and troops.actors["41:0"].evolution_stage==2,"evolved model fails to replace cached earlier appearance")
	sample.sailing=true
	troops.sync_actor_states([sample])
	check(not troops.contact_shadows["41:0"].visible,"land contact appears beneath a boat")
	sample.sailing=false
	sample.animation="death"
	troops.sync_actor_states([sample])
	check(not troops.contact_shadows["41:0"].visible,"standing contact remains beneath a fallen actor")
	troops.sync_actor_states([])
	check(troops.actors.is_empty(),"obsolete 3D actor remains after logical removal")
	check(troops.contact_shadows.is_empty(),"obsolete ground contact remains after logical removal")
	print("TROOPS_3D_QA: PASS ",checks," assertions (indexed shells, face/neck, articulated poses, PBR, projection, lighting masks, bridge)")
	game.queue_free()
	troops.queue_free()
	await process_frame
	quit(0)
