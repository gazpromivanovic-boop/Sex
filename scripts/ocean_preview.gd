@tool
class_name OceanPreview
extends Node
## Показывает воду в 3D-виде редактора.
##
## OceanSurface из аддона — не @tool: в редакторе он не строит ничего, и воду
## видно только в запущенной сцене. Чтобы посмотреть на неё, приходилось каждый
## раз запускать игру.
##
## Узел рисует ту же воду тем же шейдером, но только для глаз и только в
## редакторе: в игре он молча выключается и уступает место настоящему океану.
## Физики за превью нет — за неё отвечает автозагрузка Ocean, а её в редакторе
## тоже не существует, поэтому время здесь идёт своё.
##
## Плита неподвижная и просто большая: гоняться за камерой, как это делает
## OceanSurface, тут незачем — бухта целиком помещается в один квадрат.

## Шейдер воды. Тот же, что подставляет OceanSkin.
@export var shader: Shader
## Профиль волн. Читаем прямо из ресурса: for_shader() лежит на нём, и
## автозагрузка для этого не нужна.
@export var wave_profile: Resource
## Откуда взять цвета. Пусто — ищем соседний OceanSkin, чтобы не заводить второй
## набор тех же настроек и не разъезжаться с игрой.
@export_node_path("Node") var skin_path: NodePath

@export_group("Плита")
@export var size: float = 230.0
@export var subdiv: int = 120
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_inside_tree():
			_rebuild()

const _SKIN_PARAMS := [
	"shallow_color", "deep_color", "shore_glow_color", "foam_color",
	"underwater_color", "water_depth", "color_bands", "foam_cutoff",
	"caustics_strength", "sparkle_boost",
]

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _time: float = 0.0


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _mesh != null:
		_mesh.queue_free()
		_mesh = null
	# В игре превью не нужно и вредно: оно висело бы вторым слоем поверх
	# настоящей воды.
	if not Engine.is_editor_hint() or not enabled or shader == null:
		return

	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("disp_scale", 1.0)
	# Затухание смещения — забота настоящего океана, у которого плита едет за
	# камерой и стыкуется с юбкой горизонта. Здесь стыковать не с чем.
	_material.set_shader_parameter("disp_fade_start", size)
	_material.set_shader_parameter("disp_fade_end", size * 2.0)
	_material.set_shader_parameter("hole_radius", 0.0)
	_apply_skin()

	_mesh = MeshInstance3D.new()
	_mesh.mesh = plane
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.top_level = true          # уровень моря — мировой ноль, как в игре
	# Смещённые вершины уходят за габариты меша, и на скользящем взгляде плита
	# пропадала бы целиком.
	_mesh.custom_aabb = AABB(Vector3(-size * 0.5, -4.0, -size * 0.5),
		Vector3(size, 8.0, size))
	add_child(_mesh)
	_mesh.global_position = Vector3.ZERO


## Цвета берём с соседнего OceanSkin: он не @tool и в редакторе не работает, но
## его exported-значения на узле лежат и читаются. Так настройка одна на игру и
## на превью.
func _apply_skin() -> void:
	var skin: Node = null
	if not skin_path.is_empty():
		skin = get_node_or_null(skin_path)
	if skin == null and get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling.get_script() != null and sibling.get("shallow_color") != null:
				skin = sibling
				break
	if skin == null:
		return
	_material.set_shader_parameter("normal_map", skin.get("normal_map"))
	for param in _SKIN_PARAMS:
		var value = skin.get(param)
		if value != null:
			_material.set_shader_parameter(param, value)


func _process(delta: float) -> void:
	if _material == null or wave_profile == null:
		return
	# Время своё: автозагрузки Ocean в редакторе нет. Волны — чистая функция
	# места и времени, поэтому расхождение с игрой ни на что не влияет.
	_time += delta
	_material.set_shader_parameter("waves", wave_profile.call("for_shader"))
	_material.set_shader_parameter("t", _time)
	_material.set_shader_parameter("storm_scale", 1.0)
