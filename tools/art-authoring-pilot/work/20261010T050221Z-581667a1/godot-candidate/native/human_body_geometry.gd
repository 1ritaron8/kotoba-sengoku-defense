extends RefCounted
## Adult cloth anatomy in the existing rigid joint spaces. No separate balls
## at shoulders/knees: tapered, overlapping surfaces conceal the joint pivots.

static var _cache: Dictionary = {}
const FOOT_PROFILE = [
	Vector4(0.073,0.024,-0.038,-0.026),
	Vector4(0.060,0.035,-0.038,0.001),
	Vector4(0.018,0.037,-0.037,0.037),
	Vector4(-0.025,0.042,-0.036,0.039),
	Vector4(-0.072,0.052,-0.036,0.026),
	Vector4(-0.124,0.053,-0.035,0.015),
	Vector4(-0.167,0.046,-0.034,0.006),
	Vector4(-0.185,0.031,-0.033,-0.008),
]

static func build(unit_type: String, high_detail: bool = false) -> Array[Dictionary]:
	var light: bool = unit_type in ["archer","gunner","monk","ninja","enemy_light"]
	var key: String = "%s/%s" % [unit_type,high_detail]
	if _cache.has(key): return _cache[key]
	var builders: Dictionary = {}
	_neck(builders,high_detail)
	for side in [-1.0,1.0]:
		var suffix: String = "L" if side<0 else "R"
		_sleeve(builders,suffix,side,light,high_detail,unit_type=="archer")
		_pants(builders,suffix,side,unit_type,high_detail)
		_hand(builders,suffix,side,high_detail)
		_foot(builders,suffix,side,high_detail)
	var pieces: Array[Dictionary] = []
	for surface_key in builders:
		var entry: Dictionary = builders[surface_key]
		var tool: SurfaceTool = entry.tool
		tool.index()
		tool.generate_tangents()
		pieces.append({"bone":entry.bone,"material":entry.material,"mesh":tool.commit()})
	_cache[key]=pieces
	return pieces

static func ankle_height(pitch: float) -> float:
	# The sole is a shaped last rather than an ellipsoid. These are the exact
	# underside extrema, so toe/heel roll is grounded using the rendered foot.
	var minimum: float = INF
	var cosine: float = cos(pitch)
	var sine: float = sin(pitch)
	for section in FOOT_PROFILE:
		minimum=minf(minimum,section.z*cosine-section.x*sine)
	return -minimum+0.003

static func _tool(builders: Dictionary, bone: String, material: String) -> SurfaceTool:
	var key: String = bone+"/"+material
	if not builders.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		builders[key]={"bone":bone,"material":material,"tool":tool}
	return builders[key].tool

static func _triangle(tool: SurfaceTool, points: Array, normals: Array, uvs: Array, colors: Array, a: int, b: int, c: int) -> void:
	var cross_value: Vector3 = (points[b]-points[a]).cross(points[c]-points[a])
	if cross_value.length_squared()<0.000000000001: return
	if cross_value.dot(normals[a]+normals[b]+normals[c])>0:
		var previous: int = b
		b=c
		c=previous
	for index in [a,b,c]:
		tool.set_normal(normals[index].normalized())
		tool.set_uv(uvs[index])
		tool.set_color(colors[index])
		tool.add_vertex(points[index])

static func _grid(tool: SurfaceTool, points: Array, columns: int, rows: int, centre: Vector3, shade: float = 1.0) -> void:
	var normals: Array = []
	var uvs: Array = []
	var colors: Array = []
	for row in range(rows+1):
		for column in range(columns+1):
			var index: int = row*(columns+1)+column
			# Every ring repeats its seam vertex. The same wrapped derivative at
			# both ends avoids a hard lit stripe down a smooth sleeve or calf.
			var next_column: int = 1 if column==columns else column+1
			var previous_column: int = columns-1 if column==0 else column-1
			var du: Vector3 = points[row*(columns+1)+next_column]-points[row*(columns+1)+previous_column]
			var dv: Vector3 = points[mini(row+1,rows)*(columns+1)+column]-points[maxi(row-1,0)*(columns+1)+column]
			var radial: Vector3 = points[index]-centre
			var normal: Vector3 = du.cross(dv).normalized()
			if normal.dot(radial)<0: normal=-normal
			if normal.length_squared()<0.5: normal=radial.normalized()
			normals.append(normal)
			uvs.append(Vector2(float(column)/columns,float(row)/rows))
			var variation: float = shade*(0.975+0.025*sin(float(row)*0.63+float(column)*0.4))
			colors.append(Color(variation,variation,variation,1))
	for row in range(rows):
		for column in range(columns):
			var a: int = row*(columns+1)+column
			var b: int = a+1
			var d: int = a+columns+1
			var c: int = d+1
			_triangle(tool,points,normals,uvs,colors,a,b,c)
			_triangle(tool,points,normals,uvs,colors,a,c,d)

static func _cap(tool: SurfaceTool, ring: Array, outward: Vector3, shade: float) -> void:
	var centre: Vector3 = Vector3.ZERO
	for point in ring: centre+=point
	centre/=ring.size()
	var points: Array = [centre]
	points.append_array(ring)
	var normals: Array = []
	var colors: Array = []
	var uvs: Array = []
	for point in points:
		normals.append(outward)
		colors.append(Color(shade,shade,shade,1))
		uvs.append(Vector2(point.x*4+0.5,point.z*4+0.5))
	for index in range(ring.size()-1):
		_triangle(tool,points,normals,uvs,colors,0,index+1,index+2)

static func _loft(builders: Dictionary, bone: String, material: String, profile: Array, columns: int, folds: float = 0.0, side: float = 1.0, centre_z: float = 0.0, shade: float = 1.0, close_ends: bool = true) -> void:
	# profile Vector4: joint-local Y, half-width, half-depth, lateral offset.
	var points: Array = []
	var rows: int = profile.size()-1
	for row in range(profile.size()):
		var section: Vector4 = profile[row]
		var t: float = float(row)/maxi(1,rows)
		for column in range(columns+1):
			var angle: float = TAU*float(column)/columns
			# Fabric tension folds gather at the elbow/knee, not regular rings.
			# A few broad tension folds run into the bent elbow/knee. Dense,
			# evenly repeated ripples made the cloth look like a rigid ribbed tube.
			var gather: float = exp(-pow((t-.72)/.19,2))
			var wrinkle: float = folds*(sin(angle*3+t*2.2+side*.55)*.66+sin(angle*2-t*5.4)*.24+gather*sin(angle*2+t*6.4)*.34)*sin(t*PI)
			var x: float = cos(angle)*(section.y+wrinkle)+section.w
			var z: float = sin(angle)*(section.z+wrinkle*0.70)+centre_z
			var fabric_y: float = folds*.85*sin(angle*2.0+t*3.5+side)*pow(sin(t*PI),2)
			points.append(Vector3(x,section.x+fabric_y,z))
	var tool: SurfaceTool = _tool(builders,bone,material)
	var mid_y: float = (profile[0].x+profile[-1].x)*0.5
	_grid(tool,points,columns,rows,Vector3(0,mid_y,centre_z),shade)
	if close_ends:
		_cap(tool,points.slice(0,columns+1),Vector3.UP if profile[0].x>profile[-1].x else Vector3.DOWN,shade)
		_cap(tool,points.slice(rows*(columns+1)),Vector3.DOWN if profile[0].x>profile[-1].x else Vector3.UP,shade)

static func _smooth_profile(profile: Array, detailed: bool) -> Array:
	# Preserve every authored cross-section and the joint-local end points.
	# Intermediate Hermite sections soften deltoid/calf changes without moving
	# a wrist, knee, ankle or the sole used by the contact solver.
	if not detailed:
		return profile
	var smooth: Array = []
	for index in range(profile.size()-1):
		var a: Vector4 = profile[maxi(0,index-1)]
		var b: Vector4 = profile[index]
		var c: Vector4 = profile[index+1]
		var d: Vector4 = profile[mini(profile.size()-1,index+2)]
		smooth.append(b)
		var midpoint: Vector4 = (b+c)*.5+(b-a+c-d)*.0625
		midpoint.x = lerpf(b.x,c.x,.5)
		for component in [1,2,3]:
			midpoint[component] = clampf(midpoint[component],minf(b[component],c[component]),maxf(b[component],c[component]))
		smooth.append(midpoint)
	smooth.append(profile[-1])
	return smooth

static func _tube(builders: Dictionary, bone: String, material: String, path: Array, radii: Array, columns: int, shade: float = 1.0, aspect: float = 1.0) -> void:
	var points: Array = []
	var rows: int = path.size()-1
	for row in range(path.size()):
		var tangent: Vector3 = (path[mini(row+1,rows)]-path[maxi(row-1,0)]).normalized()
		var reference: Vector3 = Vector3.RIGHT if absf(tangent.dot(Vector3.RIGHT))<0.9 else Vector3.UP
		var a: Vector3 = tangent.cross(reference).normalized()
		var b: Vector3 = tangent.cross(a).normalized()
		for column in range(columns+1):
			var angle: float = TAU*column/columns
			points.append(path[row]+(a*cos(angle)*aspect+b*sin(angle))*float(radii[row]))
	var centre: Vector3 = Vector3.ZERO
	for point in path: centre+=point
	centre/=path.size()
	var tool: SurfaceTool = _tool(builders,bone,material)
	_grid(tool,points,columns,rows,centre,shade)
	_cap(tool,points.slice(0,columns+1),(path[0]-path[1]).normalized(),shade)
	_cap(tool,points.slice(rows*(columns+1)),(path[-1]-path[-2]).normalized(),shade)

static func _neck(builders: Dictionary, high_detail: bool) -> void:
	# Trapezius narrows into the neck beneath the real jaw. The nape leans
	# gently back, so there is no flat cylindrical plug under the skull.
	var profile: Array = [Vector4(.206,.074,.046,0),Vector4(.232,.054,.046,0),Vector4(.255,.045,.043,0),Vector4(.286,.043,.042,0),Vector4(.316,.044,.043,0),Vector4(.342,.045,.044,0)]
	_loft(builders,"torso","skin",profile,20 if high_detail else 14,0,1,.004,1)
	# The old open upper torso left a black gap below the neck. A tailored
	# shoulder yoke follows the trapezius into the existing chest shell.
	_loft(builders,"torso","cloth",_smooth_profile([Vector4(.257,.064,.049,0),Vector4(.248,.088,.054,0),Vector4(.234,.125,.073,0),Vector4(.218,.157,.089,0),Vector4(.199,.178,.101,0),Vector4(.177,.191,.109,0),Vector4(.158,.194,.109,0)],high_detail),24 if high_detail else 16,.0025,1,.003,.84,false)
	for side in [-1.0,1.0]:
		_tube(builders,"torso","skin",[Vector3(side*.026,.323,-.036),Vector3(side*.024,.288,-.039),Vector3(side*.038,.240,-.029)],[.005,.004,.002],6,.96)
		# Soft overlapping kimono collar is a folded strip, with stitched edges.
		_tube(builders,"torso","cloth",[Vector3(side*.048,.267,-.038),Vector3(side*.073,.235,-.055),Vector3(side*.086,.219,-.076)],[.010,.012,.010],8,.96,.65)

static func _sleeve(builders: Dictionary, suffix: String, side: float, light: bool, high_detail: bool, archer: bool = false) -> void:
	var volume: float = .64 if archer else .72 if light else .75
	var columns: int = 22 if high_detail else 16
	var arm: Array = [Vector4(.022,.022,.027,-side*.046),Vector4(.010,.041,.042,-side*.020),Vector4(-.012,.058,.057,-side*.007),Vector4(-.047,.063,.061,side*.001),Vector4(-.093,.062,.062,side*.002),Vector4(-.140,.057,.059,0),Vector4(-.190,.052,.054,-side*.002),Vector4(-.236,.047,.047,-side*.003),Vector4(-.276,.043,.044,-side*.002),Vector4(-.310,.041,.041,0)]
	for index in range(arm.size()):
		arm[index].y*=volume
		arm[index].z*=volume
	_loft(builders,"arm"+suffix,"cloth",_smooth_profile(arm,high_detail),columns,.0035 if archer else .0045,side,-.002,1)
	var fore: Array = [Vector4(.028,.042,.043,0),Vector4(.005,.047,.046,0),Vector4(-.037,.054,.055,-side*.003),Vector4(-.084,.055,.052,-side*.005),Vector4(-.133,.047,.046,-side*.004),Vector4(-.183,.039,.037,-side*.002),Vector4(-.228,.031,.032,0),Vector4(-.246,.029,.030,0)]
	# Only the cloth volume changes. Wrist/hand attachment and limb length stay
	# fixed; the last two sections keep the exact original cuff dimensions.
	for index in range(fore.size()-2):
		fore[index].y*=.76 if archer else .82
		fore[index].z*=.76 if archer else .82
	_loft(builders,"fore"+suffix,"cloth",_smooth_profile(fore,high_detail),columns,.0045,side,-.001,1)
	# Cuff tucks into the articulated wrist rather than ending at a round cap.
	_loft(builders,"fore"+suffix,"cloth",[Vector4(-.222,.034,.035,0),Vector4(-.234,.034,.035,0),Vector4(-.242,.031,.032,0)],columns,0,side,0,.88)

static func _pants(builders: Dictionary, suffix: String, side: float, unit_type: String, high_detail: bool) -> void:
	var volume: float = .82 if unit_type=="monk" else .71 if unit_type in ["archer","ninja"] else .75
	var columns: int = 24 if high_detail else 18
	var thigh: Array = [Vector4(.027,.094,.098,0),Vector4(-.018,.101,.107,-side*.004),Vector4(-.070,.105,.109,-side*.006),Vector4(-.130,.103,.101,-side*.005),Vector4(-.202,.091,.089,-side*.003),Vector4(-.268,.077,.076,0),Vector4(-.326,.066,.066,0),Vector4(-.380,.060,.060,0),Vector4(-.445,.056,.058,0)]
	for index in range(thigh.size()):
		thigh[index].y*=volume
		thigh[index].z*=volume
	_loft(builders,"thigh"+suffix,"cloth",_smooth_profile(thigh,high_detail),columns,.0090 if unit_type!="ninja" else .0050,side,.002,1)
	var calf: Array = [Vector4(.028,.058,.061,0),Vector4(.002,.059,.067,0),Vector4(-.052,.064,.074,side*.003),Vector4(-.114,.066,.073,side*.005),Vector4(-.176,.058,.062,side*.004),Vector4(-.241,.049,.054,side*.002),Vector4(-.305,.041,.046,0),Vector4(-.367,.034,.039,0),Vector4(-.422,.030,.034,0),Vector4(-.444,.030,.034,0)]
	for index in range(calf.size()-3):
		var taper: float=lerpf(.89,.96,float(index)/6)
		calf[index].y*=taper
		calf[index].z*=taper
	_loft(builders,"shin"+suffix,"cloth",_smooth_profile(calf,high_detail),columns,.0050,side,.002,1)
	# Kyahan cloth wraps lie on the calf contour and remain thin at the ankle.
	for wrap_y in [-.298,-.347,-.398]:
		var radius: float = lerpf(.041,.033,clampf((-wrap_y-.298)/.1,0,1))
		_loft(builders,"shin"+suffix,"cloth",[Vector4(wrap_y+.006,radius+.002,radius+.007,0),Vector4(wrap_y-.004,radius+.002,radius+.007,0)],columns,0,side,.002,.89)

static func _hand(builders: Dictionary, suffix: String, side: float, high_detail: bool) -> void:
	var columns: int = 20 if high_detail else 12
	# Flattened palm, slender wrist, four curled fingers and a crossing thumb.
	var palm: Array = [Vector4(.034,.023,.020,0),Vector4(.011,.027,.021,0),Vector4(-.014,.033,.022,0),Vector4(-.039,.036,.021,side*.002),Vector4(-.060,.033,.019,side*.003),Vector4(-.076,.026,.014,side*.002)]
	_loft(builders,"hand"+suffix,"skin",_smooth_profile(palm,high_detail),columns,0,side,.006,1)
	for finger in range(4):
		var x: float = side*(-.026+finger*.017)
		var length_offset: float = [0.004,0.0,0.002,0.009][finger]
		var path: Array = [Vector3(x,-.040,.012),Vector3(x,-.060+length_offset,.017),Vector3(x,-.078+length_offset,.008),Vector3(x,-.077+length_offset,-.010),Vector3(x,-.056+length_offset,-.026)]
		_tube(builders,"hand"+suffix,"skin",path,[.009,.0092,.0084,.0072,.0053],8 if high_detail else 6,1)
		if high_detail:
			_tube(builders,"hand"+suffix,"skin_shadow",[Vector3(x-.006,-.073+length_offset,.019),Vector3(x+.005,-.073+length_offset,.019)],[.0008,.0008],5,.95)
	var thumb: Array = [Vector3(side*.030,-.008,-.004),Vector3(side*.046,-.025,-.014),Vector3(side*.042,-.045,-.025),Vector3(side*.020,-.052,-.027)]
	_tube(builders,"hand"+suffix,"skin",thumb,[.014,.012,.010,.008],10 if high_detail else 8,1)
	# A small cloth tekko covers the back of the hand without a spherical lump.
	_tube(builders,"hand"+suffix,"cloth",[Vector3(-side*.028,-.018,.027),Vector3(0,-.030,.031),Vector3(side*.032,-.035,.026)],[.005,.0055,.0045],6,.9,1.3)

static func _foot(builders: Dictionary, suffix: String, side: float, high_detail: bool) -> void:
	var columns: int = 20 if high_detail else 16
	var sole_points: Array = []
	var upper_points: Array = []
	for section in FOOT_PROFILE:
		for column in range(columns+1):
			var angle: float = TAU*column/columns
			var x: float = cos(angle)*section.y
			var lower_curve: float = maxf(0,sin(angle)+1.0)*0.003
			var sole_y: float = section.z+lower_curve
			var upper_y: float = section.z+.006+(section.w-section.z-.006)*maxf(0,sin(angle))
			# The rounded tabi toe has a shallow split beside the big toe, while
			# its sole Z/Y extrema stay identical to the foot-contact profile.
			upper_y -= .0022*exp(-pow((section.x+.157)/.028,2))*exp(-pow((x-side*.021)/.009,2))*maxf(0,sin(angle))
			sole_points.append(Vector3(x,sole_y,section.x))
			upper_points.append(Vector3(x*.97,upper_y,section.x))
	var sole: SurfaceTool = _tool(builders,"foot"+suffix,"leather")
	_grid(sole,sole_points,columns,FOOT_PROFILE.size()-1,Vector3(0,-.032,-.05),.95)
	_cap(sole,sole_points.slice(0,columns+1),Vector3.BACK,.92)
	_cap(sole,sole_points.slice((FOOT_PROFILE.size()-1)*(columns+1)),Vector3.FORWARD,.92)
	var cloth: SurfaceTool = _tool(builders,"foot"+suffix,"cloth")
	_grid(cloth,upper_points,columns,FOOT_PROFILE.size()-1,Vector3(0,0,-.05),.92)
	_cap(cloth,upper_points.slice(0,columns+1),Vector3.BACK,.92)
	_cap(cloth,upper_points.slice((FOOT_PROFILE.size()-1)*(columns+1)),Vector3.FORWARD,.92)
	# Waraji cords cross the instep and retain the heel, with the tabi split
	# defined by a short toe seam. They are fitted to the foot, not thick rings.
	_tube(builders,"foot"+suffix,"cord",[Vector3(-.047,-.005,-.105),Vector3(-.021,.022,-.052),Vector3(.027,.016,-.073),Vector3(.050,-.013,-.119)],[.003,.003,.003,.003],6,.87)
	_tube(builders,"foot"+suffix,"cord",[Vector3(-.037,-.008,.034),Vector3(-.032,.022,.010),Vector3(.034,.022,.010),Vector3(.038,-.008,.034)],[.003,.003,.003,.003],6,.86)
	_tube(builders,"foot"+suffix,"cloth",[Vector3(side*.022,.004,-.178),Vector3(side*.022,.010,-.153),Vector3(side*.023,.015,-.128)],[.0014,.0014,.0007],5,.70)

static func _longitudinal(builders: Dictionary, bone: String, material: String, profile: Array, columns: int, shade: float = 1.0) -> void:
	# Vector4: Z, half-width, half-height and centre-Y. Elliptical rings follow
	# real shoulder/chest/muzzle volumes instead of intersecting sphere lumps.
	var points: Array=[]
	for section in profile:
		for column in range(columns+1):
			var angle: float=TAU*column/columns
			points.append(Vector3(cos(angle)*section.y,sin(angle)*section.z+section.w,section.x))
	var centre_y: float=(profile[0].w+profile[-1].w)*.5
	var tool: SurfaceTool=_tool(builders,bone,material)
	_grid(tool,points,columns,profile.size()-1,Vector3(0,centre_y,(profile[0].x+profile[-1].x)*.5),shade)
	_cap(tool,points.slice(0,columns+1),Vector3.BACK,shade)
	_cap(tool,points.slice((profile.size()-1)*(columns+1)),Vector3.FORWARD,shade)

static func build_horse(high_detail: bool = false) -> Array[Dictionary]:
	var key: String="horse/"+str(high_detail)
	if _cache.has(key): return _cache[key]
	var builders: Dictionary={}
	var columns: int=24 if high_detail else 16
	_longitudinal(builders,"mount","coat",[Vector4(.54,.080,.110,.89),Vector4(.48,.190,.226,.93),Vector4(.34,.266,.271,.924),Vector4(.17,.277,.290,.899),Vector4(-.02,.263,.289,.884),Vector4(-.19,.250,.280,.913),Vector4(-.34,.243,.256,.941),Vector4(-.47,.180,.206,.961),Vector4(-.50,.080,.152,.976)],columns)
	# A tapered arched neck joins the withers, with no ball at its base.
	_loft(builders,"horse_neck","coat",[Vector4(.40,.089,.105,0),Vector4(.31,.119,.145,0),Vector4(.19,.143,.192,0),Vector4(.04,.151,.215,0),Vector4(-.11,.136,.210,0),Vector4(-.24,.085,.164,0)],columns,0,1,-.070)
	_longitudinal(builders,"horse_head","coat",[Vector4(.115,.040,.087,.068),Vector4(.073,.089,.134,.063),Vector4(.020,.108,.142,.043),Vector4(-.037,.111,.129,.020),Vector4(-.100,.088,.103,-.018),Vector4(-.165,.075,.075,-.055),Vector4(-.222,.086,.066,-.070),Vector4(-.265,.078,.061,-.074),Vector4(-.284,.044,.041,-.080)],columns)
	_longitudinal(builders,"horse_head","skin_shadow",[Vector4(-.243,.080,.059,-.074),Vector4(-.269,.073,.057,-.077),Vector4(-.287,.044,.040,-.080)],columns,.89)
	for side in [-1.0,1.0]:
		var suffix: String="L" if side<0 else "R"
		# Tapered, flattened ear shells, the long muzzle and actual jawline read
		# together as a horse rather than a round face made of stacked spheres.
		_loft(builders,"horse_head","coat",[Vector4(.312,.004,.005,side*.069),Vector4(.284,.012,.012,side*.073),Vector4(.243,.022,.014,side*.071),Vector4(.207,.024,.013,side*.065),Vector4(.181,.015,.010,side*.061)],10 if high_detail else 8,0,side,.044,.91)
		_tube(builders,"horse_head","skin_shadow",[Vector3(side*.081,-.047,-.250),Vector3(side*.080,-.080,-.270)],[.010,.006],8,.88,.4)
		_tube(builders,"horse_head","skin_shadow",[Vector3(side*.065,-.122,-.197),Vector3(side*.062,-.119,-.254)],[.003,.0025],6,.91)
	# Mane hugs the crest. The old cylindrical mane stood off the neck.
	_tube(builders,"horse_neck","hair",[Vector3(0,-.15,.092),Vector3(0,-.01,.139),Vector3(0,.15,.126),Vector3(0,.32,.072),Vector3(0,.40,.034)],[.027,.029,.027,.023,.018],8,.90,.58)
	for leg in range(4):
		var front: bool=leg<2
		var side: float=-1.0 if leg%2==0 else 1.0
		var upper: Array=[Vector4(.045,.060,.069,0),Vector4(-.013,.065,.075,0),Vector4(-.083,.060,.073,side*.005),Vector4(-.163,.050,.059,side*.003),Vector4(-.247,.038,.045,0),Vector4(-.323,.031,.034,0),Vector4(-.387,.030,.031,0)]
		if not front:
			upper[1].y=.085
			upper[1].z=.086
			upper[2].y=.070
			upper[2].z=.079
		_loft(builders,"horse_leg%d"%leg,"coat",upper,12 if high_detail else 10,0,side)
		_loft(builders,"horse_calf%d"%leg,"coat",[Vector4(.026,.031,.033,0),Vector4(-.038,.029,.031,0),Vector4(-.112,.023,.029,0),Vector4(-.214,.021,.027,0),Vector4(-.287,.024,.026,0),Vector4(-.341,.029,.029,0),Vector4(-.384,.027,.027,0)],12 if high_detail else 10,0,side)
		# The hoof has a broad flat toe and a defined coronet, so contact comes
		# from the same -.416m bottom used by the existing leg contact solver.
		_loft(builders,"horse_calf%d"%leg,"hair",[Vector4(-.352,.027,.027,0),Vector4(-.368,.035,.038,0),Vector4(-.402,.039,.043,0),Vector4(-.416,.037,.043,0)],12 if high_detail else 10,0,side,-.017,.85)
	# Tail is tapered and follows the already animated tail joint.
	_tube(builders,"horse_tail","hair",[Vector3(0,.030,.008),Vector3(0,-.080,.022),Vector3(0,-.220,.030),Vector3(0,-.370,.046),Vector3(0,-.520,.039)],[.021,.034,.035,.025,.006],12 if high_detail else 8,.92,.72)
	var pieces: Array[Dictionary]=[]
	for surface_key in builders:
		var entry: Dictionary=builders[surface_key]
		var tool: SurfaceTool=entry.tool
		tool.index()
		tool.generate_tangents()
		pieces.append({"bone":entry.bone,"material":entry.material,"mesh":tool.commit()})
	_cache[key]=pieces
	return pieces
