extends RefCounted
## Rigid, adult-sized do and kusazuri pieces in the existing joint spaces.
## Front/back plates use Cartesian curved patches, rather than continuous rings.

static var _cache: Dictionary = {}

static func build(light_armour: bool = false, detail_enabled: bool = true) -> Array[Dictionary]:
	var cache_key: String = str(light_armour)+"/"+str(detail_enabled)
	if _cache.has(cache_key):
		return _cache[cache_key]
	var builders: Dictionary = {}
	_build_cloth_body(builders,detail_enabled)
	_build_chest(builders,light_armour,detail_enabled)
	_build_straps(builders)
	_build_skirt(builders,light_armour,detail_enabled)
	var pieces: Array[Dictionary] = []
	for key in builders:
		var entry: Dictionary = builders[key]
		var tool: SurfaceTool = entry.tool
		tool.index()
		tool.generate_tangents()
		pieces.append({"bone":entry.bone,"material":entry.material,"mesh":tool.commit()})
	_cache[cache_key] = pieces
	return pieces

static func _surface(builders: Dictionary, bone: String, material: String) -> SurfaceTool:
	var key: String = bone+"/"+material
	if not builders.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders[key] = {"tool":tool,"bone":bone,"material":material}
	return builders[key].tool

static func _vertex(tool: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, color: Color) -> void:
	tool.set_normal(normal.normalized())
	tool.set_uv(uv)
	tool.set_color(color)
	tool.add_vertex(point)

static func _triangle(tool: SurfaceTool, points: Array, normals: Array, uvs: Array, colors: Array, a: int, b: int, c: int) -> void:
	var cross_value: Vector3 = (points[b]-points[a]).cross(points[c]-points[a])
	if cross_value.length_squared()<0.000000000001:
		return
	# Godot front faces wind clockwise; normals are explicitly outward.
	if cross_value.dot(normals[a]+normals[b]+normals[c])>0.0:
		var saved: int = b
		b = c
		c = saved
	for index in [a,b,c]:
		_vertex(tool,points[index],normals[index],uvs[index],colors[index])

static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color = Color.WHITE) -> void:
	var points: Array = [a,b,c,d]
	var normals: Array = [outward,outward,outward,outward]
	var uvs: Array = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	var colors: Array = [color,color,color,color]
	_triangle(tool,points,normals,uvs,colors,0,1,2)
	_triangle(tool,points,normals,uvs,colors,0,2,3)

static func _patch(tool: SurfaceTool, points: Array, columns: int, rows: int, outward: Vector3, tint: float = 1.0, thickness: float = 0.0) -> void:
	var normals: Array = []
	var uvs: Array = []
	var colors: Array = []
	for row in range(rows+1):
		for column in range(columns+1):
			var left: int = row*(columns+1)+maxi(0,column-1)
			var right: int = row*(columns+1)+mini(columns,column+1)
			var below: int = maxi(0,row-1)*(columns+1)+column
			var above: int = mini(rows,row+1)*(columns+1)+column
			var du: Vector3 = points[right]-points[left]
			var dv: Vector3 = points[above]-points[below]
			var normal: Vector3 = du.cross(dv).normalized()
			if normal.dot(outward)<0.0:
				normal = -normal
			if normal.length_squared()<0.5:
				normal = outward
			normals.append(normal)
			var u: float = float(column)/columns
			var v: float = float(row)/rows
			uvs.append(Vector2(u,v))
			var shade: float = tint*(0.94+0.06*sin(PI*u)*sin(PI*v))
			colors.append(Color(shade,shade,shade,1))
	for row in range(rows):
		for column in range(columns):
			var a: int = row*(columns+1)+column
			var b: int = a+1
			var d: int = a+columns+1
			var c: int = d+1
			_triangle(tool,points,normals,uvs,colors,a,b,c)
			_triangle(tool,points,normals,uvs,colors,a,c,d)
	if thickness<=0.0:
		return
	var perimeter: Array[int] = []
	for column in range(columns+1):
		perimeter.append(column)
	for row in range(1,rows+1):
		perimeter.append(row*(columns+1)+columns)
	for column in range(columns-1,-1,-1):
		perimeter.append(rows*(columns+1)+column)
	for row in range(rows-1,0,-1):
		perimeter.append(row*(columns+1))
	var center: Vector3 = Vector3.ZERO
	for point in points:
		center += point
	center /= points.size()
	for cursor in range(perimeter.size()):
		var a: int = perimeter[cursor]
		var b: int = perimeter[(cursor+1)%perimeter.size()]
		var edge_normal: Vector3 = ((points[a]+points[b])*0.5-center)
		edge_normal -= outward*edge_normal.dot(outward)
		if edge_normal.length_squared()<0.000001:
			edge_normal = Vector3.UP
		_quad(tool,points[a],points[b],points[b]-normals[b]*thickness,points[a]-normals[a]*thickness,edge_normal.normalized(),Color(tint*0.66,tint*0.66,tint*0.66,1))

static func _profile(y: float) -> Vector2:
	# The lower ribs narrow into a real waist; the breast is broad but shallow.
	var levels: Array[Vector3] = [Vector3(-0.155,0.143,0.084),Vector3(-0.065,0.154,0.092),Vector3(0.025,0.177,0.108),Vector3(0.110,0.184,0.112),Vector3(0.176,0.174,0.102),Vector3(0.220,0.151,0.078)]
	for index in range(levels.size()-1):
		if y<=levels[index+1].x:
			var t: float = clampf((y-levels[index].x)/(levels[index+1].x-levels[index].x),0,1)
			return Vector2(lerpf(levels[index].y,levels[index+1].y,t),lerpf(levels[index].z,levels[index+1].z,t))
	return Vector2(levels[-1].y,levels[-1].z)

static func _body_point(face: int, u: float, y: float, offset: float = 0.0) -> Vector3:
	var size: Vector2 = _profile(y)
	if face<2:
		var sign_z: float = -1.0 if face==0 else 1.0
		var breast_curve: float = size.y*sqrt(maxf(.28,1.0-.66*u*u))
		if face==0:
			breast_curve += 0.004*exp(-pow((y-0.085)/0.095,2))*exp(-pow(u/0.75,2))
		return Vector3(u*size.x*0.94,y,sign_z*(breast_curve+offset))
	var sign_x: float = -1.0 if face==2 else 1.0
	return Vector3(sign_x*(size.x*(1.0-0.07*u*u)+offset),y,u*size.y*0.55)

static func _outward(face: int) -> Vector3:
	return [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT][face]

static func _build_cloth_body(builders: Dictionary, detail: bool = true) -> void:
	var tool: SurfaceTool = _surface(builders,"torso","cloth")
	var columns: int = 12 if detail else 8
	var rows: int = 8 if detail else 4
	for face in range(4):
		var points: Array = []
		for row in range(rows+1):
			var y: float = lerpf(-0.153,0.218,float(row)/rows)
			for column in range(columns+1):
				var u: float = lerpf(-1.0,1.0,float(column)/columns)
				points.append(_body_point(face,u,y))
		_patch(tool,points,columns,rows,_outward(face),0.79)
	# Folded kimono lapels stay visible above the plated breast.
	var lapel: SurfaceTool = _surface(builders,"torso","cloth")
	for side in [-1.0,1.0]:
		var points: Array = []
		for row in range(5):
			var t: float = float(row)/4
			var y: float = lerpf(0.077,0.219,t)
			var x: float = side*lerpf(0.038,0.093,t)
			var half: float = 0.016
			for column in range(3):
				var px: float = x+lerpf(-half,half,float(column)/2)
				var profile: Vector2 = _profile(y)
				points.append(_body_point(0,px/(profile.x*0.93),y,0.003))
		_patch(lapel,points,2,4,Vector3.FORWARD,1.05,0.004)

static func _build_chest(builders: Dictionary, light_armour: bool, detail: bool = true) -> void:
	var plate: SurfaceTool = _surface(builders,"torso","lacquer")
	var cord: SurfaceTool = _surface(builders,"torso","cord")
	var binding: SurfaceTool = _surface(builders,"torso","leather")
	var rivets: SurfaceTool = _surface(builders,"torso","metal")
	var row_count: int = 4 if light_armour else 6
	var top: float = 0.130 if light_armour else 0.181
	var around_segments: int = 6 if detail else 4
	var across_rows: int = 4 if detail else 2
	for face in range(4):
		for row in range(row_count):
			var y0: float = lerpf(-0.144,top,float(row)/row_count)+0.002
			var y1: float = lerpf(-0.144,top,float(row+1)/row_count)+0.005
			var columns: int = (18 if detail else 8) if face<2 else (8 if detail else 4)
			var points: Array = []
			for v_row in range(across_rows+1):
				var v: float = float(v_row)/across_rows
				for u_column in range(columns+1):
					var u: float = lerpf(-0.976,0.976,float(u_column)/columns)
					var y: float = lerpf(y0,y1,v)
					if row==row_count-1 and face<2:
						# The breast follows the sternum and drops away beneath the
						# armpits; a horizontal rectangular rim resembled a bucket.
						y += ((0.012 if face==0 else 0.004)*(1-u*u)-.032*pow(absf(u),3))*v
						u *= 1.0-.12*v*v
					# Raised rolled lower lip, shallow hammered curvature, tucked top.
					var lip: float = 0.0035*exp(-pow(v/0.16,2))
					var relief: float = 0.006+lip+0.002*sin(PI*v)
					points.append(_body_point(face,u,y,relief))
			_patch(plate,points,columns,across_rows,_outward(face),0.97+0.014*sin(float(row*3+face)),0.0045)
			# Each long lame has a leather edge and real countersunk fasteners.
			for u_column in range(columns):
				var u0: float = lerpf(-0.965,0.965,float(u_column)/columns)
				var u1: float = lerpf(-0.965,0.965,float(u_column+1)/columns)
				_rod(binding,_body_point(face,u0,y0+0.004,0.011),_body_point(face,u1,y0+0.004,0.011),0.0019,0.82,around_segments)
			if face<2:
				for u in ([-0.83,-0.45,0.45,0.83] if detail else [-0.58,0.58]):
					var at: Vector3 = _body_point(face,u,y1-0.009,0.011)
					_stud(rivets,at,_outward(face),0.0032,0.0014,0.66,8 if detail else 4)
					if row<row_count-1:
						var seam_y: float = y1-0.005
						_rod(cord,_body_point(face,u-0.021,seam_y-0.012,0.014),_body_point(face,u+0.020,seam_y+0.015,0.014),0.0027,0.95,around_segments)
						_rod(cord,_body_point(face,u+0.021,seam_y-0.012,0.015),_body_point(face,u-0.020,seam_y+0.015,0.015),0.0027,0.95,around_segments)
	# Soft-bound arm holes and side fastening avoid an exposed rectangular shell.
	for face in [0,1]:
		for side in [-1.0,1.0]:
			for segment in range(9):
				var y0: float = lerpf(-0.135,top,float(segment)/9)
				var y1: float = lerpf(-0.135,top,float(segment+1)/9)
				_rod(binding,_chest_edge_point(face,side,y0,top,row_count),_chest_edge_point(face,side,y1,top,row_count),0.0032,0.83,around_segments)

static func _chest_edge_point(face: int, side: float, y: float, top: float, row_count: int) -> Vector3:
	var final_row_start: float = -0.144+(top+.144)*float(row_count-1)/row_count
	var v: float = clampf((y-final_row_start)/(top-final_row_start),0,1)
	var u: float = side*.967
	var actual_y: float = y+((.012 if face==0 else .004)*(1-u*u)-.032*pow(absf(u),3))*v
	u *= 1.0-.12*v*v
	return _body_point(face,u,actual_y,.010)

static func _build_straps(builders: Dictionary) -> void:
	var leather: SurfaceTool = _surface(builders,"torso","leather")
	var paths: Array[Vector3] = [Vector3(0,0.091,-0.124),Vector3(0,0.153,-0.112),Vector3(0,0.216,-0.070),Vector3(0,0.237,0.0),Vector3(0,0.216,0.070),Vector3(0,0.150,0.112),Vector3(0,0.091,0.124)]
	for side in [-1.0,1.0]:
		var points: Array = []
		for row in range(paths.size()):
			for column in range(3):
				var x: float = side*0.119+lerpf(-0.012,0.012,float(column)/2)
				var z: float = paths[row].z
				if row<2 or row>4:
					var size: Vector2 = _profile(paths[row].y)
					z = _body_point(0 if row<2 else 1,x/(size.x*.94),paths[row].y,.013).z
				points.append(Vector3(x,paths[row].y,z))
		# The middle strip rounds over a sloping shoulder, clear of the collar.
		_patch(leather,points,2,paths.size()-1,Vector3.UP,0.69,0.004)

static func _skirt_point(face: int, u: float, y: float, offset: float = 0.0) -> Vector3:
	var t: float = clampf((-y-0.025)/0.207,0,1)
	var width: float = lerpf(0.195,0.207,t)
	var depth: float = lerpf(0.116,0.133,t)
	if face<2:
		var sign_z: float = -1.0 if face==0 else 1.0
		return Vector3(u*width*0.93,y,sign_z*(depth*(1.0-0.34*u*u)+offset))
	var sign_x: float = -1.0 if face==2 else 1.0
	return Vector3(sign_x*(width*(1.0-0.07*u*u)+offset),y,u*depth*0.66)

static func _build_skirt(builders: Dictionary, light_armour: bool, detail: bool = true) -> void:
	var cloth: SurfaceTool = _surface(builders,"pelvis","cloth")
	var panel: SurfaceTool = _surface(builders,"pelvis","lacquer")
	var cord: SurfaceTool = _surface(builders,"pelvis","cord")
	var binding: SurfaceTool = _surface(builders,"pelvis","leather")
	var rivets: SurfaceTool = _surface(builders,"pelvis","metal")
	var around_segments: int = 6 if detail else 4
	var columns: int = 6 if detail else 4
	var rows: int = 3 if detail else 2
	# Dark fabric is recessed behind the eight separately hanging kusazuri panels.
	for face in range(4):
		var lining: Array = []
		for row in range(5):
			var y: float = lerpf(-0.227,-0.026,float(row)/4)
			for column in range(9):
				var u: float = lerpf(-1.0,1.0,float(column)/8)
				var hem_lift: float = .025*exp(-pow(u/.19,2))*(1.0-float(row)/4) if face<2 else 0.0
				lining.append(_skirt_point(face,u,y+hem_lift,-0.006))
		_patch(cloth,lining,8,4,_outward(face),0.63)
		for split in range(2):
			var u0: float = -0.945 if split==0 else 0.062
			var u1: float = -0.062 if split==0 else 0.945
			var bottom: float = -0.216 if face<2 else -0.187
			for tier in range(4):
				var y0: float = lerpf(bottom,-0.029,float(tier)/4)+0.002
				var y1: float = lerpf(bottom,-0.029,float(tier+1)/4)+0.005
				var points: Array = []
				for row in range(rows+1):
					var v: float = float(row)/rows
					for column in range(columns+1):
						var across: float = float(column)/columns
						var u: float = lerpf(u0,u1,across)
						var y: float = lerpf(y0,y1,v)+0.010*pow(absf(across*2-1),4)*(1-v)
						var flare: float = 0.006+0.003*sin(float(column)/columns*PI)+0.002*(1-v)
						points.append(_skirt_point(face,u,y,flare))
				_patch(cloth if light_armour and face>=2 else panel,points,columns,rows,_outward(face),0.94+0.015*float(tier),0.004)
				for lace in [0.20,0.80]:
					var u: float = lerpf(u0,u1,lace)
					_stud(rivets,_skirt_point(face,u,y1-0.008,0.014),_outward(face),0.003,0.0013,0.68,8 if detail else 4)
			for lace in [0.20,0.80]:
				var u: float = lerpf(u0,u1,lace)
				for tier in range(3):
					var y: float = lerpf(bottom,-0.029,float(tier+1)/4)
					_rod(cord,_skirt_point(face,u-0.024,y-0.013,0.013),_skirt_point(face,u+0.024,y+0.012,0.013),0.0027,0.94,around_segments)
					_rod(cord,_skirt_point(face,u+0.024,y-0.013,0.014),_skirt_point(face,u-0.024,y+0.012,0.014),0.0027,0.94,around_segments)
			for edge in [u0,u1]:
				_rod(binding,_skirt_point(face,edge,bottom+0.012,0.010),_skirt_point(face,edge,-0.033,0.010),0.0022,0.75,around_segments)

static func _stud(tool: SurfaceTool, origin: Vector3, direction: Vector3, radius: float, height: float, tint: float = 1.0, segments: int = 8) -> void:
	var normal: Vector3 = direction.normalized()
	var tangent: Vector3 = normal.cross(Vector3.UP)
	if tangent.length_squared()<0.01:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent: Vector3 = normal.cross(tangent).normalized()
	for segment in range(segments):
		var angle0: float = TAU*float(segment)/segments
		var angle1: float = TAU*float(segment+1)/segments
		var rim0: Vector3 = tangent*cos(angle0)+bitangent*sin(angle0)
		var rim1: Vector3 = tangent*cos(angle1)+bitangent*sin(angle1)
		var points: Array = [origin+normal*height,origin+rim0*radius,origin+rim1*radius]
		var normals: Array = [normal,(normal*0.75+rim0*0.25).normalized(),(normal*0.75+rim1*0.25).normalized()]
		_triangle(tool,points,normals,[Vector2(.5,.5),Vector2(.5,.5)+Vector2(cos(angle0),sin(angle0))*.5,Vector2(.5,.5)+Vector2(cos(angle1),sin(angle1))*.5],[_grey(tint),_grey(tint),_grey(tint)],0,1,2)

static func _grey(value: float) -> Color:
	return Color(value,value,value,1)

static func _rod(tool: SurfaceTool, start: Vector3, end: Vector3, radius: float, tint: float = 1.0, segments: int = 6) -> void:
	var direction: Vector3 = (end-start).normalized()
	if start.distance_squared_to(end)<0.0000001:
		return
	var tangent: Vector3 = direction.cross(Vector3.UP)
	if tangent.length_squared()<0.01:
		tangent = direction.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent: Vector3 = direction.cross(tangent).normalized()
	for segment in range(segments):
		var angle0: float = TAU*float(segment)/segments
		var angle1: float = TAU*float(segment+1)/segments
		var normal0: Vector3 = tangent*cos(angle0)+bitangent*sin(angle0)
		var normal1: Vector3 = tangent*cos(angle1)+bitangent*sin(angle1)
		var points: Array = [start+normal0*radius,start+normal1*radius,end+normal1*radius,end+normal0*radius]
		var normals: Array = [normal0,normal1,normal1,normal0]
		var uvs: Array = [Vector2(float(segment)/segments,0),Vector2(float(segment+1)/segments,0),Vector2(float(segment+1)/segments,1),Vector2(float(segment)/segments,1)]
		var color: Color = Color(tint,tint,tint,1)
		var colors: Array = [color,color,color,color]
		_triangle(tool,points,normals,uvs,colors,0,1,2)
		_triangle(tool,points,normals,uvs,colors,0,2,3)
