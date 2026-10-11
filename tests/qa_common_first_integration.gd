extends SceneTree
## Actual Main / Game / Troops3D boundary. Candidate fixture is isolated input,
## never appended to Main.maps or the production map catalog.
## --fixture=res://path.json supplies {stage:{...worldGeometry...}} or a stage.
## GPU runs additionally require --capture and an HQ-issued --gpu-slot= token.
## --furigana-audit opts into isolated native text surfaces and unresolved gates.
## --furigana-hover-focus limits a named GPU run to native hover and critical UI.
const Store = preload("res://native/progress.gd")
var checks: int = 0
var failures: Array[String] = []
var blockers: Array[String] = []
var captures: Array = []
var observations: Array = []
var timings: Dictionary = {}
var app: Node
var capture_requested: bool = false
var initial_hashes: Dictionary = {}
var fixture_path: String = ""
var gpu_slot: String = ""
var furigana_requested: bool = false
var hover_focus: bool = false
var furigana_surfaces: Array = []
var furigana_geometry: Array = []
var audit_started_usec: int = 0
var fixture_presentation: Dictionary = {}
var desktop_first_stage: bool = false
var desktop_source_path: String = ""
var desktop_source_contract: Dictionary = {}
var desktop_events: Array = []

func audit_journal(event: Dictionary) -> void:
	if not furigana_requested:
		return
	var path: String = "user://qa-common-first-furigana-progress.jsonl"
	var output: FileAccess = FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if output == null:
		check(false,"Furigana intermediate evidence file opens")
		return
	event["elapsed_seconds"] = float(Time.get_ticks_usec()-audit_started_usec)/1000000.0
	event["checks"] = checks
	event["failure_count"] = failures.size()
	output.seek_end()
	output.store_line(JSON.stringify(event))
	output.close()

func layout_geometry(control: Control, layout: Dictionary, group: int = -1) -> Dictionary:
	var runs: Array = []
	for run in layout.get("runs",[]):
		if group>=0 and int(run.get("group",-1))!=group:
			continue
		runs.append({"role":run.role,"text":run.text,"group":run.get("group",-1),"local_bounds":str(run.bounds),"global_bounds":str(global_run_bounds(control,run.bounds)),"screen_font_pixels":screen_font_pixels(control,int(run.size))})
	return {"path":str(root.get_path_to(control)),"text":str(control.word.get("jp","")),"control_bounds":str(control.get_global_rect()),"parent_bounds":str(control.get_parent().get_global_rect()) if control.get_parent() is Control else "","clip":str(visible_clip(control)),"layout_height":layout.get("height",0),"group":group,"runs":runs}

func inspect_transition_geometry(note: String) -> void:
	var transition: Node = app.learning_transition
	var heading: Label = transition.heading
	var caption: Label = transition.caption
	var ruby: Control = heading.get_node_or_null("VisibleAnnotatedText") as Control
	if ruby == null or not heading.is_visible_in_tree() or visible_alpha(ruby)<.05 or visible_alpha(caption)<.05:
		return
	var layout: Dictionary = ruby.get_text_layout()
	var face: Font = caption.get_theme_font("font")
	var point_size: int = caption.get_theme_font_size("font_size")
	var text_width: float = face.get_string_size(caption.text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x
	# Native transition caption is one centered, unwrapped Korean line.
	var local_caption: Rect2 = Rect2(Vector2((caption.size.x-text_width)*.5,0),Vector2(text_width,face.get_height(point_size)))
	var caption_bounds: Rect2 = global_run_bounds(caption,local_caption)
	var banner_bounds: Rect2 = transition.banner.get_global_rect()
	var first_failure: int = failures.size()
	check(banner_bounds.grow(.5).encloses(caption_bounds),note+": native caption glyph bounds remain inside transition banner")
	for run in layout.get("runs",[]):
		if str(run.role) in ["body","reading"]:
			check(not global_run_bounds(ruby,run.bounds).intersects(caption_bounds),note+": transition heading glyphs do not overlap native caption glyph bounds")
			check(banner_bounds.grow(.5).encloses(global_run_bounds(ruby,run.bounds)),note+": annotated heading glyph bounds remain inside transition banner")
	var record: Dictionary = {"surface":note,"reason":"transition_heading_caption","phase":transition.phase,"banner_bounds":str(banner_bounds),"heading_bounds":str(heading.get_global_rect()),"caption_bounds":str(caption.get_global_rect()),"caption_ink_bounds":str(caption_bounds),"geometry":layout_geometry(ruby,layout)}
	furigana_geometry.append(record)
	audit_journal({"kind":"transition_geometry","record":record,"failure_notes":failures.slice(first_failure)})

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, note: String) -> bool:
	checks += 1
	if not value:
		failures.append(note)
		push_error("COMMON_FIRST_INTEGRATION " + note)
	return value

func canonical(value: String) -> String:
	return value.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func hash_directory(directory: String, result: Dictionary) -> void:
	for child in DirAccess.get_directories_at(directory):
		hash_directory(directory.path_join(child), result)
	for name_value in DirAccess.get_files_at(directory):
		if name_value.get_extension() in ["gd", "json", "gdshader", "tscn", "tres", "png", "jpg", "jpeg", "svg", "webp", "ttf", "otf"]:
			var path: String = directory.path_join(name_value)
			# This controlled runner uses the adapter's default surface, not UX's
			# independent composition/material authoring modules.
			if path in ["res://native/remaster_visual_slice.gd", "res://native/remaster_surface_materials.gd"]:
				continue
			result[path] = FileAccess.get_sha256(path)

func hashes() -> Dictionary:
	var result: Dictionary = {}
	hash_directory("res://native", result)
	for directory in ["res://assets/materials", "res://assets/fonts", "res://assets/ui", "res://assets/units", "res://assets/units-animated"]:
		if DirAccess.dir_exists_absolute(directory):
			hash_directory(directory, result)
	for path in ["res://project.godot", "res://tests/qa_common_first_integration.gd", "res://tools/run.ps1"]:
		result[path] = FileAccess.get_sha256(path)
	if not fixture_path.is_empty() and FileAccess.file_exists(fixture_path):
		result[fixture_path] = FileAccess.get_sha256(fixture_path)
	if furigana_requested:
		for path in ["res://assets/narration/manifest.json","res://assets/announcements/manifest.json"]:
			result[path] = FileAccess.get_sha256(path)
	return result

func guarded_profile() -> bool:
	var allowed: String = canonical(ProjectSettings.globalize_path("res://tests/profiles/"))
	var roaming: String = canonical(OS.get_environment("APPDATA"))
	var local: String = canonical(OS.get_environment("LOCALAPPDATA"))
	var user_path: String = canonical(ProjectSettings.globalize_path("user://"))
	if not check(roaming.begins_with(allowed + "/qa-common-first-") and local == roaming and user_path.begins_with(roaming + "/"), "Only disposable QA common-first profiles are allowed"):
		return false
	return check((DisplayServer.get_name() != "headless" and not gpu_slot.is_empty()) if capture_requested else DisplayServer.get_name() == "headless", "GPU needs capture flag and named HQ slot; ordinary mode is headless")

func settle(count: int = 3) -> void:
	for unused in range(count):
		await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	await settle(1)

func motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await settle(1)

func transaction() -> String:
	return JSON.stringify({"gold":app.game.gold, "queue":app.game.recruitment_queue, "units":app.game.units, "pending":app.game.pending, "account":app.progress.data})

func contains_kanji(text: String) -> bool:
	for index in range(text.length()):
		var code: int = text.unicode_at(index)
		if code in [0x3005,0x3007,0x303b] or (code>=0x3400 and code<=0x4dbf) or (code>=0x4e00 and code<=0x9fff) or (code>=0xf900 and code<=0xfaff) or (code>=0x20000 and code<=0x323af):
			return true
	return false

func contains_kana(text: String) -> bool:
	for index in range(text.length()):
		var code: int = text.unicode_at(index)
		if (code>=0x3041 and code<=0x3096) or (code>=0x30a1 and code<=0x30fa) or (code>=0xff66 and code<=0xff9d):
			return true
	return false

func visible_clip(control: Control) -> Rect2:
	var viewport: Viewport = control.get_viewport()
	var clip: Rect2 = viewport.get_visible_rect()
	var ancestor: Node = control.get_parent()
	# Canvas ancestry ends at its own Viewport (including a native tooltip Window).
	# Controls above that boundary are in another canvas coordinate system.
	while ancestor != null and ancestor != viewport:
		if ancestor is Control and ancestor.clip_contents:
			clip = clip.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return clip

func visible_alpha(control: CanvasItem, ignore_self: bool = false) -> float:
	var alpha: float = 1.0 if ignore_self else control.self_modulate.a
	var ancestor: Node = control
	while ancestor != null and ancestor != control.get_viewport():
		if ancestor is CanvasItem:
			alpha *= ancestor.modulate.a
		ancestor = ancestor.get_parent()
	return alpha

func global_run_bounds(control: Control, bounds: Rect2) -> Rect2:
	var transform: Transform2D = control.get_global_transform()
	var result: Rect2 = Rect2(transform*bounds.position,Vector2.ZERO)
	for corner in [Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		result = result.expand(transform*corner)
	return result

func screen_font_pixels(item: CanvasItem, nominal_size: int) -> float:
	var transform: Transform2D = item.get_screen_transform()
	var a: float = transform.x.dot(transform.x)
	var b: float = transform.x.dot(transform.y)
	var c: float = transform.y.dot(transform.y)
	var minimum_eigenvalue: float = (a+c-sqrt((a-c)*(a-c)+4.0*b*b))*.5
	return float(nominal_size)*sqrt(maxf(0.0,minimum_eigenvalue))

func reading_glyph_geometry(control: Control, run: Dictionary) -> Dictionary:
	# Godot 4.7 Font::draw_string shapes a TextLine. TextServer draws each glyph
	# at baseline + shaped offset + advance, then uses the actual cached glyph
	# offset/size (including outline). See engine font.cpp:334 and
	# text_server_adv.cpp:3972. Full font ascent/descent is not its ink rectangle.
	var server: TextServer = TextServerManager.get_primary_interface()
	var face: Font = control.reading_font if control.reading_font!=null else control.font
	var result: Dictionary = {"valid":false,"quads":[],"glyphs":[],"baseline":str(run.position),"line_box":str(run.bounds),"reason":"Unsupported raster configuration"}
	var viewport_factor: float = control.get_viewport().get_oversampling()
	if not face is FontFile or face.multichannel_signed_distance_field or face.fixed_size>0 or (face.oversampling>0 and not is_equal_approx(face.oversampling,1.0)) or not is_equal_approx(viewport_factor,1.0):
		return result
	var version: Dictionary = Engine.get_version_info()
	if int(version.major)!=4 or int(version.minor)!=7 or not server.get_name().contains("HarfBuzz"):
		return result
	var line: TextLine = TextLine.new()
	if not line.add_string(str(run.text),face,int(run.size)):
		result.reason = "Actual reading font cannot shape the complete run"
		return result
	line.get_size()
	var pen: float = 0.0
	for glyph in server.shaped_text_get_glyphs(line.get_rid()):
		var rid: RID = glyph.font_rid
		if not rid.is_valid():
			result.reason = "Missing glyph font; native hexadecimal fallback is not a reading proof"
			return result
		var size_value: int = int(glyph.font_size)
		if server.font_is_multichannel_signed_distance_field(rid) or server.font_get_antialiasing(rid)==TextServer.FONT_ANTIALIASING_LCD or not is_equal_approx(server.font_get_scale(rid,size_value),1.0):
			return result
		var subpixel: int = server.font_get_subpixel_positioning(rid)
		# These public 4.7 AUTO thresholds are 16px/20px in text_server.h.
		var quarter: bool = subpixel==TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER or (subpixel==TextServer.SUBPIXEL_POSITIONING_AUTO and size_value<=16)
		var half: bool = subpixel==TextServer.SUBPIXEL_POSITIONING_ONE_HALF or (subpixel==TextServer.SUBPIXEL_POSITIONING_AUTO and size_value<=20 and not quarter)
		for unused in range(int(glyph.repeat)):
			var position: Vector2 = Vector2(run.position)+Vector2(pen,0)+Vector2(glyph.offset)
			var encoded_index: int = int(glyph.index)&0xffffff
			if quarter:
				encoded_index |= (int(floor(4.0*(position.x+.125))-4.0*floor(position.x+.125))<<27)
				position.x += .125
			elif half:
				encoded_index |= (int(floor(2.0*(position.x+.25))-2.0*floor(position.x+.25))<<27)
				position.x += .25
			position = position.floor()
			var outlines: Array[int] = [0]
			if int(control.outline_size)>0: outlines.append(int(control.outline_size))
			for outline in outlines:
				var cache_size: Vector2i = Vector2i(size_value,outline)
				server.font_render_glyph(rid,cache_size,int(glyph.index))
				var offset: Vector2 = server.font_get_glyph_offset(rid,cache_size,encoded_index)
				var extent: Vector2 = server.font_get_glyph_size(rid,cache_size,encoded_index)
				var quad: Rect2 = Rect2(position+offset,extent)
				if quad.has_area():
					result.quads.append(quad)
					result.glyphs.append({"index":int(glyph.index),"encoded_index":encoded_index,"outline":outline,"offset":str(offset),"size":str(extent),"local_quad":str(quad),"global_quad":str(global_run_bounds(control,quad))})
			pen += float(glyph.advance)
	result.valid = not result.quads.is_empty()
	result.reason = "Actual shaped raster glyph and outline draw quads; no arbitrary clipping tolerance" if result.valid else "No graphical reading glyph was rasterized"
	return result

func inspect_visible_furigana(note: String, parent: Node = null) -> void:
	if not furigana_requested:
		return
	var surface: Node = app if parent == null else parent
	# The owner exposes the same refresh used by resize/draw. Refresh first so
	# the headless inspection traverses the actual annotated children as well.
	for control in surface.find_children("*","Control",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.has_method("refresh_ruby"):
			control.refresh_ruby()
	var ruby_controls: int = 0
	var plain_kanji_controls: int = 0
	var first_failure: int = failures.size()
	var first_geometry: int = furigana_geometry.size()
	var tooltip_candidates: Array = []
	for node in surface.find_children("*","Control",true,false):
		var control: Control = node as Control
		if control == null or not control.is_visible_in_tree() or control.is_queued_for_deletion() or visible_alpha(control,true)<.05:
			continue
		var clip: Rect2 = visible_clip(control)
		if not clip.intersects(control.get_global_rect()):
			continue
		var path: String = str(root.get_path_to(control))
		var native_text: String = str(control.text) if control is Label or control is Button or control is RichTextLabel else ""
		var annotated_wrapper: bool = contains_kanji(native_text) and control.has_method("refresh_ruby")
		if annotated_wrapper:
			var child: Control = control.get_node_or_null("VisibleAnnotatedText") as Control
			check(child != null and child.has_method("get_text_layout") and child.is_visible_in_tree() and visible_alpha(child)>.05 and clip.intersects(child.get_global_rect()),note+": typed native text has an actual visible Ruby child: "+path)
			if child != null and child.has_method("get_text_layout"):
				check(str(child.word.get("jp",""))==native_text,note+": annotated wrapper draws the unchanged complete native text: "+path)
			if control is Button:
				for colour_key in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_outline_color"]:
					check(control.get_theme_color(colour_key).a==0,note+": wrapper replaces duplicate native glyphs: "+path)
		if visible_alpha(control)<.05:
			continue
		if contains_kanji(control.tooltip_text):
			tooltip_candidates.append({"path":path,"text":control.tooltip_text,"status":"Native hover and popup rendering still required"})
		if control.has_method("get_text_layout") and control.has_method("_pieces"):
			ruby_controls += 1
			var layout: Dictionary = control.get_text_layout()
			var parts: Array = control._pieces()
			var joined: String = ""
			for piece in parts:
				var text: String = str(piece.get("text",""))
				var reading: String = str(piece.get("reading",""))
				joined += text
				if contains_kanji(text):
					check(contains_kana(reading) and not contains_kanji(reading),note+": every kanji span has authored kana: "+path+" / "+text)
			check(joined == str(control.word.get("jp","")),note+": ruby preserves the complete base string: "+path)
			if control.get_parent() is Button:
				if not check(control.get_parent().get_global_rect().grow(.5).encloses(control.get_global_rect()),note+": actual Ruby block fits its native button allocation: "+path):
					furigana_geometry.append({"surface":note,"reason":"button_allocation","geometry":layout_geometry(control,layout)})
			var visible_body_groups: Dictionary = {}
			var reading_groups: Dictionary = {}
			var drawn_body: String = ""
			for run in layout.get("runs",[]):
				var drawn: Rect2 = global_run_bounds(control,run.bounds)
				if str(run.role)=="body":
					drawn_body += str(run.text)
				if str(run.role)=="body" and contains_kanji(str(run.text)) and clip.intersects(drawn):
					visible_body_groups[int(run.get("group",-1))] = true
				elif str(run.role)=="reading":
					reading_groups[int(run.get("group",-1))] = true
				elif str(run.role)=="meaning" and contains_kanji(str(run.text)) and clip.intersects(drawn):
					check(false,note+": kanji in translation is drawn without ruby: "+path+" / "+str(run.text))
			check(drawn_body.replace(" ","").replace("\n","").replace("\t","")==joined.replace(" ","").replace("\n","").replace("\t",""),note+": actual body draw runs preserve every non-whitespace source glyph: "+path)
			for group in visible_body_groups:
				check(reading_groups.has(group),note+": visible kanji has an actual reading draw run: "+path)
			for run in layout.get("runs",[]):
				if str(run.role)!="reading" or not visible_body_groups.has(int(run.get("group",-1))):
					continue
				check(int(run.size)>=16,note+": visible kana remains at least 16px: "+path)
				check(screen_font_pixels(control,int(run.size))>=16.0-.001,note+": actual screen transform keeps kana at least 16px: "+path+" / "+str(screen_font_pixels(control,int(run.size))))
				check(Color(run.get("color",Color.TRANSPARENT)).a>.1,note+": actual reading ink is visible: "+path)
				check(Rect2(Vector2.ZERO,control.size).grow(.5).encloses(run.bounds),note+": kana glyph fits its allocated control: "+path)
				var proof: Dictionary = reading_glyph_geometry(control,run)
				check(bool(proof.valid),note+": actual shaped reading glyph and outline geometry is available: "+path+" / "+str(proof.reason))
				var glyphs_fit: bool = bool(proof.valid)
				for quad in proof.quads:
					glyphs_fit = glyphs_fit and clip.encloses(global_run_bounds(control,quad))
				if not check(glyphs_fit,note+": kana remains inside viewport and every clipping ancestor: "+path):
					furigana_geometry.append({"surface":note,"reason":"reading_clip","geometry":layout_geometry(control,layout,int(run.get("group",-1))),"glyph_geometry":proof})
				elif not clip.encloses(global_run_bounds(control,run.bounds)):
					furigana_geometry.append({"surface":note,"reason":"linebox_clip_diagnostic","geometry":layout_geometry(control,layout,int(run.get("group",-1))),"glyph_geometry":proof})
			var runs: Array = layout.get("runs",[])
			for first in range(runs.size()):
				if str(runs[first].role)!="reading" or not visible_body_groups.has(int(runs[first].get("group",-1))):
					continue
				for second in range(runs.size()):
					if second>first or str(runs[second].role)!="reading":
						check(not runs[first].bounds.intersects(runs[second].bounds),note+": kana overlaps no body, meaning or other kana glyph run: "+path)
		else:
			var text: String = ""
			if control is Label or control is Button or control is RichTextLabel:
				text = str(control.text)
			if contains_kanji(text) and not annotated_wrapper:
				plain_kanji_controls += 1
				check(false,note+": visible plain text has no ruby rendering: "+path+" / "+text)
	furigana_surfaces.append({"surface":note,"ruby_controls":ruby_controls,"plain_kanji_controls":plain_kanji_controls,"failures":failures.size()-first_failure,"tooltip_candidates":tooltip_candidates,"scope":"Actual native controls and measured draw runs; CPU inspection does not certify rendered pixels or pronunciation accuracy"})
	audit_journal({"kind":"surface_complete","surface":furigana_surfaces[-1],"failure_notes":failures.slice(first_failure),"geometry":furigana_geometry.slice(first_geometry)})

func inspect_empty_menu_furigana() -> void:
	if not furigana_requested:
		return
	var settings: Button = app.front_end.get_node_or_null("HomeSettings") as Button
	if check(settings != null and not settings.disabled,"Furigana audit uses actual available settings navigation"):
		await mouse(settings.get_global_rect().get_center(),true)
		await mouse(settings.get_global_rect().get_center(),false)
		inspect_visible_furigana("settings / "+str(root.size))
	app.front_end.show_catalog(0,false)
	await settle()
	inspect_visible_furigana("empty sortie catalog / "+str(root.size))
	app.front_end.show_catalog(0,true)
	await settle()
	inspect_visible_furigana("empty dictionary catalog / "+str(root.size))
	app.front_end.show_campaign_map()
	await settle()
	inspect_visible_furigana("atlas / "+str(root.size))
	var atlas: Node = app.front_end.find_child("CampaignAtlas",true,false)
	if atlas != null and atlas.has_method("_show_credits"):
		atlas._show_credits()
		await settle()
		inspect_visible_furigana("atlas source popup / "+str(root.size))
	else:
		observations.append({"case":"empty-catalog Atlas source navigation","scope":"Native _build_atlas intentionally opens empty catalog with no Atlas; actual source popup is tested on the disconnected historical Atlas fixture"})
	app.front_end.show_home()
	await settle()

func inspect_history_fixture() -> void:
	if not furigana_requested:
		return
	# Display-only metadata in a disconnected real Atlas. No playable Main map,
	# old world geometry, stage selection signal or campaign reward is registered.
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	var geography: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
	var metadata: Array = []
	for entry in story.get("stages",[]):
		metadata.append({"id":entry.stageId,"stageNumber":entry.stageNumber,"title":entry.battleKo})
	var atlas: Control = load("res://native/campaign_atlas.gd").new()
	atlas.name = "QADisconnectedHistoricalAtlas"
	app.front_end.hide()
	app.add_child(atlas)
	atlas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atlas.configure(app.progress,metadata,story,geography,null)
	for entry in metadata:
		if hover_focus and int(entry.stageNumber)!=1:
			continue
		atlas.chapter_index = int((int(entry.stageNumber)-1)/10)
		atlas.show_stage(str(entry.id),false)
		await settle()
		inspect_visible_furigana("isolated actual historical Atlas "+str(entry.id)+" / "+str(root.size))
		if atlas.detail_scroll != null:
			atlas.detail_scroll.scroll_vertical = int(atlas.detail_scroll.get_v_scroll_bar().max_value)
			await settle()
			inspect_visible_furigana("historical detail scrolled "+str(entry.id)+" / "+str(root.size))
	var credits: Button = atlas.get_node_or_null("AtlasCredits") as Button
	if check(credits != null and credits.is_visible_in_tree(),"Disconnected actual Atlas exposes its native source button"):
		credits.pressed.emit()
		await settle()
		var popup: Control = atlas.get_node_or_null("AtlasSourceCredits") as Control
		if check(popup != null and popup.is_visible_in_tree(),"Actual Atlas source callback creates the native popup"):
			inspect_visible_furigana("actual disconnected Atlas source popup / "+str(root.size),popup)
			if hover_focus:
				await capture("native-source-popup-%dx%d" % [root.size.x,root.size.y])
			var scroll: ScrollContainer = popup.find_child("CreditScroll",true,false) as ScrollContainer
			if scroll != null:
				scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
				await settle()
				inspect_visible_furigana("actual disconnected Atlas source popup scrolled / "+str(root.size),popup)
			var close: Button = popup.find_child("AtlasCreditClose",true,false) as Button
			if check(close != null,"Actual Atlas source popup exposes its native close callback"):
				close.pressed.emit()
				await settle()
	check(app.maps.is_empty() and app.game.config.is_empty(),"Historical display fixture registers no playable Main map or battle")
	atlas.queue_free()
	app.front_end.show_home()
	await settle()
	observations.append({"case":"disconnected actual historical Atlas","scope":"All authored history metadata through native Atlas renderer; isolated display fixture, no natural campaign entry or restored world"})

func inspect_practice_fixture(stage: Dictionary) -> void:
	if not furigana_requested:
		return
	app.front_end.hide()
	app.unit_training.open_menu("archer")
	await settle()
	inspect_visible_furigana("isolated actual practice menu / "+str(root.size))
	if check(app.unit_training.open("archer",stage),"Isolated drill uses the new QA geometry and actual practice renderer"):
		app.unit_training.set_process(false)
		await settle()
		inspect_visible_furigana("isolated actual practice drill / "+str(root.size))
		await capture("furigana-drill-%dx%d" % [root.size.x,root.size.y])
	app.unit_training.close()
	await settle()

func inspect_selected_canvas_furigana() -> void:
	if not furigana_requested or app.game.units.is_empty():
		return
	var unit: Dictionary = app.game.units[0]
	var authoritative: String = JSON.stringify(app.game.actor_states())
	var layout: Dictionary = app.game.selected_unit_label_layout(unit)
	var visible: Rect2 = app.game.visible_field_rect_local()
	var readings: Dictionary = {}
	var body: String = ""
	for run in layout.runs:
		if str(run.role)=="reading":
			readings[int(run.group)] = true
			check(int(run.size)>=16 and Color(run.color).a>.1,"Actual selected-unit canvas kana has visible font and ink")
			check(screen_font_pixels(app.game.actor_overlay,int(run.size))>=16.0-.001,"Actual selected-unit canvas screen-scale kana stays at least 16px")
			check(visible.grow(.5).encloses(run.bounds),"Actual selected-unit canvas kana remains inside field clip")
		elif str(run.role)=="body":
			body += str(run.text)
	for run in layout.runs:
		if str(run.role)=="body" and contains_kanji(str(run.text)):
			check(readings.has(int(run.group)),"Actual selected-unit canvas kanji has the reading group used by draw_string")
	check(body == str(unit.get("jp","")),"Actual selected-unit canvas preserves the paid actor name")
	check(JSON.stringify(app.game.actor_states())==authoritative,"Reading draw layout leaves authoritative actors unchanged")
	furigana_surfaces.append({"surface":"actual paid actor selected-name canvas / "+str(root.size),"scope":"Native selected_unit_label_layout consumed by actual draw_string path; rendered pixel review pending","name":body})

func inspect_banner_furigana() -> void:
	if not furigana_requested:
		return
	var feedback: Node2D = app.combat_feedback
	if not check(feedback.has_method("annotated_text_layout"),"Actual combat feedback exposes its cached draw layout"):
		return
	var before: String = JSON.stringify(app.game.actor_states())
	for action in ["wavebegin","waveend"]:
		feedback.consume_event({"action":action,"wave":1})
		check(feedback.banner_clock>0 and contains_kanji(str(feedback.banner)),"Real feedback event creates the Japanese banner: "+action)
		var layout: Dictionary = feedback.annotated_text_layout(str(feedback.banner),19)
		var readings: Dictionary = {}
		var body: String = ""
		var width: float = minf(520,app.game.field_rect.size.x-16)
		for run in layout.get("runs",[]):
			if str(run.role)=="reading":
				readings[int(run.group)] = true
				check(int(run.size)>=16 and screen_font_pixels(feedback,int(run.size))>=16.0-.001,"Actual banner cached kana stays at least 16 screen pixels")
			check(Rect2(0,0,width,float(layout.height)).grow(.5).encloses(run.bounds),"Actual banner cached draw glyph fits its measured block")
			if str(run.role)=="body": body += str(run.text)
		for run in layout.get("runs",[]):
			if str(run.role)=="body" and contains_kanji(str(run.text)):
				check(readings.has(int(run.group)),"Actual banner draw path has a reading run for every kanji group")
		check(body.replace(" ","")==str(feedback.banner).replace(" ",""),"Actual banner cached body preserves the event text")
		furigana_surfaces.append({"surface":"actual event banner "+action+" / "+str(root.size),"text":feedback.banner,"clock":feedback.banner_clock,"scope":"Real consume_event plus exact cached layout used by _ink; raster review pending"})
	check(JSON.stringify(app.game.actor_states())==before,"Banner events and draw layout leave authoritative actors unchanged")

func inspect_native_hover_furigana() -> void:
	if not furigana_requested:
		return
	var card: Button = app.army_grid.get_node_or_null("DeployCard_spear") as Button
	if not check(card != null and card.is_visible_in_tree() and contains_kanji(card.tooltip_text),"Actual deployment card exposes the authored kanji tooltip"):
		return
	var before: String = transaction()
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = card.get_global_rect().get_center()
	event.global_position = event.position
	event.button_mask = 0
	Input.parse_input_event(event)
	var delay: float = float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec",.5))+.25
	await create_timer(delay).timeout
	var popup: Control = root.find_child("AnnotatedTooltip",true,false) as Control
	if popup == null or not popup.is_visible_in_tree() or not popup.get_global_rect().has_area():
		blockers.append("Native tooltip popup was not observed after actual hover at "+str(root.size)+"; no manual tooltip construction substitutes for this route")
	else:
		var ancestors: Array = []
		var ancestor: Node = popup
		while ancestor != null:
			ancestors.append({"path":str(ancestor.get_path()),"class":ancestor.get_class(),"same_viewport":ancestor.get_viewport()==popup.get_viewport(),"clip_contents":ancestor.clip_contents if ancestor is Control else false,"bounds":str(ancestor.get_global_rect()) if ancestor is Control else ""})
			ancestor = ancestor.get_parent()
		observations.append({"case":"native tooltip Window ancestry","resolution":str(root.size),"viewport_path":str(popup.get_viewport().get_path()),"window_position":str(popup.get_window().position),"window_size":str(popup.get_window().size),"embedded":popup.get_window().is_embedded(),"ancestors":ancestors})
		inspect_visible_furigana("actual native hovered deployment tooltip / "+str(root.size),popup)
		var ruby: Control = popup.find_child("TooltipRuby",true,false) as Control
		check(ruby != null and str(ruby.word.get("jp",""))==card.tooltip_text,"Actual native popup draws the unchanged complete tooltip text")
		if int(furigana_surfaces[-1].get("ruby_controls",0))==0:
			blockers.append("Native hover popup exists but no visible Ruby draw runs were observable at "+str(root.size)+"; text correspondence alone is not rendered tooltip acceptance")
			var detail: Dictionary = {"case":"native tooltip observability","resolution":str(root.size),"popup_bounds":str(popup.get_global_rect()),"viewport_bounds":str(popup.get_viewport().get_visible_rect()),"viewport_transform":str(popup.get_viewport_transform()),"ruby_visible":ruby.is_visible_in_tree() if ruby != null else false,"ruby_bounds":str(ruby.get_global_rect()) if ruby != null else "","ruby_clip":str(visible_clip(ruby)) if ruby != null else ""}
			observations.append(detail)
			audit_journal({"kind":"tooltip_unobservable","detail":detail})
		if capture_requested:
			await RenderingServer.frame_post_draw
			var texture: Texture2D = popup.get_viewport().get_texture()
			var pixels: Image = texture.get_image() if texture != null else null
			var path: String = "user://furigana-native-tooltip-%dx%d.png" % [root.size.x,root.size.y]
			if check(pixels != null and not pixels.is_empty() and pixels.save_png(path)==OK,"Actual hovered tooltip viewport pixels are saved"):
				captures.append({"label":"native deployment tooltip","path":ProjectSettings.globalize_path(path),"size":[pixels.get_width(),pixels.get_height()]})
				if ruby != null:
					inspect_tooltip_pixels(ruby,pixels)
	check(transaction()==before,"Native tooltip hover leaves account, paid orders and actors unchanged")
	event.position = Vector2(2,2)
	event.global_position = event.position
	Input.parse_input_event(event)
	await settle()

func inspect_tooltip_pixels(ruby: Control, pixels: Image) -> void:
	# Inspect the actual native popup texture, without changing its draw state.
	var viewport: Viewport = ruby.get_viewport()
	if not check(Vector2i(viewport.get_visible_rect().size)==pixels.get_size(),"Tooltip texture has one pixel per viewport coordinate for measured ink"):
		return
	var runs: Array = ruby.get_text_layout().get("runs",[])
	var reading_count: int = 0
	for run in runs:
		if str(run.role)!="reading":
			continue
		reading_count += 1
		var proof: Dictionary = reading_glyph_geometry(ruby,run)
		check(bool(proof.valid),"Tooltip pixel audit uses supported actual raster glyph geometry")
		for glyph_number in range(proof.get("glyphs",[]).size()):
			var glyph: Dictionary = proof.glyphs[glyph_number]
			if int(glyph.outline)!=0:
				continue
			var quad: Rect2 = global_run_bounds(ruby,proof.quads[glyph_number])
			var region: Rect2i = Rect2i(Vector2i(quad.position.floor()),Vector2i(quad.end.ceil())-Vector2i(quad.position.floor()))
			if not check(Rect2i(Vector2i.ZERO,pixels.get_size()).encloses(region),"Native tooltip glyph texture is inside captured viewport"):
				continue
			var ink_pixels: int = 0
			var colour: Color = run.get("color",Color.TRANSPARENT)
			for y in range(region.position.y,region.end.y):
				for x in range(region.position.x,region.end.x):
					var pixel: Color = pixels.get_pixel(x,y)
					if pixel.a>.1 and Vector3(pixel.r,pixel.g,pixel.b).distance_to(Vector3(colour.r,colour.g,colour.b))<.2:
						ink_pixels += 1
			check(ink_pixels>0,"Actual native tooltip reading glyph has captured colour ink: "+str(run.text))
			observations.append({"case":"actual tooltip reading pixels","resolution":str(root.size),"text":str(run.text),"glyph_index":glyph.index,"viewport_quad":str(quad),"ink_pixels":ink_pixels,"reading_colour":str(colour),"screen_font_pixels":screen_font_pixels(ruby,int(run.size)),"scope":"Actual native popup texture; colour ink inside each shaped glyph quad, visual screenshot review also required"})
	check(reading_count>0,"Actual tooltip pixel audit includes kana reading draw runs")

func inspect_grammar_caption_updates() -> void:
	var before: String = transaction()
	var original_expanded: bool = app.learning_readout_expanded
	app._set_intermission_presentation(false,true)
	app._sync_announcement_reading()
	if not original_expanded:
		app.learning_readout_button.pressed.emit()
		await settle(1)
	check(app.learning_readout_expanded,"Actual native readout toggle opens GrammarCaption before word advancement")
	var original_started: bool = app.battle_started
	var original_index: int = app.learning_index
	var original_turn: int = app.learning_turn
	var original_clock: float = app.learning_clock
	var original_word: Dictionary = app.active_word.word.duplicate(true)
	var original_example: Dictionary = app.example_label.word.duplicate(true)
	var original_caption: String = app.learning_caption.text
	var original_context: Array = app.learning_caption.ruby_context_words.duplicate(true)
	var lesson_identity: String = JSON.stringify(app.current_lesson)
	# Existing isolated display path only: suppress the actual exposure-save and
	# speech branches while using native word advancement and authored examples.
	app.battle_started = false
	app.learning_index = -1
	app.learning_turn = 0
	for unused in range(1 if hover_focus else app.learning_words.size()):
		app._advance_word()
		await settle(1)
		var word: Dictionary = app.learning_words[app.learning_index]
		var note: String = "actual GrammarCaption update "+str(app.current_lesson.id)+" / "+str(word.id)+" / "+str(root.size)
		check(app.learning_panel.is_visible_in_tree() and app.learning_caption.is_visible_in_tree(),note+": actual native learning panel is visible")
		check(str(app.active_word.word.get("jp",""))==str(word.get("jp","")),note+": native word advancement uses the unchanged authored word")
		inspect_visible_furigana(note,app.learning_panel)
	app.battle_started = original_started
	app.learning_index = original_index
	app.learning_turn = original_turn
	app.learning_clock = original_clock
	app.active_word.set_word(original_word,36)
	app.example_label.set_word(original_example,24)
	app.learning_caption.ruby_context_words = original_context
	app.learning_caption.text = original_caption
	app.learning_caption.refresh_ruby()
	if app.learning_readout_expanded!=original_expanded:
		app.learning_readout_button.pressed.emit()
	app._layout()
	check(transaction()==before and JSON.stringify(app.current_lesson)==lesson_identity,"Actual GrammarCaption updates preserve account, orders, actors and authored lesson identity")
	audit_journal({"kind":"grammar_caption_updates_complete","lesson_id":str(app.current_lesson.id),"words":1 if hover_focus else app.learning_words.size(),"resolution":str(root.size)})

func inspect_story_study_fixture() -> void:
	if not furigana_requested:
		return
	if not check(app.has_method("_candidate_display_allowed") and app._candidate_display_allowed(),"Existing native display handlers allow only the configured isolated candidate"):
		return
	var original_map: Dictionary = app.current_map.duplicate(true)
	var original_story: Dictionary = app.current_story.duplicate(true)
	var original_lesson: Dictionary = app.current_lesson.duplicate(true)
	var original_words: Array = app.learning_words.duplicate(true)
	var expected_account: Dictionary = app.progress.data.duplicate(true)
	var catalog_data: String = FileAccess.get_file_as_string("res://native/maps.json")
	var stories: Array = app.campaign_story.get("stages",[])
	for story in stories:
		if hover_focus and int(story.stageNumber)!=1:
			continue
		var number: int = int(story.stageNumber)-1
		var tier: String = ["basic","beginner","intermediate","advanced"][clampi(number/10,0,3)]
		var lessons: Array = app.curriculum.get(tier,[])
		if not check(lessons.size()>number%10,"Actual story has corresponding authored curriculum metadata"):
			continue
		app.current_story = story.duplicate(true)
		app.current_map["title"] = str(story.battleKo)
		app.current_lesson = lessons[number%10].duplicate(true)
		app.learning_words = app.current_lesson.get("newWords",[]).duplicate(true)
		await inspect_grammar_caption_updates()
		app._show_briefing()
		await settle()
		if not check(app.modal != null and app.modal_context=="briefing","Actual isolated Main story briefing opens without map registration"):
			continue
		inspect_visible_furigana("actual Main story briefing "+str(story.stageId)+" / "+str(root.size))
		if app.modal_scroll != null:
			app.modal_scroll.scroll_vertical = int(app.modal_scroll.get_v_scroll_bar().max_value)
			await settle()
			inspect_visible_furigana("actual Main briefing scrolled "+str(story.stageId)+" / "+str(root.size))
		app._close_modal(false)
		app._show_study()
		await settle()
		if not check(app.modal != null and app.modal_context=="study","Actual isolated Main dictionary opens without map registration"):
			continue
		inspect_visible_furigana("actual Main dictionary "+str(app.current_lesson.id)+" / "+str(root.size))
		for scroll in app.modal.find_children("*","ScrollContainer",true,false):
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await settle()
		inspect_visible_furigana("actual Main dictionary scrolled "+str(app.current_lesson.id)+" / "+str(root.size))
		if hover_focus:
			await capture("critical-reading-study-scroll-%dx%d" % [root.size.x,root.size.y])
		app._close_modal(false)
		audit_journal({"kind":"story_study_complete","stage_id":str(story.stageId),"lesson_id":str(app.current_lesson.id),"resolution":str(root.size)})
	app.current_map = original_map
	app.current_map["title"] = "격리 검증 · 전장 후보"
	app.current_story = stories[0].duplicate(true) if not stories.is_empty() else {}
	app.current_lesson = original_lesson
	app.learning_words = original_words
	var original_finished: bool = app.battle_finished
	var original_victory: bool = app.last_victory
	for won in ([] if hover_focus else [false,true]):
		app.battle_finished = false
		app._on_battle_finished({"victory":won,"battleElapsedSeconds":1.0})
		await settle()
		if not check(app.modal != null and app.modal_context=="result","Actual isolated battle-result renderer opens with no next-map indexing"):
			continue
		inspect_visible_furigana("actual isolated battle result "+str(won)+" / "+str(root.size))
		app.modal_scroll.scroll_vertical = int(app.modal_scroll.get_v_scroll_bar().max_value)
		await settle()
		inspect_visible_furigana("actual isolated battle result scrolled "+str(won)+" / "+str(root.size))
		app._close_modal(false)
	app.current_map = original_map
	app.current_story = original_story
	app.battle_finished = original_finished
	app.last_victory = original_victory
	check(app.maps.is_empty() and FileAccess.get_file_as_string("res://native/maps.json")==catalog_data,"Actual briefing/dictionary/result fixtures preserve the empty playable catalog")
	check(app.progress.data==expected_account and app.last_campaign_reward.is_empty(),"Actual isolated display/result handlers write no account progress or rewards")
	if app.game.paused:
		app.game.pause_battle()
	app._on_state(app.game.snapshot())
	await settle()
	furigana_surfaces.append({"surface":"native Main briefing/dictionary/result fixture / "+str(root.size),"stories":stories.size(),"scope":"Authorised isolated candidate display condition; authored metadata only, Main.maps=[], no campaign entry/progression/rewards"})

func bound_fixture_mission(source: Dictionary) -> Dictionary:
	if str(source.get("id",""))!=str(fixture_presentation.get("contextMissionId","")):
		blockers.append("Controlled context mission has no explicitly authored QA floor binding")
		return {}
	var bindings: Dictionary = fixture_presentation.get("contextTargetBindings",{})
	var result: Dictionary = source.duplicate(true)
	var provider: Node3D = app.troops_3d.battlefield
	for target in result.get("targets",[]):
		var binding: Dictionary = bindings.get(str(target.get("id","")),{})
		if not binding.get("position") is Dictionary or not binding.get("world") is Dictionary:
			blockers.append("Controlled context target lacks explicit new-floor normalized/world anchor: "+str(target.get("id","")))
			return {}
		var point: Vector2 = Vector2(float(binding.position.x),float(binding.position.y))
		var expected: Vector3 = Vector3(float(binding.world.x),float(binding.world.y),float(binding.world.z))
		var actual: Vector3 = provider.world_point(point)
		var ray: Dictionary = provider.ray_pick(expected+Vector3.UP*5.0,Vector3.DOWN)
		var valid: bool = actual.is_finite() and actual.distance_to(expected)<.0001 and provider.placement_clear(point,.01) and bool(ray.get("valid",false)) and bool(ray.get("walkable",false))
		if not check(valid,"Explicit QA context target is on authored new walkable floor with world/placement/ray agreement: "+str(target.id)):
			return {}
		check(provider.world_to_normalized(actual).distance_to(point)<.0001 and Vector3(ray.worldPosition).distance_to(expected)<.0001,"QA target normalized/world/ray roundtrip matches the explicitly authored anchor")
		check(app.game.screen_to_field_point(app.game.field_point_to_screen(point)).distance_to(point)<.002,"Actual Main Game/Troops pick projection matches controlled context anchor")
		target["position"] = binding.position.duplicate(true)
	# Remove only the new spatial field to prove IDs, labels, authored kana,
	# report and grading metadata were neither rewritten nor inferred.
	var restored: Dictionary = result.duplicate(true)
	for target in restored.get("targets",[]): target.erase("position")
	check(restored==source,"Controlled new-world binding changes only explicit target positions; original mission/answer/readings unchanged")
	observations.append({"case":"controlled QA context binding","mission_id":source.id,"bindings":bindings,"scope":"One explicitly authored new QA floor binding through existing _mission_task and native Main/LearningField; production Stage01/all40 bindings remain pending"})
	return result

func inspect_learning_fixture() -> void:
	if not furigana_requested:
		return
	# Actual lesson/gate tasks and their unchanged answer identities. Only the UI
	# result presentation is toggled; no answer submission, reward or save occurs.
	app.current_map["background"] = "res://assets/ui/barracks-warroom.png"
	var seen: Array = []
	for word in app.current_lesson.get("newWords",[]):
		seen.append(str(word.id))
	for kind_index in range(3):
		app.lesson_session.begin_lesson(app.current_lesson,app.current_map)
		app.lesson_session.practice_counter = kind_index
		app.quiz_task = app.lesson_session.next_task(seen,2,true)
		if not check(not app.quiz_task.is_empty(),"Actual lesson issues isolated learning task index "+str(kind_index)):
			continue
		var identity: String = JSON.stringify(app.quiz_task)
		app.quiz_resolved = false
		app.quiz_hinted = false
		app._show_quiz()
		await create_timer(.15).timeout
		inspect_visible_furigana("actual learning transition "+str(app.quiz_task.kind)+" / "+str(root.size))
		inspect_transition_geometry("actual learning transition "+str(app.quiz_task.kind)+" / "+str(root.size))
		await create_timer(.7).timeout
		inspect_visible_furigana("actual learning choice "+str(app.quiz_task.kind)+" / "+str(root.size))
		await capture("furigana-choice-%s-%dx%d" % [str(app.quiz_task.kind),root.size.x,root.size.y])
		check(JSON.stringify(app.quiz_task)==identity,"Ruby presentation preserves lesson task, choice and grading identities")
		app._cancel_learning_transition()
		app._close_modal(false)
		app.quiz_resolved = true
		app.quiz_feedback_text = str(app.quiz_word.get("ko",""))
		app._show_quiz()
		await create_timer(.85).timeout
		inspect_visible_furigana("actual learning result "+str(app.quiz_task.kind)+" / "+str(root.size))
		check(JSON.stringify(app.quiz_task)==identity,"Result presentation preserves task identity without submitting an answer")
		app._cancel_learning_transition()
		app._close_modal(false)
	app.unlock_gate = load("res://native/learning_gate.gd").new()
	var gate_status: Dictionary = app.unlock_gate.start(app.current_lesson,str(app.current_map.id))
	if check(bool(gate_status.get("ok",false)),"Actual private gate creates assessment UI fixture"):
		app.gate_active = true
		app.quiz_task = app.unlock_gate.current_task()
		app.quiz_resolved = false
		app.quiz_hinted = false
		var gate_identity: String = JSON.stringify(app.quiz_task)
		app._show_quiz()
		await create_timer(.85).timeout
		inspect_visible_furigana("actual gate examination choice / "+str(root.size))
		check(JSON.stringify(app.quiz_task)==gate_identity,"Exam UI preserves grading identities and shows authored ruby")
		app._cancel_learning_transition()
		app._close_modal(false)
		app.gate_active = false
	var missions: Array = app.learning_plans.get("stages",{}).get("basic-forest",{}).get("missions",[])
	if not missions.is_empty():
		var source_identity: String = JSON.stringify(missions[0])
		var bound_mission: Dictionary = bound_fixture_mission(missions[0])
		app.quiz_task = app.lesson_session._mission_task(bound_mission,1) if not bound_mission.is_empty() else {}
		if not bound_mission.is_empty() and check(not app.quiz_task.is_empty(),"Authored context report plus explicit new-floor binding creates an isolated native choice fixture"):
			var context_identity: String = JSON.stringify(app.quiz_task)
			app.quiz_hinted = false
			app.quiz_resolved = false
			app._show_quiz()
			await create_timer(.85).timeout
			check(app.learning_field.target_buttons.size()==bound_mission.targets.size(),"Actual bound context creates all live native target buttons before transition focus")
			for index in range(app.learning_field.target_anchors.size()):
				var target: Dictionary = bound_mission.targets[index]
				var point: Vector2 = Vector2(float(target.position.x),float(target.position.y))
				check(app.learning_field.target_anchors[index].distance_to(app.learning_field.view_point(point))<.001,"Actual context renderer anchor draws the explicitly bound normalized target")
			inspect_visible_furigana("actual context choice / "+str(root.size))
			app.learning_field.show_hint()
			await settle()
			inspect_visible_furigana("actual context hint / "+str(root.size))
			app.learning_field.show_result(true,str(missions[0].get("successKo","")),str(app.quiz_task.answerId))
			await settle()
			inspect_visible_furigana("actual context result / "+str(root.size))
			check(JSON.stringify(app.quiz_task)==context_identity,"Context hint/result rendering preserves task, answer IDs and grading")
			app._cancel_learning_transition()
		check(JSON.stringify(missions[0])==source_identity,"Controlled context leaves production authored mission metadata unchanged")
	else:
		blockers.append("Authored basic context mission is unavailable for native display fixture")
	app.quiz_task = {}
	app.quiz_resolved = false
	app.quiz_word = {}
	app.context_task_active = false
	app.learning_field.clear()
	app._show_pause_menu()
	await settle()
	inspect_visible_furigana("actual pause menu / "+str(root.size))
	app._close_modal(false)
	if app.game.paused:
		app.game.pause_battle()
	app.game.set_input_enabled(true)
	app._on_state(app.game.snapshot())
	await settle()
	for manifest_path in ["res://assets/narration/manifest.json","res://assets/announcements/manifest.json"]:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		for caption in manifest.get("clips",[]):
			if not contains_kanji(str(caption.get("jp",""))):
				continue
			if manifest_path.contains("announcements"):
				app._on_announcement_started(caption)
			else:
				app._on_narration_started(caption)
			await settle()
			inspect_visible_furigana("actual subtitle "+str(caption.get("id",""))+" / "+str(root.size))
			app._stop_narration()

func verify_empty_barracks() -> void:
	var expected: Dictionary = app.progress.data.duplicate(true)
	app._show_barracks()
	await settle()
	inspect_visible_furigana("barracks / "+str(root.size))
	var practice: Button = app.barracks.get_node_or_null("BarracksTraining") as Button
	check(practice != null and practice.disabled, "Empty catalog disables actual Barracks practice button")
	check(app.barracks.can_train, "Empty catalog preserves permanent-growth permission")
	var upgrade: Button = app.barracks.find_child("Train_archer",true,false) as Button
	check(upgrade != null and not upgrade.disabled, "Fresh affordable archer upgrade stays enabled independently of practice")
	if practice != null:
		await mouse(practice.get_global_rect().get_center(),true)
		await mouse(practice.get_global_rect().get_center(),false)
	check(app.barracks.visible and not app.unit_training.visible and app.game.config.is_empty(), "Disabled practice click cannot open a nonexistent world")
	check(app.progress.data == expected, "Inspecting empty-catalog practice/growth controls leaves account unchanged")
	app.barracks.hide()
	app._return_from_barracks()
	await settle()

func verify_native_drop() -> void:
	var card: Button = app.army_grid.get_node_or_null("DeployCard_spear") as Button
	if not check(card != null and not card.disabled and card.is_visible_in_tree(), "Actual fresh spear card is available"):
		return
	var target: Vector2 = Vector2(INF,INF)
	var candidates: Array = []
	var base: Dictionary = app.game.ground_combat.select_march_base(-1)
	if not check(not base.is_empty(), "Actual Game provides the selected marching deployment base"):
		return
	for point in [base.position]:
		var pointer: Vector2 = app.game.field_point_to_screen(point)
		var surface: Dictionary = app._deployment_surface_point(pointer)
		var preview: Dictionary = app.game.deployment_preview("spear",point,"")
		candidates.append({"point":point,"pointer":pointer,"surface":surface,"preview":preview})
		if not surface.is_empty() and bool(preview.get("valid",false)):
			target = pointer
			break
	observations.append({"case":"native-input-targets","canPrepare":app._can_prepare_placement(),"betweenWaves":app.game.between_waves,"inputEnabled":app.game.input_enabled,"candidatePoints":candidates})
	if not check(target.is_finite(), "At least one actual visible world point accepts fresh spear drag"):
		return
	var before: String = transaction()
	var gold: int = app.game.gold
	var jobs: int = app.game.recruitment_queue.size()
	await mouse(card.get_global_rect().get_center(),true)
	check(transaction() == before, "Native card press does not spend or submit")
	await motion(target)
	check(not app.deployment_drag.is_empty() and transaction() == before, "Held native world hover is a pure preview")
	await mouse(target,false)
	check(app.game.recruitment_queue.size() == jobs+1 and app.game.gold == gold-app.game.recruit_cost("spear") and app.deployment_drag.is_empty(), "Native release on authored surface submits exactly one paid order")
	var committed: String = transaction()
	await mouse(target,false)
	check(transaction() == committed, "Duplicate native release cannot replay accepted world order")

func capture(label_value: String) -> void:
	if not capture_requested:
		return
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if not check(pixels != null and not pixels.is_empty(), "Native GPU pixels available: " + label_value):
		return
	var path: String = "user://common-first-" + label_value + ".png"
	if check(pixels.save_png(path) == OK, "Native screenshot saved: " + label_value):
		captures.append({"label":label_value, "path":ProjectSettings.globalize_path(path), "size":[pixels.get_width(),pixels.get_height()]})

func percentile(values: Array[float], quantile: float) -> Variant:
	if values.is_empty():
		return null
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(quantile * sorted.size())) - 1, 0, sorted.size() - 1)]

func sample_frames(label_value: String, warmup_seconds: float = 2.0, measured_seconds: float = 4.0) -> void:
	var warmup_end: int = Time.get_ticks_usec() + int(warmup_seconds * 1000000)
	while Time.get_ticks_usec() < warmup_end:
		await process_frame
	var frames: Array[float] = []
	var cpu_process: Array[float] = []
	var stalls: int = 0
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var memory_start: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var actor_peak: int = 0
	while Time.get_ticks_usec() - start < int(measured_seconds * 1000000):
		await process_frame
		var now: int = Time.get_ticks_usec()
		var milliseconds: float = float(now - previous) / 1000.0
		previous = now
		frames.append(milliseconds)
		cpu_process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if milliseconds > 50.0:
			stalls += 1
		actor_peak = maxi(actor_peak, app.troops_3d.actors.size())
	timings[label_value] = {
		"warmup_seconds":warmup_seconds, "measured_wall_seconds":float(previous-start)/1000000.0,
		"samples":frames.size(), "frame_ms_p50":percentile(frames,.50), "frame_ms_p95":percentile(frames,.95), "frame_ms_p99":percentile(frames,.99),
		"stalls_over_50ms":stalls, "main_process_ms_p50":percentile(cpu_process,.50),
		"memory_static_bytes_start":memory_start, "memory_static_bytes_end":Performance.get_monitor(Performance.MEMORY_STATIC),
		"troops_actor_peak":actor_peak, "gpu_time_ms":null,
		"scope":"Rendered native frame intervals; GPU duration unavailable" if capture_requested else "Headless event-loop intervals, not GPU/FPS evidence"
	}

func exercise_world(stage: Dictionary) -> void:
	var adapter_path: String = "res://native/battlefield_world_adapter.gd"
	if not FileAccess.file_exists(adapter_path):
		blockers.append("FUNCTIONAL world adapter is not available")
		return
	if not stage.get("worldGeometry") is Dictionary or stage.get("worldGeometry",{}).is_empty():
		blockers.append("Fixture needs the owner-provided worldGeometry stage contract")
		return
	if not app.has_method("configure_candidate"):
		blockers.append("FUNCTIONAL Main candidate binding is pending")
		return
	app.set_process(false)
	var configured: Dictionary = app.configure_candidate(stage)
	if not check(bool(configured.get("ok",false)), "Actual Main configures isolated new-world candidate: " + str(configured.get("reason",""))):
		return
	var music_key: String = str(stage.id)
	var prior_music: Variant = app.music_by_stage.get(music_key)
	if furigana_requested:
		var source_id: String = str(fixture_presentation.get("musicFromAuthoredStageId",""))
		if check(app.music_by_stage.has(source_id),"QA result display explicitly selects existing authored story music metadata"):
			app.music_by_stage[music_key] = app.music_by_stage[source_id].duplicate(true)
			observations.append({"case":"isolated authored music credit binding","source_stage_id":source_id,"candidate_id":music_key,"scope":"Existing authored metadata associated only with disposable candidate; music setting remains false, no production music/catalog writes"})
	var provider: Node3D = app.troops_3d.battlefield
	check(not bool(configured.get("catalogRegistered",true)) and not bool(configured.get("campaignRewards",true)), "Main candidate hook forbids campaign registration/rewards")
	app.troops_3d.show()
	app.game.start_battle()
	app.battle_started = true
	app.game.set_input_enabled(true)
	# Controlled boundary verification: real renderer and HUD, manually advanced
	# authoritative Game; this is explicitly not a natural-wave performance run.
	app.game.set_process(false)
	app.set_process(false)
	# Paid production uses the actual shared recruitment path, fresh roster only.
	app.game.enemies.clear()
	app.game.spawn_queue = ["raider"]
	app.game.spawn_source_waves = [1]
	app.game.spawn_metadata = [{}]
	app.game.spawn_clock = 100000.0
	check(app.game.begin_placement("spear",0), "Fresh isolated starter spear uses actual paid recruitment")
	for unused in range(240):
		if not app.game.units.is_empty():
			break
		app.game.advance_simulation(.05)
	app._on_state(app.game.snapshot())
	await settle()
	check(app.maps.is_empty(), "Candidate is never added to Main's playable map list")
	check(app.troops_3d.battle == app.game and app.troops_3d.battlefield == provider, "Actual Main Troops renderer binds the authoritative Game and provider")
	if not check(app.troops_3d.has_method("uses_world_geometry") and app.troops_3d.uses_world_geometry(), "Actual Troops projection advertises authored world geometry"):
		return
	check(not app.game.units.is_empty() and not app.troops_3d.actors.is_empty(), "Actual paid Game production creates actors through Main's Troops3D")
	var fixed_world_point: Vector3 = provider.world_point(Vector2(.70,.65))
	var navigation_before: bool = provider.segment_clear(Vector2(.3,.5), Vector2(.7,.5), .01)
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		app._layout()
		await settle()
		inspect_visible_furigana("controlled actual Main HUD / "+str(dimensions))
		check(provider.world_point(Vector2(.70,.65)).distance_to(fixed_world_point) < .0001, "Resizing Main does not move authored world coordinates")
		check(provider.segment_clear(Vector2(.3,.5), Vector2(.7,.5), .01) == navigation_before, "Main resize keeps navigation clearance unchanged")
		for point in [Vector2(.30,.35),Vector2(.5,.5),Vector2(.70,.65)]:
			var world_point: Vector3 = provider.world_point(point)
			check(provider.world_to_normalized(world_point).distance_to(point) < .0001, "Provider roundtrip at " + str(dimensions) + " / " + str(point))
			check(app.troops_3d.normalized_to_world(point).distance_to(world_point) < .0001 and app.troops_3d.world_to_normalized(world_point).distance_to(point) < .0001, "Actual Troops coordinate contract agrees with authored world, without camera shear")
			var screen: Vector2 = app.game.field_point_to_screen(point)
			var picked: Vector2 = app.game.screen_to_field_point(screen)
			check(picked.distance_to(point) < .002, "Actual Game/Troops screen picking roundtrip at " + str(dimensions) + " / " + str(point))
		check(root.get_visible_rect().encloses(app.hud_gold.get_global_rect()) and root.get_visible_rect().encloses(app.hud_capacity.get_global_rect()), "Actual live HUD is inside native resolution " + str(dimensions))
		var snapshot: Dictionary = app.game.snapshot()
		app._on_state(snapshot)
		check(app.hud_gold.text.contains(str(int(snapshot.get("gold",-1)))), "HUD reads current simulation gold")
		var logical_before: String = JSON.stringify(app.game.actor_states())
		app.troops_3d.sync_actor_states(app.game.actor_states())
		app.troops_3d.sync_actor_states(app.game.actor_states())
		check(JSON.stringify(app.game.actor_states()) == logical_before, "Repeated rendering does not change authoritative actor states")
		await verify_native_drop()
		if hover_focus and not app.game.units.is_empty():
			var selected_before: String = JSON.stringify(app.game.actor_states())
			app.game.select_unit(int(app.game.units[0].id))
			await settle()
			check(app.game.selected_id==int(app.game.units[0].id) and app.game._selected_name_visible(app.game.units[0]),"Actual paid actor selection enables the native selected-name canvas draw branch")
			check(JSON.stringify(app.game.actor_states())==selected_before,"Actual selection preserves authoritative actor state")
		inspect_selected_canvas_furigana()
		inspect_banner_furigana()
		if hover_focus:
			await capture("native-hud-selected-banner-%dx%d" % [dimensions.x,dimensions.y])
		await inspect_native_hover_furigana()
		await capture("controlled-world-%dx%d" % [dimensions.x,dimensions.y])
		if not hover_focus:
			await inspect_learning_fixture()
		await inspect_story_study_fixture()
	# Preserve account exactly; common fixture never runs Main's result callback.
	app.game.close_battle()
	app.troops_3d.sync_actor_states([])
	check(app.troops_3d.actors.is_empty(), "Game teardown clears rendered actors")
	if prior_music == null: app.music_by_stage.erase(music_key)
	else: app.music_by_stage[music_key] = prior_music
	observations.append({"case":"actual-Main-world-boundary", "fixture":fixture_path, "mapsRegistered":0, "scope":"Controlled isolated geometry boundary only; no natural battle, artwork approval or advanced motion signoff"})

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture": capture_requested = true
		elif arg.begins_with("--fixture="): fixture_path = arg.trim_prefix("--fixture=")
		elif arg.begins_with("--gpu-slot="): gpu_slot = arg.trim_prefix("--gpu-slot=")
		elif arg == "--furigana-audit": furigana_requested = true
		elif arg == "--furigana-hover-focus": hover_focus = true
		elif arg == "--desktop-first-stage": desktop_first_stage = true
		elif arg.begins_with("--expected-source="): desktop_source_path = arg.trim_prefix("--expected-source=")
	if desktop_first_stage:
		await run_desktop_first_stage()
		return
	if hover_focus and not check(furigana_requested and capture_requested and not gpu_slot.is_empty(),"Focused native hover requires furigana audit, GPU capture and named HQ slot"):
		quit(2)
		return
	if not guarded_profile():
		quit(2)
		return
	audit_started_usec = Time.get_ticks_usec()
	initial_hashes = hashes()
	audit_journal({"kind":"start","source_hashes_before":initial_hashes,"fixture":fixture_path,"resolution_plan":["1280x800","1440x900"],"scope":"Incomplete progress evidence until final source/account/teardown checks and final report"})
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if not check(catalog is Array and catalog.is_empty(), "This candidate harness requires the real empty catalog, with no replacement/reset"):
		quit(2)
		return
	var store: RefCounted = Store.new()
	store.save_path = "user://common-first-fixture.json"
	store.read_save()
	store.data.settings.voice = false
	store.data.settings.music = false
	store.data.settings.effects = false
	var expected_account: Dictionary = store.data.duplicate(true)
	var startup: int = Time.get_ticks_usec()
	app = load("res://native/main.tscn").instantiate()
	app.progress = store
	root.add_child(app)
	await settle()
	timings["empty_Main_startup_ms"] = float(Time.get_ticks_usec()-startup)/1000.0
	check(app.maps.is_empty() and app.game.config.is_empty(), "Actual Main starts empty without QA map registration")
	check(app.troops_3d.battle == app.game, "Actual Main connects Troops3D to Game")
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		app._layout()
		await settle()
		inspect_visible_furigana("home / "+str(dimensions))
		await capture("empty-home-%dx%d" % [dimensions.x,dimensions.y])
		if capture_requested and not hover_focus:
			await sample_frames("empty-home-%dx%d" % [dimensions.x,dimensions.y])
		if not hover_focus:
			await verify_empty_barracks()
			await inspect_empty_menu_furigana()
		await inspect_history_fixture()
	if fixture_path.is_empty():
		blockers.append("Owner-provided isolated new-world fixture is pending; shell checks are not world integration acceptance")
	elif not check(fixture_path.begins_with("res://") and FileAccess.file_exists(fixture_path), "Fixture is an existing local workspace resource"):
		pass
	else:
		var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		if check(input is Dictionary, "Fixture JSON is an object"):
			fixture_presentation = input.get("presentation",{}).duplicate(true)
			await exercise_world(input.get("stage", input))
			if furigana_requested and not hover_focus:
				for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
					root.size = dimensions
					root.content_scale_size = dimensions
					app._layout()
					await inspect_practice_fixture(input.get("stage",input))
	check(store.data == expected_account, "Candidate harness preserves isolated account data without progress/result writes")
	if furigana_requested:
		observations.append({"case":"remaining all-visible-kanji acceptance","unverified":["Fresh-account conditional campaign-completion/reward/unlock UI","Rendered GPU pixels and pronunciation accuracy"],"scope":"These remain outside this actual controlled CPU display sweep; no full acceptance claim"})
	var exit_start: int = Time.get_ticks_usec()
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await settle()
	timings["Main_teardown_ms"] = float(Time.get_ticks_usec()-exit_start)/1000.0
	var final_hashes: Dictionary = hashes()
	var changed_sources: Array[String] = []
	for path in initial_hashes:
		if final_hashes.get(path) != initial_hashes[path]: changed_sources.append(path)
	for path in final_hashes:
		if not initial_hashes.has(path): changed_sources.append(path)
	check(changed_sources.is_empty(), "Native source/data and fixture are unchanged during verification")
	var status: String = "FAIL" if not failures.is_empty() else ("BLOCKED" if not blockers.is_empty() else "PASS")
	var report: Dictionary = {
		"directive_id":"JP_DF-HQ-20261008-COMMON-FIRST-R1", "task_id":"QA-01", "owner":"QA", "status":status,
		"checks":checks, "failures":failures, "blockers":blockers, "sourceHashes":initial_hashes, "source_hashes_after":final_hashes, "changed_sources":changed_sources, "sourceFreezeUnchanged":changed_sources.is_empty(),
		"captures":captures, "observations":observations, "timings":timings, "gpu_slot":gpu_slot,
		"furigana_requested":furigana_requested, "furigana_surfaces":furigana_surfaces,"furigana_geometry":furigana_geometry,
		"hover_focus":hover_focus,
		"display_driver":DisplayServer.get_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name() if capture_requested else "headless",
		"cpu":OS.get_processor_name(), "processor_count":OS.get_processor_count(),
		"scope":"Actual empty Main + optional controlled candidate Game/Troops/HUD boundary; no accepted stage, advanced motion approval, natural full battle or game GPU performance acceptance"
	}
	var output: FileAccess = FileAccess.open("user://qa-common-first-integration.json", FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	audit_journal({"kind":"complete","status":status,"source_hashes_after":final_hashes,"changed_sources":changed_sources,"sourceFreezeUnchanged":changed_sources.is_empty(),"blockers":blockers,"final_report":ProjectSettings.globalize_path("user://qa-common-first-integration.json")})
	print("COMMON_FIRST_INTEGRATION ",status," ",checks," checks / ",failures.size()," failures; ",ProjectSettings.globalize_path("user://qa-common-first-integration.json"))
	quit(1 if status == "FAIL" else (2 if status == "BLOCKED" else 0))

func desktop_hashes() -> Dictionary:
	var result: Dictionary = hashes()
	for path in ["res://Play.cmd","res://native/remaster_visual_slice.gd","res://native/remaster_surface_materials.gd","res://assets/music/lobby/manifest.json"]:
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	if DirAccess.dir_exists_absolute("res://assets/battlefields-remaster"):
		hash_directory("res://assets/battlefields-remaster",result)
	return result

func desktop_button(parent: Node, value: String) -> Button:
	if parent == null: return null
	for node in parent.find_children("*","Button",true,false):
		if str(node.text)==value and node.is_visible_in_tree() and not node.is_queued_for_deletion():
			return node as Button
	return null

func desktop_click(button: Button, note: String, scroll: ScrollContainer = null) -> bool:
	if not check(is_instance_valid(button) and not button.is_queued_for_deletion() and not button.disabled and button.is_visible_in_tree(),note+": actual enabled native button exists"):
		return false
	# Let native hover/input routing see the actual pointer before the press.
	var hover: InputEventMouseMotion = InputEventMouseMotion.new()
	hover.position = button.get_global_rect().get_center()
	hover.global_position = hover.position
	hover.button_mask = 0
	Input.parse_input_event(hover)
	await settle(2)
	if not check(is_instance_valid(button) and not button.is_queued_for_deletion() and not button.disabled and button.is_visible_in_tree(),note+": native target survives pointer/layout settling"):
		return false
	if scroll!=null:
		# Ruby/layout updates can shift a result button after a one-shot scroll.
		var deadline: int = Time.get_ticks_usec()+5000000
		var stable_frames: int = 0
		var previous: Dictionary = {}
		while Time.get_ticks_usec()<deadline and is_instance_valid(button):
			scroll.ensure_control_visible(button)
			await process_frame
			var bounds: Rect2 = button.get_global_rect()
			var area: Rect2 = visible_clip(button).intersection(bounds)
			var state: Dictionary = {"bounds":str(bounds),"clip":str(visible_clip(button)),"input_area":str(area),"scroll_vertical":scroll.scroll_vertical,"scroll_max":scroll.get_v_scroll_bar().max_value}
			if area.has_area():
				hover.position = area.get_center()
				hover.global_position = hover.position
				Input.parse_input_event(hover)
			stable_frames = stable_frames+1 if area.has_area() and state==previous else 0
			previous = state
			if stable_frames>=3: break
		observations.append({"case":"actual result scroll input stabilization","action":note,"state":previous,"stable_frames":stable_frames,"scope":"Real ensure_control_visible and native pointer motion; no forced button position or callback"})
		if not check(stable_frames>=3,note+": actual scrolled button input area stabilizes within bounded5s"):
			await capture("desktop-retry-input-unavailable")
			return false
	var visible: Rect2 = visible_clip(button).intersection(button.get_global_rect())
	if not check(visible.has_area(),note+": actual button has a visible input area"):
		return false
	await mouse(visible.get_center(),true)
	await mouse(visible.get_center(),false)
	await settle()
	return true

func desktop_frontend_state() -> Dictionary:
	var stage: Button = app.front_end.find_child("Stage_basic-forest",true,false) as Button
	var stage_state: Dictionary = {"exists":is_instance_valid(stage)}
	if is_instance_valid(stage):
		stage_state.merge({"path":str(stage.get_path()),"disabled":stage.disabled,"visible":stage.is_visible_in_tree(),"queued_for_deletion":stage.is_queued_for_deletion(),"bounds":str(stage.get_global_rect()),"clip":str(visible_clip(stage))})
	return {"view":str(app.front_end.view),"front_end_visible":app.front_end.is_visible_in_tree(),"catalog_prepared":app.front_end.catalog_prepared,"catalog_total":app.front_end.catalog_preparation_total,"catalog_error":str(app.front_end.catalog_preparation_error),"maps_count":app.front_end.maps.size(),"first_stage_unlocked":app.progress.map_unlocked("basic-forest"),"stage_button":stage_state}

func desktop_wait_catalog_entry() -> bool:
	var deadline: int = Time.get_ticks_usec()+10000000
	var stable_frames: int = 0
	while Time.get_ticks_usec()<deadline:
		var stage: Button = app.front_end.find_child("Stage_basic-forest",true,false) as Button
		var ready: bool = str(app.front_end.view)=="catalog" and app.front_end.is_visible_in_tree() and is_instance_valid(stage) and not stage.is_queued_for_deletion() and not stage.disabled and stage.is_visible_in_tree()
		var fading: bool = app.front_end.fade!=null and app.front_end.fade.is_running()
		stable_frames = stable_frames+1 if ready and not fading else 0
		if stable_frames>=3:
			observations.append({"case":"actual Home click catalog readiness","state":desktop_frontend_state(),"scope":"Native pointer/click followed by bounded real UI mode/control settling; no direct callback or replacement catalog"})
			return true
		await process_frame
	observations.append({"case":"actual Home click catalog readiness timeout","state":desktop_frontend_state()})
	return check(false,"Actual Home click reaches the visible canonical catalog within bounded10s")

func desktop_resize(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	app._layout()
	await settle()

func desktop_save_identity_regression() -> void:
	# Independent private save fixture, never used to unlock the fresh battle.
	var store: RefCounted = Store.new()
	store.save_path = "user://desktop-later-identity.json"
	var later_id: String = ""
	for id in store.stage_numbers:
		if int(store.stage_numbers[id])==40: later_id = str(id)
	if not check(store.stage_numbers.size()==40 and not later_id.is_empty(),"Historical identity still covers all40 while playable catalog has one stage"):
		return
	store.complete_map(later_id,{"seen":2,"correct":1,"attempts":2,"qaNavigationFixture":true})
	store.data.words["basic-01-01"] = {"seen":3,"correct":2,"wrong":1,"hinted":0,"streak":1}
	store.data.settings.battleMinutes = 20
	store.data.settings.musicVolume = .35
	store.data.army.levels["archer"] = 2
	store.data.learning["assessments"] = {}
	check(store.write_save(),"Later-identity fixture saves through unchanged native Progress")
	# Compare persisted JSON values; native read adds defaults and JSON rounds timestamps.
	var expected: Dictionary = JSON.parse_string(JSON.stringify(store.data))
	var reloaded: RefCounted = Store.new()
	reloaded.save_path = store.save_path
	reloaded.read_save()
	check(reloaded.read_error.is_empty() and JSON.parse_string(JSON.stringify(reloaded.data))==expected,"One playable stage preserves later canonical receipt, words, settings and army levels on read")
	check(reloaded.write_save(),"Retained historical identity saves again without a migration")
	var reread: RefCounted = Store.new()
	reread.save_path = store.save_path
	reread.read_save()
	check(JSON.parse_string(JSON.stringify(reread.data))==expected and reread.stage_numbers.size()==40,"Read/write/read preserves the complete private later-identity fixture")
	observations.append({"case":"one-playable-stage save identity","playable_stages":1,"historical_identities":40,"later_id":later_id,"scope":"Private synthetic later-clear receipt; no later terrain playability or natural victory claim"})

func desktop_record_event(event: Dictionary) -> void:
	if str(event.get("type","")) in ["hit","killed","recruited","placed","wave","objective_hit","finished"]:
		desktop_events.append(event.duplicate(true))

func desktop_paid_order(unit_id: String) -> bool:
	var card: Button = app.army_grid.get_node_or_null("DeployCard_"+unit_id) as Button
	if not check(card != null and not card.disabled,"Fresh native paid card is available: "+unit_id): return false
	var points: Array[Vector2] = []
	if unit_id=="spear":
		var base: Dictionary = app.game.ground_combat.select_march_base(-1)
		if not base.is_empty(): points.append(Vector2(base.position))
	else:
		for zone in app.game.zones:
			if str(zone.get("placementRole",""))!="ranged": continue
			var center: Vector2 = Vector2(zone.position)
			points.append(center)
			for fraction in [.4,.75]:
				for index in range(8):
					points.append(center+Vector2.from_angle(TAU*index/8.0)*float(zone.get("r",0))*fraction)
	var target: Vector2 = Vector2(INF,INF)
	for point in points:
		var screen: Vector2 = app.game.field_point_to_screen(point)
		if not app._deployment_surface_point(screen).is_empty() and bool(app.game.deployment_preview(unit_id,point,"").get("valid",false)):
			target = screen
			break
	if not check(target.is_finite(),"Actual authored stage offers a legal visible paid destination: "+unit_id): return false
	var cost: int = app.game.recruit_cost(unit_id)
	var gold: int = app.game.gold
	var accepted_before: int = app.game.next_recruitment_id
	await mouse(card.get_global_rect().get_center(),true)
	await motion(target)
	await mouse(target,false)
	check(app.game.next_recruitment_id==accepted_before+1,"Native drag release accepts exactly one real paid order: "+unit_id)
	check(app.game.gold<=gold-cost,"Real paid order deducts its native recruitment cost: "+unit_id)
	return app.game.next_recruitment_id==accepted_before+1

func desktop_firing_pad_route_clearance() -> void:
	var provider: Node3D = app.troops_3d.battlefield
	if not check(is_instance_valid(provider) and provider.get_script()==load("res://native/battlefield_world_adapter.gd") and app.game.ground_combat.structure_segment_clear==Callable(provider,"segment_clear"),"Firing-pad connectors use the actual mounted WorldAdapter navigation provider"): return
	var margin: float = .018
	for pad_id in ["left-shoulder-pad","right-shoulder-pad"]:
		var pad: Dictionary = {}
		for zone in app.game.zones:
			if str(zone.get("id",""))==pad_id:
				pad = zone
				break
		if not check(not pad.is_empty() and str(pad.get("placementRole",""))=="ranged","Canonical firing pad is registered in actual Game zones: "+pad_id): continue
		var center: Vector2 = Vector2(pad.position)
		var nearest: Vector2 = Vector2(INF,INF)
		var nearest_distance: float = INF
		var nearest_path_index: int = -1
		var nearest_segment_index: int = -1
		for path_index in range(app.game.paths.size()):
			var points: Array = app.game.paths[path_index].points
			for segment_index in range(points.size()-1):
				var point: Vector2 = Geometry2D.get_closest_point_to_segment(center,Vector2(points[segment_index]),Vector2(points[segment_index+1]))
				var distance: float = center.distance_to(point)
				if distance<nearest_distance:
					nearest = point
					nearest_distance = distance
					nearest_path_index = path_index
					nearest_segment_index = segment_index
		if not check(center.is_finite() and nearest.is_finite() and nearest_path_index>=0,"Firing pad has a nearest point over all actual canonical route segments: "+pad_id): continue
		var forward: bool = provider.segment_clear(center,nearest,margin)
		var reverse: bool = provider.segment_clear(nearest,center,margin)
		var center_world: Vector3 = provider.world_point(center)
		var nearest_world: Vector3 = provider.world_point(nearest)
		observations.append({"case":"actual firing-pad nearest-route connector clearance","map_id":str(app.game.config.get("id","")),"pad_id":pad_id,"provider_instance_id":provider.get_instance_id(),"provider_script":provider.get_script().resource_path,"provider_source_hash":provider.source_hash,"pad_center_normalized":[center.x,center.y],"nearest_route_point_normalized":[nearest.x,nearest.y],"pad_center_world":[center_world.x,center_world.y,center_world.z],"nearest_route_point_world":[nearest_world.x,nearest_world.y,nearest_world.z],"path_index":nearest_path_index,"path_id":str(app.game.paths[nearest_path_index].get("id","")),"segment_index":nearest_segment_index,"connector_distance_normalized":nearest_distance,"body_margin_normalized":margin,"forward_clear":forward,"reverse_clear":reverse,"scope":"Actual normal-entry mounted provider and registered Game zones/routes; nearest point searched over every canonical route segment, no constructed provider or fixture geometry"})
		check(forward,"Actual firing-pad center to nearest canonical route clears body margin .018: "+pad_id)
		check(reverse,"Actual nearest canonical route to firing-pad center clears body margin .018: "+pad_id)

func desktop_learning_bindings() -> void:
	var expected_labels: Dictionary = {"zone-09":["森","もり"],"zone-08":["山","やま"],"zone-11":["川","かわ"]}
	var approved_worlds: Dictionary = desktop_source_contract.get("learning_landmark_worlds",{})
	var approved_supports: Dictionary = desktop_source_contract.get("learning_support_worlds",{})
	var runtime_supports: Dictionary = app.game.config.get("historicalBattlefield",{}).get("learningSupportAnchors",{})
	var provider: Node3D = app.troops_3d.battlefield
	check(app.stage_learning.get("missions",[]).size()==3,"Canonical production lesson retains all three context missions")
	for mission in app.stage_learning.get("missions",[]):
		var mission_id: String = str(mission.id)
		check(runtime_supports.has(mission_id) and approved_supports.has(mission_id),"Production mission has an explicit new support anchor, not center fallback: "+mission_id)
		if runtime_supports.has(mission_id) and approved_supports.has(mission_id):
			var anchor: Dictionary = runtime_supports[mission_id]
			var approved: Dictionary = approved_supports[mission_id]
			check(provider.world_point(Vector2(float(anchor.x),float(anchor.y))).distance_to(Vector3(float(approved.x),float(approved.y),float(approved.z)))<.001,"Production support anchor matches approved new world point: "+mission_id)
		for target in mission.get("targets",[]):
			var id: String = str(target.id)
			if not check(expected_labels.has(id) and approved_worlds.has(id) and target.get("position") is Dictionary,"Production mission target has approved new terrain coordinates: "+id): continue
			check(str(target.label.jp)==str(expected_labels[id][0]) and str(target.label.reading)==str(expected_labels[id][1]),"Production target preserves canonical Japanese and reading: "+id)
			var point: Vector2 = Vector2(float(target.position.x),float(target.position.y))
			var world: Vector3 = provider.world_point(point)
			var approved: Dictionary = approved_worlds[id]
			check(world.distance_to(Vector3(float(approved.x),float(approved.y),float(approved.z)))<.001,"Production target resolves the actual approved new landmark surface: "+id)
			var screen: Vector2 = app.game.field_point_to_screen(point)
			check(app.game.screen_to_field_point(screen).distance_to(point)<.002,"Actual camera picking roundtrip agrees with landmark world position: "+id)
			observations.append({"case":"production learning landmark binding","mission_id":mission_id,"target_id":id,"world":str(world),"screen":str(screen),"answer_id":str(mission.answerId),"scope":"Runtime production mission and approved new authored coordinates; no old QA floor anchors used"})

func desktop_mission_ui_fixture() -> void:
	# Exercise each real bound production mission through Main's existing UI.
	# This is a controlled VALID intermission after the natural-contact receipt.
	# Only phase flags change; no clock, HP, actor or natural wave arrival is injected.
	if app.game.finished or app.game.battle_closed:
		blockers.append("Native mission UI/support fixture unavailable because observed battle already ended")
		return
	var original_phase: Dictionary = {"between_waves":app.game.between_waves,"paused":app.game.paused,"processing":app.game.is_processing()}
	var observed_elapsed: float = app.game.elapsed
	app.game.set_process(false)
	for mission in app.stage_learning.get("missions",[]):
		# Mirror the existing intermission invariant before native Main presentation.
		app.game.between_waves = true
		app.game.paused = false
		app._on_state(app.game.snapshot())
		var task: Dictionary = app.lesson_session._mission_task(mission,int(mission.wave))
		if not check(not task.is_empty(),"Unmodified production mission builds its real native task: "+str(mission.id)): continue
		app.lesson_session.pending = task.duplicate(true)
		app.quiz_task = task.duplicate(true)
		app.quiz_hinted = false
		app.quiz_resolved = false
		app._show_quiz()
		await create_timer(.85).timeout
		check(app.learning_field.target_buttons.size()==3,"Actual Main context presentation creates all three production target controls")
		if str(mission.id)==str(app.stage_learning.missions[0].id):
			await desktop_pending_context_navigation_fixture()
		await desktop_context_resize_evidence(mission,"choice")
		var target_button: Button = app.learning_field.get_node_or_null("LearningTarget_"+str(task.answerId)) as Button
		await desktop_click(target_button,"Actual authored context answer callback")
		check(app.quiz_resolved and app.quiz_outcome_correct,"Native internal task grading accepts its unchanged authored target")
		var claim: Dictionary = app.game.battle_support.claims.get(str(task.id),{})
		var anchor: Dictionary = app.game.config.get("historicalBattlefield",{}).get("learningSupportAnchors",{}).get(str(mission.id),{})
		var requested: Dictionary = claim.get("requestedAnchor",{})
		if check(bool(claim.get("ok",false)) and anchor.has("x") and anchor.has("y") and requested.has("x") and requested.has("y"),"Actual native support claim and production mission both retain an explicit anchor"):
			var requested_point: Vector2 = Vector2(float(requested.x),float(requested.y))
			check(requested_point.distance_to(Vector2(float(anchor.x),float(anchor.y)))<.000001,"Actual requested support anchor matches its explicit production anchor within float32 precision")
			var approved: Dictionary = desktop_source_contract.get("learning_support_worlds",{}).get(str(mission.id),{})
			if check(approved.has("x") and approved.has("y") and approved.has("z"),"Independent source contract retains this mission's approved support world point"):
				check(app.troops_3d.battlefield.world_point(requested_point).distance_to(Vector3(float(approved.x),float(approved.y),float(approved.z)))<.001,"Actual claimed support resolves the independently approved new world anchor")
		var path_index: int = int(claim.get("pathIndex",-1))
		if check(path_index>=0 and path_index<app.game.paths.size(),"Native support claim selects a real configured route"):
			var base: Dictionary = app.game.ground_combat.select_march_base(path_index)
			var matching_job: bool = false
			for job in app.game.battle_support.jobs:
				if str(job.receipt.get("attemptId",""))==str(task.id):
					matching_job = true
					check(not base.is_empty() and Vector2(job.origin).distance_to(Vector2(base.get("position",Vector2(INF,INF))))<.001,"Actual queued support origin is the native safe base of the selected route")
					observations.append({"case":"actual production mission support","mission_id":str(mission.id),"task_id":str(task.id),"claim":claim.duplicate(true),"selected_path":path_index,"base":base.duplicate(true),"job_origin":str(job.origin),"scope":"Real answer callback and native queued reward/path/base; controlled mission issuance, no natural waves3/6 or full support completion claim"})
			check(matching_job,"Actual support claim retains a matching queued native job")
		await desktop_context_resize_evidence(mission,"resolved")
		await desktop_click(app.learning_field.continue_button,"Actual production mission returns to battle")
		await create_timer(.6).timeout
		check(not app.context_task_active,"Actual native return removes context UI and restores battle input")
		check(not app.troops_3d.external_viewport_consumer,"Actual return clears the external learning viewport consumer")
	check(app.game.elapsed==observed_elapsed,"Controlled intermission UI fixture never advances or assigns the observed combat clock")
	app.game.between_waves = bool(original_phase.between_waves)
	app.game.paused = bool(original_phase.paused)
	app._on_state(app.game.snapshot())
	app.game.set_process(bool(original_phase.processing))
	check(bool(app.state.get("betweenWaves",false))==app.game.between_waves and bool(app.state.get("paused",false))==app.game.paused,"Controlled fixture restores consistent Game/Main phase state")
	observations.append({"case":"production mission UI fixture scope","original_phase":original_phase,"observed_elapsed":observed_elapsed,"scope":"Controlled valid betweenWaves phase, Game processing suspended/restored, all three production tasks through native UI/support callbacks. Existing native return may begin the next wave; no natural arrival/completion or unchanged full-battle state claim. No clock/HP/actor rewriting; separate from earlier bounded natural contact."})

func desktop_pending_context_navigation_fixture() -> void:
	# Existing navigation callbacks are invoked as a separate lifecycle fixture.
	# Returning uses actual visible Home/Catalog controls; no task is reissued.
	var retained_task: Dictionary = app.quiz_task.duplicate(true)
	var retained_pending: Dictionary = app.lesson_session.pending.duplicate(true)
	var retained_progress: Dictionary = app.progress.data.duplicate(true)
	for destination in ["home","catalog"]:
		if destination=="home": app._show_home()
		else: app._show_catalog()
		await settle()
		check(app.front_end.visible and app.context_task_active and not app.troops_3d.external_viewport_consumer,"Pending context navigation disables the external world consumer: "+destination)
		for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
			await desktop_resize(dimensions)
			app._on_state(app.game.snapshot())
			await settle()
			check(not app.troops_3d.external_viewport_consumer,"Navigation resize/state callback cannot rearm the hidden learning world consumer: "+destination+" / "+str(dimensions))
		check(app.quiz_task==retained_task and app.lesson_session.pending==retained_pending and app.progress.data==retained_progress,"Pending context navigation preserves the task, pending lesson and account: "+destination)
		var return_button: Button
		if destination=="home": return_button = app.front_end.get_node_or_null("HomeResume") as Button
		else: return_button = desktop_button(app.front_end,"전장 복귀")
		if not await desktop_click(return_button,"Actual pending-context navigation return: "+destination): return
		await create_timer(.85).timeout
		check(not app.front_end.visible and app.context_task_active and app.troops_3d.external_viewport_consumer,"Actual navigation return restores the pending learning world consumer: "+destination)
		check(app.learning_transition.accepts_answers() and app.learning_field.interaction_enabled,"Actual navigation return restores answer input for the retained pending context task: "+destination)
		check(app.quiz_task==retained_task and app.lesson_session.pending==retained_pending and app.progress.data==retained_progress,"Actual return retains the same pending task and account without issuance: "+destination)
	observations.append({"case":"pending context navigation lifecycle fixture","task_id":str(retained_task.get("id","")),"scope":"Controlled valid betweenWaves timing only. Existing Main Home/Catalog callbacks, actual visible return controls, real resize/state callbacks; task/account retention and consumer lifecycle only, no hidden live pose or natural wave claim"})

func desktop_context_resize_evidence(mission: Dictionary, phase: String) -> void:
	# Include both resize directions for choice and resolved presentation.
	var resize_index: int = 0
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1280,800)]:
		resize_index += 1
		root.size = dimensions
		root.content_scale_size = dimensions
		app._layout()
		check(not app.troops_3d.is_visible_in_tree() and app.troops_3d.viewport.render_target_update_mode==SubViewport.UPDATE_ONCE,"Actual hidden learning viewport requests one native resize draw: "+phase)
		await settle()
		await RenderingServer.frame_post_draw
		await settle(1)
		var field: Variant = app.learning_field
		var viewport: SubViewport = app.troops_3d.viewport
		check(app.troops_3d.external_viewport_consumer and field.world_projection.is_valid(),"Actual learning view retains its live world consumer/projector: "+phase)
		check(viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Actual hidden learning resize draw returns ONCE to DISABLED: "+phase)
		check(field.stage_texture==viewport.get_texture() and field.world_texture==viewport.get_texture(),"Actual learning background uses the native Troops viewport texture: "+phase)
		var pixels: Image = viewport.get_texture().get_image()
		var pixel_ready: bool = check(pixels!=null and not pixels.is_empty(),"Actual resized learning world has GPU pixels: "+phase)
		if pixel_ready:
			check(pixels.get_size()==viewport.size,"Actual world texture pixel dimensions follow the resized viewport: "+phase)
			var reference: Color = pixels.get_pixel(0,0)
			var varied: bool = false
			for y in range(1,9):
				for x in range(1,9):
					var pixel: Color = pixels.get_pixel(int(x*(pixels.get_width()-1)/9.0),int(y*(pixels.get_height()-1)/9.0))
					if Vector3(pixel.r-reference.r,pixel.g-reference.g,pixel.b-reference.b).length()>.01: varied = true
			check(varied,"Actual learning viewport contains varied rendered pixels, not a blank resize frame: "+phase)
		if check(app.troops_3d.field_size.x>0 and app.troops_3d.field_size.y>0,"Actual camera projection has a nonzero field size"):
			check(field.target_anchors.size()==mission.targets.size(),"Actual learning anchor count matches production targets")
			check(field.target_buttons.size()==mission.targets.size(),"Actual learning image controls match production targets")
			for index in range(mini(mini(field.target_anchors.size(),mission.targets.size()),field.target_buttons.size())):
				var target: Dictionary = mission.targets[index]
				var point: Vector2 = Vector2(float(target.position.x),float(target.position.y))
				var projected: Vector2 = app.troops_3d.model_to_field_point(point)/app.troops_3d.field_size
				check(projected.is_finite() and field.target_anchors[index].distance_to(projected)<.001,"Actual context anchor agrees with independent native camera projection: "+str(target.id)+" / "+phase)
				var picture: TextureRect = field.target_buttons[index].get_node_or_null("DestinationImage") as TextureRect
				if not check(picture!=null and picture.texture is AtlasTexture,"Actual target image keeps its native world AtlasTexture: "+str(target.id)): continue
				var crop: AtlasTexture = picture.texture
				var source_size: Vector2 = viewport.get_texture().get_size()
				var display: Dictionary = desktop_source_contract.get("learning_display_crops",{}).get(str(target.id),{})
				var focus_value: Variant = display.get("displayFocusWorld",[])
				var scale_value: Variant = display.get("displayCropSizeNormalized",[])
				if not check(focus_value is Array and focus_value.size()==3 and scale_value is Array and scale_value.size()==2 and field.world_focus_projection.is_valid(),"Independent display crop contract and actual world focus projector exist: "+str(target.id)): continue
				var focus: Vector3 = Vector3(float(focus_value[0]),float(focus_value[1]),float(focus_value[2]))
				var crop_scale: Vector2 = Vector2(float(scale_value[0]),float(scale_value[1]))
				if not check(focus.is_finite() and crop_scale.is_finite() and crop_scale.x>0 and crop_scale.y>0 and crop_scale.x<=1 and crop_scale.y<=1,"Approved display focus and crop dimensions are valid: "+str(target.id)): continue
				var cue: Dictionary = app.current_map.get("visualComposition",{}).get("contextAnchors",{}).get(str(target.id),{})
				check(cue.get("displayFocusWorld",[])==focus_value and cue.get("displayCropSizeNormalized",[])==scale_value,"Actual authored display cue matches the independent approved contract: "+str(target.id))
				var focus_projected: Vector2 = app.troops_3d.project_world_to_field(focus)/app.troops_3d.field_size
				if not check(focus_projected.is_finite(),"Actual camera projects the independently approved display focus: "+str(target.id)): continue
				var crop_size: Vector2 = source_size*crop_scale
				var raw_anchor: Vector2 = Vector2(1.0-focus_projected.x,focus_projected.y) if field.presentation_mirrored else focus_projected
				var center: Vector2 = raw_anchor*source_size
				var expected_position: Vector2 = Vector2(clampf(center.x-crop_size.x*.5,0,source_size.x-crop_size.x),clampf(center.y-crop_size.y*.5,0,source_size.y-crop_size.y))
				check(crop.atlas==viewport.get_texture() and crop.region.position.distance_to(expected_position)<.01 and crop.region.size.distance_to(crop_size)<.01,"Actual resized target crop agrees with native camera/texture dimensions: "+str(target.id)+" / "+phase)
				var crop_pixels: Image = crop.get_image()
				if check(crop_pixels!=null and not crop_pixels.is_empty(),"Actual native destination AtlasTexture provides GPU crop pixels: "+str(target.id)+" / "+phase):
					check(Vector2(crop_pixels.get_size()).distance_to(crop.region.size)<2,"Actual destination pixels match the resized AtlasTexture region dimensions")
					if pixel_ready:
						var sample: Vector2i = crop_pixels.get_size()/2
						var source_sample: Vector2i = Vector2i(crop.region.position)+sample
						if check(Rect2i(Vector2i.ZERO,pixels.get_size()).has_point(source_sample),"Destination crop sample lies inside its actual source viewport"):
							check(crop_pixels.get_pixelv(sample).is_equal_approx(pixels.get_pixelv(source_sample)),"Actual destination crop pixels agree with the native viewport source")
					var crop_path: String = "user://common-first-desktop-destination-%s-%s-%s-resize%d-%dx%d.png" % [str(mission.id),str(target.id),phase,resize_index,dimensions.x,dimensions.y]
					if check(crop_pixels.save_png(crop_path)==OK,"Actual native destination crop PNG saves"):
						captures.append({"label":"native destination GPU crop","path":ProjectSettings.globalize_path(crop_path),"kind":"actual-atlas-gpu-pixels","mission_id":str(mission.id),"target_id":str(target.id),"phase":phase,"resolution":str(dimensions),"size":[crop_pixels.get_width(),crop_pixels.get_height()],"display_flip_h":picture.flip_h,"scope":"Raw native AtlasTexture image; actual displayed orientation and UI visibility are verified separately in the matching full context capture"})
				observations.append({"case":"actual context resize","mission_id":str(mission.id),"target_id":str(target.id),"phase":phase,"resolution":str(dimensions),"projected":str(projected),"actual_anchor":str(field.target_anchors[index]),"display_focus_world":str(focus),"display_focus_projected":str(focus_projected),"approved_crop_scale":str(crop_scale),"atlas_region":str(crop.region),"viewport_size":str(viewport.size),"gpu_pixels_available":pixel_ready,"scope":"Ground target/support unchanged; independent presentation-only world focus projected by actual camera for native Atlas crop. Pixel captures still require feature/readability review."})
		inspect_visible_furigana("desktop actual context "+str(mission.id)+" / "+phase+" / "+str(dimensions))
		await desktop_capture_context("desktop-context-%s-%s-resize%d-%dx%d" % [str(mission.id),phase,resize_index,dimensions.x,dimensions.y])

func desktop_wait_contact() -> void:
	var started: int = Time.get_ticks_usec()
	var hit: Dictionary = {}
	var first_enemy: Dictionary = {}
	while Time.get_ticks_usec()-started<90000000 and not app.game.finished:
		if first_enemy.is_empty() and not app.game.enemies.is_empty():
			first_enemy = app.game.enemies[0].duplicate(true)
			check(int(app.game.wave)==1 and is_equal_approx(float(first_enemy.get("maxHp",0)),39.9),"Actual canonical first-wave enemy retains maxHP39.9")
		for event in desktop_events:
			if str(event.get("type",""))=="hit" and str(event.get("side",""))=="friendly" and str(event.get("unitType","")) in ["archer","spear"] and float(event.get("damage",0))>0 and float(event.get("hpBefore",0))>float(event.get("hpAfter",0)):
				hit = event
				break
		if not hit.is_empty(): break
		# Follow the existing native skip/continue UI if learning pauses the clock.
		# This observation run never rewrites task IDs, answers or Game.elapsed.
		if app.learning_field.choosing and app.learning_field.continue_button.is_visible_in_tree() and not app.learning_field.continue_button.disabled:
			await desktop_click(app.learning_field.continue_button,"Natural learning skip/continue")
		elif app.modal_context=="quiz" and app.quiz_continue_button != null and app.quiz_continue_button.is_visible_in_tree() and not app.quiz_continue_button.disabled:
			await desktop_click(app.quiz_continue_button,"Natural question skip/continue")
		await process_frame
	if hit.is_empty(): blockers.append("No actual paid starter HP-decreasing contact observed in bounded90s natural clock; no simulated contact substitutes for it")
	var produced: Dictionary = {"archer":0,"spear":0}
	for event in desktop_events:
		if str(event.get("type","")) in ["recruited","placed"] and produced.has(str(event.get("unitType",""))) and int(event.get("cost",0))>0:
			produced[str(event.unitType)] += int(event.get("quantity",0))
	check(int(produced.archer)==2 and int(produced.spear)==2,"Native production records two paid starter archers and two paid starter spears")
	observations.append({"case":"bounded natural paid contact","wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"combat_elapsed":app.game.elapsed,"hit":hit,"first_enemy":first_enemy,"paid_produced":produced,"events":desktop_events.duplicate(true),"scope":"Native process clock and paid UI orders; no advance_simulation/time_scale/clock/HP injection, no ten-minute victory claim"})

func desktop_capture_context(label_value: String) -> void:
	if not capture_requested: return
	await RenderingServer.frame_post_draw
	desktop_popup_readback(label_value)
	var pixels: Image = root.get_texture().get_image()
	if not check(pixels!=null and not pixels.is_empty(),"Actual context GPU pixels available: "+label_value): return
	var path: String = "user://common-first-"+label_value+".png"
	if check(pixels.save_png(path)==OK,"Actual context screenshot saved: "+label_value):
		captures.append({"label":label_value,"path":ProjectSettings.globalize_path(path),"size":[pixels.get_width(),pixels.get_height()]})

func desktop_popup_readback(label_value: String) -> void:
	# Native embedded tooltip Windows can be outside Main's ordinary app tree.
	# Observe internal children without changing hover, popup visibility or UI.
	var pending: Array[Node] = [root]
	var windows: Array = []
	var popup_controls: Array = []
	var root_strips: Array = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children(true): pending.append(child)
		if node is Window and node!=root and node.visible:
			windows.append({"path":str(node.get_path()),"class":node.get_class(),"position":str(node.position),"size":str(node.size),"embedded":node.is_embedded()})
		if not node is Control or not node.is_visible_in_tree(): continue
		var window: Window = node.get_window()
		if window==root and (node is Panel or node is PanelContainer or node is ProgressBar):
			var bounds: Rect2 = node.get_global_rect()
			if bounds.size.y>0 and bounds.size.x>300 and bounds.size.x/bounds.size.y>5 and visible_alpha(node)>.05:
				root_strips.append({"path":str(node.get_path()),"class":node.get_class(),"bounds_in_root":str(bounds),"clip_in_root":str(visible_clip(node))})
		if window==root and str(node.name) not in ["AnnotatedTooltip","TooltipRuby"]: continue
		if not window.visible: continue
		var entry: Dictionary = {"path":str(node.get_path()),"class":node.get_class(),"window_path":str(window.get_path()),"bounds_in_window":str(node.get_global_rect()),"clip_in_window":str(visible_clip(node)),"alpha":visible_alpha(node),"tooltip_text":node.tooltip_text}
		if node is Label or node is Button: entry["text"] = str(node.text)
		if node.has_method("get_text_layout"):
			var word: Variant = node.get("word")
			if word is Dictionary: entry["ruby_text"] = str(word.get("jp",""))
		if window!=root and window.is_embedded():
			entry["bounds_in_root"] = str(Rect2(node.get_global_rect().position+Vector2(window.position),node.get_global_rect().size))
		popup_controls.append(entry)
	var hovered: Control = root.gui_get_hovered_control()
	var hover_owner: Dictionary = {}
	if is_instance_valid(hovered):
		hover_owner = {"path":str(hovered.get_path()),"class":hovered.get_class(),"tooltip_text":hovered.tooltip_text,"bounds":str(hovered.get_global_rect()),"window_path":str(hovered.get_window().get_path())}
	observations.append({"case":"actual native popup capture readback","capture":label_value,"visible_windows":windows,"popup_controls":popup_controls,"wide_root_panels":root_strips,"actual_hover_owner":hover_owner,"scope":"Actual internal root descendants and hovered control at the exact PNG frame_post_draw; read-only, no tooltip construction/hiding or hover movement. Empty arrays mean no popup was observed at this capture, not a proof for prior R4."})

func desktop_floor_readback(dimensions: Vector2i) -> void:
	var provider: Variant = app.troops_3d.battlefield
	var material: ShaderMaterial = provider.ground.material_override as ShaderMaterial
	var details: Dictionary = {"case":"actual normal floor/cue readback","resolution":str(dimensions),"sun_energy":app.troops_3d.sun.light_energy,"fill_energy":app.troops_3d.fill.light_energy,"ambient_energy":app.troops_3d.environment.ambient_light_energy}
	if check(material!=null,"Actual normal authored floor uses the shared remaster shader"):
		check(material==provider.get("_material"),"Actual drawn floor and stored provider material remain identical after resize")
		check(int(material.get_shader_parameter("retreat_count"))==10 and bool(material.get_shader_parameter("has_rear_gate")),"Actual drawn shader retains complete retreat trail and rear opening after resize")
		for uniform in ["retreat_count","has_rear_gate","approach_base_color","retreat_base_color"]:
			details[uniform] = str(material.get_shader_parameter(uniform))
	if check(is_instance_valid(app.remaster_visuals),"Actual normal Main mounts its authored direction scenery"):
		var labels: Array = []
		var field: Rect2 = app.field_clip.get_global_rect()
		var transform: Transform2D = app.troops_3d.get_global_transform_with_canvas()
		var camera: Camera3D = app.troops_3d.camera
		var cues: Array = app.remaster_visuals.diagnostics().get("directionCues",[])
		check(cues.size()==2,"Actual scenery contains approach and retreat direction cues")
		for cue in cues:
			var p: Array = cue.labelWorldPosition
			var anchor: Vector3 = Vector3(float(p[0]),float(p[1]),float(p[2]))
			var font: Font = app.remaster_visuals.get_node("ApproachDirectionLabel" if str(cue.role)=="approach" else "WithdrawalDirectionLabel").font
			# Full font extents on both sides deliberately overbound the billboard.
			# Original captures still decide raster readability and scenery visibility.
			var width: float = (font.get_string_size(str(cue.label),HORIZONTAL_ALIGNMENT_LEFT,-1,int(cue.labelFontSize)).x+8)*float(cue.labelPixelSize)
			var height: float = (font.get_height(int(cue.labelFontSize))+8)*float(cue.labelPixelSize)
			var bounds: Rect2 = Rect2(transform*app.troops_3d.project_world_to_field(anchor),Vector2.ZERO)
			for x in [-1.0,1.0]:
				for y in [-1.0,1.0]:
					bounds = bounds.expand(transform*app.troops_3d.project_world_to_field(anchor+camera.global_transform.basis.x*width*x+camera.global_transform.basis.y*height*y))
			var covered: bool = app.army_panel.is_visible_in_tree() and app.army_panel.get_global_rect().intersects(bounds)
			check(field.encloses(bounds) and not covered,"Conservative actual direction label bounds remain inside the field and clear of the inspector: "+str(cue.role))
			labels.append({"role":str(cue.role),"world_anchor":str(anchor),"conservative_font_bounds":str(bounds),"covered_by_inspector":covered})
		details["direction_labels"] = labels
	details["scope"] = "Actual shader/lighting/cue projection after resize. Conservative font bounds only; original native battle captures require visual review of direction labels, retreat trail and rear opening. No new movement or evacuation rule."
	observations.append(details)

func desktop_result_retry_fixture() -> void:
	# The result renderer/save guards are deliberately a separate synthetic fixture.
	# Close the observed battle normally before injecting a result callback.
	app.game.close_battle()
	check(app._next_registered_stage().is_empty(),"Actual single-stage navigation helper returns no absent next stage")
	for won in [false,true]:
		app.battle_finished = false
		app._on_battle_finished({"victory":won,"qaSyntheticResult":true})
		await settle()
		if not check(app.modal_context=="result" and app.modal != null,"Single-stage result callback renders without absent-next-stage indexing"): return
		for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
			await desktop_resize(dimensions)
			inspect_visible_furigana("desktop synthetic result "+str(won)+" / "+str(dimensions))
			await capture("desktop-result-fixture-%s-%dx%d" % [str(won),dimensions.x,dimensions.y])
		var saved: Dictionary = app.progress.data.duplicate(true)
		app._on_battle_finished({"victory":won,"qaSyntheticResult":true})
		check(app.progress.data==saved,"Duplicate result callback cannot duplicate private campaign rewards or records")
		for node in app.modal.find_children("*","Button",true,false):
			# The existing unlock exam is a learning action, not missing terrain navigation.
			if str(node.name)=="ResultUnlockExam": continue
			if str(node.text) in ["다음 지도  ›","다음 원정  ›"]:
				check(node.disabled,"Unavailable next-stage action is disabled in a one-stage catalog")
		var retry: Button = desktop_button(app.modal,"같은 지도 다시 출진")
		if not await desktop_click(retry,"Actual result retry callback",app.modal_scroll): return
		check(app.modal_context=="briefing" and str(app.current_map.id)=="basic-forest" and not app.isolated_candidate,"Retry returns through canonical normal stage selection and briefing")
		check(app.game.units.is_empty() and app.game.recruitment_queue.is_empty() and app.troops_3d.actors.is_empty(),"Retry removes previous actors and orders")
		check(app.game.gold==280 and int(app.game.snapshot().get("maxHp",0))==26,"Retry restores original canonical gold280 and objectiveHP26")
	observations.append({"case":"synthetic normal result/retry guards","scope":"Private defeat/victory callback fixtures and duplicate-save guard only; synthetic saved wins are not natural battle completion evidence"})

func desktop_abort_entry() -> void:
	# An invalid real UI entry must leave a failure receipt, not cascade into runtime errors.
	observations.append({"case":"actual entry abort UI state","state":desktop_frontend_state()})
	await capture("desktop-entry-abort")
	app.game.close_battle()
	app._stop_narration()
	app.battle_audio.shutdown()
	app.queue_free()
	await settle()
	var after: Dictionary = desktop_hashes()
	var report: Dictionary = {"status":"FAIL","checks":checks,"failures":failures,"blockers":blockers,"sourceHashes":initial_hashes,"source_hashes_after":after,"sourceFreezeUnchanged":after==initial_hashes,"captures":captures,"observations":observations,"gpu_slot":gpu_slot,"scope":"Stopped at invalid actual UI entry/order before dependent checks; no natural contact or complete desktop acceptance"}
	var output: FileAccess = FileAccess.open("user://qa-common-first-desktop.json",FileAccess.WRITE)
	if output!=null:
		output.store_string(JSON.stringify(report,"  "))
		output.close()
	audit_journal({"kind":"desktop_entry_abort","status":"FAIL","source_hashes_after":after,"final_report":ProjectSettings.globalize_path("user://qa-common-first-desktop.json")})
	quit(1)

func run_desktop_first_stage() -> void:
	if not guarded_profile() or not check(furigana_requested and not hover_focus and fixture_path.is_empty(),"Desktop branch uses actual maps and furigana audit, never the candidate fixture"):
		quit(2)
		return
	audit_started_usec = Time.get_ticks_usec()
	initial_hashes = desktop_hashes()
	if not check(desktop_source_path.begins_with("res://tests/profiles/qa-common-first-") and FileAccess.file_exists(desktop_source_path),"Desktop branch requires a current HQ frozen source manifest inside isolated QA profiles"):
		quit(2)
		return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(desktop_source_path))
	if not check(expected is Dictionary and expected.get("source_hashes_before") is Dictionary,"Frozen source manifest provides the approved current input hashes"):
		quit(2)
		return
	desktop_source_contract = expected.get("desktop_contract",{}).duplicate(true)
	check(desktop_source_contract.get("learning_landmark_worlds",{}).size()==3 and desktop_source_contract.get("learning_support_worlds",{}).size()==3,"Source READY contract supplies independently approved new landmark and support world points")
	check(desktop_source_contract.get("learning_display_crops",{}).size()==3,"Source READY contract supplies all three independently approved display focuses and crop sizes")
	for path in initial_hashes:
		check(expected.source_hashes_before.get(path)==initial_hashes[path],"Approved desktop source hash matches before initialization: "+path)
	if not failures.is_empty():
		quit(1)
		return
	audit_journal({"kind":"desktop_start","source_hashes_before":initial_hashes,"source_manifest":desktop_source_path,"source_manifest_sha256":FileAccess.get_sha256(desktop_source_path),"desktop_contract":desktop_source_contract,"scope":"Actual maps normal entry; incomplete until final receipt and source/teardown checks"})
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	if not check(catalog is Array and catalog.size()==1 and str(catalog[0].id)=="basic-forest" and int(catalog[0].stageNumber)==1,"Actual playable catalog contains exactly canonical first stage"):
		quit(2)
		return
	await desktop_save_identity_regression()
	var store: RefCounted = Store.new()
	store.save_path = "user://desktop-first-stage.json"
	store.read_save()
	store.data.settings.voice = false
	store.data.settings.music = false
	store.data.settings.effects = false
	app = load("res://native/main.tscn").instantiate()
	app.progress = store
	root.add_child(app)
	await settle()
	app.game.game_event.connect(desktop_record_event)
	check(app.maps.size()==1 and not app.isolated_candidate and store.data.maps.is_empty(),"Actual Main loads its one-stage catalog with a fresh independent account")
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
		await desktop_resize(dimensions)
		inspect_visible_furigana("desktop actual Home / "+str(dimensions),app.front_end)
		await capture("desktop-home-%dx%d" % [dimensions.x,dimensions.y])
	if not await desktop_click(app.front_end.get_node_or_null("HomeSortie") as Button,"Actual Home sortie"):
		await desktop_abort_entry()
		return
	if not await desktop_wait_catalog_entry():
		await desktop_abort_entry()
		return
	if not await desktop_click(app.front_end.find_child("Stage_basic-forest",true,false) as Button,"Actual canonical stage selection"):
		await desktop_abort_entry()
		return
	inspect_visible_furigana("desktop actual stage catalog",app.front_end)
	if not await desktop_click(app.front_end.get_node_or_null("CatalogSortie") as Button,"Actual catalog sortie"):
		await desktop_abort_entry()
		return
	if not check(app.modal_context=="briefing" and str(app.current_map.get("id",""))=="basic-forest" and str(app.game.config.get("id",""))=="basic-forest","Actual UI entry binds canonical Main/Game/story/lesson"):
		await desktop_abort_entry()
		return
	check(str(app.current_lesson.get("id",""))=="basic-01" and str(app.current_story.get("stageId",""))=="basic-forest","Canonical entry uses the original first lesson and historical story")
	check(is_equal_approx(app.game.FIRST_STAGE_ENEMY_HP_FACTOR,.95),"Original canonical enemyHP factor remains .95")
	check(is_equal_approx(float(app.troops_3d.visual_profiles["basic-forest"].perspective.farScale),.88),"Actual Troops uses canonical far perspective scale .88")
	check(is_equal_approx(float(app.troops_3d.visual_profiles["basic-forest"].perspective.nearScale),1.10) and is_equal_approx(app.troops_3d.actor_base_scale(),.70),"Canonical body scale retains base .70 and position-dependent far .88 / near1.10")
	var archer_bonus: float = 1.0
	for bonus in app.game.config.get("trait",{}).get("unitBonuses",[]):
		if str(bonus.get("type","all")) in ["archer","all"]: archer_bonus *= float(bonus.get("damageFactor",1.0))
	check(is_equal_approx(archer_bonus,1.1),"Original canonical archer trait damage factor remains1.1; this is not an actor scale")
	check(app.game.gold==280 and int(app.game.snapshot().get("maxHp",0))==26,"Canonical initial gold280 and objectiveHP26 remain unchanged")
	observations.append({"case":"canonical runtime constants","archer_stats":store.army_stats("archer"),"archer_trait_damage_factor":archer_bonus,"actor_base_scale":app.troops_3d.actor_base_scale(),"scope":"Archer1.1 is native trait damage multiplier; body scale is the unchanged position-dependent canonical visual profile"})
	for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
		await desktop_resize(dimensions)
		desktop_learning_bindings()
		inspect_visible_furigana("desktop actual briefing / "+str(dimensions))
		if app.modal_scroll != null: app.modal_scroll.scroll_vertical = int(app.modal_scroll.get_v_scroll_bar().max_value)
		await settle()
		inspect_visible_furigana("desktop actual briefing scrolled / "+str(dimensions))
	if not await desktop_click(desktop_button(app.modal_footer,"출진"),"Actual briefing starts native battle"):
		await desktop_abort_entry()
		return
	if not check(app.battle_started and app.game.running and app.game.is_processing(),"Normal UI starts the actual natural Game process"):
		await desktop_abort_entry()
		return
	desktop_firing_pad_route_clearance()
	for unit_id in ["archer","spear","archer","spear"]:
		if not await desktop_paid_order(unit_id):
			await desktop_abort_entry()
			return
	await desktop_wait_contact()
	if not app.game.finished and app.modal == null:
		await desktop_click(app.pause_button,"Actual pause for equivalent two-resolution native captures")
		var clock: float = app.game.elapsed
		for dimensions in [Vector2i(1280,800),Vector2i(1440,900)]:
			await desktop_resize(dimensions)
			desktop_floor_readback(dimensions)
			inspect_visible_furigana("desktop actual paid battle / "+str(dimensions))
			await capture("desktop-native-battle-%dx%d" % [dimensions.x,dimensions.y])
		check(app.game.elapsed==clock,"Equivalent native captures use the actual paused state without moving the combat clock")
		await desktop_click(app.pause_button,"Actual resume after native captures")
	else:
		blockers.append("Actual unoccluded native battle captures were unavailable after contact; no constructed state substitutes")
	await desktop_mission_ui_fixture()
	await desktop_result_retry_fixture()
	check(store.write_save(),"Normal-entry private account writes through native Progress")
	var reloaded: RefCounted = Store.new()
	reloaded.save_path = store.save_path
	reloaded.read_save()
	var expected_saved: Dictionary = JSON.parse_string(JSON.stringify(store.data))
	# Native read supplies this empty default; retain every observed learning record.
	if not expected_saved.learning.has("assessments"): expected_saved.learning["assessments"] = {}
	check(JSON.parse_string(JSON.stringify(reloaded.data))==expected_saved and reloaded.read_error.is_empty(),"Normal-entry private save reload preserves observed native account transitions")
	app._stop_narration()
	app.player.stop()
	app.player.stream = null
	app.battle_audio.shutdown()
	app.game.close_battle()
	app.queue_free()
	await settle()
	var after: Dictionary = desktop_hashes()
	check(after==initial_hashes,"Actual desktop branch source/art/launcher/map inputs remain frozen")
	var status: String = "FAIL" if not failures.is_empty() else ("BLOCKED" if not blockers.is_empty() else "PASS")
	var report: Dictionary = {"status":status,"checks":checks,"failures":failures,"blockers":blockers,"desktop_first_stage":true,"sourceHashes":initial_hashes,"source_hashes_after":after,"sourceFreezeUnchanged":after==initial_hashes,"captures":captures,"observations":observations,"furigana_surfaces":furigana_surfaces,"furigana_geometry":furigana_geometry,"gpu_slot":gpu_slot,"display_driver":DisplayServer.get_name(),"scope":"Actual desktop Main/maps/UI code path in a disposable account. Bounded natural paid contact is separate from synthetic result/retry/save fixtures. No natural ten-minute victory, all40, G1 or real-player save mutation claim."}
	var output: FileAccess = FileAccess.open("user://qa-common-first-desktop.json",FileAccess.WRITE)
	if output == null:
		quit(2)
		return
	output.store_string(JSON.stringify(report,"  "))
	output.close()
	audit_journal({"kind":"desktop_complete","status":status,"sourceFreezeUnchanged":after==initial_hashes,"source_hashes_after":after,"final_report":ProjectSettings.globalize_path("user://qa-common-first-desktop.json")})
	print("DESKTOP_FIRST_STAGE ",status," ",checks," checks / ",failures.size()," failures")
	quit(1 if status=="FAIL" else (2 if status=="BLOCKED" else 0))
