extends SceneTree
## CPU observation of the real LearningField. Images are not GPU rendered here.
const Field = preload("res://native/learning_field.gd")
const Presentation = preload("res://native/battlefield_presentation.gd")
const BattlefieldMaterials = preload("res://native/battlefield_materials.gd")
var checks: int = 0
var failures: Array = []
var samples: int = 0
var click_events: int = 0
var emissions: Array = []
var field: Control
var context: String = ""
var art_entries: Dictionary = {}
var art_observations: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(context+" · "+message)
		if failures.size()<=20: push_error(failures.back())

func settle() -> void:
	await process_frame
	await process_frame

func click(button: Button) -> void:
	var press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = button.get_global_rect().get_center()
	press.global_position = press.position
	Input.parse_input_event(press)
	await process_frame
	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = press.position
	release.global_position = press.position
	Input.parse_input_event(release)
	await process_frame
	click_events += 1

func inspect_mission(stage: Dictionary, mission: Dictionary) -> void:
	var expected_mirror: bool = Presentation.mirror_for_stage(stage)
	check(field.stage_id==str(stage.id),"Actual mission resolves its own original stage")
	check(field.presentation_mirrored==expected_mirror,"Stage orientation agrees with the shared battlefield policy")
	var active_art: Dictionary = art_entries.get(str(stage.id),{})
	check(not active_art.is_empty(),"This stage has its own active manifest entry")
	check(str(field.stage_art.get("mode",""))=="rendered" and str(field.stage_art.get("reason",""))=="","Active artwork passed the real resolver's source/geometry validation")
	check(bool(field.stage_art.get("sourceDataVerified",false)) and bool(field.stage_art.get("rawArtHashVerified",false)),"Source map and raw artwork hash are verified")
	check(str(field.stage_art.get("physicalGeometryFingerprint",""))==str(active_art.get("sourceGeometryFingerprint","")),"Actual physical geometry agrees with the manifest's claimed blueprint")
	var approved_texture: Texture2D = BattlefieldMaterials.rendered_art_texture(str(active_art.get("path","")),str(active_art.get("sha256","")))
	check(field.stage_texture!=null and field.stage_texture==approved_texture,"The learning image shares this stage's approved physical-battlefield texture, not a legacy photo")
	check(str(field.stage_art.get("artSha256",""))==str(active_art.get("sha256","")),"Learning image keeps the approved original texture fingerprint")
	check(JSON.stringify(field.mission)==JSON.stringify(mission),"Original mission/answer/action/target coordinates remain canonical")
	check(field.target_buttons.size()==mission.targets.size(),"No choice is added, removed or reordered")
	var draw_rect: Rect2 = field.background_draw_rect()
	for canonical in [Vector2.ZERO,Vector2.ONE,Vector2(.2,.6)]:
		check((draw_rect.position+draw_rect.size*canonical).distance_to(Presentation.to_view(canonical,expected_mirror)*field.size)<.001,"Whole background uses the same mirror transform as the battlefield")
		check(field.model_point(field.view_point(canonical)).distance_to(canonical)<.00001,"Display/model conversion round-trips independently of control size")
	for index in range(mission.targets.size()):
		var target: Dictionary = mission.targets[index]
		var point: Vector2 = Vector2(float(target.position.x),float(target.position.y))
		var button: Button = field.target_buttons[index]
		var picture: TextureRect = button.get_node("DestinationImage")
		check(button.name=="LearningTarget_"+str(target.id),"Stable target identity and ordering are preserved")
		check(field.target_anchors[index].distance_to(Presentation.to_view(point,expected_mirror))<.00001,"Display anchor matches the mirrored battlefield target")
		check(picture.flip_h==expected_mirror,"Choice image mirrors scenery without mirroring its Japanese text/button")
		check(picture.texture is AtlasTexture,"Choice still uses the real stage-image crop")
		if picture.texture is AtlasTexture:
			var crop: AtlasTexture = picture.texture
			check(crop.atlas==field.stage_texture,"Choice crop is bound to this stage's actual texture")
			var source_size: Vector2 = field.stage_texture.get_size()
			var crop_size: Vector2 = source_size*Vector2(.34,.42)
			var center: Vector2 = point*source_size
			var expected: Rect2 = Rect2(Vector2(clampf(center.x-crop_size.x*.5,0,source_size.x-crop_size.x),clampf(center.y-crop_size.y*.5,0,source_size.y-crop_size.y)),crop_size)
			check(crop.region.position.distance_to(expected.position)<.001 and crop.region.size.distance_to(expected.size)<.001,"Cropping uses canonical source pixels; display flip does not choose a different destination")
			var local_source: Vector2 = (center-crop.region.position)/crop.region.size
			var view_crop: Rect2 = Presentation.rect_to_view(Rect2(crop.region.position/source_size,crop.region.size/source_size),expected_mirror)
			var target_in_view: Vector2 = (field.view_point(point)-view_crop.position)/view_crop.size
			check(Presentation.to_view(local_source,expected_mirror).distance_to(target_in_view)<.00001,"Full-map and cropped-map destination positions describe the same scenery")
		check(button.get_node("ChoiceNumber").text==str(index+1),"Existing keyboard choice numbering is unchanged")
		check(button.scale==Vector2.ONE and button.get_node("DestinationWord").scale==Vector2.ONE,"Text and card controls stay upright")

func run() -> void:
	var profile: String = ProjectSettings.globalize_path("user://").replace("\\","/").simplify_path().to_lower()
	if not profile.begins_with(qa_project_path("tests/profiles/").to_lower()):
		push_error("Learning presentation QA requires tests/profiles isolated APPDATA")
		quit(2)
		return
	var maps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	var plans: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/battlefields-rendered/manifest.json"))
	for entry in manifest.get("stages",[]): art_entries[str(entry.stageId)] = entry
	var source_maps: String = FileAccess.get_file_as_string("res://native/maps.json")
	var source_plans: String = FileAccess.get_file_as_string("res://native/learning_plans.json")
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	field = Field.new()
	root.add_child(field)
	field.target_chosen.connect(func(id: String): emissions.append(id))
	await settle()
	var mirrored: int = 0
	for stage in maps:
		if Presentation.mirror_for_stage(stage): mirrored += 1
	for viewport_size in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		field.size = Vector2(viewport_size)
		for stage in maps:
			# Use Main's existing one-argument background API, rather than supplying
			# a test-only stage dictionary that could conceal a missing connection.
			field.set_stage_background(str(stage.get("background","")))
			for mission in plans.stages[str(stage.id)].missions:
				context = "%s %s %s" % [str(viewport_size),str(stage.id),str(mission.id)]
				field.begin_choice(mission,false)
				await settle()
				inspect_mission(stage,mission)
				if not art_observations.has(str(stage.id)):
					var art: Dictionary = art_entries.get(str(stage.id),{})
					var raw_hash: String = FileAccess.get_sha256(str(art.get("path","")))
					check(raw_hash==str(art.get("sha256","")),"Independent raw-file hash matches the approved original rendered pixels")
					if field.stage_texture!=null:
						var original: Image = Image.load_from_file(ProjectSettings.globalize_path(str(art.get("path",""))))
						var rendered: Image = field.stage_texture.get_image()
						check(rendered.get_size()==original.get_size(),"Active stage texture retains the original pixel dimensions")
						for ratio in [Vector2(.12,.18),Vector2(.38,.62),Vector2(.86,.76)]:
							var pixel: Vector2i = Vector2i(Vector2(original.get_size())*ratio)
							check(rendered.get_pixelv(pixel).is_equal_approx(original.get_pixelv(pixel)),"Actual bound texture retains independently read original color pixels")
					art_observations[str(stage.id)] = {"path":str(art.get("path","")),"rawSHA256":raw_hash,"physicalFingerprint":str(field.stage_art.get("physicalGeometryFingerprint","")),"mirrored":field.presentation_mirrored}
				if int(mission.get("wave",0))==1:
					for index in range(field.target_buttons.size()):
						var before: int = emissions.size()
						await click(field.target_buttons[index])
						check(emissions.size()==before+1 and str(emissions.back())==str(mission.targets[index].id),"Actual mouse click returns exactly its authored target ID, never a mirrored coordinate or different choice")
				field.show_hint()
				check(field.hinted and not field.resolved,"Hint behavior survives a mirrored stage")
				check(field.presentation_mirrored==Presentation.mirror_for_stage(stage),"Hint does not reset the stage orientation")
				field.show_result(true,"지원 성공",str(mission.answerId))
				check(field.resolved and field.correct_target==str(mission.answerId),"Result keeps the original correct target")
				var before: int = emissions.size()
				field._choose(str(mission.targets[0].id))
				check(emissions.size()==before,"Resolved task rejects another selection")
				samples += 1
			field.clear()
	# Mission identity also resolves orientation when no image was provided,
	# keeping passive/report-only calls and source-independent fixtures coherent.
	field.set_stage_background("")
	for stage in maps:
		var mission: Dictionary = plans.stages[str(stage.id)].missions[0]
		field.show_report(mission,false)
		check(field.stage_id==str(stage.id) and field.presentation_mirrored==Presentation.mirror_for_stage(stage),"Report-only mission resolves orientation after a previous different stage")
	field.clear()
	field.set_stage_background("")
	check(not field.presentation_mirrored and field.stage_id.is_empty(),"Clearing an unknown background does not retain the previous stage's mirror")
	check(FileAccess.get_file_as_string("res://native/maps.json")==source_maps,"Canonical maps file was not rewritten")
	check(FileAccess.get_file_as_string("res://native/learning_plans.json")==source_plans,"Canonical learning plans were not rewritten")
	var report: Dictionary = {"checks":checks,"failures":failures,"samples":samples,"maps":maps.size(),"missions":samples/3,"mirroredStages":mirrored,"unchangedStages":maps.size()-mirrored,"actualMouseClicks":click_events,"cpuOnly":true,"activeArtwork":art_observations,"scope":"Actual LearningField across 40 stages, 120 authored missions and three viewport sizes. Active resolver-approved per-stage deployed artwork with independent raw-file hash and source-geometry verification; canonical crop/source pixels and target/action/answer identity, display/background mirror geometry, upright text, real card mouse input and hint/result/stage switching. No Main save, gameplay or GPU visual claim.","sourceSHA256":{"learning_field.gd":FileAccess.get_sha256("res://native/learning_field.gd"),"maps.json":FileAccess.get_sha256("res://native/maps.json"),"learning_plans.json":FileAccess.get_sha256("res://native/learning_plans.json"),"manifest.json":FileAccess.get_sha256("res://assets/battlefields-rendered/manifest.json")}}
	var output = FileAccess.open("user://qa_learning_presentation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	field.queue_free()
	await settle()
	print("LEARNING_PRESENTATION_QA ",checks," checks; samples=",samples," actualClicks=",click_events," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

# Source root also works for external packed verifiers without res://tests.
func qa_project_path(relative_path: String="") -> String:
	var script_path: String=get_script().resource_path.replace("\\","/")
	if script_path.begins_with("res://"): script_path=ProjectSettings.globalize_path(script_path)
	var project_root: String=script_path.get_base_dir().get_base_dir().simplify_path()
	if not project_root.is_absolute_path(): return "__invalid_qa_project__/"
	return project_root if relative_path.is_empty() else project_root.path_join(relative_path)
