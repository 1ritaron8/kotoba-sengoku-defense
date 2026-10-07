extends RefCounted
## Neutral adult head, facing -Z. Coordinates are already in the head bone's space.
## Each indexed mesh is batched by material, ready for SurfaceTool.append_from().

const CENTER = Vector3(0.0, 0.035, 0.0)
const HALF_HEIGHT = 0.125
const HALF_WIDTH = 0.100
const HALF_DEPTH = 0.084
const SEGMENTS = 72
const ROWS = 48
const EYE_X = 0.0345
const EYE_Y = 0.055
const EYE_HALF_WIDTH = 0.0186
const MATERIAL_RECIPE = {
	"skin":{"albedo":Color("bb9279"),"roughness":0.76,"metallic":0.0,"vertexColor":true,"detailKind":"skin"},
	"eye":{"albedo":Color("b7b4a9"),"roughness":0.30,"metallic":0.0,"vertexColor":true,"detailKind":"eye"},
	"iris":{"albedo":Color("342920"),"roughness":0.48,"metallic":0.0,"vertexColor":true},
	"hair":{"albedo":Color("24211c"),"roughness":0.80,"metallic":0.0,"vertexColor":true,"detailKind":"hair"},
	"lip":{"albedo":Color("956b5e"),"roughness":0.69,"metallic":0.0,"vertexColor":true,"detailKind":"lip"}
}
static var _cached: Dictionary = {}

static func material_recipe() -> Dictionary:
	return MATERIAL_RECIPE.duplicate(true)

static func build(high_detail: bool = true) -> Array[Dictionary]:
	if _cached.has(high_detail):
		return _cached[high_detail]
	var builders: Dictionary = {}
	for key in MATERIAL_RECIPE:
		var tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_smooth_group(0)
		builders[key] = tool
	_build_skull(builders.skin,high_detail)
	_build_hair(builders.hair,high_detail)
	for side in [-1.0, 1.0]:
		_build_ear(builders.skin,side,high_detail)
		_build_eye(builders,side,high_detail)
		_build_brow(builders.hair,side,high_detail)
		_build_nostril(builders.iris,side,high_detail)
		_build_lower_eye_fold(builders.skin,side,high_detail)
	_build_lips(builders,high_detail)
	var parts: Array[Dictionary] = []
	for key in MATERIAL_RECIPE:
		var tool: SurfaceTool = builders[key]
		tool.index()
		tool.generate_normals()
		tool.generate_tangents()
		parts.append({"mesh":tool.commit(),"material":key})
	_cached[high_detail] = parts
	return parts

static func _divisions(value: int, high_detail: bool) -> int:
	# Half-resolution preserves the connected nasal bridge, eyelids and adult
	# jaw planes. The old third-resolution head became a pointed diamond.
	return value if high_detail else maxi(1,int(round(float(value)*0.5)))

static func _bell(value: float, center: float, width: float) -> float:
	return exp(-pow((value-center)/width, 2.0))

static func _width_factor(q: float) -> float:
	# A narrower temporal/cheek envelope and a defined mandibular angle replace
	# the almost circular lower head. Height, attachment and helmet scale stay fixed.
	return 0.900 + 0.105*_bell(q,-0.54,0.24) + 0.025*_bell(q,0.27,0.24) - 0.040*_bell(q,-0.85,0.17) - 0.035*_bell(q,0.80,0.24)

static func _front_features(x: float, y: float) -> float:
	var depth = 0.0
	# The bridge, tip and alae are displacements of the skull, not separate beads.
	depth -= 0.0078*_bell(x,0.0,0.0100)*_bell(y,0.048,0.026)
	depth -= 0.0060*_bell(x,0.0,0.0074)*_bell(y,0.025,0.024)
	depth -= 0.0150*_bell(x,0.0,0.0098)*_bell(y,0.007,0.0105)
	depth -= 0.0062*_bell(absf(x),0.0108,0.0054)*_bell(y,-0.0005,0.0061)
	depth -= 0.0026*_bell(x,0.0,0.0040)*_bell(y,-0.006,0.0052)
	# Zygomatic, orbital, masseter and chin planes are part of one skin shell.
	depth -= 0.0043*_bell(absf(x),0.051,0.017)*_bell(y,0.025,0.019)
	depth -= 0.0045*_bell(absf(x),0.034,0.024)*_bell(y,0.076,0.013)
	depth += 0.0060*_bell(absf(x),EYE_X,0.020)*_bell(y,EYE_Y,0.012)
	depth -= 0.0017*_bell(absf(x),0.038,0.020)*_bell(y,0.039,0.009)
	depth += 0.0038*_bell(absf(x),0.063,0.018)*_bell(y,-0.005,0.029)
	depth -= 0.0040*_bell(absf(x),0.059,0.016)*_bell(y,-0.043,0.021)
	depth -= 0.0023*_bell(x,0.0,0.024)*_bell(y,-0.031,0.013)
	depth += 0.0017*_bell(x,0.0,0.0055)*_bell(y,-0.018,0.008)
	# The alar crease flows diagonally toward the mouth corner; it is a shallow
	# surface transition, not a separate nose bead or a painted outline.
	var nasolabial_x = 0.015+0.26*clampf(0.002-y,0.0,0.034)
	depth += 0.00125*_bell(absf(x),nasolabial_x,0.0055)*_bell(y,-0.018,0.020)
	depth += 0.0024*_bell(x,0.0,0.022)*_bell(y,-0.049,0.007)
	depth -= 0.0075*_bell(x,0.0,0.031)*_bell(y,-0.067,0.016)
	return depth

static func _front_z(x: float, y: float) -> float:
	var q = clampf((y-CENTER.y)/HALF_HEIGHT, -0.9999, 0.9999)
	var ring_radius = sqrt(maxf(0.00001,1.0-q*q))
	var ring_width = HALF_WIDTH*ring_radius*_width_factor(q)
	var x_fraction = clampf(x/maxf(ring_width,0.0001),-0.9999,0.9999)
	var face_cross_section = pow(maxf(0.00001,1.0-x_fraction*x_fraction),0.36)
	var front_depth = -HALF_DEPTH*ring_radius*face_cross_section
	# The mandibular front remains forward below the mouth rather than curving
	# immediately back into a spherical chin. Forehead and cheek planes are flatter.
	front_depth *= 0.965+0.15*_bell(q,-0.73,0.26)+0.025*_bell(q,0.44,0.45)
	return front_depth+_front_features(x,y)*maxf(0.0,1.0-pow(x_fraction,4.0))

static func _theta(column: int, columns: int) -> float:
	var angle = TAU*float(column)/columns
	# More vertices at the face, fewer under the helmet at the back.
	return angle-0.60*sin(angle)

static func _head_point(theta: float, q: float) -> Vector3:
	if absf(q)>0.999999:
		return Vector3(0.0,CENTER.y+HALF_HEIGHT*q,0.0)
	var ring_radius = sqrt(maxf(0.0,1.0-q*q))
	var x = HALF_WIDTH*ring_radius*_width_factor(q)*sin(theta)
	var y = CENTER.y+HALF_HEIGHT*q
	var z = -HALF_DEPTH*ring_radius*cos(theta)
	if cos(theta)>0.0:
		z = _front_z(x,y)
	else:
		z *= 1.03
	return Vector3(x,y,z)

static func _skin_color(x: float, y: float, z: float = -0.08) -> Color:
	# Controlled anatomical color zones; tiny unevenness stays below 1%.
	# No painted dark outlines or large random blotches are used.
	var face = smoothstep(0.018,0.067,-z)
	var cheek = _bell(absf(x),0.050,0.023)*_bell(y,0.023,0.027)*face
	var nose = _bell(x,0.0,0.018)*_bell(y,0.009,0.020)*face
	var socket = _bell(absf(x),EYE_X,0.027)*_bell(y,EYE_Y-0.005,0.014)*face
	var temple = _bell(absf(x),0.075,0.018)*_bell(y,0.050,0.055)
	var jaw = _bell(y,-0.064,0.024)
	var stubble = _bell(x,0.0,0.055)*(_bell(y,-0.048,0.021)+0.25*_bell(y,-0.023,0.008))*face
	# Material/shader owns pores. These broad anatomical zones add restrained
	# warmth and orbital color without whitening the face or drawing hard shadows.
	var shade = 1.0-0.047*socket-0.028*temple-0.023*jaw-0.022*stubble
	return Color(shade+0.006*cheek,shade-0.027*cheek-0.016*nose,shade-0.039*cheek-0.022*nose,1.0)

static func _vertex(tool: SurfaceTool, point: Vector3, uv: Vector2, color: Color = Color.WHITE) -> void:
	tool.set_uv(uv)
	tool.set_color(color)
	tool.add_vertex(point)

static func _triangle(tool: SurfaceTool, points: Array, uvs: Array, colors: Array, a: int, b: int, c: int) -> void:
	if (points[b]-points[a]).cross(points[c]-points[a]).length_squared()<1.0e-16:
		return
	for index in [a,b,c]:
		_vertex(tool,points[index],uvs[index],colors[index])

static func _grid(tool: SurfaceTool, points: Array, uvs: Array, columns: int, rows: int, colors: Array = [], reverse: bool = false) -> void:
	if colors.is_empty():
		for unused in points: colors.append(Color.WHITE)
	for row in range(rows):
		for column in range(columns):
			var a = row*(columns+1)+column
			var b = a+1
			var d = a+columns+1
			var c = d+1
			if reverse:
				_triangle(tool,points,uvs,colors,a,c,b)
				_triangle(tool,points,uvs,colors,a,d,c)
			else:
				_triangle(tool,points,uvs,colors,a,b,c)
				_triangle(tool,points,uvs,colors,a,c,d)

static func _build_skull(tool: SurfaceTool, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var rows = _divisions(ROWS,high_detail)
	var columns = _divisions(SEGMENTS,high_detail)
	for row in range(rows+1):
		var v = float(row)/rows
		for column in range(columns+1):
			var point = _head_point(_theta(column,columns),2.0*v-1.0)
			points.append(point)
			uvs.append(Vector2(float(column)/columns,v))
			colors.append(_skin_color(point.x,point.y,point.z))
	_grid(tool,points,uvs,columns,rows,colors)

static func _build_hair(tool: SurfaceTool, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	# Match the skull's ring planes. A coarser independent scalp cap intersects
	# the skull near the crown and exposes skin through the hair at low LOD.
	var rows = _divisions(ROWS,high_detail)
	var columns = _divisions(SEGMENTS,high_detail)
	for row in range(rows+1):
		var v = float(row)/rows
		for column in range(columns+1):
			var theta = _theta(column,columns)
			var front = maxf(cos(theta),0.0)
			# A broad adult frontal hairline transitions into the temples instead
			# of the previous triangular bowl-cut edge over the forehead.
			var hairline_y = 0.046+0.061*pow(front,0.70)-0.017*maxf(-cos(theta),0.0)
			hairline_y += 0.0006*sin(theta*17.0)*front
			var q = maxf((hairline_y-CENTER.y)/HALF_HEIGHT,2.0*v-1.0)
			var point = _head_point(theta,q)
			var flow = 0.5+0.5*sin(theta*48.0+q*9.0)
			point += (point-CENTER).normalized()*(0.0018+0.00025*flow*(1.0-q*q))
			points.append(point)
			uvs.append(Vector2(float(column)/columns,v))
			var value = 0.88+0.12*flow
			colors.append(Color(value,value*0.995,value*0.985,1.0))
	_grid(tool,points,uvs,columns,rows,colors)

static func _build_ear(tool: SurfaceTool, side: float, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var rows = _divisions(10,high_detail)
	var columns = _divisions(32,high_detail)
	for row in range(rows+1):
		var r = float(row)/rows
		for column in range(columns+1):
			var angle = TAU*float(column)/columns
			var y = 0.026+0.028*cos(angle)*r
			var z = 0.004+0.0135*sin(angle)*r
			var rim = 0.0038*_bell(r,0.78,0.16)
			# The concha attaches to the narrower temple; the outer helix keeps
			# the existing helmet/ear envelope instead of floating off the skull.
			# Front, upper and lower helix margins sink into the temporal skin;
			# only the posterior rim projects. A centre-only attachment looked
			# like a separate floating disk from the front after narrowing the skull.
			var outer = 0.095+0.012*r*sin(angle)-0.009*r*absf(cos(angle))+rim-0.0025*(1.0-r*r)
			# A small attached lobe and folded helix, without sphere earrings.
			outer += 0.0022*_bell(angle,PI,0.65)*r
			outer += 0.0017*_bell(r,0.47,0.14)*(0.5+0.5*cos(angle+0.7))
			points.append(Vector3(side*outer,y,z))
			uvs.append(Vector2(float(column)/columns,r))
			var fold = _bell(r,0.39,0.22)
			colors.append(Color(0.985-0.05*fold,0.920-0.068*fold,0.900-0.070*fold,1.0))
	_grid(tool,points,uvs,columns,rows,colors,side<0.0)

static func _eye_height(u: float, upper: bool) -> float:
	return sin(PI*clampf(u,0.0,1.0))*(0.0052 if upper else 0.0038)

static func _eye_z(x: float, y: float, center_x: float, side: float) -> float:
	var u = clampf((x-center_x+EYE_HALF_WIDTH)/(2.0*EYE_HALF_WIDTH),0.0,1.0)
	var tilt = side*(x-center_x)*0.035
	var edge = _eye_height(u,y>=EYE_Y+tilt)
	var v = (y-EYE_Y-tilt)/maxf(edge,0.0001)
	return _front_z(x,y)-0.00065-0.0018*sin(PI*u)*maxf(0.0,1.0-v*v)

static func _build_eye(builders: Dictionary, side: float, high_detail: bool) -> void:
	var center_x = side*EYE_X
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var rows = _divisions(8,high_detail)
	var columns = _divisions(32,high_detail)
	for row in range(rows+1):
		var v = 2.0*float(row)/rows-1.0
		for column in range(columns+1):
			var u = float(column)/columns
			var x = center_x+(2.0*u-1.0)*EYE_HALF_WIDTH
			var y = EYE_Y+side*(x-center_x)*0.035+v*_eye_height(u,v>=0.0)
			points.append(Vector3(x,y,_eye_z(x,y,center_x,side)))
			uvs.append(Vector2(u,(v+1.0)*0.5))
			var edge = pow(absf(2.0*u-1.0),3.0)
			colors.append(Color(1.0-0.06*edge,0.995-0.095*edge,0.970-0.10*edge,1.0))
	_grid(builders.eye,points,uvs,columns,rows,colors)
	for upper in [false,true]:
		_build_lid(builders.skin,center_x,side,upper,high_detail)
	_build_iris(builders.iris,center_x,side,0.0053,Color.WHITE,0.0,high_detail)
	_build_iris(builders.iris,center_x,side,0.0019,Color(0.16,0.17,0.18),0.00015,high_detail)

static func _build_lid(tool: SurfaceTool, center_x: float, side: float, upper: bool, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var sign_y = 1.0 if upper else -1.0
	var rows = _divisions(4,high_detail)
	var columns = _divisions(32,high_detail)
	for row in range(rows+1):
		var v = float(row)/rows
		for column in range(columns+1):
			var u = float(column)/columns
			var x = center_x+(2.0*u-1.0)*EYE_HALF_WIDTH
			var edge_y = EYE_Y+side*(x-center_x)*0.035+sign_y*_eye_height(u,upper)
			var y = edge_y+sign_y*v*sin(PI*u)*(0.005 if upper else 0.0035)
			var ridge = 0.0014*sin(PI*u)*pow(1.0-v,1.0)
			ridge -= 0.00055*_bell(v,0.80,0.17)*sin(PI*u) if upper else 0.0
			points.append(Vector3(x,y,_front_z(x,y)-(0.00065+ridge)*(1.0-v)))
			uvs.append(Vector2(u,v))
			var tint = _skin_color(x,y)
			var lash_edge = sin(PI*u)*pow(1.0-v,3.0)
			var crease = _bell(v,0.80,0.20)*sin(PI*u) if upper else 0.0
			colors.append(tint*Color(1.0-0.080*lash_edge-0.036*crease,1.0-0.096*lash_edge-0.040*crease,1.0-0.100*lash_edge-0.040*crease,1.0))
	_grid(tool,points,uvs,columns,rows,colors,not upper)

static func _build_iris(tool: SurfaceTool, center_x: float, side: float, radius: float, color: Color, front_offset: float, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var rows = _divisions(4,high_detail)
	var columns = _divisions(32,high_detail)
	for row in range(rows+1):
		var r = radius*float(row)/rows
		for column in range(columns+1):
			var angle = TAU*float(column)/columns
			var x = center_x+r*cos(angle)
			var u = clampf((x-center_x+EYE_HALF_WIDTH)/(2.0*EYE_HALF_WIDTH),0.0,1.0)
			var tilt = side*(x-center_x)*0.035
			var y = clampf(EYE_Y+r*sin(angle),EYE_Y+tilt-_eye_height(u,false)+0.0001,EYE_Y+tilt+_eye_height(u,true)-0.0001)
			points.append(Vector3(x,y,_eye_z(x,y,center_x,side)-0.00018-front_offset))
			uvs.append(Vector2(0.5+0.5*cos(angle)*r/radius,0.5+0.5*sin(angle)*r/radius))
			var radial = float(row)/rows
			var fibres = 0.94+0.06*sin(angle*13.0+radial*4.0)
			colors.append(color*Color(fibres,fibres*0.99,fibres*0.97,1.0))
	_grid(tool,points,uvs,columns,rows,colors,true)

static func _build_lower_eye_fold(tool: SurfaceTool, side: float, high_detail: bool) -> void:
	# A small infraorbital fold gives the eyelid a real transition into the
	# cheek. It is a skin surface, rather than a dark drawn outline.
	var points: Array=[]
	var uvs: Array=[]
	var colors: Array=[]
	var columns=_divisions(28,high_detail)
	var rows=2
	for row in range(rows+1):
		var v=float(row)/rows
		for column in range(columns+1):
			var u=float(column)/columns
			var x=side*(EYE_X+(2.0*u-1.0)*0.0185)
			var y=EYE_Y-0.0072-0.0025*sin(PI*u)+(v-0.5)*0.0026*sin(PI*u)
			var offset=0.00032+0.00030*sin(PI*v)*sin(PI*u)
			points.append(Vector3(x,y,_front_z(x,y)-offset))
			uvs.append(Vector2(u,v))
			var crease=0.045*sin(PI*v)*sin(PI*u)
			colors.append(_skin_color(x,y)*Color(1.0-crease,1.0-crease,1.0-crease,1.0))
	_grid(tool,points,uvs,columns,rows,colors,side<0.0)

static func _build_brow(tool: SurfaceTool, side: float, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var rows = _divisions(2,high_detail)
	var columns = _divisions(24,high_detail)
	for row in range(rows+1):
		for column in range(columns+1):
			var u = float(column)/columns
			var x = side*(0.014+0.043*u)
			var y = 0.074+0.0028*sin(PI*u)-0.0029*u+(float(row)/rows-0.5)*0.0041*sin(PI*u)
			points.append(Vector3(x,y,_front_z(x,y)-0.00075))
			uvs.append(Vector2(u,float(row)/rows))
			var strands = 0.80+0.20*pow(sin(PI*u),0.35)
			colors.append(Color(strands,strands,strands,1.0))
	_grid(tool,points,uvs,columns,rows,colors,side<0.0)

static func _build_nostril(tool: SurfaceTool, side: float, high_detail: bool) -> void:
	var points: Array = []
	var uvs: Array = []
	var colors: Array = []
	var rows = _divisions(2,high_detail)
	var columns = _divisions(16,high_detail)
	for row in range(rows+1):
		for column in range(columns+1):
			var u = float(column)/columns
			var x = side*(0.0060+0.0072*u)
			var y = -0.0024-0.0014*sin(PI*u)+(float(row)/rows-0.5)*0.0015*sin(PI*u)
			points.append(Vector3(x,y,_front_z(x,y)-0.00025))
			uvs.append(Vector2(u,float(row)/rows))
			colors.append(Color(0.60,0.57,0.55))
	_grid(tool,points,uvs,columns,rows,colors,side<0.0)

static func _build_lips(builders: Dictionary, high_detail: bool) -> void:
	var rows = _divisions(5,high_detail)
	var columns = _divisions(32,high_detail)
	for upper in [false,true]:
		var points: Array = []
		var uvs: Array = []
		var colors: Array = []
		var sign_y = 1.0 if upper else -1.0
		for row in range(rows+1):
			var v = float(row)/rows
			for column in range(columns+1):
				var u = float(column)/columns
				var x = (2.0*u-1.0)*0.0225
				var closed_y = -0.032
				var height = (0.0025+0.0009*_bell(absf(x),0.006,0.004)) if upper else 0.0038
				var y = closed_y+sign_y*v*height*sin(PI*u)
				var bulge = 0.0012*sin(PI*u)*sin(PI*v)
				points.append(Vector3(x,y,_front_z(x,y)-0.0003-bulge))
				uvs.append(Vector2(u,v))
				var value = 0.95+0.05*sin(PI*v)-0.026*sin(u*PI*22.0)*sin(PI*u)
				colors.append(Color(value,value*0.985,value*0.980,1.0))
		_grid(builders.lip,points,uvs,columns,rows,colors,not upper)
	var line_points: Array = []
	var line_uvs: Array = []
	var line_colors: Array = []
	for row in range(2):
		for column in range(columns+1):
			var u = float(column)/columns
			var x = (2.0*u-1.0)*0.0220
			var y = -0.032+(float(row)-0.5)*0.00055*sin(PI*u)
			line_points.append(Vector3(x,y,_front_z(x,y)-0.00060))
			line_uvs.append(Vector2(u,float(row)))
			line_colors.append(Color(0.62,0.55,0.50))
	_grid(builders.iris,line_points,line_uvs,columns,1,line_colors)
