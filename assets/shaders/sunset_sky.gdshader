shader_type sky;

// Закатное небо: вертикальный градиент в три цвета, диск солнца с широким
// ореолом и слой облаков, подсвеченных со стороны солнца. Ничего не грузится
// извне — шум считается прямо здесь, поэтому небо весит один файл.
//
// LIGHT0_DIRECTION смотрит НА источник (так же его использует встроенный
// ProceduralSkyMaterial), поэтому dot(EYEDIR, LIGHT0_DIRECTION) равен единице,
// когда смотришь прямо на солнце. Само солнце — это DirectionalLight3D сцены:
// подвинули свет, и небо поехало за ним вместе с тенями.

group_uniforms sky;
// Цвет в зените.
uniform vec3 zenith_color : source_color = vec3(0.055, 0.09, 0.25);
// Цвет в середине купола.
uniform vec3 mid_color : source_color = vec3(0.42, 0.28, 0.42);
// Цвет у горизонта — самая тёплая часть заката.
uniform vec3 horizon_color : source_color = vec3(1.0, 0.46, 0.17);
// Насколько узкой полосой горизонт прижат к линии земли. Больше — уже.
uniform float horizon_falloff : hint_range(1.0, 24.0) = 7.0;
// То же для средней зоны, она размывает переход от зенита к горизонту.
uniform float mid_falloff : hint_range(0.5, 8.0) = 2.0;

group_uniforms sun;
uniform vec3 sun_color : source_color = vec3(1.0, 0.82, 0.58);
// Угловой радиус диска в градусах. У настоящего солнца это 0.27°, но такое
// пятно на закате не читается — берём заметно крупнее.
uniform float sun_angular_size : hint_range(0.1, 15.0) = 2.2;
uniform float sun_energy : hint_range(0.0, 40.0) = 7.0;
uniform vec3 halo_color : source_color = vec3(1.0, 0.42, 0.14);
// Ширина ореола вокруг солнца: больше значение — уже пятно.
uniform float halo_tightness : hint_range(1.0, 200.0) = 22.0;
uniform float halo_energy : hint_range(0.0, 8.0) = 1.6;
// Второй, совсем широкий ореол — он и подкрашивает полнеба в тёплый.
uniform float wash_tightness : hint_range(0.5, 20.0) = 2.5;
uniform float wash_energy : hint_range(0.0, 4.0) = 0.3;

group_uniforms ground;
// Цвет у самой линии горизонта — сюда садится дымка.
uniform vec3 ground_horizon : source_color = vec3(0.30, 0.17, 0.16);
// Цвет вниз, под ноги. Между ними идёт градиент: ровная заливка читается как
// чёрный провал, стоит только посмотреть за край уровня.
uniform vec3 ground_deep : source_color = vec3(0.05, 0.04, 0.06);
// Насколько быстро дымка темнеет ко дну. Меньше — дольше держится светлой.
uniform float ground_falloff : hint_range(0.2, 8.0) = 1.7;
// Насколько мягко небо переходит в землю под линией горизонта.
uniform float ground_blend : hint_range(0.005, 0.5) = 0.12;

group_uniforms clouds;
// 0 — чистое небо, 1 — сплошная облачность.
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_sharpness : hint_range(0.01, 1.0) = 0.45;
uniform float cloud_scale : hint_range(0.1, 8.0) = 1.2;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.008;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.66, 0.38);
uniform vec3 cloud_dark : source_color = vec3(0.16, 0.12, 0.2);


// Хеш без sin. У варианта fract(sin(dot(p, k)) * 43758.5) изо-линии — прямые:
// аргумент синуса линеен по p, и на больших координатах, где float теряет
// точность, это вылезает наружу прямыми полосами. Здесь чистая арифметика
// с fract, распределение ровное и никакой направленности.
float hash(vec2 p) {
	vec3 q = fract(vec3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);   // сглаживание, чтобы не было решётки
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y);
}


// Между октавами координаты не только растягиваются, но и поворачиваются:
// иначе решётки всех октав совпадают по осям и складываются в видимую сетку.
const mat2 OCTAVE_ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += value_noise(p) * amp;
		p = OCTAVE_ROT * p * 2.03;   // не ровно два, иначе октавы липнут друг к другу
		amp *= 0.5;
	}
	return sum;
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, -1.0, 1.0);
	float down_from_zenith = 1.0 - clamp(up, 0.0, 1.0);

	// вертикальный градиент: зенит → середина → горизонт
	vec3 col = mix(zenith_color, mid_color, pow(down_from_zenith, mid_falloff));
	col = mix(col, horizon_color, pow(down_from_zenith, horizon_falloff));

	float sun_dot = 0.0;
	if (LIGHT0_ENABLED) {
		sun_dot = clamp(dot(dir, normalize(LIGHT0_DIRECTION)), 0.0, 1.0);
		// широкий подмес: небо со стороны солнца теплее противоположного края
		col += halo_color * pow(sun_dot, wash_tightness) * wash_energy;
	}

	// Облака лежат на условной плоскости над головой: направление взгляда делится
	// на свою же высоту, как и положено перспективе плоского слоя. Знаменатель
	// только подпирается снизу — у самого горизонта деление уходит в бесконечность.
	// Смягчать его сильнее нельзя: перспектива схлопывается, всё небо умещается
	// в одну-две ячейки шума, и вместо облаков видно их билинейную интерполяцию —
	// огромные четырёхугольники с прямыми изломами по границам ячеек.
	if (cloud_amount > 0.001) {
		float h = max(up, 0.0);
		vec2 uv = dir.xz / max(h, 0.12) * cloud_scale;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);

		// доменное искажение: облака получают рваные края вместо круглых пятен
		vec2 warp = vec2(fbm(uv * 0.55 + 11.3), fbm(uv * 0.55 - 7.1)) - 0.5;
		float n = fbm(uv + warp * 1.7);

		float lo = 1.0 - cloud_amount;
		float cover = smoothstep(lo, lo + cloud_sharpness, n);
		// К горизонту слой истончается и уходит в дымку. Заодно это прячет зону,
		// где знаменатель упёрся в предел, а шум пошёл бы муаром.
		cover *= smoothstep(0.05, 0.35, h);

		// подсветка со стороны солнца плюс объём: плотное ядро светлее краёв
		vec3 cloud = mix(cloud_dark, cloud_lit, pow(sun_dot, 2.5));
		// окно фиксированной ширины: при малой облачности lo подходит к единице,
		// и smoothstep(lo, 1.0, n) выродился бы в неопределённый случай
		cloud *= mix(0.8, 1.2, smoothstep(lo, lo + 0.5, n));
		col = mix(col, cloud, cover);
	}

	if (LIGHT0_ENABLED) {
		// ореол и диск рисуем поверх облаков: солнце просвечивает сквозь них
		col += halo_color * pow(sun_dot, halo_tightness) * halo_energy;
		// порог по косинусу угла: снаружи диска мягкий край, внутри — полная яркость
		float cos_outer = cos(radians(sun_angular_size));
		float cos_inner = cos(radians(sun_angular_size * 0.55));
		float disc = smoothstep(cos_outer, cos_inner, sun_dot);
		col += sun_color * disc * sun_energy * LIGHT0_ENERGY;
	}

	// Земля под горизонтом. Не заливка одним цветом, а дымка: у линии горизонта
	// светлая, ко дну темнеет и со стороны солнца подхватывает тепло. Иначе,
	// стоит посмотреть за край уровня, полкадра занимает чёрная пустота.
	// Порядок краёв в smoothstep важен: при edge0 >= edge1 результат по
	// спецификации не определён и на разных драйверах разный.
	float below = 1.0 - smoothstep(-ground_blend, 0.0, up);
	if (below > 0.001) {
		float depth = pow(clamp(-up, 0.0, 1.0), 1.0 / ground_falloff);
		vec3 gnd = mix(ground_horizon, ground_deep, depth);
		gnd += halo_color * pow(sun_dot, wash_tightness * 1.5)
			* wash_energy * 0.7 * (1.0 - depth);
		col = mix(col, gnd, below);
	}

	COLOR = col;
}
