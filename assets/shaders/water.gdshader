shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// Вода лобби: три бегущие волны в вершинах, цвет по френелю и пена на гребнях.
// Ничего не грузится извне — ни текстур, ни карт нормалей.
//
// Нормаль в пикселе считается аналитически по той же функции, что двигала
// вершины. Брать нормаль из геометрии нельзя: сетка грубая, и блик получился бы
// плоскими многоугольниками вместо ряби.

group_uniforms color;
uniform vec3 deep_color : source_color = vec3(0.015, 0.07, 0.11);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.30, 0.34);
uniform vec3 foam_color : source_color = vec3(0.72, 0.80, 0.84);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;

group_uniforms waves;
uniform float wave_height : hint_range(0.0, 1.0) = 0.13;
uniform float wave_scale : hint_range(0.02, 2.0) = 0.22;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.7;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.35;

group_uniforms surface;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float water_alpha : hint_range(0.0, 1.0) = 0.93;

varying vec3 world_pos;


// Сумма трёх волн, идущих под разными углами: одинаковые направления дают
// стиральную доску, а не воду.
float waves_at(vec2 p, float t) {
	float h = sin(dot(p, vec2(1.0, 0.35)) * wave_scale + t * wave_speed);
	h += 0.7 * sin(dot(p, vec2(-0.45, 1.0)) * wave_scale * 1.7 - t * wave_speed * 1.3);
	h += 0.45 * sin(dot(p, vec2(0.8, -0.7)) * wave_scale * 3.1 + t * wave_speed * 1.9);
	return h * wave_height * 0.45;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves_at(world_pos.xz, TIME);
}


void fragment() {
	// численная производная той же функции: шаг мельче гребня, но крупнее
	// пикселя, иначе на дальней воде идёт рябь-муар
	float e = 0.35;
	float h = waves_at(world_pos.xz, TIME);
	float hx = waves_at(world_pos.xz + vec2(e, 0.0), TIME);
	float hz = waves_at(world_pos.xz + vec2(0.0, e), TIME);
	vec3 n = normalize(vec3(h - hx, e, h - hz));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	vec3 col = mix(deep_color, shallow_color, clamp(fres * 1.4, 0.0, 1.0));

	// пена на гребнях: чем выше волна, тем светлее
	float crest = smoothstep(wave_height * 0.30, wave_height * 0.48, h);
	col = mix(col, foam_color, crest * foam_amount);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = water_roughness;
	SPECULAR = 0.75;
	ALPHA = water_alpha;
}
