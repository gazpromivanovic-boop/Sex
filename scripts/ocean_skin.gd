class_name OceanSkin
extends Node
## Меняет вид океана, не трогая его волны.
##
## Отдельным узлом, а не правкой файлов аддона. Ocean3D — сторонний код, и его
## README прямо говорит, что платная версия подменяет те же файлы: любая правка
## внутри addons/ пропадёт при обновлении. Здесь же мы лишь переставляем шейдер
## на материалах, которые OceanSurface собрал у себя в _ready.
##
## Это безопасно ровно потому, что наш шейдер объявляет все uniform'ы Ocean3D с
## теми же именами: таблицу волн, время и storm_scale аддон продолжает слать
## каждый кадр, они попадают куда надо, и картинка остаётся синхронной с физикой.
##
## Заодно выключаем у родителя storm_styling: с ним включённым он каждый кадр
## перезаписывает цвета своими, и подобранная палитра держалась бы ровно до
## первого кадра.
##
## Узел намеренно НЕ @tool. OceanSurface тоже не @tool, в редакторе его _ready не
## выполняется и материалов там не существует вовсе — помеченный @tool скин
## только ругался бы в редакторе на их отсутствие.

## Шейдер, который встаёт вместо родного. Обязателен — без него узел бесполезен.
@export var shader: Shader
## Карта нормалей для ряби. Своей у Ocean3D нет, она нужна только нашему виду.
@export var normal_map: Texture2D

@export_group("Цвет")
@export var shallow_color: Color = Color(0.44, 0.82, 0.86, 0.55)
@export var deep_color: Color = Color(0.10, 0.30, 0.50, 0.93)
@export var shore_glow_color: Color = Color(0.90, 0.98, 1.0, 1.0)
@export var foam_color: Color = Color(0.97, 0.99, 1.0, 1.0)
## Как выглядит поверхность снизу. Без своего цвета изнанка чёрная, и под водой
## пусто.
@export var underwater_color: Color = Color(0.05, 0.24, 0.32, 0.72)

@export_group("Настройка")
## На какой глубине вода показывает полный дальний цвет, метры.
@export var water_depth: float = 4.0
@export var color_bands: int = 4
## Насколько далеко от уреза достаёт пена.
@export var foam_cutoff: float = 0.55
@export var caustics_strength: float = 0.22
@export var sparkle_boost: float = 0.25


func _ready() -> void:
	if shader == null:
		push_warning("OceanSkin: не задан шейдер, вид океана остался родным.")
		return
	# Родитель собирает материалы в своём _ready, а он выполняется после нашего:
	# дети готовы раньше родителей. Обычно хватает одного кадра, но ждём с
	# запасом: одного кадра не хватит, если родитель сам чего-то дожидается.
	for i in 10:
		await get_tree().process_frame
		if apply():
			return
	push_warning("OceanSkin: у родителя так и не появились материалы океана.")


## Возвращает true, если вид применён. Вынесено отдельно, чтобы можно было
## позвать ещё раз после правки цветов.
func apply() -> bool:
	var surface := get_parent()
	if surface == null or shader == null:
		return false

	# Материалы берём прямо, без проверки «есть ли такое свойство»: оператор in
	# на объекте отвечает не про свойства скрипта, и проверка отсекала живой
	# OceanSurface. Пусто — значит родитель ещё не собрался, ждём дальше.
	var mats: Array = []
	for prop in ["material", "far_material"]:
		var mat := surface.get(prop) as ShaderMaterial
		if mat != null:
			mats.append(mat)
	if mats.is_empty():
		return false

	surface.set("storm_styling", false)

	for material in mats:
		var mat := material as ShaderMaterial
		if mat == null:
			continue
		# Значения, которые аддон уже положил (waves, t, storm_scale, disp_*,
		# hole_radius), переживают смену шейдера: они хранятся у материала по
		# имени, а имена мы сохранили.
		mat.shader = shader
		mat.set_shader_parameter("normal_map", normal_map)
		mat.set_shader_parameter("shallow_color", shallow_color)
		mat.set_shader_parameter("deep_color", deep_color)
		mat.set_shader_parameter("shore_glow_color", shore_glow_color)
		mat.set_shader_parameter("foam_color", foam_color)
		mat.set_shader_parameter("underwater_color", underwater_color)
		mat.set_shader_parameter("water_depth", water_depth)
		mat.set_shader_parameter("color_bands", color_bands)
		mat.set_shader_parameter("foam_cutoff", foam_cutoff)
		mat.set_shader_parameter("caustics_strength", caustics_strength)
		mat.set_shader_parameter("sparkle_boost", sparkle_boost)
	return true
