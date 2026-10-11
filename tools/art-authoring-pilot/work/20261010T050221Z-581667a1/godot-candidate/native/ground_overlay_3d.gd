extends Node3D
## Shared retained terrain display only. No picking, placement or combat authority.
const OverlayShader = preload("res://native/ground_overlay.gdshader")
const DESCRIPTORS_PER_PASS: int = 16
const PREALLOCATED_DESCRIPTOR_CAPACITY: int = 128
const CHUNK_AXIS: int = 4
const MAX_CHUNKS: int = CHUNK_AXIS*CHUNK_AXIS
const SURFACE_BIAS: float = 0.002

var _terrain_signature: Array = []
var _chunks: Array = []
var _materials: Array = []
var _passes: Array = []
var _descriptors: Array = []
var _geometry_rebuilds: int = 0
var _descriptor_updates: int = 0
var _capacity_extensions: int = 0
var _invalid_descriptors: int = 0
var _active_pages: int = 0
var _source_triangles: int = 0
var _ready_surface: bool = false
var _status: String = "NO_AUTHORED_SURFACE"

func bind_terrain(provider: Node3D) -> bool:
	if not is_instance_valid(provider) or not provider.has_method("surface_mesh") or not provider.has_method("diagnostics"):
		_invalidate_surface("NO_AUTHORED_SURFACE")
		return false
	var info: Dictionary = provider.diagnostics()
	var mesh: ArrayMesh = provider.surface_mesh()
	var width: float = float(provider.get("width"))
	var depth: float = float(provider.get("depth"))
	var bounds: Rect2 = provider.get("bounds")
	if not bool(info.get("ready",false)) or mesh == null or mesh.get_surface_count() != 1 or not is_finite(width) or not is_finite(depth) or width <= 0 or depth <= 0:
		_invalidate_surface("INVALID_AUTHORED_SURFACE")
		return false
	var signature: Array = [provider.get_instance_id(),str(info.get("sourceHash","")),mesh.get_instance_id(),bounds,width,depth]
	if signature == _terrain_signature and _ready_surface: return true
	_clear_geometry()
	global_transform = provider.global_transform
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var index_count: int = indices.size() if not indices.is_empty() else vertices.size()
	if index_count == 0 or index_count%3 != 0:
		_invalidate_surface("INVALID_SURFACE_TRIANGLES")
		return false
	var groups: Array = []
	for index in range(MAX_CHUNKS): groups.append({"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array()})
	for offset in range(0,index_count,3):
		var ids: PackedInt32Array = PackedInt32Array()
		for corner in range(3): ids.append(indices[offset+corner] if not indices.is_empty() else offset+corner)
		var center: Vector3 = (vertices[ids[0]]+vertices[ids[1]]+vertices[ids[2]])/3.0
		var cell_x: int = clampi(int(floor((center.x-bounds.position.x)/width*CHUNK_AXIS)),0,CHUNK_AXIS-1)
		var cell_z: int = clampi(int(floor((center.z-bounds.position.y)/depth*CHUNK_AXIS)),0,CHUNK_AXIS-1)
		var group: Dictionary = groups[cell_z*CHUNK_AXIS+cell_x]
		for id in ids:
			var point: Vector3 = vertices[id]
			group.vertices.append(point)
			group.normals.append(normals[id] if normals.size() == vertices.size() else Vector3.UP)
			group.uv.append(Vector2((point.x-bounds.position.x)/width,(point.z-bounds.position.y)/depth))
	for group in groups:
		if group.vertices.is_empty(): continue
		var chunk_arrays: Array = []
		chunk_arrays.resize(Mesh.ARRAY_MAX)
		chunk_arrays[Mesh.ARRAY_VERTEX] = group.vertices
		chunk_arrays[Mesh.ARRAY_NORMAL] = group.normals
		chunk_arrays[Mesh.ARRAY_TEX_UV] = group.uv
		var chunk: ArrayMesh = ArrayMesh.new()
		chunk.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,chunk_arrays)
		_chunks.append(chunk)
	_source_triangles = index_count/3
	_terrain_signature = signature
	_ready_surface = true
	_status = "READY"
	_geometry_rebuilds += 1
	_descriptors.clear()
	_ensure_pages(maxi(PREALLOCATED_DESCRIPTOR_CAPACITY/DESCRIPTORS_PER_PASS,_materials.size()))
	return true

func _invalidate_surface(reason: String) -> void:
	_ready_surface = false
	_status = reason
	_terrain_signature.clear()
	_active_pages = 0
	_descriptors.clear()
	for page in _passes:
		for instance in page: instance.hide()

func _clear_geometry() -> void:
	for page in _passes:
		for instance in page:
			instance.hide()
			instance.queue_free()
	_passes.clear()
	_chunks.clear()
	_active_pages = 0
	_source_triangles = 0

func _ensure_pages(count: int) -> void:
	while _materials.size() < count:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = OverlayShader
		material.set_shader_parameter("surface_bias",SURFACE_BIAS)
		# Current legitimate data fits three pages. Additional pages retain all
		# descriptors; no zone is discarded on exceeding the initial allocation.
		material.render_priority = mini(_materials.size(),127)
		_materials.append(material)
	while _passes.size() < count:
		var page: Array = []
		for chunk in _chunks:
			var instance: MeshInstance3D = MeshInstance3D.new()
			instance.name = "GroundOverlay_%d_%d" % [_passes.size(),page.size()]
			instance.mesh = chunk # The same terrain-derived resource in every page.
			instance.material_override = _materials[_passes.size()]
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.extra_cull_margin = SURFACE_BIAS
			instance.hide()
			add_child(instance)
			page.append(instance)
		_passes.append(page)

func update_descriptors(values: Array) -> void:
	if not _ready_surface: return
	var accepted: Array = []
	_invalid_descriptors = 0
	for value in values:
		if not value is Dictionary or not value.get("center") is Vector2 or not value.get("fill") is Color or not value.get("outline") is Color:
			_invalid_descriptors += 1
			continue
		var center: Vector2 = value.center
		var radius: float = float(value.get("radius",0))
		var line_width: float = float(value.get("lineWidth",1.2))
		if not center.is_finite() or not is_finite(radius) or radius <= 0 or not is_finite(line_width) or line_width <= 0:
			_invalid_descriptors += 1
			continue
		accepted.append({"center":center,"radius":radius,"fill":value.fill,"outline":value.outline,"lineWidth":line_width,"kind":str(value.get("kind","circle"))})
	if accepted == _descriptors: return
	_descriptors = accepted
	_descriptor_updates += 1
	_active_pages = ceili(float(accepted.size())/DESCRIPTORS_PER_PASS)
	var previous_pages: int = _materials.size()
	_ensure_pages(maxi(PREALLOCATED_DESCRIPTOR_CAPACITY/DESCRIPTORS_PER_PASS,_active_pages))
	if _materials.size() > previous_pages: _capacity_extensions += 1
	for page_index in range(_passes.size()):
		var enabled: bool = page_index < _active_pages
		for instance in _passes[page_index]: instance.visible = enabled
		if not enabled: continue
		var circles: Array[Vector4] = []
		var fills: Array[Color] = []
		var outlines: Array[Color] = []
		var count: int = mini(DESCRIPTORS_PER_PASS,accepted.size()-page_index*DESCRIPTORS_PER_PASS)
		for index in range(DESCRIPTORS_PER_PASS):
			if index < count:
				var descriptor: Dictionary = accepted[page_index*DESCRIPTORS_PER_PASS+index]
				circles.append(Vector4(descriptor.center.x,descriptor.center.y,descriptor.radius,descriptor.lineWidth))
				fills.append(descriptor.fill)
				outlines.append(descriptor.outline)
			else:
				circles.append(Vector4.ZERO)
				fills.append(Color(0,0,0,0))
				outlines.append(Color(0,0,0,0))
		var material: ShaderMaterial = _materials[page_index]
		material.set_shader_parameter("circle_count",count)
		material.set_shader_parameter("circles",circles)
		material.set_shader_parameter("fill_colors",fills)
		material.set_shader_parameter("outline_colors",outlines)

func descriptor_snapshot() -> Array:
	return _descriptors.duplicate(true)

func diagnostics() -> Dictionary:
	return {"status":_status,"ready":_ready_surface,"geometryRebuilds":_geometry_rebuilds,"descriptorUpdates":_descriptor_updates,"activeDescriptors":_descriptors.size(),"chunkCount":_chunks.size(),"maxChunks":MAX_CHUNKS,"descriptorsPerPass":DESCRIPTORS_PER_PASS,"preallocatedDescriptorCapacity":PREALLOCATED_DESCRIPTOR_CAPACITY,"allocatedPages":_materials.size(),"activePasses":_active_pages,"renderSubmissions":_active_pages*_chunks.size(),"submissionCountIsUpperBound":true,"capacityExtensions":_capacity_extensions,"invalidDescriptors":_invalid_descriptors,"pageOrderPriorityExceeded":_active_pages>128,"sourceTriangles":_source_triangles,"surfaceBias":SURFACE_BIAS,"depthTest":true,"terrainSignature":_terrain_signature.duplicate()}
