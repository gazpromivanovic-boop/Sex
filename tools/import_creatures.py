# -*- coding: utf-8 -*-
"""Готовит анимированную живность и кладёт её в assets/models/.

    blender --background --factory-startup --python tools/import_creatures.py

Отдельно от import_props.py, и это не дублирование. Тот конвейер сваривает все
меши в один объект и режет сетку прореживанием — для сундука и валуна правильно,
для скелетной модели смертельно: join рвёт привязку к костям, а decimate портит
веса. Здесь геометрия не трогается вовсе.

Что делается:

* **ужимаются текстуры**. Черепаха приехала на 27 МБ, из них 26 — четыре PNG по
  4K. В кадре она размером с ладонь, разницы не видно, а вес репозитория
  разница есть;
* **чинятся материалы**, если карты в поставке лежат отдельными файлами и
  импортёр их не подхватил;
* **сохраняются скелет и клипы**. Ничего не применяется и не сваривается.

Масштаб намеренно НЕ трогаем. Применить его к скелету, не сломав анимацию,
нельзя без плясок с бинд-позой; в сцене он задаётся полем scale у экземпляра, и
там же его удобно подбирать глазами. Скрипт печатает измеренные габариты — по
ним и считается нужный множитель.
"""

import os
import sys

import bpy

TEMP = "C:/Users/GamePC/AppData/Local/Temp"
DOWNLOADS = "C:/Users/GamePC/Downloads"

CREATURES = [
    {
        "src": DOWNLOADS + "/model_50a_-_hawksbill_sea_turtle.glb",
        "name": "turtle",
        "texture": 1024,
    },
    {
        "src": TEMP + "/manta/source/dd404dfababe4cadaeeacdbc3386386b.fbx.fbx",
        "name": "manta",
        "texture": 1024,
        # У FBX карты лежат отдельными файлами рядом; импортёр находит их не
        # всегда, поэтому пути указаны явно.
        "maps": {
            "base": TEMP + "/manta/textures/MantaRayBirostris_Diffuse.jpg",
            "normal": TEMP + "/manta/textures/MantaRayBirostris_Normal.jpg",
            "spec": TEMP + "/manta/textures/MantaRayBirostris_Spec.jpg",
        },
    },
]

OUT_DIR = "assets/models"


def cap_textures(max_size):
    for img in bpy.data.images:
        w, h = img.size
        if w > max_size or h > max_size:
            k = float(max_size) / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))
            print("###        текстура %dx%d -> %dx%d" % (w, h, img.size[0], img.size[1]))


def bounds():
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        # Габариты снимаем по вычисленной сетке: у скелетной модели вершины в
        # исходных координатах могут стоять где угодно относительно поз.
        mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        for v in mesh.vertices:
            w = obj.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def wire_maps(maps):
    """Собирает материал из отдельно лежащих карт."""
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nodes = mat.node_tree.nodes
        bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue

        base = nodes.new("ShaderNodeTexImage")
        base.image = bpy.data.images.load(maps["base"])
        base.location = (bsdf.location.x - 400, bsdf.location.y)
        mat.node_tree.links.new(bsdf.inputs["Base Color"], base.outputs["Color"])

        if maps.get("normal"):
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(maps["normal"])
            tex.image.colorspace_settings.name = "Non-Color"
            tex.location = (bsdf.location.x - 700, bsdf.location.y - 400)
            nrm = nodes.new("ShaderNodeNormalMap")
            nrm.location = (bsdf.location.x - 300, bsdf.location.y - 400)
            mat.node_tree.links.new(nrm.inputs["Color"], tex.outputs["Color"])
            mat.node_tree.links.new(bsdf.inputs["Normal"], nrm.outputs["Normal"])

        if maps.get("spec"):
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(maps["spec"])
            tex.image.colorspace_settings.name = "Non-Color"
            tex.location = (bsdf.location.x - 400, bsdf.location.y - 750)
            # Карта бликов — это обратная шероховатость: где блестит, там гладко.
            inv = nodes.new("ShaderNodeInvert")
            inv.location = (bsdf.location.x - 200, bsdf.location.y - 750)
            mat.node_tree.links.new(inv.inputs["Color"], tex.outputs["Color"])
            mat.node_tree.links.new(bsdf.inputs["Roughness"], inv.outputs["Color"])


def prepare(creature):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not os.path.exists(creature["src"]):
        print("### нет файла:", creature["src"])
        return False
    ext = os.path.splitext(creature["src"])[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=creature["src"])
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=creature["src"])
    else:
        print("### не знаю, как открыть", creature["src"])
        return False

    if creature.get("maps"):
        wire_maps(creature["maps"])
    cap_textures(creature.get("texture", 1024))

    clips = [a.name for a in bpy.data.actions]
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    lo, hi = bounds()
    print("### %-7s треугольников %d, клипов %d %s" % (creature["name"], tris,
                                                       len(clips), clips))
    print("###         габариты %.2f x %.2f x %.2f м" % (hi[0] - lo[0],
                                                         hi[1] - lo[1], hi[2] - lo[2]))

    path = os.path.join(OUT_DIR, creature["name"] + ".glb")
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    # export_apply здесь нельзя: он применяет модификаторы, и на скелетной
    # модели это разрушило бы привязку. Анимации, наоборот, нужны все.
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_apply=False, export_yup=True, export_animations=True,
        export_skins=True)
    print("### экспортировано:", path, "%.1f МБ" % (os.path.getsize(path) / 1048576))
    return True


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for creature in CREATURES:
        if only and creature["name"] not in only:
            continue
        prepare(creature)


if __name__ == "__main__":
    main()
