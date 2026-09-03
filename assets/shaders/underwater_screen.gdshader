shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;

// Мир под водой: экранный слой поверх всего, что нарисовала камера.
//
// Туман окружения красит даль в синий, и на этом всё: цвет есть, среды нет.
// Вода отличается от подкрашенного воздуха четырьмя вещами, и все четыре здесь.
//
//   поглощение — вода съедает красный за считанные метры, зелёный за десяток,
//     синий почти не трогает. Именно поэтому под водой всё синеет с
//     расстоянием, а не просто темнеет. Один множитель на канал даёт это
//     точнее любого подбора цвета;
//   столбы света — солнце низкое, и его лучи в мутной воде видно колоннами;
//   каустики — сетка светлых жил, которую поверхность рисует на дне;
//   рябь — вся картинка чуть гуляет, как сквозь неспокойную воду.
//
// Слой рисуется поверх всего, включая изнанку поверхности. Поэтому пикселям,
// за которыми геометрии нет (небо, та самая изнанка), расстояние назначается
// не бесконечным, а sky_distance: окно Снелла остаётся видно, только
// подкрашенным толщей — как оно и выглядит на самом деле.

// Насколько камера под водой, 0..1. Ведёт скрипт: на границе волна ходит через
// камеру по нескольку раз в секунду, и резкое включение било бы по глазам.
uniform float submerge : hint_range(0.0, 1.0) = 0.0;
// Уровень воды над камерой, мировые координаты.
uniform float water_y = 0.0;
// Куда летят лучи солнца.
uniform vec3 sun_dir = vec3(0.3, -0.8, 0.5);
uniform vec4 sun_color : source_color = vec4(1.0, 0.86, 0.66, 1.0);

group_uniforms Absorption;
// Цвет толщи: к нему сходится всё далёкое.
uniform vec4 deep_color : source_color = vec4(0.04, 0.20, 0.28, 1.0);
// Поглощение по каналам, 1/метр. Красный гаснет первым — это не стилизация, а
// то, как ведёт себя вода.
uniform vec3 absorb = vec3(0.32, 0.09, 0.045);
// Какое расстояние приписать пикселям без геометрии.
uniform float sky_distance : hint_range(2.0, 120.0) = 26.0;
group_uniforms;

group_uniforms Shafts;
uniform float shaft_strength : hint_range(0.0, 2.0) = 0.55;
// Крупность столбов: сколько их укладывается на метр поперёк луча.
uniform float shaft_scale : hint_range(0.01, 0.5) = 0.08;
// На скольких метрах глубины столбы гаснут.
uniform float shaft_depth : hint_range(1.0, 40.0) = 14.0;
group_uniforms;

group_uniforms Caustics;
uniform float caustics_strength : hint_range(0.0, 1.0) = 0.35;
uniform float caustics_scale : hint_range(0.05, 2.0) = 0.55;
uniform float caustics_depth : hint_range(1.0, 30.0) = 9.0;
group_uniforms;

group_uniforms Ripple;
// Насколько гуляет картинка, доли экрана.
uniform float wobble : hint_range(0.0, 0.02) = 0.0035;
uniform float wobble_speed : hint_range(0.0, 3.0) = 1.1;
group_uniforms;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;


float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Каустики: яркие жилы там, где волновые фронты пересекают ноль. Тот же приём,
// что в шейдере воды — рисунок должен читаться одним и тем же сверху и снизу.
float caustic(vec2 p, float time) {
	vec2 warp = vec2(vnoise(p * 0.35 + time * 0.08),
		vnoise(p * 0.35 + time * 0.10 + 5.1)) - 0.5;
	vec2 pd = p + warp * 0.7;
	float w1 = sin(dot(pd, vec2(1.000, 0.000)) * 2.0 + time * 0.60);
	float w2 = sin(dot(pd, vec2(0.500, 0.866)) * 2.2 + time * 0.45);
	float w3 = sin(dot(pd, vec2(-0.500, 0.866)) * 1.8 + time * 0.55);
	float w4 = sin(dot(pd, vec2(0.707, 0.707)) * 2.7 + time * 0.40);
	float ridge = 1.0 - abs((w1 + w2 + w3 + w4) * 0.25);
	return clamp(pow(ridge, 4.0) * 1.4, 0.0, 1.0);
}


void vertex() {
	// Растягиваем квадрат на весь экран прямо в отсечённых координатах: так
	// слой не зависит ни от размера меша, ни от того, куда смотрит камера.
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}


void fragment() {
	// Рябь: смещаем выборку экрана. Две несоизмеримые волны по осям, иначе
	// рисунок читается ровной сеткой.
	vec2 shake = vec2(
		sin(SCREEN_UV.y * 34.0 + TIME * wobble_speed),
		cos(SCREEN_UV.x * 27.0 - TIME * wobble_speed * 0.87)) * wobble * submerge;
	vec2 uv = clamp(SCREEN_UV + shake, vec2(0.001), vec2(0.999));

	vec3 src = texture(screen_texture, uv).rgb;
	float raw = texture(depth_texture, uv).r;
	bool has_scene = raw > 0.0;

	// Восстанавливаем мировую точку пикселя: по ней считаются и расстояние, и
	// глубина под поверхностью, и координаты каустик.
	vec3 ndc = vec3(uv * 2.0 - 1.0, has_scene ? raw : 0.5);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0)).xyz;
	vec3 to_pixel = world - CAMERA_POSITION_WORLD;
	float dist = has_scene ? length(to_pixel) : sky_distance;
	vec3 ray = normalize(to_pixel);

	// Поглощение по каналам. Экспонента, а не линейка: свет гаснет в среде
	// именно так, и на большом расстоянии линейка ушла бы в минус.
	vec3 trans = exp(-absorb * dist);
	vec3 col = mix(deep_color.rgb, src, trans);

	float depth_below = max(0.0, water_y - world.y);
	vec3 sd = normalize(sun_dir);

	// Столбы света. Рисунок берётся в плоскости, перпендикулярной лучу, поэтому
	// полосы идут вдоль солнца, а не поперёк, как вышло бы в мировых xz.
	vec3 helper = abs(sd.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 ax = normalize(cross(sd, helper));
	vec3 ay = cross(sd, ax);
	vec2 sp = vec2(dot(world, ax), dot(world, ay)) * shaft_scale;
	float beams = vnoise(sp + vec2(TIME * 0.03, TIME * 0.02)) * 0.65
		+ vnoise(sp * 2.3 - vec2(TIME * 0.02, 0.0)) * 0.35;
	beams = smoothstep(0.52, 0.86, beams);
	// Видно их против солнца и близко к поверхности.
	beams *= max(0.0, dot(ray, -sd)) * exp(-depth_below / shaft_depth);
	col += sun_color.rgb * beams * shaft_strength;

	// Каустики — только на том, что реально есть: на небе их быть не может.
	if (has_scene && caustics_strength > 0.0) {
		float c = caustic(world.xz * caustics_scale, TIME * 0.5);
		c *= exp(-depth_below / caustics_depth);
		col += sun_color.rgb * c * caustics_strength * trans;
	}

	ALBEDO = col;
	ALPHA = submerge;
}
