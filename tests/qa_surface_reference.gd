extends SceneTree
## Compare atlas reference colours with the decoded asset, not a screen capture.

func _initialize() -> void:
	var atlas = Image.load_from_file("res://assets/materials/sengoku/surface-atlas-v1.png")
	assert(atlas != null and not atlas.is_empty())
	var means: Array = []
	for tile in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
		var total = Vector3.ZERO
		var count = 0
		for y in range(30,atlas.get_height()/2-30,8):
			for x in range(30,atlas.get_width()/2-30,8):
				var pixel: Color = atlas.get_pixel(x+tile.x*atlas.get_width()/2,y+tile.y*atlas.get_height()/2)
				total += Vector3(pixel.r,pixel.g,pixel.b)
				count += 1
		var mean: Vector3 = total/count
		var linear: Color = Color(mean.x,mean.y,mean.z).srgb_to_linear()
		means.append({"tile":[tile.x,tile.y],"srgb":[mean.x,mean.y,mean.z],"linear":[linear.r,linear.g,linear.b]})
	print("ATLAS_COLOUR_REFERENCE ",JSON.stringify(means))
	quit(0)
