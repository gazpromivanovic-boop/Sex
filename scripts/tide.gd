class_name Tide
extends Node3D
## Прилив: медленно поднимает и опускает уровень воды.
##
## Зачем: у шейдера воды и пена, и цвет считаются по глубине, поэтому стоит
## сдвинуть уровень на десяток сантиметров — и линия прибоя уезжает по пологому
## песку на метр-другой. Получается накат, который то ближе, то дальше от берега,
## без единой лишней частицы и без анимации.
##
## Периодов несколько, и они не кратны друг другу: с одним ходом накат стучит
## метрономом, и цикличность бросается в глаза. Три несоизмеримых периода дают
## рисунок, который повторяется настолько редко, что читается живым.

## Насколько уровень гуляет вверх-вниз от исходного, метры.
@export var amplitude: float = 0.38
## Периоды колебаний в секундах. Специально не кратные друг другу.
@export var periods: PackedFloat32Array = PackedFloat32Array([13.0, 7.3, 4.1])
## Веса тех же колебаний: первое главное, остальные подмешиваются.
@export var weights: PackedFloat32Array = PackedFloat32Array([1.0, 0.45, 0.2])

## Дальняя плоскость воды: её надо двигать вместе, иначе на горизонте появится
## ступенька между ближней и дальней водой.
@export_node_path("Node3D") var far_water: NodePath

var _base: float = 0.0
var _far: Node3D
var _far_base: float = 0.0
var _time: float = 0.0

## Текущий уровень воды в мире. Отсюда его читают брызги и всё, кому он нужен.
var level: float = 0.0


func _ready() -> void:
	_base = global_position.y
	level = _base
	if not far_water.is_empty():
		_far = get_node_or_null(far_water) as Node3D
		if _far != null:
			_far_base = _far.global_position.y


func _process(delta: float) -> void:
	_time += delta
	var sum := 0.0
	var norm := 0.0
	for i in periods.size():
		var w: float = weights[i] if i < weights.size() else 1.0
		sum += sin(TAU * _time / maxf(periods[i], 0.01)) * w
		norm += w
	var offset := amplitude * sum / maxf(norm, 0.01)

	level = _base + offset
	global_position.y = level
	if _far != null:
		_far.global_position.y = _far_base + offset
