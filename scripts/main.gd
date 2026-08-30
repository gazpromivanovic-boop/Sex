extends Node3D
## Логика уровня: страховка от падения за пределы карты и выход по Esc.

@onready var player: CharacterBody3D = $Player

var spawn_transform: Transform3D


func _ready() -> void:
	spawn_transform = player.global_transform


func _physics_process(_delta: float) -> void:
	# если персонаж каким-то образом провалился — возвращаем на старт
	if player.global_position.y < -12.0:
		player.velocity = Vector3.ZERO
		player.global_transform = spawn_transform


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().quit()
