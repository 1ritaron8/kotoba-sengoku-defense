extends Control

const GameFonts = preload("res://native/game_fonts.gd")
const RubyReadings = preload("res://native/ruby_readings.gd")

const MIN_READING_SIZE: int = 16
const TEXT_PADDING: float = 4.0
const READING_GAP: float = 2.0
const LINE_GAP: float = 8.0

var word: Dictionary = {}
var _text_value: String = ""
var text: String:
	get: return _text_value
	set(value): set_text(value)
var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
var _display_parts: Array = []
var base_size: int = 34
var font: Font = GameFonts.japanese()
var reading_font: Font = GameFonts.reading()
var meaning_font: Font = GameFonts.body()
var ink: Color = Color("ead9b9")
var reading_ink: Color = Color("d7dec9")
var meaning_ink: Color = Color("ccd5c7")
var meaning_visible: bool = true
var meaning_size: int = 20
var wrap_japanese: bool = false
var outline_size: int = 0
var outline_ink: Color = Color(0.04,0.05,0.04,0.95)
var min_reading_size: int = MIN_READING_SIZE
var group_spacing: float = 0.0
var show_reading_guides: bool = false
var merge_adjacent_readings: bool = false
var colour_reading_groups: bool = true
var reading_group_palette: Array[Color] = [Color("f5d58a"),Color("a3dafa")]

func _ready() -> void:
	resized.connect(_sync_minimum_height)
	_sync_minimum_height()

func _init() -> void:
	custom_minimum_size = Vector2(110,89)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_word(value: Dictionary, text_size: int = 34, show_meaning: bool = true) -> void:
	word = value
	_text_value = str(value.get("jp",""))
	_display_parts = RubyReadings.for_word(value)
	base_size = text_size
	meaning_visible = show_meaning
	_sync_minimum_height()

func set_text(value: String, text_size: int = -1, context_words: Array = []) -> void:
	set_word(RubyReadings.word_for_text(value,context_words),base_size if text_size<0 else text_size,false)

static func make_tooltip(value: String, context_words: Array = []) -> Control:
	var panel: PanelContainer=PanelContainer.new()
	panel.name="AnnotatedTooltip"
	var box: StyleBoxFlat=StyleBoxFlat.new()
	box.bg_color=Color("141819f5")
	box.border_color=Color("67614f")
	box.set_border_width_all(1)
	box.content_margin_left=10
	box.content_margin_right=10
	box.content_margin_top=6
	box.content_margin_bottom=6
	panel.add_theme_stylebox_override("panel",box)
	var ruby: Control=load("res://native/ruby_label.gd").new()
	ruby.name="TooltipRuby"
	ruby.font=GameFonts.body()
	ruby.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	ruby.wrap_japanese=true
	ruby.colour_reading_groups=false
	ruby.custom_minimum_size.x=420
	ruby.size.x=420
	ruby.set_text(value,20,context_words)
	panel.add_child(ruby)
	return panel

func _pieces() -> Array:
	var pieces: Array = _display_parts
	if pieces.is_empty():
		var jp: String = str(word.get("jp",""))
		var reading: String = str(word.get("reading",""))
		pieces = [{"text":jp,"reading":reading if reading!=jp else ""}]
	if not merge_adjacent_readings:
		return pieces
	var grouped: Array = []
	for piece in pieces:
		var body: String = str(piece.get("text",""))
		var kana: String = str(piece.get("reading",""))
		var has_reading: bool = not kana.is_empty() and kana!=body
		if has_reading and not grouped.is_empty() and not str(grouped[-1].get("reading","")).is_empty():
			grouped[-1].text = str(grouped[-1].text)+body
			grouped[-1].reading = str(grouped[-1].reading)+kana
		else:
			grouped.append({"text":body,"reading":kana if has_reading else ""})
	return grouped

func _reading_size(text_size: int) -> int:
	return maxi(maxi(MIN_READING_SIZE,min_reading_size),ceili(text_size*0.55))

func _text_lines(face: Font, text: String, point_size: int, width: float) -> Array[String]:
	var lines: Array[String] = []
	for paragraph in text.split("\n"):
		var current: String = ""
		for character in paragraph:
			var candidate: String = current+character
			if not current.is_empty() and face.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x>width:
				lines.append(current.strip_edges())
				current = character
			else:
				current = candidate
		if not current.is_empty():
			lines.append(current.strip_edges())
	return lines

func _part_width(face: Font, part: Dictionary, text_size: int) -> float:
	# Ruby can overhang above a word, but never changes the base glyph advance.
	return face.get_string_size(str(part.get("text","")),HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x

func _group_gap(_previous: Dictionary, _part: Dictionary) -> float:
	# Retain the public option for callers, without inserting artificial spaces.
	return 0.0

func _japanese_lines(face: Font, width: float, text_size: int) -> Array:
	var kana_face: Font = reading_font if reading_font!=null else face
	var lines: Array = []
	var current: Array = []
	var body_used: float = 0.0
	var reading_used: float = 0.0
	var reading_count: int = 0
	var group_index: int = -1
	for part in _pieces():
		group_index += 1
		var body: String = str(part.get("text",""))
		var kana: String = str(part.get("reading",""))
		var fragments: Array = [part]
		if kana.is_empty() or kana==body:
			fragments = []
			for character in body: fragments.append({"text":character})
		for fragment in fragments:
			body = str(fragment.get("text",""))
			if body=="\n":
				lines.append(current)
				current=[]
				body_used=0.0
				reading_used=0.0
				reading_count=0
				continue
			kana = str(fragment.get("reading",""))
			if kana==body: kana = ""
			var span: float = minf(width,_part_width(face,fragment,text_size))
			var kana_lines: Array[String] = _text_lines(kana_face,kana,_reading_size(text_size),width)
			var kana_span: float = 0.0
			for text in kana_lines: kana_span=maxf(kana_span,kana_face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,_reading_size(text_size)).x)
			var reading_gap: float = READING_GAP if reading_count>0 and kana_span>0 else 0.0
			if maxf(body_used+span,reading_used+reading_gap+kana_span)>width and not current.is_empty():
				lines.append(current)
				current=[]
				body_used=0.0
				reading_used=0.0
				reading_count=0
				reading_gap=0.0
			current.append({"span":span,"gap":0.0,"group":group_index,"body":_text_lines(face,body,text_size,width),"reading":kana_lines,"reading_span":kana_span})
			body_used+=span
			reading_used+=reading_gap+kana_span
			if kana_span>0: reading_count+=1
	if not current.is_empty(): lines.append(current)
	return lines

func _reading_positions(row: Array, body_left: float, width: float) -> Dictionary:
	var positions: Dictionary={}
	var preferred_positions: Dictionary={}
	var annotated: Array=[]
	var body_x: float=body_left
	var previous_end: float=TEXT_PADDING-READING_GAP
	for index in range(row.size()):
		var part: Dictionary=row[index]
		if float(part.reading_span)>0:
			var preferred: float=body_x+(float(part.span)-float(part.reading_span))*.5
			preferred_positions[index]=preferred
			var start: float=maxf(preferred,previous_end+READING_GAP)
			positions[index]=start
			annotated.append(index)
			previous_end=start+float(part.reading_span)
		body_x+=float(part.span)
	# Shift overflowing readings back into the widget while preserving their
	# order and colour correspondence. Only ruby moves; base advances stay fixed.
	var next_start: float=TEXT_PADDING+width+READING_GAP
	for ordinal in range(annotated.size()-1,-1,-1):
		var index: int=annotated[ordinal]
		var span: float=float(row[index].reading_span)
		positions[index]=minf(float(positions[index]),next_start-READING_GAP-span)
		next_start=float(positions[index])
	if not annotated.is_empty():
		var displacement: float=0.0
		for index in annotated: displacement+=float(positions[index])-float(preferred_positions[index])
		var first: int=annotated[0]
		var last: int=annotated[-1]
		var preferred_shift: float=-displacement/annotated.size()
		if annotated.size()==row.size():
			preferred_shift=(body_left+body_x)*.5-(float(positions[first])+float(positions[last])+float(row[last].reading_span))*.5
		var shift: float=clampf(preferred_shift,TEXT_PADDING-float(positions[first]),TEXT_PADDING+width-float(positions[last])-float(row[last].reading_span))
		for index in annotated: positions[index]=float(positions[index])+shift
	return positions

func _text_run(face: Font, text: String, point_size: int, x: float, top: float, role: String) -> Dictionary:
	var width: float = face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x
	return {"text":text,"size":point_size,"role":role,"position":Vector2(x,top+face.get_ascent(point_size)),"bounds":Rect2(x,top,width,face.get_height(point_size))}

# Drawing and minimum height use the same measured baselines, including font descent.
func get_text_layout() -> Dictionary:
	var face: Font = font if font!=null else ThemeDB.fallback_font
	var kana_face: Font = reading_font if reading_font!=null else face
	var korean_face: Font = meaning_font if meaning_font!=null else face
	var width: float = maxf(1.0,size.x-TEXT_PADDING*2.0) if size.x>10 else 592.0
	var text_size: int = base_size
	if not wrap_japanese:
		while text_size>18:
			var requested: float = 0.0
			var previous_part: Dictionary = {}
			for part in _pieces():
				requested += _group_gap(previous_part,part)
				requested += _part_width(face,part,text_size)
				previous_part = part
			if requested<=width:
				break
			text_size -= 1
	var ruby_size: int = _reading_size(text_size)
	var lines: Array = _japanese_lines(face,width,text_size)
	var runs: Array = []
	var guides: Array = []
	var annotated_groups: Dictionary = {}
	for row in lines:
		for part in row:
			if not part.reading.is_empty() and not annotated_groups.has(int(part.group)):
				annotated_groups[int(part.group)] = annotated_groups.size()
	var y: float = TEXT_PADDING
	for row in lines:
		var total_width: float = 0.0
		var reading_rows: int = 0
		var body_rows: int = 1
		for part in row:
			total_width += float(part.gap)+float(part.span)
			reading_rows = maxi(reading_rows,part.reading.size())
			body_rows = maxi(body_rows,part.body.size())
		var reading_height: float = reading_rows*kana_face.get_height(ruby_size)
		var body_y: float = y+reading_height+(READING_GAP if reading_rows>0 else 0.0)
		var x: float = TEXT_PADDING
		if horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER: x+=(width-total_width)*0.5
		elif horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT: x+=width-total_width
		var reading_positions: Dictionary=_reading_positions(row,x,width)
		for part_index in range(row.size()):
			var part: Dictionary=row[part_index]
			x += float(part.gap)
			if show_reading_guides and not part.reading.is_empty():
				guides.append({"from":Vector2(x+2.0,body_y-1.0),"to":Vector2(x+float(part.span)-2.0,body_y-1.0),"group":int(part.group)})
			for index in range(part.reading.size()):
				var text: String = part.reading[index]
				var span: float = kana_face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,ruby_size).x
				var top: float = y+(reading_rows-part.reading.size()+index)*kana_face.get_height(ruby_size)
				var ruby_x: float=float(reading_positions[part_index])+(float(part.reading_span)-span)*.5
				var run: Dictionary = _text_run(kana_face,text,ruby_size,ruby_x,top,"reading")
				run["group"] = int(part.group)
				run["color"] = _group_ink(int(part.group),"reading",annotated_groups)
				runs.append(run)
			for index in range(part.body.size()):
				var text: String = part.body[index]
				var span: float = face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,text_size).x
				var run: Dictionary = _text_run(face,text,text_size,x+(float(part.span)-span)*0.5,body_y+index*face.get_height(text_size),"body")
				run["group"] = int(part.group)
				run["color"] = _group_ink(int(part.group),"body",annotated_groups)
				runs.append(run)
			x += float(part.span)
		y = body_y+body_rows*face.get_height(text_size)+LINE_GAP
	if not lines.is_empty():
		y -= LINE_GAP
	if meaning_visible:
		var meanings: Array[String] = _text_lines(korean_face,str(word.get("ko","")),meaning_size,width)
		if not meanings.is_empty() and not lines.is_empty():
			y += 4.0
		for text in meanings:
			var span: float = korean_face.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,meaning_size).x
			var meaning_x: float=TEXT_PADDING
			if horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER: meaning_x+=(width-span)*.5
			elif horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT: meaning_x+=width-span
			runs.append(_text_run(korean_face,text,meaning_size,meaning_x,y,"meaning"))
			y += korean_face.get_height(meaning_size)
	return {"runs":runs,"guides":guides,"height":y+TEXT_PADDING,"body_size":text_size,"ruby_size":ruby_size,"colouredGroups":annotated_groups.size() if colour_reading_groups and annotated_groups.size()>1 else 0}

func _group_ink(group: int, role: String, annotated_groups: Dictionary) -> Color:
	if colour_reading_groups and annotated_groups.size()>1 and annotated_groups.has(group) and not reading_group_palette.is_empty():
		return reading_group_palette[int(annotated_groups[group]) % reading_group_palette.size()]
	return reading_ink if role=="reading" else ink

func _sync_minimum_height() -> void:
	var desired: float = float(get_text_layout().height)
	if absf(custom_minimum_size.y-desired)>0.1:
		custom_minimum_size.y = desired
	queue_redraw()

func _draw() -> void:
	var face: Font = font if font!=null else ThemeDB.fallback_font
	var layout: Dictionary = get_text_layout()
	for guide in layout.guides:
		draw_line(guide.from,guide.to,Color(reading_ink,0.52),1.0,true)
	for run in layout.runs:
		var run_face: Font = (reading_font if reading_font!=null else face) if run.role=="reading" else (meaning_font if meaning_font!=null else face) if run.role=="meaning" else face
		var color: Color = meaning_ink if run.role=="meaning" else Color(run.color)
		if outline_size>0:
			draw_string_outline(run_face,run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),outline_size,outline_ink)
		draw_string(run_face,run.position,run.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(run.size),color)
