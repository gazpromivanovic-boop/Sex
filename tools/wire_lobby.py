# -*- coding: utf-8 -*-
"""Досборка scenes/lobby.tscn: океан, разброс, ряды, реквизит, свет и звук.

Почему скриптом, а не руками в редакторе. Открытый Godot держит сцену в памяти
и при своём сохранении откатывает файл к этой копии — правки .tscn текстом
пропадают молча, вместе со всем, что было добавлено с момента открытия. Скрипт
идемпотентен: сначала выкусывает всё, чем управляет, потом вписывает заново.
После отката достаточно закрыть редактор и запустить его ещё раз.

    python tools/wire_lobby.py

Добавить свой узел — дописать блок в NODES. Всё, что там перечислено, считается
собственностью скрипта: правки этих узлов в редакторе он затрёт.
"""

import io
import os
import re

SCENE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                     "scenes", "lobby.tscn")

# (id, тип, путь). Идентификаторы держим в своём диапазоне, чтобы не столкнуться
# с теми, что раздаёт редактор.
EXT = [
    ("20_scatter", "Script", "res://scripts/scatter.gd"),
    ("30_row", "Script", "res://scripts/row.gd"),
    ("36_snap", "Script", "res://scripts/ground_snap.gd"),
    ("21_ra", "PackedScene", "res://assets/models/rock_a.glb"),
    ("22_rb", "PackedScene", "res://assets/models/rock_b.glb"),
    ("23_rc", "PackedScene", "res://assets/models/rock_c.glb"),
    ("24_rd", "PackedScene", "res://assets/models/rock_d.glb"),
    ("25_log", "PackedScene", "res://assets/models/log.glb"),
    ("33_logb", "PackedScene", "res://assets/models/log_b.glb"),
    ("26_gp", "PackedScene", "res://assets/models/grass_patch.glb"),
    ("27_gd", "PackedScene", "res://assets/models/grass_dry.glb"),
    ("28_lamp", "PackedScene", "res://assets/models/lamp.glb"),
    ("29_tile", "PackedScene", "res://assets/models/tile.glb"),
    ("35_cchair", "PackedScene", "res://assets/models/cover_chair.glb"),
    ("34_sea", "AudioStream", "res://assets/audio/sea_gulls.mp3"),
    ("37_ocean", "Script", "res://addons/ocean3d_lite/ocean_surface.gd"),
    ("38_waves", "Resource", "res://assets/water/bay_waves.tres"),
    ("39_grade", "Compositor", "res://scenes/grade.tres"),
    ("40_skin", "Script", "res://scripts/ocean_skin.gd"),
    ("41_wshader", "Shader", "res://assets/shaders/ocean_bay.gdshader"),
    ("42_wnormal", "Texture2D", "res://assets/water/EA_Water_Normal.tres"),
    ("43_mist", "Script", "res://scripts/haze.gd"),
    ("44_under", "Script", "res://scripts/underwater.gd"),
    ("45_swim", "Script", "res://scripts/swimmer.gd"),
    ("46_turtle", "PackedScene", "res://assets/models/turtle.glb"),
    ("47_manta", "PackedScene", "res://assets/models/manta.glb"),
    ("48_preview", "Script", "res://scripts/ocean_preview.gd"),
]

NODES = """
[node name="Ocean" type="Node3D" parent="."]
script = ExtResource("37_ocean")
wave_profile = ExtResource("38_waves")
tile_size = 260.0
disp_fade_start = 90.0
disp_fade_end = 126.0
far_size = 9000.0
fair_deep_color = Color(0.02, 0.11, 0.18, 1)
fair_shallow_color = Color(0.13, 0.42, 0.46, 1)
fair_roughness = 0.1

[node name="OceanSkin" type="Node" parent="Ocean"]
script = ExtResource("40_skin")
shader = ExtResource("41_wshader")
normal_map = ExtResource("42_wnormal")
shallow_color = Color(0.44, 0.82, 0.86, 0.55)
deep_color = Color(0.1, 0.3, 0.5, 0.93)
shore_glow_color = Color(0.94, 0.98, 1, 1)
foam_color = Color(0.97, 0.99, 1, 1)
underwater_color = Color(0.05, 0.24, 0.32, 0.72)
water_depth = 4.0
color_bands = 4
foam_cutoff = 0.55
caustics_strength = 0.22
sparkle_boost = 0.25

[node name="OceanPreview" type="Node" parent="Ocean"]
script = ExtResource("48_preview")
shader = ExtResource("41_wshader")
wave_profile = ExtResource("38_waves")
skin_path = NodePath("../OceanSkin")
size = 230.0
subdiv = 120

[node name="ShoreMist" type="GPUParticles3D" parent="."]
position = Vector3(0, 0.5, 2)
script = ExtResource("43_mist")
span = Vector2(150, 22)
height = 3.5
count = 44
life = 18.0
mist_color = Color(0.88, 0.74, 0.68, 0.09)
puff_size = Vector2(6, 15)
drift = Vector3(0.35, 0.05, 0.12)

[node name="Motes" type="GPUParticles3D" parent="."]
position = Vector3(0, -4.5, 52)
script = ExtResource("43_mist")
span = Vector2(130, 95)
height = 7.0
count = 240
life = 26.0
mist_color = Color(0.72, 0.88, 0.88, 0.055)
puff_size = Vector2(0.05, 0.22)
drift = Vector3(0.05, 0.1, -0.04)

[node name="Reef" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("21_ra"), ExtResource("22_rb"), ExtResource("23_rc"), ExtResource("24_rd")])
count = 26
seed_value = 7710
area = Vector2(150, 95)
area_center = Vector3(0, 0, 50)
min_height = -9.5
max_height = -1.2
scale_range = Vector2(0.5, 2.2)
sink = 0.25
tilt_deg = 16.0
collision = false

[node name="Manta" parent="." instance=ExtResource("47_manta")]
transform = Transform3D(0.55, 0, 0, 0, 0.55, 0, 0, 0, 0.55, 0, -4.2, 58)
script = ExtResource("45_swim")
radius = Vector2(26, 17)
period = 46.0
tilt_deg = 6.0
bob = 0.9
bob_period = 17.0
bank_deg = 10.0
facing_offset_deg = 180.0

[node name="TurtleA" parent="." instance=ExtResource("46_turtle")]
transform = Transform3D(0.45, 0, 0, 0, 0.45, 0, 0, 0, 0.45, -16, -2.6, 42)
script = ExtResource("45_swim")
radius = Vector2(11, 7)
period = 27.0
phase = 0.15
facing_offset_deg = 180.0

[node name="TurtleB" parent="." instance=ExtResource("46_turtle")]
transform = Transform3D(0.38, 0, 0, 0, 0.38, 0, 0, 0, 0.38, 15, -3.4, 54)
script = ExtResource("45_swim")
radius = Vector2(9, 13)
period = 32.0
phase = 0.6
tilt_deg = 11.0
facing_offset_deg = 180.0

[node name="TurtleC" parent="." instance=ExtResource("46_turtle")]
transform = Transform3D(0.5, 0, 0, 0, 0.5, 0, 0, 0, 0.5, -4, -5.6, 70)
script = ExtResource("45_swim")
radius = Vector2(15, 10)
period = 38.0
phase = 0.35
tilt_deg = 5.0
bob = 1.2
facing_offset_deg = 180.0

[node name="Underwater" type="Node" parent="."]
script = ExtResource("44_under")
world_environment = NodePath("../WorldEnvironment")
fog_color = Color(0.05, 0.21, 0.27, 1)
fog_density = 0.11

[node name="Boards" type="Node3D" parent="Level"]
position = Vector3(0, 0.39, -7)
script = ExtResource("30_row")
scene = ExtResource("29_tile")
count = 26
spacing = 1.07
base_rotation = Vector3(0, 90, 0)
collision = false

[node name="LampA" parent="Level" instance=ExtResource("28_lamp")]
position = Vector3(2.15, 0.55, 2)
rotation = Vector3(0, -1.570796, 0)

[node name="LampB" parent="Level" instance=ExtResource("28_lamp")]
position = Vector3(2.15, 0.55, 14)
rotation = Vector3(0, -1.570796, 0)

[node name="LampGlowA" type="OmniLight3D" parent="Level/LampA"]
position = Vector3(0, 4.25, 0)
light_color = Color(1, 0.83, 0.58, 1)
light_energy = 3.2
light_specular = 0.3
shadow_enabled = true
omni_range = 13.0
omni_attenuation = 1.6

[node name="LampGlowB" type="OmniLight3D" parent="Level/LampB"]
position = Vector3(0, 4.25, 0)
light_color = Color(1, 0.83, 0.58, 1)
light_energy = 3.2
light_specular = 0.3
shadow_enabled = true
omni_range = 13.0
omni_attenuation = 1.6

[node name="Rocks" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("21_ra"), ExtResource("22_rb"), ExtResource("23_rc"), ExtResource("24_rd")])
count = 14
seed_value = 4471
area = Vector2(116, 46)
area_center = Vector3(0, 0, -24)
min_height = -0.85
max_height = 0.95
scale_range = Vector2(0.35, 1.2)
sink = 0.32

[node name="Pebbles" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("21_ra"), ExtResource("22_rb"), ExtResource("24_rd")])
count = 40
seed_value = 6120
area = Vector2(118, 22)
area_center = Vector3(0, 0, -8)
min_height = -1.05
max_height = 1.15
scale_range = Vector2(0.05, 0.16)
sink = 0.04
collision = false

[node name="Logs" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("25_log"), ExtResource("33_logb")])
count = 5
seed_value = 8812
area = Vector2(100, 34)
area_center = Vector3(0, 0, -26)
min_height = 0.65
max_height = 2.15
scale_range = Vector2(0.7, 1.3)
tilt_deg = 6.0

[node name="Grass" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("26_gp"), ExtResource("27_gd")])
count = 60
seed_value = 3305
area = Vector2(112, 40)
area_center = Vector3(0, 0, -28)
min_height = 1.25
max_height = 9.55
scale_range = Vector2(0.35, 0.8)
sink = 0.06
collision = false
tilt_deg = 5.0

[node name="CoverChairPier" parent="Level" instance=ExtResource("35_cchair")]
position = Vector3(-1.5, 0.7, 12.6)
rotation = Vector3(0, 0.13, 0)
script = ExtResource("36_snap")

[node name="CoverChairA" parent="Level" instance=ExtResource("35_cchair")]
position = Vector3(-12.5, 1, -24.5)
rotation = Vector3(0, -0.436332, 0)
script = ExtResource("36_snap")
align_to_normal = true

[node name="CoverChairB" parent="Level" instance=ExtResource("35_cchair")]
position = Vector3(-9, 1, -25.8)
rotation = Vector3(0, 0.523599, 0)
script = ExtResource("36_snap")
align_to_normal = true
"""

# Убрать из сцены и не возвращать. Water и WaterFar заменил океан, забор убран
# по просьбе: ряд каменных секций читался цепочкой валунов.
DROP = {"Water", "WaterFar", "Fence", "FenceRuins"}

# Замены отдельных строк, до которых секционному разбору не дотянуться: у
# подресурсов нет имени, а материал песка знает уровень воды, и он переехал.
REPLACE = [
    ("shader_parameter/water_level = -0.55", "shader_parameter/water_level = 0.0"),
]

# Правки узлов, которые скрипту не принадлежат: их держит редактор, мы лишь
# дописываем свойства.
PATCH = {
    "WorldEnvironment": {
        "props": [("compositor", 'ExtResource("39_grade")')],
    },
    # Ocean3D жёстко держит море на мировом нуле — таково его условие. Чтобы
    # береговая линия осталась там же, где была, поднимаем на 0.55 не воду, а
    # весь уровень: раньше вода стояла ровно настолько ниже нуля рельефа.
    "Level": {
        "props": [("transform",
                   "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.55, 0)")],
    },
    "Ambience": {
        # Синтезированные крики больше не нужны: их закрывает живая запись.
        "props": [("bed", 'ExtResource("34_sea")')],
        "drop": ["gulls"],
    },
}


def parse(text):
    """Разбирает .tscn на шапку и секции.

    Формат построчный: секция начинается со строки в квадратных скобках, всё до
    следующей такой — её тело. Полноценный разбор тут не нужен и вреден: он
    переписал бы весь файл по-своему, а хочется трогать только своё.
    """
    head, blocks, cur = [], [], None
    for line in text.split("\n"):
        if line.startswith("["):
            if cur is not None:
                blocks.append(cur)
            cur = [line, []]
        elif cur is not None:
            cur[1].append(line)
        else:
            head.append(line)
    if cur is not None:
        blocks.append(cur)
    return head, blocks


def node_name(header):
    match = re.match(r'\[node name="([^"]+)"', header)
    return match.group(1) if match else None


def attr(header, key):
    match = re.search(r'%s="([^"]+)"' % key, header)
    return match.group(1) if match else None


def _without(body, key):
    return [l for l in body if not re.match(r"^%s\s*=" % re.escape(key), l)]


def main():
    head, blocks = parse(io.open(SCENE, encoding="utf-8").read())

    mine_ids = set(ident for ident, _, _ in EXT)
    mine_paths = set(path for _, _, path in EXT)
    mine_nodes = set(re.findall(r'\[node name="([^"]+)"', NODES))

    kept = []
    for header, body in blocks:
        if header.startswith("[ext_resource"):
            if attr(header, "id") in mine_ids or attr(header, "path") in mine_paths:
                continue
        elif re.sub(r"\d+$", "", node_name(header) or "") in mine_nodes | DROP:
            # Редактор дописывает цифру к имени при столкновении: CoverChairA2.
            # Такой хвост — тоже наш узел, иначе дубли копятся в сцене.
            continue
        kept.append([header, body])

    for block in kept:
        rule = PATCH.get(node_name(block[0]))
        if rule is None:
            continue
        for group in rule.get("groups", []):
            if "groups=" not in block[0]:
                block[0] = block[0][:-1] + ' groups=["%s"]]' % group
        for key in rule.get("drop", []):
            block[1] = _without(block[1], key)
        for key, value in rule.get("props", []):
            block[1] = _without(block[1], key)
            filled = [i for i, line in enumerate(block[1]) if line.strip()]
            block[1].insert(filled[-1] + 1 if filled else 0,
                            "%s = %s" % (key, value))

    last_ext = max(i for i, block in enumerate(kept)
                   if block[0].startswith("[ext_resource"))
    out = list(head)
    for i, (header, body) in enumerate(kept):
        out.append(header)
        out.extend(body)
        if i == last_ext:
            for ident, kind, path in EXT:
                out.append('[ext_resource type="%s" path="%s" id="%s"]'
                           % (kind, path, ident))
            out.append("")

    text = "\n".join(out).rstrip("\n") + "\n" + NODES
    for old, new in REPLACE:
        text = text.replace(old, new)
    io.open(SCENE, "w", encoding="utf-8", newline="").write(text)
    print("вписано: ресурсов %d, узлов %d" % (len(EXT), len(mine_nodes)))


if __name__ == "__main__":
    main()
