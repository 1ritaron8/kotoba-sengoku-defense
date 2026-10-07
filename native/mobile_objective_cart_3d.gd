extends Node3D
## Render-only cart at the Game's existing moving objective anchor.
## The original convoy clock, route, HP, targeting and rewards are untouched.
const ActorMaterials = preload("res://native/actor_materials.gd")
const WHEEL_RADIUS: float = .28
static var mesh_cache: Dictionary = {}
var wheels: Array[Node3D] = []
var flag: MeshInstance3D
var pieces: Array[MeshInstance3D] = []
var pigments: Dictionary = {}
var marker_id: String = ""
var last_point: Vector3 = Vector3.ZERO
var last_clock: float = -1.0
var wheel_distance: float = 0.0
var heading: float = 0.0
var initial_heading: float = 0.0
var movement_updates: int = 0
var lighting_values: Dictionary = {}

func configure(id: String, facing: float=0.0) -> void:
	marker_id=id
	initial_heading=facing
	set_meta("render_only",true)
	if not pieces.is_empty(): reset_motion();return
	var wood: StandardMaterial3D=_material(Color("9f784a"),.79,.0)
	var rim: StandardMaterial3D=_material(Color("525a62"),.55,.16)
	var canvas: StandardMaterial3D=_material(Color("c0b48d"),.90,.0)
	var binding: StandardMaterial3D=_material(Color("e0cf9f"),.86,.0)
	var body: ArrayMesh=build_body()
	var shell: MeshInstance3D=_attach(self,body,null)
	for surface in range(body.get_surface_count()): shell.set_surface_override_material(surface,[wood,rim,canvas,binding][surface])
	for side in [-1,1]:
		var joint: Node3D=Node3D.new()
		joint.position=Vector3(side*.54,WHEEL_RADIUS,.12)
		add_child(joint)
		wheels.append(joint)
		var wheel: MeshInstance3D=_attach(joint,build_wheel(),null)
		wheel.set_surface_override_material(0,wood)
		wheel.set_surface_override_material(1,rim)
	flag=_attach(self,build_flag(),null)
	flag.position=Vector3(.70,1.27,.40)
	var shader: Shader=Shader.new()
	shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform float battle_clock=0.0;
uniform float local_exposure=1.0;
uniform vec3 local_tint=vec3(1.0);
void vertex() {
    float free_edge=clamp((VERTEX.x+0.24)/0.48,0.0,1.0);
    VERTEX.z+=sin(VERTEX.x*10.0-battle_clock*2.7)*0.025*free_edge;
}
void fragment() {
    ALBEDO=vec3(0.040,0.230,0.570)*local_tint*local_exposure;
    ROUGHNESS=0.82;
    SPECULAR=0.18;
}"""
	var flag_material: ShaderMaterial=ShaderMaterial.new()
	flag_material.shader=shader
	flag.material_override=flag_material
	var shadow: MeshInstance3D=_attach(self,_contact_plane(),ActorMaterials.contact_shadow_material())
	shadow.position.y=.002
	shadow.layers=1
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reset_motion()

func reset_motion() -> void:
	last_clock=-1.0
	wheel_distance=0.0
	heading=initial_heading
	for wheel in wheels: wheel.rotation.x=0.0

func apply_marker(marker: Dictionary, world_point: Vector3, clock: float, reset: bool=false) -> bool:
	if not world_point.is_finite() or not is_finite(clock): return false
	var changed: bool=position!=world_point or last_clock!=clock or reset
	var dt: float=maxf(0.0,clock-last_clock)
	var travel: Vector3=world_point-last_point
	travel.y=0.0
	var distance: float=travel.length()
	var restart: bool=reset or last_clock<0.0 or clock<last_clock or distance>1.5
	if restart:
		wheel_distance=0.0
		if last_clock<0.0 or clock<last_clock: heading=initial_heading
	elif dt>0.0 and distance>.00001:
		heading=lerp_angle(heading,atan2(-travel.x,-travel.z),1.0-exp(-dt*10.0))
		wheel_distance+=distance/maxf(scale.x,.01)
		movement_updates+=1
	position=world_point
	rotation.y=heading
	for wheel in wheels: wheel.rotation.x=-fmod(wheel_distance/WHEEL_RADIUS,TAU)
	if last_clock!=clock: (flag.material_override as ShaderMaterial).set_shader_parameter("battle_clock",clock)
	last_point=world_point
	last_clock=clock
	set_meta("objective_id",str(marker.get("objectiveId","")))
	set_meta("normalized_point",Vector2(float(marker.x),float(marker.y)))
	return changed

func set_local_light(exposure: float, tint: Color, _saturation: float=1.0, _roughness: float=0.0) -> void:
	var values: Dictionary={"exposure":exposure,"tint":tint}
	if lighting_values==values: return
	lighting_values=values
	for material in pigments:
		material.albedo_color=(pigments[material] as Color)*tint*clampf(exposure,.8,1.16)
	var material: ShaderMaterial=flag.material_override
	material.set_shader_parameter("local_exposure",clampf(exposure,.8,1.16))
	material.set_shader_parameter("local_tint",Vector3(tint.r,tint.g,tint.b))

func _material(colour: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material: StandardMaterial3D=StandardMaterial3D.new()
	material.albedo_color=colour
	material.roughness=roughness
	material.metallic=metallic
	material.metallic_specular=.22
	pigments[material]=colour
	return material

func _attach(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D=MeshInstance3D.new()
	instance.mesh=mesh
	instance.material_override=material
	instance.layers=3
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	pieces.append(instance)
	return instance

static func _append(tool: SurfaceTool, mesh: Mesh, position_value: Vector3, rotation_value: Vector3=Vector3.ZERO, scale_value: Vector3=Vector3.ONE) -> void:
	tool.append_from(mesh,0,Transform3D(Basis.from_euler(rotation_value).scaled(scale_value),position_value))

static func _box(tool: SurfaceTool, center: Vector3, dimensions: Vector3, angle: Vector3=Vector3.ZERO) -> void:
	var box: BoxMesh=BoxMesh.new()
	box.size=dimensions
	_append(tool,box,center,angle)

static func build_body() -> ArrayMesh:
	if mesh_cache.has("body"): return mesh_cache.body
	var mesh: ArrayMesh=ArrayMesh.new()
	for category in range(4):
		var tool: SurfaceTool=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		if category==0:
			for strip in range(7): _box(tool,Vector3((strip-3)*.13,.31,0),Vector3(.12,.055,1.26))
			for side in [-1,1]:
				_box(tool,Vector3(side*.48,.42,0),Vector3(.055,.19,1.30))
				_box(tool,Vector3(side*.39,.23,.22),Vector3(.10,.11,1.02))
				_box(tool,Vector3(side*.35,.26,-.84),Vector3(.042,.046,.66),Vector3(-.12,side*.09,0))
			for z in [-.64,.63]: _box(tool,Vector3(0,.42,z),Vector3(.92,.19,.055))
			_box(tool,Vector3(.46,.88,.40),Vector3(.026,1.22,.026))
		elif category==1:
			_box(tool,Vector3(0,WHEEL_RADIUS,.12),Vector3(1.14,.035,.035))
			for side in [-1,1]:
				for z in [-.54,.52]: _box(tool,Vector3(side*.481,.40,z),Vector3(.060,.21,.025))
		elif category==2:
			var sack: SphereMesh=SphereMesh.new()
			sack.radial_segments=16;sack.rings=8;sack.radius=.22;sack.height=.44
			for z in [-.29,.23]: _append(tool,sack,Vector3(0,.53,z),Vector3(0,0,.04),Vector3(1.70,.80,.86))
		else:
			for z in [-.29,.23]:
				_box(tool,Vector3(0,.66,z),Vector3(.63,.015,.016))
				_box(tool,Vector3(.33,.53,z),Vector3(.014,.24,.014))
		tool.index()
		var surface: ArrayMesh=tool.commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface.surface_get_arrays(0))
	mesh_cache.body=mesh
	return mesh

static func build_wheel() -> ArrayMesh:
	if mesh_cache.has("wheel"): return mesh_cache.wheel
	var mesh: ArrayMesh=ArrayMesh.new()
	for category in range(2):
		var tool: SurfaceTool=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		if category==0:
			var ring: TorusMesh=TorusMesh.new()
			ring.inner_radius=.228;ring.outer_radius=WHEEL_RADIUS;ring.rings=20;ring.ring_segments=6
			_append(tool,ring,Vector3.ZERO,Vector3(0,0,PI*.5))
			for spoke in range(8):
				var angle: float=spoke*TAU/8.0
				_box(tool,Vector3(0,cos(angle)*.13,sin(angle)*.13),Vector3(.05,.28,.026),Vector3(angle,0,0))
		else:
			var hub: CylinderMesh=CylinderMesh.new()
			hub.top_radius=.055;hub.bottom_radius=.055;hub.height=.11;hub.radial_segments=12
			_append(tool,hub,Vector3.ZERO,Vector3(0,0,PI*.5))
		tool.index()
		var surface: ArrayMesh=tool.commit()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface.surface_get_arrays(0))
	mesh_cache.wheel=mesh
	return mesh

static func build_flag() -> ArrayMesh:
	if mesh_cache.has("flag"): return mesh_cache.flag
	var tool: SurfaceTool=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(3):
		for column in range(8):
			for corner in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(1,0)]:
				var uv: Vector2=Vector2((column+corner.x)/8.0,(row+corner.y)/3.0)
				tool.set_normal(Vector3.FORWARD);tool.set_uv(uv)
				tool.add_vertex(Vector3((uv.x-.5)*.48,(uv.y-.5)*.32,0))
	tool.index()
	mesh_cache.flag=tool.commit()
	return mesh_cache.flag

static func _contact_plane() -> PlaneMesh:
	var mesh: PlaneMesh=PlaneMesh.new()
	mesh.size=Vector2(1.06,1.32)
	return mesh

func diagnostics() -> Dictionary:
	return {"id":marker_id,"renderOnly":true,"worldPosition":position,"normalizedPoint":get_meta("normalized_point",Vector2.ZERO),"objectiveId":get_meta("objective_id",""),"heading":heading,"wheelDistance":wheel_distance,"wheelRadius":WHEEL_RADIUS,"wheelAngles":[wheels[0].rotation.x,wheels[1].rotation.x] if wheels.size()==2 else [],"battleClock":last_clock,"movementUpdates":movement_updates,"meshInstances":pieces.size(),"realShadows":true,"blueFlag":true,"staticBaseCreated":false}
