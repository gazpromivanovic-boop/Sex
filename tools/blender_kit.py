"""Общие кирпичи для скриптов, которые собирают модели в Blender.

Импортируется из build_bathyscaphe.py и build_lobby.py:

    import sys, os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from blender_kit import *

Здесь только то, на чём оба скрипта уже спотыкались: transform_apply работает по
всему выделению, а не по одной детали; EEVEE в фоновом режиме молча не пишет
кадр; после булевых операций гладить всё подряд нельзя. Каждая ловушка обойдена
внутри соответствующей функции, чтобы не наступать на них заново.
"""

import math
import os

import bpy
from mathutils import Vector


# ─────────────────────────────────────────────────────────────── материалы


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


# ─────────────────────────────────────────────────────────────── примитивы


def rename(obj, name, mat=None):
    obj.name = name
    obj.data.name = name
    if mat is not None:
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    return obj


def smooth(obj, angle=35.0):
    """Сглаживание по углу. Гладить всё подряд после булевых операций нельзя:
    рёбра вырезов расплываются, и корпус выглядит мятым."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    if hasattr(obj.data, "use_auto_smooth"):
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


def wedge(location, scale):
    """Треугольная призма — из неё делаются скаты крыш и косынки."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    mesh = obj.data
    # сводим верхнее ребро в конёк: две верхние пары вершин съезжаются к центру
    top = sorted(mesh.vertices, key=lambda v: -v.co.z)[:4]
    for v in top:
        v.co.x = 0.0
    return obj


def join(objects, name, mat=None):
    """Сваривает тела в одно. Объекты с разными трансформами тоже сваривает —
    Blender приводит их сам, поэтому transform_apply перед этим не нужен."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return rename(bpy.context.object, name, mat)


# ─────────────────────────────────────────────────────────────── вывод


def export_glb(parts, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True)
    print("### экспортировано:", path)


def render_previews(views, target, out_dir, prefix, lens=42, sun=(8, -10, 16)):
    """Cycles, а не EEVEE: последнему в фоновом режиме нужен графический
    контекст, которого без окна нет, и он молча не пишет кадр."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640

    scene.world = bpy.data.worlds.new("W")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.09, 0.14, 1)

    bpy.ops.object.light_add(type="SUN", location=sun)
    bpy.context.object.data.energy = 3.5
    bpy.ops.object.light_add(type="AREA", location=(-12, 8, 10))
    bpy.context.object.data.energy = 3000.0
    bpy.context.object.data.size = 16.0

    os.makedirs(out_dir, exist_ok=True)
    for name, pos in views.items():
        bpy.ops.object.camera_add(location=pos)
        cam = bpy.context.object
        cam.rotation_euler = (Vector(target) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        scene.camera = cam
        scene.render.filepath = os.path.abspath(
            os.path.join(out_dir, "%s_%s.png" % (prefix, name)))
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
    print("### превью в", out_dir)
