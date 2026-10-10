extends Node2D

# states
enum State { IDLE, WALK, BORED, SLEEP, DRAGGED, FALLING, TYPING }
var current_state: State = State.IDLE

# movement and gravity
@export var move_speed: float = 120.0
var move_direction: int = -1
var accumulated_subpixel_x: float = 0.0

var fall_velocity: float = 0.0
@export var gravity: float = 900.0

# drag
var is_dragging: bool = false
var drag_offset: Vector2i = Vector2i.ZERO
var click_start_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 5.0

# progress bar
@export var progress_bar: ProgressBar
@export var typing_activity_duration: float = 0.6
var typing_decay_timer: float = 0.0

# timers
@onready var state_timer: Timer = Timer.new()
@onready var boredom_timer: Timer = Timer.new()
@onready var speech_timer: Timer = Timer.new()
@onready var pet_sprite: AnimatedSprite2D = $AnimatedSprite2D

# Ui
@onready var pet_button: Control = get_node_or_null("Pet_button")
@onready var speech_bubble: PanelContainer = get_node_or_null("SpeechBubble")
@onready var speech_label: Label = speech_bubble.get_node("MarginContainer/Label") if speech_bubble else null

# Fake Quote System
var http_request: HTTPRequest = HTTPRequest.new()
var mask_cache: Dictionary = {}

var fake_authors: Array[String] = [
	"Albert Einstein",
	"Sun Tzu, The Art of War",
	"Mahatma Gandhi",
	"Batman",
	"Your Local Barista",
	"A Very Smart Pigeon",
	"William Shakespeare",
	"The Wi-Fi Router",
	"Abraham Lincoln (1863)",
	"Isaac Newton"
]

func _ready() -> void:
	var window = get_window()
	window.size = Vector2i(512, 512)
	get_viewport().transparent_bg = true
	window.transparent = true
	window.borderless = true
	window.always_on_top = true
	window.unresizable = false
	
	# Position above taskbar at the far-RIGHT corner
	var usable_rect = DisplayServer.screen_get_usable_rect()
	var target_x = usable_rect.end.x - window.size.x
	var target_y = usable_rect.end.y - window.size.y
	window.position = Vector2i(target_x, target_y)
	
	_setup_progress_bar()
	_precalculate_mouse_masks()
	_setup_timers()
	_setup_http_and_speech()
	_setup_button_signals()
	
	pet_sprite.frame_changed.connect(_apply_cached_mouse_mask)
	Engine.max_fps = 30
	
	change_state(State.IDLE)
	_turn_around(-1)
	reset_boredom_timer()

func _setup_progress_bar() -> void:
	if not progress_bar:
		progress_bar = get_node_or_null("ProgressBar") as ProgressBar
		
	if progress_bar:
		#vertical bar
		progress_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP


func _unhandled_input(event: InputEvent) -> void:
	# Ignore input events while dragging or falling
	if current_state == State.DRAGGED or current_state == State.FALLING:
		return

	# Trigger typing state and add progress 
	if event is InputEventKey and event.pressed and not event.is_echo():
		on_user_activity(5.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on_user_activity(3.0)

func on_user_activity(progress_amount: float) -> void:
	reset_boredom_timer()
	
	# Add progress on every key or click
	if progress_bar:
		if progress_bar.has_method("add_progress"):
			progress_bar.call("add_progress", progress_amount)
		else:
			progress_bar.value = clampf(progress_bar.value + progress_amount, progress_bar.min_value, progress_bar.max_value)
	



func _setup_timers() -> void:
	add_child(state_timer)
	state_timer.one_shot = true
	state_timer.timeout.connect(_on_state_timer_timeout)
	
	add_child(boredom_timer)
	boredom_timer.one_shot = true
	boredom_timer.timeout.connect(_on_boredom_timer_timeout)
	
	add_child(speech_timer)
	speech_timer.one_shot = true
	speech_timer.timeout.connect(_hide_speech_bubble)

func _setup_http_and_speech() -> void:
	add_child(http_request)
	http_request.request_completed.connect(_on_advice_received)
	http_request.set_use_threads(true)
	_hide_speech_bubble()

func _setup_button_signals() -> void:
	if pet_button:
		pet_button.gui_input.connect(_on_pet_button_gui_input)

func _on_pet_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			is_dragging = false
			click_start_pos = DisplayServer.mouse_get_position()
			drag_offset = DisplayServer.mouse_get_position() - get_window().position
		else:
			if is_dragging:
				is_dragging = false
				change_state(State.FALLING)
			else:
				# Clicked on pet - Show Fake Quote Speech Bubble
				reset_boredom_timer()
				change_state(State.IDLE)
				fetch_advice()

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var current_mouse_pos = DisplayServer.mouse_get_position()
		if not is_dragging and click_start_pos.distance_to(current_mouse_pos) > DRAG_THRESHOLD:
			is_dragging = true
			change_state(State.DRAGGED)
		
		if is_dragging:
			get_window().position = Vector2i(current_mouse_pos) - drag_offset

# PROCESS & PHYSICS

func _process(delta: float) -> void:
	match current_state:
		State.WALK:
			_move_window(delta)
		State.FALLING:
			_apply_gravity(delta)
		State.TYPING:
			typing_decay_timer -= delta
			if typing_decay_timer <= 0.0:
				change_state(State.IDLE)

func _apply_gravity(delta: float) -> void:
	var window = get_window()
	var usable_rect = DisplayServer.screen_get_usable_rect()
	var floor_y = usable_rect.end.y - window.size.y
	
	fall_velocity += gravity * delta
	window.position.y += int(fall_velocity * delta)
	
	if window.position.y >= floor_y:
		window.position.y = floor_y
		fall_velocity = 0.0
		change_state(State.IDLE)

func _move_window(delta: float) -> void:
	var window = get_window()
	var usable_rect = DisplayServer.screen_get_usable_rect()
	
	accumulated_subpixel_x += move_direction * move_speed * delta
	var pixel_step = int(accumulated_subpixel_x)
	accumulated_subpixel_x -= pixel_step
	
	window.position.x += pixel_step
	
	if window.position.x + window.size.x >= usable_rect.end.x:
		window.position.x = usable_rect.end.x - window.size.x
		_turn_around(-1)
	elif window.position.x <= usable_rect.position.x:
		window.position.x = usable_rect.position.x
		_turn_around(1)

# FAKE QUOTE API 

func fetch_advice() -> void:
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_request.cancel_request()
		
	_show_speech_bubble("Thinking...")
	
	var headers = ["User-Agent: Mozilla/5.0"]
	var err = http_request.request("https://dummyjson.com/quotes/random", headers)
	
	if err != OK:
		_show_speech_bubble('"Do not trust everything on the internet."\n- Abraham Lincoln')

func _on_advice_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		if parse_result == OK:
			var quote_text = json.data.quote
			var wrong_author = fake_authors.pick_random()
			var troll_quote = '"' + quote_text + '"\n- ' + wrong_author
			_show_speech_bubble(troll_quote)
			return
			
	_show_speech_bubble('"If you drop food, the 5-second rule applies to bacteria too."\n- FDA Guidelines')

func _show_speech_bubble(text: String) -> void:
	if speech_bubble and speech_label:
		speech_label.text = text
		
		speech_bubble.custom_minimum_size = Vector2(120, 0)
		speech_bubble.size.x = 120
		speech_bubble.reset_size()
		
		speech_bubble.position.x = (140 - speech_bubble.size.x) / 2.0
		speech_bubble.position.y = pet_sprite.position.y - speech_bubble.size.y - 10.0
		
		speech_bubble.visible = true
		speech_timer.start(5.0)

func _hide_speech_bubble() -> void:
	if speech_bubble:
		speech_bubble.visible = false
		speech_timer.stop()

# STATE MACHINE & UTILITIES 

func change_state(new_state: State) -> void:
	if new_state != State.IDLE or current_state == State.WALK:
		_hide_speech_bubble()
		
	current_state = new_state
	
	match current_state:
		State.IDLE:
			pet_sprite.play("idle")
			state_timer.start(randf_range(2.0, 5.0))

		State.TYPING:
			state_timer.stop()
			if pet_sprite.sprite_frames.has_animation("typing"):
				pet_sprite.play("typing")
			elif pet_sprite.sprite_frames.has_animation("tap"):
				pet_sprite.play("tap")
			else:
				pet_sprite.play("idle")

		State.WALK:
			pet_sprite.play("walk")
			var window_x = get_window().position.x
			var usable_rect = DisplayServer.screen_get_usable_rect()
			var left_bound = usable_rect.position.x
			var right_bound = usable_rect.end.x - get_window().size.x
			
			if window_x >= right_bound - 10:
				_turn_around(-1)
			elif window_x <= left_bound + 10:
				_turn_around(1)
			else:
				_turn_around([-1, 1].pick_random())
				
			state_timer.start(randf_range(2.0, 6.0))

		State.BORED:
			if pet_sprite.sprite_frames.has_animation("bored"):
				pet_sprite.play("bored")
			else:
				pet_sprite.play("idle")
			state_timer.start(5.0)

		State.SLEEP:
			if pet_sprite.sprite_frames.has_animation("sleep"):
				pet_sprite.play("sleep")
			else:
				pet_sprite.play("idle")

		State.DRAGGED:
			state_timer.stop()
			if pet_sprite.sprite_frames.has_animation("dragged"):
				pet_sprite.play("dragged")
			else:
				pet_sprite.play("idle")

		State.FALLING:
			state_timer.stop()
			fall_velocity = 0.0
			if pet_sprite.sprite_frames.has_animation("falling"):
				pet_sprite.play("falling")
			else:
				pet_sprite.play("idle")
				
	_apply_cached_mouse_mask()

func reset_boredom_timer() -> void:
	boredom_timer.start(12.0)

func _turn_around(new_dir: int) -> void:
	move_direction = new_dir
	pet_sprite.flip_h = (move_direction == 1)
	_apply_cached_mouse_mask()

func _on_state_timer_timeout() -> void:
	match current_state:
		State.IDLE:
			if randf() > 0.4:
				change_state(State.WALK)
			else:
				state_timer.start(randf_range(2.0, 4.0))
		State.WALK:
			change_state(State.IDLE)
		State.BORED:
			change_state(State.SLEEP)

func _on_boredom_timer_timeout() -> void:
	if current_state != State.DRAGGED and current_state != State.FALLING and current_state != State.TYPING:
		change_state(State.BORED)

# MASK CACHING

func _precalculate_mouse_masks() -> void:
	if not pet_sprite.sprite_frames: return
	var anim_names = pet_sprite.sprite_frames.get_animation_names()
	
	for anim in anim_names:
		var frame_count = pet_sprite.sprite_frames.get_frame_count(anim)
		for frame in range(frame_count):
			var texture = pet_sprite.sprite_frames.get_frame_texture(anim, frame)
			if not texture: continue
			
			var base_image = texture.get_image()
			var rect = Rect2(Vector2.ZERO, texture.get_size())
			
			var normal_bitmap = BitMap.new()
			normal_bitmap.create_from_image_alpha(base_image)
			mask_cache[_get_cache_key(anim, frame, false)] = normal_bitmap.opaque_to_polygons(rect, 0.1)
			
			var flipped_image = base_image.duplicate()
			flipped_image.flip_x()
			var flipped_bitmap = BitMap.new()
			flipped_bitmap.create_from_image_alpha(flipped_image)
			mask_cache[_get_cache_key(anim, frame, true)] = flipped_bitmap.opaque_to_polygons(rect, 0.1)

func _get_cache_key(anim_name: String, frame_idx: int, flipped: bool) -> String:
	return anim_name + "_" + str(frame_idx) + "_" + str(flipped)

func _apply_cached_mouse_mask() -> void:
	var cache_key = _get_cache_key(pet_sprite.animation, pet_sprite.frame, pet_sprite.flip_h)
	if mask_cache.has(cache_key):
		DisplayServer.window_set_mouse_passthrough(mask_cache[cache_key])
