extends Node3D
## One authored height-field mesh drives rendering, contact, picking and navigation.
## Normalized simulation distances stay unchanged; camera size never changes bounds.
const EPS: float = .000001
var width: float = 0.0
var depth: float = 0.0
var bounds: Rect2
var terrain_bounds: Rect2
var _normalized_terrain_bounds: Rect2
var errors: Array = []
var source_hash: String = ""
var ground: MeshInstance3D
var collision_body: StaticBody3D
var _vertices: PackedVector3Array = []
var _indices: PackedInt32Array = []
var _faces: Array = []
var _boundary: Array = []
var _blockers: Array = []
var _cells: Dictionary = {}
var _cell_count: int = 4
var _ready_surface: bool = false
var _material: Material

func supports_world_geometry() -> bool:
	return true

func configure(stage: Dictionary, _legacy_width: float = 0, _legacy_depth: float = 0, _legacy_elevation: float = 0) -> void:
	if not stage.get("worldGeometry",{}) is Dictionary:
		_invalid("worldGeometry must be a dictionary")
		return
	var data: Dictionary = stage.get("worldGeometry",{})
	var fingerprint: String = JSON.stringify(data).sha256_text()
	if fingerprint == source_hash and _ready_surface: return
	load_geometry(data)

func clear_surface() -> void:
	_ready_surface = false
	width = 0; depth = 0; bounds = Rect2()
	terrain_bounds = Rect2(); _normalized_terrain_bounds = Rect2()
	_vertices.clear(); _indices.clear(); _faces.clear(); _boundary.clear()
	_blockers.clear(); _cells.clear(); source_hash = ""
	if is_instance_valid(ground): ground.free()
	if is_instance_valid(collision_body): collision_body.free()
	ground = null; collision_body = null

func _invalid(reason: String) -> bool:
	clear_surface()
	errors = [reason]
	return false

func load_geometry(data: Dictionary) -> bool:
	clear_surface()
	errors.clear()
	if not _identity_space(): return _invalid("Authored world provider requires identity transforms")
	if not _number(data.get("schemaVersion")) or float(data.schemaVersion)!=1: return _invalid("worldGeometry requires schemaVersion 1")
	if not data.get("simulationBounds") is Dictionary: return _invalid("simulationBounds must be a dictionary")
	var authored_bounds: Dictionary = data.get("simulationBounds",{})
	for key in ["x","z","width","depth"]:
		if not _number(authored_bounds.get(key)): return _invalid("simulationBounds coordinates must be numeric")
	bounds = Rect2(float(authored_bounds.get("x",NAN)),float(authored_bounds.get("z",NAN)),float(authored_bounds.get("width",NAN)),float(authored_bounds.get("depth",NAN)))
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0 or bounds.size.y<=0: return _invalid("Fixed simulationBounds must be finite and positive")
	width = bounds.size.x; depth = bounds.size.y
	# The metric stays fixed; a larger authored footprint only adds floor.
	var footprint: Variant = data.get("terrainBounds",authored_bounds)
	if not footprint is Dictionary: return _invalid("terrainBounds must be a dictionary")
	for key in ["x","z","width","depth"]:
		if not _number(footprint.get(key)): return _invalid("terrainBounds coordinates must be numeric")
	terrain_bounds = Rect2(float(footprint.x),float(footprint.z),float(footprint.width),float(footprint.depth))
	if terrain_bounds.size.x<=0 or terrain_bounds.size.y<=0 or not terrain_bounds.encloses(bounds): return _invalid("terrainBounds must contain the fixed simulationBounds")
	_normalized_terrain_bounds = Rect2((terrain_bounds.position-bounds.position)/bounds.size,terrain_bounds.size/bounds.size)
	var points: Variant = data.get("vertices",[])
	var indices: Variant = data.get("triangles",[])
	if not points is Array or points.size()<3 or not indices is Array or indices.is_empty() or indices.size()%3!=0: return _invalid("Indexed ground triangles are required")
	var unique: Dictionary = {}
	for value in points:
		if not value is Dictionary: return _invalid("Each ground vertex must be {x,y,z}")
		for key in ["x","y","z"]:
			if not _number(value.get(key)): return _invalid("Ground vertex coordinates must be numeric")
		var point: Vector3 = Vector3(float(value.get("x",NAN)),float(value.get("y",NAN)),float(value.get("z",NAN)))
		var normalized: Vector2 = Vector2((point.x-bounds.position.x)/width,(point.z-bounds.position.y)/depth)
		if not point.is_finite() or not _normalized_terrain_bounds.grow(EPS).has_point(normalized): return _invalid("Ground vertex is nonfinite or outside terrainBounds")
		var xz: Vector2 = Vector2(point.x,point.z)
		if unique.has(xz): return _invalid("Duplicate X/Z vertices or stacked floors are unsupported")
		unique[xz] = true
		_vertices.append(point)
	var walkable: Variant = data.get("triangleWalkable",[])
	if not walkable is Array or (not walkable.is_empty() and walkable.size()!=indices.size()/3): return _invalid("triangleWalkable must be empty or one bool per triangle")
	var edges: Dictionary = {}
	var all_edges: Dictionary = {}
	for offset in range(0,indices.size(),3):
		var ids: Array = []
		for n in range(3):
			var value: Variant = indices[offset+n]
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)) or int(value)<0 or int(value)>=_vertices.size(): return _invalid("Ground triangle index is invalid")
			ids.append(int(value))
		var a: Vector3 = _vertices[ids[0]]; var b: Vector3 = _vertices[ids[1]]; var c: Vector3 = _vertices[ids[2]]
		# Godot triangle fronts use clockwise winding. Give ground an upward front.
		var normal: Vector3 = (c-a).cross(b-a)
		if not normal.is_finite(): return _invalid("Ground triangle scale produces nonfinite normals")
		if absf(normal.y)<.00000001: return _invalid("Vertical or degenerate ground triangles are unsupported")
		if normal.y<0:
			var swap: int = ids[1]; ids[1]=ids[2]; ids[2]=swap
			b=_vertices[ids[1]]; c=_vertices[ids[2]]; normal=-normal
		var polygon: PackedVector2Array = [world_to_normalized(a),world_to_normalized(b),world_to_normalized(c)]
		if absf(_polygon_area(polygon))<.000000000001: return _invalid("Ground triangle is degenerate in simulation coordinates")
		var allowed: bool = true
		if not walkable.is_empty():
			if not walkable[offset/3] is bool: return _invalid("triangleWalkable entries must be bool")
			allowed=walkable[offset/3]
		_faces.append({"ids":ids,"points":polygon,"normal":normal.normalized(),"walkable":allowed,"rect":Rect2(polygon[0],Vector2.ZERO).expand(polygon[1]).expand(polygon[2])})
		_indices.append_array(PackedInt32Array(ids))
		for n in range(3):
			var first: int = ids[n]; var second: int = ids[(n+1)%3]
			var key: Vector2i = Vector2i(mini(first,second),maxi(first,second))
			all_edges[key]=int(all_edges.get(key,0))+1
			if int(all_edges[key])>2: return _invalid("Nonmanifold ground edges are unsupported")
			if allowed: edges[key]=int(edges.get(key,0))+1
	_cell_count=clampi(ceili(sqrt(float(_faces.size()))),4,64)
	for index in range(_faces.size()):
		for cell in _rect_cells(_faces[index].rect):
			if not _cells.has(cell): _cells[cell]=[]
			_cells[cell].append(index)
	for index in range(_faces.size()):
		var face: Dictionary = _faces[index]
		for other in _candidate_faces(face.rect):
			if int(other)<=index: continue
			for intersection in Geometry2D.intersect_polygons(face.points,_faces[other].points):
				if absf(_polygon_area(intersection))>.00000001: return _invalid("Overlapping projected floor triangles are unsupported")
	# Reject T-junctions instead of treating their internal partial seams as walls.
	for key in all_edges:
		var start: Vector2=world_to_normalized(_vertices[key.x]); var end: Vector2=world_to_normalized(_vertices[key.y])
		var rect: Rect2=Rect2(start,Vector2.ZERO).expand(end)
		for face_index in _candidate_faces(rect):
			for id in _faces[face_index].ids:
				if int(id)==key.x or int(id)==key.y: continue
				var point: Vector2=world_to_normalized(_vertices[id])
				var closest: Vector2=Geometry2D.get_closest_point_to_segment(point,start,end)
				if point.distance_squared_to(closest)<.000000000001 and closest.distance_squared_to(start)>.000000000001 and closest.distance_squared_to(end)>.000000000001: return _invalid("Ground T-junctions must share authored vertex indices")
		if int(edges.get(key,0))==1: _boundary.append([start,end])
	var blockers: Variant=data.get("blockedPolygons",[])
	if not blockers is Array: return _invalid("blockedPolygons must be an array")
	for entry in blockers:
		if not entry is Dictionary or not entry.get("points") is Array: return _invalid("Each blocker requires points in world X/Z")
		for flag in ["blocksMovement","blocksPlacement"]:
			if entry.has(flag) and not entry[flag] is bool: return _invalid("Blocker flags must be bool")
		var polygon: PackedVector2Array=[]
		for value in entry.points:
			if not value is Dictionary: return _invalid("Each blocker point must be {x,z}")
			if not _number(value.get("x")) or not _number(value.get("z")): return _invalid("Blocker coordinates must be numeric")
			var point: Vector2=Vector2(float(value.get("x",NAN)),float(value.get("z",NAN)))
			if not point.is_finite(): return _invalid("Blocker coordinates must be finite")
			polygon.append((point-bounds.position)/bounds.size)
		if not _simple_polygon(polygon): return _invalid("Blockers require simple nondegenerate polygons")
		_blockers.append({"id":str(entry.get("id","")),"points":polygon,"movement":bool(entry.get("blocksMovement",true)),"placement":bool(entry.get("blocksPlacement",true))})
	_build_surface()
	source_hash=JSON.stringify(data).sha256_text()
	_ready_surface=true
	return true

func _polygon_area(points: PackedVector2Array) -> float:
	var area: float=0.0
	for n in range(points.size()): area+=points[n].cross(points[(n+1)%points.size()])
	return area*.5

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _identity_space() -> bool:
	return transform.is_equal_approx(Transform3D.IDENTITY) and (not is_inside_tree() or global_transform.is_equal_approx(Transform3D.IDENTITY))

func _simple_polygon(points: PackedVector2Array) -> bool:
	if points.size()<3 or absf(_polygon_area(points))<.00000001: return false
	for n in range(points.size()):
		if points[n].distance_squared_to(points[(n+1)%points.size()])<.000000000001: return false
		var incoming: Vector2=points[n]-points[(n-1+points.size())%points.size()]
		var outgoing: Vector2=points[(n+1)%points.size()]-points[n]
		if absf(incoming.cross(outgoing))<.000000000001 and incoming.dot(outgoing)<0: return false
		for j in range(n+1,points.size()):
			if j==n+1 or (n==0 and j==points.size()-1): continue
			if _segment_distance(points[n],points[(n+1)%points.size()],points[j],points[(j+1)%points.size()])<.00000001: return false
	return true

func _rect_cells(rect: Rect2) -> Array:
	var result: Array=[]
	if not _normalized_terrain_bounds.grow(EPS).intersects(rect.grow(EPS),true): return result
	var cell_start: Vector2=(rect.position-_normalized_terrain_bounds.position-Vector2.ONE*EPS)/_normalized_terrain_bounds.size
	var cell_end: Vector2=(rect.end-_normalized_terrain_bounds.position+Vector2.ONE*EPS)/_normalized_terrain_bounds.size
	var first: Vector2i=Vector2i(clampi(floori(cell_start.x*_cell_count),0,_cell_count-1),clampi(floori(cell_start.y*_cell_count),0,_cell_count-1))
	var last: Vector2i=Vector2i(clampi(floori(cell_end.x*_cell_count),0,_cell_count-1),clampi(floori(cell_end.y*_cell_count),0,_cell_count-1))
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1): result.append(Vector2i(x,y))
	return result

func _candidate_faces(rect: Rect2) -> Array:
	var found: Dictionary={}
	for cell in _rect_cells(rect):
		for index in _cells.get(cell,[]): found[index]=true
	return found.keys()

func _build_surface() -> void:
	var normals: PackedVector3Array=[]; var uv: PackedVector2Array=[]
	normals.resize(_vertices.size())
	for face in _faces:
		for id in face.ids: normals[id]+=face.normal
	for id in range(_vertices.size()):
		normals[id]=normals[id].normalized()
		uv.append(Vector2(_vertices[id].x,_vertices[id].z))
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=_indices
	var mesh: ArrayMesh=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	# Normal-mapped materials need a UV-aligned tangent basis, not just normals.
	var shading: SurfaceTool=SurfaceTool.new()
	shading.create_from(mesh,0)
	shading.generate_tangents()
	mesh=shading.commit()
	ground=MeshInstance3D.new(); ground.name="AuthoredGround"; ground.mesh=mesh; ground.material_override=_material; add_child(ground)
	collision_body=StaticBody3D.new(); collision_body.name="AuthoredGroundCollision"; add_child(collision_body)
	var shape: CollisionShape3D=CollisionShape3D.new(); shape.shape=mesh.create_trimesh_shape(); collision_body.add_child(shape)

func surface_mesh() -> ArrayMesh:
	return ground.mesh as ArrayMesh if is_instance_valid(ground) else null

func set_surface_material(material: Material) -> void:
	_material=material
	if is_instance_valid(ground): ground.material_override=material

func world_to_normalized(point: Vector3) -> Vector2:
	if width<=0 or depth<=0 or not point.is_finite(): return Vector2(NAN,NAN)
	return Vector2((point.x-bounds.position.x)/width,(point.z-bounds.position.y)/depth)

func world_point(point: Vector2) -> Vector3:
	return Vector3(bounds.position.x+point.x*width,height_at(point),bounds.position.y+point.y*depth)

func _height_on_face(point: Vector2, face: Dictionary) -> float:
	var p: PackedVector2Array=face.points
	var denom: float=(p[1]-p[0]).cross(p[2]-p[0])
	var second: float=(point-p[0]).cross(p[2]-p[0])/denom
	var third: float=(p[1]-p[0]).cross(point-p[0])/denom
	if second < -EPS or third < -EPS or second+third > 1+EPS: return NAN
	return _vertices[face.ids[0]].y*(1-second-third)+_vertices[face.ids[1]].y*second+_vertices[face.ids[2]].y*third

func height_at(point: Vector2) -> float:
	if not _ready_surface or not _identity_space() or not point.is_finite() or not _normalized_terrain_bounds.grow(EPS).has_point(point): return NAN
	for index in _candidate_faces(Rect2(point,Vector2.ZERO)):
		var height: float=_height_on_face(point,_faces[index])
		if is_finite(height): return height
	return NAN

func sample_world_height(point: Vector3) -> float:
	# A lifted foot's Y must not influence which X/Z surface is sampled.
	return height_at(world_to_normalized(point))

func ray_pick(origin: Vector3, direction: Vector3) -> Dictionary:
	var result: Dictionary={"valid":false}
	if not _ready_surface or not _identity_space() or not origin.is_finite() or not direction.is_finite() or direction.length_squared()<.000000000001: return result
	var nearest: float=INF
	for index in range(_faces.size()):
		var face: Dictionary=_faces[index]
		var hit: Variant=Geometry3D.ray_intersects_triangle(origin,direction,_vertices[face.ids[0]],_vertices[face.ids[1]],_vertices[face.ids[2]])
		if not hit is Vector3: continue
		var distance: float=origin.distance_squared_to(hit)
		if distance<nearest:
			nearest=distance
			result={"valid":true,"position":world_to_normalized(hit),"worldPosition":hit,"normal":face.normal,"triangleIndex":index,"walkable":face.walkable}
	return result

func _face_interval(start: Vector2, end: Vector2, face: Dictionary) -> Vector2:
	var lower: float=0.0; var upper: float=1.0
	var polygon: PackedVector2Array=face.points
	var sign_value: float=signf(_polygon_area(polygon))
	for n in range(3):
		var corner: Vector2=polygon[n]
		var next_corner: Vector2=polygon[(n+1)%3]
		# Vector2 subtraction/cross rounds in float32. Separate rounded start
		# and direction distances can create a false gap at a shared seam.
		# Compute both endpoint distances in scalar float64 before clipping.
		var edge_x: float=float(next_corner.x)-float(corner.x)
		var edge_y: float=float(next_corner.y)-float(corner.y)
		var value: float=sign_value*(edge_x*(float(start.y)-float(corner.y))-edge_y*(float(start.x)-float(corner.x)))
		var end_value: float=sign_value*(edge_x*(float(end.y)-float(corner.y))-edge_y*(float(end.x)-float(corner.x)))
		var change: float=end_value-value
		if absf(change)<.000000000001:
			if value < -.0000000001: return Vector2(1,0)
		elif change>0: lower=maxf(lower,(-.0000000001-value)/change)
		else: upper=minf(upper,(-.0000000001-value)/change)
		if lower>upper: return Vector2(1,0)
	return Vector2(lower,upper)

func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return 0.0
	return minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a,c,d)),b.distance_to(Geometry2D.get_closest_point_to_segment(b,c,d))),minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b)),d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))))

func _floor_clear(start: Vector2, end: Vector2, margin: float) -> bool:
	if not _ready_surface or not start.is_finite() or not end.is_finite() or not is_finite(margin) or margin<0: return false
	if not is_finite(height_at(start)) or not is_finite(height_at(end)): return false
	var intervals: Array=[]
	for index in _candidate_faces(Rect2(start,Vector2.ZERO).expand(end)):
		if not bool(_faces[index].walkable): continue
		var interval: Vector2=_face_interval(start,end,_faces[index])
		if interval.x<=interval.y: intervals.append(interval)
	intervals.sort_custom(func(a: Vector2,b: Vector2): return a.x<b.x)
	var covered: float=0.0
	for interval in intervals:
		if interval.x>covered+EPS: return false
		covered=maxf(covered,interval.y)
	if covered<1-EPS: return false
	for edge in _boundary:
		if _segment_distance(start,end,edge[0],edge[1])<margin-.00000001: return false
	return true

func _blocked(start: Vector2, end: Vector2, margin: float, kind: String) -> bool:
	for blocker in _blockers:
		if not bool(blocker[kind]): continue
		var polygon: PackedVector2Array=blocker.points
		if Geometry2D.is_point_in_polygon(start,polygon) or Geometry2D.is_point_in_polygon(end,polygon): return true
		for n in range(polygon.size()):
			if _segment_distance(start,end,polygon[n],polygon[(n+1)%polygon.size()])<=margin+.00000001: return true
	return false

func segment_clear(start: Vector2, end: Vector2, margin: float = 0.0) -> bool:
	return _floor_clear(start,end,margin) and not _blocked(start,end,margin,"movement")

func placement_clear(point: Vector2, margin: float = 0.0) -> bool:
	if not point.is_finite() or point.x<0 or point.x>1 or point.y<0 or point.y>1: return false
	return _floor_clear(point,point,margin) and not _blocked(point,point,margin,"placement")

func diagnostics() -> Dictionary:
	return {"geometryFirst":true,"ready":_ready_surface and _identity_space(),"errors":errors.duplicate(),"sourceHash":source_hash,"vertices":_vertices.size(),"triangles":_faces.size(),"boundaryEdges":_boundary.size(),"blockers":_blockers.size(),"worldWidth":width,"worldDepth":depth,"simulationBounds":{"x":bounds.position.x,"z":bounds.position.y,"width":width,"depth":depth},"terrainBounds":{"x":terrain_bounds.position.x,"z":terrain_bounds.position.y,"width":terrain_bounds.size.x,"depth":terrain_bounds.size.y},"projectionShear":false}
