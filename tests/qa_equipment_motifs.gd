extends SceneTree
## Standalone equipment validation, independent of in-progress head integration.
const Equipment = preload("res://native/sengoku_equipment_geometry.gd")
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

func run() -> void:
	for detail in [false,true]:
		for type_name in TYPES:
			var stage_hashes: Dictionary = {}
			for stage in range(3):
				var label: String = "%s/%s/%s" % [type_name,stage,detail]
				var pieces: Array = Equipment.build(type_name,stage,detail)
				check(not pieces.is_empty(),label+": pieces exist")
				var triangles: int = 0
				var head_gold: int = 0
				var head_metal: int = 0
				var signature: String = ""
				for piece in pieces:
					check(piece.bone in ["head","torso","pelvis","armL","armR","foreL","foreR","shinL","shinR","thighL","thighR","weapon","handL","handR"],label+": existing joint contract")
					var mesh: ArrayMesh = piece.mesh
					var a: Array = mesh.surface_get_arrays(0)
					var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
					var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
					var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
					var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
					var finite: bool = indices.size()>0 and indices.size()%3==0 and normals.size()==vertices.size() and uvs.size()==vertices.size()
					var used: Dictionary = {}
					for index in range(vertices.size()):
						finite = finite and vertices[index].is_finite() and normals[index].is_finite() and uvs[index].is_finite() and absf(normals[index].length()-1)<.01
					for index in indices:
						finite = finite and index>=0 and index<vertices.size()
						used[index] = true
					check(finite,label+"/"+piece.bone+": indexed finite UV and unit normals")
					check(used.size()==vertices.size(),label+"/"+piece.bone+": every vertex rendered")
					var valid_triangles: bool = true
					if finite:
						for index in range(0,indices.size(),3):
							valid_triangles = valid_triangles and (vertices[indices[index+1]]-vertices[indices[index]]).cross(vertices[indices[index+2]]-vertices[indices[index]]).length_squared()>=1e-14
					check(valid_triangles,label+"/"+piece.bone+": no collapsed triangles")
					triangles += indices.size()/3
					if piece.bone=="head" and piece.material=="gold":
						head_gold += indices.size()/3
						var restrained: bool = true
						for vertex in vertices:
							restrained = restrained and vertex.y<=.265 and absf(vertex.x)<=.091
						check(restrained,label+": compact crest, no shared giant fantasy horns")
					if piece.bone=="head" and piece.material=="metal":
						head_metal += indices.size()/3
					var cached: Array = Equipment.build(type_name,stage,detail)
					check(cached[pieces.find(piece)].mesh==mesh,label+": immutable variant cache reused")
					signature += str(piece.bone)+str(piece.material)+str(vertices.size())+str(indices.size())+str(vertices[0])
				if type_name in ["spear","samurai","naginata","commander"]:
					check(head_gold>0,label+": physical clan crest exists at every evolution")
				if type_name=="monk":
					check(head_metal==0,label+": cowl remains cloth with exposed face")
				stage_hashes[signature.sha256_text()] = true
				variants.append({"type":type_name,"stage":stage,"detail":detail,"triangles":triangles,"sourceSurfaces":pieces.size(),"headCrestTriangles":head_gold})
			check(stage_hashes.size()==3,type_name+"/"+str(detail)+": evolution geometry differs")
	var output: FileAccess = FileAccess.open("res://tests/qa_equipment_motifs.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"variants":variants},"  "))
	output.close()
	print("EQUIPMENT_MOTIFS_QA ",JSON.stringify({"checks":checks,"failures":failures,"variants":variants.size()}))
	quit(0 if failures.is_empty() else 1)
