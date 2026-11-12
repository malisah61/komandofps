extends Control
## Ekran: nisangah, fark edilme gostergesi (asker yonunu gosteren oklar), can/silah, gorevler,
## alarm bandi, etkilesim yazisi, bildirimler, diyalog, menuler ve Android dokunmatik kontroller.

const WEAPON_NAMES := ["Bıçak", "Yumruk", "Tabanca", "Taş"]

var main
var shake := 0.0
var hold_progress := 0.0
var timer_text := ""
var touch_run := false
var touch_use_held := false

var _toasts: Array = []            # [metin, kalan]
var _dialog: Array = []            # [[konusan, metin], ...]
var _dialog_t := 0.0
var _alarm := ""
var _map := false
var _font: Font
var _menu: Control
var _pause: Control
var _end: Control
var _loading: Label
var _brief := ""
var _brief_t := 0.0
var _level_name := ""

# dokunmatik
var _mobile := false
var _stick_id := -1
var _stick_c := Vector2.ZERO
var _stick_p := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _btns := {}                    # ad -> Rect2
var _btn_ids := {}                 # dokunus id -> ad


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_mobile = main.is_mobile()
	_loading = Label.new()
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.add_theme_font_size_override("font_size", 32)
	_loading.visible = false
	add_child(_loading)


# ---------------- menuler ----------------
func _panel(title: String) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.05, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	cc.add_child(vb)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	return vb


func _button(vb: Container, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(460, 54 if not _mobile else 70)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	vb.add_child(b)
	return b


func show_menu() -> void:
	hide_menu()
	var vb := _panel("KOMANDO FPS")
	_menu = vb.get_parent().get_parent()
	var sub := Label.new()
	sub.text = "Birinci şahıs gizlilik – Komando bölümleri"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.8, 0.85, 0.75)
	vb.add_child(sub)
	for i in main.LEVELS.size():
		var path: String = main.LEVELS[i]
		var nm := "Bölüm %d" % i
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				nm = str(d.get("name", nm))
		_button(vb, nm, func(): main.start_level(path))
	var help := Label.new()
	help.text = ("Sol: yürü  •  Sağ: bak  •  Düğmeler: ateş / etkileşim / çömel / koş / harita" if _mobile
		else "WASD yürü • Fare bak • Sol tık silah • E / sağ tık etkileşim • C çömel • Shift koş\n1-4 silah • Z ıslık • H ilk yardım • TAB taktik harita • ESC duraklat")
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.7, 0.75, 0.7)
	vb.add_child(help)
	if not _mobile:
		_button(vb, "Çıkış", func(): get_tree().quit())


func hide_menu() -> void:
	for n in [_menu, _end, _pause]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_menu = null
	_end = null
	_pause = null


func show_loading(t: String) -> void:
	_loading.text = t
	_loading.visible = true


func hide_loading() -> void:
	_loading.visible = false


func show_pause(on: bool) -> void:
	if _pause != null and is_instance_valid(_pause):
		_pause.queue_free()
		_pause = null
	if not on:
		return
	var vb := _panel("DURAKLATILDI")
	_pause = vb.get_parent().get_parent()
	_button(vb, "Devam", func(): main.toggle_pause())
	_button(vb, "Bölümü yeniden başlat", func(): main.restart())
	_button(vb, "Ana menü", func(): main.to_menu())


func show_end(won: bool, text: String, st: Dictionary, elapsed: float) -> void:
	var vb := _panel(text)
	_end = vb.get_parent().get_parent()
	var l := Label.new()
	l.text = "Süre: %d:%02d   Alarm: %d   Bıçak: %d   Bayıltma: %d   Atış: %d   Bulunan ceset: %d" % [
		int(elapsed) / 60, int(elapsed) % 60, st.get("alarms", 0), st.get("knife", 0), st.get("knockouts", 0), st.get("shots", 0), st.get("bodies_found", 0)]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	if won and st.get("alarms", 0) == 0:
		var g := Label.new()
		g.text = "HAYALET – hiç alarm çalmadı!"
		g.modulate = Color(0.5, 1, 0.6)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(g)
	_button(vb, "Tekrar oyna", func(): main.restart())
	_button(vb, "Ana menü", func(): main.to_menu())


func start_level(d: Dictionary) -> void:
	_level_name = str(d.get("name", ""))
	_brief = str(d.get("brief", ""))
	_brief_t = 8.0
	_alarm = ""
	_toasts.clear()
	_dialog.clear()


func set_alarm(t: String) -> void:
	_alarm = t


func set_map_mode(on: bool) -> void:
	_map = on


func toast(t: String) -> void:
	_toasts.append([t, 4.0])
	if _toasts.size() > 4:
		_toasts.pop_front()


func show_dialog(lines: Array) -> void:
	for l in lines:
		_dialog.append(l)
	if _dialog_t <= 0.0:
		_dialog_t = 4.5


# ---------------- cizim ----------------
func _process(delta: float) -> void:
	for t in _toasts:
		t[1] -= delta
	while not _toasts.is_empty() and _toasts[0][1] <= 0.0:
		_toasts.pop_front()
	if not _dialog.is_empty():
		_dialog_t -= delta
		if _dialog_t <= 0.0:
			_dialog.pop_front()
			_dialog_t = 4.5 if not _dialog.is_empty() else 0.0
	_brief_t -= delta
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		if main.player != null:
			main.player.cam.h_offset = randf_range(-1, 1) * shake * 0.15
			main.player.cam.v_offset = randf_range(-1, 1) * shake * 0.15
	queue_redraw()


func _txt(p: Vector2, s: String, size := 18, c := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string_outline(_font, p, s, align, w, size, 5, Color(0, 0, 0, 0.8))
	draw_string(_font, p, s, align, w, size, c)


func _draw() -> void:
	if main.player == null or main.menu_open or main.loading:
		return
	var vs := get_viewport_rect().size
	var c := vs / 2
	var p = main.player
	if _map:
		_txt(Vector2(20, 40), "TAKTİK HARİTA – oyun durdu  •  sürükle: kaydır  •  tekerlek: yakınlaş  •  TAB/ESC: geri dön", 20, Color(0.8, 1, 0.8))
		_txt(Vector2(20, 66), "Mavi: devriye  Sarı: şüphe  Turuncu: arıyor  Kırmızı: alarm/çatışma", 16, Color(0.8, 0.85, 0.8))
		_objectives(Vector2(20, 100))
		if _mobile:
			_draw_map_buttons(vs)
		return
	# hasar kizarmasi
	if p.hurt_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0, 0, p.hurt_t * 0.4))
	if p.hp < 35.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.5, 0, 0, 0.15 + sin(Time.get_ticks_msec() / 200.0) * 0.05))
	# nisangah
	var cc := Color(1, 1, 1, 0.85)
	draw_line(c + Vector2(-9, 0), c + Vector2(-3, 0), cc, 2)
	draw_line(c + Vector2(3, 0), c + Vector2(9, 0), cc, 2)
	draw_line(c + Vector2(0, -9), c + Vector2(0, -3), cc, 2)
	draw_line(c + Vector2(0, 3), c + Vector2(0, 9), cc, 2)
	_detection(c, p)
	# durum
	var hidden: bool = p.is_hidden()
	var stance := "ÇALILIKTA GİZLİ" if hidden else ("ÇÖMELİK" if p.crouched else ("KOŞUYOR – duyulur!" if p.is_running() else "AYAKTA"))
	_txt(Vector2(24, vs.y - 92), stance, 18, Color(0.5, 1, 0.6) if hidden else Color(0.9, 0.9, 0.85))
	draw_rect(Rect2(24, vs.y - 78, 220, 14), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(24, vs.y - 78, 220 * p.hp / p.max_hp, 14), Color(0.85, 0.2, 0.15))
	_txt(Vector2(24, vs.y - 40), "%s   Mermi: %d   Taş: %d   İlk yardım: %d" % [WEAPON_NAMES[p.weapon], p.ammo, p.stones, p.medkits], 18)
	var items := ""
	for k in main.mission.items:
		if main.mission.items[k] > 0:
			items += "%s%s  " % [main.mission.item_name(k), (" x%d" % main.mission.items[k]) if main.mission.items[k] > 1 else ""]
	if items != "":
		_txt(Vector2(24, vs.y - 16), items, 15, Color(1, 0.9, 0.5))
	_objectives(Vector2(20, 34))
	# alarm
	var al: int = main.alert_level
	if al > 0 or _alarm != "":
		var t := _alarm if _alarm != "" else "SARI ALARM: askerler tetikte"
		var col := Color(1, 0.25, 0.2) if al >= 2 else Color(1, 0.8, 0.25)
		_txt(Vector2(0, 34), t, 22, col, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if timer_text != "":
		_txt(Vector2(0, 64), timer_text, 26, Color(1, 0.5, 0.2), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	# etkilesim
	var it = main.current_interaction
	if it != null:
		var key := "" if _mobile else "[E] "
		_txt(Vector2(0, c.y + 70), key + it["text"], 22, Color(1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if hold_progress > 0.0:
			draw_rect(Rect2(c.x - 100, c.y + 82, 200, 10), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(c.x - 100, c.y + 82, 200 * clampf(hold_progress, 0, 1), 10), Color(1, 0.85, 0.3))
	# bildirimler
	var y := c.y + 112
	for tt in _toasts:
		_txt(Vector2(0, y), tt[0], 18, Color(1, 1, 1, clampf(tt[1], 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		y += 24
	# gorev ozeti / diyalog
	if _brief_t > 0.0:
		_txt(Vector2(0, vs.y * 0.25), _level_name, 30, Color(1, 0.9, 0.6, clampf(_brief_t, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_txt(Vector2(0, vs.y * 0.25 + 34), _brief, 18, Color(1, 1, 1, clampf(_brief_t, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not _dialog.is_empty():
		var dl: Array = _dialog[0]
		draw_rect(Rect2(vs.x * 0.15, vs.y - 190, vs.x * 0.7, 70), Color(0, 0, 0, 0.6))
		_txt(Vector2(vs.x * 0.15 + 14, vs.y - 166), str(dl[0]), 17, Color(1, 0.85, 0.5))
		_txt(Vector2(vs.x * 0.15 + 14, vs.y - 140), str(dl[1]), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, vs.x * 0.7 - 28)
	if _mobile:
		_draw_touch(vs)


func _objectives(at: Vector2) -> void:
	var y := at.y
	for o in main.mission.active_list():
		_txt(Vector2(at.x, y), ("○ " if not o.get("optional", false) else "◇ ") + str(o.get("text", "")), 16, Color(0.95, 0.95, 0.85) if not o.get("optional", false) else Color(0.75, 0.8, 0.75))
		y += 21


func _detection(c: Vector2, p) -> void:
	## FPS'te koni gorunmez: seni gormeye baslayan askerin yonunde dolan bir ok cikar
	var cam: Camera3D = p.cam
	var fwd := -cam.global_transform.basis.z
	var fa := atan2(fwd.z, fwd.x)
	for g in get_tree().get_nodes_in_group("guards"):
		if not g.alive:
			continue
		var lvl := 0.0
		var col := Color(1, 0.85, 0.2)
		if g.state == &"combat" and g.target == p:
			lvl = 1.0
			col = Color(1, 0.2, 0.15)
		elif g.suspicion > 0.0:
			lvl = g.suspicion
			col = Color(1, 0.85, 0.2).lerp(Color(1, 0.3, 0.1), g.suspicion)
		elif g.state == &"alarm_run":
			lvl = 0.6
			col = Color(1, 0.4, 0.9)
		else:
			continue
		var to: Vector3 = g.global_position - p.global_position
		var a := wrapf(atan2(to.z, to.x) - fa, -PI, PI)
		var dir := Vector2(sin(a), -cos(a))
		var r := 90.0
		var tip := c + dir * (r + 26)
		var b1 := c + dir * r + dir.orthogonal() * 14
		var b2 := c + dir * r - dir.orthogonal() * 14
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), Color(col, 0.25 + lvl * 0.75))
		draw_arc(c, r - 6, a - PI / 2 - 0.25, a - PI / 2 - 0.25 + 0.5 * lvl, 12, col, 4)


# ---------------- dokunmatik ----------------
func _layout(vs: Vector2) -> void:
	var s := minf(vs.x, vs.y) / 720.0
	var r := 70.0 * s
	_btns = {
		"ates": Rect2(vs.x - 190 * s, vs.y - 230 * s, 150 * s, 150 * s),
		"etkilesim": Rect2(vs.x - 360 * s, vs.y - 170 * s, 120 * s, 120 * s),
		"comel": Rect2(vs.x - 150 * s, vs.y - 380 * s, 110 * s, 110 * s),
		"kos": Rect2(40 * s, vs.y - 400 * s, 110 * s, 90 * s),
		"silah": Rect2(vs.x - 320 * s, vs.y - 330 * s, 110 * s, 90 * s),
		"harita": Rect2(vs.x - 140 * s, 20 * s, 110 * s, 80 * s),
		"menu": Rect2(vs.x - 270 * s, 20 * s, 110 * s, 80 * s),
		"islik": Rect2(170 * s, vs.y - 400 * s, 110 * s, 90 * s),
	}
	if _stick_id < 0:
		_stick_c = Vector2(200 * s, vs.y - 200 * s)
	_stick_r = r


var _stick_r := 70.0
const BTN_TEXT := {"ates": "ATEŞ", "etkilesim": "E", "comel": "ÇÖMEL", "kos": "KOŞ", "silah": "SİLAH", "harita": "HARİTA", "menu": "MENÜ", "islik": "ISLIK"}


func _draw_touch(vs: Vector2) -> void:
	_layout(vs)
	draw_circle(_stick_c, _stick_r * 1.4, Color(1, 1, 1, 0.08))
	draw_arc(_stick_c, _stick_r * 1.4, 0, TAU, 32, Color(1, 1, 1, 0.3), 2)
	draw_circle(_stick_c + _stick_p * _stick_r, _stick_r * 0.55, Color(1, 1, 1, 0.25))
	for k in _btns:
		var on: bool = (k == "kos" and touch_run) or (k == "comel" and main.player.crouched) or _btn_ids.values().has(k)
		var r: Rect2 = _btns[k]
		draw_rect(r, Color(1, 1, 1, 0.28 if on else 0.12))
		draw_rect(r, Color(1, 1, 1, 0.4), false, 2)
		_txt(Vector2(r.position.x, r.get_center().y + 7), BTN_TEXT[k], 20, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_map_buttons(vs: Vector2) -> void:
	_layout(vs)
	var r: Rect2 = _btns["harita"]
	draw_rect(r, Color(1, 1, 1, 0.2))
	_txt(Vector2(r.position.x, r.get_center().y + 7), "GERİ", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in 2:
		var b := Rect2(r.position.x, r.end.y + 20 + i * 100, r.size.x, 80)
		draw_rect(b, Color(1, 1, 1, 0.2))
		_txt(Vector2(b.position.x, b.get_center().y + 9), "+" if i == 0 else "−", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)


func _input(e: InputEvent) -> void:
	if not _mobile or main.player == null or main.menu_open or main.loading or main.game_over:
		return
	if not (e is InputEventScreenTouch or e is InputEventScreenDrag):
		return
	var vs := get_viewport_rect().size
	_layout(vs)
	if main.map_mode:
		if e is InputEventScreenTouch and e.pressed:
			var r: Rect2 = _btns["harita"]
			if r.has_point(e.position):
				main.toggle_map()
			elif Rect2(r.position.x, r.end.y + 20, r.size.x, 80).has_point(e.position):
				main.zoom_map(0.8)
			elif Rect2(r.position.x, r.end.y + 120, r.size.x, 80).has_point(e.position):
				main.zoom_map(1.25)
		elif e is InputEventScreenDrag:
			main.pan_map(e.relative)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	var p = main.player
	if e is InputEventScreenTouch:
		if e.pressed:
			for k in _btns:
				if _btns[k].has_point(e.position):
					_btn_ids[e.index] = k
					_press(k)
					get_viewport().set_input_as_handled()
					return
			if e.position.x < vs.x * 0.4 and _stick_id < 0:
				_stick_id = e.index
				_stick_c = e.position
				_stick_p = Vector2.ZERO
			elif _look_id < 0:
				_look_id = e.index
				_look_last = e.position
		else:
			if _btn_ids.has(e.index):
				if _btn_ids[e.index] == "etkilesim":
					touch_use_held = false
				_btn_ids.erase(e.index)
			if e.index == _stick_id:
				_stick_id = -1
				_stick_p = Vector2.ZERO
				p.touch_move = Vector2.ZERO
			if e.index == _look_id:
				_look_id = -1
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if e.index == _stick_id:
			_stick_p = ((e.position - _stick_c) / (_stick_r * 1.4)).limit_length(1.0)
			p.touch_move = _stick_p
		elif e.index == _look_id:
			p.look((e.position - _look_last) * 1.6)
			_look_last = e.position
		get_viewport().set_input_as_handled()


func _press(k: String) -> void:
	var p = main.player
	match k:
		"ates":
			p.attack()
		"etkilesim":
			touch_use_held = true
			main.interact()
		"comel":
			p.toggle_crouch()
		"kos":
			touch_run = not touch_run
		"silah":
			p.set_weapon((p.weapon + 1) % p.WEAPONS.size())
		"harita":
			main.toggle_map()
		"menu":
			main.toggle_pause()
		"islik":
			p.whistle()
