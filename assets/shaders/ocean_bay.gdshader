shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Вода бухты: волны от Ocean3D, вид от EA CoolWater.
//
// Зачем гибрид. Ocean3D даёт то, ради чего он и взят: одна и та же сумма волн
// Герстнера считается в GDScript для физики и здесь для картинки, поэтому тело
// качается ровно на той воде, которую видно. Но фрагментная часть у него
// предельно скупая — два цвета по Френелю, — и море выходило тёмным и никак не
// связанным с берегом: ни отмели, ни пены, ни линии прибоя.
//
// EA CoolWater наоборот: богатая фрагментная часть (глубина по буферу глубины,
// полосы, свечение у берега, пена, преломление, каустики), а волны у него —
// две синусоиды, к физике отношения не имеющие.
//
// Здесь взято по половине от каждого:
//   вершинная часть и все uniform'ы Ocean3D — дословно. Их имена трогать
//     нельзя: OceanSurface кладёт в них таблицу волн и время каждый кадр, и
//     любое несовпадение имени — это ошибка в консоли каждый кадр и разъезд
//     картинки с физикой;
//   фрагментная часть — от EA, с заменой нормали на аналитическую от Герстнера.
//
// Источники: addons/ocean3d_lite (MIT, Justin Schroeder),
// assets/water/EA_CoolWater.gdshader (порт EmacEArt, лицензия в assets/water).

// ---- Ocean3D: эти имена менять нельзя --------------------------------------
// waves[i] = (направление в градусах, крутизна, длина волны в метрах)
uniform vec3 waves[4];
uniform float t = 0.0;
uniform float storm_scale = 1.0;
// Ocean3D шлёт сюда цвета, когда у OceanSurface включён storm_styling. У нас он
// выключен — цвет ведём сами, — но объявить обязаны, иначе при его включении
// посыплются ошибки.
uniform vec4 deep_color : source_color = vec4(0.10, 0.30, 0.50, 0.93);
uniform vec4 shallow_color : source_color = vec4(0.44, 0.82, 0.86, 0.55);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.08;
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;
// Только для вида: смещение гаснет с расстоянием, чтобы край ближней плиты был
// плоским и сходился с плоской юбкой горизонта. Физика не гаснет никогда.
uniform float disp_scale : hint_range(0.0, 1.0) = 1.0;
uniform float disp_fade_start = 90.0;
uniform float disp_fade_end = 126.0;
// Только для юбки горизонта: выкусить круг под камерой, чтобы из-под воды юбка
// не читалась крышкой над головой.
uniform float hole_radius = 0.0;

// ---- Вид ------------------------------------------------------------------
group_uniforms Depth;  // Глубина
// На какой глубине в метрах вода показывает полный дальний цвет.
uniform float water_depth : hint_range(0.1, 20.0) = 4.0;
uniform int color_bands : hint_range(1, 8) = 4;
uniform vec4 shore_glow_color : source_color = vec4(0.90, 0.98, 1.0, 1.0);
uniform float shore_glow_width : hint_range(0.0, 0.75) = 0.16;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.022;
uniform float fresnel_power : hint_range(0.0, 3.0) = 1.0;
group_uniforms;

group_uniforms Foam;  // Пена
uniform vec4 foam_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);
// Насколько далеко от линии прибоя достаёт пена и на скольких метрах по высоте.
uniform float foam_cutoff : hint_range(0.0, 1.0) = 0.55;
uniform float foam_depth : hint_range(0.0, 2.0) = 0.55;
uniform float foam_speed : hint_range(0.0, 0.6) = 0.35;
uniform float foam_tiling : hint_range(0.0, 1.0) = 0.22;
uniform float foam_edge_break : hint_range(0.0, 1.0) = 0.6;
uniform float foam_hardness : hint_range(0.0, 1.0) = 0.75;
// Дрожание самой линии уреза: срез воды по рельефу геометрически ровный, и без
// этого прибой заканчивался бы идеальной дугой.
uniform float shore_edge_break : hint_range(0.0, 0.6) = 0.22;
group_uniforms;

group_uniforms Caustics;  // Каустики и блики
uniform float caustics_strength : hint_range(0.0, 0.5) = 0.22;
uniform float caustics_scale : hint_range(0.0, 0.1) = 0.05;
uniform float caustics_speed : hint_range(0.0, 1.2) = 0.5;
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular_size : hint_range(5.0, 60.0) = 26.0;
uniform float specular_softness : hint_range(0.0, 1.0) = 0.25;
uniform float specular_hardness : hint_range(0.0, 1.0) = 0.8;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float sparkle_boost : hint_range(0.0, 1.0) = 0.25;
uniform float sparkle_density : hint_range(0.0, 1.0) = 0.5;
uniform float sparkle_size : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

group_uniforms Ripple;  // Рябь
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_tiling : hint_range(0.0, 0.15) = 0.06;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.45;
uniform float ripple_speed : hint_range(0.0, 0.2) = 0.05;
group_uniforms;

group_uniforms Underwater;  // Под водой
// Как выглядит поверхность, если смотреть на неё снизу. Без этого изнанка
// поверхности — чёрная плоскость, и под водой пусто.
uniform vec4 underwater_color : source_color = vec4(0.05, 0.24, 0.32, 0.72);
// Окно Снелла: у горизонта изнанка почти зеркало, над головой сквозь неё видно
// небо. Чем больше, тем шире прозрачное пятно над головой.
uniform float snell_window : hint_range(0.05, 1.0) = 0.5;
group_uniforms;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

varying vec3 v_world_pos;
varying vec2 v_world_xz;

const float G = 9.8;


// ---- Волны: дословно из ocean.gd и ocean.gdshader ---------------------------
vec3 gerstner(vec2 xz) {
	vec3 p = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float ang = radians(waves[i].x);
		vec2 dir = vec2(cos(ang), sin(ang));
		float steepness = waves[i].y;
		float k = 6.28318530718 / waves[i].z;
		float c = sqrt(G / k);
		float a = steepness * storm_scale / k;
		float f = k * (dot(dir, xz) - c * t);
		p.x += dir.x * a * cos(f);
		p.y += a * sin(f);
		p.z += dir.y * a * cos(f);
	}
	return p;
}


// ---- Помощники вида: из EA CoolWater ----------------------------------------
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

float worley_min_dist(vec2 p) {
	vec2 pi = floor(p);
	vec2 pf = fract(p);
	float min_d = 1.0;
	for (int wx = -1; wx <= 1; wx++) {
		for (int wy = -1; wy <= 1; wy++) {
			vec2 g = vec2(float(wx), float(wy));
			vec2 o = vec2(
				fract(sin(dot(pi + g, vec2(127.1, 311.7))) * 43758.5),
				fract(sin(dot(pi + g, vec2(269.5, 183.3))) * 12345.6));
			min_d = min(min_d, length(g + o - pf));
		}
	}
	return min_d;
}

// Пена ячейками: светло внутри ячеек, тёмные швы между ними.
float foam_pattern(vec2 p, float time) {
	vec2 d = vec2(time * 0.25, time * 0.18);
	return 1.0 - smoothstep(0.36, 0.42, worley_min_dist(p * 1.2 + d));
}

// Одно место, где каждая маска пены решает, насколько широк её край. Чистый
// step() лесенкой рвал бы линию прибоя, идущую по экрану наискось, поэтому
// ширина пикселя — пол, ниже которого край не сжимается.
float foam_threshold(float v, float center, float soft_width, float px_width) {
	float w = max(mix(soft_width, px_width, foam_hardness), 1e-5);
	return smoothstep(center - w, center + w, v);
}

vec2 distort_uv(vec2 uv, float amount, float time) {
	float a = amount * 0.01;
	float b = amount * 0.12;
	uv.y += a * (sin(uv.x * 3.5 + time * 0.35) + sin(uv.x * 4.8 + time * 1.05)
		+ sin(uv.x * 7.3 + time * 0.45)) / 3.0;
	uv.x += b * (sin(uv.y * 4.0 + time * 0.50) + sin(uv.y * 6.8 + time * 0.75)
		+ sin(uv.y * 11.3 + time * 0.20)) / 3.0;
	return uv;
}

// Каустики: яркие жилы там, где волновые фронты пересекают ноль.
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

float sparkle_points(vec2 p, float time, float density, float size) {
	vec2 pi = floor(p);
	vec2 pf = fract(p);
	float acc = 0.0;
	for (int sx = -1; sx <= 1; sx++) {
		for (int sy = -1; sy <= 1; sy++) {
			vec2 g = vec2(float(sx), float(sy));
			vec2 cell = pi + g;
			float h1 = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5);
			float h2 = fract(sin(dot(cell, vec2(269.5, 183.3))) * 12345.6);
			float h3 = fract(sin(dot(cell, vec2(419.2, 371.9))) * 65537.1);
			if (h3 > density) {
				continue;
			}
			float r = mix(0.05, 0.18, size);
			float point_mask = 1.0 - smoothstep(r * 0.35, r, length(g + vec2(h1, h2) - pf));
			float blink = sin(time * 2.6 + h1 * 31.4 + h2 * 17.7) * 0.5 + 0.5;
			acc = max(acc, point_mask * smoothstep(0.45, 1.0, blink));
		}
	}
	return acc;
}

vec3 reconstruct_world_pos(vec2 suv, float raw_depth, mat4 inv_proj, mat4 inv_view) {
	vec3 ndc = vec3(suv * 2.0 - 1.0, raw_depth);
	vec4 view_pos = inv_proj * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	return (inv_view * vec4(view_pos.xyz, 1.0)).xyz;
}


void vertex() {
	// Плиты едут за камерой: их только двигают, никогда не вращают и не
	// масштабируют. Волны считаются в МИРОВЫХ xz, поэтому меш скользит под
	// неподвижным полем волн и вершины не плавают.
	vec2 xz = VERTEX.xz + MODEL_MATRIX[3].xz;
	v_world_xz = xz;
	float fade = disp_scale
		* (1.0 - smoothstep(disp_fade_start, disp_fade_end,
			distance(xz, CAMERA_POSITION_WORLD.xz)));
	VERTEX += gerstner(xz) * fade;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	if (hole_radius > 0.0
			&& distance(v_world_xz, CAMERA_POSITION_WORLD.xz) < hole_radius) {
		discard;
	}

	// Нормаль аналитическая, по полю волн, и на ОБЕИХ плитах в полную
	// амплитуду — независимо от затухания смещения. Иначе затенение рвётся на
	// плоском ободе ближней плиты. Шаг растёт с расстоянием и срезает детали
	// волн, ушедшие мельче пикселя.
	float e = 0.6 + distance(v_world_xz, CAMERA_POSITION_WORLD.xz) * 0.012;
	vec3 dc = gerstner(v_world_xz);
	vec3 tx = vec3(e, 0.0, 0.0) + gerstner(v_world_xz + vec2(e, 0.0)) - dc;
	vec3 tz = vec3(0.0, 0.0, e) + gerstner(v_world_xz + vec2(0.0, e)) - dc;
	vec3 wave_n = normalize(cross(tz, tx));

	vec3 pos_ws = v_world_pos;
	vec2 scr_uv = SCREEN_UV;
	float nt = TIME * ripple_speed;

	// Рябь поверх формы волны: две карты, ползущие в разные стороны.
	vec2 nm_base = pos_ws.xz * normal_tiling;
	vec3 tn_a = texture(normal_map, nm_base + nt * vec2(0.07, 0.05)).rgb * 2.0 - 1.0;
	vec3 tn_b = texture(normal_map, nm_base * 0.7 + nt * vec2(-0.04, 0.08)).rgb * 2.0 - 1.0;
	vec3 tn = normalize(tn_a + tn_b);
	vec3 ripple_n = normalize(vec3(tn.x, tn.z, tn.y));
	vec3 blend_n = normalize(mix(wave_n, ripple_n, normal_strength * 0.5));

	vec3 view_dir_ws = normalize(CAMERA_POSITION_WORLD - pos_ws);
	float fresnel = pow(1.0 - clamp(dot(blend_n, view_dir_ws), 0.0, 1.0),
		max(0.1, fresnel_power));

	// ---- Изнанка: смотрим на поверхность снизу ------------------------------
	if (!FRONT_FACING) {
		// Окно Снелла: у горизонта изнанка почти зеркало, к зениту сквозь неё
		// видно мир над водой. Без этого под водой сверху чёрная крышка.
		float up = clamp(dot(blend_n, -view_dir_ws), 0.0, 1.0);
		float window = smoothstep(1.0 - snell_window, 1.0, up);
		vec2 ref_uv = clamp(scr_uv + blend_n.xz * refraction_strength * 3.0,
			vec2(0.001), vec2(0.999));
		vec3 through = texture(screen_texture, ref_uv).rgb;
		vec3 col_under = mix(underwater_color.rgb, through, window * 0.85);
		ALBEDO = vec3(0.0);
		EMISSION = col_under;
		ALPHA = mix(underwater_color.a, 0.35, window);
		NORMAL = normalize((VIEW_MATRIX * vec4(-blend_n, 0.0)).xyz);
		ROUGHNESS = roughness_value;
		SPECULAR = specular_value;
		return;
	}

	// ---- Глубина по буферу глубины ------------------------------------------
	float raw_depth = texture(depth_texture, scr_uv).r;
	// Обратная Z: ноль — дальняя плоскость, то есть за водой ничего нет (небо
	// у горизонта). Восстанавливать по такому значению нельзя — точка уезжает
	// на дальнюю плоскость, и её высота случайна: у горизонта вода то
	// выкусывалась дырами, то белела пеной. Считаем такую воду просто глубокой.
	bool has_scene = raw_depth > 0.0;
	vec3 scene_ws = reconstruct_world_pos(scr_uv, raw_depth,
		INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);

	float shore_jitter = (vnoise(pos_ws.xz * 1.8 + TIME * foam_speed * 0.2) - 0.5)
		* shore_edge_break;
	if (has_scene && scene_ws.y > pos_ws.y + 0.05 + shore_jitter) {
		discard;                    // берег выше воды: тут воды нет
	}
	float depth_diff = has_scene ? max(0.0, pos_ws.y - scene_ws.y) : water_depth;
	float depth_t = clamp(depth_diff / max(0.001, water_depth), 0.0, 1.0);

	// ---- Цвет: полосы по глубине и свечение у самого берега ------------------
	float bands = max(1.0, float(color_bands));
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, floor(depth_t * bands) / bands);
	float shore_t = clamp(depth_diff / max(0.001, shore_glow_width * water_depth),
		0.0, 1.0);
	col = mix(shore_glow_color.rgb, col, shore_t);

	// ---- Преломление: на отмели сквозь воду видно дно ------------------------
	vec2 ref_nm_uv = pos_ws.xz * 0.45 + nt * vec2(0.06, 0.04);
	vec3 ref_tn = texture(normal_map, ref_nm_uv).rgb * 2.0 - 1.0;
	vec2 ref_uv = clamp(scr_uv + ref_tn.xy * refraction_strength * 4.0
		* (1.0 - depth_t * 0.3), vec2(0.001), vec2(0.999));
	col = mix(texture(screen_texture, ref_uv).rgb, col,
		clamp(depth_t * 0.9 - 0.1, 0.0, 1.0));

	// ---- Каустики на дне ----------------------------------------------------
	// Считаются в координатах дна, а не поверхности: жилы ползут по рельефу,
	// как настоящий преломлённый свет, а не скользят поверх него.
	if (has_scene && caustics_strength > 0.0) {
		float zone = clamp(1.0 - smoothstep(0.30, 1.00, depth_t), 0.0, 1.0);
		vec2 c_p = scene_ws.xz * mix(0.5, 2.5, caustics_scale);
		float ct = TIME * caustics_speed;
		float c = max(caustic(c_p, ct * 0.55), caustic(c_p * 1.43 + 2.7, ct * 0.43));
		c = floor(c * bands) / bands;
		float mask = smoothstep(0.35, 0.65, vnoise(scene_ws.xz * 0.30 + ct * 0.18));
		vec3 tint = clamp(mix(shallow_color.rgb, shore_glow_color.rgb, 0.7) * 1.55,
			0.0, 1.0);
		vec3 effect = clamp(tint * c * zone * mask * caustics_strength, 0.0, 1.0);
		// Экранное смешение: свет проходит сквозь цвет воды, а не красит поверх.
		col = 1.0 - (1.0 - col) * (1.0 - effect);
	}

	col = mix(col, shore_glow_color.rgb, fresnel * 0.55);
	float alpha = clamp(mix(shallow_color.a, deep_color.a, depth_t) + fresnel * 0.3,
		0.0, 1.0);

	// ---- Пена вдоль линии прибоя --------------------------------------------
	float ft = TIME * foam_speed;
	// Четыре диагональных отсчёта глубины вокруг пикселя: наименьший — самый
	// мелкий, значит берег рядом. Меряем по мировой высоте, а не по глубине от
	// камеры, иначе пена ездит при повороте камеры.
	vec2 ts = 8.0 / VIEWPORT_SIZE;
	float proj_diff = 1e6;
	for (int i = 0; i < 4; i++) {
		vec2 off = vec2(i == 0 || i == 2 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
		vec2 fu = scr_uv + ts * off;
		float fd_raw = texture(depth_texture, fu).r;
		if (fd_raw <= 0.0) {
			continue;               // за водой небо: берега тут нет
		}
		vec3 fw = reconstruct_world_pos(fu, fd_raw, INV_PROJECTION_MATRIX,
			INV_VIEW_MATRIX);
		proj_diff = min(proj_diff, fw.y > pos_ws.y ? 1e6 : pos_ws.y - fw.y);
	}
	float proj_dist = clamp(proj_diff / max(0.001, foam_depth), 0.0, 1.0);

	vec2 foam_uv = distort_uv(pos_ws.xz * mix(0.05, 2.0, foam_tiling), 0.3, ft);
	float foam_samp = foam_pattern(foam_uv, ft);
	// Шум разбивки — на фиксированной частоте, намеренно не связанной с
	// tiling: рисунок пены шириной в метры, и камень полутора метров целиком
	// попал бы в одну ячейку, получив ровную ленту пены по кругу.
	float bt = ft * 0.6;
	float break_n = vnoise(pos_ws.xz * 1.9 + vec2(bt * 0.5, bt * 0.3)) * 0.62
		+ vnoise(pos_ws.xz * 4.6 - vec2(bt * 0.4, bt * 0.6) + 5.3) * 0.38;
	float pd = clamp(proj_dist + (break_n - 0.5) * foam_edge_break * 0.95, 0.0, 1.0);
	float foam_break = smoothstep(0.35, 0.65, break_n);
	float fw_aa = fwidth(pd) + 0.01;
	float pd_px = fwidth(pd) * 0.5;
	float inner = 1.0 - foam_threshold(pd, foam_cutoff * 0.30
		* mix(1.0, 0.35 + foam_break * 1.30, foam_edge_break), fw_aa, pd_px);
	float outer_shape = mix(foam_samp, min(foam_samp, foam_break), foam_edge_break);
	float outer = (1.0 - foam_threshold(pd, foam_cutoff * (0.35 + outer_shape * 1.30),
			fw_aa, pd_px))
		* foam_threshold(outer_shape, 0.425, 0.125, fwidth(outer_shape) * 0.5);
	float foam_mask = max(inner, outer);
	col = mix(col, foam_color.rgb, foam_mask * foam_color.a);
	alpha = max(alpha, foam_mask * foam_color.a);

	// ---- Блики ---------------------------------------------------------------
	if (sparkle_boost > 0.0) {
		float glint = sparkle_points(pos_ws.xz * mix(1.2, 5.5, sparkle_density),
			TIME * (0.4 + ripple_speed * 6.0),
			mix(0.04, 0.45, sparkle_density), sparkle_size);
		glint *= 1.0 - foam_mask;   // пена и так белая
		col = mix(col, specular_color.rgb, glint * sparkle_boost);
		alpha = max(alpha, glint * sparkle_boost * 0.85);
	}

	// Цвет воды собран здесь целиком и несётся свечением, альбедо остаётся
	// чёрным: иначе окружающий свет подкрасит поверхность второй раз.
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ALPHA = alpha;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	// Для бликов в light() нужна частая нормаль: на редкой вся поверхность
	// смотрит почти одинаково, и солнце разливается одним пятном вместо чипов.
	vec3 st_a = texture(normal_map, nm_base * 9.0 + nt * vec2(0.11, 0.07)).rgb * 2.0 - 1.0;
	vec3 st_b = texture(normal_map, nm_base * 6.3 + nt * vec2(-0.06, 0.12)).rgb * 2.0 - 1.0;
	vec3 st = normalize(st_a + st_b);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(st.x, st.z, st.y)), 0.0)).xyz);
}


void light() {
	// Мультяшный блик: размер, мягкость края, добивка до плоского чипа и яркость.
	vec3 half_dir = normalize(VIEW + LIGHT);
	float spec_raw = pow(max(dot(NORMAL, half_dir), 0.0), max(1.0, specular_size));
	float edge = mix(0.004, 0.35, specular_softness);
	float soft = smoothstep(0.5 - edge, 0.5 + edge, spec_raw);
	float hard = smoothstep(0.005, 0.01, soft);
	float mask = mix(soft, hard, specular_hardness);
	SPECULAR_LIGHT += specular_color.rgb * mask * specular_intensity
		* (LIGHT_COLOR / PI) * ATTENUATION;
}
