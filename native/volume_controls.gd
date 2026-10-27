extends VBoxContainer

signal volume_changed(key: String, value: float)

const GameFonts = preload("res://native/game_fonts.gd")
const UIStyle = preload("res://native/sengoku_ui.gd")
const CHANNELS: Array = [
	{"key":"masterVolume", "label":"전체", "default":1.0},
	{"key":"musicVolume", "label":"배경음악", "default":1.0},
	{"key":"effectsVolume", "label":"효과음", "default":0.8},
	{"key":"voiceVolume", "label":"음성", "default":0.8}
]
var sliders: Dictionary = {}

func configure(settings: Dictionary) -> void:
	name = "VolumeControls"
	add_theme_constant_override("separation",8)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	sliders.clear()
	var heading = UIStyle.TooltipLabel.new()
	heading.name="VolumeHeading"
	heading.text = "音量\n음량"
	heading.add_theme_font_override("font",GameFonts.heading())
	heading.add_theme_font_size_override("font_size",24)
	heading.add_theme_color_override("font_color",Color("f2ead9"))
	add_child(heading)
	for channel in CHANNELS:
		var row = HBoxContainer.new()
		row.name = "VolumeRow_"+str(channel.key)
		row.custom_minimum_size.y = 36
		row.add_theme_constant_override("separation",14)
		add_child(row)
		var label = Label.new()
		label.text = str(channel.label)
		label.custom_minimum_size.x = 100
		label.add_theme_font_override("font",GameFonts.body())
		label.add_theme_font_size_override("font_size",20)
		label.add_theme_color_override("font_color",Color("f2ead9"))
		row.add_child(label)
		var slider = HSlider.new()
		slider.name = "VolumeSlider_"+str(channel.key)
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size.x = 120
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_ALL
		var value: Variant = settings.get(str(channel.key),float(channel.default))
		slider.value = roundf(clampf(float(value),0.0,1.0)*100.0) if (value is int or value is float) and is_finite(float(value)) else float(channel.default)*100.0
		slider.tooltip_text = str(channel.label)+" 음량 · 0%는 음소거"
		row.add_child(slider)
		sliders[str(channel.key)] = slider
		var readout = Label.new()
		readout.name = "VolumePercent_"+str(channel.key)
		readout.text = "%d%%" % int(slider.value)
		readout.custom_minimum_size.x = 56
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.add_theme_font_override("font",GameFonts.body())
		readout.add_theme_font_size_override("font_size",20)
		readout.add_theme_color_override("font_color",Color("e8d4a9"))
		row.add_child(readout)
		slider.value_changed.connect(_on_value_changed.bind(str(channel.key),readout))

func _on_value_changed(value: float, key: String, readout: Label) -> void:
	readout.text = "%d%%" % int(value)
	volume_changed.emit(key,value/100.0)
