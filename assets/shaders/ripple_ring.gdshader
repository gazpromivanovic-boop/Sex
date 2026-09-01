shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Круги по воде от шага.
//
// Именно они читаются как «идёт по мелководью». Брызги без кругов выглядят
// висящей в воздухе взвесью: глазу не за что зацепиться, чтобы понять, что
// внизу вода, а не пыль.
//
// Кольцо не движется и не растёт мешем — растёт рисунок внутри квадрата. Так
// одна частица даёт всю расходящуюся волну, и не нужно ни анимировать масштаб,
// ни держать десяток частиц на один круг.
//
// Возраст берётся из INSTANCE_CUSTOM.y, доля прожитой жизни от 0 до 1.

uniform vec4 tint : source_color = vec4(0.95, 0.99, 1.0, 0.55);
// Толщина кольца в долях радиуса.
uniform float thickness : hint_range(0.01, 0.4) = 0.09;
// Второй круг позади первого: одиночное кольцо читается ровным обручем, пара
// расходящихся — водой.
uniform float second_ring : hint_range(0.0, 1.0) = 0.55;
// Рваность края: настоящий круг по воде не идеально круглый.
uniform float wobble : hint_range(0.0, 0.3) = 0.07;

varying float v_age;
varying float v_seed;


void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.x * 11.7;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0;
	float angle = atan(uv.y, uv.x);

	// Край кольца гуляет по углу: три несоизмеримые гармоники, чтобы рисунок не
	// читался правильным многоугольником.
	float bump = (sin(angle * 3.0 + v_seed)
		+ sin(angle * 5.0 - v_seed * 1.7) * 0.6
		+ sin(angle * 8.0 + v_seed * 0.4) * 0.3) / 1.9;
	float r = v_age * (1.0 + bump * wobble);

	// Кольцо тоньше по мере расхождения: волна выполаживается.
	float w = max(thickness * (1.0 - v_age * 0.6), 0.004);
	float ring = smoothstep(w, 0.0, abs(d - r));
	// Второе, отстающее и слабее.
	float inner = smoothstep(w * 0.8, 0.0, abs(d - r * 0.52)) * second_ring;

	// За внешним краем квадрата ничего не рисуем: иначе на большом возрасте
	// кольцо упирается в границу и обрывается прямой линией.
	float clip = 1.0 - smoothstep(0.94, 1.0, d);

	ALBEDO = tint.rgb;
	ALPHA = (ring + inner) * clip * tint.a * COLOR.a * (1.0 - v_age);
}
