extends SceneTree
## Geometry validity and retained animation contracts, without a GPU renderer.
const Body = preload("res://native/human_body_geometry.gd")
const Armour = preload("res://native/sengoku_armor_geometry.gd")
const Equipment = preload("res://native/sengoku_equipment_geometry.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array = []
var variants: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func validate(label: String, pieces: Array) -> void:
	check(not pieces.is_empty(),label+": model pieces exist")
	var triangles: int = 0
	var joints: Dictionary = {}
	for piece in pieces:
		joints[str(piece.bone)] = true
		var mesh: ArrayMesh = piece.mesh
		for surface in range(mesh.get_surface_count()):
			var a: Array = mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var finite: bool = ix.size()>0 and ix.size()%3==0 and n.size()==v.size() and uv.size()==v.size()
			var used: Dictionary = {}
			for i in range(v.size()):
				finite = finite and v[i].is_finite() and n[i].is_finite() and uv[i].is_finite() and absf(n[i].length()-1)<.01
			for i in ix:
				finite = finite and i>=0 and i<v.size()
				used[i] = true
			check(finite,label+"/"+piece.bone+"/"+piece.material+": indexed finite vertices, UV and unit normals")
			check(used.size()==v.size(),label+"/"+piece.bone+": no unrendered vertices")
			var nondegenerate: bool = true
			if finite:
				for i in range(0,ix.size(),3):
					if (v[ix[i+1]]-v[ix[i]]).cross(v[ix[i+2]]-v[ix[i]]).length_squared()<1e-14:
						nondegenerate = false
			check(nondegenerate,label+"/"+piece.bone+": no collapsed triangles")
			triangles += ix.size()/3
	variants.append({"label":label,"triangles":triangles,"sourceSurfaces":pieces.size(),"batchedJoints":joints.size()})

func run() -> void:
	for detail in [false,true]:
		for light in [false,true]:
			validate("armour/"+str(light)+"/"+str(detail),Armour.build(light,detail))
		for type_name in TYPES:
			validate("body/"+type_name+"/"+str(detail),Body.build(type_name,detail))
			for stage in range(3):
				validate("equipment/"+type_name+"/"+str(stage)+"/"+str(detail),Equipment.build(type_name,stage,detail))
				var actor = Actor.new()
				root.add_child(actor)
				actor.configure(type_name,false,27,detail,stage)
				var info: Dictionary = actor.diagnostics()
				check(int(info.unreferencedVertices)==0,"actor/"+type_name+": batching renders every vertex")
				check(int(info.meshBatches)==(31 if type_name=="commander" else 19),"actor/"+type_name+": refinement preserves draw-batch count")
				check(actor.bones.foreL.position.is_equal_approx(Vector3(0,-.29*.94,0)) and actor.bones.handL.position.is_equal_approx(Vector3(0,-.265*.94,0)),"actor/"+type_name+": arm IK segment lengths match approved94% human skeleton")
				check(actor.bones.shinL.position.is_equal_approx(Vector3(0,-.42*.94,0)) and actor.bones.footL.position.is_equal_approx(Vector3(0,-.425*.94,0)),"actor/"+type_name+": leg IK segment lengths match approved94% human skeleton")
				actor.queue_free()
				await process_frame
	var file: FileAccess = FileAccess.open("res://tests/qa_body_refinement.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"variants":variants},"  "))
	file.close()
	print("BODY_REFINEMENT_QA ",JSON.stringify({"checks":checks,"failures":failures,"variants":variants.size()}))
	quit(0 if failures.is_empty() else 1)
