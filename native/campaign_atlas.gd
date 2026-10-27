extends Control
## Original paper atlas drawn from public-domain physical coastline coordinates.
signal stage_requested(stage_id: String)
signal assessment_requested(stage_id: String)
signal selection_changed(stage_id: String)
signal home_requested
signal catalog_requested
signal resume_requested

const RubyText = preload("res://native/ruby_label.gd")
const RubyReadings = preload("res://native/ruby_readings.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const GameFonts = preload("res://native/game_fonts.gd")
const COASTLINE_PATH: String = "res://assets/atlas/japan-coastline.json"
const JAPAN: Vector4 = Vector4(121,149,24,46)
const CAMPAIGN: Vector4 = Vector4(130,141.5,30.5,38)
const CHAPTER_NAMES: Array = ["기초", "초급", "중급", "고급"]
const MIN_LEADER_LENGTH: float = 8.0
static var _coastline: Array = []
# Modern orientation points; these are not Sengoku battle locations.
# Coordinates verified against the linked city publications / coordinate entries.
const CITIES: Array = [
	{"jp":"札幌","ko":"삿포로","lon":141.355,"lat":43.0628,"source":"https://www.city.sapporo.jp/city/map/"},
	{"jp":"仙台","ko":"센다이","lon":140.8728,"lat":38.2647,"source":"https://www.city.sendai.jp/chosatoke/shise/toke/tokesho/h05-01/documents/h05-01.pdf"},
	{"jp":"東京","ko":"도쿄","lon":139.6917,"lat":35.6894,"source":"https://www.toukei.metro.tokyo.lg.jp/faq/fq-faq.htm"},
	{"jp":"名古屋","ko":"나고야","lon":136.900,"lat":35.183,"source":"https://en.wikipedia.org/wiki/Nagoya"},
	{"jp":"京都","ko":"교토","lon":135.7681,"lat":35.0117,"source":"https://www2.city.kyoto.lg.jp/sogo/toukei/Publish/Analysis/News/001Land.pdf"},
	{"jp":"大阪","ko":"오사카","lon":135.5022,"lat":34.6939,"source":"https://en.wikipedia.org/wiki/Osaka"},
	{"jp":"福岡","ko":"후쿠오카","lon":130.4017,"lat":33.5900,"source":"https://facts.city.fukuoka.lg.jp/data/position/"}
]

class MapCanvas extends Control:
	var atlas: Control
	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		clip_contents=true
		set_process(false)
	func _draw() -> void:
		if atlas!=null: atlas.draw_map(self)

var progress: RefCounted
var maps: Array = []
var story_by_id: Dictionary = {}
var geography_by_id: Dictionary = {}
var font: Font
var selected_stage_id: String = ""
var battle_active: bool = false
var all_japan: bool = false
var chapter_index: int = 0
var revealed_ids: Array = []
var available_chapters: Array = []
var unlock_cache: Dictionary = {}
var bounds: Vector4 = CAMPAIGN
var photo_rect: Rect2
var crop_rect: Rect2
var map_area: Rect2
var callout_rects: Dictionary = {}
var projected_coasts: Array = []
var battle_links: Array = []
var pin_groups: Array = []
var pin_buttons: Array = []
var source_anchors: Dictionary = {}
var selected_place_rect: Rect2 = Rect2()
var map_canvas: Control
var selected_entry: Dictionary = {}
var action_button: Button
var gate_button: Button
var detail_scroll: ScrollContainer
var stage_scroll: ScrollContainer
var geography_status: String = "pending"
var data_credits: Array = []
var coordinate_policy: String = ""
var city_labels: Array = []
var city_battle_links: Array = []
var coast_projection_cache: Dictionary = {}

func _geographic_land_polygon(anchor: Vector2) -> PackedVector2Array:
	var local: Vector2=anchor-map_area.position
	var closest: PackedVector2Array=PackedVector2Array()
	var closest_distance: float=INF
	for coast in projected_coasts:
		if coast.triangles.is_empty(): continue
		var polygon: PackedVector2Array=coast.points
		if Geometry2D.is_point_in_polygon(local,polygon): return polygon
		for edge in range(polygon.size()):
			var start: Vector2=polygon[edge]
			var delta: Vector2=polygon[(edge+1)%polygon.size()]-start
			var amount: float=clampf((local-start).dot(delta)/maxf(.000001,delta.length_squared()),0,1)
			var distance: float=local.distance_squared_to(start+delta*amount)
			if distance<closest_distance:
				closest_distance=distance
				closest=polygon
	# The source anchor is retained even where the simplified coast misses a city.
	return closest if closest_distance<=24.0*24.0 else PackedVector2Array()

func _land_name_rect(anchor: Vector2, dimensions: Vector2, occupied: Array[Rect2]) -> Rect2:
	var polygon: PackedVector2Array=_geographic_land_polygon(anchor)
	if polygon.is_empty(): return Rect2()
	var maximum_distance: float=minf(180,minf(map_area.size.x,map_area.size.y)*.30)
	for placement_pass in range(2):
		var best: Rect2=Rect2()
		var best_score: float=INF
		for ring in range(16):
			var radius: float=maximum_distance*float(ring)/15.0
			var count: int=1 if ring==0 else 24
			for direction in range(count):
				var angle: float=TAU*float(direction)/float(count)
				var center: Vector2=anchor+Vector2(cos(angle),sin(angle))*radius
				var candidate: Rect2=Rect2(center-dimensions*.5,dimensions)
				if not map_area.grow(-6).encloses(candidate): continue
				var collision: bool=false
				for other in occupied:
					if candidate.grow(5).intersects(other): collision=true; break
				if collision: continue
				var land_samples: int=0
				var text_centers_on_land: bool=true
				for row in [0.2,0.5,0.8]:
					for column in [0.25,0.5,0.75]:
						var point: Vector2=candidate.position+dimensions*Vector2(column,row)-map_area.position
						var on_land: bool=Geometry2D.is_point_in_polygon(point,polygon)
						if on_land: land_samples+=1
						if column==.5 and not on_land: text_centers_on_land=false
				if not text_centers_on_land: continue
				if placement_pass==0 and land_samples<9: continue
				if placement_pass==1 and land_samples<5: continue
				var score: float=anchor.distance_squared_to(center)+float(9-land_samples)*900
				if score<best_score: best=candidate; best_score=score
		if best.has_area(): return best
	return Rect2()

func _layout_cities() -> void:
	city_labels.clear()
	var names: Array=[]
	var historic_names: Dictionary={}
	# Country/place text comes from the existing authored name/reading pair.
	# It adds no province borders, guessed readings or replacement coordinates.
	for entry in _eligible_entries():
		var id: String=str(entry.id)
		if not geography_by_id.has(id): continue
		var geo: Dictionary=geography_by_id[id]
		var point: Vector2=coordinates(geo)
		if point.x<bounds.x or point.x>bounds.y or point.y<bounds.z or point.y>bounds.w: continue
		var jp: String=str(geo.get("oldNameJP","")).strip_edges()
		var reading: String=str(geo.get("oldNameReading","")).strip_edges()
		var ko: String=str(geo.get("oldNameKo","")).strip_edges()
		var japanese_parts: PackedStringArray=jp.split("・")
		var reading_parts: PackedStringArray=reading.split("・")
		var korean_parts: PackedStringArray=ko.split(" · ")
		if japanese_parts.size()>1 and japanese_parts.size()==reading_parts.size() and japanese_parts.size()==korean_parts.size():
			jp=japanese_parts[0].strip_edges()
			reading=reading_parts[0].strip_edges()
			ko=korean_parts[0].strip_edges()
		if jp.is_empty() or historic_names.has(jp): continue
		historic_names[jp]=true
		names.append({"jp":jp,"reading":reading,"ko":ko,"lon":point.x,"lat":point.y,"kind":"historic","source":geo.get("sources",[])})
	for city in CITIES:
		var point: Vector2=Vector2(city.lon,city.lat)
		if point.x<bounds.x or point.x>bounds.y or point.y<bounds.z or point.y>bounds.w: continue
		var reading: String=""
		for part in RubyReadings.for_text(city.jp): reading+=str(part.get("reading",""))
		names.append({"jp":city.jp,"reading":reading,"ko":city.ko,"lon":city.lon,"lat":city.lat,"kind":"modern","source":city.source})
	var occupied: Array[Rect2]=[]
	for place in names:
		var anchor: Vector2=project(Vector2(place.lon,place.lat))
		var width: float=maxf(GameFonts.japanese().get_string_size(place.jp,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x,GameFonts.body().get_string_size(place.ko,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x)
		width=maxf(width,GameFonts.reading().get_string_size(place.reading,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x)+20
		var word: Control=RubyText.new()
		word.custom_minimum_size.x=1
		word.size.x=width
		word.wrap_japanese=true
		word.meaning_size=18
		word.outline_size=3
		word.set_word({"jp":place.jp,"reading":place.reading,"ko":place.ko},20,true)
		var dimensions: Vector2=Vector2(width,float(word.get_text_layout().height))
		word.free()
		var chosen: Rect2=_land_name_rect(anchor,dimensions,occupied)
		if not chosen.has_area(): continue
		occupied.append(chosen)
		var label: Dictionary=place.duplicate()
		label["anchor"]=anchor
		label["rect"]=chosen
		city_labels.append(label)

func _ready() -> void:
	theme = GameFonts.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_process(false)
	set_physics_process(false)
	resized.connect(_rebuild)
	_rebuild()

func configure(account: RefCounted, stage_maps: Array, story: Dictionary, geography: Dictionary, face: Font) -> void:
	progress=account
	maps=stage_maps.duplicate(true)
	maps.sort_custom(func(a,b): return int(a.stageNumber)<int(b.stageNumber))
	font=face if face!=null else GameFonts.body()
	story_by_id.clear()
	for entry in story.get("stages",[]): story_by_id[str(entry.get("stageId",""))]=entry
	geography_by_id.clear()
	for entry in geography.get("stages",[]):
		if entry is Dictionary and valid_coordinates(entry): geography_by_id[str(entry.get("stageId",""))]=entry
	geography_status=str(geography.get("status","pending"))
	data_credits=geography.get("dataCredits",[]).duplicate(true)
	coordinate_policy=str(geography.get("coordinatePolicyKo",""))
	_sync_progress()
	_choose_known_stage(selected_stage_id)
	_rebuild()

func show_stage(stage_id: String = "", can_resume: bool = false) -> void:
	battle_active=can_resume
	_sync_progress()
	_choose_known_stage(stage_id)
	show()
	_rebuild()

func stage(id: String) -> Dictionary:
	for entry in maps:
		if str(entry.id)==id: return entry
	return {}

func valid_coordinates(entry: Dictionary) -> bool:
	if not (entry.get("lat") is int or entry.get("lat") is float) or not (entry.get("lon") is int or entry.get("lon") is float): return false
	return is_finite(float(entry.lat)) and is_finite(float(entry.lon)) and absf(float(entry.lat))<=90 and absf(float(entry.lon))<=180

func coordinates(entry: Dictionary) -> Vector2:
	var location=entry.get("phaseLocation",{})
	if location is Dictionary and valid_coordinates(location): return Vector2(float(location.lon),float(location.lat))
	return Vector2(float(entry.lon),float(entry.lat))

func project(lon_lat: Vector2) -> Vector2:
	return photo_rect.position+Vector2((lon_lat.x-bounds.x)/(bounds.y-bounds.x),(bounds.w-lon_lat.y)/(bounds.w-bounds.z))*photo_rect.size

func _load_coastline() -> void:
	if not _coastline.is_empty(): return
	var data=JSON.parse_string(FileAccess.get_file_as_string(COASTLINE_PATH))
	if not data is Dictionary: return
	for ring in data.get("rings",[]):
		if not ring is Array or ring.size()<3: continue
		var points: PackedVector2Array=[]
		for coordinate in ring:
			if coordinate is Array and coordinate.size()==2:
				points.append(Vector2(float(coordinate[0]),float(coordinate[1])))
		if points.size()>3 and points[0].is_equal_approx(points[-1]): points.resize(points.size()-1)
		if points.size()>=3: _coastline.append(points)

func _sync_progress() -> void:
	revealed_ids.clear()
	unlock_cache.clear()
	available_chapters.assign([0,1,2,3])
	var latest_number: int=1
	for entry in maps:
		var id: String=str(entry.id)
		var unlocked: bool=progress!=null and progress.map_unlocked(id)
		unlock_cache[id]=unlocked
		if unlocked or _cleared(id):
			revealed_ids.append(id)
			latest_number=maxi(latest_number,int(entry.stageNumber))
	if revealed_ids.is_empty() and not maps.is_empty(): revealed_ids.append(str(maps[0].id))
	# The single next locked battle gives the player an immediate objective.
	for entry in maps:
		if int(entry.stageNumber)>latest_number:
			revealed_ids.append(str(entry.id))
			break

func _choose_known_stage(requested: String) -> void:
	if not stage(requested).is_empty():
		selected_stage_id=requested
	elif stage(selected_stage_id).is_empty():
		selected_stage_id=""
		for entry in maps:
			if _unlocked(str(entry.id)) or _cleared(str(entry.id)): selected_stage_id=str(entry.id)
		if selected_stage_id.is_empty() and not revealed_ids.is_empty(): selected_stage_id=str(revealed_ids[0])
	chapter_index=int((int(stage(selected_stage_id).get("stageNumber",1))-1)/10)

func _label(parent: Node, text: String, points: int = 20, ink: Color = Color(UIStyle.TEXT), initial_width: float = 340) -> Label:
	var label: Label=UIStyle.TooltipLabel.new()
	# Give autowrap a real line width before text enters the tree. Otherwise a
	# fresh Label can retain its width-zero minimum height at first presentation.
	label.size.x=initial_width
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",GameFonts.heading() if points>=26 else GameFonts.body())
	label.add_theme_font_size_override("font_size",maxi(20,points))
	label.add_theme_color_override("font_color",ink)
	label.text=text
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button=UIStyle.TooltipButton.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,44)
	button.add_theme_font_override("font",GameFonts.body())
	button.add_theme_font_size_override("font_size",20)
	for state_name in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state_name,UIStyle.textured_button(state_name))
	button.pressed.connect(callback)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	return button

func _name_ruby(parent: Node, jp: String, reading: String, ko: String, points: int) -> Control:
	var ruby: Control=RubyText.new()
	ruby.font=GameFonts.japanese()
	ruby.reading_font=GameFonts.reading()
	ruby.meaning_font=GameFonts.body()
	ruby.ink=Color(UIStyle.INK)
	ruby.reading_ink=Color("65533e")
	ruby.meaning_ink=Color("584834")
	ruby.wrap_japanese=true
	ruby.size.x=356
	ruby.merge_adjacent_readings=false
	ruby.show_reading_guides=false
	ruby.reading_group_palette[0]=Color("795424")
	ruby.reading_group_palette[1]=Color("285f74")
	ruby.set_word({"jp":jp,"reading":reading,"ko":ko,"parts":[{"text":jp,"reading":reading}]},points,true)
	parent.add_child(ruby)
	return ruby

func _unlocked(id: String) -> bool:
	return bool(unlock_cache.get(id,false))

func _cleared(id: String) -> bool:
	return progress!=null and progress.map_cleared(id)

func _status(id: String) -> String:
	if _cleared(id): return "클리어"
	if _unlocked(id): return "출진 가능"
	return "다음 전투 · 잠김" if id in revealed_ids else "잠김"

func _eligible_entries() -> Array:
	var entries: Array=[]
	for entry in maps:
		if int((int(entry.stageNumber)-1)/10)==chapter_index: entries.append(entry)
	return entries

func _pin_rect(group: Array) -> Rect2:
	return callout_rects.get(str(group[0]),Rect2())

func _layout_callouts() -> void:
	pin_groups.clear()
	callout_rects.clear()
	source_anchors.clear()
	battle_links.clear()
	city_battle_links.clear()
	var entries: Array=_eligible_entries()
	selected_place_rect=Rect2()
	var used: Array[Rect2]=[]
	for place in city_labels: used.append(place.rect.grow(5))
	for entry in entries:
		var id: String=str(entry.id)
		if not geography_by_id.has(id): continue
		var point: Vector2=coordinates(geography_by_id[id])
		var actual: Vector2=project(point)
		source_anchors[id]={"lon":point.x,"lat":point.y,"display":actual}
		var marker_size: Vector2=Vector2(clampf(GameFonts.body().get_string_size(_atlas_label(id,"battleKo"),HORIZONTAL_ALIGNMENT_LEFT,-1,18).x+24,150,300),44)
		var best: Rect2=Rect2()
		var distance: float=INF
		# Repeated battles share a real coordinate. Only their compact markers
		# fan out; the dot and leader remain attached to the true location.
		for ring in range(20):
			var count: int=1 if ring==0 else 16
			for index in range(count):
				var angle: float=-PI*.5+TAU*float(index)/float(count)
				var center: Vector2=actual+Vector2(cos(angle),sin(angle))*float(ring)*38.0
				var minimum: Vector2=map_area.position+marker_size*.5+Vector2(8,8)
				var maximum: Vector2=map_area.end-marker_size*.5-Vector2(8,8)
				center=center.clamp(minimum,maximum)
				var candidate: Rect2=Rect2(center-marker_size*.5,marker_size)
				var battle_endpoint: Vector2=Vector2(clampf(actual.x,candidate.position.x,candidate.end.x),clampf(actual.y,candidate.position.y,candidate.end.y))
				if actual.distance_to(battle_endpoint)<MIN_LEADER_LENGTH: continue
				var occupied: bool=false
				for other in used:
					if candidate.grow(5).intersects(other): occupied=true;break
				if occupied: continue
				var score: float=actual.distance_squared_to(center)
				if score<distance: best=candidate;distance=score
			if best.has_area(): break
		if not best.has_area():
			for grid_y in range(8,int(map_area.size.y-marker_size.y-8),12):
				for grid_x in range(8,int(map_area.size.x-marker_size.x-8),12):
					var fallback: Rect2=Rect2(map_area.position+Vector2(grid_x,grid_y),marker_size)
					var overlap: bool=false
					for occupied in used:
						if fallback.grow(5).intersects(occupied): overlap=true; break
					if overlap: continue
					var gap: float=actual.distance_squared_to(fallback.get_center())
					if gap<distance: best=fallback; distance=gap
		if best.has_area():
			used.append(best)
			callout_rects[id]=best
			pin_groups.append([id])
	for index in range(entries.size()-1):
		var first: String=str(entries[index].id)
		var second: String=str(entries[index+1].id)
		if source_anchors.has(first) and source_anchors.has(second):
			battle_links.append({"from":first,"to":second,"battleKo":_atlas_label(second,"battleKo")})

func _atlas_label(id: String, key: String) -> String:
	var data: Dictionary=stage(id).get("historicalBattlefield",{}).get("atlasLabels",{})
	if data.has(key): return str(data[key])
	var geo: Dictionary=geography_by_id.get(id,{})
	if key=="historicPlaceKo": return str(geo.get("oldNameKo","지명 확인 중")).split(" · ")[-1]
	if key=="modernPlaceKo": return str(geo.get("modernNameKo","현재 지명 확인 중")).split(" · ")[0]
	return str(story_by_id.get(id,{}).get("battleKo",stage(id).get("title","전투")))

func _change_chapter(chapter: int) -> void:
	if chapter not in available_chapters: return
	chapter_index=chapter
	var entries: Array=_eligible_entries()
	if not entries.is_empty(): selected_stage_id=str(entries[0].id)
	for entry in entries:
		if _unlocked(str(entry.id)) and not _cleared(str(entry.id)):
			selected_stage_id=str(entry.id)
			break
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree() or not visible or size.x<700 or size.y<500: return
	_sync_progress()
	if chapter_index not in available_chapters: _choose_known_stage("")
	for child in get_children():
		if child.name=="InterfaceDetailReader": continue
		remove_child(child)
		child.queue_free()
	pin_buttons.clear()
	_load_coastline()
	var background: Panel=Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel",UIStyle.textured_panel("lacquer"))
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var title: Label=_label(self,"全国地図 · 전국 원정 지도",30)
	title.position=Vector2(24,10)
	title.size=Vector2(size.x-48,76)
	var note: Label=_label(self,"지리 이름: 육지 위 · 전투명: 실제 위치에 연결 · 붉은 점선: 게임 진행 순서",20,Color(UIStyle.MUTED),size.x-48)
	note.position=Vector2(24,96)
	note.size=Vector2(size.x-48,36)
	var campaign_zoom: Button=_button(self,"원정 지역",func(): all_japan=false; _rebuild())
	campaign_zoom.name="CampaignZoom"
	campaign_zoom.position=Vector2(24,140)
	campaign_zoom.size=Vector2(140,44)
	var japan_zoom: Button=_button(self,"일본 전체",func(): all_japan=true; _rebuild())
	japan_zoom.name="JapanZoom"
	japan_zoom.position=Vector2(174,140)
	japan_zoom.size=Vector2(140,44)
	for chapter in available_chapters:
		var tier: Button=_button(self,str(CHAPTER_NAMES[chapter]),_change_chapter.bind(chapter))
		tier.name="AtlasTier_%d"%chapter
		tier.position=Vector2(326+chapter*120,140)
		tier.size=Vector2(112,44)
		if chapter==chapter_index: tier.add_theme_stylebox_override("normal",UIStyle.textured_button("normal",false,true))
	bounds=JAPAN if all_japan else CAMPAIGN
	map_area=Rect2(24,208,maxf(200,size.x-456),size.y-288)
	# Match the mean latitude so Japan's recognizable shape is not stretched.
	var ratio: float=(bounds.y-bounds.x)*cos(deg_to_rad((bounds.z+bounds.w)*.5))/(bounds.w-bounds.z)
	var map_size: Vector2=Vector2(minf(map_area.size.x,map_area.size.y*ratio),minf(map_area.size.y,map_area.size.x/ratio))
	photo_rect=Rect2(map_area.position+(map_area.size-map_size)*.5,map_size)
	crop_rect=Rect2()
	var projection_key: String=str(bounds)+str(map_area)+str(photo_rect)
	if not coast_projection_cache.has(projection_key):
		var projected: Array=[]
		for ring in _coastline:
			var points: PackedVector2Array=[]
			for point in ring: points.append(project(point)-map_area.position)
			projected.append({"points":points,"triangles":Geometry2D.triangulate_polygon(points)})
		if coast_projection_cache.size()>=8: coast_projection_cache.clear()
		coast_projection_cache[projection_key]=projected
	projected_coasts=coast_projection_cache[projection_key]
	_layout_cities()
	_layout_callouts()
	map_canvas=MapCanvas.new()
	map_canvas.name="CoordinateMap"
	map_canvas.atlas=self
	map_canvas.position=map_area.position
	map_canvas.size=map_area.size
	add_child(map_canvas)
	for place in city_labels:
		var name_text: Control=RubyText.new()
		name_text.name=("AtlasHistoric_" if place.kind=="historic" else "AtlasCity_")+str(place.jp)
		name_text.font=GameFonts.japanese()
		name_text.reading_font=GameFonts.reading()
		name_text.meaning_font=GameFonts.body()
		name_text.custom_minimum_size.x=1
		name_text.position=place.rect.position
		name_text.size=place.rect.size
		name_text.wrap_japanese=true
		name_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		name_text.meaning_size=18
		name_text.ink=Color("5a4127") if place.kind=="historic" else Color("244d49")
		name_text.reading_ink=name_text.ink
		name_text.meaning_ink=name_text.ink
		name_text.outline_size=3
		name_text.outline_ink=Color("f4e9ce")
		name_text.set_meta("real_anchor",place.anchor)
		name_text.set_word({"jp":place.jp,"reading":place.reading,"ko":place.ko},20,true)
		add_child(name_text)
	for group in pin_groups:
		var id: String=str(group[0])
		var number: int=int(stage(id).stageNumber)
		var button: Button=_button(self,_atlas_label(id,"battleKo"),_select_stage.bind(id))
		button.name="AtlasPin_%02d"%number
		button.set_meta("stage_ids",[id])
		button.set_meta("real_anchor",source_anchors[id].display)
		var card_rect: Rect2=callout_rects[id]
		button.position=card_rect.position
		button.size=card_rect.size
		button.custom_minimum_size=Vector2(1,44)
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.clip_text=true
		button.add_theme_font_size_override("font_size",18)
		for state_name in ["normal","hover","pressed","disabled"]: button.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
		button.add_theme_stylebox_override("focus",UIStyle.frame("00000000","845632"))
		button.add_theme_color_override("font_outline_color",Color("f4e9ce"))
		button.add_theme_constant_override("outline_size",4)
		button.add_theme_color_override("font_hover_color",Color("883e29"))
		button.add_theme_color_override("font_pressed_color",Color("883e29"))
		var ink: Color=Color("392d22") if _unlocked(id) else Color("756959")
		button.add_theme_color_override("font_color",ink)
		button.tooltip_text="%02d · %s\n%s\n현재 %s"%[number,_atlas_label(id,"battleKo"),_atlas_label(id,"historicPlaceKo"),_atlas_label(id,"modernPlaceKo")]
		if id==selected_stage_id:
			button.add_theme_color_override("font_color",Color("883e29"))
		pin_buttons.append(button)
	if geography_by_id.is_empty() or _coastline.is_empty():
		var pending: Label=_label(self,"지도 자료를 준비 중입니다. 오른쪽에서 알려진 전투를 선택할 수 있습니다.",24,Color(UIStyle.INK),map_area.size.x-36)
		pending.position=map_area.position+Vector2(18,18)
		pending.size=Vector2(map_area.size.x-36,100)
	_build_sidebar(Rect2(size.x-408,140,384,size.y-220))
	var home: Button=_button(self,"본진으로",func(): home_requested.emit())
	home.name="AtlasHome"
	home.position=Vector2(24,size.y-62)
	home.size=Vector2(150,44)
	var catalog: Button=_button(self,"전장 목록",func(): catalog_requested.emit())
	catalog.name="AtlasCatalog"
	catalog.position=Vector2(184,size.y-62)
	catalog.size=Vector2(160,44)
	if battle_active:
		var resume: Button=_button(self,"전투 계속",func(): resume_requested.emit())
		resume.name="AtlasResume"
		resume.position=Vector2(354,size.y-62)
		resume.size=Vector2(170,44)
	var credit: Button=_button(self,"해안선 · 역사 자료 출처",_show_credits)
	credit.name="AtlasCredits"
	credit.position=Vector2(size.x-402,size.y-62)
	credit.size=Vector2(378,44)
	credit.tooltip_text=_credit_text()
	var reader: Node=get_node_or_null("InterfaceDetailReader")
	if reader!=null: move_child(reader,get_child_count()-1)

func _credit_text() -> String:
	var lines: PackedStringArray=["자체 제작 전국시대풍 지도 · 현대 해안선을 지리 참고로 사용했습니다.","해안선: Natural Earth 1:50m Countries v5.1.1 · Public Domain.","https://www.naturalearthdata.com/about/terms-of-use/","https://www.naturalearthdata.com/downloads/50m-cultural-vectors/50m-admin-0-countries-2/","전국시대 영토·병력 이동의 정확한 복원도가 아닙니다."]
	for item in data_credits:
		if not item is Dictionary: continue
		lines.append(str(item.get("credit",item.get("title",""))))
		lines.append(str(item.get("url","")))
		if not str(item.get("license","")).is_empty(): lines.append("라이선스: "+str(item.license))
		if not str(item.get("modifiedKo","")).is_empty(): lines.append(str(item.modifiedKo))
	if not coordinate_policy.is_empty(): lines.append(coordinate_policy)
	lines.append("한자 도시명은 현대의 방향 참고점입니다. 청록 점선은 가까운 도시와 전투 라벨의 UI 연결이며 실제 전장 위치·행군로가 아닙니다. 붉은 점선은 게임 진행 순서입니다.")
	for city in CITIES: lines.append("현대 도시 참고 · "+str(city.jp)+" · "+str(city.source))
	return "\n".join(lines)

func _show_credits() -> void:
	UIStyle.open_detail(self,"지도 자료 · 출처",[{"title":"자료 출처","text":_credit_text()}])

func _select_stage(id: String) -> void:
	if stage(id).is_empty(): return
	selected_stage_id=id
	selection_changed.emit(id)
	_rebuild()

func _gate_stage() -> String:
	if progress==null: return ""
	var selected: Dictionary=stage(selected_stage_id)
	var candidate: String=selected_stage_id
	if not _unlocked(candidate):
		candidate=progress.previous_map(selected_stage_id)
	if _unlocked(candidate) and _cleared(candidate) and not progress.map_assessed(candidate) and int(stage(candidate).get("stageNumber",40))<40: return candidate
	return ""

func _show_stage_detail(section: int) -> void:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://native/learning_plans.json"))
	var plan: Dictionary=data.get("stages",{}).get(selected_stage_id,{}) if data is Dictionary else {}
	var reader: Control=UIStyle.open_detail(self,str(story_by_id.get(selected_stage_id,{}).get("battleKo",selected_entry.get("title","전투"))),UIStyle.stage_detail_sections(selected_entry,story_by_id.get(selected_stage_id,{}),geography_by_id.get(selected_stage_id,{}),plan))
	reader.set("section_index",section)

func _step_stage(offset: int) -> void:
	var entries: Array=_eligible_entries()
	for index in range(entries.size()):
		if str(entries[index].id)==selected_stage_id:
			_select_stage(str(entries[clampi(index+offset,0,entries.size()-1)].id))
			return

func _build_sidebar(rect: Rect2) -> void:
	var panel: PanelContainer=PanelContainer.new()
	panel.name="AtlasPaperPanel"
	panel.position=rect.position
	panel.size=rect.size
	panel.add_theme_stylebox_override("panel",UIStyle.textured_panel("paper",Color("ebdfc8")))
	add_child(panel)
	var stack: VBoxContainer=VBoxContainer.new()
	stack.add_theme_constant_override("separation",8)
	panel.add_child(stack)
	selected_entry=stage(selected_stage_id)
	if selected_entry.is_empty(): return
	var story: Dictionary=story_by_id.get(selected_stage_id,{})
	var geo: Dictionary=geography_by_id.get(selected_stage_id,{})
	_label(stack,"%02d · %d년 · %s"%[int(selected_entry.stageNumber),int(story.get("year",0)),_status(selected_stage_id)],20,Color("6b5230"),rect.size.x-28)
	_label(stack,str(story.get("battleKo",selected_entry.title)),22,Color(UIStyle.INK),rect.size.x-28)
	if not geo.is_empty():
		if str(geo.get("oldNameJP","")).length()<=12 and str(geo.get("oldNameReading","")).length()<=36:
			_name_ruby(stack,str(geo.get("oldNameJP","")),str(geo.get("oldNameReading","")),str(geo.get("oldNameKo","")),24)
		else:
			_label(stack,str(geo.get("oldNameKo","")),20,Color(UIStyle.INK),rect.size.x-28)
	var spacer: Control=Control.new()
	spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL
	stack.add_child(spacer)
	var detail_actions: HBoxContainer=HBoxContainer.new()
	detail_actions.add_theme_constant_override("separation",8)
	stack.add_child(detail_actions)
	var history: Button=_button(detail_actions,"역사 크게 보기",_show_stage_detail.bind(0))
	history.name="AtlasDetails"
	history.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var location: Button=_button(detail_actions,"지명·지형",_show_stage_detail.bind(1))
	location.name="AtlasLocationDetails"
	location.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	action_button=_button(stack,"선택한 전투에 출진",func(): stage_requested.emit(selected_stage_id))
	action_button.name="AtlasSortie"
	action_button.disabled=not _unlocked(selected_stage_id)
	action_button.tooltip_text=progress.map_lock_reason(selected_stage_id) if action_button.disabled and progress!=null else ""
	var gate_id: String=_gate_stage()
	gate_button=_button(stack,"다음 전투 해금 시험" if gate_id==selected_stage_id else "이전 전투 해금 시험",func(): assessment_requested.emit(gate_id))
	gate_button.name="AtlasAssessment"
	gate_button.visible=not gate_id.is_empty()
	var entries: Array=_eligible_entries()
	var selected_index: int=0
	for index in range(entries.size()):
		if str(entries[index].id)==selected_stage_id: selected_index=index
	_label(stack,"%s 전투 · %d / %d"%[CHAPTER_NAMES[chapter_index],selected_index+1,entries.size()],20,Color(UIStyle.INK),rect.size.x-28).name="AtlasStageListTitle"
	var navigation: HBoxContainer=HBoxContainer.new()
	navigation.add_theme_constant_override("separation",8)
	stack.add_child(navigation)
	var previous: Button=_button(navigation,"이전 전투",_step_stage.bind(-1))
	previous.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	previous.disabled=selected_index==0
	var next: Button=_button(navigation,"다음 전투",_step_stage.bind(1))
	next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	next.disabled=selected_index>=entries.size()-1

func draw_map(canvas: Control) -> void:
	var local_rect: Rect2=Rect2(Vector2.ZERO,map_area.size)
	canvas.draw_rect(local_rect,Color("c5d6d3"))
	# Sparse ink-wave marks add a paper-chart texture without fake geography.
	for row in range(9):
		for column in range(12):
			var center: Vector2=Vector2(26+column*78,25+row*75)
			canvas.draw_arc(center,13,.25,2.8,9,Color("7b989225"),1,true)
	for ring in projected_coasts:
		var points: PackedVector2Array=ring.points
		if not ring.triangles.is_empty(): canvas.draw_colored_polygon(points,Color("eadfc1"))
		var closed: PackedVector2Array=points.duplicate()
		closed.append(points[0])
		canvas.draw_polyline(closed,Color("66583f"),1.6,true)
	for link in battle_links:
		var start: Vector2=source_anchors[link.from].display-map_area.position
		var end: Vector2=source_anchors[link.to].display-map_area.position
		if start.distance_to(end)>2:
			canvas.draw_dashed_line(start,end,Color("973e31a0"),2,7,true,true)
			var direction: Vector2=(end-start).normalized()
			var middle: Vector2=start.lerp(end,.56)
			canvas.draw_line(middle-direction.rotated(.6)*10,middle,Color("973e31"),2,true)
			canvas.draw_line(middle-direction.rotated(-.6)*10,middle,Color("973e31"),2,true)
	for id in source_anchors:
		var actual: Vector2=source_anchors[id].display
		if not callout_rects.has(id): continue
		var rect: Rect2=callout_rects[id]
		var endpoint: Vector2=Vector2(clampf(actual.x,rect.position.x+6,rect.end.x-6),clampf(actual.y,rect.position.y+6,rect.end.y-6))
		canvas.draw_line(actual-map_area.position,endpoint-map_area.position,Color("564535"),1.3,true)
		var anchor_ink: Color=Color("973e31") if _unlocked(id) else Color("777266")
		canvas.draw_line(actual-map_area.position-Vector2(4,0),actual-map_area.position+Vector2(4,0),anchor_ink,1.5,true)
		canvas.draw_line(actual-map_area.position-Vector2(0,4),actual-map_area.position+Vector2(0,4),anchor_ink,1.5,true)
		if id==selected_stage_id:
			canvas.draw_arc(actual-map_area.position,10,0,TAU,24,Color("973e31"),2,true)
	canvas.draw_rect(local_rect,Color("aa8c52"),false,2)

func diagnostics() -> Dictionary:
	var groups: Array=[]
	var visible_ids: Array=[]
	for group in pin_groups:
		groups.append({"stageIds":group.duplicate(),"rect":_pin_rect(group),"anchor":source_anchors[str(group[0])].display})
		visible_ids.append(str(group[0]))
	var intersections: Array=[]
	for first in range(groups.size()):
		for second in range(first+1,groups.size()):
			if groups[first].rect.intersects(groups[second].rect): intersections.append([groups[first].stageIds,groups[second].stageIds])
	return {"numberedDots":false,"mapLabelScheme":"direct land geographic JP/ruby/KO text; battle-name-only buttons with true-coordinate leaders","labelIntersections":intersections,"ordinaryScroll":false,"selectedStageId":selected_stage_id,"geographyStatus":geography_status,"geographyCount":geography_by_id.size(),"mapCount":maps.size(),"sourcePath":COASTLINE_PATH,"sourcePixelSize":Vector2.ZERO,"sourceCrop":Rect2(),"photoRect":photo_rect,"mapArea":map_area,"bounds":bounds,"anchors":source_anchors.duplicate(true),"pinGroups":groups,"static":true,"processing":is_processing(),"fade":false,"historicalTerritoryMap":false,"credits":_credit_text(),"mapAccuracy":"Original vector atlas based on Natural Earth's physical coastline. Battle connections show game progression, not documented march routes.","stageActionEnabled":action_button!=null and not action_button.disabled,"chapter":chapter_index,"availableChapters":available_chapters.duplicate(),"revealedStageIds":revealed_ids.duplicate(),"visibleStageIds":visible_ids,"battleLinks":battle_links.duplicate(true),"cityLabels":city_labels.duplicate(true),"cityBattleLinks":city_battle_links.duplicate(true),"coastProjectionCacheCount":coast_projection_cache.size(),"coastlineRingCount":_coastline.size(),"coastlineCoordinateCount":1097}
