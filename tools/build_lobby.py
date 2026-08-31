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
    дом стоит слева от пирса, крыльцом к воде;
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
    "land_size": 70.0,

    "pier_len": 26.0,            # от берега в сторону воды
    "pier_width": 5.0,
    "pier_z": 0.55,              # высота настила над нулём
    "plank": 0.28,
    "piling_r": 0.22,

    "house_w": 9.0,
    "house_d": 7.5,
    "house_h": 3.6,
    "roof_h": 3.0,          # круче скат: пологая крыша читается плоской плитой
    "house_x": -9.5,
    "house_y": 15.0,
}

OUT_GLB = "assets/models/lobby.glb"
OUT_RENDER = "tools/preview"


# ─────────────────────────────────────────────────────────────── берег


def build_land(mats):
    """Берег: плита с фаской у кромки, чтобы не было ножа на линии воды."""
    land = box((0, P["shore_y"] + P["land_size"] / 2, -1.5),
               (P["land_size"], P["land_size"], 3.0))
    bevel(land, 0.35, 3)
    parts = [rename(land, "Land-col", mats["sand"])]

    # отмель: уходит под воду, иначе берег обрывается стеной
    shelf = box((0, P["shore_y"] - 1.0, -2.2), (P["land_size"], 14.0, 4.2))
    shelf.rotation_euler = (math.radians(-7), 0, 0)   # пологий заход в воду
    bevel(shelf, 0.5, 2)
    parts.append(rename(shelf, "Shelf-col", mats["sand"]))

    rocks = []
    for i, (x, y, r) in enumerate([(-20, 4.0, 1.5), (16, 2.5, 1.1), (22, 7.0, 1.8),
                                   (-13, 1.0, 0.9), (10, -3.0, 1.3)]):
        rock = ball(r, (x, y, -0.4 + r * 0.35), scale=(1.0, 0.8, 0.6),
                    segments=12, rings=7)
        rock.rotation_euler = (0, 0, i * 0.7)
        rocks.append(rock)
    parts.append(join(rocks, "Rocks-col", mats["rock"]))
    return parts


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


def build_house(mats):
    """Домик смотрителя: сруб с двускатной крышей, крыльцо повёрнуто к пирсу."""
    x0, y0 = P["house_x"], P["house_y"]
    w, d, h = P["house_w"], P["house_d"], P["house_h"]
    parts = []

    walls = box((x0, y0, h / 2), (w, d, h))
    # полость: дом должен быть коробкой со стенами, а не монолитом
    boolean(walls, box((x0, y0, h / 2), (w - 0.5, d - 0.5, h - 0.5)))
    # дверь и окна прорезаем насквозь
    boolean(walls, box((x0, y0 - d / 2, 1.1), (1.3, 1.2, 2.2)))
    for sx in (-1, 1):
        boolean(walls, box((x0 + sx * 2.7, y0 - d / 2, 2.1), (1.5, 1.2, 1.2)))
    boolean(walls, box((x0 + w / 2, y0 + 1.2, 2.1), (1.2, 1.6, 1.2)))
    parts.append(rename(bevel(walls, 0.04), "House_Walls-col", mats["wood_dark"]))

    # свес небольшой: при +1.2 м крыша выглядела плитой размером с сам дом
    roof = wedge((x0, y0, h + P["roof_h"] / 2), (w + 0.7, d + 0.6, P["roof_h"]))
    parts.append(rename(roof, "House_Roof-col", mats["roof"]))

    glass = []
    for sx in (-1, 1):
        glass.append(box((x0 + sx * 2.7, y0 - d / 2 + 0.02, 2.1), (1.4, 0.06, 1.1)))
    glass.append(box((x0 + w / 2 - 0.02, y0 + 1.2, 2.1), (0.06, 1.5, 1.1)))
    parts.append(join(glass, "House_Windows", mats["glass"]))

    porch = []
    porch.append(box((x0, y0 - d / 2 - 1.4, 0.2), (w * 0.75, 2.8, 0.4)))
    for sx in (-1, 1):
        porch.append(box((x0 + sx * (w * 0.35), y0 - d / 2 - 2.6, 1.5),
                         (0.16, 0.16, 2.6)))
    porch.append(box((x0, y0 - d / 2 - 2.6, 2.85), (w * 0.78, 0.2, 0.3)))
    porch.append(wedge((x0, y0 - d / 2 - 1.5, 3.05), (w * 0.78, 3.2, 0.5)))
    parts.append(join(porch, "House_Porch-col", mats["wood"]))

    # тропинка от крыльца к пирсу
    path = box((x0 * 0.5, (y0 - d / 2 - 2.8 + P["shore_y"]) / 2, 0.06),
               (2.2, y0 - d / 2 - 2.8 - P["shore_y"] + 2.0, 0.12))
    path.rotation_euler = (0, 0, math.radians(-14))
    parts.append(rename(path, "Path", mats["stone"]))

    chimney = box((x0 - w / 4, y0 + 1.0, h + P["roof_h"] * 0.7),
                  (0.8, 0.8, P["roof_h"] * 1.3))
    parts.append(rename(bevel(chimney, 0.03), "Chimney-col", mats["stone"]))
    return parts


# ─────────────────────────────────────────────────────────────── вывод


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {
        "sand": material("Sand", (0.46, 0.40, 0.31), 0.0, 0.95),
        "rock": material("Rock", (0.28, 0.28, 0.30), 0.0, 0.9),
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
    for builder in (build_land, build_pier, build_pier_props, build_house):
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
