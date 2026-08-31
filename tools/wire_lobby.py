# -*- coding: utf-8 -*-
"""Досборка scenes/lobby.tscn: разброс, ряды, реквизит, прилив и звук.

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
    ("31_tide", "Script", "res://scripts/tide.gd"),
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
    ("32_fence", "PackedScene", "res://assets/models/fence.glb"),
    ("35_cchair", "PackedScene", "res://assets/models/cover_chair.glb"),
    ("34_sea", "AudioStream", "res://assets/audio/sea_gulls.mp3"),
]

NODES = """
[node name="Boards" type="Node3D" parent="Level"]
position = Vector3(0, 0.52, -7)
script = ExtResource("30_row")
scene = ExtResource("29_tile")
count = 26
spacing = 1.07
base_rotation = Vector3(0, 90, 0)

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
min_height = -1.4
max_height = 0.4
scale_range = Vector2(0.35, 1.2)

[node name="Pebbles" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("21_ra"), ExtResource("22_rb"), ExtResource("24_rd")])
count = 40
seed_value = 6120
area = Vector2(118, 22)
area_center = Vector3(0, 0, -8)
min_height = -1.6
max_height = 0.6
scale_range = Vector2(0.05, 0.16)
sink = 0.04

[node name="Logs" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("25_log"), ExtResource("33_logb")])
count = 5
seed_value = 8812
area = Vector2(100, 34)
area_center = Vector3(0, 0, -26)
min_height = 0.1
max_height = 1.6
scale_range = Vector2(0.7, 1.3)
tilt_deg = 6.0

[node name="Grass" type="Node3D" parent="Level"]
script = ExtResource("20_scatter")
scenes = Array[PackedScene]([ExtResource("26_gp"), ExtResource("27_gd")])
count = 60
seed_value = 3305
area = Vector2(112, 40)
area_center = Vector3(0, 0, -28)
min_height = 0.7
max_height = 9.0
scale_range = Vector2(0.35, 0.8)
sink = 0.06
tilt_deg = 5.0

[node name="Fence" type="Node3D" parent="Level"]
position = Vector3(-27, 0, -34)
rotation = Vector3(0, 0.261799, 0)
script = ExtResource("30_row")
scene = ExtResource("32_fence")
count = 9
spacing = 2.82
base_rotation = Vector3(0, 90, 0)
snap_to_ground = true
jitter = Vector2(0.12, 0.06)
yaw_jitter = 5.0
roll_jitter = 3.0

[node name="FenceRuins" type="Node3D" parent="Level"]
position = Vector3(21, 0, -31)
rotation = Vector3(0, -0.610865, 0)
script = ExtResource("30_row")
scene = ExtResource("32_fence")
count = 4
spacing = 3.6
base_rotation = Vector3(0, 90, 0)
snap_to_ground = true
jitter = Vector2(0.4, 0.1)
yaw_jitter = 14.0
roll_jitter = 9.0

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

# Правки узлов, которые скрипту не принадлежат: их держит редактор, мы лишь
# дописываем свойства.
PATCH = {
    "Water": {
        "groups": ["water"],
        "props": [("script", 'ExtResource("31_tide")'),
                  ("far_water", 'NodePath("../WaterFar")')],
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
        elif re.sub(r"\d+$", "", node_name(header) or "") in mine_nodes:
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

    io.open(SCENE, "w", encoding="utf-8", newline="").write(
        "\n".join(out).rstrip("\n") + "\n" + NODES)
    print("вписано: ресурсов %d, узлов %d" % (len(EXT), len(mine_nodes)))


if __name__ == "__main__":
    main()
