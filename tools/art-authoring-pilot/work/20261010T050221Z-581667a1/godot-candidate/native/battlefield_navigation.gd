extends RefCounted
## PRIVATE API: observe emitted parts once; every query uses this scene only.
## No union: actual individual primitive footprints retain openings/holes.
var snapshots: Array=[]
var vertex_cache: Dictionary={}
var raw_count: int=0
var query_count: int=0
var polygon_tests: int=0
var verify_union: bool=false # QA compatibility; this cache performs no union.
var world_point_callback: Callable
var current: Dictionary={}
var current_width: float=18.5
var current_depth: float=1.0
var unclassified_parts: Array=[]

var query_bins: Dictionary={}

func invalidate() -> void:
	current.clear();snapshots.clear();vertex_cache.clear();query_bins.clear()
	unclassified_parts.clear()
	raw_count=0;query_count=0;polygon_tests=0
	world_point_callback=Callable()

func capture_current(parts: Array,world_point: Callable,width: float,depth: float) -> Dictionary:
	invalidate()
	world_point_callback=world_point;current_width=width;current_depth=depth
	var entries: Array=[]
	var phase_counts: Dictionary={}
	for part in parts:
		var phase: String=str(part.get("phase",""))
		if phase not in ["structure","roof","banner","gate_upper","platform","ground_surface"]:
			unclassified_parts.append({"owner":part.get("owner",""),"key":part.get("key",""),"phase":phase})
			continue
		phase_counts[phase]=int(phase_counts.get(phase,0))+1
		if phase in ["banner","ground_surface"]: continue
		var mesh: Mesh=part.mesh
		var id: int=mesh.get_instance_id()
		if not vertex_cache.has(id):
			var vertices: PackedVector3Array=PackedVector3Array()
			for surface in range(mesh.get_surface_count()):
				vertices.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
			vertex_cache[id]=vertices
		var points: PackedVector2Array=PackedVector2Array()
		for vertex in vertex_cache[id]:
			var actual: Vector3=part.transform*Vector3(vertex)
			points.append(Vector2(actual.x,actual.z))
		if points.size()<3: continue
		var hull: PackedVector2Array=Geometry2D.convex_hull(points)
		if hull.size()<3: continue
		var movement: bool=phase=="structure"
		entries.append({"polygon":hull,"aabb":bounds_of(hull),"projection":hull,"projectionAabb":bounds_of(hull),"movement":movement,"owner":str(part.get("owner","")),"sources":[str(part.get("key",""))+":"+phase],"partCount":1})
		raw_count+=1
	# Primitive polygons retain all omitted wall pieces and compound openings.
	for index in range(entries.size()):
		for cell in cells_for(entries[index].aabb):
			if not query_bins.has(cell): query_bins[cell]=[]
			query_bins[cell].append(index)
	var union_audit: Dictionary={"executed":false,"mode":"actual_primitive_identity_no_union","sourceFootprints":entries.size(),"addedAreaWorldSquared":0.0,"omittedAreaWorldSquared":0.0}
	current={"entries":entries,"depth":depth,"sourceCounts":phase_counts,"exactUnionAudit":union_audit}
	snapshots=[current]
	return current

func clear_segment(a: Vector2,b: Vector2,margin_normalized: float=0.0,placement: bool=false,_ignored_snapshot: int=-1) -> bool:
	query_count+=1
	# Invalid callback fails closed; callers clear/bind the cache on map change.
	if not world_point_callback.is_valid() or not unclassified_parts.is_empty(): return false
	var first: Vector3=world_point_callback.call(a)
	var last: Vector3=world_point_callback.call(b)
	var start: Vector2=Vector2(first.x,first.z);var end: Vector2=Vector2(last.x,last.z)
	var margin: float=margin_normalized*maxf(current_width,current_depth)
	var query_margin: float = maxf(margin,.34) if placement else margin
	var query: Rect2=Rect2(start,Vector2.ZERO).expand(end).grow(query_margin+.000001)
	var candidates: Dictionary={}
	for cell in cells_for(query):
		for index in query_bins.get(cell,[]): candidates[index]=true
	for index in candidates:
		var entry: Dictionary=current.entries[int(index)]
		if not placement and not entry.movement: continue
		# A planted actor's feet travel farther during its walk/attack poses
		# than the route's center-line clearance. Low earth banks need that
		# full foot envelope even though their top is only ankle-high.
		var entry_margin: float = maxf(margin,.34) if placement and entry.sources[0].begins_with("earth_bank:") else margin
		if Rect2(start,Vector2.ZERO).expand(end).grow(entry_margin+.000001).intersects(entry.aabb,true) and segment_hits(start,end,entry.polygon,entry_margin): return false
	return true

func segment_clear(a: Vector2,b: Vector2,margin: float=.008) -> bool:
	return clear_segment(a,b,margin,false)

func placement_clear(p: Vector2,margin: float=.012) -> bool:
	return clear_segment(p,p,margin,true)

func obstruction_report(a: Vector2,b: Vector2,margin: float) -> Array:
	var first: Vector3=world_point_callback.call(a);var last: Vector3=world_point_callback.call(b)
	var start: Vector2=Vector2(first.x,first.z);var end: Vector2=Vector2(last.x,last.z)
	var world_margin: float=margin*maxf(current_width,current_depth)
	var rect: Rect2=Rect2(start,Vector2.ZERO).expand(end).grow(world_margin+.000001)
	var found: Array=[]
	for entry in current.entries:
		if not entry.movement or not rect.intersects(entry.aabb,true): continue
		if not segment_hits(start,end,entry.polygon,world_margin): continue
		var polygon: Array=[]
		for p in entry.polygon: polygon.append([p.x,p.y])
		found.append({"owner":entry.owner,"actualSourceKeys":entry.sources,"worldXZ":polygon,"normalizedStart":[a.x,a.y],"normalizedEnd":[b.x,b.y],"actualWorldStart":[first.x,first.y,first.z],"actualWorldEnd":[last.x,last.y,last.z],"worldMargin":world_margin})
	return found

func cells_for(rect: Rect2) -> Array:
	var result: Array=[]
	for y in range(floori(rect.position.y/.65),floori(rect.end.y/.65)+1):
		for x in range(floori(rect.position.x/.65),floori(rect.end.x/.65)+1): result.append(Vector2i(x,y))
	return result

func bounds_of(poly: PackedVector2Array) -> Rect2:
	var bounds: Rect2=Rect2(poly[0],Vector2.ZERO)
	for p in poly: bounds=bounds.expand(p)
	return bounds

func point_hits(p: Vector2,poly: PackedVector2Array,margin: float) -> bool:
	polygon_tests+=1
	if Geometry2D.is_point_in_polygon(p,poly): return true
	for i in range(poly.size()):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()]))<=margin: return true
	return false

func segment_hits(a: Vector2,b: Vector2,poly: PackedVector2Array,margin: float) -> bool:
	if point_hits(a,poly,margin) or point_hits(b,poly,margin): return true
	for i in range(poly.size()):
		var c: Vector2=poly[i];var d: Vector2=poly[(i+1)%poly.size()]
		if Geometry2D.segment_intersects_segment(a,b,c,d)!=null: return true
		if c.distance_to(Geometry2D.get_closest_point_to_segment(c,a,b))<=margin or d.distance_to(Geometry2D.get_closest_point_to_segment(d,a,b))<=margin: return true
	return false

func report() -> Array:
	var result: Array=[]
	for snapshot in snapshots:
		var polygons: Array=[]
		for entry in snapshot.entries:
			var points: Array=[]
			for p in entry.polygon: points.append([p.x,p.y])
			polygons.append({"owner":entry.owner,"movement":entry.movement,"sources":entry.sources,"actualEmittedPartCount":entry.partCount,"worldXZ":points})
		result.append({"worldDepth":snapshot.depth,"actualSourceCounts":snapshot.sourceCounts,"polygonCount":polygons.size(),"exactUnionAudit":snapshot.exactUnionAudit,"polygons":polygons})
	return result
