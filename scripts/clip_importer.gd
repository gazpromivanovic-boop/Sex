class_name ClipImporter
extends RefCounted
## Переносит анимацию из отдельно импортированного файла в скелет персонажа.
##
## Зачем: клип, скачанный с Mixamo и положенный в проект как есть, к нашей модели
## сам не встанет. Godot импортирует его со своим скелетом, дорожки в нём
## называют кости по путям вида «Armature/Skeleton3D:mixamorig:Hips», а в
## player.glb префикс `mixamorig:` при сборке срезан, и путь к скелету другой.
## Плюс исходник Mixamo лежит в сантиметрах, а модель нормализована под 1.8 м:
## дорожки поворотов от масштаба не зависят, а вот смещение таза — зависит, и
## без пересчёта персонажа разорвёт.
##
## Поэтому клип переносится, а не подключается: пути дорожек переписываются на
## наш скелет, смещения масштабируются по отношению ростов двух ригов, а кости,
## которых у нас нет, выбрасываются.
##
## Использование:
##     ClipImporter.add_clip(anim_player, skeleton,
##         load("res://assets/animations/sitting_idle.fbx"), "SitIdle")

## Префиксы имён костей, которые срезаются при переносе.
const BONE_PREFIXES := ["mixamorig:", "mixamorig1:", "mixamorig_"]


## Кладёт первую анимацию из scene в библиотеку target под именем clip_name.
## Возвращает true, если клип добавлен.
static func add_clip(target: AnimationPlayer, skeleton: Skeleton3D,
		scene: PackedScene, clip_name: String, loop := true) -> bool:
	if target == null or skeleton == null or scene == null:
		push_warning("ClipImporter: не хватает целей для переноса «%s»." % clip_name)
		return false
	if target.has_animation(clip_name):
		return true                       # уже перенесли

	var probe := scene.instantiate()
	var source: Animation = null
	var source_skeleton: Skeleton3D = null
	var players := probe.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		var names := player.get_animation_list()
		for n in names:
			# RESET — служебный клип позы покоя, он нам не нужен
			if n != "RESET":
				source = player.get_animation(n)
				break
	var skeletons := probe.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		source_skeleton = skeletons[0]

	if source == null:
		push_warning("ClipImporter: в файле для «%s» нет анимации." % clip_name)
		probe.queue_free()
		return false

	var scale := _rig_scale(source_skeleton, skeleton)
	var bone_path := _bone_track_prefix(target)
	var clip := _retarget(source, source_skeleton, skeleton, bone_path, scale)
	probe.queue_free()

	if clip.get_track_count() == 0:
		push_warning("ClipImporter: ни одна дорожка «%s» не легла на скелет." % clip_name)
		return false
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var library := target.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		target.add_animation_library("", library)
	library.add_animation(clip_name, clip)
	return true


## Во сколько раз исходный риг крупнее нашего. Считаем по высоте таза в позе
## покоя: это единственная величина, которая есть у обоих скелетов и не зависит
## от того, в каких единицах экспортировали файл.
static func _rig_scale(source: Skeleton3D, target: Skeleton3D) -> float:
	if source == null:
		return 1.0
	var from := _rest_height(source)
	var to := _rest_height(target)
	if from <= 0.0001 or to <= 0.0001:
		return 1.0
	return to / from


static func _rest_height(skeleton: Skeleton3D) -> float:
	var top := 0.0
	for b in skeleton.get_bone_count():
		top = maxf(top, absf(skeleton.get_bone_global_rest(b).origin.y))
	return top


## Путь к скелету в том виде, в каком его пишут уже готовые клипы персонажа.
## Берём из них, а не строим сами: у AnimationTree свой корень, и промахнуться
## тут проще, чем кажется.
static func _bone_track_prefix(target: AnimationPlayer) -> String:
	for name in target.get_animation_list():
		var anim := target.get_animation(name)
		for i in anim.get_track_count():
			if anim.track_get_type(i) in [Animation.TYPE_POSITION_3D,
					Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				return str(NodePath(anim.track_get_path(i)).get_concatenated_names())
	return ""


## Позиции переносятся не как есть, а как смещение от позы покоя: у двух ригов
## таз стоит на разной высоте и в разных единицах, и абсолютное значение оттуда
## сюда не годится — персонаж уезжает под пол. Берём, насколько кость сдвинулась
## относительно своего покоя в исходнике, пересчитываем в наш масштаб и
## прикладываем к нашему покою.
static func _retarget(source: Animation, from_skeleton: Skeleton3D, skeleton: Skeleton3D,
		bone_path: String, scale: float) -> Animation:
	var clip: Animation = source.duplicate(true)
	for i in range(clip.get_track_count() - 1, -1, -1):
		var kind := clip.track_get_type(i)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
				Animation.TYPE_SCALE_3D]:
			clip.remove_track(i)          # дорожки мешей и материалов нам не нужны
			continue

		var raw := NodePath(clip.track_get_path(i)).get_concatenated_subnames()
		var bone := _clean_bone(str(raw))
		var target_bone := skeleton.find_bone(bone)
		if target_bone < 0:
			clip.remove_track(i)          # такой кости у нас нет
			continue
		clip.track_set_path(i, NodePath("%s:%s" % [bone_path, bone]))

		if kind == Animation.TYPE_POSITION_3D:
			var here := skeleton.get_bone_rest(target_bone).origin
			var there := Vector3.ZERO
			if from_skeleton != null:
				var source_bone := from_skeleton.find_bone(str(raw))
				if source_bone < 0:
					source_bone = from_skeleton.find_bone(bone)
				if source_bone >= 0:
					there = from_skeleton.get_bone_rest(source_bone).origin
			for k in clip.track_get_key_count(i):
				var v: Vector3 = clip.track_get_key_value(i, k)
				clip.track_set_key_value(i, k, here + (v - there) * scale)
	return clip


static func _clean_bone(name: String) -> String:
	for prefix in BONE_PREFIXES:
		if name.begins_with(prefix):
			return name.substr(prefix.length())
	return name
