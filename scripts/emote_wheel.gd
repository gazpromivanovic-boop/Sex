extends Control
## Колесо эмоций — как в Fortnite: удерживаешь клавишу, ведёшь мышью в сторону
## нужного сектора, отпускаешь — эмоция запускается.
##
## Рисуется кодом, без картинок: кольцо, разделённое на сектора по числу эмоций,
## подсвечивается тот, в сторону которого уведена мышь.

signal emote_chosen(id: String)

## Список эмоций приходит от игрока: [{id = "EmoteHipHop", title = "Хип-хоп"}, ...]
var emotes: Array = []

@export var radius_outer: float = 190.0
@export var radius_inner: float = 78.0
@export var dead_zone: float = 34.0
@export var open_time: float = 0.12

var opened: bool = false
var hovered: int = -1
var _anim: float = 0.0            ## 0..1 — раскрытие колеса
var _pointer: Vector2 = Vector2.ZERO

const COL_BG := Color(0.06, 0.09, 0.11, 0.72)
const COL_SECTOR := Color(0.16, 0.20, 0.23, 0.82)
const COL_HOVER := Color(0.18, 0.56, 0.56, 0.95)
const COL_LINE := Color(1, 1, 1, 0.10)
const COL_TEXT := Color(0.88, 0.93, 0.95)
const COL_TEXT_DIM := Color(0.62, 0.70, 0.74)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func open() -> void:
	if opened or emotes.is_empty():
		return
	opened = true
	visible = true
	hovered = -1
	_pointer = Vector2.ZERO
	set_process(true)


## Закрывает колесо. Возвращает id выбранной эмоции или пустую строку.
func close_and_pick() -> String:
	if not opened:
		return ""
	opened = false
	var id := ""
	if hovered >= 0 and hovered < emotes.size():
		id = str(emotes[hovered]["id"])
		emote_chosen.emit(id)
	return id


## Мышь двигает указатель внутри колеса, а не камеру.
func handle_motion(relative: Vector2) -> void:
	if not opened:
		return
	_pointer += relative
	if _pointer.length() > radius_outer:
		_pointer = _pointer.normalized() * radius_outer
	_update_hover()


func _update_hover() -> void:
	if _pointer.length() < dead_zone:
		hovered = -1
		return
	var count := emotes.size()
	var step := TAU / float(count)
	# 0-й сектор смотрит вверх, дальше по часовой стрелке
	var angle := wrapf(atan2(_pointer.x, -_pointer.y) + step * 0.5, 0.0, TAU)
	hovered = int(angle / step) % count


func _process(delta: float) -> void:
	var target := 1.0 if opened else 0.0
	_anim = move_toward(_anim, target, delta / maxf(open_time, 0.001))
	if not opened and is_equal_approx(_anim, 0.0):
		visible = false
		set_process(false)
	queue_redraw()


func _draw() -> void:
	# на самом старте раскрытия радиусы почти нулевые — полигон вырождается
	if emotes.is_empty() or _anim <= 0.02:
		return
	# центр берём у вьюпорта, а не у своего прямоугольника: под CanvasLayer
	# размер Control'а не всегда совпадает с экраном
	var center := get_viewport_rect().size * 0.5
	if center.x < 1.0:
		return
	var k: float = ease(_anim, 0.35)
	var r_out := radius_outer * k
	var r_in := radius_inner * k
	var count := emotes.size()
	var step := TAU / float(count)
	var font := ThemeDB.fallback_font
	var fsize := 15

	draw_circle(center, r_out + 10.0 * k, COL_BG)

	for i in count:
		var a0 := -step * 0.5 + step * i - PI * 0.5
		var a1 := a0 + step
		var is_hot := i == hovered
		_draw_sector(center, r_in, r_out, a0, a1, COL_HOVER if is_hot else COL_SECTOR)

		var mid := (a0 + a1) * 0.5
		var text_r := (r_in + r_out) * 0.5
		var pos := center + Vector2(cos(mid), sin(mid)) * text_r
		var title: String = str(emotes[i].get("title", emotes[i]["id"]))
		var num := str(i + 1)
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, pos + Vector2(-tw * 0.5, 2), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, COL_TEXT if is_hot else COL_TEXT_DIM)
		var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, pos + Vector2(-nw * 0.5, 20), num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_TEXT_DIM)

	draw_arc(center, r_in, 0.0, TAU, 64, COL_LINE, 1.5, true)
	draw_arc(center, r_out, 0.0, TAU, 96, COL_LINE, 1.5, true)

	# указатель
	if _pointer.length() > 1.0:
		draw_line(center, center + _pointer.limit_length(r_out), COL_HOVER, 2.0, true)
	draw_circle(center + _pointer.limit_length(r_out), 4.0, COL_TEXT)

	var hint := "отпусти — запустить, Shift — прекратить"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, center + Vector2(-hw * 0.5, r_out + 34.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_TEXT_DIM)


func _draw_sector(center: Vector2, r_in: float, r_out: float,
		a0: float, a1: float, color: Color) -> void:
	if r_out - r_in < 1.0:
		return
	var steps := 12
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a: float = lerpf(a0, a1, float(i) / steps)
		pts.append(center + Vector2(cos(a), sin(a)) * r_out)
	for i in range(steps, -1, -1):
		var a: float = lerpf(a0, a1, float(i) / steps)
		pts.append(center + Vector2(cos(a), sin(a)) * r_in)
	draw_colored_polygon(pts, color)
