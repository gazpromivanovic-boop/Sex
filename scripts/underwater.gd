class_name Underwater
extends Node
## Делает мир под водой водой, а не подкрашенным воздухом.
##
## Работает в два слоя, и они делят обязанности, а не дублируют друг друга.
##
## Туман окружения отвечает за объём: он живёт в трёхмерной сетке, знает про
## источники света и потому даёт настоящие лучи от солнца и мягкое затухание
## далёкой геометрии. Экранным шейдером такого не сделать.
##
## Экранный слой отвечает за среду: поглощение цвета толщей по каналам, каустики
## на дне, рябь всей картинки. Туману это недоступно — он умеет только один цвет
## на всю дальность.
##
## Оба ведутся одной величиной: насколько камера погружена. Не «да/нет», потому
## что на границе волна ходит через камеру по нескольку раз в секунду, и
## переключатель мигал бы.
##
## Окружение дублируется при запуске: ресурс default_env.tres общий с
## редактором, и правка его свойств в игре — это правка того же объекта, который
## держит редактор. Однажды сохранившись, подводные настройки остались бы в
## файле навсегда.

## Кого спрашивать про уровень воды. Пусто — берём автозагрузку Ocean.
@export_node_path("Node3D") var water_path: NodePath
@export_node_path("WorldEnvironment") var world_environment: NodePath
## Солнце: с него берутся направление и цвет лучей. Пусто — ищем сами.
@export_node_path("DirectionalLight3D") var sun_path: NodePath

@export_group("Туман")
@export var fog_color: Color = Color(0.05, 0.21, 0.27)
## Плотность обычного тумана под водой. Небольшая: цвет толщи ведёт экранный
## слой, он делает это точнее — по каналам, а не одним оттенком.
@export var fog_density: float = 0.05
## Плотность объёмного тумана. Он и даёт настоящие лучи: солнце низкое, и в
## плотной среде его свет становится видимым столбами.
@export var volume_density: float = 0.04
@export var volume_albedo: Color = Color(0.32, 0.62, 0.66)

@export_group("Экранный слой")
@export var screen_shader: Shader = preload("res://assets/shaders/underwater_screen.gdshader")
## Цвет толщи: к нему сходится всё далёкое.
@export var deep_color: Color = Color(0.04, 0.20, 0.28)
## Поглощение по каналам, 1/метр. Красный гаснет первым — так ведёт себя вода.
@export var absorb: Vector3 = Vector3(0.32, 0.09, 0.045)
@export var shaft_strength: float = 0.55
@export var caustics_strength: float = 0.35
@export var wobble: float = 0.0035

@export_group("Переход")
## Насколько глубоко под поверхностью эффект набирает полную силу, метры.
@export var fade_depth: float = 0.6
## Скорость перехода.
@export var blend_speed: float = 7.0

var _env: Environment
var _ocean: Node
var _water: Node3D
var _sun: DirectionalLight3D
var _overlay: MeshInstance3D
var _screen: ShaderMaterial
var _amount: float = 0.0

# исходные значения, к которым возвращаемся над водой
var _dry_color: Color
var _dry_density: float
var _dry_sky: float
var _dry_scatter: float
var _dry_volume: float
var _dry_volume_albedo: Color


func _ready() -> void:
	_ocean = get_node_or_null("/root/Ocean")
	if not water_path.is_empty():
		_water = get_node_or_null(water_path) as Node3D
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if _sun == null:
		_sun = _find_sun(get_tree().current_scene)

	var holder := get_node_or_null(world_environment) as WorldEnvironment
	if holder != null and holder.environment != null:
		_env = holder.environment.duplicate()
		holder.environment = _env
		_dry_color = _env.fog_light_color
		_dry_density = _env.fog_density
		_dry_sky = _env.fog_sky_affect
		_dry_scatter = _env.fog_sun_scatter
		_dry_volume = _env.volumetric_fog_density
		_dry_volume_albedo = _env.volumetric_fog_albedo
	else:
		push_warning("Underwater: не найдено окружение, туман останется прежним.")

	_build_overlay()


func _build_overlay() -> void:
	if screen_shader == null:
		return
	_screen = ShaderMaterial.new()
	_screen.shader = screen_shader
	_screen.set_shader_parameter("deep_color", deep_color)
	_screen.set_shader_parameter("absorb", absorb)
	_screen.set_shader_parameter("shaft_strength", shaft_strength)
	_screen.set_shader_parameter("caustics_strength", caustics_strength)
	_screen.set_shader_parameter("wobble", wobble)
	_screen.set_shader_parameter("submerge", 0.0)
	# Рисуется последним, поверх всей прозрачной геометрии: вода — это среда
	# между глазом и миром, а не предмет в мире.
	_screen.render_priority = 120

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _screen

	_overlay = MeshInstance3D.new()
	_overlay.name = "Screen"
	_overlay.mesh = quad
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.visible = false
	# Шейдер растягивает квадрат на весь экран прямо в отсечённых координатах,
	# поэтому где узел стоит — неважно. А вот отсечь по видимости его могут:
	# габариты у него метровые. Огромный запас снимает вопрос.
	_overlay.extra_cull_margin = 16384.0
	add_child(_overlay)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var eye := camera.global_position
	var surface := _level_at(eye.x, eye.z)
	var wanted := clampf((surface - eye.y) / maxf(fade_depth, 0.01), 0.0, 1.0)
	_amount = lerpf(_amount, wanted, clampf(1.0 - exp(-blend_speed * delta), 0.0, 1.0))

	if _env != null:
		_env.fog_light_color = _dry_color.lerp(fog_color, _amount)
		_env.fog_density = lerpf(_dry_density, fog_density, _amount)
		_env.fog_sky_affect = lerpf(_dry_sky, 1.0, _amount)
		_env.fog_sun_scatter = lerpf(_dry_scatter, 0.05, _amount)
		_env.volumetric_fog_density = lerpf(_dry_volume, volume_density, _amount)
		_env.volumetric_fog_albedo = _dry_volume_albedo.lerp(volume_albedo, _amount)

	if _overlay == null:
		return
	# Над водой слой не рисуем вовсе: это полноэкранный проход с шумом, и
	# гонять его ради нулевой прозрачности незачем.
	_overlay.visible = _amount > 0.002
	if not _overlay.visible:
		return
	_screen.set_shader_parameter("submerge", _amount)
	_screen.set_shader_parameter("water_y", surface)
	if _sun != null:
		# Направление луча — куда светит солнце, то есть -Z его собственных осей.
		_screen.set_shader_parameter("sun_dir", -_sun.global_transform.basis.z)
		_screen.set_shader_parameter("sun_color", _sun.light_color)


func _level_at(x: float, z: float) -> float:
	if _ocean != null:
		return _ocean.get_height(x, z)
	if _water != null:
		return _water.global_position.y
	return -1000.0


func _find_sun(node: Node) -> DirectionalLight3D:
	if node == null:
		return null
	for child in node.get_children():
		if child is DirectionalLight3D:
			return child
		var found := _find_sun(child)
		if found != null:
			return found
	return null
