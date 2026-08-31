"""Приводит присланные модели к игровому виду и кладёт их в assets/models/.

    blender --background --factory-startup --python tools/import_props.py

Модели из генераторов вроде Tripo и Meshy приходят в двух миллионах
треугольников и отнормированные ровно в единицу высоты. В игру такое класть
нельзя: домик и стул по два миллиона каждый — это больше, чем вся остальная
сцена вместе взятая, а размер у них одинаковый, хотя дом должен быть втрое выше
стула.

Скрипт делает три вещи:

* **режет сетку** до игрового бюджета. Decimate collapse сохраняет развёртку,
  поэтому текстура остаётся на месте. Бюджет задаётся в треугольниках, а не
  долей: доля ничего не говорит, а «пять тысяч на стул» — говорит;
* **возвращает масштаб**. Генератор нормирует модель в единицу, поэтому реальную
  высоту приходится задавать снаружи — её знает только человек;
* **ставит на пол и в центр**. Начало координат уезжает в геометрический центр
  меша, а нужно, чтобы объект стоял на нуле: тогда его можно просто поставить
  на поверхность, не подбирая высоту.

Добавить свою модель — дописать строку в PROPS.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blender_kit import export_glb, render_previews

TEMP = "C:/Users/GamePC/AppData/Local/Temp"
ROCKS = TEMP + "/rocks"

PROPS = [
    {
        "src": TEMP + "/маленький домик.fbx",
        "name": "house",
        "height": 5.6,        # м: свайный дом, высота считается с опорами
        "budget": 24000,      # треугольников после прореживания
        "texture": 1024,      # предел стороны текстуры
    },
    {
        "src": TEMP + "/стулик.fbx",
        "name": "chair",
        "height": 0.95,
        "budget": 6000,
        "texture": 512,
    },
    # Камни со Sketchfab. Бюджет мелкий: их будет много, и каждый лишний
    # треугольник умножается на количество разбросанных копий.
    {"src": ROCKS + "/obj-nat-rock-01/source/c5233a6c6cec48bcb40fcfc665521932.obj",
     "name": "rock_a", "height": 1.8, "budget": 900, "texture": 512},
    {"src": ROCKS + "/rock/source/untitled.obj",
     "name": "rock_b", "height": 2.6, "budget": 1200, "texture": 512},
    {"src": ROCKS + "/rock-photogrammetry-scan/source/Rock.obj",
     "name": "rock_c", "height": 3.4, "budget": 1500, "texture": 1024},
    {"src": ROCKS + "/rock-rock/source/model/model.dae",
     "name": "rock_d", "height": 2.1, "budget": 900, "texture": 512},
    # Фонарь стоит вертикально, поэтому height — это его полная высота.
    {"src": ROCKS + "/street-light-lamp-spotlight-10mb/source/02.fbx",
     "name": "lamp", "height": 4.6, "budget": 2500, "texture": 1024},
    # Бревно лежит, и по вертикали у него всего лишь толщина ствола.
    {"src": ROCKS + "/log-photogrammetrised/source/log1_low.obj",
     "name": "log", "height": 0.62, "budget": 1400, "texture": 512},
    {"src": ROCKS + "/pier-ground-tile/source/Pier Ground Tile.obj",
     "name": "tile", "height": 0.14, "budget": 600, "texture": 1024},
    # Трава: настоящие кустики вместо моих конусов.
    {"src": ROCKS + "/grass-patches/source/grasspatches.fbx",
     "name": "grass_patch", "height": 0.55, "budget": 900, "texture": 512},
    {"src": ROCKS + "/dry-grass/source/sketchfabGrass.fbx",
     "name": "grass_dry", "height": 0.45, "budget": 700, "texture": 512},
    # Из .rar: распаковщик нашёлся у WinRAR.
    {"src": ROCKS + "/ruined-rock-fence/source/unpacked/stone_fence_old_low.fbx",
     "name": "fence", "height": 1.25, "budget": 1600, "texture": 1024},
    {"src": ROCKS + "/log/source/unpacked/Log_fbx.fbx",
     "name": "log_b", "height": 0.55, "budget": 1200, "texture": 512},
]

OUT_DIR = "assets/models"
OUT_RENDER = "tools/preview"


def count_tris():
    total = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            total += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return total


def bounds():
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def cap_textures(max_size):
    """Ужимает текстуры. Генератор отдаёт 4K даже на сарай, а в кадре он
    занимает сотню пикселей — вес файла втрое, разницы никакой."""
    for img in bpy.data.images:
        w, h = img.size
        if w > max_size or h > max_size:
            k = float(max_size) / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))
            print("###        текстура %dx%d -> %dx%d" % (w, h, img.size[0], img.size[1]))


def prepare(prop):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not os.path.exists(prop["src"]):
        print("### нет файла:", prop["src"])
        return None
    ext = os.path.splitext(prop["src"])[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=prop["src"])
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=prop["src"])
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=prop["src"])
    else:
        print("### не знаю, как открыть", prop["src"])
        return None

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("### в файле нет мешей:", prop["src"])
        return None

    # Свариваем в один объект. У стула их было двенадцать — это двенадцать
    # узлов и столько же вызовов отрисовки на предмет мебели.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = prop["name"]
    obj.data.name = prop["name"]

    # Отвязываем от родителя, сохраняя вид, и запекаем весь трансформ. У FBX
    # сверху обычно висит пустышка со стократным масштабом (сантиметры против
    # метров); transform_apply применяет только свой масштаб, родительский
    # остаётся — фонарь из-за этого вышел высотой в четыреста шестьдесят метров.
    if obj.parent is not None:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Режем с проверкой результата, а не одним расчётом. Decimate считает долю
    # по граням, а триангуляция после него добавляет треугольники сверху — с
    # одного прохода стул промахивался мимо бюджета почти вдвое.
    before = count_tris()
    for _ in range(4):
        current = count_tris()
        if current <= prop["budget"] * 1.05:
            break
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.01, float(prop["budget"]) / current)
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    after = count_tris()

    # масштаб: генератор нормирует модель в единицу высоты
    lo, hi = bounds()
    tall = max(0.0001, hi[2] - lo[2])
    scale = prop["height"] / tall
    obj.scale = (scale, scale, scale)
    bpy.ops.object.transform_apply(scale=True)

    # начало координат — в центр по горизонтали и на пол по высоте
    lo, hi = bounds()
    obj.location = (obj.location.x - (lo[0] + hi[0]) / 2,
                    obj.location.y - (lo[1] + hi[1]) / 2,
                    obj.location.z - lo[2])
    bpy.ops.object.transform_apply(location=True)

    cap_textures(prop.get("texture", 1024))

    lo, hi = bounds()
    print("### %-6s треугольников %d -> %d (бюджет %d), габариты %.2f x %.2f x %.2f м"
          % (prop["name"], before, after, prop["budget"],
             hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
    print("###        низ на z=%.3f (должен быть 0)" % lo[2])
    return obj


def main():
    for prop in PROPS:
        obj = prepare(prop)
        if obj is None:
            continue
        # коллизию Godot соберёт сам по суффиксу; для мебели выпуклой хватает
        obj.name = prop["name"] + "-convcol"
        obj.data.name = obj.name
        path = os.path.join(OUT_DIR, prop["name"] + ".glb")
        export_glb([obj], path)
        render_previews(views={"view": (2.2, -2.6, 1.9)},
                        target=(0, 0, prop["height"] * 0.45),
                        out_dir=OUT_RENDER, prefix=prop["name"], lens=45)


if __name__ == "__main__":
    main()
