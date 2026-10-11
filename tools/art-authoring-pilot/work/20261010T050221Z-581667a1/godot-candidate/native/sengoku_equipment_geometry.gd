extends RefCounted
## Class equipment in the actor's existing rigid joint coordinates.
## Weapon shafts/blades point along +Y; the animation rig supplies the aim.
## Stages 0, 1 and 2 correspond to initial, level-four and level-eight equipment.

const Panels = preload("res://native/sengoku_armor_geometry.gd")
const TYPES = ["archer","spear","samurai","gunner","naginata","monk","commander","ninja"]
static var _cache: Dictionary = {}
static var _detail_enabled: bool = true

static func build(unit_type: String, evolution_stage: int = 0, detail_enabled: bool = true) -> Array[Dictionary]:
	var type: String = "spear" if unit_type=="enemy_light" else "samurai" if unit_type=="enemy_heavy" else unit_type
	if not TYPES.has(type):
		return []
	var stage: int = clampi(evolution_stage,0,2)
	var key: String = type+"/"+str(stage)+"/"+str(detail_enabled)
	if _cache.has(key):
		return _cache[key]
	# Construction is synchronous; every cached variant stores its own meshes.
	_detail_enabled = detail_enabled
	var builders: Dictionary = {}
	_build_weapon(builders,type,stage)
	_build_headgear(builders,type,stage)
	_build_outfit(builders,type,stage)
	_build_evolution_guards(builders,type,stage)
	_build_evolution(builders,type,stage)
	var pieces: Array[Dictionary] = []
	for surface_key in builders:
		var entry: Dictionary = builders[surface_key]
		var tool: SurfaceTool = entry.tool
		tool.index()
		tool.generate_tangents()
		pieces.append({"bone":entry.bone,"material":entry.material,"mesh":tool.commit()})
	_cache[key] = pieces
	return pieces

static func _tool(builders: Dictionary, bone: String, material: String) -> SurfaceTool:
	var key: String = bone+"/"+material
	if not builders.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders[key] = {"tool":tool,"bone":bone,"material":material}
	return builders[key].tool

static func _color(value: float) -> Color:
	return Color(value,value,value,1)

static func _append(builders: Dictionary, bone: String, material: String, mesh: Mesh, origin: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, tint: float = 1.0) -> void:
	var tool: SurfaceTool = _tool(builders,bone,material)
	var basis: Basis = Basis.from_euler(rotation).scaled(scale)
	var normal_basis: Basis = basis.inverse().transposed()
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for cursor in range(0,count,3):
			var triangle_indices: Array[int] = []
			var triangle_points: Array[Vector3] = []
			for corner in range(3):
				var index: int = indices[cursor+corner] if not indices.is_empty() else cursor+corner
				triangle_indices.append(index)
				triangle_points.append(basis*vertices[index]+origin)
			# Built-in sphere poles and cone caps can contain zero-area triangles.
			if (triangle_points[1]-triangle_points[0]).cross(triangle_points[2]-triangle_points[0]).length_squared()<0.00000000000001:
				continue
			for corner in range(3):
				var index: int = triangle_indices[corner]
				tool.set_normal((normal_basis*normals[index]).normalized())
				tool.set_uv(uvs[index])
				tool.set_color(_color(tint))
				tool.add_vertex(triangle_points[corner])

static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12 if _detail_enabled else 8
	mesh.rings = 6 if _detail_enabled else 4
	return mesh

static func _rod(builders: Dictionary, bone: String, material: String, start: Vector3, end: Vector3, radius: float, tint: float = 1.0, end_radius: float = -1.0) -> void:
	var delta: Vector3 = end-start
	if delta.length_squared()<0.000001:
		return
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if end_radius<0.0 else end_radius
	mesh.height = delta.length()
	mesh.radial_segments = 8 if _detail_enabled else 4
	mesh.rings = 1
	var basis: Basis = Basis(Quaternion(Vector3.UP,delta.normalized()))
	_append(builders,bone,material,mesh,(start+end)*0.5,basis.get_euler(),Vector3.ONE,tint)

static func _ring(builders: Dictionary, bone: String, material: String, center: Vector3, radius: float, tube: float, axis: Vector3 = Vector3.FORWARD, tint: float = 1.0, start_angle: float = 0.0, arc: float = TAU) -> void:
	var basis: Basis = Basis(Quaternion(Vector3.FORWARD,axis.normalized()))
	var major: int = maxi(6,ceili(((20 if radius>0.07 else 12) if _detail_enabled else 8)*arc/TAU))
	var minor: int = 4 if _detail_enabled else 3
	var tool: SurfaceTool = _tool(builders,bone,material)
	var points: Array = []
	var normals: Array = []
	var uvs: Array = []
	var colors: Array = []
	for row in range(major+1):
		var a: float = start_angle+arc*float(row)/major
		for column in range(minor+1):
			var b: float = TAU*float(column)/minor
			points.append(center+basis*Vector3(cos(a)*(radius+tube*cos(b)),sin(a)*(radius+tube*cos(b)),tube*sin(b)))
			normals.append(basis*Vector3(cos(a)*cos(b),sin(a)*cos(b),sin(b)))
			uvs.append(Vector2(float(row)/major,float(column)/minor))
			colors.append(_color(tint))
	for row in range(major):
		for column in range(minor):
			var a: int = row*(minor+1)+column
			var b: int = a+1
			var d: int = a+minor+1
			var c: int = d+1
			Panels._triangle(tool,points,normals,uvs,colors,a,b,c)
			Panels._triangle(tool,points,normals,uvs,colors,a,c,d)

static func _polygon(builders: Dictionary, bone: String, material: String, shape: PackedVector2Array, depth: float, origin: Vector3 = Vector3.ZERO, tint: float = 1.0) -> void:
	var tool: SurfaceTool = _tool(builders,bone,material)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(shape)
	for side in [-1.0,1.0]:
		var points: Array = []
		var normals: Array = []
		var uvs: Array = []
		var colors: Array = []
		for point in shape:
			points.append(origin+Vector3(point.x,point.y,side*depth*0.5))
			normals.append(Vector3(0,0,side))
			uvs.append(Vector2(point.x*2+0.5,point.y))
			colors.append(_color(tint))
		for cursor in range(0,indices.size(),3):
			Panels._triangle(tool,points,normals,uvs,colors,indices[cursor],indices[cursor+1],indices[cursor+2])
	var center: Vector2 = Vector2.ZERO
	for point in shape: center += point
	center /= shape.size()
	for index in range(shape.size()):
		var a: Vector2 = shape[index]
		var b: Vector2 = shape[(index+1)%shape.size()]
		var edge_normal: Vector3 = Vector3((a.x+b.x)*0.5-center.x,(a.y+b.y)*0.5-center.y,0).normalized()
		Panels._quad(tool,origin+Vector3(a.x,a.y,-depth*0.5),origin+Vector3(b.x,b.y,-depth*0.5),origin+Vector3(b.x,b.y,depth*0.5),origin+Vector3(a.x,a.y,depth*0.5),edge_normal,_color(tint*0.78))

static func _profile_cap(builders: Dictionary, bone: String, material: String, profile: Array[Vector2], ratio: float = 1.0, tint: float = 1.0, start_angle: float = 0.0, arc: float = TAU, offset: Vector3 = Vector3.ZERO) -> void:
	var tool: SurfaceTool = _tool(builders,bone,material)
	var points: Array = []
	var segments: int = maxi(3,ceili((24 if _detail_enabled else 12)*arc/TAU))
	for row in range(profile.size()):
		for column in range(segments+1):
			var angle: float = start_angle+arc*float(column)/segments
			points.append(offset+Vector3(cos(angle)*profile[row].x,profile[row].y,sin(angle)*profile[row].x*ratio))
	# Partial helmet arcs and complete hat crowns are separate from torso panels.
	var normals: Array = []
	var uvs: Array = []
	var colors: Array = []
	for row in range(profile.size()):
		var below: Vector2 = profile[maxi(0,row-1)]
		var above: Vector2 = profile[mini(profile.size()-1,row+1)]
		var slope: float = (above.x-below.x)/maxf(0.000001,above.y-below.y)
		for column in range(segments+1):
			var angle: float = start_angle+arc*float(column)/segments
			normals.append(Vector3(cos(angle),-slope,sin(angle)/ratio).normalized())
			uvs.append(Vector2(float(column)/segments,float(row)/maxi(1,profile.size()-1)))
			colors.append(_color(tint))
	for row in range(profile.size()-1):
		for column in range(segments):
			var a: int = row*(segments+1)+column
			var b: int = a+1
			var d: int = a+segments+1
			var c: int = d+1
			Panels._triangle(tool,points,normals,uvs,colors,a,b,c)
			Panels._triangle(tool,points,normals,uvs,colors,a,c,d)

static func _build_weapon(builders: Dictionary, type: String, stage: int) -> void:
	if type=="archer":
		var length: float = 1.14+float(stage)*0.09
		for section in range(16):
			var t0: float = float(section)/16
			var t1: float = float(section+1)/16
			var p0: Vector3 = Vector3(0.13*sin(t0*PI),-length*0.44+t0*length,0)
			var p1: Vector3 = Vector3(0.13*sin(t1*PI),-length*0.44+t1*length,0)
			_rod(builders,"weapon","wood",p0,p1,0.013+stage*0.001,0.82)
		# The actor owns the posed string and nocked arrow in the existing
		# skin palette; permanently batched copies would survive a real shot.
		_rod(builders,"weapon","leather",Vector3(0.127,-0.045,0),Vector3(0.127,0.065,0),0.017,0.85)
	elif type=="spear":
		_rod(builders,"weapon","wood",Vector3(0,-0.72,0),Vector3(0,1.0+stage*0.025,0),0.015,0.85)
		_blade(builders,"weapon",[Vector3(0,0.970,0.010),Vector3(0,1.024,0.032),Vector3(0,1.120+stage*0.020,0.025),Vector3(0,1.310+stage*0.035,0.0005)],Vector3.ZERO,0.006)
		_rod(builders,"weapon","leather",Vector3(0,0.82,0),Vector3(0,0.96,0),0.019,0.70)
	elif type in ["samurai","commander"]:
		_build_katana(builders,"weapon",stage,Vector3.ZERO)
		_rod(builders,"pelvis","wood",Vector3(-0.17,0.03,0.04),Vector3(-0.39,-0.26,0.08),0.022,0.72)
	elif type=="gunner":
		_build_matchlock(builders,stage)
	elif type=="naginata":
		_rod(builders,"weapon","wood",Vector3(0,-0.77,0),Vector3(0,0.94,0),0.016,0.84)
		var extension: float = stage*0.035
		_blade(builders,"weapon",[Vector3(.007,.870,.015),Vector3(.028,.975,.027),Vector3(.047,1.080+extension,.029),Vector3(.066,1.180+extension,.024),Vector3(.086,1.250+extension,.0005)],Vector3.ZERO,.005)
		_rod(builders,"weapon","leather",Vector3(0,0.74,0),Vector3(0,0.89,0),0.022,0.76)
		if stage>0:
			_rod(builders,"weapon","gold",Vector3(0,0.81,0),Vector3(0,0.84,0),0.024,0.63)
	elif type=="monk":
		_rod(builders,"weapon","wood",Vector3(0,-0.73,0),Vector3(0,0.92,0),0.017,0.86)
		_ring(builders,"weapon","metal",Vector3(0,0.996,0),0.104+0.008*stage,0.007,Vector3.FORWARD,0.75)
		var rings: int = 4+stage*2
		for index in range(rings):
			var angle: float = PI*float(index+1)/float(rings+1)
			var point: Vector3 = Vector3(cos(angle)*0.095,0.97+sin(angle)*0.064,-0.010)
			_ring(builders,"weapon","metal",point,0.027,0.0034,Vector3.RIGHT,0.66)
		_rod(builders,"weapon","gold",Vector3(0,0.83,0),Vector3(0,0.90,0),0.022,0.65)
	elif type=="ninja":
		_build_dagger(builders,"weapon",stage,Vector3.ZERO)
		_build_dagger(builders,"handL",stage,Vector3(0,-0.05,0.012))

static func _build_katana(builders: Dictionary, bone: String, stage: int, offset: Vector3) -> void:
	_rod(builders,bone,"leather",offset+Vector3(0,-0.17,0),offset+Vector3(0,0.071,0),0.020,0.76)
	_rod(builders,bone,"gold",offset+Vector3(0,0.075,0),offset+Vector3(0,0.087,0),0.046,0.56)
	var tip: float = 0.79+stage*0.035
	_blade(builders,bone,[Vector3(0,.090,.0175),Vector3(.006,.280,.0178),Vector3(.018,.470,.0169),Vector3(.039,tip-.072,.0145),Vector3(.053,tip,.0005)],offset,.0042)
	_wrapped_grip(builders,bone,offset,-.154,.045,.017,7 if _detail_enabled else 4)

static func _build_dagger(builders: Dictionary, bone: String, stage: int, offset: Vector3) -> void:
	_rod(builders,bone,"leather",offset+Vector3(0,-0.13,0),offset+Vector3(0,0.035,0),0.019,0.53)
	_rod(builders,bone,"metal",offset+Vector3(-0.027,0.045,0),offset+Vector3(0.027,0.045,0),0.009,0.44)
	var length: float = 0.31+stage*0.055
	_blade(builders,bone,[Vector3(0,.047,.017),Vector3(.003,length-.077,.018),Vector3(.014,length,.0005)],offset,.004)
	_wrapped_grip(builders,bone,offset,-.119,.022,.015,4 if _detail_enabled else 2)

static func _wrapped_grip(builders: Dictionary, bone: String, origin: Vector3, bottom: float, top: float, width: float, bands: int) -> void:
	# Two crossed silk runs leave physical diamond-shaped leather gaps.
	var tool: SurfaceTool = _tool(builders,bone,"cord")
	for side in [-1.0,1.0]:
		for band in range(bands):
			var y0: float = lerpf(bottom,top,float(band)/bands)
			var y1: float = lerpf(bottom,top,float(band+1)/bands)
			Panels._rod(tool,origin+Vector3(-width,y0,side*.014),origin+Vector3(width,y1,side*.014),.0029,.93,6 if _detail_enabled else 4)
			Panels._rod(tool,origin+Vector3(width,y0,side*.014),origin+Vector3(-width,y1,side*.014),.0029,.93,6 if _detail_enabled else 4)

static func _blade(builders: Dictionary, bone: String, stations: Array[Vector3], offset: Vector3, half_depth: float) -> void:
	# Forged spine and cutting bevel are distinct planes, not a flat extrusion.
	var tool: SurfaceTool = _tool(builders,bone,"metal")
	var fractions: Array[float] = [-1.0,-0.33,0.26,1.0]
	var depths: Array[float] = [.18,.91,1.0,.06]
	for side in [-1.0,1.0]:
		var points: Array = []
		for station in stations:
			for column in range(4):
				points.append(offset+Vector3(station.x+station.z*fractions[column],station.y,side*half_depth*depths[column]))
		Panels._patch(tool,points,3,stations.size()-1,Vector3(0,0,side),1.02)
	for edge in [0,3]:
		for row in range(stations.size()-1):
			var s0: Vector3 = stations[row]
			var s1: Vector3 = stations[row+1]
			var a: Vector3 = offset+Vector3(s0.x+s0.z*fractions[edge],s0.y,half_depth*depths[edge])
			var b: Vector3 = offset+Vector3(s1.x+s1.z*fractions[edge],s1.y,half_depth*depths[edge])
			var c: Vector3 = b-Vector3(0,0,2*half_depth*depths[edge])
			var d: Vector3 = a-Vector3(0,0,2*half_depth*depths[edge])
			Panels._quad(tool,a,b,c,d,Vector3(-1 if edge==0 else 1,0,0),_color(.85 if edge==0 else 1.12))

static func _build_matchlock(builders: Dictionary, stage: int) -> void:
	var stock: PackedVector2Array = PackedVector2Array([Vector2(-0.057,-0.395),Vector2(0.044,-0.366),Vector2(0.040,-0.108),Vector2(0.025,0.27),Vector2(0.021,0.55),Vector2(-0.018,0.56),Vector2(-0.023,0.075),Vector2(-0.043,-0.073)])
	_polygon(builders,"weapon","wood",stock,0.052,Vector3(0,0,0.018),0.91)
	var muzzle: float = 0.79+stage*0.028
	_rod(builders,"weapon","metal",Vector3(0,-0.037,-0.025),Vector3(0,muzzle,-0.025),0.017,0.42)
	for y in [0.10,0.34,0.56]:
		_rod(builders,"weapon","gold",Vector3(0,y,-0.025),Vector3(0,y+0.013,-0.025),0.019,0.55)
	_rod(builders,"weapon","wood",Vector3(0,0.02,0.056),Vector3(0,0.69,0.056),0.006,0.70)
	# Side-mounted pan, serpentine match holder, and a curved trigger guard.
	_rod(builders,"weapon","metal",Vector3(0.034,0.037,-0.01),Vector3(0.066,0.037,-0.01),0.015,0.52)
	_rod(builders,"weapon","metal",Vector3(0.048,-0.036,0.004),Vector3(0.059,0.036,0.004),0.006,0.51)
	_rod(builders,"weapon","metal",Vector3(0.059,0.036,0.004),Vector3(0.043,0.076,-0.015),0.005,0.51)
	_rod(builders,"weapon","cord",Vector3(0.043,0.076,-0.015),Vector3(0.045,0.030,-0.025),0.003,0.75)
	_ring(builders,"weapon","metal",Vector3(0,-0.104,0.053),0.035,0.0035,Vector3.RIGHT,0.52,PI*0.10,PI*1.78)
	_rod(builders,"weapon","metal",Vector3(0,-0.09,0.048),Vector3(0,-0.118,0.064),0.004,0.49)
	if stage==2:
		_profile_cap(builders,"weapon","gold",[Vector2(0.020,muzzle-0.013),Vector2(0.020,muzzle+0.001)],1,0.60,0,TAU,Vector3(0,0,-0.025))

static func _build_headgear(builders: Dictionary, type: String, stage: int) -> void:
	if type=="archer" and stage<2:
		# The existing face helper owns the archer's hachimaki and topknot.
		return
	if type=="ninja":
		_build_hood(builders,stage)
		return
	if type=="monk":
		# A pale cloth zukin stays open around the face at every training stage.
		# The actor owns the fabric palette; this avoids the old dark ninja cap.
		_build_hood(builders,stage,false,1.05)
		_build_cowl_drape(builders,stage)
		return
	if type in ["spear","gunner"] or (type=="archer" and stage==2):
		var brim: float = 0.183+stage*0.012
		_profile_cap(builders,"head","lacquer",[Vector2(brim,0.079),Vector2(brim-0.013,0.092),Vector2(0.061,0.168),Vector2(0.004,0.184)],0.96,0.81)
		for side in [-1.0,1.0]:
			_rod(builders,"head","cord",Vector3(side*0.084,0.077,0.015),Vector3(side*0.042,-0.075,-0.030),0.003,0.61)
		return
	# A smoothly domed suji-bachi and its low curved brow visor read as armour,
	# rather than a cap stacked on top of a face.
	var crown_profile: Array[Vector2] = []
	var crown_rows: int = 10 if _detail_enabled else 5
	for row in range(crown_rows+1):
		var angle: float = lerpf(0.05,PI*0.5-0.015,float(row)/crown_rows)
		crown_profile.append(Vector2(0.143*cos(angle),0.085+0.145*sin(angle)))
	_profile_cap(builders,"head","lacquer",crown_profile,0.96,0.92)
	var ribs: int = 12 if _detail_enabled else 8
	var sections: int = 5 if _detail_enabled else 3
	for rib in range(ribs):
		var around: float = TAU*float(rib)/ribs
		for section in range(sections):
			var a0: float = lerpf(0.14,1.36,float(section)/sections)
			var a1: float = lerpf(0.14,1.36,float(section+1)/sections)
			var p0: Vector3 = Vector3(cos(around)*0.144*cos(a0),0.085+0.146*sin(a0),sin(around)*0.139*cos(a0))
			var p1: Vector3 = Vector3(cos(around)*0.144*cos(a1),0.085+0.146*sin(a1),sin(around)*0.139*cos(a1))
			_rod(builders,"head","metal",p0,p1,0.0019,0.62)
	var visor: Array = []
	var visor_columns: int = 12 if _detail_enabled else 6
	var visor_rows: int = 3 if _detail_enabled else 2
	for row in range(visor_rows+1):
		var v: float = float(row)/visor_rows
		for column in range(visor_columns+1):
			var u: float = lerpf(-1,1,float(column)/visor_columns)
			visor.append(Vector3(u*(0.133+v*0.016),0.099-0.021*u*u+0.008*v,-0.105-0.077*v*(1-0.50*u*u)))
	Panels._patch(_tool(builders,"head","lacquer"),visor,visor_columns,visor_rows,Vector3.UP,0.96,0.004)
	for row in range(3):
		for segment in range(7):
			var a0: float = -0.07+PI*float(segment)/7+0.030
			var a1: float = -0.07+PI*float(segment+1)/7-0.030
			_profile_cap(builders,"head","lacquer",[Vector2(0.166+row*0.006,-0.057+row*0.048),Vector2(0.160+row*0.006,-0.018+row*0.048)],0.80,0.80,a0,a1-a0)
	# Raised leather bindings and paired odoshi connect the shikoro lames.
	for column in range(8):
		var a: float = 0.12+PI*float(column)/7
		for row in range(2):
			var y: float = -0.029+float(row)*0.048
			var radius: float = 0.169+float(row)*0.006
			var p0: Vector3 = Vector3(cos(a-0.026)*radius,y-0.015,sin(a-0.026)*radius*0.80)
			var p1: Vector3 = Vector3(cos(a+0.026)*radius,y+0.016,sin(a+0.026)*radius*0.80)
			_rod(builders,"head","cord",p0,p1,0.0025,0.88)
	for side in [-1.0,1.0]:
		var cheek_wing: Array = []
		for row in range(4):
			var v: float = float(row)/3
			for column in range(5):
				var u: float = float(column)/4
				cheek_wing.append(Vector3(side*(0.145+v*0.025),0.042+v*0.067,-0.018-u*0.057+0.004*sin(v*PI)))
		Panels._patch(_tool(builders,"head","lacquer"),cheek_wing,4,3,Vector3(side,0,0),0.86,0.004)
		_stud(builders,"head","metal",Vector3(side*0.171,0.095,-0.047),Vector3(side,0,0),0.0034,0.62)

static func _build_hood(builders: Dictionary, stage: int, mask_enabled: bool = true, cloth_tint: float = 0.66) -> void:
	var points: Array = []
	var rows: int = 12 if _detail_enabled else 6
	var columns: int = 32 if _detail_enabled else 16
	for row in range(rows+1):
		var v: float = float(row)/rows
		for column in range(columns+1):
			var theta: float = TAU*float(column)/columns
			var front: float = maxf(cos(theta),0)
			var hem: float = lerpf(-0.115,0.119,pow(front,3.0))
			var y: float = lerpf(hem,0.207,v)
			var q: float = clampf((y-0.039)/0.170,-0.98,0.999)
			var radius: float = sqrt(maxf(0.002,1-q*q))
			var fold: float = 0.0025*sin(theta*7+v*3.1)*sin(PI*v)
			points.append(Vector3(sin(theta)*(0.120*radius+fold),y,-cos(theta)*(0.111*radius+fold)))
	_radial_grid(_tool(builders,"head","cloth"),points,columns,rows,Vector3(0,0.039,0),cloth_tint)
	if mask_enabled:
		var mask: Array = []
		for row in range(5):
			var v: float = float(row)/4
			for column in range(13):
				var u: float = lerpf(-1,1,float(column)/12)
				mask.append(Vector3(u*0.095,lerpf(-0.082,0.033,v),-0.122+0.035*u*u-0.003*sin(v*PI)*sin(u*PI)))
		Panels._patch(_tool(builders,"head","cloth"),mask,12,4,Vector3.FORWARD,0.58,0.003)
	if stage>0 and mask_enabled:
		_polygon(builders,"head","metal",PackedVector2Array([Vector2(-0.039,0.108),Vector2(0.039,0.108),Vector2(0.035,0.126),Vector2(-0.035,0.126)]),0.003,Vector3(0,0,-0.098),0.43)

static func _build_cowl_drape(builders: Dictionary, stage: int) -> void:
	# Folds join the rear hood to the shoulders without hiding eyes or mouth.
	var columns: int = 12 if _detail_enabled else 6
	var rows: int = 5 if _detail_enabled else 3
	var points: Array = []
	for row in range(rows+1):
		var v: float = float(row)/rows
		for column in range(columns+1):
			var theta: float = lerpf(-PI*.12,PI*1.12,float(column)/columns)
			var radius: float = lerpf(.098,.147+stage*.005,v)
			points.append(Vector3(cos(theta)*radius,lerpf(-.058,-.161-stage*.004,v)+.010*sin(theta*6.0)*sin(v*PI),sin(theta)*radius*.79))
	_radial_grid(_tool(builders,"head","cloth"),points,columns,rows,Vector3(0,-.04,0),.98)

static func _radial_grid(tool: SurfaceTool, points: Array, columns: int, rows: int, center: Vector3, tint: float) -> void:
	var normals: Array = []
	var uvs: Array = []
	var colors: Array = []
	for row in range(rows+1):
		for column in range(columns+1):
			var index: int = row*(columns+1)+column
			var du: Vector3 = points[row*(columns+1)+mini(columns,column+1)]-points[row*(columns+1)+maxi(0,column-1)]
			var dv: Vector3 = points[mini(rows,row+1)*(columns+1)+column]-points[maxi(0,row-1)*(columns+1)+column]
			var normal: Vector3 = du.cross(dv).normalized()
			var outward: Vector3 = points[index]-center
			if normal.dot(outward)<0:
				normal = -normal
			if normal.length_squared()<0.5: normal = outward.normalized()
			normals.append(normal)
			uvs.append(Vector2(float(column)/columns,float(row)/rows))
			colors.append(_color(tint))
	for row in range(rows):
		for column in range(columns):
			var a: int = row*(columns+1)+column
			var b: int = a+1
			var d: int = a+columns+1
			var c: int = d+1
			Panels._triangle(tool,points,normals,uvs,colors,a,b,c)
			Panels._triangle(tool,points,normals,uvs,colors,a,c,d)

static func _build_outfit(builders: Dictionary, type: String, stage: int) -> void:
	if type=="archer":
		_build_quiver(builders,stage)
	elif type=="gunner":
		_build_bandolier(builders,stage)
	elif type=="monk":
		_build_sash(builders,"cloth",0.091,0.084,0.71)
		var beads: int = 12+stage*2
		for index in range(beads):
			var angle: float = PI*float(index)/float(beads-1)
			_append(builders,"torso","wood",_sphere(0.010,0.020),Vector3(cos(angle)*0.088,0.122-sin(angle)*0.093,-0.142),Vector3.ZERO,Vector3.ONE,0.60)
	elif type=="ninja":
		_build_sash(builders,"leather",0.018,0.021,0.57)
		var scarf: Array = []
		for row in range(9):
			var v: float = float(row)/8
			for column in range(3):
				var u: float = float(column)/2
				scarf.append(Vector3(0.072+u*0.037+0.025*sin(v*PI),0.228-v*(0.29+0.045*stage),0.074+v*0.18))
		Panels._patch(_tool(builders,"torso","cloth"),scarf,2,8,Vector3.BACK,0.56,0.002)
	elif type=="commander":
		_build_banner(builders,0.135,0.11,0.44+stage*0.06,0.73)
	elif type=="naginata":
		_build_sash(builders,"cord",0.027,0.020,0.64)

static func _build_sash(builders: Dictionary, material: String, top_width: float, bottom_width: float, tint: float) -> void:
	var points: Array = []
	for row in range(9):
		var t: float = float(row)/8
		var y: float = lerpf(-0.127,0.189,t)
		var x: float = lerpf(-0.146,0.139,t)
		var width: float = lerpf(bottom_width,top_width,t)
		for column in range(3):
			var px: float = x+lerpf(-width*0.5,width*0.5,float(column)/2)
			var profile: Vector2 = Panels._profile(y)
			points.append(Panels._body_point(0,px/(profile.x*0.93),y,0.016))
	Panels._patch(_tool(builders,"torso",material),points,2,8,Vector3.FORWARD,tint,0.004)

static func _build_quiver(builders: Dictionary, stage: int) -> void:
	_rod(builders,"torso","leather",Vector3(0.12,-0.096,0.188),Vector3(0.16,0.276,0.182),0.047,0.76,0.052)
	var count: int = 4+stage*2
	for index in range(count):
		var x: float = 0.143+0.023*cos(float(index)*TAU/count)
		var z: float = 0.186+0.024*sin(float(index)*TAU/count)
		_rod(builders,"torso","wood",Vector3(x,0.06,z),Vector3(x+0.032,0.407+float(index%3)*0.018,z),0.0032,0.80)
		_polygon(builders,"torso","cloth",PackedVector2Array([Vector2(-0.009,0),Vector2(-0.009,0.052),Vector2(0.009,0.042),Vector2(0.009,0)]),0.002,Vector3(x+0.028,0.350+float(index%3)*0.018,z),0.74)

static func _build_bandolier(builders: Dictionary, stage: int) -> void:
	_build_sash(builders,"leather",0.033,0.035,0.75)
	for index in range(5+stage*2):
		var t: float = float(index)/float(5+stage*2)
		var y: float = lerpf(-0.097,0.16,t)
		var x: float = lerpf(-0.132,0.139,t)
		_rod(builders,"torso","wood",Vector3(x,y-0.026,-0.168),Vector3(x,y+0.013,-0.168),0.010,0.80)
	if stage>0:
		_append(builders,"pelvis","wood",_sphere(0.042,0.103),Vector3(-0.229,-0.08,-0.11),Vector3(0,0,-0.13),Vector3(0.72,1,0.66),0.72)
		_rod(builders,"pelvis","cord",Vector3(-0.219,0.043,-0.11),Vector3(-0.229,-0.031,-0.11),0.003,0.65)

static func _build_banner(builders: Dictionary, x: float, width: float, height: float, tint: float) -> void:
	_rod(builders,"torso","wood",Vector3(x,-0.15,0.173),Vector3(x,0.18+height,0.173),0.009,0.85)
	var points: Array = []
	for row in range(7):
		var v: float = float(row)/6
		for column in range(5):
			var u: float = float(column)/4
			points.append(Vector3(x+u*width,0.22+height-v*height,0.176+0.009*sin(u*PI*2)*sin(v*PI)))
	Panels._patch(_tool(builders,"torso","cloth"),points,4,6,Vector3.BACK,tint,0.0015)
	# A physical round crest contrasts with the tall rectangular banner outline.
	_append(builders,"torso","gold",_sphere(width*0.25,width*0.50),Vector3(x+width*0.52,0.24+height*0.63,0.161),Vector3.ZERO,Vector3(1,1,0.10),0.62)

static func _build_evolution(builders: Dictionary, type: String, stage: int) -> void:
	_build_historic_crest(builders,type,stage)
	if stage==0:
		return
	if type in ["gunner","archer"]:
		_polygon(builders,"head","lacquer",PackedVector2Array([Vector2(-0.036,0.15),Vector2(0.036,0.15),Vector2(0.029,0.225+stage*0.016),Vector2(-0.029,0.225+stage*0.016)]),0.013,Vector3(0,0,-0.104),0.89)
	elif type=="monk":
		_build_banner(builders,-0.168,0.062,0.247+stage*0.048,0.75)
	elif type=="ninja":
		_rod(builders,"head","metal",Vector3(-0.035,0.119,-0.103),Vector3(0.035,0.119,-0.103),0.004,0.50)
	# Additional front thigh guards and upper breast pieces alter coverage, not colour.
	if type not in ["monk","ninja","archer"]:
		for side in [-1.0,1.0]:
			var bone_name: String = "thighL" if side<0 else "thighR"
			var points: Array = []
			for row in range(4):
				var v: float = float(row)/3
				for column in range(5):
					var u: float = lerpf(-1,1,float(column)/4)
					# Haidate follows the actual thigh, rather than hanging almost
					# a hand's width in front of the trousers.
					points.append(Vector3(side*0.010+u*(0.049+stage*0.005),lerpf(-0.219,-0.308-stage*0.021,v),-lerpf(.090,.072,v)+.021*u*u))
			Panels._patch(_tool(builders,bone_name,"lacquer"),points,4,3,Vector3.FORWARD,0.81,0.005)
	if stage==2:
		if type=="ninja":
			var star: PackedVector2Array = PackedVector2Array([Vector2(0,0.034),Vector2(0.008,0.008),Vector2(0.034,0),Vector2(0.008,-0.008),Vector2(0,-0.034),Vector2(-0.008,-0.008),Vector2(-0.034,0),Vector2(-0.008,0.008)])
			for index in range(3):
				_polygon(builders,"pelvis","metal",star,0.003,Vector3(-0.165+index*0.034,-0.008,-0.149),0.48)
		elif type=="archer":
			_build_sash(builders,"leather",0.038,0.032,0.69)
		elif type=="commander":
			_build_banner(builders,-0.16,0.074,0.43,0.76)
		elif type=="spear":
			_polygon(builders,"weapon","cloth",PackedVector2Array([Vector2(0,0.78),Vector2(0.18,0.91),Vector2(0.15,0.77),Vector2(0.18,0.65),Vector2(0,0.73)]),0.002,Vector3(0,0,0.006),0.81)
		elif type=="naginata":
			_build_banner(builders,-0.15,0.076,0.31,0.77)
		elif type=="samurai":
			_build_banner(builders,0.12,0.084,0.32,0.79)

static func _build_historic_crest(builders: Dictionary, type: String, stage: int) -> void:
	# Original class designs borrow compact clan motifs, not a claimed replica
	# of an individual warrior's surviving armour. No shared giant fantasy V.
	if type=="spear":
		var radius: float = .0105+stage*.0012
		var spacing: float = radius*2.35
		for row in range(2):
			for column in range(3):
				_coin_crest(builders,Vector3((column-1)*spacing,.142+row*spacing,-.123),radius)
	elif type=="samurai":
		var scale: float = 1.0+stage*.12
		var center: Vector3 = Vector3(0,.174+stage*.008,-.147)
		for petal in range(5):
			var angle: float = -PI*.5+TAU*float(petal)/5
			var petal_center: Vector3 = center+Vector3(cos(angle)*.0205*scale,sin(angle)*.0205*scale,0)
			_ring(builders,"head","gold",petal_center,.0125*scale,.0023,Vector3.FORWARD,.82)
		_ring(builders,"head","gold",center,.010*scale,.0020,Vector3.FORWARD,.80)
		_rod(builders,"head","metal",Vector3(0,.130,-.139),Vector3(0,.151,-.145),.006,.58)
	elif type=="commander":
		var scale: float = 1.0+stage*.14
		var center: Vector3 = Vector3(0,.173+stage*.009,-.148)
		for offset in [Vector2(-.022,0),Vector2(.022,0),Vector2(0,-.020),Vector2(0,.020)]:
			var shape: PackedVector2Array = PackedVector2Array()
			for point in [Vector2(-.019,0),Vector2(0,-.016),Vector2(.019,0),Vector2(0,.016)]:
				shape.append((point+offset)*scale)
			_polygon(builders,"head","gold",shape,.004,center,.80)
		_rod(builders,"head","metal",Vector3(0,.127,-.138),Vector3(0,.148,-.144),.008,.58)
	elif type=="naginata":
		var height: float = .216+stage*.014
		for side in [-1.0,1.0]:
			_polygon(builders,"head","gold",PackedVector2Array([
				Vector2(side*.025,.141),Vector2(side*.045,.160),
				Vector2(side*.076,height),Vector2(side*.070,height-.024),
				Vector2(side*.046,.187),Vector2(side*.019,.168)]),.006,Vector3(0,0,-.144),.78)

static func _coin_crest(builders: Dictionary, center: Vector3, radius: float) -> void:
	# A thin pierced copper/gold coin retains the square hole of the motif.
	var tool: SurfaceTool = _tool(builders,"head","gold")
	var segments: int = 16 if _detail_enabled else 8
	for side in [-1.0,1.0]:
		var points: Array = []
		var normals: Array = []
		var uvs: Array = []
		var colors: Array = []
		for index in range(segments+1):
			var angle: float = TAU*float(index)/segments
			var direction: Vector2 = Vector2(cos(angle),sin(angle))
			var hole_radius: float = radius*.25/maxf(absf(direction.x),absf(direction.y))
			for distance in [hole_radius,radius]:
				points.append(center+Vector3(direction.x*distance,direction.y*distance,side*.0013))
				normals.append(Vector3(0,0,side))
				uvs.append(direction*distance/(radius*2)+Vector2(.5,.5))
				colors.append(_color(.84 if side<0 else .71))
		for index in range(segments):
			var a: int = index*2
			Panels._triangle(tool,points,normals,uvs,colors,a,a+1,a+3)
			Panels._triangle(tool,points,normals,uvs,colors,a,a+3,a+2)

static func _build_evolution_guards(builders: Dictionary, type: String, stage: int) -> void:
	var light: bool = type in ["archer","monk","ninja"]
	var extent: float = .56 if type=="archer" else .66 if light else (.73 if type=="gunner" else .86)
	var material: String = "cloth" if type=="monk" else "leather" if type=="ninja" else "lacquer"
	var rows: int = 1+stage if light else 3+stage
	var surface_columns: int = 8 if _detail_enabled else 4
	var surface_rows: int = 3 if _detail_enabled else 2
	# Sode fit the shoulder instead of floating as wide rectangular wings.
	# Their rounded corners, top ridge, lacing and lower leather edge are mesh.
	for side in [-1.0,1.0]:
		var suffix: String = "L" if side<0 else "R"
		var shoulder: SurfaceTool = _tool(builders,"arm"+suffix,material)
		# Two thick leather hangers seat the sode on the sleeve cap. They also
		# provide visible attachment when the upper arm swings away from the do.
		for strap_z in [-0.049,0.049]:
			var hanger: Array = []
			for row in range(5):
				var v: float = float(row)/4
				for column in range(3):
					var z: float = strap_z+lerpf(-.010,.010,float(column)/2)*extent
					hanger.append(Vector3(side*lerpf(.030*extent,(.077+stage*.006)*extent,v),.025+.009*sin(v*PI)-.048*v,z))
			Panels._patch(_tool(builders,"arm"+suffix,"leather"),hanger,2,4,Vector3.UP,.82,.004)
			_stud(builders,"arm"+suffix,"metal",Vector3(side*(.077+stage*.006)*extent,-.020,strap_z),Vector3.UP,.003,.63)
		for plate in range(rows):
			var points: Array = []
			var top: float = -.015-float(plate)*.034
			var half_depth: float = (.073+stage*.006)*extent
			for row in range(surface_rows+1):
				var v: float = float(row)/surface_rows
				for column in range(surface_columns+1):
					var u: float = lerpf(-1,1,float(column)/surface_columns)
					points.append(_sode_point(side,extent,stage,plate,top,half_depth,u,v))
			Panels._patch(shoulder,points,surface_columns,surface_rows,Vector3(side,0,0),0.98,0.004)
			for lace in [-1.0,1.0]:
				var z: float = lace*half_depth*0.64
				var start: Vector3 = _sode_point(side,extent,stage,plate,top,half_depth,lace*.64-.08,.86)+Vector3(side*.003,0,0)
				var end: Vector3 = _sode_point(side,extent,stage,plate,top,half_depth,lace*.64+.08,.12)+Vector3(side*.003,0,0)
				_rod(builders,"arm"+suffix,"cord",start,end,.0028,.93)
				_stud(builders,"arm"+suffix,"metal",_sode_point(side,extent,stage,plate,top,half_depth,z/half_depth,.45)+Vector3(side*.003,0,0),Vector3(side,0,0),.0028,.60)
			for section in range(4):
				var u0: float = lerpf(-.87,.87,float(section)/4)
				var u1: float = lerpf(-.87,.87,float(section+1)/4)
				_rod(builders,"arm"+suffix,"leather",_sode_point(side,extent,stage,plate,top,half_depth,u0,.88)+Vector3(side*.003,0,0),_sode_point(side,extent,stage,plate,top,half_depth,u1,.88)+Vector3(side*.003,0,0),.0026,.77)
		_build_limb_guard(builders,"fore"+suffix,material,stage,-0.036,-0.237,0.054*extent,0.056,0.94)
		_build_limb_guard(builders,"shin"+suffix,material,stage,-0.068,-0.366,0.055*extent,0.068,0.91)
	# Trained armour adds raised upper gussets, leaving the laced do readable.
	if not light and stage>0:
		for side in [-1.0,1.0]:
			var points: Array = []
			for row in range(5):
				var v: float = float(row)/4
				for column in range(6):
					var u: float = side*lerpf(0.47,0.91,float(column)/5)
					var y: float = lerpf(0.076,0.178,v)+0.007*(1-u*u)*v
					points.append(Panels._body_point(0,u,y,0.011+stage*0.002))
			Panels._patch(_tool(builders,"torso","lacquer"),points,5,4,Vector3.FORWARD,1.02,0.004)
			for u in [side*0.58,side*0.81]:
				_stud(builders,"torso","metal",Panels._body_point(0,u,0.147,0.017),Vector3.FORWARD,0.0032,0.64)

static func _sode_point(side: float, extent: float, stage: int, plate: int, top: float, half_depth: float, u: float, v: float) -> Vector3:
	# A close-fitting convex cap slopes down from the deltoid. The hanging
	# lames are compact and curve around the arm instead of forming box wings.
	var outward: float = (.068+stage*.006+.011*sin(v*PI*.5)+.005*(1-u*u)-plate*.002)*extent
	var y: float = top-v*.040+.011*pow(absf(u),4)-.007*(1-u*u)
	return Vector3(side*outward,y,u*half_depth)

static func _build_limb_guard(builders: Dictionary, bone: String, material: String, stage: int, top: float, bottom: float, half_width: float, depth: float, tint: float) -> void:
	var tool: SurfaceTool = _tool(builders,bone,material)
	var columns: int = 4 if _detail_enabled else 2
	var rows: int = 8 if _detail_enabled else 4
	# Three slender longitudinal splints surround fabric and cross-laced straps.
	for plate in range(3):
		var points: Array = []
		for row in range(rows+1):
			var v: float = float(row)/rows
			var y: float = lerpf(bottom,top,v)
			var taper: float = _guard_contour(v)
			for column in range(columns+1):
				var u: float = lerpf(-0.97+plate*0.66,-0.39+plate*0.66,float(column)/columns)
				var corner: float = 0.007*pow(absf(float(column)*2/columns-1),4)
				var edge_y: float = y+corner*(1-v)-corner*v
				points.append(Vector3(u*half_width*(1+stage*0.07)*taper,edge_y,-depth*taper*(1-0.28*u*u)-0.004-stage*0.002))
		Panels._patch(tool,points,columns,rows,Vector3.FORWARD,tint,0.004)
		for v in [0.14,0.86]:
			var u: float = -0.68+plate*0.66
			var y: float = lerpf(bottom,top,v)
			var x: float = u*half_width*(1+stage*0.07)*_guard_contour(v)
			var z: float = -depth*_guard_contour(v)*(1-0.28*u*u)-0.009-stage*0.002
			_stud(builders,bone,"metal",Vector3(x,y,z),Vector3.FORWARD,0.0026,0.61)
	for v in [0.19,0.78]:
		var y: float = lerpf(bottom,top,v)
		for section in range(8):
			var a0: float = PI+PI*float(section)/8
			var a1: float = PI+PI*float(section+1)/8
			var radius: float = half_width*(1+stage*.07)*_guard_contour(v)+.003
			var p0: Vector3 = Vector3(cos(a0)*radius,y,sin(a0)*(depth*_guard_contour(v)+0.010))
			var p1: Vector3 = Vector3(cos(a1)*radius,y,sin(a1)*(depth*_guard_contour(v)+0.010))
			_rod(builders,bone,"leather",p0,p1,0.0034,0.76)
		_rod(builders,bone,"cord",Vector3(-0.013,y-0.009,-depth*_guard_contour(v)-0.016),Vector3(0.013,y+0.010,-depth*_guard_contour(v)-0.016),0.0024,0.91)

static func _guard_contour(v: float) -> float:
	return lerpf(.58,1.0,v)+.20*sin(PI*v)

static func _stud(builders: Dictionary, bone: String, material: String, origin: Vector3, normal: Vector3, radius: float, tint: float) -> void:
	Panels._stud(_tool(builders,bone,material),origin,normal,radius,radius*0.45,tint,8 if _detail_enabled else 4)
