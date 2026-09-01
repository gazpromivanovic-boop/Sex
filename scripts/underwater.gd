class_name Underwater
extends Node
## Красит мир, когда камера уходит под воду.
##
## Изнанку самой поверхности рисует шейдер воды, но этого мало: под водой должно
## меняться всё, что видно вокруг, иначе камера просто оказывается в пустоте —
## тот же берег, то же небо, только сверху плёнка. Дешевле и вернее всего это
## делает туман окружения. Он уже есть, ему достаточно сменить цвет, плотность и
## разрешить красить небо: под водой «неба» нет, есть толща над головой.
##
## Окружение дублируется при запуске. Ресурс default_env.tres общий, и правка
## его свойств в игре — это правка того же объекта, который держит редактор;
## однажды сохранившись, подводные настройки остались бы в файле навсегда.

## Кого спрашивать про уровень воды. Пусто — берём автозагрузку Ocean.
@export_node_path("Node3D") var water_path: NodePath
@export_node_path("WorldEnvironment") var world_environment: NodePath

@export_group("Под водой")
@export var fog_color: Color = Color(0.05, 0.21, 0.27)
@export var fog_density: float = 0.11
## Насколько глубоко под поверхностью эффект набирает полную силу, метры.
@export var fade_depth: float = 0.6
## Скорость перехода. Мгновенный переключатель бьёт по глазам на каждой волне.
@export var blend_speed: float = 7.0

var _env: Environment
var _ocean: Node
var _water: Node3D
var _amount: float = 0.0

# исходные значения, к которым возвращаемся над водой
var _dry_color: Color
var _dry_density: float
var _dry_sky: float
var _dry_scatter: float


func _ready() -> void:
	_ocean = get_node_or_null("/root/Ocean")
	if not water_path.is_empty():
		_water = get_node_or_null(water_path) as Node3D

	var holder := get_node_or_null(world_environment) as WorldEnvironment
	if holder == null or holder.environment == null:
		push_warning("Underwater: не найдено окружение.")
		return
	_env = holder.environment.duplicate()
	holder.environment = _env

	_dry_color = _env.fog_light_color
	_dry_density = _env.fog_density
	_dry_sky = _env.fog_sky_affect
	_dry_scatter = _env.fog_sun_scatter


func _process(delta: float) -> void:
	if _env == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var eye := camera.global_position
	var surface := _level_at(eye.x, eye.z)
	# Не «да/нет», а насколько глубоко: на границе волна ходит вверх-вниз через
	# камеру по нескольку раз в секунду, и переключатель мигал бы.
	var wanted := clampf((surface - eye.y) / maxf(fade_depth, 0.01), 0.0, 1.0)
	_amount = lerpf(_amount, wanted, clampf(1.0 - exp(-blend_speed * delta), 0.0, 1.0))

	_env.fog_light_color = _dry_color.lerp(fog_color, _amount)
	_env.fog_density = lerpf(_dry_density, fog_density, _amount)
	_env.fog_sky_affect = lerpf(_dry_sky, 1.0, _amount)
	_env.fog_sun_scatter = lerpf(_dry_scatter, 0.05, _amount)


func _level_at(x: float, z: float) -> float:
	if _ocean != null:
		return _ocean.get_height(x, z)
	if _water != null:
		return _water.global_position.y
	return -1000.0
