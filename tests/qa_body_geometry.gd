extends SceneTree
const Body = preload("res://native/human_body_geometry.gd")
const Actor = preload("res://native/sengoku_actor_3d.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
var checks: int = 0
var failures: Array = []
var variants: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
func vertices_for(pieces: Array, bone: String) -> Array:
	var result: Array = []
	for piece in pieces:
		if str(piece.bone)!=bone: continue
		for surface in range(piece.mesh.get_surface_count()):
			result.append_array(piece.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return result
func bounds(vertices: Array) -> AABB:
	var box = AABB(vertices[0],Vector3.ZERO)
	for vertex in vertices: box=box.expand(vertex)
	return box
func slice_width(vertices: Array, y: float, tolerance: float) -> float:
	var low: float=INF
	var high: float=-INF
	for v in vertices:
		if absf(v.y-y)<tolerance:
			low=minf(low,v.x)
			high=maxf(high,v.x)
	return high-low
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for type_name in TYPES:
		for detail in [false,true]:
			var pieces: Array=Body.build(type_name,detail)
			check(not pieces.is_empty(),type_name+": anatomy exists")
			check(pieces[0].mesh==Body.build(type_name,detail)[0].mesh,type_name+": geometry cache shares meshes")
			var triangles: int=0
			for piece in pieces:
				for surface in range(piece.mesh.get_surface_count()):
					var arrays: Array=piece.mesh.surface_get_arrays(surface)
					var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
					var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
					var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
					var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
					var valid: bool=indices.size()>0 and indices.size()%3==0 and normals.size()==points.size() and uvs.size()==points.size()
					var used: Dictionary={}
					for i in indices:
						valid=valid and i>=0 and i<points.size()
						used[i]=true
					for index in range(points.size()):
						valid=valid and points[index].is_finite() and normals[index].is_finite() and absf(normals[index].length()-1)<.01 and uvs[index].is_finite()
					check(valid,type_name+"/"+str(detail)+"/"+piece.bone+"/"+piece.material+": indexed finite geometry with valid normals/UV")
					check(used.size()==points.size(),type_name+"/"+piece.bone+": every vertex is actually rendered")
					triangles+=indices.size()/3
			var hand: AABB=bounds(vertices_for(pieces,"handL"))
			check(hand.size.y>.10 and hand.size.x>.075 and hand.size.z<hand.size.x,type_name+": flatter anatomical palm and curled fingers replace sphere hands")
			var shoe: AABB=bounds(vertices_for(pieces,"footL"))
			check(shoe.size.z>.25 and shoe.size.x<.12 and shoe.size.y<.09,type_name+": actual shoe has a long last and thin sole")
			var fore: Array=vertices_for(pieces,"foreL")
			check(slice_width(fore,-.084,.003)>slice_width(fore,-.246,.003)*1.5,type_name+": forearm tapers to a wrist")
			var calf: Array=vertices_for(pieces,"shinL")
			check(slice_width(calf,-.114,.003)>slice_width(calf,-.422,.003)*1.8,type_name+": calf volume narrows into ankle")
			for pitch in [-.30,-.20,-.10,0.0,.10,.20,.30]:
				var minimum: float=INF
				var rotation: Basis=Basis.from_euler(Vector3(pitch,0,0))
				for vertex in vertices_for(pieces,"footL"):
					minimum=minf(minimum,(rotation*vertex).y+Body.ankle_height(pitch))
				check(minimum>=.0029 and minimum<.0045,type_name+": heel/toe support keeps the rendered sole on ground at "+str(pitch))
			variants.append({"type":type_name,"detail":detail,"triangles":triangles})
	for detail in [false,true]:
		var horse: Array=Body.build_horse(detail)
		var triangles: int=0
		for piece in horse:
			for surface in range(piece.mesh.get_surface_count()):
				var arrays: Array=piece.mesh.surface_get_arrays(surface)
				var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
				var valid: bool=indices.size()>0 and indices.size()%3==0 and normals.size()==points.size() and uvs.size()==points.size()
				var used: Dictionary={}
				for i in indices:
					valid=valid and i>=0 and i<points.size()
					used[i]=true
				for index in range(points.size()):
					valid=valid and points[index].is_finite() and normals[index].is_finite() and absf(normals[index].length()-1)<.01 and uvs[index].is_finite()
				check(valid,"horse/"+str(detail)+"/"+piece.bone+": valid indexed anatomical geometry")
				check(used.size()==points.size(),"horse/"+piece.bone+": no orphan vertices")
				triangles+=indices.size()/3
		var barrel: AABB=bounds(vertices_for(horse,"mount"))
		check(barrel.size.z>1.0 and barrel.size.x<.60 and barrel.size.y>.55,"Horse has a continuous long barrel with narrower shoulder and rump")
		for leg in range(4):
			var hoof: AABB=bounds(vertices_for(horse,"horse_calf%d"%leg))
			check(absf(hoof.position.y+.416)<.0001,"Horse hoof sole matches the contact solver")
		variants.append({"type":"horse","detail":detail,"triangles":triangles})
	var actor=Actor.new()
	root.add_child(actor)
	actor.configure("samurai",false,1,false)
	check(actor.bones.head.scale.is_equal_approx(Vector3(.90,.94,.90)),"Head and helmet share the adult proportion correction")
	check(is_equal_approx(absf(actor.bones.armL.position.x),.220),"Shoulder width fits the slimmer adult chest")
	actor.queue_free()
	await process_frame
	var report={"checks":checks,"failures":failures,"variants":variants}
	var file=FileAccess.open("res://tests/qa_body_geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("BODY_GEOMETRY_QA ",JSON.stringify({"checks":checks,"failures":failures,"variants":variants.size()}))
	quit(0 if failures.is_empty() else 1)
