@tool
extends Window

## Modal image gallery viewer - displays images with thumbnails and navigation

signal closed

var _images: Array[Dictionary] = []  # Array of {url: String, texture: Texture2D}
var _current_index: int = 0
var _http_requests: Array[HTTPRequest] = []

# UI Elements
var _main_panel: Panel
var _main_image: TextureRect
var _main_container: Control
var _thumbnails_container: HBoxContainer
var _thumbnails_scroll: ScrollContainer
var _left_btn: Button
var _right_btn: Button
var _close_btn: Button
var _counter_label: Label
var _loading_label: Label


func _init() -> void:
	# Window settings for modal popup
	title = ""
	borderless = true
	unresizable = true
	transient = true
	exclusive = false  # Allow clicking outside
	wrap_controls = true
	# Size will be set when shown
	size = Vector2i(900, 640)


func _ready() -> void:
	_build_ui()
	# Center the window
	if get_parent():
		var parent_size = DisplayServer.window_get_size()
		position = Vector2i((parent_size.x - size.x) / 2, (parent_size.y - size.y) / 2)
	# Handle close request
	close_requested.connect(_on_close_pressed)
	# Close when window loses focus (click outside)
	focus_exited.connect(_on_close_pressed)


func _build_ui() -> void:
	# Main panel with dark background
	_main_panel = Panel.new()
	_main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12)
	panel_style.set_corner_radius_all(0)
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_main_panel)

	# Close button (top-right) with visible background
	_close_btn = Button.new()
	_close_btn.text = "✕  Close"
	_close_btn.add_theme_font_size_override("font_size", 13)
	_close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.position = Vector2(-90, 8)
	_close_btn.custom_minimum_size = Vector2(80, 28)
	_close_btn.pressed.connect(_on_close_pressed)
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# Dark button style
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.2, 0.2, 0.22)
	close_style.set_corner_radius_all(4)
	close_style.content_margin_left = 10
	close_style.content_margin_right = 10
	close_style.content_margin_top = 4
	close_style.content_margin_bottom = 4
	_close_btn.add_theme_stylebox_override("normal", close_style)
	var close_hover = StyleBoxFlat.new()
	close_hover.bg_color = Color(0.35, 0.2, 0.2)
	close_hover.set_corner_radius_all(4)
	close_hover.content_margin_left = 10
	close_hover.content_margin_right = 10
	close_hover.content_margin_top = 4
	close_hover.content_margin_bottom = 4
	_close_btn.add_theme_stylebox_override("hover", close_hover)
	_main_panel.add_child(_close_btn)

	# Counter label (top-center)
	_counter_label = Label.new()
	_counter_label.text = "1 / 1"
	_counter_label.add_theme_font_size_override("font_size", 13)
	_counter_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_counter_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_counter_label.position = Vector2(-20, 12)
	_main_panel.add_child(_counter_label)

	# Main image container
	_main_container = Control.new()
	_main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_container.offset_left = 50
	_main_container.offset_right = -50
	_main_container.offset_top = 40
	_main_container.offset_bottom = -100
	_main_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_main_panel.add_child(_main_container)

	# Main image with rounded corners
	var img_clip = Panel.new()
	img_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	img_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var img_clip_style = StyleBoxFlat.new()
	img_clip_style.bg_color = Color(0.06, 0.06, 0.08)
	img_clip_style.set_corner_radius_all(8)
	img_clip.add_theme_stylebox_override("panel", img_clip_style)
	_main_container.add_child(img_clip)

	_main_image = TextureRect.new()
	_main_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_main_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_main_image.mouse_filter = Control.MOUSE_FILTER_PASS
	img_clip.add_child(_main_image)

	# Loading label
	_loading_label = Label.new()
	_loading_label.text = "Loading..."
	_loading_label.add_theme_font_size_override("font_size", 14)
	_loading_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.position = Vector2(-35, -8)
	_loading_label.visible = false
	_main_container.add_child(_loading_label)

	# Left arrow button
	_left_btn = Button.new()
	_left_btn.text = "◀"
	_left_btn.flat = true
	_left_btn.add_theme_font_size_override("font_size", 24)
	_left_btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	_left_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.95))
	_left_btn.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_left_btn.position = Vector2(10, -20)
	_left_btn.custom_minimum_size = Vector2(40, 40)
	_left_btn.pressed.connect(_on_prev_pressed)
	_left_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_panel.add_child(_left_btn)

	# Right arrow button
	_right_btn = Button.new()
	_right_btn.text = "▶"
	_right_btn.flat = true
	_right_btn.add_theme_font_size_override("font_size", 24)
	_right_btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	_right_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.95))
	_right_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_right_btn.position = Vector2(-50, -20)
	_right_btn.custom_minimum_size = Vector2(40, 40)
	_right_btn.pressed.connect(_on_next_pressed)
	_right_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_panel.add_child(_right_btn)

	# Thumbnails area at bottom
	_thumbnails_scroll = ScrollContainer.new()
	_thumbnails_scroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_thumbnails_scroll.offset_top = -90
	_thumbnails_scroll.offset_bottom = -10
	_thumbnails_scroll.offset_left = 15
	_thumbnails_scroll.offset_right = -15
	_thumbnails_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_thumbnails_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_main_panel.add_child(_thumbnails_scroll)

	# Thumbnails HBox
	_thumbnails_container = HBoxContainer.new()
	_thumbnails_container.add_theme_constant_override("separation", 8)
	_thumbnails_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_thumbnails_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thumbnails_scroll.add_child(_thumbnails_container)


func setup(images: Array, current_index: int = 0) -> void:
	## Setup the gallery with an array of image data
	_images.clear()
	for img in images:
		if img is Dictionary:
			_images.append(img)
		elif img is String:
			_images.append({"url": img, "texture": null})

	_current_index = clamp(current_index, 0, max(0, _images.size() - 1))
	_update_display()
	_create_thumbnails()
	# Show the window
	popup_centered()


func _update_display() -> void:
	if _images.is_empty():
		_main_image.texture = null
		_counter_label.text = "0 / 0"
		_left_btn.visible = false
		_right_btn.visible = false
		return

	_counter_label.text = "%d / %d" % [_current_index + 1, _images.size()]
	_left_btn.visible = _images.size() > 1
	_right_btn.visible = _images.size() > 1
	_left_btn.disabled = _current_index == 0
	_right_btn.disabled = _current_index >= _images.size() - 1

	# Update arrow colors based on disabled state
	_left_btn.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25) if _left_btn.disabled else Color(0.4, 0.4, 0.45))
	_right_btn.add_theme_color_override("font_color", Color(0.2, 0.2, 0.25) if _right_btn.disabled else Color(0.4, 0.4, 0.45))

	var current_data = _images[_current_index]
	if current_data.get("texture"):
		_main_image.texture = current_data.texture
		_loading_label.visible = false
	else:
		_main_image.texture = null
		_loading_label.visible = true
		_load_image(_current_index)

	_update_thumbnail_selection()


func _create_thumbnails() -> void:
	# Clear existing thumbnails
	for child in _thumbnails_container.get_children():
		child.queue_free()

	# Hide thumbnails area if only one image
	_thumbnails_scroll.visible = _images.size() > 1

	if _images.size() <= 1:
		return

	for i in range(_images.size()):
		var thumb_btn = Button.new()
		thumb_btn.custom_minimum_size = Vector2(70, 70)
		thumb_btn.toggle_mode = true
		thumb_btn.button_pressed = (i == _current_index)

		# Style for thumbnail button
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.15, 0.15, 0.18)
		normal_style.set_corner_radius_all(4)
		normal_style.set_border_width_all(2)
		normal_style.border_color = Color(0.2, 0.2, 0.25)
		thumb_btn.add_theme_stylebox_override("normal", normal_style)

		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.18, 0.18, 0.22)
		pressed_style.set_corner_radius_all(4)
		pressed_style.set_border_width_all(2)
		pressed_style.border_color = Color(0.4, 0.6, 1.0)
		thumb_btn.add_theme_stylebox_override("pressed", pressed_style)

		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.17, 0.17, 0.2)
		hover_style.set_corner_radius_all(4)
		hover_style.set_border_width_all(2)
		hover_style.border_color = Color(0.3, 0.3, 0.35)
		thumb_btn.add_theme_stylebox_override("hover", hover_style)

		# Thumbnail image inside button
		var thumb_img = TextureRect.new()
		thumb_img.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb_img.offset_left = 3
		thumb_img.offset_right = -3
		thumb_img.offset_top = 3
		thumb_img.offset_bottom = -3
		thumb_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb_btn.add_child(thumb_img)

		var img_data = _images[i]
		if img_data.get("texture"):
			thumb_img.texture = img_data.texture
		else:
			_load_thumbnail(i, thumb_img)

		var idx = i
		thumb_btn.pressed.connect(func(): _on_thumbnail_pressed(idx))
		_thumbnails_container.add_child(thumb_btn)


func _update_thumbnail_selection() -> void:
	var buttons = _thumbnails_container.get_children()
	for i in range(buttons.size()):
		if buttons[i] is Button:
			buttons[i].button_pressed = (i == _current_index)


func _load_image(index: int) -> void:
	if index < 0 or index >= _images.size():
		return

	var img_data = _images[index]
	var url = img_data.get("url", "")
	if url.is_empty():
		return

	var http = HTTPRequest.new()
	add_child(http)
	_http_requests.append(http)

	var idx = index
	http.request_completed.connect(func(result, code, headers, body):
		_http_requests.erase(http)
		http.queue_free()
		_on_image_loaded(result, code, body, idx)
	)
	http.request(url)


func _load_thumbnail(index: int, thumb_rect: TextureRect) -> void:
	if index < 0 or index >= _images.size():
		return

	var img_data = _images[index]
	var url = img_data.get("thumbnail_url", img_data.get("url", ""))
	if url.is_empty():
		return

	var http = HTTPRequest.new()
	add_child(http)
	_http_requests.append(http)

	http.request_completed.connect(func(result, code, headers, body):
		_http_requests.erase(http)
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var img = Image.new()
			var err = _load_image_from_buffer(img, body)
			if err == OK:
				thumb_rect.texture = ImageTexture.create_from_image(img)
	)
	http.request(url)


func _on_image_loaded(result: int, code: int, body: PackedByteArray, index: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_loading_label.text = "Failed to load"
		return

	var img = Image.new()
	# Try to detect format from header bytes
	var err = _load_image_from_buffer(img, body)

	if err != OK:
		_loading_label.text = "Invalid format"
		return

	var texture = ImageTexture.create_from_image(img)
	_images[index]["texture"] = texture

	if index == _current_index:
		_main_image.texture = texture
		_loading_label.visible = false

	# Update thumbnail if exists
	var buttons = _thumbnails_container.get_children()
	if index < buttons.size() and buttons[index] is Button:
		var thumb_img = buttons[index].get_child(0)
		if thumb_img is TextureRect and not thumb_img.texture:
			thumb_img.texture = texture


func _on_thumbnail_pressed(index: int) -> void:
	_current_index = index
	_update_display()


func _on_prev_pressed() -> void:
	if _current_index > 0:
		_current_index -= 1
		_update_display()


func _on_next_pressed() -> void:
	if _current_index < _images.size() - 1:
		_current_index += 1
		_update_display()


func _on_close_pressed() -> void:
	_cleanup()
	closed.emit()
	hide()
	queue_free()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_close_pressed()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_on_prev_pressed()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_on_next_pressed()
				get_viewport().set_input_as_handled()


func _cleanup() -> void:
	for req in _http_requests:
		if is_instance_valid(req):
			req.cancel_request()
			req.queue_free()
	_http_requests.clear()


func _load_image_from_buffer(img: Image, body: PackedByteArray) -> Error:
	## Try to load image by detecting format from header bytes
	if body.size() < 4:
		return ERR_INVALID_DATA

	# Check magic bytes to detect format
	# PNG: 89 50 4E 47 (‰PNG)
	# JPEG: FF D8 FF
	# WebP: 52 49 46 46 ... 57 45 42 50 (RIFF...WEBP)
	# GIF: 47 49 46 38 (GIF8)

	var is_png = body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47
	var is_jpg = body[0] == 0xFF and body[1] == 0xD8 and body[2] == 0xFF
	var is_webp = body[0] == 0x52 and body[1] == 0x49 and body[2] == 0x46 and body[3] == 0x46
	if is_webp and body.size() >= 12:
		is_webp = body[8] == 0x57 and body[9] == 0x45 and body[10] == 0x42 and body[11] == 0x50

	var err: Error = ERR_FILE_UNRECOGNIZED

	# Try detected format first
	if is_png:
		err = img.load_png_from_buffer(body)
	elif is_jpg:
		err = img.load_jpg_from_buffer(body)
	elif is_webp:
		err = img.load_webp_from_buffer(body)

	# Fallback: try all formats if detection failed
	if err != OK:
		err = img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		err = img.load_webp_from_buffer(body)

	return err
