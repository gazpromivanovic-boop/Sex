extends CanvasLayer
## Подсказки по управлению и текущее состояние камеры.

const HINTS := """[Управление]
WASD — движение
Shift — бег вперёд
Пробел — прыжок
ПКМ — режим прицела (страйф)
C — сесть / лечь, Shift — встать
V — первое / третье лицо
Q — сменить плечо
Колесо — приблизить камеру
B — колесо эмоций, 1-9 — быстрые
Esc — курсор / выход"""

@onready var hints: Label = $Panel/Hints
@onready var status: Label = $Status

## Показывать вместо скорости пару «текущая / целевая» и счётчик ступенек.
## Включается, когда движение ведёт себя не так, как ожидалось.
@export var show_diagnostics: bool = false

var player: Node = null
var emote_title: String = ""
var pose_title: String = ""


func _ready() -> void:
	hints.text = HINTS
	hints.add_theme_font_size_override("font_size", 15)
	status.add_theme_font_size_override("font_size", 16)
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		player = get_parent().get_node_or_null("Player")
	if player != null and player.has_signal("emote_changed"):
		player.emote_changed.connect(_on_emote_changed)
	if player != null and player.has_signal("pose_changed"):
		player.pose_changed.connect(_on_pose_changed)


func _on_emote_changed(id: String) -> void:
	emote_title = ""
	if id == "":
		return
	for e in player.EMOTES:
		if e["id"] == id:
			emote_title = str(e["title"])
			return
	emote_title = id


func _on_pose_changed(title: String) -> void:
	pose_title = title


func _process(_delta: float) -> void:
	if player == null:
		return
	var view := "от первого лица" if player.first_person else "от третьего лица"
	var mode := "прицел" if player.aiming else "свободный"
	var text := "%s · %s\n%.1f м/с" % [view, mode, player.get_horizontal_speed()]
	if show_diagnostics:
		# вторым числом идёт цель разгона: если скорость её обгоняет, значит
		# энергию кто-то добавляет — по этой паре видно, где именно
		text = "%s · %s\n%.2f / %.2f м/с · ступеней %d" % [
			view, mode, player.get_horizontal_speed(), player.target_speed, player.step_count]
	if player.emoting:
		text = "эмоция: %s\nShift — прекратить" % emote_title
	elif player.posing:
		text = "%s\nC — сменить позу, Shift — встать" % pose_title
	status.text = text
