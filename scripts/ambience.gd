class_name Ambience
extends Node3D
## Звуковая подложка сцены: прибой, ветер и редкие чайки.
##
## Прибой и ветер — непозиционные: они окружают, а не доносятся из точки. Чайки
## наоборот, каждая кричит из своего места над водой, иначе стая слышится одним
## пятном в центре головы.
##
## Зацикливание ставится кодом, а не в настройках импорта. У .wav флаг петли
## живёт в файле импорта, его легко потерять при переимпорте, и подложка тогда
## играет один раз и замолкает — тихо и не сразу заметно.
##
## Звуки синтезированы (tools/make_ambience.py). Прибой держится достойно, а
## чайки слышно, что ненастоящие: это заглушка под запись с нормальной лицензией.

@export var surf: AudioStream
@export var wind: AudioStream
@export var gulls: Array[AudioStream] = []

@export_group("Громкость, дБ")
@export var surf_db: float = -8.0
@export var wind_db: float = -20.0
@export var gull_db: float = -6.0

@export_group("Чайки")
## Пауза между криками, от и до, секунд.
@export var gull_pause: Vector2 = Vector2(7.0, 22.0)
## На каком расстоянии вокруг слушателя они появляются.
@export var gull_radius: Vector2 = Vector2(12.0, 45.0)
@export var gull_height: Vector2 = Vector2(6.0, 20.0)
## Вокруг кого летают. Пусто — вокруг самого узла.
@export_node_path("Node3D") var listener: NodePath

var _listener: Node3D
var _timer: float = 0.0


func _ready() -> void:
	_listener = self
	if not listener.is_empty():
		var found := get_node_or_null(listener) as Node3D
		if found != null:
			_listener = found

	_start_bed(surf, surf_db, "Surf")
	_start_bed(wind, wind_db, "Wind")
	_timer = randf_range(gull_pause.x, gull_pause.y)


## Непрерывный слой: играет всегда и отовсюду.
func _start_bed(stream: AudioStream, volume: float, name: String) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = name
	player.stream = _looped(stream)
	player.volume_db = volume
	player.autoplay = true
	add_child(player)
	player.play()


## Ставит петлю прямо в потоке. См. примечание в шапке — на настройки импорта
## тут полагаться нельзя.
func _looped(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate() as AudioStream
	if copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 4      # 16 бит стерео: 4 байта на кадр
	elif copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	return copy


func _process(delta: float) -> void:
	if gulls.is_empty():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(gull_pause.x, gull_pause.y)
	_cry()


func _cry() -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = gulls[randi() % gulls.size()]
	player.volume_db = gull_db
	player.unit_size = 18.0
	player.max_distance = 120.0
	add_child(player)

	var angle := randf() * TAU
	var dist := randf_range(gull_radius.x, gull_radius.y)
	player.global_position = _listener.global_position + Vector3(
		cos(angle) * dist, randf_range(gull_height.x, gull_height.y), sin(angle) * dist)
	player.finished.connect(player.queue_free)
	player.play()
