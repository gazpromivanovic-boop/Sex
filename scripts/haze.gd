@tool
class_name Haze
extends Node3D
## Взвесь в воздухе или в воде: дымка над прибоем, муть в толще воды.
##
## Одно и то же по существу, поэтому один узел: полупрозрачные клоки, медленно
## сносимые в заданную сторону, разбросанные по коробке. Разница между дымкой и
## подводной взвесью — только в размере клока, их числе и цвете.
##
## Туман окружения даёт глубину всей сцене разом, но у самой воды воздух ведёт
## себя иначе: там висят рваные полосы, они движутся и у них есть край. Ровный
## объёмный туман такого не даёт по построению — он однороден.
##
## Частицы живут на ДОЧЕРНЕМ узле, а не на самом Haze, и это не прихоть. Узел
## помечен @tool, чтобы взвесь была видна прямо в редакторе и ради неё не
## приходилось запускать игру. Но process_material и draw_pass_1 — свойства
## самого узла, и собранные в редакторе они уехали бы прямо в файл сцены при
## сохранении, застыв там навсегда. Дочерний узел добавляется без owner, в файл
## сцены не попадает, и сохранять там нечего.
##
## Пятно — радиальная растяжка, а не картинка: файла в проекте не требуется, а
## мягкий круглый клок именно так и выглядит. Квадрат без неё читался бы
## квадратом.

## Длина полосы вдоль берега и её ширина поперёк, метры.
@export var span: Vector2 = Vector2(120.0, 16.0):
	set(value):
		span = value
		_rebuild()
## Сколько клоков держать. Под водой их нужно заметно больше, чем над прибоем:
## взвесь читается количеством, а дымка — размером.
@export var count: int = 44:
	set(value):
		count = value
		_rebuild()
## Сколько живёт один клок, секунд.
@export var life: float = 18.0:
	set(value):
		life = value
		_rebuild()
## Насколько высоко клоки поднимаются над узлом, метры.
@export var height: float = 3.0:
	set(value):
		height = value
		_rebuild()

@export_group("Вид")
## Цвет и плотность. Альфа тут — единственное место, где она задаётся: в
## материале альбедо остаётся белым. Поставить её в обоих местах — значит
## перемножить: при 0.09 на 0.09 от дымки остаётся 0.008, то есть ничего.
@export var mist_color: Color = Color(0.86, 0.72, 0.66, 0.16):
	set(value):
		mist_color = value
		_rebuild()
## Размер одного клока, метры.
@export var puff_size: Vector2 = Vector2(4.0, 9.0):
	set(value):
		puff_size = value
		_rebuild()
## Куда сносит течением или ветром, м/с.
@export var drift: Vector3 = Vector3(0.35, 0.05, 0.12):
	set(value):
		drift = value
		_rebuild()

var _particles: GPUParticles3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _particles != null:
		_particles.queue_free()
	_particles = GPUParticles3D.new()
	_particles.amount = maxi(1, count)
	_particles.lifetime = maxf(0.1, life)
	# Разбрасываем возраст клоков по всему сроку жизни, иначе вся полоса
	# появляется и гаснет разом, как мигалка.
	_particles.preprocess = _particles.lifetime
	_particles.explosiveness = 0.0
	_particles.randomness = 0.6
	_particles.fixed_fps = 20          # взвесь медленная, чаще считать незачем
	_particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_particles.process_material = _make_process_material()
	_particles.draw_pass_1 = _make_mesh()
	# Клоки большие, и их центры уезжают далеко за исходный объём: без своего
	# AABB узел исчезает целиком, стоит центру выйти из кадра.
	_particles.custom_aabb = AABB(
		Vector3(-span.x * 0.5 - puff_size.y, -puff_size.y, -span.y * 0.5 - puff_size.y),
		Vector3(span.x + puff_size.y * 2.0, height + puff_size.y * 2.0,
			span.y + puff_size.y * 2.0))
	add_child(_particles)


func _make_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(span.x * 0.5, 0.4, span.y * 0.5)
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = height / maxf(life, 0.1) * 0.4
	m.initial_velocity_max = height / maxf(life, 0.1) * 1.2
	m.gravity = drift                  # снос вместо тяжести: взвесь не падает
	m.scale_min = puff_size.x
	m.scale_max = puff_size.y
	m.damping_min = 0.0
	m.damping_max = 0.05
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -3.0
	m.angular_velocity_max = 3.0

	# Клок проявляется и тает, а не возникает и пропадает.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	fade.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	m.color_ramp = ramp
	m.color = mist_color
	return m


func _make_mesh() -> Mesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	var soft := Gradient.new()
	soft.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	soft.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var blob := GradientTexture2D.new()
	blob.gradient = soft
	blob.fill = GradientTexture2D.FILL_RADIAL
	blob.fill_from = Vector2(0.5, 0.5)
	blob.fill_to = Vector2(1.0, 0.5)
	blob.width = 128
	blob.height = 128

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = blob
	# Белое, а не mist_color: цвет и плотность несёт частица, и умножить их ещё
	# раз здесь значило бы возвести альфу в квадрат.
	mat.albedo_color = Color.WHITE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	# Не писать глубину: клоки насквозь прозрачные и пересекаются друг с другом,
	# запись глубины вырезала бы из соседей дыры по своему квадрату.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Мягкое смыкание с землёй и с камнями: без этого у каждого клока видна
	# ровная линия среза там, где квадрат входит в поверхность.
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.6
	quad.material = mat
	return quad
