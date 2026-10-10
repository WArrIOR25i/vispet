extends TextureButton

func _ready():
	
	button_down.connect(on_button_down)
	button_up.connect(on_button_up)
	
	if texture_normal:
		var image = texture_normal.get_image()
		var bitmap = BitMap.new()
		bitmap.create_from_image_alpha(image)
		texture_click_mask = bitmap

func on_button_down():
	get_window().start_drag()
	
func on_button_up():
	pass
