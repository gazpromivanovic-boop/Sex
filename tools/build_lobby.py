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
    "terrain_step": 1.6,         # шаг сетки рельефа, м
    "beach_x": 58.0,             # докуда пляж по бортам
    "beach_back": 46.0,          # и вглубь суши
    "arch_x": 15.0,              # где в скалах проход
    "arch_w": 7.0,
    "cliff_h": 17.0,             # высота скальной стены вокруг пляжа
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
    out = max(abs(x) - P["beach_x"], y - P["beach_back"])
    if out > -1.0:
        wall = P["cliff_h"] * smoothstep(-1.0, 11.0, out)
        # проход под арку: узкая щель в задней стене
        if y > P["beach_back"] - 4.0:
            # щель ровно под арку: шире — и она повисает в чистом поле
            gap = smoothstep(P["arch_w"] * 0.42, P["arch_w"] * 0.62,
                             abs(x - P["arch_x"]))
            wall *= gap
        base += wall

    dune = smoothstep(10.0, 34.0, t)          # крупный шум только в дюнах
    h = bnoise.noise(Vector((x * 0.032, y * 0.032, 0.0))) * 1.5 * dune
    h += bnoise.noise(Vector((x * 0.11, y * 0.11, 11.0))) * 0.30 * (0.2 + 0.8 * dune)
    h += bnoise.noise(Vector((x * 0.40, y * 0.40, 23.0))) * 0.07
    # на скалах шум крупнее и жёстче: у камня рельеф не такой, как у песка
    rocky = smoothstep(-2.0, 8.0, max(abs(x) - P["beach_x"], y - P["beach_back"]))
    if rocky > 0.0:
        h += bnoise.noise(Vector((x * 0.09, y * 0.09, 41.0))) * 3.4 * rocky
        h += bnoise.noise(Vector((x * 0.26, y * 0.26, 57.0))) * 1.1 * rocky

    # площадки под постройками: дом на сваях, но стулья стоят прямо на песке
    flat = 1.0
    for px, py, pr in P["pads"]:
        d = math.hypot(x - px, y - py)
        flat = min(flat, smoothstep(pr, pr + 5.0, d))
    return base + h * flat


def build_terrain(mats):
    """Берег и дно одним мешем: раздельные плиты давали ступеньку на линии воды."""
    x0, x1, y0, y1 = -92.0, 92.0, -100.0, 84.0
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

    rocks = []
    for i, (x, y, r) in enumerate([(-20, 4.0, 1.5), (16, 2.5, 1.1), (22, 9.0, 1.8),
                                   (-13, 1.0, 0.9), (10, -3.0, 1.3), (-26, 14.0, 1.2),
                                   (28, 18.0, 1.6), (-31, -4.0, 1.4), (33, -8.0, 1.1)]):
        rock = ball(r, (x, y, terrain_height(x, y) + r * 0.25),
                    scale=(1.0, 0.8, 0.6), segments=12, rings=7)
        rock.rotation_euler = (0, 0, i * 0.7)
        rocks.append(rock)
    parts.append(join(rocks, "Rocks-col", mats["rock"]))

    # Галька у линии прибоя. Кладём по псевдослучайной решётке, а не в цикле по
    # углу: ровное кольцо камней вокруг берега читается декорацией, а не пляжем.
    pebbles = []
    seed = 12345
    for i in range(90):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        x = (seed / 0x7FFFFFFF) * 76.0 - 38.0
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        y = P["shore_y"] + (seed / 0x7FFFFFFF) * 16.0 - 9.0
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        r = 0.10 + (seed / 0x7FFFFFFF) * 0.22
        if abs(x) < 3.6:
            continue                          # под пирсом галька не нужна
        p = ball(r, (x, y, terrain_height(x, y) + r * 0.15),
                 scale=(1.0, 0.85, 0.45), segments=8, rings=5)
        p.rotation_euler = (0, 0, i * 0.9)
        pebbles.append(p)
    parts.append(join(pebbles, "Pebbles", mats["rock"]))

    # Коряги: без них сухой песок читается пустым полем.
    logs = []
    for i, (x, y, ln, ang) in enumerate([(-15.5, 11.0, 3.2, 0.7), (13.0, 13.5, 2.4, -1.1),
                                         (-24.0, 9.0, 2.8, 2.2), (24.0, 6.5, 2.0, 0.3)]):
        log = cylinder(0.22, ln, (x, y, terrain_height(x, y) + 0.18),
                       rotation=(math.radians(90), 0, ang), verts=10)
        smooth(log)
        logs.append(log)
    parts.append(join(logs, "Driftwood-col", mats["wood_dark"]))
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


def build_arch(mats):
    """Арка в скале — единственный вход на пляж. Собирается из пролёта по
    полуокружности: сплошная глыба с дыркой булевой операцией дала бы
    непредсказуемую форму, а тут проход гарантированно проходим."""
    nxt = _rand_stream(99887)
    ax, ay = P["arch_x"], P["beach_back"]
    ground = terrain_height(ax, ay - 6.0)   # высота в самом проходе
    half = P["arch_w"] * 0.5
    height = 9.0
    pieces = []

    for sx in (-1, 1):
        for k in range(3):
            r = nxt(2.2, 3.2)
            pieces.append(ball(r, (ax + sx * (half + r * 0.55) + nxt(-0.4, 0.4),
                                   ay + nxt(-1.2, 1.2),
                                   ground + 1.2 + k * 2.6),
                               scale=(1.0, nxt(0.8, 1.2), nxt(0.9, 1.3)),
                               segments=12, rings=7))
    # пролёт: восемь глыб по дуге от опоры к опоре
    for i in range(9):
        a = math.pi * i / 8.0
        x = ax - math.cos(a) * (half + 1.4)
        z = ground + height - 2.2 + math.sin(a) * 2.6
        r = nxt(1.9, 2.7)
        pieces.append(ball(r, (x, ay + nxt(-1.0, 1.0), z),
                           scale=(1.0, nxt(0.85, 1.25), nxt(0.7, 1.0)),
                           segments=12, rings=7))
    for p in pieces:
        smooth(p, 50.0)
    return [join(pieces, "Arch-col", mats["rock"])]


# ─────────────────────────────────────────────────────────────── пирс


def build_pier(mats):
    """Настил из досок, сваи, перила с одной стороны и лестница к воде."""
    w, top = P["pier_width"], P["pier_z"]
    y0, y1 = P["shore_y"] + 1.0, P["shore_y"] - P["pier_len"]

    planks = []
    y = y0
    while y > y1:
        planks.append(box((0, y - P["plank"] / 2, top - 0.06),
                          (w, P["plank"] * 0.88, 0.12)))
        y -= P["plank"]
    # продольные балки под настилом
    for sx in (-1, 1):
        planks.append(box((sx * (w / 2 - 0.3), (y0 + y1) / 2, top - 0.28),
                          (0.22, y0 - y1, 0.32)))
    parts = [join(planks, "Pier_Deck-col", mats["wood"])]

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

    posts, lamps = [], []
    for y in (P["shore_y"] - 8.0, P["shore_y"] - 20.0):
        p = cylinder(0.09, 3.2, (w / 2 - 0.35, y, top + 1.6), verts=12)
        arm = box((w / 2 - 0.7, y, top + 3.1), (0.8, 0.08, 0.08))
        posts += [p, arm]
        lamps.append(ball(0.22, (w / 2 - 1.05, y, top + 2.95), segments=16, rings=8))
    parts.append(join(posts, "Lamp_Posts-col", mats["metal"]))
    parts.append(join(lamps, "Lamp_Globes", mats["lamp"]))
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
        "glass": glass_material("WindowGlass", (0.55, 0.70, 0.78)),
        "lamp": material("LampGlobe", (1.0, 0.90, 0.68), 0.0, 0.2, emission=5.0),
    }

    parts = []
    for builder in (build_terrain, build_arch, build_pier,
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
