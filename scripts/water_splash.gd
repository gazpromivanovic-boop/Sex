class_name WaterSplash
extends GPUParticles3D
## Брызги из-под ног, когда идёшь по мелководью.
##
## Узел сам собирает себе материал частиц и меш: в сцене достаточно положить его
## под персонажа и указать уровень воды. Настраивать вручную десяток свойств
## GPUParticles3D не нужно — всё, что реально хочется крутить, вынесено сюда.
##
## Брызги привязаны к поверхности воды, а не к ступням: эмиттер каждый кадр
## переезжает под персонажа на уровень воды. Иначе на глубине частицы рождались
## бы под водой и оттуда не видны.

## За кем следим. Пусто — берём родителя.
@export_node_path("Node3D") var body_path: NodePath
## Узел воды: с него берётся высота поверхности. Если не задан, берётся water_level.
@export_node_path("Node3D") var water_path: NodePath
@export var water_level: float = 0.0

@export_group("Когда брызгать")
## Насколько глубоко ещё считается «по щиколотку». Глубже — плавание, не брызги.
@export var wade_depth: float = 0.9
## Медленнее этой скорости брызг нет: стоящий в воде человек не разбрызгивает.
@export var min_speed: float = 0.8
## На этой скорости брызг максимум.
@export var full_speed: float = 5.0

@export_group("Вид")
@export var splash_color: Color = Color(0.92, 0.97, 1.0, 0.85)
@export var splash_scale: float = 0.10
@export var splash_speed: float = 2.2

var _body: Node3D
var _water: Node3D
var _ocean: Node                          ## автозагрузка Ocean3D, если она есть
var _last_pos: Vector3
var _speed: float = 0.0


func _ready() -> void:
	_body = get_parent() as Node3D
	if not body_path.is_empty():
		var found := get_node_or_null(body_path) as Node3D
		if found != null:
			_body = found
	_ocean = get_node_or_null("/root/Ocean")
	if not water_path.is_empty():
		_water = get_node_or_null(water_path) as Node3D
		if _water != null:
			water_level = _water.global_position.y

	top_level = true          # эмиттер живёт в мире, а не в системе персонажа
	emitting = false
	amount = 48
	lifetime = 0.7
	explosiveness = 0.0
	randomness = 0.4
	if process_material == null:
		process_material = _make_process_material()
	if draw_pass_1 == null:
		draw_pass_1 = _make_mesh()
	if _body != null:
		_last_pos = _body.global_position


func _make_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 55.0
	m.initial_velocity_min = splash_speed * 0.5
	m.initial_velocity_max = splash_speed
	m.gravity = Vector3(0, -9.0, 0)          # капли падают обратно в воду
	m.scale_min = splash_scale * 0.4
	m.scale_max = splash_scale
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.color = splash_color
	# капли рождаются не в точке, а в пятне под ногами
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.28
	return m


func _make_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = splash_color
	mat.disable_receive_shadows = true
	quad.material = mat
	return quad


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	var pos := _body.global_position
	# скорость считаем по смещению, а не по velocity: так узел годится любому
	# телу, а не только CharacterBody3D
	var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	_speed = lerpf(_speed, moved / maxf(delta, 0.0001), clampf(delta * 12.0, 0.0, 1.0))

	# уровень читаем каждый кадр и в той самой точке, где стоит персонаж: вода
	# ходит волной, и запомненный при старте уровень означал бы, что брызги
	# рождаются то под водой, то в воздухе
	if _ocean != null:
		water_level = _ocean.get_height(pos.x, pos.z)
	elif _water != null:
		water_level = _water.global_position.y
	var depth := water_level - pos.y          # больше нуля — ступни под водой
	var wading := depth > -0.05 and depth < wade_depth
	emitting = wading and _speed > min_speed
	if emitting:
		global_position = Vector3(pos.x, water_level, pos.z)
		amount_ratio = clampf((_speed - min_speed) / maxf(full_speed - min_speed, 0.01),
			0.25, 1.0)
