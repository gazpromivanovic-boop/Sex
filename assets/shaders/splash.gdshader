shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Брызги из-под ног: клок взвеси, который к концу жизни рвётся на отдельные
// капли.
//
// Зачем шейдер, а не картинка. Готовая текстура брызг — это один и тот же
// рисунок на всех частицах: сорок капель под ногами оказываются сорока копиями
// одного пятна, и в кучу они складываются заметным повторяющимся узором.
// Здесь рисунок разный у каждой частицы (сдвиг берётся из её же поворота) и
// вдобавок меняется со временем.
//
// Возраст частицы приходит в INSTANCE_CUSTOM.y — доля прожитой жизни от 0 до 1.
// Это единственный способ узнать в материале, насколько частица стара:
// цветовая рампа даёт только прозрачность, а форму по ней не построить.

// Цвет и общая плотность. Альфа тут — общий множитель поверх рампы частицы.
uniform vec4 tint : source_color = vec4(0.93, 0.97, 1.0, 0.9);
// Кромка ярче тела: в тонком слое воды свет рассеивается сильнее, чем в толще
// капли, и край всегда светлее середины.
uniform float rim_boost : hint_range(0.0, 2.0) = 0.7;
// Насколько клок разрывается на капли к концу жизни. Ноль — так и останется
// сплошным пятном.
uniform float erosion : hint_range(0.0, 1.0) = 0.8;
// Крупность капель: сколько ячеек укладывается поперёк частицы.
uniform float cell_scale : hint_range(1.0, 12.0) = 4.5;
// Вытягивание по вертикали в начале полёта: сорвавшаяся капля летит каплей, а
// не шариком.
uniform float stretch : hint_range(0.0, 1.0) = 0.45;

varying float v_age;
varying float v_seed;

// Ячейки Ворли: расстояние до ближайшей случайной точки. Из него получаются
// круглые капли, а не пятна шума.
float worley(vec2 p) {
	vec2 pi = floor(p);
	vec2 pf = fract(p);
	float best = 1.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = fract(sin(vec2(
				dot(pi + g, vec2(127.1, 311.7)),
				dot(pi + g, vec2(269.5, 183.3)))) * 43758.5);
			best = min(best, length(g + o - pf));
		}
	}
	return best;
}

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	// Поворот частицы служит и зерном: у каждой свой, и рисунок капель не
	// повторяется от частицы к частице.
	v_seed = INSTANCE_CUSTOM.x * 7.13;

	// Разворот к камере. У ShaderMaterial своего billboard нет, в отличие от
	// StandardMaterial3D, поэтому матрицу собираем сами: берём оси камеры и
	// умножаем на длины столбцов MODEL_MATRIX — это и есть масштаб, который
	// частице задал процессорный материал. Без умножения все капли стали бы
	// одного размера.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0]),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1]),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2]),
		MODEL_MATRIX[3]);

	// Свой поворот каждой капли в плоскости экрана.
	float roll = INSTANCE_CUSTOM.x;
	float cs = cos(roll);
	float sn = sin(roll);
	VERTEX.xy = mat2(vec2(cs, -sn), vec2(sn, cs)) * VERTEX.xy;

	// Взлетающая капля вытянута по вертикали, падающая — сплющена. Растягиваем
	// меш, а не текстуру: растянутая текстура размыла бы края капель. После
	// поворота, поэтому вытянутость всегда вертикальна на экране.
	float rise = 1.0 - v_age;
	VERTEX.y *= 1.0 + stretch * (rise - v_age);
	VERTEX.x *= 1.0 - stretch * 0.35 * (rise - v_age);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv) * 2.0;

	// Тело клока: мягкий круг, к краю сходящий на нет.
	float body = 1.0 - smoothstep(0.5, 1.0, d);

	// Разрыв на капли. Порог поднимается с возрастом, поэтому сплошной клок
	// сначала покрывается прожилками, потом распадается на отдельные точки.
	float cells = worley(uv * cell_scale + vec2(v_seed, v_seed * 1.7 + v_age));
	float cut = erosion * v_age;
	float drops = smoothstep(cut, cut + 0.3, 1.0 - cells);
	float mask = body * mix(1.0, drops, v_age);

	// Светлая кромка по краю тела.
	float rim = smoothstep(0.3, 0.75, d) * (1.0 - smoothstep(0.8, 1.0, d));

	ALBEDO = tint.rgb * (1.0 + rim * rim_boost);
	// COLOR несёт рампу частицы: ею задан общий вход и уход, здесь — только
	// форма. Квадрат возраста гасит хвост быстрее линейного, иначе капли долго
	// висят еле заметной дымкой.
	ALPHA = mask * tint.a * COLOR.a * (1.0 - v_age * v_age);
}
