extends CharacterBody2D

var hunger: int = 100
var happiness: int = 100
var energy: int = 100

#func _physics_process(delta: float) -> void:
	#global_position = lerp(global_position, get_global_mouse_position(), 0.02)
