extends SceneTree
## Measures authored human surfaces and unchanged rig/transport contracts.
const Actor = preload("res://native/sengoku_actor_3d.gd")
const Body = preload("res://native/human_body_geometry.gd")
const Armour = preload("res://native/sengoku_armor_geometry.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja","enemy_light","enemy_heavy"]
var failures: Array = []
var checks: int = 0
var variants: Array = []
var before: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		push_error(note)

func bone_bounds(actor: Node3D, bone_name: String) -> AABB:
	var box: AABB
	var started: bool = false
	for instance in actor.meshes:
		if instance.get_parent().name!=bone_name: continue
		for surface in range(instance.mesh.get_surface_count()):
			for vertex in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if not started:
					box=AABB(vertex,Vector3.ZERO)
					started=true
				else: box=box.expand(vertex)
	return box

func bone_hash(actor: Node3D, bone_name: String) -> String:
	var context=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for instance in actor.meshes:
		if instance.get_parent().name!=bone_name: continue
		for surface in range(instance.mesh.get_surface_count()):
			context.update(var_to_bytes(instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]))
	return context.finish().hex_encode()

func run() -> void:
	var profile: String=ProjectSettings.globalize_path("user://").replace("\\","/").to_lower()
	if not profile.begins_with("c:/jp_df/tests/profiles/actor-proportions/"):
		push_error("Proportion QA refuses player profile")
		quit(2)
		return
	before="--before" in OS.get_cmdline_user_args()
	var old: Dictionary={}
	if not before:
		old=JSON.parse_string(FileAccess.get_file_as_string("C:/JP_DF/tests/qa_actor_proportions_before.json"))
	for type_name in TYPES:
		for evolution in range(1 if type_name.begins_with("enemy") else 3):
			var actor=Actor.new()
			root.add_child(actor)
			actor.configure(type_name,type_name.begins_with("enemy"),1,false,evolution)
			var arm: AABB=bone_bounds(actor,"armL")
			var shin: AABB=bone_bounds(actor,"shinL")
			var thigh: AABB=bone_bounds(actor,"thighL")
			var waist: AABB=bone_bounds(actor,"pelvis")
			var observation: Dictionary={"type":type_name,"evolution":evolution,"shoulderSpan":absf(actor.bones.armL.position.x-actor.bones.armR.position.x),"chestWidth":Armour._profile(.11).x*2,"chestDepth":Armour._profile(.11).y*2,"armWidth":arm.size.x,"armDepth":arm.size.z,"thighWidth":thigh.size.x,"calfWidth":shin.size.x,"waistWidth":waist.size.x,"shoulderEnvelope":absf(actor.bones.armL.position.x)*2+maxf(absf(arm.position.x),absf(arm.end.x))*2,"transportHashes":{}}
			for bone_name in ["head","handL","handR","footL","footR","weapon","boat","oarL","oarR","mount","horse_neck","horse_head","horse_leg0","horse_calf0"]:
				observation.transportHashes[bone_name]=bone_hash(actor,bone_name)
			check(actor.scale.is_equal_approx(Vector3.ONE),"No global axis squash "+type_name)
			check(is_equal_approx(actor.bones.foreL.position.y,-.29*.94) and is_equal_approx(actor.bones.handL.position.y,-.265*.94),"Approved94% human arm lengths "+type_name)
			check(is_equal_approx(actor.bones.shinL.position.y,-.42*.94) and is_equal_approx(actor.bones.footL.position.y,-.425*.94),"Approved94% human leg lengths "+type_name)
			check(actor.bones.head.scale.is_equal_approx(Vector3(.90,.94,.90)),"Face/head proportions retained "+type_name)
			if not before:
				var original: Dictionary=old.variants[variants.size()]
				check(observation.shoulderSpan<original.shoulderSpan*.90,"Shoulder span measurably narrower "+type_name)
				check(observation.chestWidth<original.chestWidth*.88,"Chest width measurably narrower "+type_name)
				check(observation.chestDepth<original.chestDepth*.90,"Chest depth measurably shallower "+type_name)
				check(observation.shoulderEnvelope<original.shoulderEnvelope*.89,"Armour silhouette narrows "+type_name)
				check(observation.thighWidth<original.thighWidth*.94,"Trousers volume narrows "+type_name)
				for bone_name in observation.transportHashes:
					check(observation.transportHashes[bone_name]==original.transportHashes[bone_name],"Face/hands/soles/weapons/boat/horse exact geometry retained "+type_name+"/"+bone_name)
			variants.append(observation)
			actor.queue_free()
			await process_frame
	var file=FileAccess.open("C:/JP_DF/tests/qa_actor_proportions_"+("before" if before else "after")+".json",FileAccess.WRITE)
	check(file!=null,"Measured QA report opens")
	if file:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"variants":variants},"  "))
		file.close()
	print("ACTOR_PROPORTIONS ",JSON.stringify({"checks":checks,"failures":failures,"before":before,"variants":variants.size()}))
	quit(0 if failures.is_empty() else 1)
