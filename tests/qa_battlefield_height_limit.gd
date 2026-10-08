extends SceneTree

const Battlefield = preload("res://native/battlefield_3d.gd")
var checks: int=0
var failures: Array[String]=[]
var observations: Array=[]

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error("HEIGHT_LIMIT "+message)

func collect(field: Node3D,source: Dictionary,angle: float=42.0,aspect: float=1280.0/720.0) -> void:
	field.stage=source
	field.history=source.get("historicalBattlefield",{})
	field.width=18.5
	field.depth=18.5/aspect/sin(deg_to_rad(angle))
	field.elevation=angle
	field.seed_value=absi(str(source.get("id","height-fixture")).hash())
	field._collect_geometry()

func run() -> void:
	var profile: String=OS.get_environment("APPDATA").replace("\\","/").simplify_path().to_lower()
	var boundary: String=ProjectSettings.globalize_path("res://tests/profiles/height-limit-").replace("\\","/").to_lower()
	if not profile.begins_with(boundary) or OS.get_environment("LOCALAPPDATA").replace("\\","/").simplify_path().to_lower()!=profile:
		quit(2);return
	for sample in [[{},1.45],[{"heightLimitWorld":2.4},2.4],[{"heightLimitWorld":10},3.0],[{"heightLimitWorld":-1},1.45],[{"heightLimitWorld":NAN},1.45],[{"heightLimitWorld":"bad"},1.45]]:
		check(Battlefield.height_limit_for_history(sample[0])==sample[1],"Height limit boundary "+str(sample[0]))
	var source: Dictionary={"id":"qa-height-fixture","historicalBattlefield":{"heightFeatures":[{"kind":"hill","x":.5,"y":.5,"w":.7,"h":.7,"amplitudeWorld":2.2}]}}
	var taller: Dictionary=source.duplicate(true)
	taller.historicalBattlefield["heightLimitWorld"]=2.4
	var field: Node3D=Battlefield.new()
	collect(field,source)
	var original_center: float=field._natural_height(Vector2(.5,.5))
	var original_physical: String=JSON.stringify(field._physical_contract(source)).sha256_text()
	check(not field._physical_contract(source).has("heightLimitWorld"),"Unspecified stages retain their original physical contract shape")
	check(field.height_amplitudes[0]==1.4,"Unspecified feature amplitude keeps its original1.4 ceiling")
	check(field._begin_configure(source,18.5,field.depth,42.0),"Initial geometry configure succeeds")
	var previous_geometry: String=field.geometry_fingerprint
	check(field._begin_configure(taller,18.5,field.depth,42.0),"Changing only explicit height limit requests new terrain")
	check(field.geometry_fingerprint!=previous_geometry,"Height limit invalidates cached geometry identity")
	collect(field,taller)
	var taller_center: float=field._natural_height(Vector2(.5,.5))
	check(taller_center>original_center+.7 and taller_center>2.1 and taller_center<=2.4,"Explicit2.4 permits the authored2.2 peak instead of clipping to1.45")
	check(JSON.stringify(field._physical_contract(taller)).sha256_text()!=original_physical,"Height limit alters artwork source physical fingerprint")
	var excessive: Dictionary=taller.duplicate(true)
	excessive.historicalBattlefield.heightLimitWorld=100
	excessive.historicalBattlefield.heightFeatures[0].amplitudeWorld=20
	collect(field,excessive)
	check(field._natural_height(Vector2(.5,.5))<=3.0 and field.height_amplitudes[0]==3.0,"Explicit amplitude and final height are safely bounded to3worldunits")
	observations.append({"defaultCenterHeight":original_center,"expandedCenterHeight":taller_center,"maximumCenterHeight":field._natural_height(Vector2(.5,.5))})
	var baseline_path: String="res://tests/profiles/catalog-preview-compatibility/battlefield_baseline.gd"
	var comparison_count: int=0
	if FileAccess.file_exists(baseline_path):
		var prior_script: GDScript=load(baseline_path)
		var prior: Node3D=prior_script.new()
		var maps: Array=JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
		for stage in maps:
			if int(stage.stageNumber) in [15,40]: continue
			check(not stage.historicalBattlefield.has("heightLimitWorld"),"Other38 stages retain implicit height limit: "+str(stage.id))
			collect(prior,stage);collect(field,stage)
			check(JSON.stringify(prior._physical_contract(stage))==JSON.stringify(field._physical_contract(stage)),"Preserved physical fingerprint: "+str(stage.id))
			check(JSON.stringify(prior._geometry_contract(stage))==JSON.stringify(field._geometry_contract(stage)),"Preserved terrain cache fingerprint: "+str(stage.id))
			for p in [Vector2(.13,.69),Vector2(.5,.5),Vector2(.87,.15),Vector2(.04,.04),Vector2(.96,.96)]:
				check(field._raw_height(p)==prior._raw_height(p),"Independent preserved height calculation: "+str(stage.id)+" "+str(p))
			comparison_count+=1
		prior.free()
	elif "--compatibility-baseline" in OS.get_cmdline_user_args(): check(false,"Requested preserved baseline exists")
	var viewport: SubViewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	viewport.add_child(field)
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.size=18.5;camera.near=.1;camera.far=90;camera.current=true
	viewport.add_child(camera)
	var maximum_projection_error: float=0
	for pixels in [Vector2i(1280,720),Vector2i(1920,900)]:
		viewport.size=pixels
		for angle in [35.0,38.0,42.0,58.0,65.0]:
			collect(field,taller,angle,float(pixels.x)/pixels.y)
			# Direct callers have no configured geometry key; avoid unrelated cached grids.
			field.geometry_fingerprint=""
			field._build_height_grid()
			camera.position=Vector3(0,30,30/tan(deg_to_rad(angle)))
			camera.look_at(Vector3.ZERO,Vector3.UP)
			await process_frame
			for p in [Vector2(.13,.69),Vector2(.5,.5),Vector2(.35,.38),Vector2(.7,.55),Vector2(.87,.15)]:
				var error: float=camera.unproject_position(field.world_point(p)).distance_to(p*Vector2(pixels))
				maximum_projection_error=maxf(maximum_projection_error,error)
				check(error<.05,"Expanded-height foot stays on normalized gameplay anchor: "+str(pixels)+" "+str(angle)+" "+str(p))
	observations.append({"preservedStagesCompared":comparison_count,"maximumFootProjectionErrorPixels":maximum_projection_error})
	viewport.free()
	Battlefield.release_shared_resources()
	var file: FileAccess=FileAccess.open("user://height-limit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"));file.close()
	print("HEIGHT_LIMIT checks=%d failures=%d projectionError=%.6f"%[checks,failures.size(),maximum_projection_error])
	quit(0 if failures.is_empty() else 1)
