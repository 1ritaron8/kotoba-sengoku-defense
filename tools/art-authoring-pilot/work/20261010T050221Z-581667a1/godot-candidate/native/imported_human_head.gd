extends RefCounted
## Imported anatomy keeps its own StandardMaterial3D, UVs and source textures.
## It must not pass through ActorMaterials' procedural colour-family shader.

const CORE: String = "res://assets/models3d/makehuman/makehuman/data/"
const SOURCE_ID: String = "MakeHuman-hm08-Asian-male-a8bc2d54ff0ac92e78ff71431b1023eda42bf482"
const SKINS: String = "res://assets/models3d/makehuman/system_assets/skins/"
# Research-only: external anatomy is inactive unless explicitly configured.
# The current product uses the game's authored Sengoku actors.
static var source_path: String = ""
static var source_options: Dictionary = {}
static var _cache: Dictionary = {}
static var _source_data: Dictionary = {}
static var _diagnostics: Dictionary = {"ready":false,"sourcePath":""}

static func configure_source(path: String, options: Dictionary = {}) -> void:
	if source_path==path and source_options==options:
		return
	source_path = path
	source_options = options.duplicate(true)
	_cache.clear()
	_source_data.clear()
	_diagnostics = {"ready":false,"sourcePath":source_path}

static func diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)

static func build(unit_type: String = "archer", high_detail: bool = true) -> Array[Dictionary]:
	# These are authored game-age variations of an explicitly named Asian male
	# morph. They do not purport to be scans or portraits of historical people.
	var ages: Dictionary = {"archer":0.0,"spear":0.08,"samurai":0.30,"commander":0.48,"gunner":0.22,"naginata":0.18,"monk":0.38,"ninja":0.10,"enemy_light":0.18,"enemy_heavy":0.40}
	var age_mix: float = float(source_options.get("oldWeight",ages.get(unit_type,0.0)))
	age_mix = clampf(age_mix,0.0,1.0)
	var key: String = unit_type+":"+str(high_detail)+":"+str(age_mix)
	if _cache.has(key):
		_diagnostics = _cache[key].info.duplicate(true)
		return _cache[key].pieces
	_diagnostics = {"ready":false,"sourceId":SOURCE_ID,"sourcePath":source_path,"unitType":unit_type,"highDetail":high_detail,"errors":[]}
	if not FileAccess.file_exists(source_path):
		_diagnostics.errors.append("MakeHuman base OBJ is unavailable")
		return []
	if _source_data.is_empty():
		_source_data = _read_obj(source_path)
	if _source_data.is_empty():
		_diagnostics.errors.append("Could not parse source OBJ")
		return []
	var positions: PackedVector3Array = _source_data.positions.duplicate()
	var target_info: Array = []
	for target in [{"name":"asian-male-young","weight":1.0-age_mix},{"name":"asian-male-old","weight":age_mix},{"name":"universal-male-young-averagemuscle-averageweight","weight":1.0}]:
		var path: String = CORE+"targets/macrodetails/"+str(target.name)+".target"
		var modified: int = _apply_target(positions,path,float(target.weight))
		if modified<0:
			_diagnostics.errors.append("Invalid or missing target "+path)
			return []
		target_info.append({"path":path,"weight":target.weight,"modifiedVertices":modified})
	var neck: Vector3 = _group_center(_source_data,positions,"joint-neck")
	var head_joint: Vector3 = _group_center(_source_data,positions,"joint-head")
	var faces: Array[Dictionary] = []
	var crown: float = -INF
	var bounds: AABB = AABB()
	var found_bound: bool = false
	for face in _source_data.faces:
		if face.group!="body":
			continue
		var include: bool = true
		for vertex in face.v:
			if positions[vertex].y < neck.y-0.04:
				include = false
		if not include:
			continue
		faces.append(face)
		for vertex in face.v:
			var p: Vector3 = positions[vertex]
			crown = maxf(crown,p.y)
			if not found_bound:
				bounds = AABB(p,Vector3.ZERO)
				found_bound = true
			else:
				bounds = bounds.expand(p)
	if faces.is_empty():
		_diagnostics.errors.append("Head crop contains no body faces")
		return []
	# One uniform physical scale preserves the original facial aspect ratio.
	# Crown anchors to the existing equipment envelope. Neck is retained below
	# the chin rather than closing the crop with an artificial sphere or cap.
	var scale_value: float = 0.11
	var origin: Vector3 = Vector3(0,crown-0.16/scale_value,head_joint.z)
	var transformed: PackedVector3Array = PackedVector3Array()
	for p in positions:
		transformed.append(_head_point(p,origin,scale_value))
	var skin_geometry: Dictionary = {"positions":transformed,"faces":faces}
	if high_detail:
		skin_geometry = _subdivide(skin_geometry)
	var skin_mesh: ArrayMesh = _surface_mesh(skin_geometry)
	var eyes_name: String = "high-poly" if high_detail else "low-poly"
	var eye_obj: Dictionary = _read_obj(CORE+"eyes/"+eyes_name+"/"+eyes_name+".obj")
	var fitted: PackedVector3Array = _fit_proxy(CORE+"eyes/"+eyes_name+"/"+eyes_name+".mhclo",positions)
	if eye_obj.is_empty() or fitted.size()!=eye_obj.positions.size():
		_diagnostics.errors.append("Eye proxy vertex mapping is invalid")
		return []
	var eyes_local: PackedVector3Array = PackedVector3Array()
	for p in fitted:
		eyes_local.append(_head_point(p,origin,scale_value))
	var eye_mesh: ArrayMesh = _surface_mesh({"positions":eyes_local,"faces":eye_obj.faces})
	var skin_path: String = SKINS+"young_asian_male/young_lightskinned_male_diffuse3.png"
	if age_mix>=0.25:
		skin_path = SKINS+"middleage_asian_male/middleage_lightskinned_male_diffuse2.png"
	var eye_path: String = CORE+"eyes/materials/brown_eye.png"
	var skin_material: StandardMaterial3D = _textured_material(skin_path,false)
	var eye_material: StandardMaterial3D = _textured_material(eye_path,true)
	if skin_material==null or eye_material==null:
		_diagnostics.errors.append("Skin/eye textures have not been imported")
		return []
	var pieces: Array[Dictionary] = [
		{"bone":"head","part":"skin","mesh":skin_mesh,"material_resource":skin_material,"imported":true,"source_path":source_path},
		{"bone":"head","part":"eyes","mesh":eye_mesh,"material_resource":eye_material,"imported":true,"source_path":CORE+"eyes/"+eyes_name+"/"+eyes_name+".obj"}
	]
	var landmark: Dictionary = {}
	for name in ["joint-head","joint-head-2","joint-neck","joint-jaw","joint-l-eye","joint-r-eye","joint-mouth"]:
		var value: Vector3 = _head_point(_group_center(_source_data,positions,name),origin,scale_value)
		landmark[name] = [value.x,value.y,value.z]
	var nose: Vector3 = Vector3(0,0,INF)
	var left_ear: Vector3 = Vector3(INF,0,0)
	var right_ear: Vector3 = Vector3(-INF,0,0)
	for face in faces:
		for index in face.v:
			var p: Vector3 = transformed[index]
			if p.z<nose.z:
				nose = p
			if p.x<left_ear.x:
				left_ear = p
			if p.x>right_ear.x:
				right_ear = p
	landmark["noseTip"] = [nose.x,nose.y,nose.z]
	landmark["earLeftExtreme"] = [left_ear.x,left_ear.y,left_ear.z]
	landmark["earRightExtreme"] = [right_ear.x,right_ear.y,right_ear.z]
	_diagnostics.merge({"ready":true,"sourceVertexCount":positions.size(),"sourceBodyFaceCount":faces.size(),"oldWeight":age_mix,"morphTargets":target_info,"landmarks":landmark,"uniformScale":scale_value,"faceDirection":"-Z","neckCoverage":true,"albedoPaths":[skin_path,eye_path],"triangles":{"skin":skin_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3,"eyes":eye_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3},"bounds":{"position":str(skin_mesh.get_aabb().position),"size":str(skin_mesh.get_aabb().size)},"uvPreserved":true,"materialPipeline":"StandardMaterial3D-original-UV"},true)
	_cache[key] = {"pieces":pieces,"info":_diagnostics.duplicate(true)}
	return pieces

static func _head_point(p: Vector3, origin: Vector3, scale_value: float) -> Vector3:
	var value: Vector3 = (p-origin)*scale_value
	return Vector3(-value.x,value.y,-value.z)

static func _read_obj(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var positions: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var faces: Array[Dictionary] = []
	var group: String = ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = str(raw).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts: PackedStringArray = line.replace("\t"," ").split(" ",false)
		if parts[0]=="v" and parts.size()>=4:
			positions.append(Vector3(float(parts[1]),float(parts[2]),float(parts[3])))
		elif parts[0]=="vt" and parts.size()>=3:
			# OBJ V originates at the bottom; Godot textures originate at the top.
			uv.append(Vector2(float(parts[1]),1.0-float(parts[2])))
		elif parts[0]=="g":
			group = parts[1] if parts.size()>1 else ""
		elif parts[0]=="f" and parts.size()>=4:
			var corners: PackedInt32Array = PackedInt32Array()
			var face_uv: Array[Vector2] = []
			for corner in parts.slice(1):
				var values: PackedStringArray = corner.split("/")
				var index: int = int(values[0])-1
				if index<0 or index>=positions.size():
					return {}
				corners.append(index)
				var tex_index: int = int(values[1])-1 if values.size()>1 and not values[1].is_empty() else -1
				face_uv.append(uv[tex_index] if tex_index>=0 and tex_index<uv.size() else Vector2.ZERO)
			faces.append({"v":corners,"uv":face_uv,"group":group})
	return {"positions":positions,"uv":uv,"faces":faces}

static func _apply_target(positions: PackedVector3Array, path: String, weight: float) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var count: int = 0
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = str(raw).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts: PackedStringArray = line.split(" ",false)
		if parts.size()!=4:
			return -1
		var index: int = int(parts[0])
		if index<0 or index>=positions.size():
			return -1
		positions[index] += Vector3(float(parts[1]),float(parts[2]),float(parts[3]))*weight
		count += 1
	return count

static func _group_center(data: Dictionary, positions: PackedVector3Array, group: String) -> Vector3:
	var used: Dictionary = {}
	var result: Vector3 = Vector3.ZERO
	for face in data.faces:
		if face.group==group:
			for index in face.v:
				if not used.has(index):
					used[index] = true
					result += positions[index]
	return result/float(maxi(1,used.size()))

static func _fit_proxy(path: String, source: PackedVector3Array) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var scales: Vector3 = Vector3.ONE
	var reading: bool = false
	if not FileAccess.file_exists(path):
		return result
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = str(raw).strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts: PackedStringArray = line.split(" ",false)
		if parts[0] in ["x_scale","y_scale","z_scale"]:
			var axis: int = {"x_scale":0,"y_scale":1,"z_scale":2}[parts[0]]
			scales[axis] = absf(source[int(parts[1])][axis]-source[int(parts[2])][axis])/float(parts[3])
		elif parts[0]=="verts":
			reading = true
		elif reading:
			if parts.size()==1 and parts[0].is_valid_int():
				result.append(source[int(parts[0])])
			elif parts.size()==9:
				var p: Vector3 = source[int(parts[0])]*float(parts[3])+source[int(parts[1])]*float(parts[4])+source[int(parts[2])]*float(parts[5])
				p += Vector3(float(parts[6]),float(parts[7]),float(parts[8]))*scales
				result.append(p)
			else:
				break
	return result

static func _edge_key(a: int,b: int) -> String:
	return str(mini(a,b))+":"+str(maxi(a,b))

static func _subdivide(data: Dictionary) -> Dictionary:
	# Catmull-Clark is evaluated on unsplit source topology. UV seams only split
	# the final draw vertices and therefore cannot create cracks or hard normals.
	var original: PackedVector3Array = data.positions
	var points: PackedVector3Array = original.duplicate()
	var edges: Dictionary = {}
	var adjacent: Dictionary = {}
	var centers: Array[int] = []
	for face_index in range(data.faces.size()):
		var face: Dictionary = data.faces[face_index]
		var center: Vector3 = Vector3.ZERO
		for index in face.v:
			center += original[index]
			if not adjacent.has(index):
				adjacent[index] = {"faces":[],"edges":[]}
			adjacent[index].faces.append(face_index)
		centers.append(points.size())
		points.append(center/float(face.v.size()))
		for k in range(face.v.size()):
			var a: int = face.v[k]
			var b: int = face.v[(k+1)%face.v.size()]
			var key: String = _edge_key(a,b)
			if not edges.has(key):
				edges[key] = {"a":a,"b":b,"faces":[],"point":-1}
				edges[key].faces.append(face_index)
				adjacent[a].edges.append(key)
				adjacent[b].edges.append(key)
			else:
				edges[key].faces.append(face_index)
	for key in edges:
		var edge: Dictionary = edges[key]
		var point: Vector3 = original[edge.a]+original[edge.b]
		if edge.faces.size()==2:
			point = (point+points[centers[edge.faces[0]]]+points[centers[edge.faces[1]]])*0.25
		else:
			point *= 0.5
		edge.point = points.size()
		points.append(point)
	for index in adjacent:
		var ring: Dictionary = adjacent[index]
		var boundary: Array[int] = []
		var midpoint: Vector3 = Vector3.ZERO
		var center: Vector3 = Vector3.ZERO
		for key in ring.edges:
			var edge: Dictionary = edges[key]
			midpoint += (original[edge.a]+original[edge.b])*0.5
			if edge.faces.size()==1:
				boundary.append(edge.b if edge.a==index else edge.a)
		if boundary.size()==2:
			points[index] = original[index]*0.75+(original[boundary[0]]+original[boundary[1]])*0.125
		elif boundary.is_empty():
			for face_index in ring.faces:
				center += points[centers[face_index]]
			var n: float = float(ring.faces.size())
			points[index] = (center/n+2.0*midpoint/float(ring.edges.size())+(n-3.0)*original[index])/n
	var faces: Array[Dictionary] = []
	for face_index in range(data.faces.size()):
		var face: Dictionary = data.faces[face_index]
		var uv_center: Vector2 = Vector2.ZERO
		for uv in face.uv:
			uv_center += uv
		uv_center /= float(face.v.size())
		for k in range(face.v.size()):
			var prev: int = (k+face.v.size()-1)%face.v.size()
			var next: int = (k+1)%face.v.size()
			faces.append({"v":PackedInt32Array([face.v[k],edges[_edge_key(face.v[k],face.v[next])].point,centers[face_index],edges[_edge_key(face.v[prev],face.v[k])].point]),"uv":[face.uv[k],(face.uv[k]+face.uv[next])*0.5,uv_center,(face.uv[prev]+face.uv[k])*0.5],"group":face.group})
	return {"positions":points,"faces":faces}

static func _surface_mesh(data: Dictionary) -> ArrayMesh:
	var source: PackedVector3Array = data.positions
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(source.size())
	for face in data.faces:
		for k in range(1,face.v.size()-1):
			var a: int = face.v[0]
			var b: int = face.v[k]
			var c: int = face.v[k+1]
			var normal: Vector3 = (source[b]-source[a]).cross(source[c]-source[a])
			normals[a] += normal
			normals[b] += normal
			normals[c] += normal
	var vertices: PackedVector3Array = PackedVector3Array()
	var draw_normals: PackedVector3Array = PackedVector3Array()
	var uv: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var vertex_map: Dictionary = {}
	for face in data.faces:
		var draw_face: PackedInt32Array = PackedInt32Array()
		for k in range(face.v.size()):
			var vertex: int = face.v[k]
			var tex: Vector2 = face.uv[k]
			var key: String = str(vertex)+":"+str(tex)
			if not vertex_map.has(key):
				vertex_map[key] = vertices.size()
				vertices.append(source[vertex])
				draw_normals.append(normals[vertex].normalized())
				uv.append(tex)
			draw_face.append(vertex_map[key])
		# OBJ is counterclockwise; Godot front faces are clockwise.
		for k in range(1,draw_face.size()-1):
			indices.append_array(PackedInt32Array([draw_face[0],draw_face[k+1],draw_face[k]]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = draw_normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.set_meta("source_id",SOURCE_ID)
	mesh.set_meta("original_uv",true)
	return mesh

static func _textured_material(path: String, eyes: bool) -> StandardMaterial3D:
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture==null:
		return null
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.albedo_texture = texture
	material.roughness = 0.23 if eyes else 0.76
	material.metallic = 0.0
	material.metallic_specular = 0.5 if eyes else 0.28
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.set_meta("source_part","eyes" if eyes else "skin")
	material.set_meta("source_id",SOURCE_ID)
	return material

static func _root_relative(node: Node3D, scene_root: Node) -> Transform3D:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent!=null:
		if parent is Node3D:
			transform = parent.transform*transform
		if parent==scene_root:
			break
		parent = parent.get_parent()
	return transform

static func _nodes(root_node: Node) -> Array[Node]:
	var found: Array[Node] = [root_node]
	for child in root_node.get_children():
		found.append_array(_nodes(child))
	return found

static func _node_path(node: Node, scene_root: Node) -> String:
	var value: String = str(node.name)
	var parent: Node = node.get_parent()
	while parent!=null:
		value = str(parent.name)+"/"+value
		if parent==scene_root:
			break
		parent = parent.get_parent()
	return value

static func _texture_info(texture: Texture2D) -> Dictionary:
	if texture==null:
		return {}
	return {"path":texture.resource_path,"width":texture.get_width(),"height":texture.get_height()}

static func inspect_source(path: String) -> Dictionary:
	var result: Dictionary = {"sourcePath":path,"ready":false,"skeletons":[],"meshes":[],"errors":[]}
	if not ResourceLoader.exists(path):
		result.errors.append("Source is missing or has not been imported")
		return result
	var packed: PackedScene = load(path) as PackedScene
	if packed==null:
		result.errors.append("Source is not an imported PackedScene")
		return result
	var scene: Node = packed.instantiate()
	for node in _nodes(scene):
		if node is Skeleton3D:
			var skeleton: Skeleton3D = node
			var bone_data: Array = []
			var skeleton_transform: Transform3D = _root_relative(skeleton,scene)
			for index in range(skeleton.get_bone_count()):
				var rest: Transform3D = skeleton_transform*skeleton.get_bone_global_rest(index)
				bone_data.append({"index":index,"name":skeleton.get_bone_name(index),"parent":skeleton.get_bone_parent(index),"origin":[rest.origin.x,rest.origin.y,rest.origin.z],"basis":str(rest.basis)})
			result.skeletons.append({"node":_node_path(node,scene),"bones":bone_data})
		if node is MeshInstance3D and node.mesh!=null:
			var instance: MeshInstance3D = node
			var surfaces: Array = []
			for surface in range(instance.mesh.get_surface_count()):
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES]!=null else PackedInt32Array()
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS]!=null else PackedFloat32Array()
				var material: Material = instance.get_active_material(surface)
				var material_data: Dictionary = {"name":material.resource_name if material!=null else "","class":material.get_class() if material!=null else ""}
				if material is StandardMaterial3D:
					material_data["albedo"] = _texture_info(material.albedo_texture)
					material_data["normal"] = _texture_info(material.normal_texture)
					material_data["albedoColour"] = str(material.albedo_color)
					material_data["roughness"] = material.roughness
					material_data["transparency"] = material.transparency
				surfaces.append({"surface":surface,"vertices":vertices.size(),"triangles":indices.size()/3 if not indices.is_empty() else vertices.size()/3,"boneInfluences":bones.size()/maxi(1,vertices.size()),"weightCount":weights.size(),"material":material_data,"bounds":str(instance.mesh.get_aabb())})
			var binds: Array = []
			if instance.skin!=null:
				for bind in range(instance.skin.get_bind_count()):
					binds.append({"bind":bind,"bone":instance.skin.get_bind_bone(bind),"name":instance.skin.get_bind_name(bind),"pose":str(instance.skin.get_bind_pose(bind))})
			result.meshes.append({"node":_node_path(instance,scene),"transform":str(_root_relative(instance,scene)),"skeleton":str(instance.skeleton),"surfaces":surfaces,"binds":binds})
	scene.free()
	result["ready"] = result.errors.is_empty() and not result.meshes.is_empty()
	return result
