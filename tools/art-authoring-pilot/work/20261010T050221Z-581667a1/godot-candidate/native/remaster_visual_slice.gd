extends Node3D
## Newly authored candidate art. FUNCTIONAL provider remains the sole floor/pick source.
const SurfaceMaterials = preload("res://native/remaster_surface_materials.gd")
const SourceTextures = preload("res://native/battlefield_materials.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const MODEL_ROOT: String = "res://assets/models/battlefield/"
const CROWN_TEXTURE: String = "res://assets/battlefields-remaster/materials/stage01-broadleaf-canopy-v1.png"
const CROWN_TEXTURE_SHA256: String = "3d02148c7d6491da09080b931d463ea83d9feaca77df088660249e143371d354"
var provider: Node3D
var composition: Dictionary = {}
var prop_count: int = 0
var picket_count: int = 0
var static_instance_groups: int = 0
var material_channels: int = 0
var scan_templates: Dictionary = {}
var static_triangles: int = 0
var scenery_vertices: PackedVector3Array = []
var scenery_indices: PackedInt32Array = []
var scenery_bounds: Rect2
var scenery_mesh: MeshInstance3D
var scenery_height_failures: int = 0
var direction_cues: Array = []
var stream_triangle_count: int = 0
var canopy_tree_count: int = 0
var canopy_triangle_count: int = 0
var earthwork_picket_count: int = 0
var crown_sprite_count: int = 0
var understory_cluster_count: int = 0
var understory_triangle_count: int = 0
var volume_leaf_triangles: int = 0
var volume_wood_triangles: int = 0
var lighting_readback: Dictionary = {}
var lighting_owner: WeakRef

func configure(stage: Dictionary, floor_provider: Node3D) -> void:
	provider = floor_provider
	composition = stage.get("visualComposition",{}).duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	prop_count = 0
	picket_count = 0
	static_instance_groups = 0
	_pilot_prepare()
	composition["materialPadHeightSamples"] = _material_pad_height_samples()
	provider.set_surface_material(_pilot_ground_material(SurfaceMaterials.ground(composition)))
	if composition.has("artCoherence"):
		# Receiver stays visible/depth-tested;only floor self-casting is disabled.
		var ground_receiver: MeshInstance3D=provider.get_node_or_null("AuthoredGround") as MeshInstance3D
		if ground_receiver!=null: ground_receiver.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_channels = 16
	static_triangles = 0
	scenery_height_failures = 0
	direction_cues.clear()
	stream_triangle_count = 0
	canopy_tree_count = 0
	canopy_triangle_count = 0
	earthwork_picket_count = 0
	crown_sprite_count = 0
	understory_cluster_count = 0
	understory_triangle_count = 0
	volume_leaf_triangles = 0
	volume_wood_triangles = 0
	lighting_readback.clear()
	lighting_owner=null
	_build_landscape_scenery()
	_build_scenery_stream()
	_build_palisades()
	_build_earthwork_pickets()
	_build_gate()
	_build_shelter()
	_build_scanned_props()
	_build_loose_timber()
	if str(composition.get("renderStyle","")) == "compact-smooth-v2":
		_build_camp_details()
		_build_direction_cues()

func _material_pad_height_samples() -> Dictionary:
	# Presentation receives measured heights from the one actual floor. Never
	# derive a new platform, navigation height or gameplay elevation from art.
	var result: Dictionary = {}
	for area in composition.get("deploymentAreas",[]):
		var data: Dictionary = area.get("earthworkPresentation",{})
		var center: Array = area.get("center",[])
		var radii: Array = data.get("bankRadiiWorld",[])
		if not bool(data.get("floorOwnsElevation",false)) or center.size()!=2 or radii.size()!=2: continue
		if float(radii[0])<=0 or float(radii[1])<=0: continue
		var centre_y: float = provider.sample_world_height(Vector3(float(center[0]),0,float(center[1])))
		if not is_finite(centre_y): continue
		var sum_y: float = 0.0
		var min_y: float = INF
		var max_y: float = -INF
		var count: int = 0
		for index in range(16):
			var angle: float = TAU*float(index)/16.0
			var point := Vector3(float(center[0])+cos(angle)*float(radii[0]),0,float(center[1])+sin(angle)*float(radii[1]))
			var height: float = provider.sample_world_height(point)
			if not is_finite(height): break
			sum_y += height
			min_y = minf(min_y,height)
			max_y = maxf(max_y,height)
			count += 1
		if count!=16 or centre_y<=sum_y/16.0+.001: continue
		result[str(area.id)] = {"centreY":centre_y,"baseYMean":sum_y/16.0,"baseYMin":min_y,"baseYMax":max_y,"sampleCount":count}
	return result

func _build_direction_cues() -> void:
	# Both plan and gameplay read these WORLD XZ presentation anchors. They do
	# not supply a simulation route, spawn, evacuation counter or victory rule.
	for role in ["approach","retreat"]:
		var data: Dictionary = composition.get(role+"Presentation",{})
		if data.is_empty(): continue
		var points: Array = composition.get("route" if role=="approach" else "retreatTrail",[]).duplicate()
		if role=="retreat":
			for point in data.get("outerContinuation",{}).get("points",[]):
				if points.is_empty() or points[-1]!=point: points.append(point)
		var color := Color(str(data.get("color","#938574" if role=="approach" else "#899397")))
		var marker_anchors: Array = []
		for marker in data.get("directionMarkers",[]):
			var index: int = int(marker.get("segmentIndex",-1))
			if index<0 or index+1>=points.size():
				push_error("Invalid authored %s direction marker segment." % role)
				continue
			var a := Vector2(float(points[index][0]),float(points[index][1]))
			var b := Vector2(float(points[index+1][0]),float(points[index+1][1]))
			if a.distance_squared_to(b)<.000001: continue
			var center: Vector2 = a.lerp(b,clampf(float(marker.get("t",.5)),0.0,1.0))
			_add_direction_chevron(center,(b-a).normalized(),color)
			marker_anchors.append([center.x,center.y])
		var anchor: Array = data.get("labelWorldPosition",[])
		if anchor.size()!=2:
			push_error("Authored %s label requires WORLD XZ anchor." % role)
			continue
		var label := Label3D.new()
		label.name = "ApproachDirectionLabel" if role=="approach" else "WithdrawalDirectionLabel"
		label.text = str(data.get("label","적 접근" if role=="approach" else "철수 방향"))
		label.font = GameFonts.body()
		label.font_size = 32
		label.pixel_size = .01
		label.outline_size = 4
		label.modulate = Color("e2d2b8") if role=="approach" else Color("d6d3c8")
		label.outline_modulate = Color("283034")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = _ground(float(anchor[0]),float(anchor[1]))+Vector3.UP*float(data.get("labelHeightAboveFloorWorld",.20))
		label.layers = 1
		label.set_meta("presentation_only",true)
		add_child(label)
		direction_cues.append({"role":role,"label":label.text,"labelWorldPosition":[label.position.x,label.position.y,label.position.z],
			"labelWorldXz":anchor,"labelFontSize":32,"labelPixelSize":.01,"color":str(data.get("color","")),
			"pathPointCount":points.size(),"markerWorldXz":marker_anchors,"interactive":false})

func _add_direction_chevron(center: Vector2, direction: Vector2, color: Color) -> void:
	var side := Vector2(-direction.y,direction.x)
	var tip: Vector2 = center+direction*.16
	var inner_tip: Vector2 = center+direction*.085
	var left: Vector2 = center-direction*.09+side*.15
	var right: Vector2 = center-direction*.09-side*.15
	var inner_left: Vector2 = left-direction*.035-side*.035
	var inner_right: Vector2 = right-direction*.035+side*.035
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [tip,left,inner_left,tip,inner_left,inner_tip,tip,inner_tip,inner_right,tip,inner_right,right]:
		tool.add_vertex(_ground(point.x,point.y)+Vector3.UP*.026)
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.lightened(.12)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	tool.set_material(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "PresentationDirectionChevron"
	mesh.mesh = tool.commit()
	mesh.layers = 1
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("presentation_only",true)
	add_child(mesh)

func _build_scenery_stream() -> void:
	# A small learning landmark on the peripheral scenery only. The functional
	# floor remains dry, and the stream adds no body, pick surface or navigation.
	var data: Dictionary = composition.get("landscapeScenery",{}).get("stream",{})
	if data.is_empty() or not bool(data.get("sceneryOnly",false)) or bool(data.get("interactive",true)): return
	var points: Array = data.get("points",[])
	if points.size()<2: return
	_add_stream_ribbon(data,float(data.get("widthWorld",.4))+2.0*float(data.get("bankWidthWorld",0.0)),Color(str(data.get("bankColor","#6c736f"))),.010)
	_add_stream_ribbon(data,float(data.get("widthWorld",.4)),Color(str(data.get("color","#506d73"))),.022)

func _add_stream_ribbon(data: Dictionary, width: float, color: Color, lift: float) -> void:
	var points: Array = data.get("points",[])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size()-1):
		var a := Vector2(float(points[index][0]),float(points[index][1]))
		var b := Vector2(float(points[index+1][0]),float(points[index+1][1]))
		if a.distance_squared_to(b)<.000001: continue
		var side: Vector2 = Vector2(-(b-a).y,(b-a).x).normalized()*width*.5
		var divisions: int = maxi(1,ceili(a.distance_to(b)/.25))
		for step in range(divisions):
			var start: Vector2 = a.lerp(b,float(step)/divisions)
			var finish: Vector2 = a.lerp(b,float(step+1)/divisions)
			for point in [start-side,start+side,finish-side,start+side,finish+side,finish-side]:
				tool.add_vertex(_ground(point.x,point.y)+Vector3.UP*lift)
			stream_triangle_count += 2
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .72
	material.metallic_specular = .18
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(material)
	var mesh := MeshInstance3D.new()
	mesh.name = "PeripheralLearningStream"
	mesh.mesh = tool.commit()
	mesh.layers = 1
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("scenery_only",true)
	mesh.set_meta("authoritative_floor",false)
	add_child(mesh)

func _ground(x: float, z: float) -> Vector3:
	var point := Vector3(x,0,z)
	var height: float = provider.sample_world_height(point)
	# Only static art outside the canonical floor uses this separate backdrop.
	# Actors, picking, placement and navigation still use the FUNCTIONAL provider.
	if not is_finite(height): height = _scenery_height(Vector2(x,z))
	if not is_finite(height): scenery_height_failures += 1
	point.y = height if is_finite(height) else 0.0
	return point

func _scenery_height(point: Vector2) -> float:
	if scenery_vertices.is_empty() or not scenery_bounds.grow(.000001).has_point(point): return NAN
	for index in range(0,scenery_indices.size(),3):
		var a: Vector3 = scenery_vertices[scenery_indices[index]]
		var b: Vector3 = scenery_vertices[scenery_indices[index+1]]
		var c: Vector3 = scenery_vertices[scenery_indices[index+2]]
		var first := Vector2(b.x-a.x,b.z-a.z)
		var second := Vector2(c.x-a.x,c.z-a.z)
		var delta := point-Vector2(a.x,a.z)
		var denominator: float = first.cross(second)
		if absf(denominator)<.000000001: continue
		var u: float = delta.cross(second)/denominator
		var v: float = first.cross(delta)/denominator
		if u>=-.000001 and v>=-.000001 and u+v<=1.000001:
			return a.y*(1-u-v)+b.y*u+c.y*v
	return NAN

func _build_landscape_scenery() -> void:
	scenery_vertices.clear()
	scenery_indices.clear()
	scenery_mesh = null
	var data: Dictionary = composition.get("landscapeScenery",{})
	if data.is_empty() or bool(data.get("interactive",true)): return
	var bounds: Dictionary = data.bounds
	scenery_bounds = Rect2(float(bounds.x),float(bounds.z),float(bounds.width),float(bounds.depth))
	for value in data.vertices:
		scenery_vertices.append(Vector3(float(value.x),float(value.y),float(value.z)))
	for value in data.triangles: scenery_indices.append(int(value))
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	normals.resize(scenery_vertices.size())
	for index in range(0,scenery_indices.size(),3):
		var a: int = scenery_indices[index]
		var b: int = scenery_indices[index+1]
		var c: int = scenery_indices[index+2]
		# Godot front faces are clockwise, matching the authored provider surface.
		var normal: Vector3 = (scenery_vertices[c]-scenery_vertices[a]).cross(scenery_vertices[b]-scenery_vertices[a]).normalized()
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for index in range(normals.size()):
		normals[index] = normals[index].normalized()
		uv.append(Vector2(scenery_vertices[index].x,scenery_vertices[index].z))
	# Match the sole authoritative floor's actual edge shading as well as height.
	var floor_mesh: ArrayMesh = provider.surface_mesh()
	var floor_arrays: Array = floor_mesh.surface_get_arrays(0)
	var floor_vertices: PackedVector3Array = floor_arrays[Mesh.ARRAY_VERTEX]
	var floor_normals: PackedVector3Array = floor_arrays[Mesh.ARRAY_NORMAL]
	var edge_normals: Dictionary = {}
	for index in range(floor_vertices.size()):
		edge_normals[floor_vertices[index]] = floor_normals[index]
	for index in range(int(data.get("boundaryVertexCount",data.get("innerBoundaryVertexCount",0)))):
		if edge_normals.has(scenery_vertices[index]): normals[index] = edge_normals[scenery_vertices[index]]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = scenery_vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = scenery_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var shading := SurfaceTool.new()
	shading.create_from(mesh,0)
	shading.generate_tangents()
	scenery_mesh = MeshInstance3D.new()
	scenery_mesh.name = "PeripheralLandscapeScenery"
	scenery_mesh.mesh = shading.commit()
	scenery_mesh.material_override = SurfaceMaterials.ground(composition)
	scenery_mesh.layers = 1
	if composition.has("artCoherence"):
		scenery_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery_mesh.set_meta("scenery_only",true)
	scenery_mesh.set_meta("authoritative_floor",false)
	# Intentionally no body, collision shape, provider registration or game anchor.
	add_child(scenery_mesh)

func _emit_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	tool.set_uv(uva)
	tool.add_vertex(a)
	tool.set_uv(uvb)
	tool.add_vertex(b)
	tool.set_uv(uvc)
	tool.add_vertex(c)

func _log_mesh(height: float, radius: float, variant: int, tip_depth: float = .15) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int = 12
	var shoulder: float = height-minf(tip_depth,height*.45)
	for i in range(sides):
		var angle_a: float = TAU*float(i)/sides
		var angle_b: float = TAU*float(i+1)/sides
		var radial_a: float = radius*(1.0+0.035*sin(float(i*3+variant)))
		var radial_b: float = radius*(1.0+0.035*sin(float((i+1)*3+variant)))
		var a := Vector3(cos(angle_a)*radial_a,0,sin(angle_a)*radial_a)
		var b := Vector3(cos(angle_b)*radial_b,0,sin(angle_b)*radial_b)
		var c := a+Vector3.UP*shoulder
		var d := b+Vector3.UP*shoulder
		var v_a: float = 0.02+float(i)/sides*0.15+variant*0.18
		var v_b: float = 0.02+float(i+1)/sides*0.15+variant*0.18
		_emit_triangle(tool,a,b,c,Vector2(0,v_a),Vector2(0,v_b),Vector2(shoulder/1.8,v_a))
		_emit_triangle(tool,b,d,c,Vector2(0,v_b),Vector2(shoulder/1.8,v_b),Vector2(shoulder/1.8,v_a))
		var tip := Vector3(radius*0.08,height,radius*0.07)
		_emit_triangle(tool,c,d,tip,Vector2(shoulder/1.8,v_a),Vector2(shoulder/1.8,v_b),Vector2(height/1.8,(v_a+v_b)*0.5))
		_emit_triangle(tool,b,a,Vector3.ZERO,Vector2(0,v_b),Vector2(0,v_a),Vector2(radius/1.8,(v_a+v_b)*0.5))
	tool.index()
	tool.generate_normals()
	tool.generate_tangents()
	tool.set_material(SurfaceMaterials.scan("timber"))
	return tool.commit()

func _build_palisades() -> void:
	var transforms: Array = [[],[],[]]
	for fence in composition.get("fences",[]):
		if _pilot_fence(fence): continue
		var a := Vector2(float(fence.a[0]),float(fence.a[1]))
		var b := Vector2(float(fence.b[0]),float(fence.b[1]))
		var spacing: float=.135 if bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)) else .16
		var count: int = maxi(2,ceili(a.distance_to(b)/spacing))
		var direction: Vector2 = (b-a).normalized()
		var normal := Vector2(-direction.y,direction.x)
		for i in range(count+1):
			var t: float = float(i)/count
			var p: Vector2 = a.lerp(b,t)+normal*0.012*sin(float(i)*1.7)
			var group: int = (i+str(fence.id).length())%3
			var angle: float = 0.014*sin(float(i)*2.13)
			var basis := Basis(Vector3.FORWARD,angle)
			var height_scale: float = float(fence.height)/1.3*(0.97+0.04*sin(float(i)*2.7))
			basis = basis.scaled(Vector3(1,height_scale,1))
			transforms[group].append(Transform3D(basis,_ground(p.x,p.y)-Vector3(0,.035,0)))
			picket_count += 1
		# Interior rails and braces are real timber, with a passable gate gap.
		for height in [float(fence.height)*.28,float(fence.height)*.70]:
			var start: Vector3 = _ground(a.x,a.y)+Vector3(0,height,0)
			var finish: Vector3 = _ground(b.x,b.y)+Vector3(0,height,0)
			_add_beam(start,finish,0.045)
		for i in range(0,count,10):
			var p: Vector2 = a.lerp(b,float(i)/count)
			var foot: Vector3 = _ground(p.x-normal.x*.31,p.y-normal.y*.31)
			var top: Vector3 = _ground(p.x,p.y)+Vector3(0,float(fence.height)*.56,0)
			_add_beam(foot,top,0.040)
	for group in range(3):
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _log_mesh(1.3+group*.035,0.069+group*.003,group)
		multi.instance_count = transforms[group].size()
		for i in range(multi.instance_count): multi.set_instance_transform(i,transforms[group][i])
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = multi
		batch.layers = 1
		add_child(batch)
		static_instance_groups += 1

func _build_earthwork_pickets() -> void:
	# The mound is already in the sole provider mesh. Only the authored, blocked
	# timber segments are added here; there is no second raised placement floor.
	for area in composition.get("deploymentAreas",[]):
		var earthwork: Dictionary = area.get("earthworkPresentation",{})
		if str(earthwork.get("kind",""))!="low-earthen-picket-pad": continue
		var height: float = float(earthwork.get("picketHeightWorld",.48))
		var radius: float = float(earthwork.get("picketRadiusWorld",.04))
		var transforms: Array = []
		var posts: Array = earthwork.get("picketPosts",[])
		for post in posts:
			var center: Array = post.center
			var post_height: float = float(post.get("heightWorld",height))
			var basis := Basis.IDENTITY.scaled(Vector3(1,post_height/height,1))
			transforms.append(Transform3D(basis,_ground(float(center[0]),float(center[1]))-Vector3.UP*.01))
			earthwork_picket_count += 1
		for segment in earthwork.get("picketSegments",[]):
			var a := Vector2(float(segment.a[0]),float(segment.a[1]))
			var b := Vector2(float(segment.b[0]),float(segment.b[1]))
			var count: int = maxi(2,ceili(a.distance_to(b)/.125))
			for index in range(count+1):
				var p: Vector2 = a.lerp(b,float(index)/count)
				var basis := Basis.IDENTITY.scaled(Vector3(1,.96+.06*sin(index*1.7),1))
				transforms.append(Transform3D(basis,_ground(p.x,p.y)-Vector3.UP*.015))
				earthwork_picket_count += 1
			for rail_height in [height*.35,height*.72]:
				_add_beam(_ground(a.x,a.y)+Vector3.UP*rail_height,_ground(b.x,b.y)+Vector3.UP*rail_height,radius*.55)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _log_mesh(height,radius,0,float(earthwork.get("picketTipDepthWorld",.15)))
		multi.instance_count = transforms.size()
		for index in range(transforms.size()): multi.set_instance_transform(index,transforms[index])
		var batch := MultiMeshInstance3D.new()
		batch.name = str(area.get("id","Earthwork"))+"Pickets"
		batch.multimesh = multi
		batch.layers = 1
		batch.set_meta("provider_owns_pad_floor",true)
		batch.set_meta("individual_source_stakes",not posts.is_empty())
		add_child(batch)
		static_instance_groups += 1

func _add_beam(a: Vector3, b: Vector3, radius: float) -> void:
	var vector: Vector3 = b-a
	var length: float = vector.length()
	if length<0.001: return
	var mesh := CylinderMesh.new()
	mesh.height = length
	mesh.top_radius = radius*0.94
	mesh.bottom_radius = radius
	mesh.radial_segments = 10
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = SurfaceMaterials.scan("timber")
	instance.position = (a+b)*0.5
	instance.quaternion = Quaternion(Vector3.UP,vector/length)
	instance.layers = 1
	add_child(instance)
	prop_count += 1

func _add_box(center: Vector3, dimensions: Vector3, angle: float = 0.0) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = dimensions
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = SurfaceMaterials.scan("timber")
	mesh.position = center
	mesh.rotation.y = angle
	mesh.layers = 1
	add_child(mesh)
	prop_count += 1
	return mesh

func _build_gate() -> void:
	var gate: Dictionary = composition.get("gate",{})
	var center: Array = gate.get("center",[-3.4,.95])
	var width: float = float(gate.get("width",1.64))
	var height: float = float(gate.get("clearHeight",1.62))
	var jambs: Array = gate.get("jambCenters",[[float(center[0])-width*.5,float(center[1])],[float(center[0])+width*.5,float(center[1])]])
	var left: Vector3 = _ground(float(jambs[0][0]),float(jambs[0][1]))
	var right: Vector3 = _ground(float(jambs[1][0]),float(jambs[1][1]))
	var gate_angle: float = deg_to_rad(float(gate.get("rotationDegrees",0)))
	_add_beam(left-Vector3(0,.025,0),left+Vector3(0,height+.18,0),.105)
	_add_beam(right-Vector3(0,.025,0),right+Vector3(0,height+.18,0),.105)
	_add_box((left+right)*.5+Vector3(0,height+.10,0),Vector3(width+.32,.18,.20),gate_angle)
	for post in [left,right]: _add_gate_torch(post+Vector3.UP*.49)
	if gate.has("leaves"):
		for entry in gate.leaves:
			var leaf_center: Array = entry.center
			var leaf_height: float = float(entry.height)
			var leaf: MeshInstance3D = _add_box(_ground(float(leaf_center[0]),float(leaf_center[1]))+Vector3.UP*leaf_height*.5,Vector3(float(entry.width),leaf_height,float(entry.depth)),deg_to_rad(float(entry.rotationDegrees)))
			leaf.set_meta("occupancy_proxy",str(entry.occupancyProxy))
		for post in [left,right]:
			_add_rope_tie(post+Vector3.UP*.39,.105)
			_add_rope_tie(post+Vector3.UP*.94,.105)
		return
	# Open gate leaves rest at the side, never painted across the walkable opening.
	for sign_value in [-1,1]:
		var post: Vector3 = left if sign_value==-1 else right
		var offset: Vector3 = Vector3(sign_value*.21,.68,-.38)
		var leaf: MeshInstance3D = _add_box(post+offset,Vector3(.68,1.25,.06),sign_value*deg_to_rad(72))
		leaf.set_meta("role","open_visual_gate_leaf")
		for tie_height in [.42,1.25]:
			var ring := TorusMesh.new()
			ring.inner_radius = .09
			ring.outer_radius = .111
			ring.rings = 12
			ring.ring_segments = 6
			var mesh := MeshInstance3D.new()
			mesh.mesh = ring
			mesh.material_override = SurfaceMaterials.rope()
			mesh.position = post+Vector3(0,tie_height,0)
			add_child(mesh)
			prop_count += 1

func _add_gate_torch(center: Vector3) -> void:
	# Two small lights at the same authored gate jambs; no crew or game effects.
	_add_beam(center-Vector3.UP*.21,center,.018)
	var bowl := SphereMesh.new()
	bowl.radius = .053
	bowl.height = .065
	var holder := MeshInstance3D.new()
	holder.mesh = bowl
	holder.material_override = SurfaceMaterials.metal()
	holder.position = center
	holder.layers = 1
	add_child(holder)
	var flame := SphereMesh.new()
	flame.radius = .038
	flame.height = .14
	flame.radial_segments = 8
	flame.rings = 4
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("f6b35b")
	if bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)):
		glow.emission_enabled=true
		glow.emission=Color("edb276")
		glow.emission_energy_multiplier=2.1
	var fire := MeshInstance3D.new()
	fire.mesh = flame
	fire.material_override = glow
	fire.position = center+Vector3.UP*.065
	fire.layers = 1
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire)
	var light := OmniLight3D.new()
	light.position = fire.position
	light.light_color = Color("edb276")
	light.light_energy = .45
	light.omni_range = .85
	light.shadow_enabled = bool(composition.get("mapCameraArt",{}).get("volumetricForest",false))
	light.light_cull_mask = 3 if bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)) else 1
	add_child(light)
	prop_count += 2

func _build_shelter() -> void:
	var value: Dictionary = composition.get("shelter",{})
	var center: Array = value.get("center",[-4.95,-2.85])
	var p: Vector3 = _ground(float(center[0]),float(center[1]))
	var width: float = float(value.get("width",1.75))
	var depth: float = float(value.get("depth",1.3))
	var height_scale: float = float(value.get("heightScale",1.0))
	for x_sign in [-1,1]:
		for z_sign in [-1,1]:
			var bottom: Vector3 = _ground(p.x+x_sign*width*.46,p.z+z_sign*depth*.45)
			_add_beam(bottom,bottom+Vector3.UP*(1.12 if z_sign==1 else 1.49)*height_scale,.046)
	# Individual weathered boards, thin overlap and genuine edge shadows.
	for i in range(13):
		var board: MeshInstance3D = _add_box(p+Vector3(-width*.5+(i+.5)*width/13,1.37*height_scale,0),Vector3(width/13+.012,.045,depth+.24))
		board.rotation.x = deg_to_rad(15.7)
	for i in range(9):
		_add_box(p+Vector3(-width*.43+i*width*.108,.71*height_scale,-depth*.43),Vector3(width*.106,1.36*height_scale,.055))
	_add_box(p+Vector3(0,.18,-.21),Vector3(.71,.34,.37))
	_add_box(p+Vector3(.46,.15,.12),Vector3(.33,.29,.38),.17)

func _model_bounds(node: Node, inherited: Transform3D = Transform3D.IDENTITY) -> AABB:
	var transform: Transform3D = inherited
	if node is Node3D: transform = inherited*node.transform
	var bounds := AABB()
	var found: bool = false
	if node is MeshInstance3D and node.mesh!=null:
		bounds = transform*node.get_aabb()
		found = true
	for child in node.get_children():
		var child_bounds: AABB = _model_bounds(child,transform)
		if child_bounds.size.length_squared()>0:
			bounds = bounds.merge(child_bounds) if found else child_bounds
			found = true
	return bounds

func _add_scanned(path: String, p: Vector3, target_size: float, angle: float, use_height: bool) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed==null: return
	var model: Node3D = packed.instantiate() as Node3D
	if path.contains("grass_medium"):
		_tint_dry_grass(model)
	var bounds: AABB = _model_bounds(model)
	var dimension: float = bounds.size.y if use_height else maxf(bounds.size.x,bounds.size.z)
	var scale_value: float = target_size/maxf(.01,dimension)
	var wrapper := Node3D.new()
	wrapper.position = p
	wrapper.rotation.y = angle
	add_child(wrapper)
	wrapper.add_child(model)
	model.scale *= scale_value
	model.position -= Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*scale_value
	prop_count += 1

func _tint_dry_grass(node: Node) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		for index in range(node.mesh.get_surface_count()):
			var source: BaseMaterial3D = node.get_active_material(index) as BaseMaterial3D
			if source==null: continue
			var material: BaseMaterial3D = source.duplicate() as BaseMaterial3D
			material.albedo_color *= Color(.93,.80,.58)
			material.roughness = maxf(.85,material.roughness)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			node.set_surface_override_material(index,material)
	for child in node.get_children():
		_tint_dry_grass(child)

func _build_scanned_props() -> void:
	if str(composition.get("renderStyle","")) == "compact-smooth-v2":
		_build_scanned_batches()
		return
	for stone in composition.get("rocks",[]):
		_add_scanned(MODEL_ROOT+"boulder_01/boulder_01_1k.gltf",_ground(float(stone.x),float(stone.z))-Vector3(0,.035,0),float(stone.scale),deg_to_rad(float(stone.rotationDegrees)),false)
	for tree in composition.get("trees",[]):
		_add_scanned(MODEL_ROOT+"pine_sapling_small/pine_sapling_small_1k.gltf",_ground(float(tree.x),float(tree.z)),float(tree.scale)*2.9,0.37*float(prop_count%9),true)
	for bush in composition.get("bushes",[]):
		_add_scanned(MODEL_ROOT+"shrub_01/shrub_01_1k.gltf",_ground(float(bush.x),float(bush.z)),float(bush.scale),0.63*float(prop_count%7),false)
	for grass in composition.get("grasses",[]):
		_add_scanned(MODEL_ROOT+"grass_medium_01/grass_medium_01_1k.gltf",_ground(float(grass.x),float(grass.z)),float(grass.scale),0.39*float(prop_count%7),false)

func _build_loose_timber() -> void:
	if composition.has("looseTimber"):
		for entry in composition.looseTimber:
			var a: Vector3 = _ground(float(entry.a[0]),float(entry.a[1]))+Vector3.UP*float(entry.radius)
			var b: Vector3 = _ground(float(entry.b[0]),float(entry.b[1]))+Vector3.UP*float(entry.radius)
			_add_beam(a,b,float(entry.radius))
		return
	for entry in [[-5.8,1.6,-5.05,1.88],[-.25,-2.7,.62,-2.53],[.05,-2.8,.81,-2.77]]:
		var a: Vector3 = _ground(float(entry[0]),float(entry[1]))+Vector3(0,.067,0)
		var b: Vector3 = _ground(float(entry[2]),float(entry[3]))+Vector3(0,.067,0)
		_add_beam(a,b,.055)

func _add_rope_tie(center: Vector3, radius: float) -> void:
	var ring:=TorusMesh.new()
	ring.inner_radius=radius
	ring.outer_radius=radius+.018
	ring.rings=12
	ring.ring_segments=6
	var mesh:=MeshInstance3D.new()
	mesh.mesh=ring
	mesh.material_override=SurfaceMaterials.rope()
	mesh.position=center
	add_child(mesh)
	prop_count+=1

func _mesh_parts(node: Node, inherited: Transform3D, parts: Array) -> void:
	var transform: Transform3D=inherited
	if node is Node3D: transform=inherited*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		parts.append({"node":node,"transform":transform})
	for child in node.get_children(): _mesh_parts(child,transform,parts)

func _tactical_scan_mesh(node: MeshInstance3D, budget: int, family: String) -> ArrayMesh:
	var result:=ArrayMesh.new()
	var evidence: Array = []
	for index in range(node.mesh.get_surface_count()):
		var source_material: BaseMaterial3D = node.get_active_material(index) as BaseMaterial3D
		# This scan's twig atlas is bare branches and pine cones. Keep its actual
		# bark/trunk surfaces and author foliage separately instead of inflating a
		# bare-twig LOD budget or misrepresenting it as a leafy tree.
		if family=="trunk" and (source_material==null or not source_material.resource_name.to_lower().contains("bark")): continue
		var arrays: Array=node.mesh.surface_get_arrays(index)
		var source_indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		# Reduce static scan detail once per template, preserving vertex attributes.
		# No actor mesh, authored floor, collision or navigation is simplified here.
		var lod_count: int = 0
		var selected_lod: int = -1
		if source_indices.size()>budget*3:
			var importer := ImporterMesh.new()
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
			importer.generate_lods(60.0,25.0,[])
			lod_count = importer.get_surface_lod_count(0)
			var reduced: PackedInt32Array = source_indices
			# Choose the fullest generated LOD inside budget; otherwise retain the
			# smallest real result and expose its over-budget count in diagnostics.
			for lod in range(lod_count):
				var candidate: PackedInt32Array = importer.get_surface_lod_indices(0,lod)
				if candidate.size()<3 or candidate.size()>=source_indices.size(): continue
				var candidate_fits: bool = candidate.size()<=budget*3
				var chosen_fits: bool = selected_lod>=0 and reduced.size()<=budget*3
				if (candidate_fits and (not chosen_fits or candidate.size()>reduced.size())) or (not candidate_fits and not chosen_fits and candidate.size()<reduced.size()):
					reduced = candidate
					selected_lod = lod
			if selected_lod>=0:
				# LOD indices address the importer's resulting attribute arrays.
				arrays = importer.get_surface_arrays(0)
				arrays[Mesh.ARRAY_INDEX] = reduced
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material: BaseMaterial3D=node.get_active_material(index) as BaseMaterial3D
		if material!=null:
			result.surface_set_material(result.get_surface_count()-1,SurfaceMaterials.presentation_scan(material,"foliage" if family=="trunk" else family))
		var selected_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		evidence.append({"surface":index,"sourceTriangles":int(source_indices.size()/3),"selectedTriangles":int(selected_indices.size()/3),"triangleBudget":budget,"generatedLodCount":lod_count,"selectedLod":selected_lod,"withinBudget":selected_indices.size()<=budget*3})
	result.set_meta("tactical_lod_evidence",evidence)
	return result

func _scan_template(path: String, variant: int, budget: int) -> Dictionary:
	var key: String=path+":"+str(variant)+":"+str(budget)
	if scan_templates.has(key): return scan_templates[key]
	var packed: PackedScene=load(path) as PackedScene
	if packed==null: return {}
	var model: Node3D=packed.instantiate() as Node3D
	var parts: Array=[]
	_mesh_parts(model,Transform3D.IDENTITY,parts)
	if parts.is_empty():
		model.free()
		return {}
	# These GLTF sources contain several separate scan variants, not one plant.
	# Select a single actual variant per instance instead of rendering the whole kit.
	var choice: int=variant%parts.size()
	if path.contains("grass_medium"):
		choice=[0,3,5][variant%3]%parts.size()
	var part: Dictionary=parts[choice]
	var node: MeshInstance3D=part.node
	var family: String = "stone" if path.contains("boulder") else "grass" if path.contains("grass_medium") else "trunk" if path.contains("pine_sapling_small") else "foliage"
	var mesh: ArrayMesh=_tactical_scan_mesh(node,budget,family)
	var bounds: AABB=part.transform*mesh.get_aabb()
	var template: Dictionary={"mesh":mesh,"transform":part.transform,"bounds":bounds}
	scan_templates[key]=template
	model.free()
	return template

func _batch_scans(entries: Array, path: String, height_factor: float, budget: int, variants: int) -> void:
	for variant in range(variants):
		var template: Dictionary=_scan_template(path,variant,budget)
		if template.is_empty(): continue
		var transforms: Array=[]
		var bounds: AABB=template.bounds
		var offset:=Transform3D(Basis.IDENTITY,-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z))
		for index in range(entries.size()):
			if index%variants!=variant: continue
			var entry: Dictionary=entries[index]
			var target: float=float(entry.scale)*height_factor if height_factor>0 else float(entry.scale)
			var dimension: float=bounds.size.y if height_factor>0 else maxf(bounds.size.x,bounds.size.z)
			var scale_value: float=target/maxf(.01,dimension)
			if bool(entry.get("sceneryOnly",false)):
				var half_diagonal: float = Vector2(bounds.size.x,bounds.size.z).length()*.5
				scale_value = minf(scale_value,float(entry.maxPlanarRadiusWorld)/maxf(.01,half_diagonal))
			var angle: float=deg_to_rad(float(entry.get("rotationDegrees",index*43%360)))
			var basis:=Basis(Vector3.UP,angle).scaled(Vector3.ONE*scale_value)
			var position: Vector3=_ground(float(entry.x),float(entry.z))
			# Source-authored bank toe stones sit into the SAME floor, without a second support plane.
			position.y-=clampf(float(entry.get("groundEmbedWorld",0.0)),0.0,target*.25)
			transforms.append(Transform3D(basis,position)*offset*template.transform)
			prop_count+=1
		if transforms.is_empty(): continue
		var multi:=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=template.mesh
		multi.instance_count=transforms.size()
		for index in range(transforms.size()): multi.set_instance_transform(index,transforms[index])
		var batch:=MultiMeshInstance3D.new()
		batch.multimesh=multi
		batch.layers=1
		batch.set_meta("scenery_only",bool(entries[0].get("sceneryOnly",false)))
		add_child(batch)
		static_instance_groups+=1
		for surface in range(multi.mesh.get_surface_count()):
			var indices: PackedInt32Array=multi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			static_triangles+=int(indices.size()/3)*transforms.size()

func _build_scanned_batches() -> void:
	_batch_scans(composition.get("rocks",[]),MODEL_ROOT+"boulder_01/boulder_01_1k.gltf",0,3000,1)
	if bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)):
		var all_trees: Array=composition.get("trees",[]).duplicate()
		var all_bushes: Array=composition.get("bushes",[]).duplicate()
		var backdrop: Dictionary=composition.get("landscapeScenery",{})
		all_trees.append_array(backdrop.get("trees",[]))
		all_bushes.append_array(backdrop.get("bushes",[]))
		for plant in backdrop.get("props",[]):
			if str(plant.get("kind",""))=="tree": all_trees.append(plant)
			elif str(plant.get("kind",""))=="bush": all_bushes.append(plant)
		all_bushes.append_array(composition.get("mapCameraArt",{}).get("understoryBridges",[]))
		_build_volume_forest(all_trees,all_bushes)
		_build_volume_pad_rails()
		return
	_batch_scans(composition.get("trees",[]),MODEL_ROOT+"pine_sapling_small/pine_sapling_small_1k.gltf",1.48,700,3)
	_build_leafy_crowns(composition.get("trees",[]))
	_build_grouped_understory(composition.get("bushes",[]))
	# Short grass stays in the real broad ground material, without isolated blade meshes.
	var scenery: Dictionary = composition.get("landscapeScenery",{})
	var trees: Array = scenery.get("trees",[]).duplicate()
	var bushes: Array = scenery.get("bushes",[]).duplicate()
	for entry in scenery.get("props",[]):
		if str(entry.get("kind",""))=="tree": trees.append(entry)
		elif str(entry.get("kind",""))=="bush": bushes.append(entry)
	_batch_scans(trees,MODEL_ROOT+"pine_sapling_small/pine_sapling_small_1k.gltf",1.48,700,3)
	_build_leafy_crowns(trees)
	_build_grouped_understory(bushes)

func _leaf_cluster(tool: SurfaceTool, center: Vector3, half_width: float, half_height: float, phase: float, color: Color, understory: bool = false, mirror: bool = false) -> void:
	# Independent leaf-cutout planes occupy true3D centers with varying tilt/yaw/roll.
	var pitch: float=deg_to_rad(float(composition.get("camera",{}).get("elevationDegrees",44)))+sin(phase*1.37)*.20
	var yaw: float=sin(phase*.91)*.38
	var normal:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	var right:=Vector3(cos(yaw),0,-sin(yaw))
	var up: Vector3=normal.cross(right).normalized()
	var roll: float=sin(phase*1.71)*.17
	var rolled_right: Vector3=right*cos(roll)+up*sin(roll)
	var rolled_up: Vector3=up*cos(roll)-right*sin(roll)
	# Clockwise frontfaces agree with authored normals;avoid backface normal inversion.
	for point in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		var uv_x: float=(point.x+1.0)*.5
		tool.set_uv(Vector2(1.0-uv_x if mirror else uv_x,(1.0-point.y)*.5))
		tool.set_normal(normal)
		tool.set_color(color)
		tool.add_vertex(center+rolled_right*point.x*half_width+rolled_up*point.y*half_height)
	if understory: understory_triangle_count+=2
	else: canopy_triangle_count+=2
	if not understory:
		volume_leaf_triangles+=2
		crown_sprite_count+=1

func _volume_branch(tool: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float) -> void:
	var direction: Vector3=b-a
	if direction.length_squared()<.000001: return
	var axis: Basis=Basis(Quaternion(Vector3.UP,direction.normalized()))
	for side in range(7):
		var aa: float=TAU*float(side)/7.0
		var ab: float=TAU*float(side+1)/7.0
		var ra: Vector3=axis*Vector3(cos(aa),0,sin(aa))
		var rb: Vector3=axis*Vector3(cos(ab),0,sin(ab))
		var p: Vector3=a+ra*radius_a
		var q: Vector3=a+rb*radius_a
		var r: Vector3=b+ra*radius_b
		var s: Vector3=b+rb*radius_b
		_emit_triangle(tool,p,q,r,Vector2(float(side)/7,0),Vector2(float(side+1)/7,0),Vector2(float(side)/7,direction.length()/1.3))
		_emit_triangle(tool,q,s,r,Vector2(float(side+1)/7,0),Vector2(float(side+1)/7,direction.length()/1.3),Vector2(float(side)/7,direction.length()/1.3))
		_emit_triangle(tool,r,s,b,Vector2(0,0),Vector2(1,0),Vector2(.5,1))
		volume_wood_triangles+=3

func _volume_batch(tool: SurfaceTool, material: Material, label: String, wood: bool = false) -> void:
	tool.index()
	if wood: tool.generate_normals(); tool.generate_tangents()
	tool.set_material(material)
	var batch:=MeshInstance3D.new()
	batch.name=label
	batch.mesh=tool.commit()
	batch.layers=1
	batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	batch.set_meta("presentation_only",true)
	batch.set_meta("physical_blockers_unchanged",true)
	add_child(batch)
	static_instance_groups+=1

func _woodland_crown_point(center: Vector3, right: Vector3, up: Vector3, normal: Vector3, half_width: float, half_height: float, bulge: float, skew: float, point: Vector2) -> Vector3:
	# One whole crown texture spans this curved surface;it is not a tiny repeated leaf.
	var spread: float=point.x*(1.0+.12*point.y)+skew*point.y
	var depth: float=bulge*(1.0-point.x*point.x)*(1.0-point.y*point.y)
	return center+right*spread*half_width+up*point.y*half_height+normal*depth

func _woodland_crown(tool: SurfaceTool, center: Vector3, half_width: float, half_height: float, bulge: float, skew: float, yaw: float, roll: float, color: Color, mirror: bool, understory: bool = false) -> void:
	var pitch: float=deg_to_rad(float(composition.get("camera",{}).get("elevationDegrees",44)))
	var normal:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	var horizontal:=Vector3(cos(yaw),0,-sin(yaw))
	var vertical: Vector3=normal.cross(horizontal).normalized()
	var right: Vector3=horizontal*cos(roll)+vertical*sin(roll)
	var up: Vector3=vertical*cos(roll)-horizontal*sin(roll)
	var columns: int=8
	var rows: int=6
	for row in range(rows):
		for column in range(columns):
			var x0: float=-1.0+2.0*float(column)/float(columns)
			var x1: float=-1.0+2.0*float(column+1)/float(columns)
			var y0: float=-1.0+2.0*float(row)/float(rows)
			var y1: float=-1.0+2.0*float(row+1)/float(rows)
			# Clockwise front faces;normals follow the real shallow crown curvature.
			for point in [Vector2(x0,y0),Vector2(x0,y1),Vector2(x1,y0),Vector2(x1,y0),Vector2(x0,y1),Vector2(x1,y1)]:
				var tangent_x: Vector3=right*half_width*(1.0+.12*point.y)-normal*(2.0*bulge*point.x*(1.0-point.y*point.y))
				var tangent_y: Vector3=right*half_width*(.12*point.x+skew)+up*half_height-normal*(2.0*bulge*point.y*(1.0-point.x*point.x))
				var uv_x: float=(point.x+1.0)*.5
				tool.set_uv(Vector2(1.0-uv_x if mirror else uv_x,(1.0-point.y)*.5))
				tool.set_normal(tangent_x.cross(tangent_y).normalized())
				tool.set_color(color)
				tool.add_vertex(_woodland_crown_point(center,right,up,normal,half_width,half_height,bulge,skew,point))
	var triangles: int=columns*rows*2
	if understory:
		understory_triangle_count+=triangles
	else:
		canopy_triangle_count+=triangles
		volume_leaf_triangles+=triangles
		crown_sprite_count+=1

func _woodland_tree(leaf: SurfaceTool, wood: SurfaceTool, tree: Dictionary, profile: Dictionary, index: int) -> void:
	var origin: Vector3=_ground(float(tree.x),float(tree.z))
	var total: float=float(tree.get("treeHeightWorld",2.0))*float(profile.heightFactor)
	var width: float=float(profile.halfWidthWorld)
	var trunk_radius: float=float(tree.get("trunkRadius",.12))*.82
	var phase: float=float(index)*1.713
	var fork: Vector3=origin+Vector3(sin(phase)*.045,total*.29,cos(phase)*.035)
	var stem: Vector3=origin+Vector3(sin(phase)*.07,total*.58,cos(phase)*.05)
	var left: Vector3=origin+Vector3(-width*.62,total*.60,-width*.08)
	var right: Vector3=origin+Vector3(width*.54,total*.68,width*.06)
	# Unequal structural forks replace the five equal radial spokes;roots stay exact.
	_volume_branch(wood,origin-Vector3.UP*.025,fork,trunk_radius,trunk_radius*.67)
	_volume_branch(wood,fork,stem,trunk_radius*.67,trunk_radius*.30)
	_volume_branch(wood,fork,left,trunk_radius*.40,trunk_radius*.10)
	_volume_branch(wood,fork,right,trunk_radius*.44,trunk_radius*.11)
	_volume_branch(wood,stem,origin+Vector3(width*.06,total*.87,-width*.22),trunk_radius*.24,trunk_radius*.06)
	_volume_branch(wood,left,origin+Vector3(-width*.80,total*.73,-width*.10),trunk_radius*.10,trunk_radius*.035)
	_volume_branch(wood,right,origin+Vector3(width*.72,total*.84,width*.05),trunk_radius*.11,trunk_radius*.035)
	var shade: float=.91+.055*sin(phase)
	var color:=Color(shade*.96,shade,shade*.92,1.0)
	var crown_offset: float=float(composition.get("mapCameraArt",{}).get("crownOffsetZ",{}).get(str(tree.get("id","")),0.0))
	_woodland_crown(leaf,origin+Vector3(0,total*.65,crown_offset),width,total*.47,float(profile.bulgeWorld),float(profile.skew),deg_to_rad(float(profile.yawDegrees)),deg_to_rad(float(profile.rollDegrees)),color,bool(profile.mirror))

func _build_volume_forest(trees: Array, bushes: Array) -> void:
	var leaf:=SurfaceTool.new(); leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood:=SurfaceTool.new(); wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown_factors: Dictionary=composition.get("mapCameraArt",{}).get("crownRadiusFactors",{})
	var crown_offsets: Dictionary=composition.get("mapCameraArt",{}).get("crownOffsetZ",{})
	var art: Dictionary=composition.get("artCoherence",{})
	var shapes: Array=art.get("foliageShapes",[])
	var tree_heights: Dictionary=art.get("treeHeightFactors",{})
	var representative: Dictionary=art.get("woodlandRepresentative",{})
	var representative_trees: Dictionary=representative.get("trees",{})
	var representative_bushes: Dictionary=representative.get("bushes",{})
	if shapes.is_empty():
		push_error("Authored forest shape variants are missing.")
		return
	for index in range(trees.size()):
		var tree: Dictionary=trees[index]
		var tree_id: String=str(tree.get("id",""))
		if _pilot_vegetation(tree,true): continue
		if representative_trees.has(tree_id):
			_woodland_tree(leaf,wood,tree,representative_trees[tree_id],index)
			canopy_tree_count+=1
			prop_count+=1
			continue
		var origin: Vector3=_ground(float(tree.x),float(tree.z))
		var radius: float=maxf(.12,float(tree.get("canopyRadiusWorld",.7)))
		radius*=clampf(float(crown_factors.get(str(tree.get("id","")),1.0)),.35,1.0)
		var variant: int=index%shapes.size()
		var shape: Dictionary=shapes[variant]
		var total: float=float(tree.get("treeHeightWorld",2.0))*float(shape.get("heightFactor",1.0))*clampf(float(tree_heights.get(str(tree.get("id","")),1.0)),.25,1.0)
		var phase: float=float(index)*1.713
		var crown_offset: float=float(crown_offsets.get(str(tree.get("id","")),0.0))
		var trunk_height: float=total*.57
		var trunk_radius: float=minf(float(tree.get("trunkRadius",.12))*.82,radius*.22)
		var fork: Vector3=origin+Vector3(sin(phase)*.045,trunk_height*.67,cos(phase)*.035)
		_volume_branch(wood,origin-Vector3.UP*.025,fork,trunk_radius,trunk_radius*.67)
		_volume_branch(wood,fork,origin+Vector3.UP*trunk_height,trunk_radius*.67,trunk_radius*.30)
		for branch in range(5):
			var angle: float=phase+TAU*float(branch)/5.0
			var end: Vector3=origin+Vector3(cos(angle)*radius*.49,trunk_height+total*.08,sin(angle)*radius*.49)
			_volume_branch(wood,fork,end,trunk_radius*.40,trunk_radius*.08)
		var clusters: Array=shape.get("clusters",[])
		for lobe in range(clusters.size()):
			var cluster: Array=clusters[lobe]
			var local_x: float=float(cluster[0])*radius
			var local_z: float=float(cluster[2])*radius
			var offset:=Vector3(local_x*cos(phase)-local_z*sin(phase),0,local_x*sin(phase)+local_z*cos(phase)+crown_offset)
			var center: Vector3=origin+offset+Vector3.UP*(total*float(cluster[1]))
			var half_width: float=radius*float(cluster[3])
			var half_height: float=minf(total*float(cluster[4]),radius*.67)
			var shade: float=.91+.055*sin(phase+lobe*2.17)
			var color:=Color(shade*.96,shade,shade*.92,1.0)
			_leaf_cluster(leaf,center,half_width,half_height,phase+lobe*.83,color,false,(index+lobe)%2==0)
		canopy_tree_count+=1
		prop_count+=1
	if not trees.is_empty():
		_volume_batch(leaf,SurfaceMaterials.volume_foliage(),"BatchedFiveVariantAlphaLeafCrowns")
		_volume_batch(wood,SurfaceMaterials.volume_bark(),"BatchedBroadleafTrunksAndBranches",true)
	var low:=SurfaceTool.new(); low.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(bushes.size()):
		var bush: Dictionary=bushes[index]
		var bush_id: String=str(bush.get("id",""))
		if _pilot_vegetation(bush,false): continue
		if representative_bushes.has(bush_id):
			var profile: Dictionary=representative_bushes[bush_id]
			var half_height: float=float(profile.halfHeightWorld)
			var pitch: float=deg_to_rad(float(composition.get("camera",{}).get("elevationDegrees",44)))
			var contact: Vector3=_ground(float(bush.x),float(bush.z)+sin(pitch)*half_height*.96)
			var center:=Vector3(float(bush.x),contact.y+cos(pitch)*half_height*.96+.012,float(bush.z))
			_woodland_crown(low,center,float(profile.halfWidthWorld),half_height,.065,float(profile.skew),0,0,Color(.82,.85,.77,1),bool(profile.mirror),true)
			understory_cluster_count+=1
			prop_count+=1
			continue
		var radius: float=minf(float(bush.get("maxPlanarRadiusWorld",.48)),float(bush.get("scale",.5))*.66)
		for lobe in range(3+index%2):
			var angle: float=float(index)*1.71+lobe*TAU/float(3+index%2)
			var p: Vector3=_ground(float(bush.x)+cos(angle)*radius*.25,float(bush.z)+sin(angle)*radius*.25)
			_leaf_cluster(low,p+Vector3.UP*radius*(.30+.10*sin(angle)),radius*(.50+.10*cos(angle*1.3)),radius*(.31+.08*sin(angle*.7)),angle,Color(.82,.85,.77,1),true,(index+lobe)%2==0)
		understory_cluster_count+=1
		prop_count+=1
	if not bushes.is_empty(): _volume_batch(low,SurfaceMaterials.volume_foliage(),"BatchedConnected3DUnderstory")

func _build_volume_pad_rails() -> void:
	var wood:=SurfaceTool.new(); wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int=0
	for area in composition.get("deploymentAreas",[]):
		var posts: Array=area.get("earthworkPresentation",{}).get("picketPosts",[])
		for index in range(posts.size()-1):
			var aa: Array=posts[index].center
			var bb: Array=posts[index+1].center
			# Keep the existing90degree entrance open;low ties follow the existing crest arc.
			for height in [.13,.25]:
				_volume_branch(wood,_ground(float(aa[0]),float(aa[1]))+Vector3.UP*height,_ground(float(bb[0]),float(bb[1]))+Vector3.UP*height,.014,.014)
				count+=1
	if count>0: _volume_batch(wood,SurfaceMaterials.scan("timber"),"BatchedLowPadCrestRails",true)

func _build_grouped_understory(entries: Array) -> void:
	if entries.is_empty(): return
	var art: Texture2D = SourceTextures.rendered_art_texture(CROWN_TEXTURE,CROWN_TEXTURE_SHA256)
	if art==null: return
	var camera: Dictionary = composition.get("camera",{})
	var pitch: float = deg_to_rad(float(camera.get("elevationDegrees",50)))
	var yaw: float = deg_to_rad(float(camera.get("azimuthDegrees",0)))
	var horizontal := Vector3(sin(yaw),0,cos(yaw))
	var right := Vector3(cos(yaw),0,-sin(yaw))
	var up: Vector3 = Vector3.UP*cos(pitch)-horizontal*sin(pitch)
	var normal: Vector3 = Vector3.UP*sin(pitch)+horizontal*cos(pitch)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The observed .45-alpha contour ends at row1227 in the unchanged1254px source.
	var bottom_contour: float = 2.0*1227.0/1254.0-1.0
	for entry in entries:
		var radius: float = minf(float(entry.get("scale",.4))*.5,.26)
		if bool(entry.get("sceneryOnly",false)):
			radius = minf(radius,float(entry.get("maxPlanarRadiusWorld",radius)))
		var half_height: float = radius*.38
		for side in [-1,1]:
			var center_xz: Vector2 = Vector2(float(entry.x),float(entry.z))+Vector2(right.x,right.z)*radius*.22*side
			var bottom_xz: Vector2 = center_xz+Vector2(horizontal.x,horizontal.z)*half_height*bottom_contour*sin(pitch)
			var contact: Vector3 = _ground(bottom_xz.x,bottom_xz.y)
			var center := Vector3(center_xz.x,contact.y+half_height*bottom_contour*cos(pitch)+.003,center_xz.y)
			_append_crown_sprite(tool,center,right,up,normal,radius*.59,half_height,Color(.84,.84,.84),false)
		understory_cluster_count += 1
		prop_count += 1
	var material := StandardMaterial3D.new()
	material.albedo_texture = art
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = .45
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.texture_repeat = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tool.set_material(material)
	var batch := MeshInstance3D.new()
	batch.name = "SourceGroupedLowUnderstory"
	batch.mesh = tool.commit()
	batch.layers = 1
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.set_meta("presentation_only",true)
	batch.set_meta("traversable_understory",true)
	add_child(batch)
	static_instance_groups += 1

func _reference_foliage_basis(center: Vector3) -> Basis:
	# Perspective-only static decoration faces the authored eye at its OWN world position.
	# This changes neither actors nor trunk/collision ownership.
	var camera_data: Dictionary=composition.get("camera",{})
	var target_data: Array=camera_data.get("worldTarget",[.4,.45,-.25])
	var target:=Vector3(float(target_data[0]),float(target_data[1]),float(target_data[2]))
	var pitch: float=deg_to_rad(float(camera_data.get("elevationDegrees",50.0)))
	var yaw: float=deg_to_rad(float(camera_data.get("azimuthDegrees",0.0)))
	var distance: float=float(camera_data.get("distance",34.06872000123732))
	var eye: Vector3=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	var normal: Vector3=(eye-center).normalized()
	var right: Vector3=Vector3.UP.cross(normal).normalized()
	var up: Vector3=normal.cross(right).normalized()
	return Basis(right,up,normal)

func _build_leafy_crowns(entries: Array) -> void:
	# The accepted fixed tactical projection uses a real crown image. The
	# source-sized crown remains decoration; only the original trunk blocks.
	if entries.is_empty(): return
	# Existing generated-art cache loads raw sources before editor import and
	# releases them at the same application shutdown boundary as other art.
	var crown_art: Texture2D = SourceTextures.rendered_art_texture(CROWN_TEXTURE,CROWN_TEXTURE_SHA256)
	if crown_art==null:
		push_error("Authored broadleaf crown texture is missing.")
		return
	var before_count: int = canopy_tree_count
	var shadow_tool := SurfaceTool.new()
	shadow_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crowns := SurfaceTool.new()
	crowns.begin(Mesh.PRIMITIVE_TRIANGLES)
	var camera_data: Dictionary = composition.get("camera",{})
	var pitch: float = deg_to_rad(float(camera_data.get("elevationDegrees",50.0)))
	var yaw: float = deg_to_rad(float(camera_data.get("azimuthDegrees",0.0)))
	var horizontal := Vector3(sin(yaw),0,cos(yaw))
	var right := Vector3(cos(yaw),0,-sin(yaw))
	var up: Vector3 = Vector3.UP*cos(pitch)-horizontal*sin(pitch)
	var normal: Vector3 = Vector3.UP*sin(pitch)+horizontal*cos(pitch)
	for index in range(entries.size()):
		var tree: Dictionary = entries[index]
		if str(tree.get("canopyStyle",""))!="grouped-broadleaf": continue
		var radius: float = float(tree.canopyRadiusWorld)
		var height: float = float(tree.canopyHeightWorld)
		var total_height: float = float(tree.treeHeightWorld)
		var origin: Vector3 = _ground(float(tree.x),float(tree.z))
		var color := Color(str(tree.get("canopyTint","#63684b")))
		var phase: float = deg_to_rad(float(tree.get("rotationDegrees",0)))
		var center: Vector3 = origin+Vector3.UP*(total_height-height*.53)
		# Retain the former small crown volume for actual world shadow contact,
		# but keep that opaque volume out of the visible foliage silhouette.
		_append_crown_lobe(shadow_tool,center,Vector3(radius*.62,height*.34,radius*.59),phase,color.darkened(.17))
		var projected_half_height: float = sqrt(pow(height*.5*cos(pitch),2.0)+pow(radius*sin(pitch),2.0))
		var shade: float = .96+.04*cos(index*.71+phase)
		if bool(composition.get("referenceScene",{}).get("perspectiveFoliageOrientation",false)):
			var facing: Basis=_reference_foliage_basis(center)
			_append_crown_sprite(crowns,center,facing.x,facing.y,facing.z,radius,projected_half_height,Color(shade,shade,shade,1.0))
		else:
			_append_crown_sprite(crowns,center,right,up,normal,radius,projected_half_height,Color(shade,shade,shade,1.0))
		canopy_tree_count += 1
		crown_sprite_count += 1
	if canopy_tree_count==before_count: return
	if before_count==0: material_channels += 1
	shadow_tool.index()
	shadow_tool.set_material(SurfaceMaterials.canopy(composition))
	var shadow_batch := MeshInstance3D.new()
	shadow_batch.name = "BroadleafCrownContactShadows"
	shadow_batch.mesh = shadow_tool.commit()
	shadow_batch.layers = 1
	shadow_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow_batch.set_meta("presentation_only",true)
	shadow_batch.set_meta("canopy_collision",false)
	add_child(shadow_batch)
	var material := StandardMaterial3D.new()
	material.albedo_texture = crown_art
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = .45
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.texture_repeat = false
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .97
	material.metallic_specular = .08
	crowns.index()
	crowns.set_material(material)
	var crown_batch := MeshInstance3D.new()
	crown_batch.name = "AuthoredBroadleafCrownSprites"
	crown_batch.mesh = crowns.commit()
	crown_batch.layers = 1
	crown_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown_batch.set_meta("presentation_only",true)
	crown_batch.set_meta("canopy_collision",false)
	crown_batch.set_meta("art_source",CROWN_TEXTURE)
	add_child(crown_batch)
	static_instance_groups += 2

func _append_crown_sprite(tool: SurfaceTool, center: Vector3, right: Vector3, up: Vector3, normal: Vector3, half_width: float, half_height: float, color: Color, tree_crown: bool = true) -> void:
	# Exactly two camera-facing triangles. The source alpha cuts the contour;
	# there is no opaque rectangle, leaf-plate fan or invented physical body.
	for point in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		tool.set_uv(Vector2((point.x+1.0)*.5,(1.0-point.y)*.5))
		tool.set_normal(normal)
		tool.set_color(color)
		tool.add_vertex(center+right*point.x*half_width+up*point.y*half_height)
	if tree_crown:
		canopy_triangle_count += 2
	else:
		understory_triangle_count += 2

func _crown_point(center: Vector3, radii: Vector3, latitude: float, angle: float, phase: float) -> Vector3:
	var ring: float = cos(latitude)
	var scallop: float = 1.0+.085*sin(angle*5+phase)*ring+.045*cos(angle*3-phase*1.3)*ring
	return center+Vector3(cos(angle)*ring*radii.x*scallop,sin(latitude)*radii.y,sin(angle)*ring*radii.z*scallop)

func _append_crown_lobe(tool: SurfaceTool, center: Vector3, radii: Vector3, phase: float, color: Color) -> void:
	var sides: int = 14
	var rings: int = 7
	for ring in range(rings):
		var lat_a: float = -PI*.5+PI*float(ring)/rings
		var lat_b: float = -PI*.5+PI*float(ring+1)/rings
		for side in range(sides):
			var angle_a: float = TAU*float(side)/sides
			var angle_b: float = TAU*float(side+1)/sides
			var a: Vector3 = _crown_point(center,radii,lat_a,angle_a,phase)
			var b: Vector3 = _crown_point(center,radii,lat_a,angle_b,phase)
			var c: Vector3 = _crown_point(center,radii,lat_b,angle_a,phase)
			var d: Vector3 = _crown_point(center,radii,lat_b,angle_b,phase)
			for point in [a,b,c,b,d,c]:
				var local: Vector3 = point-center
				var normal := Vector3(local.x/(radii.x*radii.x),local.y/(radii.y*radii.y),local.z/(radii.z*radii.z)).normalized()
				tool.set_normal(normal)
				tool.set_color(color)
				tool.add_vertex(point)
			canopy_triangle_count += 2

func _build_camp_details() -> void:
	for entry in composition.get("tents",[]):
		var center: Array=entry.center
		var p: Vector3=_ground(float(center[0]),float(center[1]))
		var width: float=float(entry.width)
		var depth: float=float(entry.depth)
		var height: float=float(entry.height)
		var angle: float=deg_to_rad(float(entry.get("rotationDegrees",0)))
		var basis:=Basis(Vector3.UP,angle)
		var tool:=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for sign_value in [-1,1]:
			for panel in range(4):
				var t_a: float = float(panel)/4.0
				var t_b: float = float(panel+1)/4.0
				var y_a: float = height*(1.0-t_a)-.025*sin(PI*t_a)
				var y_b: float = height*(1.0-t_b)-.025*sin(PI*t_b)
				var a: Vector3 = p+basis*Vector3(sign_value*width*.5*t_a,y_a,-depth*.5)
				var b: Vector3 = p+basis*Vector3(sign_value*width*.5*t_a,y_a,depth*.5)
				var c: Vector3 = p+basis*Vector3(sign_value*width*.5*t_b,y_b,-depth*.5)
				var d: Vector3 = p+basis*Vector3(sign_value*width*.5*t_b,y_b,depth*.5)
				if sign_value>0:
					_emit_triangle(tool,a,c,b,Vector2(t_a,0),Vector2(t_b,0),Vector2(t_a,1))
					_emit_triangle(tool,b,c,d,Vector2(t_a,1),Vector2(t_b,0),Vector2(t_b,1))
				else:
					_emit_triangle(tool,a,b,c,Vector2(t_a,0),Vector2(t_a,1),Vector2(t_b,0))
					_emit_triangle(tool,b,d,c,Vector2(t_a,1),Vector2(t_b,1),Vector2(t_b,0))
			var edge_front: Vector3 = p+basis*Vector3(sign_value*width*.5,0,-depth*.5)
			var edge_back: Vector3 = p+basis*Vector3(sign_value*width*.5,0,depth*.5)
			_add_beam(edge_front,p+basis*Vector3(0,height,-depth*.5),.018)
			_add_beam(edge_back,p+basis*Vector3(0,height,depth*.5),.018)
		tool.generate_normals()
		var cloth_material: StandardMaterial3D = SurfaceMaterials.cloth().duplicate() as StandardMaterial3D
		cloth_material.albedo_color = Color(str(entry.get("color","#bdb7a0")))
		tool.set_material(cloth_material)
		var tent:=MeshInstance3D.new()
		tent.mesh=tool.commit()
		add_child(tent)
		prop_count+=1
	for entry in composition.get("supplyCrates",[]):
		var height: float=float(entry.height)
		var p: Vector3=_ground(float(entry.x),float(entry.z))
		_add_box(p+Vector3.UP*height*.5,Vector3(float(entry.width),height,float(entry.depth)),deg_to_rad(float(entry.rotationDegrees)))
		_add_rope_tie(p+Vector3.UP*height*.6,minf(float(entry.width),float(entry.depth))*.52)
	for family in ["barrels","baskets"]:
		for entry in composition.get(family,[]):
			var height: float=float(entry.height)
			var radius: float=float(entry.radius)
			var p: Vector3=_ground(float(entry.x),float(entry.z))
			var body:=CylinderMesh.new()
			body.top_radius=radius*.90 if family=="barrels" else radius
			body.bottom_radius=radius*.88
			body.height=height
			body.radial_segments=12
			var mesh:=MeshInstance3D.new()
			mesh.mesh=body
			mesh.material_override=SurfaceMaterials.scan("timber") if family=="barrels" else SurfaceMaterials.rope()
			mesh.position=p+Vector3.UP*height*.5
			add_child(mesh)
			_add_rope_tie(p+Vector3.UP*height*.20,radius)
			_add_rope_tie(p+Vector3.UP*height*.80,radius)
			prop_count+=1
	for entry in composition.get("weaponRacks",[]):
		var center: Array=entry.center
		var p: Vector3=_ground(float(center[0]),float(center[1]))
		var basis:=Basis(Vector3.UP,deg_to_rad(float(entry.rotationDegrees)))
		var width: float=float(entry.width)
		var height: float=float(entry.height)
		for sign_value in [-1,1]: _add_beam(p+basis*Vector3(sign_value*width*.5,0,0),p+basis*Vector3(sign_value*width*.5,height,0),.025)
		_add_beam(p+basis*Vector3(-width*.5,height*.72,0),p+basis*Vector3(width*.5,height*.72,0),.024)
		for index in range(3): _add_beam(p+basis*Vector3(-width*.3+index*width*.3,.015,.06),p+basis*Vector3(-width*.3+index*width*.3,height+.14,-.08),.012)

func apply_lighting(troops: Control) -> void:
	if not is_instance_valid(troops.get("sun")): return
	lighting_owner=weakref(troops)
	var light: Dictionary = composition.get("lighting",{})
	var rotation_values: Array = light.get("sunRotationDegrees",[-54,-38,0])
	troops.sun.rotation_degrees = Vector3(float(rotation_values[0]),float(rotation_values[1]),float(rotation_values[2]))
	troops.sun.light_energy = float(light.get("sunEnergy",1.12))
	troops.sun.light_color = Color(str(light.get("sunColor","#e1e4dd")))
	troops.sun.shadow_bias = .02
	troops.sun.shadow_normal_bias = .24
	troops.sun.shadow_blur = 1.8
	troops.sun.shadow_opacity = .45
	if bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)):
		troops.sun.shadow_enabled=true
		troops.sun.shadow_normal_bias=.08
		troops.sun.shadow_blur=2.2
		troops.sun.shadow_opacity=.50
	if is_instance_valid(troops.get("fill")): troops.fill.light_energy = float(light.get("actorFillEnergy",.18))
	if troops.get("environment")!=null:
		troops.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		troops.environment.ambient_light_color = Color(str(light.get("ambientColor","#88969b")))
		troops.environment.ambient_light_energy = float(light.get("ambientEnergy",.6))
		if bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)):
			troops.environment.tonemap_mode=Environment.TONE_MAPPER_ACES
			troops.environment.tonemap_exposure=1.0
			troops.environment.ssao_enabled=true
			troops.environment.ssao_radius=.45
			troops.environment.ssao_intensity=.65
			troops.environment.glow_enabled=true
			troops.environment.glow_intensity=.12
			troops.environment.glow_bloom=.015
			troops.environment.glow_hdr_threshold=1.1
			troops.environment.fog_enabled=true
			troops.environment.fog_mode=Environment.FOG_MODE_DEPTH
			troops.environment.fog_depth_begin=48.0
			troops.environment.fog_depth_end=60.0
			troops.environment.fog_depth_curve=1.6
			troops.environment.fog_density=.12
			troops.environment.fog_light_color=Color("a0aaa0")
			troops.environment.fog_light_energy=.75
			troops.environment.fog_height_density=0.0
			troops.environment.fog_sky_affect=.15
			troops.environment.fog_sun_scatter=0.0
		lighting_readback={"tonemapMode":troops.environment.tonemap_mode,"exposure":troops.environment.tonemap_exposure,"ssaoEnabled":troops.environment.ssao_enabled,"ssaoRadius":troops.environment.ssao_radius,"ssaoIntensity":troops.environment.ssao_intensity,"glowEnabled":troops.environment.glow_enabled,"glowIntensity":troops.environment.glow_intensity,"glowBloom":troops.environment.glow_bloom,"sunShadowEnabled":troops.sun.shadow_enabled,"sunCullMask":troops.sun.light_cull_mask,"sunShadowNormalBias":troops.sun.shadow_normal_bias,"sunShadowOpacity":troops.sun.shadow_opacity}
	troops.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func diagnostics() -> Dictionary:
	if lighting_owner!=null and is_instance_valid(lighting_owner.get_ref()):
		var actual: Control=lighting_owner.get_ref() as Control
		var env: Environment=actual.get("environment") as Environment
		var actual_sun: DirectionalLight3D=actual.get("sun") as DirectionalLight3D
		if env!=null and is_instance_valid(actual_sun):
			lighting_readback={"tonemapMode":env.tonemap_mode,"exposure":env.tonemap_exposure,"fogEnabled":env.fog_enabled,"fogMode":env.fog_mode,"fogDensity":env.fog_density,"fogDepthBegin":env.fog_depth_begin,"fogDepthEnd":env.fog_depth_end,"fogHeightDensity":env.fog_height_density,"ssaoEnabled":env.ssao_enabled,"ssaoRadius":env.ssao_radius,"ssaoIntensity":env.ssao_intensity,"glowEnabled":env.glow_enabled,"glowIntensity":env.glow_intensity,"glowBloom":env.glow_bloom,"sunShadowEnabled":actual_sun.shadow_enabled,"sunCullMask":actual_sun.light_cull_mask,"sunShadowNormalBias":actual_sun.shadow_normal_bias,"sunShadowOpacity":actual_sun.shadow_opacity}
	var gate_lights: Array=[]
	for child in get_children():
		if child is OmniLight3D: gate_lights.append({"cullMask":child.light_cull_mask,"shadows":child.shadow_enabled,"energy":child.light_energy,"range":child.omni_range})
	var lod_records: Array = []
	var lod_budgets_met: bool = true
	for key in scan_templates:
		for record in scan_templates[key].mesh.get_meta("tactical_lod_evidence",[]):
			var entry: Dictionary = record.duplicate()
			entry["template"] = key
			lod_records.append(entry)
			lod_budgets_met = lod_budgets_met and bool(entry.withinBudget)
	return {"blenderPilot":_pilot_diagnostics.duplicate(true),"candidate":true,"providerOwnsFloor":true,"propCount":prop_count,"picketCount":picket_count,
		"volumetricForest":bool(composition.get("mapCameraArt",{}).get("volumetricForest",false)),"volumeLeafTriangles":volume_leaf_triangles,"volumeWoodTriangles":volume_wood_triangles,"lightingReadback":lighting_readback.duplicate(true),"gateLightReadback":gate_lights,
		"staticPicketGroups":static_instance_groups,"materialChannels":material_channels,
		"staticScanTriangles":static_triangles,"staticScanTemplates":scan_templates.size(),
		"staticLodEvidence":lod_records,"staticLodBudgetsMet":lod_budgets_met,
		"peripheralSceneryTriangles":int(scenery_indices.size()/3),"peripheralSceneryInteractive":false,
		"peripheralSceneryHeightFailures":scenery_height_failures,
		"directionCues":direction_cues.duplicate(true),"peripheralStreamTriangles":stream_triangle_count,
		"broadleafTreeCount":canopy_tree_count,"broadleafTriangles":canopy_triangle_count,
		"broadleafSpriteCount":crown_sprite_count,"broadleafArtPath":CROWN_TEXTURE,
		"broadleafArtSha256":CROWN_TEXTURE_SHA256,
		"broadleafVisibleTriangles":volume_leaf_triangles if volume_leaf_triangles>0 else crown_sprite_count*2,"broadleafShadowTriangles":volume_leaf_triangles if volume_leaf_triangles>0 else canopy_triangle_count-crown_sprite_count*2,
		"materialPadHeightSamples":composition.get("materialPadHeightSamples",{}).duplicate(true),
		"groupedUnderstoryCount":understory_cluster_count,"groupedUnderstoryTriangles":understory_triangle_count,
		"shortGrassPresentation":"provider-ground-material;no-individual-blade-meshes",
		"earthworkPicketCount":earthwork_picket_count,"padFloorSource":"provider.worldGeometry",
		"floorFromAuthoredTriangles":provider.has_method("supports_world_geometry") and provider.supports_world_geometry()}


# BLENDER-ASSET-PRODUCTION-01: isolated imported render assets only.
var _pilot_templates: Dictionary = {}
var _pilot_bindings: Dictionary = {}
var _pilot_library: Node3D
var _pilot_diagnostics: Dictionary = {}

func _pilot_prepare() -> void:
	_pilot_templates.clear()
	_pilot_bindings.clear()
	_pilot_diagnostics={"treeInstances":0,"shrubInstances":0,"palisadeInstances":0,"importedTriangles":0,"floorGeometryChanged":false,"firingPad":"showcase-only;provider floor and exact entrance retained","errors":[]}
	var path: String="res://assets/blender-pilot/asset.glb"
	var binding_path: String="res://assets/blender-pilot/bindings.json"
	if not FileAccess.file_exists(binding_path) or not ResourceLoader.exists(path):
		_pilot_diagnostics.errors.append("Asset GLB/bindings missing or not imported;old render assets retained")
		return
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding_path))
	if not parsed is Dictionary: return
	_pilot_bindings=parsed
	var packed: PackedScene=load(path) as PackedScene
	if packed==null: return
	_pilot_library=packed.instantiate() as Node3D
	if _pilot_library==null: return
	_pilot_library.name="BlenderPilotHiddenTemplateLibrary"
	add_child(_pilot_library)
	_pilot_library.hide()
	for name_value in _pilot_bindings.roots:
		var node: Node3D=_pilot_library.find_child(str(name_value),true,false) as Node3D
		if node==null:
			_pilot_diagnostics.errors.append("Imported named root missing: "+str(name_value))
			continue
		_pilot_templates[str(name_value)]=node

func _pilot_relative_transform(node: Node3D) -> Transform3D:
	var result:=Transform3D.IDENTITY
	var cursor: Node=node
	while cursor is Node3D:
		result=(cursor as Node3D).transform*result
		if cursor==_pilot_library: break
		cursor=cursor.get_parent()
	return result

func _pilot_render_only(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Light3D or child is Camera3D:
			node.remove_child(child)
			child.queue_free()
		else: _pilot_render_only(child)
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers=1
		(node as MeshInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _pilot_instance(asset: String, position_value: Vector3, scale_value: Vector3, yaw: float, identifier: String) -> Node3D:
	if not _pilot_templates.has(asset): return null
	var source: Node3D=_pilot_templates[asset]
	var model: Node3D=source.duplicate() as Node3D
	if model==null: return null
	model.transform=_pilot_relative_transform(source)
	model.show()
	_pilot_render_only(model)
	var wrapper:=Node3D.new()
	wrapper.name="BlenderPilot_"+identifier.replace("-","_")
	wrapper.position=position_value
	wrapper.rotation.y=yaw
	wrapper.scale=scale_value
	wrapper.set_meta("scenery_only",true)
	wrapper.set_meta("authoritative_floor",false)
	wrapper.set_meta("source_anchor_id",identifier)
	add_child(wrapper)
	wrapper.add_child(model)
	_pilot_diagnostics.importedTriangles+=int(_pilot_bindings.roots[asset].triangles)
	return wrapper

func _pilot_vegetation(entry: Dictionary, tree: bool) -> bool:
	var records: Dictionary=_pilot_bindings.get("trees" if tree else "shrubs",{})
	var identifier: String=str(entry.get("id",""))
	if not records.has(identifier): return false
	var record: Dictionary=records[identifier]
	var p: Vector3=_ground(float(entry.x),float(entry.z))
	if not is_finite(p.y): return false
	var model: Node3D=_pilot_instance(str(record.asset),p,Vector3.ONE*float(record.scale),deg_to_rad(float(record.yaw_degrees)),identifier)
	if model==null: return false
	_pilot_diagnostics["treeInstances" if tree else "shrubInstances"]+=1
	prop_count+=1
	if tree: canopy_tree_count+=1
	else: understory_cluster_count+=1
	return true

func _pilot_fence(fence: Dictionary) -> bool:
	if str(fence.get("id",""))!=str(_pilot_bindings.get("fence_id","")): return false
	var a: Vector3=_ground(float(fence.a[0]),float(fence.a[1]))
	var b: Vector3=_ground(float(fence.b[0]),float(fence.b[1]))
	if absf(a.y-b.y)>.12:
		_pilot_diagnostics.errors.append("Palisade base terrain differs >.12;old segment retained")
		return false
	var bounds: Dictionary=_pilot_bindings.roots.Palisade
	var dimensions: Array=bounds.size
	var direction:=Vector2(b.x-a.x,b.z-a.z)
	var position_value: Vector3=_ground((a.x+b.x)*.5,(a.z+b.z)*.5)
	var model: Node3D=_pilot_instance("Palisade",position_value,Vector3(direction.length()/float(dimensions[0]),float(fence.height)/float(dimensions[1]),1),-atan2(direction.y,direction.x),str(fence.id))
	if model==null: return false
	_pilot_diagnostics.palisadeInstances+=1
	return true

func _pilot_ground_source(node: Node, material_name: String) -> BaseMaterial3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null:
		var mesh_node:=node as MeshInstance3D
		for index in range(mesh_node.mesh.get_surface_count()):
			var source: BaseMaterial3D=mesh_node.get_active_material(index) as BaseMaterial3D
			if source!=null and source.resource_name==material_name and source.albedo_texture!=null: return source
	for child in node.get_children():
		var found: BaseMaterial3D=_pilot_ground_source(child,material_name)
		if found!=null: return found
	return null

func _pilot_ground_material(existing: ShaderMaterial) -> ShaderMaterial:
	if not _pilot_templates.has("FiringPad"): return existing
	var material_name: String="CompactedDirt_ImagePBR"
	var source: BaseMaterial3D=_pilot_ground_source(_pilot_templates.FiringPad,material_name)
	if source==null:
		_pilot_diagnostics.errors.append("FiringPad CompactedDirt_ImagePBR image material missing;existing ground retained")
		return existing
	var material: ShaderMaterial=existing.duplicate(false)
	_pilot_diagnostics["groundSourceMaterial"]=material_name
	_pilot_diagnostics["groundSourceRoot"]="FiringPad"
	_pilot_diagnostics["groundUVScale"]="Existing soil_uv p*.31 for map-camera finish or p*.40 otherwise;no GroundSample UV/layout reuse"
	material.set_shader_parameter("soil_albedo",source.albedo_texture)
	_pilot_diagnostics["groundAlbedoBound"]=true
	_pilot_diagnostics["groundUV"]="existing world XZ;no mesh/UV/route-mask edits"
	if source.normal_enabled and source.normal_texture!=null:
		material.set_shader_parameter("soil_normal",source.normal_texture)
		_pilot_diagnostics["groundNormalBound"]=true
	if source.roughness_texture!=null and source.roughness_texture_channel==BaseMaterial3D.TEXTURE_CHANNEL_RED:
		material.set_shader_parameter("soil_rough",source.roughness_texture)
		_pilot_diagnostics["groundRoughnessBound"]=true
	else: _pilot_diagnostics["groundRoughness"]="Existing roughness retained;packed imported G-channel not misread as R"
	return material
