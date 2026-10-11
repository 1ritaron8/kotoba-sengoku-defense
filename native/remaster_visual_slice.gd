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

func configure(stage: Dictionary, floor_provider: Node3D) -> void:
	provider = floor_provider
	composition = stage.get("visualComposition",{}).duplicate(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	prop_count = 0
	picket_count = 0
	static_instance_groups = 0
	composition["materialPadHeightSamples"] = _material_pad_height_samples()
	provider.set_surface_material(SurfaceMaterials.ground(composition))
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
		var a := Vector2(float(fence.a[0]),float(fence.a[1]))
		var b := Vector2(float(fence.b[0]),float(fence.b[1]))
		var count: int = maxi(2,ceili(a.distance_to(b)/0.16))
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
	light.shadow_enabled = false
	light.light_cull_mask = 1
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
	var light: Dictionary = composition.get("lighting",{})
	var rotation_values: Array = light.get("sunRotationDegrees",[-54,-38,0])
	troops.sun.rotation_degrees = Vector3(float(rotation_values[0]),float(rotation_values[1]),float(rotation_values[2]))
	troops.sun.light_energy = float(light.get("sunEnergy",1.12))
	troops.sun.light_color = Color(str(light.get("sunColor","#e1e4dd")))
	troops.sun.shadow_bias = .02
	troops.sun.shadow_normal_bias = .24
	troops.sun.shadow_blur = 1.8
	troops.sun.shadow_opacity = .45
	if is_instance_valid(troops.get("fill")): troops.fill.light_energy = float(light.get("actorFillEnergy",.18))
	if troops.get("environment")!=null:
		troops.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		troops.environment.ambient_light_color = Color(str(light.get("ambientColor","#88969b")))
		troops.environment.ambient_light_energy = float(light.get("ambientEnergy",.6))
	troops.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func diagnostics() -> Dictionary:
	var lod_records: Array = []
	var lod_budgets_met: bool = true
	for key in scan_templates:
		for record in scan_templates[key].mesh.get_meta("tactical_lod_evidence",[]):
			var entry: Dictionary = record.duplicate()
			entry["template"] = key
			lod_records.append(entry)
			lod_budgets_met = lod_budgets_met and bool(entry.withinBudget)
	return {"candidate":true,"providerOwnsFloor":true,"propCount":prop_count,"picketCount":picket_count,
		"staticPicketGroups":static_instance_groups,"materialChannels":material_channels,
		"staticScanTriangles":static_triangles,"staticScanTemplates":scan_templates.size(),
		"staticLodEvidence":lod_records,"staticLodBudgetsMet":lod_budgets_met,
		"peripheralSceneryTriangles":int(scenery_indices.size()/3),"peripheralSceneryInteractive":false,
		"peripheralSceneryHeightFailures":scenery_height_failures,
		"directionCues":direction_cues.duplicate(true),"peripheralStreamTriangles":stream_triangle_count,
		"broadleafTreeCount":canopy_tree_count,"broadleafTriangles":canopy_triangle_count,
		"broadleafSpriteCount":crown_sprite_count,"broadleafArtPath":CROWN_TEXTURE,
		"broadleafArtSha256":CROWN_TEXTURE_SHA256,
		"broadleafVisibleTriangles":crown_sprite_count*2,"broadleafShadowTriangles":canopy_triangle_count-crown_sprite_count*2,
		"materialPadHeightSamples":composition.get("materialPadHeightSamples",{}).duplicate(true),
		"groupedUnderstoryCount":understory_cluster_count,"groupedUnderstoryTriangles":understory_triangle_count,
		"shortGrassPresentation":"provider-ground-material;no-individual-blade-meshes",
		"earthworkPicketCount":earthwork_picket_count,"padFloorSource":"provider.worldGeometry",
		"floorFromAuthoredTriangles":provider.has_method("supports_world_geometry") and provider.supports_world_geometry()}
