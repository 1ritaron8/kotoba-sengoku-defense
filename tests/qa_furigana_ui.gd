extends "C:/JP_DF/tests/qa_premium_ui.gd"

const RubyText = preload("res://native/ruby_label.gd")

func check_reading_controls(parent: Node, note: String) -> void:
	for control in parent.find_children("*","Control",true,false):
		if control.get_script()!=RubyText or not control.is_visible_in_tree():
			continue
		var layout: Dictionary = control.get_text_layout()
		var owner: Node = control.get_parent()
		var bounds: Rect2 = Rect2(Vector2.ZERO,control.size)
		for run in layout.runs:
			check(bounds.grow(.1).encloses(run.bounds),note+": ruby glyph fits its control: "+str(control.word.get("jp","")))
			if run.role=="reading":
				check(int(run.size)>=16,note+": visible reading is at least 16px")
		if owner is Button or (owner is Control and owner.clip_contents and not owner is ScrollContainer):
			check(Rect2(Vector2.ZERO,owner.size).grow(.1).encloses(Rect2(control.position,control.size)),note+": allocated reading block fits its clipping parent: "+str(control.word.get("jp","")))

func capture(name: String) -> void:
	check_reading_controls(app,"%s %s" % [name,str(current_dimensions)])
	if name=="battle":
		check(app.learning_panel.get_global_rect().end.y<app.army_toolbar.get_global_rect().position.y,"Enlarged subtitles stay above recruitment")
		check(app.army_panel.get_global_rect().end.y<app.learning_panel.get_global_rect().position.y,"Inspector stays above enlarged subtitles")
		check(app.selected_word.get_rect().end.y<app.selected_label.get_rect().position.y,"Inspector reading does not cover combat statistics")
	if not capture_enabled:
		return
	if current_dimensions!=Vector2i(1280,800) and not (current_dimensions==Vector2i(1440,900) and name in ["battle","support-choice","sentence-choice"]):
		return
	if not name in ["home","barracks","battle","support-choice","support-result","sentence-choice","sentence-result"]:
		return
	await create_timer(.36).timeout
	app.troops_3d._process(0)
	app.game.queue_redraw()
	app.game.actor_overlay.queue_redraw()
	await settle()
	await RenderingServer.frame_post_draw
	var path: String = "C:/JP_DF/dist/furigana-%s-%dx%d.png" % [name,current_dimensions.x,current_dimensions.y]
	check(root.get_texture().get_image().save_png(path)==OK,"GPU reading image saved: "+name)
	images.append(path)
