extends RapierCharacterBody2D

@export var speed: int = 400

func _physics_process(delta: float) -> void:
	move_and_slide()
	get_input()

func get_input():
	var input_direction = Input.get_vector("left", "right", "up", "down")	
	velocity = input_direction * speed
