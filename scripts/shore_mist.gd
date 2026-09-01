@tool
class_name ShoreMist
extends GPUParticles3D
## Дымка над полосой прибоя.
##
## Туман окружения даёт глубину всей сцене разом, но у самой воды воздух ведёт
## себя иначе: там висят рваные полосы, они движутся и у них есть край. Ровный
## объёмный туман такого не даёт по построению — он однороден.
##
## Узел собирает себе и материал, и меш: в сцене достаточно положить его вдоль
## берега и задать длину полосы. Настраивать вручную полтора десятка свойств
## GPUParticles3D незачем — наружу вынесено то, что действительно хочется
## крутить.
##
## Пятно — радиальная растяжка, а не картинка: файла в проекте не требуется, а
## мягкий круглый клок именно так и выглядит. Квадрат без неё читался бы
## квадратом.

## Длина полосы вдоль берега и её ширина поперёк, метры.
@export var span: Vector2 = Vector2(120.0, 16.0):
	set(value):
		span = value
		if is_inside_tree():
			_rebuild()
## Насколько высоко клоки поднимаются над узлом, метры.
@export var height: float = 3.0:
	set(value):
		height = value
		if is_inside_tree():
			_rebuild()

@export_group("Вид")
@export var mist_color: Color = Color(0.86, 0.72, 0.66, 0.10):
	set(value):
		mist_color = value
		if is_inside_tree():
			_rebuild()
## Размер одного клока, метры.
@export var puff_size: Vector2 = Vector2(6.0, 14.0):
	set(value):
		puff_size = value
		if is_inside_tree():
			_rebuild()
## Куда сносит ветром, м/с.
@export var drift: Vector3 = Vector3(0.35, 0.05, 0.12):
	set(value):
		drift = value
		if is_inside_tree():
			_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	amount = 44
	lifetime = 18.0
	# Разбрасываем возраст частиц по всему сроку жизни, иначе вся полоса
	# появляется и гаснет разом, как мигалка.
	preprocess = lifetime
	explosiveness = 0.0
	randomness = 0.6
	fixed_fps = 20                     # дымка медленная, чаще считать незачем
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	process_material = _make_process_material()
	draw_pass_1 = _make_mesh()
	# Клоки большие, и их центры могут уехать далеко за исходный объём: без
	# своего AABB узел исчезает целиком, стоит центру выйти из кадра.
	custom_aabb = AABB(Vector3(-span.x * 0.5, -1.0, -span.y * 0.5),
		Vector3(span.x, height + 4.0, span.y))


func _make_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(span.x * 0.5, 0.4, span.y * 0.5)
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = height / lifetime * 0.4
	m.initial_velocity_max = height / lifetime * 1.2
	m.gravity = drift                  # ветер вместо тяжести: дымка не падает
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
	mat.albedo_color = mist_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	# Не писать глубину: клоки насквозь прозрачные и пересекаются друг с другом,
	# запись глубины вырезала бы из соседей дыры по своему квадрату.
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Мягкое смыкание с землёй и с камнями: без этого у каждого клока видна
	# ровная линия среза там, где квадрат входит в поверхность.
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 1.6
	quad.material = mat
	return quad
