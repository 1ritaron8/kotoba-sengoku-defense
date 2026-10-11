extends SceneTree
## Observe posed attachments and joints under authoritative combat metadata.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array[String] = []

class SlopedGround extends RefCounted:
	var grade: Vector2 = Vector2(.09,.10)
	func height_at(point: Vector3) -> float:
		return .35+point.x*grade.x+point.z*grade.y

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("TROOP MOTION POSES: "+message)

func state(animation: String, clock: float = .18) -> Dictionary:
	return {"animation":animation,"animationClock":clock,"animationPhase":0.0,"attackDuration":.5,"releaseTime":.18,"attackReleased":false,"attackCancelled":false,"aimX":0.0,"aimY":-1.0,"sailing":false,"hitClock":0.0}

func actor_for(type_name: String, detail: bool = false, hostile: bool = false) -> Node3D:
	var actor: Node3D = Actor.new()
	root.add_child(actor)
	actor.configure(type_name,hostile,9,detail)
	return actor

func palm(actor: Node3D, side: String) -> Vector3:
	return actor.bones["hand"+side].global_transform*Vector3(0,-.03,-.005)

func test_bow(detail: bool) -> void:
	var actor: Node3D = actor_for("archer",detail)
	var prefix: String = "bow/detail="+str(detail)+": "
	var data: Dictionary = state("attack",.178)
	var encoded: String = JSON.stringify(data)
	actor.apply_state(data)
	check(JSON.stringify(data)==encoded,prefix+"renderer preserves supplied combat state")
	check(actor.bones.nockedArrow.visible and actor.bones.nockedArrow.scale.x>.99,prefix+"nocked arrow is visible before committed release")
	check(float(actor.motion_debug.bowStringNock.z)>.16,prefix+"string visibly follows the draw")
	var nock: Vector3 = actor.bones.weapon.global_transform*Vector3(0,.015,.18)
	check(palm(actor,"R").distance_to(nock)<.035,prefix+"pulling hand reaches the actual nock")
	var before_position: Vector3 = actor.position
	data = state("attack",.18)
	data.attackReleased = true
	actor.apply_state(data)
	check(not actor.bones.nockedArrow.visible and actor.bones.nockedArrow.scale.x<.00002,prefix+"arrow disappears exactly with the committed shot")
	check(absf(float(actor.motion_debug.bowStringNock.z))<.0001,prefix+"string snaps at that same release")
	check(actor.position==before_position,prefix+"release introduces no root displacement")
	check((-actor.bones.weapon.global_basis.z).normalized().dot(Vector3.FORWARD)>.999,prefix+"nocked arrow faces the actual aim at release")
	if not detail:
		var index: int = actor.skinned_renderer.joint_names.find("nockedArrow")
		check(index>=0 and actor.skinned_renderer.joint_poses[index].basis.get_scale().length()<.0001,prefix+"field skin palette hides the consumed nocked arrow")
		check(actor.skinned_renderer.groups.size()==3,prefix+"bow attachments add no draw batch")
	data = state("attack",.181)
	actor.apply_state(data)
	check(actor.bones.nockedArrow.visible and not bool(actor.motion_debug.bowReleased),prefix+"elapsed release timestamp without a receipt never fires")
	check(float(actor.motion_debug.bowStringNock.z)>.16,prefix+"uncommitted string remains drawn")
	data = state("attack",.19)
	data.attackCancelled = true
	actor.apply_state(data)
	check(not bool(actor.motion_debug.bowReleased) and actor.bones.nockedArrow.visible,prefix+"cancelled preparation retains its arrow while lowering")
	check(is_zero_approx(float(actor._attack_phases(data,.19).drive)),prefix+"cancelled release does not play a strike drive")
	data = state("attack",.34)
	data.erase("attackReleased")
	data.erase("releaseTime")
	actor.apply_state(data)
	check(bool(actor.motion_debug.bowReleased),prefix+"legacy preview retains its existing release frame")
	data = state("idle")
	data.sailing = true
	actor.apply_state(data)
	check(not actor.bones.bowStringLower.visible and actor.bones.bowStringLower.scale.length()<.0001,prefix+"sailing hides string in both geometry paths")
	actor.apply_state(state("death"))
	check(not actor.bones.nockedArrow.visible and actor.bones.bowStringLower.visible,prefix+"casualty retains its bow without a phantom nocked arrow")
	actor.free()

func test_matchlock() -> void:
	var actor: Node3D = actor_for("gunner")
	var start: Vector3 = Vector3.ZERO
	var furthest: float = 0.0
	var steepest: float = 0.0
	var original_position: Vector3 = actor.position
	var original_basis: Basis = Basis.IDENTITY
	for progress in [0.0,.16,.35,.60,.80,1.0]:
		var data: Dictionary = state("idle")
		data.motionPhase = "reload"
		data.reloadProgress = progress
		var encoded: String = JSON.stringify(data)
		actor.apply_state(data)
		check(JSON.stringify(data)==encoded,"matchlock: reload never changes gameplay clocks")
		check(actor.position==original_position,"matchlock: reload introduces no root displacement")
		if is_zero_approx(progress):
			start = palm(actor,"L")
			original_basis = actor.bones.weapon.global_basis
		furthest = maxf(furthest,palm(actor,"L").distance_to(start))
		steepest = maxf(steepest,actor.bones.weapon.global_basis.y.angle_to(original_basis.y))
		if is_equal_approx(progress,1.0):
			check(palm(actor,"L").distance_to(start)<.001,"matchlock: completed cooldown restores the same support grip")
	check(furthest>.08 and steepest>.35,"matchlock: charging stroke and weapon lowering are visible between shots")
	var data: Dictionary = state("idle")
	data.reloadProgress = .5
	actor.apply_state(data)
	check(not bool(actor.motion_debug.reloading),"matchlock: progress alone cannot invent a reload")
	data = state("attack",.23)
	actor.apply_state(data)
	check(is_zero_approx(float(actor.motion_debug.matchlockRecoil)),"matchlock: elapsed timestamp without commitment has no firing recoil")
	data.attackReleased = true
	actor.apply_state(data)
	check(float(actor.motion_debug.matchlockRecoil)>.7,"matchlock: committed recoil follows the actual release time")
	data.attackReleased = false
	data.attackCancelled = true
	actor.apply_state(data)
	check(is_zero_approx(float(actor.motion_debug.matchlockRecoil)),"matchlock: cancelled attack has no firing recoil")
	actor.free()

func test_contacts_and_hit() -> void:
	for type_name in TYPES:
		var actor: Node3D = actor_for(type_name)
		for animation in ["idle","walk","attack"]:
			var data: Dictionary = state(animation,.18)
			data.attackReleased = animation=="attack"
			actor.apply_state(data)
			var torso: Basis = actor.bones.torso.global_basis
			var left: Vector3 = actor.bones.footL.global_position
			var right: Vector3 = actor.bones.footR.global_position
			var original_position: Vector3 = actor.position
			data.hitClock = .06
			actor.apply_state(data)
			check(torso.z.angle_to(actor.bones.torso.global_basis.z)>.05 or torso.x.angle_to(actor.bones.torso.global_basis.x)>.05,type_name+"/"+animation+": hit flinch remains visible after full-body pose")
			check(actor.position==original_position,type_name+"/"+animation+": hit adds no root motion")
			check(left.distance_to(actor.bones.footL.global_position)<.0001 and right.distance_to(actor.bones.footR.global_position)<.0001,type_name+"/"+animation+": hit preserves planted feet or current gait")
			check(str(actor.current_state.animation)==animation,type_name+"/"+animation+": hit does not stop or replace the action")
			var frozen: Transform3D = actor.bones.torso.global_transform
			actor.apply_state(data)
			check(frozen.is_equal_approx(actor.bones.torso.global_transform),type_name+"/"+animation+": repeated hit phase does not accumulate recoil")
			for key in actor.bones:
				check(actor.bones[key].global_transform.is_finite(),type_name+"/"+animation+": finite posed joint "+str(key))
		if type_name != "monk":
			for release in [.12,.18,.4]:
				var data: Dictionary = state("attack",release)
				data.releaseTime = release
				data.attackReleased = true
				actor.apply_state(data)
				check(is_equal_approx(float(actor._attack_phases(data,release).drive),1.0),type_name+": strike peaks at supplied gameplay release "+str(release))
		actor.free()

func test_heal_receipt() -> void:
	var actor: Node3D = actor_for("monk")
	var data: Dictionary = state("heal",0)
	data.healDuration = .6
	data.healAmount = 12.0
	data.healCommittedAt = 8.2
	data.healingTargetId = 71
	actor.apply_state(data)
	check(bool(actor.motion_debug.healCommitted) and int(actor.motion_debug.healTargetId)==71 and is_equal_approx(float(actor.motion_debug.healCommittedAt),8.2),"monk: committed recovery is reported at the actual start-time receipt")
	data = state("idle")
	actor.apply_state(data)
	check(not bool(actor.motion_debug.healCommitted) and is_zero_approx(float(actor.motion_debug.supportGesture)),"monk: guard without a receipt invents neither healing nor casting")
	actor.free()

func ground_clearance(actor: Node3D, sampler: Callable, key: String) -> float:
	var clearance: float = INF
	for source in actor.meshes:
		if source.get_parent()!=actor.bones[key]:
			continue
		for surface in range(source.mesh.get_surface_count()):
			for vertex in source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if key.begins_with("horse") and vertex.y>-.352:
					continue
				var point: Vector3 = source.global_transform*vertex
				clearance = minf(clearance,point.y-float(sampler.call(point)))
	return clearance

func test_sloped_contacts() -> void:
	var ground: SlopedGround = SlopedGround.new()
	var sampler: Callable = Callable(ground,"height_at")
	for type_name in TYPES+["enemy_light","enemy_heavy"]:
		for hostile in [false,true]:
			var actor: Node3D = actor_for(type_name,false,hostile)
			var keys: Array = ["horse_calf0","horse_calf1","horse_calf2","horse_calf3"] if type_name=="commander" else ["footL","footR"]
			for size in [1.0,.38]:
				actor.scale = Vector3.ONE*size
				for animation in ["idle","attack"]:
					var data: Dictionary = state(animation,.19)
					data.attackReleased = animation=="attack"
					data.groundMotion = true
					data.motionReset = true
					data.groundHeightSampler = sampler
					actor.position = Vector3(.2,0,-.1)
					actor.position.y = ground.height_at(actor.position)
					var path_position: Vector3 = actor.position
					actor.apply_state(data)
					check(actor.position==path_position,type_name+"/"+str(hostile)+"/"+animation+": slope does not move the route root")
					for key in keys:
						var clearance: float = ground_clearance(actor,sampler,key)
						check(clearance>=-.004*size and clearance<.013*size,type_name+"/"+str(hostile)+"/"+animation+"/"+str(size)+"/"+str(key)+": real sole or hoof contacts the sloped surface; gap="+str(clearance))
			actor.free()
	for type_name in ["samurai","commander","enemy_heavy"]:
		var actor: Node3D = actor_for(type_name,false,type_name.begins_with("enemy"))
		var lifted: bool = false
		for frame in range(55):
			var clock: float = frame*.03
			var animation: String = "walk" if frame<35 else "attack" if frame<48 else "idle"
			var data: Dictionary = state(animation,clock if animation=="walk" else (frame-35)*.03 if animation=="attack" else 0.0)
			data.attackReleased = animation=="attack" and float(data.animationClock)>=.18
			data.motionTime = clock
			data.groundMotion = true
			data.motionReset = frame==0
			data.groundHeightSampler = sampler
			data.locomotionPhase = clock*.90
			data.locomotionCadence = .90
			data.runBlend = .35
			data.travelVelocity = Vector3(.12,0,-.15)
			data.visualYaw = -.35+minf(clock,1.02)*.20
			var route_clock: float = minf(clock,1.02)
			actor.position = Vector3(.2+route_clock*.12,0,-.1-route_clock*.15)
			actor.position.y = ground.height_at(actor.position)
			var path_position: Vector3 = actor.position
			actor.apply_state(data)
			check(actor.position==path_position,type_name+": live slope/turn/stop retains the measured route root")
			var keys: Array = ["horse_calf0","horse_calf1","horse_calf2","horse_calf3"] if type_name=="commander" else ["footL","footR"]
			for key in keys:
				var clearance: float = ground_clearance(actor,sampler,key)
				check(clearance>=-.008,type_name+"/"+animation+"/"+str(frame)+"/"+str(key)+": moving/stopped real contact stays above the slope; gap="+str(clearance))
				lifted = lifted or clearance>.030
				if animation=="idle":
					check(clearance<.018,type_name+"/"+str(key)+": stopped contact settles on terrain after gait; gap="+str(clearance))
			if frame==54:
				var frozen: Dictionary = {}
				for key in keys:
					frozen[key] = actor.bones[key].global_transform
				actor.apply_state(data)
				for key in keys:
					check((frozen[key] as Transform3D).is_equal_approx(actor.bones[key].global_transform),type_name+"/"+str(key)+": stationary slope pose is deterministic")
		check(lifted,type_name+": terrain correction preserves a real swing lift")
		actor.free()

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.contains("/tests/profiles/troop-motion-poses/"):
		push_error("Troop motion pose QA refuses a player profile")
		quit(2)
		return
	for detail in [false,true]:
		test_bow(detail)
	test_matchlock()
	test_contacts_and_hit()
	test_heal_receipt()
	test_sloped_contacts()
	var report: Dictionary = {"checks":checks,"failures":failures,"scope":"Actual bow attachment visibility in rigid and skin palettes, string/hand contact, committed release/cancel timing, original-cooldown reload, upper-body hit without gait/root motion, eight existing attack phases, heal receipts, real sole/hoof vertices on stationary, moving, turning and stopped slopes at two scales for both teams. Authored-map live-wave visual QA remains separate."}
	var output: FileAccess = FileAccess.open("user://qa_troop_motion_poses.json",FileAccess.WRITE)
	check(output!=null,"profile-only result file opens")
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	print("TROOP_MOTION_POSES_QA ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
