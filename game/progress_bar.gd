extends ProgressBar

signal filled

@export var step_amount: float = 10.0
@export var fill_speed: float = 0.1
@export var particles: GPUParticles2D

var _target_value := 0.0

func _ready() -> void:
	_target_value = value
	fill_mode = FillMode.FILL_BOTTOM_TO_TOP

func _process(delta: float) -> void:
	if not is_equal_approx(value, _target_value):
		# interpol
		value = move_toward(value, _target_value, fill_speed * delta * (max_value - min_value))

func add_progress(amount: float) -> bool:
	if amount <= 0.0:
		return false
		
	# particle fx
	if particles:
		particles.restart()
		particles.emitting = true

	#check for max
	if _target_value + amount >= max_value:
		# calc for remaining fill 
		var leftover = (_target_value + amount) - max_value
		
		# roll over
		_target_value = min_value + leftover
		value = min_value
		filled.emit()
	else:
		_target_value += amount
		
	return true
