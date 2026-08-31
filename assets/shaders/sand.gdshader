shader_type spatial;

// Песок: рябь, разброс цвета и мокрая полоса у линии воды.
//
// Геометрией песок не сделать — крупные бугры читаются глыбами, а мелкие стоят
// слишком дорого. Поэтому рельеф здесь только в нормали, а меш остаётся почти
// плоским. Всё процедурное: ни текстур, ни развёртки не нужно, и работает на
// любом меше, куда шейдер положат.
//
// Координаты берутся мировые, а не UV: у сборочных мешей развёртки нет, зато
// стыков между кусками песка при мировой привязке не видно вовсе.

group_uniforms color;
uniform vec3 sand_dry : source_color = vec3(0.78, 0.68, 0.50);
uniform vec3 sand_wet : source_color = vec3(0.38, 0.30, 0.22);
uniform float color_variation : hint_range(0.0, 0.5) = 0.12;
uniform float variation_scale : hint_range(0.01, 2.0) = 0.09;

group_uniforms wet;
// Ниже этой высоты песок считается мокрым, выше — сухим.
uniform float water_level = -0.55;
uniform float wet_fade : hint_range(0.01, 4.0) = 0.9;

group_uniforms bands;
// Выше этой высоты песок сменяется камнем, ещё выше — снегом. Пояса нужны
// потому, что одним материалом покрыт весь рельеф: и пляж, и горы.
uniform vec3 rock_color : source_color = vec3(0.35, 0.32, 0.30);
uniform vec3 snow_color : source_color = vec3(0.92, 0.94, 0.97);
uniform float rock_level = 12.0;
uniform float rock_fade = 14.0;
uniform float snow_level = 46.0;
uniform float snow_fade = 22.0;
// На отвесной стене снег не держится — маскируем по крутизне.
uniform float snow_min_flatness : hint_range(0.0, 1.0) = 0.34;

group_uniforms ripples;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;
uniform float ripple_scale : hint_range(0.1, 20.0) = 3.4;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.25;
uniform float grain_scale : hint_range(1.0, 120.0) = 42.0;

varying vec3 world_pos;
varying vec3 world_normal;


float hash(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}


const mat2 OCTAVE_ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = OCTAVE_ROT * p * 2.03;
		amp *= 0.5;
	}
	return sum;
}


// Ветровая рябь: параллельные гребни, изогнутые шумом. Ровные синусоиды читаются
// гофрокартоном, поэтому направление гребня заранее уводится в сторону.
float ripple_height(vec2 p) {
	float warp = fbm(p * 0.35) * 2.4;
	float ridge = sin((p.x * 0.7 + p.y * 0.3) * ripple_scale + warp);
	return ridge * ridge;      // квадрат: гребни узкие, впадины широкие
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec2 p = world_pos.xz;

	// Нормаль складывается из двух масштабов: крупная рябь и мелкое зерно.
	// Считаем численной производной — карт нормалей у нас нет и не нужно.
	float e = 0.06;
	float h = ripple_height(p);
	vec2 d_ripple = vec2(ripple_height(p + vec2(e, 0.0)) - h,
						 ripple_height(p + vec2(0.0, e)) - h) / e;
	float g = value_noise(p * grain_scale);
	vec2 d_grain = vec2(value_noise((p + vec2(e, 0.0)) * grain_scale) - g,
						value_noise((p + vec2(0.0, e)) * grain_scale) - g) / e;

	// Рябь накладывается НА настоящую нормаль поверхности, а не заменяет её.
	// Раньше нормаль строилась как (dx, 1, dz) — то есть считалось, что земля
	// всегда горизонтальна, и на отвесных стенах свет ложился неправильно.
	float flatness = clamp(world_normal.y, 0.0, 1.0);
	vec3 bump = vec3(-(d_ripple.x * ripple_strength * 0.12
					   + d_grain.x * grain_strength * 0.004),
					 0.0,
					 -(d_ripple.y * ripple_strength * 0.12
					   + d_grain.y * grain_strength * 0.004));
	vec3 n = normalize(world_normal + bump * flatness);
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	// мокрый песок ниже уровня воды: темнее и заметно глаже
	float wet = 1.0 - smoothstep(water_level, water_level + wet_fade, world_pos.y);
	vec3 base = mix(sand_dry, sand_wet, wet);

	// пятна светлее и темнее, чтобы поверхность не была залита одним цветом
	float patch = fbm(p * variation_scale) - 0.5;
	base *= 1.0 + patch * color_variation * 2.0;
	// гребни ряби подсвечены, впадины в тени — так рельеф читается и в упор
	base *= mix(0.94, 1.06, h);

	// пояса по высоте: песок -> камень -> снег. Границы размыты шумом, иначе
	// они читаются горизонтальными полосами, как на торте
	float edge = fbm(p * 0.05) * 8.0 - 4.0;
	float rocky = smoothstep(rock_level, rock_level + rock_fade, world_pos.y + edge);
	base = mix(base, rock_color * (0.85 + patch * 0.5), rocky);

	float snowy = smoothstep(snow_level, snow_level + snow_fade, world_pos.y + edge);
	snowy *= smoothstep(snow_min_flatness, snow_min_flatness + 0.3, flatness);
	base = mix(base, snow_color, snowy);

	ALBEDO = base;
	ROUGHNESS = mix(mix(0.95, 0.35, wet), 0.42, max(rocky, snowy * 0.6));
	SPECULAR = mix(0.25, 0.6, max(wet, snowy));
	METALLIC = 0.0;
}
