"""Собирает модель батискафа и кладёт её в assets/models/bathyscaphe.glb.

    blender --background --factory-startup --python tools/build_bathyscaphe.py

Модель параметрическая: все размеры лежат в P, менять их надо там, а не в
вершинах. Аппарат в игре обитаемый, и когда выяснится, что четверым тесно или
что люк не совпал с трапом, размеры придётся двигать — руками такое потом не
пересобрать.

Части остаются отдельными объектами с говорящими именами (Ballast_Fore,
Thruster_RR_Blade, Viewport_Main). Ломаться в игре должны конкретные узлы, а не
«батискаф вообще», поэтому каждый узел адресуем из кода.

Компоновка классическая, как у «Триеста»: сверху поплавок с лёгкой жидкостью,
под ним на клетчатой раме — стальная обитаемая сфера, снизу полозья, чтобы
садиться на грунт. Гондола висит НИЖЕ поплавка, а не утоплена в него: иначе
иллюминаторы смотрят в цистерну.

Ориентация и начало координат сразу под Godot: метры, нос в −Z, начало координат
в самой нижней точке полозьев — тогда global_position тела совпадает с точкой
опоры, и BodyCollider обмеряет всё правильно.
"""

import math
import os

import bpy
from mathutils import Vector

# ─────────────────────────────────────────────────────────────── размеры
# Ось Z здесь вертикальная (Blender). Экспортёр сам развернёт сцену в Y-up.

P = {
    # обитаемая сфера
    "sphere_r": 2.40,            # радиус по обшивке
    "sphere_wall": 0.25,
    "floor_drop": 0.90,          # насколько пол ниже центра сферы
    "sphere_z": 2.90,            # центр сферы над полозьями

    # поплавок: цистерны лёгкой жидкости, за их счёт аппарат всплывает
    "float_len": 11.0,
    "float_r": 2.15,
    "float_z": 7.60,             # низ поплавка = 5.45, верх сферы = 5.30

    # клетка вокруг сферы
    "cage_x": 2.05,              # стойки по бортам
    "cage_y": 2.25,              # и по носу с кормой
    "beam": 0.15,

    # иллюминаторы
    "viewport_r": 0.62,
    "porthole_r": 0.24,
    "porthole_count": 4,

    # бункеры дроби: сбрасываются, чтобы всплыть
    "ballast_r": 0.72,
    "ballast_h": 1.5,
    "ballast_x": 1.55,           # по бортам, а не по носу: иначе бункер
    "ballast_y": 1.90,           # встаёт ровно перед носовым иллюминатором

    # движители
    "thruster_r": 0.52,
    "duct_wall": 0.11,

    # полозья
    "skid_len": 7.6,
    "skid_h": 0.30,
}

OUT_GLB = "assets/models/bathyscaphe.glb"
OUT_RENDER = "tools/preview"


# ─────────────────────────────────────────────────────────────── утилиты


def material(name, color, metallic=0.9, roughness=0.45, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def glass_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.08
    bsdf.inputs["Transmission Weight"].default_value = 0.9
    return mat


def rename(obj, name, mat=None):
    obj.name = name
    obj.data.name = name
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def smooth(obj, angle=35.0):
    """Сглаживание по углу: после булевых операций гладить всё подряд нельзя —
    рёбра вырезов расплываются, и корпус выглядит мятым."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    mod = obj.modifiers.new("Smooth", "SMOOTH_BY_ANGLE") \
        if "SMOOTH_BY_ANGLE" in dir(bpy.types) else None
    if mod is None and hasattr(obj.data, "use_auto_smooth"):
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = math.radians(angle)
    return obj


def bevel(obj, width=0.02, segments=2):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    return obj


def boolean(target, cutter, op="DIFFERENCE"):
    mod = target.modifiers.new("Bool", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return target


def cylinder(radius, depth, location, rotation=(0, 0, 0), verts=40):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth,
        location=location, rotation=rotation)
    return bpy.context.object


def box(location, scale):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return obj


def ball(radius, location, scale=(1, 1, 1), segments=64, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return obj


def join(objects, name, mat):
    """Сваривает несколько тел в одно: рама и полозья в игре ломаются целиком,
    держать их десятком объектов незачем."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return rename(bpy.context.object, name, mat)


# ─────────────────────────────────────────────────────────────── узлы


def build_gondola(mats):
    """Стальная сфера: толстая стенка, плоский пол, вырезы под иллюминаторы."""
    z = P["sphere_z"]
    hull = ball(P["sphere_r"], (0, 0, z))
    rename(hull, "Gondola_Hull", mats["steel"])

    # Полость режем с уже плоским дном, а не приваливаем пол отдельным телом:
    # приваренный цилиндр вылезал за сферу юбкой, и гондола выходила яйцом.
    floor_z = z - P["floor_drop"]
    inner = P["sphere_r"] - P["sphere_wall"]
    cavity = ball(inner, (0, 0, z))
    boolean(cavity, box((0, 0, floor_z - 2.0), (8.0, 8.0, 4.0)))
    boolean(hull, cavity)

    boolean(hull, cylinder(P["viewport_r"], 1.4, (0, -P["sphere_r"], z + 0.15),
                           rotation=(math.radians(90), 0, 0)))
    for i in range(P["porthole_count"]):
        a = math.radians(55 + i * 72)
        pos = Vector((math.sin(a) * P["sphere_r"], -math.cos(a) * P["sphere_r"], z + 0.1))
        boolean(hull, cylinder(P["porthole_r"], 1.2, pos,
                               rotation=(math.radians(90), 0, -a), verts=24))
    smooth(hull)
    parts = [hull]

    glass = cylinder(P["viewport_r"], 0.1, (0, -P["sphere_r"] + 0.07, z + 0.15),
                     rotation=(math.radians(90), 0, 0))
    parts.append(rename(glass, "Viewport_Main", mats["glass"]))
    for i in range(P["porthole_count"]):
        a = math.radians(55 + i * 72)
        r = P["sphere_r"] - 0.07
        pos = Vector((math.sin(a) * r, -math.cos(a) * r, z + 0.1))
        g = cylinder(P["porthole_r"], 0.08, pos,
                     rotation=(math.radians(90), 0, -a), verts=24)
        parts.append(rename(g, "Porthole_%d" % (i + 1), mats["glass"]))
    return parts


def build_float(mats):
    """Поплавок — вытянутый эллипсоид, а не цилиндр с приваренными шарами:
    булева сварка оставляла складки на носу."""
    hull = ball(P["float_r"], (0, 0, P["float_z"]),
                scale=(1.0, P["float_len"] / (2 * P["float_r"]), 1.0))
    smooth(hull)
    parts = [rename(hull, "Float_Hull", mats["paint"])]

    # обручи-шпангоуты: заодно дробят длинный борт, который иначе читается пустым
    rings = []
    for y in (-3.4, -1.1, 1.2, 3.5):
        r = P["float_r"] * math.sqrt(max(0.05, 1.0 - (y / (P["float_len"] / 2)) ** 2))
        ring = cylinder(r + 0.05, 0.16, (0, y, P["float_z"]),
                        rotation=(math.radians(90), 0, 0), verts=48)
        smooth(ring)
        rings.append(ring)
    parts.append(join(rings, "Float_Ribs", mats["steel"]))
    return parts


def build_cage(mats):
    """Клетка: четыре стойки по углам, кольцевые балки и киль. Стойки идут по
    носу и корме сферы (y = ±cage_y), где она уже узкая, поэтому обходят её."""
    b = P["beam"]
    top = P["float_z"] - P["float_r"] + 0.1
    pieces = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            pieces.append(box((sx * P["cage_x"], sy * P["cage_y"], top / 2 + 0.2),
                              (b, b, top)))
    for sy in (-1, 1):
        pieces.append(box((0, sy * P["cage_y"], P["sphere_z"]),
                          (P["cage_x"] * 2, b, b)))
        pieces.append(box((0, sy * P["cage_y"], top),
                          (P["cage_x"] * 2, b, b)))
    for sx in (-1, 1):
        pieces.append(box((sx * P["cage_x"], 0, top),
                          (b, P["cage_y"] * 2, b)))
    pieces.append(box((0, 0, top + 0.1), (0.6, P["float_len"] * 0.85, b)))
    for p in pieces:
        bevel(p, 0.015)
    return [join(pieces, "Cage", mats["steel"])]


def build_skids(mats):
    """Полозья: на них аппарат садится на грунт. Начало координат — их низ."""
    pieces = []
    for sx in (-1, 1):
        pieces.append(box((sx * P["cage_x"], 0, P["skid_h"] / 2),
                          (0.18, P["skid_len"], P["skid_h"])))
    for sy in (-1, 1):
        pieces.append(box((0, sy * 2.9, P["skid_h"] / 2),
                          (P["cage_x"] * 2, 0.18, P["skid_h"])))
    for sx in (-1, 1):
        for sy in (-1, 1):
            pieces.append(box((sx * P["cage_x"], sy * P["cage_y"], 0.6),
                              (0.14, 0.14, 1.2)))
    for p in pieces:
        bevel(p, 0.02)
    return [join(pieces, "Skids", mats["steel"])]


def build_ballast(mats):
    """Бункеры дроби по бортам, за миделем сферы. Ставить их по носу нельзя —
    закрывают главный иллюминатор, а он тут рабочее место пилота."""
    parts = []
    for name, sx in (("Ballast_L", -1), ("Ballast_R", 1)):
        x, y = sx * P["ballast_x"], P["ballast_y"]
        hop = cylinder(P["ballast_r"], P["ballast_h"], (x, y, P["sphere_z"] - 1.0),
                       verts=28)
        smooth(hop)
        cone = cylinder(P["ballast_r"] * 0.45, 0.5, (x, y, P["sphere_z"] - 1.9),
                        verts=28)
        parts.append(join([hop, cone], name, mats["accent"]))
    return parts


def build_thrusters(mats):
    """Два маршевых в корме и два подруливающих по бортам, все в насадках."""
    parts = []
    layout = [
        ("Thruster_ML", (-1.15, P["float_len"] / 2 - 0.5, P["float_z"] - 0.9), (math.radians(90), 0, 0)),
        ("Thruster_MR", (1.15, P["float_len"] / 2 - 0.5, P["float_z"] - 0.9), (math.radians(90), 0, 0)),
        ("Thruster_SL", (-P["float_r"] - 0.35, -2.4, P["float_z"] - 0.2), (0, math.radians(90), 0)),
        ("Thruster_SR", (P["float_r"] + 0.35, -2.4, P["float_z"] - 0.2), (0, math.radians(90), 0)),
    ]
    for name, pos, rot in layout:
        duct = cylinder(P["thruster_r"] + P["duct_wall"], 0.62, pos, rotation=rot, verts=32)
        smooth(duct)
        boolean(duct, cylinder(P["thruster_r"], 1.0, pos, rotation=rot, verts=32))
        parts.append(rename(duct, name + "_Duct", mats["steel"]))

        # Винт собираем в начале координат и ставим на место трансформом самого
        # объекта. transform_apply здесь нельзя: он применяется ко всему
        # выделению, а не к одной детали, и лопасти разлетались по сцене.
        hub = cylinder(0.12, 0.66, (0, 0, 0), verts=16)
        blades = [hub]
        for k in range(3):
            blade = box((0, 0, 0), (P["thruster_r"] * 1.5, 0.05, 0.16))
            blade.rotation_euler = (0, 0, math.radians(k * 60))
            blades.append(blade)
        prop = join(blades, name + "_Blade", mats["accent"])
        prop.rotation_euler = rot
        prop.location = pos
        parts.append(prop)
    return parts


def build_lights(mats):
    """Прожекторы на носовых стойках. В игре гаснут первыми."""
    parts, lenses = [], []
    housings = []
    for sx in (-1, 1):
        pos = (sx * P["cage_x"], -P["cage_y"] - 0.3, P["sphere_z"] + 1.3)
        h = cylinder(0.26, 0.5, pos, rotation=(math.radians(75), 0, 0), verts=24)
        smooth(h)
        housings.append(bevel(h, 0.02))
        lens = cylinder(0.22, 0.06, (pos[0], pos[1] - 0.22, pos[2] - 0.06),
                        rotation=(math.radians(75), 0, 0), verts=24)
        lenses.append(lens)
    parts.append(join(housings, "Floodlight_Housing", mats["steel"]))
    parts.append(join(lenses, "Floodlight_Lens", mats["lamp"]))
    return parts


def build_hatch(mats):
    """Шахта из сферы наверх сквозь поплавок — единственный вход внутрь."""
    top_of_sphere = P["sphere_z"] + P["sphere_r"]
    top = P["float_z"] + P["float_r"] + 0.2
    trunk = cylinder(0.5, top - top_of_sphere + 0.6,
                     (0, 1.1, (top + top_of_sphere) / 2), verts=28)
    smooth(trunk)
    parts = [rename(bevel(trunk, 0.02), "Hatch_Trunk", mats["steel"])]

    lid = cylinder(0.66, 0.14, (0, 1.1, top + 0.1), verts=28)
    parts.append(rename(bevel(lid, 0.03), "Hatch_Lid", mats["accent"]))
    return parts


def build_interior(mats):
    """Палуба и четыре поста — по одному на игрока."""
    floor_z = P["sphere_z"] - P["floor_drop"]
    inner = P["sphere_r"] - P["sphere_wall"]
    radius = math.sqrt(max(0.01, inner ** 2 - P["floor_drop"] ** 2))

    deck = cylinder(radius, 0.08, (0, 0, floor_z + 0.04), verts=48)
    parts = [rename(deck, "Deck", mats["deck"])]

    for i in range(4):
        a = math.radians(45 + i * 90)
        c = box((0, 0, 0), (1.0, 0.45, 0.9))
        bevel(c, 0.03)
        c.rotation_euler = (0, 0, -a)
        c.location = (math.sin(a) * (radius - 0.45),
                      -math.cos(a) * (radius - 0.45), floor_z + 0.5)
        parts.append(rename(c, "Station_%d" % (i + 1), mats["accent"]))
    return parts


def build_manipulator(mats):
    """Манипулятор для образцов. Крепится к носовой стойке клетки."""
    y = -P["cage_y"] - 0.15
    base = cylinder(0.26, 0.44, (1.1, y, P["sphere_z"] - 1.3),
                    rotation=(math.radians(90), 0, 0), verts=20)
    smooth(base)
    parts = [rename(bevel(base, 0.02), "Arm_Base", mats["steel"])]

    upper = box((1.1, y - 0.75, P["sphere_z"] - 1.15), (0.16, 1.5, 0.16))
    parts.append(rename(bevel(upper, 0.02), "Arm_Upper", mats["accent"]))
    fore = box((1.1, y - 1.45, P["sphere_z"] - 1.75), (0.13, 0.13, 1.3))
    parts.append(rename(bevel(fore, 0.02), "Arm_Fore", mats["accent"]))
    return parts


# ─────────────────────────────────────────────────────────────── вывод


def render_previews():
    scene = bpy.context.scene
    # Cycles, а не EEVEE: последнему в фоновом режиме нужен графический контекст,
    # которого без окна нет, и он молча не пишет кадр.
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640

    scene.world = bpy.data.worlds.new("W")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.04, 0.08, 0.13, 1)

    bpy.ops.object.light_add(type="SUN", location=(8, -10, 16))
    bpy.context.object.data.energy = 3.5
    bpy.ops.object.light_add(type="AREA", location=(-12, 8, 8))
    bpy.context.object.data.energy = 2500.0
    bpy.context.object.data.size = 14.0

    target = Vector((0, 0, 5.0))
    views = {
        "side": Vector((26, 0, 6.5)),
        "front": Vector((0.5, -24, 6.0)),
        "three_quarter": Vector((17, -18, 11)),
    }
    os.makedirs(OUT_RENDER, exist_ok=True)
    for name, pos in views.items():
        bpy.ops.object.camera_add(location=pos)
        cam = bpy.context.object
        cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 42
        scene.camera = cam
        scene.render.filepath = os.path.abspath(
            os.path.join(OUT_RENDER, "bathyscaphe_%s.png" % name))
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {
        "steel": material("Steel", (0.40, 0.43, 0.47), 0.95, 0.38),
        "paint": material("HullPaint", (0.86, 0.38, 0.10), 0.30, 0.50),
        "accent": material("Accent", (0.14, 0.40, 0.44), 0.65, 0.42),
        "deck": material("Deck", (0.17, 0.18, 0.19), 0.10, 0.85),
        "glass": glass_material("Glass", (0.52, 0.74, 0.86)),
        "lamp": material("Lamp", (1.0, 0.94, 0.78), 0.0, 0.15, emission=8.0),
    }

    parts = []
    for builder in (build_gondola, build_float, build_cage, build_skids,
                    build_ballast, build_thrusters, build_lights,
                    build_hatch, build_interior, build_manipulator):
        parts += builder(mats)

    print("### частей:", len(parts), "->", ", ".join(p.name for p in parts))

    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB, export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True)
    print("### экспортировано:", OUT_GLB)

    render_previews()
    print("### превью в", OUT_RENDER)


if __name__ == "__main__":
    main()
