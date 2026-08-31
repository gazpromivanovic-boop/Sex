"""Собирает геометрию лобби и кладёт её в assets/models/lobby.glb.

    blender --background --factory-startup --python tools/build_lobby.py

Лобби — это берег с домом и пирсом, у которого стоит батискаф. Место, где
собираются перед погружением: осмотрелись, подошли к аппарату, ушли вниз.

Имена объектов заканчиваются на «-col»: по этому суффиксу импортёр Godot сам
делает статическое тело с коллизией по мешу. Руками расставлять коллизии по
дому и пирсу не придётся, а если что-то менять — меняется в одном месте, здесь.

Разметка (координаты Godot: Y вверх, −Z вперёд):
    берег занимает z от +6 и дальше, вода начинается на z = +6;
    пирс уходит от берега в −Z до z = −20;
    дом — готовая модель house.glb, её ставит сцена;
    батискаф швартуется справа от пирса — его ставит уже сцена, не этот скрипт.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_kit import (material, glass_material, rename, smooth, bevel,
                         boolean, cylinder, box, ball, wedge, join,
                         export_glb, render_previews)

# ─────────────────────────────────────────────────────────────── размеры
# Ось Z вертикальная (Blender), Y — «вглубь» сцены. Экспортёр развернёт в Y-up,
# и Y Blender'а станет −Z Godot'а: то есть +Y здесь = «от воды к берегу».

P = {
    "water_z": -0.55,            # уровень воды
    "shore_y": 6.0,              # где кончается вода и начинается берег
    "terrain_step": 1.8,         # шаг сетки рельефа, м
    "beach_x": 58.0,             # докуда пляж по бортам
    "beach_back": 46.0,          # и вглубь суши
    "arch_x": 15.0,              # где в скалах проход
    "arch_w": 7.0,
    "arch_depth": 15.0,          # насколько арка утоплена вглубь прохода
    "cliff_h": 58.0,             # высота гор вокруг бухты
    "dune_rise": 1.7,            # насколько поднимается суша к дюнам
    "depth": 9.0,                # глубина вдали от берега
    # ровные площадки: пирс и дом не должны стоять на буграх (x, y, радиус)
    "pads": [(-9.5, 11.0, 6.0), (-5.8, 8.4, 2.0)],

    "pier_len": 26.0,            # от берега в сторону воды
    "pier_width": 5.0,
    "pier_z": 0.55,              # высота настила над нулём
    "plank": 0.28,
    "piling_r": 0.22,

    "house_w": 9.0,
    "house_d": 7.5,
    "house_h": 3.6,
    "roof_h": 3.0,          # круче скат: пологая крыша читается плоской плитой
    "wall": 0.28,                # толщина стены
    "door_w": 1.5,
    "door_h": 2.3,
    "house_x": -9.5,
    "house_y": 15.0,
}

OUT_GLB = "assets/models/lobby.glb"
OUT_RENDER = "tools/preview"


# ─────────────────────────────────────────────────────────────── берег


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / max(1e-6, b - a)))
    return t * t * (3.0 - 2.0 * t)


def shore_line(x):
    """Где проходит линия воды на данной поперечине.

    Прямой берег — главная причина, по которой пена выстраивалась ровной
    цепочкой: у прямой кромки одинаковая глубина по всей длине, и шейдер
    рисует одинаковую полосу. Кривая линия ломает и глубину, и пену.
    """
    from mathutils import noise as bnoise
    from mathutils import Vector
    wander = bnoise.noise(Vector((x * 0.022, 0.0, 5.0))) * 7.0
    wander += bnoise.noise(Vector((x * 0.075, 0.0, 9.0))) * 2.4
    return P["shore_y"] + wander


def terrain_height(x, y):
    """Высота песка в точке. Одна функция и для меша, и для расстановки того,
    что на песке стоит: камни и коряги садятся ровно на поверхность.

    Профиль пляжный: у самой воды почти плоско, потом полоса сухого песка, и
    только дальше от воды поднимаются дюны. Гасить рельеф вдоль пирса, как я
    делал сначала, нельзя — дюны вокруг встают стеной, и пирс оказывается в
    траншее. Плоско у воды получается само, если так задать профиль.
    """
    from mathutils import noise as bnoise
    from mathutils import Vector

    t = y - shore_line(x)                     # >0 — суша, <0 — вода
    if t >= 0.0:
        # берм: пологий подъём, дюны подключаются только дальше от воды
        base = 0.8 * (1.0 - math.exp(-t / 26.0))
        base += P["dune_rise"] * smoothstep(12.0, 46.0, t)
    else:
        # дно: степень меньше единицы дала бы обрыв у берега, больше — блюдце
        base = -P["depth"] * pow(min(1.0, -t / 50.0), 1.6)

    # Скалы — часть рельефа, а не отдельные глыбы. Расставленные шарами они
    # читались галькой, между ними зияли щели, и пляж всё равно обрывался.
    # Поднятая стеной земля не имеет ни швов, ни дыр по построению.
    # Граница бухты извилистая. Прямая давала правильный прямоугольник со
    # скруглёнными углами — сверху это читалось ванной, а не берегом.
    side = P["beach_x"] + bnoise.noise(Vector((0.0, y * 0.028, 3.0))) * 11.0
    back = P["beach_back"] + bnoise.noise(Vector((x * 0.026, 0.0, 7.0))) * 13.0
    out = max(abs(x) - side, y - back)
    if out > -1.0:
        wall = P["cliff_h"] * smoothstep(-1.0, 34.0, out)
        # проход под арку: узкая щель в задней стене
        if y > back - 6.0:
            # щель ровно под арку: шире — и она повисает в чистом поле
            # щель шире проёма арки: иначе за аркой видно узкую прорезь
            gap = smoothstep(P["arch_w"] * 0.78, P["arch_w"] * 1.25,
                             abs(x - P["arch_x"]))
            wall *= gap
        base += wall

    dune = smoothstep(10.0, 34.0, t)          # крупный шум только в дюнах
    h = bnoise.noise(Vector((x * 0.032, y * 0.032, 0.0))) * 1.5 * dune
    h += bnoise.noise(Vector((x * 0.11, y * 0.11, 11.0))) * 0.30 * (0.2 + 0.8 * dune)
    h += bnoise.noise(Vector((x * 0.40, y * 0.40, 23.0))) * 0.07
    # на скалах шум крупнее и жёстче: у камня рельеф не такой, как у песка
    rocky = smoothstep(-2.0, 20.0, out)
    if rocky > 0.0:
        h += bnoise.noise(Vector((x * 0.014, y * 0.014, 41.0))) * 22.0 * rocky
        h += bnoise.noise(Vector((x * 0.041, y * 0.041, 57.0))) * 9.0 * rocky
        h += bnoise.noise(Vector((x * 0.11, y * 0.11, 73.0))) * 3.2 * rocky
        h += bnoise.noise(Vector((x * 0.28, y * 0.28, 89.0))) * 1.1 * rocky

    # площадки под постройками: дом на сваях, но стулья стоят прямо на песке
    flat = 1.0
    for px, py, pr in P["pads"]:
        d = math.hypot(x - px, y - py)
        flat = min(flat, smoothstep(pr, pr + 5.0, d))
    return base + h * flat


def build_terrain(mats):
    """Берег и дно одним мешем: раздельные плиты давали ступеньку на линии воды."""
    x0, x1, y0, y1 = -120.0, 120.0, -110.0, 112.0
    step = P["terrain_step"]
    nx = int((x1 - x0) / step) + 1
    ny = int((y1 - y0) / step) + 1

    verts = []
    for j in range(ny):
        y = y0 + j * step
        for i in range(nx):
            x = x0 + i * step
            verts.append((x, y, terrain_height(x, y)))
    faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))

    mesh = bpy.data.meshes.new("Terrain")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Terrain", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    smooth(obj, 60.0)
    parts = [rename(obj, "Terrain-col", mats["sand"])]

    return parts


# ─────────────────────────────────────────────────────────────── скалы


def _rand_stream(seed):
    """Свой генератор, чтобы расстановка не менялась от запуска к запуску:
    случайные скалы, но всегда одни и те же."""
    state = [seed]
    def nxt(lo=0.0, hi=1.0):
        state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
        return lo + (state[0] / 0x7FFFFFFF) * (hi - lo)
    return nxt


def build_mountains(mats):
    """Дальняя гряда за бухтой.

    Скалы вокруг пляжа держат границу и стоят вплотную; горы — это силуэт на
    горизонте, до них не дойти. Поэтому они отдельной геометрией и без
    коллизии: игрок упрётся в скалы задолго до них.

    Конусы, а не шары: у горы есть вершина, а шар всегда читается валуном.
    """
    from mathutils import noise as bnoise
    from mathutils import Vector

    nxt = _rand_stream(555111)
    peaks = []
    count = 40
    for i in range(count):
        # ставим по дуге со стороны суши, море оставляем открытым
        a = math.radians(-150.0 + 300.0 * i / (count - 1.0))
        dist = nxt(330.0, 620.0)
        x = math.sin(a) * dist
        y = P["shore_y"] + math.cos(a) * dist
        # гора внутри бухты выглядит колом посреди пляжа
        if abs(x) < P["beach_x"] + 55.0 and y < P["beach_back"] + 70.0:
            continue
        h = nxt(70.0, 175.0)
        r = h * nxt(0.75, 1.35)          # шире и ниже: острые колпаки читались бумажными
        bpy.ops.mesh.primitive_cone_add(vertices=int(nxt(9, 13)), radius1=r,
                                        radius2=nxt(0.0, r * 0.3),
                                        depth=h, location=(x, y, h * 0.5 - 14.0))
        peak = bpy.context.object
        # Мнём сильно и на трёх масштабах. Слабое сминание оставляло ровный
        # конус, а гора — это отроги и седловины, а не колпак.
        top = h * 0.5
        for v in peak.data.vertices:
            w = peak.matrix_world @ v.co
            n = bnoise.noise(Vector((w.x * 0.008, w.y * 0.008, w.z * 0.008))) * 0.30
            n += bnoise.noise(Vector((w.x * 0.024, w.y * 0.024, w.z * 0.024))) * 0.16
            n += bnoise.noise(Vector((w.x * 0.07, w.y * 0.07, w.z * 0.07))) * 0.06
            # У вершины конуса вершины сетки сходятся в точку, и сминание там
            # вытягивает иглу. Глушим деформацию по мере приближения к верхушке.
            taper = 1.0 - max(0.0, min(1.0, (v.co.z + top) / (h * 1.05))) ** 3
            v.co += v.normal * n * h * taper
        peak.data.update()
        peak.rotation_euler = (0, 0, nxt(0.0, 6.28))
        peaks.append(peak)
    peak = join(peaks, "Mountains", mats["rock"])
    smooth(peak, 50.0)
    return [peak]


# ─────────────────────────────────────────────────────────────── пирс


def build_pier(mats):
    """Настил из досок, сваи, перила с одной стороны и лестница к воде."""
    w, top = P["pier_width"], P["pier_z"]
    y0, y1 = P["shore_y"] + 1.0, P["shore_y"] - P["pier_len"]

    # Настил: доски — присланная модель, её кладёт Row в сцене. Здесь остаётся
    # только сплошная плита-основание. Она же решает старую беду: коллизия по
    # мешу из отдельных досок с зазорами дырявая, сквозь неё проваливались.
    deck = [box((0, (y0 + y1) / 2, top - 0.09), (w - 0.02, y0 - y1, 0.12))]
    for sx in (-1, 1):
        deck.append(box((sx * (w / 2 - 0.3), (y0 + y1) / 2, top - 0.32),
                        (0.22, y0 - y1, 0.32)))
    parts = [join(deck, "Pier_Deck-col", mats["wood_dark"])]

    pilings = []
    y = y0 - 1.5
    while y > y1:
        for sx in (-1, 1):
            p = cylinder(P["piling_r"], 5.0, (sx * (w / 2 - 0.35), y, top - 2.6),
                         verts=12)
            smooth(p)
            pilings.append(p)
        y -= 4.0
    parts.append(join(pilings, "Pier_Pilings-col", mats["wood_dark"]))

    rails = []
    for sx in (-1, 1):
        rails.append(box((sx * (w / 2 - 0.1), (y0 + y1) / 2, top + 1.0),
                         (0.09, y0 - y1, 0.09)))
        rails.append(box((sx * (w / 2 - 0.1), (y0 + y1) / 2, top + 0.55),
                         (0.07, y0 - y1, 0.07)))
        y = y0 - 1.0
        while y > y1:
            rails.append(box((sx * (w / 2 - 0.1), y, top + 0.5), (0.11, 0.11, 1.0)))
            y -= 2.0
    parts.append(join(rails, "Pier_Rails-col", mats["wood_dark"]))

    # трап к воде на конце пирса
    steps = []
    for i in range(5):
        steps.append(box((w / 2 + 0.35, y1 + 0.8, top - 0.35 - i * 0.32),
                         (1.2, 0.3, 0.08)))
    for sy in (-1, 1):
        steps.append(box((w / 2 + 0.35, y1 + 0.8 + sy * 0.2, top - 1.0),
                         (0.1, 0.1, 1.6)))
    parts.append(join(steps, "Pier_Ladder-col", mats["wood_dark"]))
    return parts


def build_pier_props(mats):
    """Кнехты, ящики, бочки и фонари — без них пирс читается пустой доской."""
    top = P["pier_z"]
    w = P["pier_width"]
    parts = []

    bollards = []
    for y in (P["shore_y"] - 4.0, P["shore_y"] - 14.0, P["shore_y"] - 23.0):
        for sx in (-1, 1):
            b = cylinder(0.16, 0.7, (sx * (w / 2 - 0.45), y, top + 0.3), verts=16)
            smooth(b)
            cap = cylinder(0.22, 0.1, (sx * (w / 2 - 0.45), y, top + 0.68), verts=16)
            bollards += [b, cap]
    parts.append(join(bollards, "Bollards-col", mats["metal"]))

    crates = []
    for x, y, s, rot in [(-1.4, P["shore_y"] - 6.0, 0.8, 0.3),
                         (-1.5, P["shore_y"] - 6.6, 0.6, -0.5),
                         (1.5, P["shore_y"] - 18.0, 0.75, 0.9),
                         (-1.3, P["shore_y"] - 6.2, 0.7, 0.1)]:
        c = box((0, 0, 0), (s, s, s))
        bevel(c, 0.03)
        c.location = (x, y, top + s / 2)
        c.rotation_euler = (0, 0, rot)
        crates.append(c)
    parts.append(join(crates, "Crates-col", mats["wood"]))

    barrels = []
    for x, y in [(1.5, P["shore_y"] - 9.0), (1.6, P["shore_y"] - 9.9)]:
        b = cylinder(0.42, 1.1, (x, y, top + 0.55), verts=20)
        smooth(b)
        barrels.append(b)
    parts.append(join(barrels, "Barrels-col", mats["barrel"]))

    return parts


# ─────────────────────────────────────────────────────────────── дом


def build_path(mats):
    """Тропинка от берега к пирсу. Дом теперь готовая модель (assets/models/
    house.glb), её ставит сцена — собирать коробку заново незачем."""
    path = box((-5.0, P["shore_y"] + 4.0, 0.06), (2.4, 12.0, 0.12))
    path.rotation_euler = (0, 0, math.radians(-18))
    return [rename(path, "Path", mats["stone"])]


# ─────────────────────────────────────────────────────────────── вывод


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {
        "sand": material("Sand", (0.76, 0.66, 0.48), 0.0, 0.98),
        "rock": material("Rock", (0.34, 0.31, 0.28), 0.0, 0.9),
        "wood": material("Wood", (0.52, 0.36, 0.22), 0.0, 0.75),
        "wood_dark": material("WoodDark", (0.32, 0.22, 0.15), 0.0, 0.8),
        "roof": material("Roof", (0.30, 0.15, 0.13), 0.0, 0.7),
        "stone": material("Stone", (0.42, 0.41, 0.39), 0.0, 0.85),
        "metal": material("Metal", (0.35, 0.36, 0.38), 0.9, 0.45),
        "barrel": material("Barrel", (0.20, 0.34, 0.34), 0.5, 0.55),
        "grass": material("Grass", (0.42, 0.44, 0.24), 0.0, 0.85),
        "glass": glass_material("WindowGlass", (0.55, 0.70, 0.78)),
        "lamp": material("LampGlobe", (1.0, 0.90, 0.68), 0.0, 0.2, emission=5.0),
    }

    parts = []
    for builder in (build_terrain, build_mountains, build_pier,
                    build_pier_props, build_path):
        parts += builder(mats)
    print("### частей:", len(parts), "->", ", ".join(p.name for p in parts))

    export_glb(parts, OUT_GLB)
    render_previews(
        views={
            "overview": (34, 34, 20),
            "pier": (12, -22, 9),
        },
        target=(0, 2, 2), out_dir=OUT_RENDER, prefix="lobby", lens=34)


if __name__ == "__main__":
    main()
