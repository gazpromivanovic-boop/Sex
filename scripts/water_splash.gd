class_name WaterSplash
extends GPUParticles3D
## Брызги из-под ног, когда идёшь по мелководью.
##
## Узел сам собирает себе материалы и меши: в сцене достаточно положить его под
## персонажа. Настраивать вручную десяток свойств GPUParticles3D не нужно — всё,
## что реально хочется крутить, вынесено сюда.
##
## Эффектов два, и второй не менее важен первого. Брызги без кругов по воде
## читаются висящей в воздухе пылью: глазу не за что зацепиться, чтобы понять,
## что внизу вода. Круги живут на дочернем узле, потому что им нужна своя
## ориентация — они лежат на поверхности плашмя, а брызги развёрнуты к камере.
##
## И те и другие привязаны к поверхности воды, а не к ступням: эмиттер каждый
## кадр переезжает под персонажа на текущий уровень волны. Иначе на глубине
## частицы рождались бы под водой и оттуда не видны.

## За кем следим. Пусто — берём родителя.
@export_node_path("Node3D") var body_path: NodePath
## Запасной узел воды, если нет автозагрузки Ocean. Пусто — берём water_level.
@export_node_path("Node3D") var water_path: NodePath
@export var water_level: float = 0.0

@export_group("Когда брызгать")
## Насколько глубоко ещё считается «по щиколотку». Глубже — плавание, не брызги.
@export var wade_depth: float = 0.9
## Медленнее этой скорости брызг нет: стоящий в воде человек не разбрызгивает.
@export var min_speed: float = 0.8
## На этой скорости брызг максимум.
@export var full_speed: float = 5.0

@export_group("Брызги")
@export var spray_shader: Shader = preload("res://assets/shaders/splash.gdshader")
@export var splash_color: Color = Color(0.93, 0.97, 1.0, 0.9)
## Размер клока взвеси, метры.
@export var splash_size: Vector2 = Vector2(0.07, 0.17)
## С какой скоростью капли срываются вверх.
@export var splash_speed: float = 2.4

@export_group("Круги по воде")
@export var ring_shader: Shader = preload("res://assets/shaders/ripple_ring.gdshader")
@export var ring_color: Color = Color(0.95, 0.99, 1.0, 0.5)
## Поперечник круга в конце расхождения, метры.
@export var ring_size: Vector2 = Vector2(0.9, 1.7)
## Сколько живёт один круг. Дольше брызг: вода успокаивается не сразу.
@export var ring_life: float = 1.3
## Насколько поднять круги над поверхностью, чтобы они не спорили с водой за
## порядок отрисовки. Меньше сантиметра, на глаз незаметно.
@export var ring_lift: float = 0.02

var _body: Node3D
var _water: Node3D
var _ocean: Node                          ## автозагрузка Ocean3D, если она есть
var _rings: GPUParticles3D
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
	amount = 56
	lifetime = 0.75
	explosiveness = 0.0
	randomness = 0.5
	process_material = _make_spray_process()
	draw_pass_1 = _make_spray_mesh()

	_rings = GPUParticles3D.new()
	_rings.name = "Rings"
	_rings.top_level = true
	_rings.emitting = false
	_rings.amount = 12
	_rings.lifetime = ring_life
	_rings.explosiveness = 0.0
	_rings.randomness = 0.4
	_rings.process_material = _make_ring_process()
	_rings.draw_pass_1 = _make_ring_mesh()
	add_child(_rings)

	if _body != null:
		_last_pos = _body.global_position


## Общая часть: обе системы гасят частицу к концу жизни одной и той же рампой.
func _fade_ramp() -> GradientTexture1D:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	return ramp


func _make_spray_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 58.0
	m.initial_velocity_min = splash_speed * 0.45
	m.initial_velocity_max = splash_speed
	m.gravity = Vector3(0, -11.0, 0)      # капли падают обратно в воду
	m.scale_min = splash_size.x
	m.scale_max = splash_size.y
	m.damping_min = 0.4
	m.damping_max = 1.6
	# Свой поворот каждой капле: шейдер берёт его и как разворот на экране, и
	# как зерно для рисунка капель.
	m.angle_min = -180.0
	m.angle_max = 180.0
	# Капли рождаются не в точке, а в пятне под ногами.
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	m.color_ramp = _fade_ramp()
	return m


func _make_spray_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = spray_shader
	mat.set_shader_parameter("tint", splash_color)
	quad.material = mat
	return quad


func _make_ring_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	# Круг не летит и не падает: он стоит на месте, а расходится рисунок внутри
	# квадрата. Так одна частица даёт всю волну целиком.
	m.direction = Vector3(0, 1, 0)
	m.spread = 0.0
	m.initial_velocity_min = 0.0
	m.initial_velocity_max = 0.0
	m.gravity = Vector3.ZERO
	m.scale_min = ring_size.x
	m.scale_max = ring_size.y
	m.angle_min = -180.0
	m.angle_max = 180.0            # зерно для рваности края
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.22
	m.color_ramp = _fade_ramp()
	return m


func _make_ring_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	# Плашмя, а не к камере: круг лежит на воде. Отсюда же и отдельный узел —
	# развернуть половину частиц одной системы иначе нельзя.
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = ring_shader
	mat.set_shader_parameter("tint", ring_color)
	# Поверх воды: обе поверхности прозрачные и глубину не пишут, порядок между
	# ними решается приоритетом.
	mat.render_priority = 1
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
	var active := wading and _speed > min_speed

	emitting = active
	_rings.emitting = active
	if not active:
		return

	global_position = Vector3(pos.x, water_level, pos.z)
	_rings.global_position = Vector3(pos.x, water_level + ring_lift, pos.z)
	var force := clampf((_speed - min_speed) / maxf(full_speed - min_speed, 0.01),
		0.25, 1.0)
	amount_ratio = force
	# Кругов заметно меньше, чем капель: на каждый шаг их нужен один-два, а не
	# горсть. Полная плотность превращает след в сплошную пенную полосу.
	_rings.amount_ratio = clampf(force * 0.6, 0.15, 0.7)
