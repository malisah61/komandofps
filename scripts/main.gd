extends Node
## KomandoFPS ana dugum: bolum yukleme, alarm sistemi (Komando'nun main.gd mantigi), taktik harita,
## etkilesim, efektler, kazanma/kaybetme.

const LV := preload("res://scripts/level3d.gd")
const Guard := preload("res://scripts/guard3d.gd")
const Player := preload("res://scripts/player.gd")
const Npc := preload("res://scripts/npc3d.gd")
const Mission := preload("res://scripts/mission3d.gd")
const Hud := preload("res://scripts/hud.gd")

const LEVELS := [
	"res://levels/bolum0.json", "res://levels/bolum1.json", "res://levels/bolum2.json", "res://levels/bolum3.json",
	"res://levels/bolum4.json", "res://levels/bolum5.json", "res://levels/bolum6.json",
]
const FAR := 70.0                  # bu mesafeden uzak askerler seyrek dusunur

var world: Node3D
var level
var player
var mission
var hud
var map_cam: Camera3D
var map_mode := false
var menu_open := true
var game_over := false
var loading := false
var level_path := ""
var alert_level := 0
var alarm_t := 0.0
var runner = null
var _reinforced := false
var _pending: Array = []           # [gecikme, kisla, sayi, hedef]
var bodies: Array = []
var current_interaction = null
var stats := {}
var _npcs: Array = []
var _cone_t := 0.0
var _map_zoom := 70.0
var _dragging := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var cl := CanvasLayer.new()
	cl.layer = 5
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	hud = Hud.new()
	hud.main = self
	cl.add_child(hud)
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--level="):
			start_level(a.substr(8))
			return
	hud.show_menu()


func _setup_input() -> void:
	var keys := {
		"ileri": [KEY_W, KEY_UP], "geri": [KEY_S, KEY_DOWN], "sol": [KEY_A, KEY_LEFT], "sag": [KEY_D, KEY_RIGHT],
		"kos": [KEY_SHIFT], "comel": [KEY_C, KEY_CTRL], "etkilesim": [KEY_E], "islik": [KEY_Z],
		"harita": [KEY_TAB, KEY_M], "ilac": [KEY_H], "silah_1": [KEY_1], "silah_2": [KEY_2], "silah_3": [KEY_3],
		"silah_4": [KEY_4], "menu": [KEY_ESCAPE], "silah_sonraki": [KEY_Q],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	for a in ["ates", "silah_onceki"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("ates", mb)
	var wu := InputEventMouseButton.new()
	wu.button_index = MOUSE_BUTTON_WHEEL_UP
	InputMap.action_add_event("silah_onceki", wu)
	var wd := InputEventMouseButton.new()
	wd.button_index = MOUSE_BUTTON_WHEEL_DOWN
	InputMap.action_add_event("silah_sonraki", wd)
	var rb := InputEventMouseButton.new()
	rb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("etkilesim", rb)


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")


# ---------------- bolum ----------------
func start_level(path: String) -> void:
	loading = true
	get_tree().paused = false
	_clear()
	level_path = path
	menu_open = false
	game_over = false
	map_mode = false
	hud.hide_menu()
	hud.show_loading("Bölüm yükleniyor…")
	await get_tree().process_frame
	await get_tree().process_frame
	world = Node3D.new()
	world.name = "Dunya"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	level = LV.new()
	level.name = "Bolum"
	world.add_child(level)
	if not level.load_level(path):
		hud.show_loading("Bölüm açılamadı: " + path)
		return
	level.bake_nav(false)
	alert_level = 0
	alarm_t = 0.0
	runner = null
	_reinforced = false
	_pending.clear()
	bodies.clear()
	stats = {"knife": 0, "knockouts": 0, "shots": 0, "alarms": 0, "damage": 0.0, "bodies_found": 0}
	# oyuncu
	player = Player.new()
	player.main = self
	player.name = "Komando"
	world.add_child(player)
	player.global_position = level.start + Vector3(0, 0.1, 0)
	var center := Vector3(level.size.x * LV.S / 2, 0, level.size.y * LV.S / 2)
	player.set_facing(atan2(center.z - level.start.z, center.x - level.start.x))
	player.stones = int(level.data.get("stones", 4))
	_add_map_marker(player, Color(0.3, 1.0, 0.4))
	player.cam.current = true
	# askerler
	var gi := 0
	for gd in level.data.get("guards", []):
		var g := Guard.new()
		g.main = self
		g.name = "Asker%d" % gi
		gi += 1
		g.kind = str(gd.get("type", "er"))
		g.facing = deg_to_rad(float(gd.get("facing", 0.0)))
		g.drops = str(gd.get("drops", ""))
		for p in gd["path"]:
			g.waypoints.append(LV.P(p))
		var pos: Vector3 = g.waypoints[0]
		if g.kind == "kule":
			for tw in level.towers:
				if Vector2(tw.x - pos.x, tw.z - pos.z).length() < 4.0:
					pos = tw
					break
			g.waypoints = [pos]
		world.add_child(g)
		g.global_position = pos + (Vector3(0, 0.05, 0) if g.kind != "kule" else Vector3.ZERO)
	_pair_buddies()
	# dostlar
	_npcs.clear()
	for nd in level.data.get("npcs", []):
		var n := Npc.new()
		n.main = self
		n.id = nd["id"]
		n.display_name = str(nd.get("name", nd["id"]))
		n.outfit = str(nd.get("outfit", "direnisci"))
		n.facing = deg_to_rad(float(nd.get("facing", 90.0)))
		world.add_child(n)
		n.global_position = LV.P(nd["pos"]) + Vector3(0, 0.05, 0)
		_npcs.append(n)
	mission = Mission.new()
	mission.main = self
	world.add_child(mission)
	for n in _npcs:
		mission.npcs[n.id] = n
	mission.setup(level.data)
	# taktik harita kamerasi
	map_cam = Camera3D.new()
	map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	map_cam.size = _map_zoom
	map_cam.far = 200.0
	map_cam.cull_mask = 0xFFFFF & ~LV.V_FPS
	map_cam.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(map_cam)
	hud.hide_loading()
	hud.start_level(level.data)
	loading = false
	_capture(true)


func _clear() -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = null
	level = null
	player = null
	mission = null
	_npcs.clear()
	bodies.clear()


func _pair_buddies() -> void:
	## yakindaki iki sabit nobetci birbirini kollar (Shadow Tactics): biri kaybolursa digeri fark eder
	var stat: Array = []
	for g in get_tree().get_nodes_in_group("guards"):
		if g.waypoints.size() <= 1 and g.kind != "kule":
			stat.append(g)
	for g in stat:
		if g.buddy != null:
			continue
		for h in stat:
			if h != g and h.buddy == null and g.global_position.distance_to(h.global_position) < 12.0:
				g.buddy = h
				h.buddy = g
				g.buddy_post = h.global_position
				h.buddy_post = g.global_position
				break


func _add_map_marker(n: Node3D, c: Color) -> void:
	var pm := PrismMesh.new()
	pm.size = Vector3(1.6, 2.2, 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	mi.material_override = m
	mi.layers = LV.V_MAP
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = Vector3(0, 3.0, 0)
	n.add_child(mi)


func targets() -> Array:
	var out: Array = []
	if player != null:
		out.append(player)
	for n in _npcs:
		if n.following and n.alive:
			out.append(n)
	return out


func far_from_player(p: Vector3) -> bool:
	return player == null or Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() > FAR


# ---------------- alarm (Komando ile ayni kurallar) ----------------
func set_alert_level(l: int) -> void:
	alert_level = l


func combat_alarm(p: Vector3, by) -> void:
	if level.sirens.is_empty():
		raise_alarm(p, by)
		return
	if alert_level >= 2:
		alarm_t = maxf(alarm_t, 35.0)
		if not _reinforced:
			_dispatch_runner(p, by)
		return
	alarm_t = maxf(alarm_t, 35.0)
	stats["alarms"] += 1
	set_alert_level(2)
	hud.set_alarm("ALARM! Asker bağırdı – sirene koşanı durdur, yoksa takviye gelir")
	_sweep(p, by)
	_dispatch_runner(p, by)


func _dispatch_runner(p: Vector3, by) -> void:
	if runner != null and is_instance_valid(runner) and runner.alive and runner.state == &"alarm_run":
		return
	var sp: Vector3 = level.sirens[0]
	for q in level.sirens:
		if q.distance_to(p) < sp.distance_to(p):
			sp = q
	if sp.distance_to(p) > 75.0:
		raise_alarm(p, by)
		return
	var best = null
	var bd := INF
	for g in get_tree().get_nodes_in_group("guards"):
		if not g.alive or g.carried or g.kind == "kule" or (g.state == &"combat" and g != by):
			continue
		if g.global_position.distance_to(p) > 24.0:
			continue
		var d: float = g.global_position.distance_to(sp)
		if g == by:
			d += 12.0
		if d < bd:
			bd = d
			best = g
	if best == null:
		return
	runner = best
	best.run_to_siren(sp, p)
	hud.toast("Bir asker sirene koşuyor! Durdur!")


func siren_reached(g) -> void:
	runner = null
	hud.toast("Siren çaldı!")
	raise_alarm(g.investigate_pos, g)


func runner_stopped(_g) -> void:
	runner = null
	hud.toast("Alarm koşucusu durduruldu")


func raise_alarm(p: Vector3, by) -> void:
	alarm_t = maxf(alarm_t, 35.0)
	if alert_level < 2:
		stats["alarms"] += 1
		set_alert_level(2)
		hud.set_alarm("KIRMIZI ALARM – takviye geliyor")
		_sweep(p, by)
	if not _reinforced:
		_reinforced = true
		var sent := 0
		var order: Array = level.barracks.duplicate()
		order.sort_custom(func(a, b): return a[0].distance_to(p) < b[0].distance_to(p))
		for bk in order:
			if sent >= 2 or bk[1] <= 0:
				continue
			var n: int = mini(3, bk[1])
			bk[1] -= n
			_pending.append([bk[3], bk, n, p])
			sent += 1


func _sweep(p: Vector3, by) -> void:
	## alarmda olay yerine yakin askerler genis alani tarar
	for g in get_tree().get_nodes_in_group("guards"):
		if g != by and g.alive and g.kind != "kule" and g.state != &"combat" and g.state != &"alarm_run" and g.global_position.distance_to(p) < 45.0:
			g.sweep(p)


func _spawn_reinforcements(bk: Array, n: int, target: Vector3) -> void:
	for k in n:
		var g := Guard.new()
		g.main = self
		g.kind = bk[2]
		g.reinforcement = true
		g.state = &"investigate"
		g.investigate_pos = target + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		world.add_child(g)
		g.global_position = bk[0] + Vector3((k - 1) * 1.1, 0.05, (k % 2) * 0.8)
	hud.toast("Takviye birlik geldi: %d asker" % n)


func body_found(p: Vector3, by = null) -> void:
	if alert_level < 1:
		set_alert_level(1)
	stats["bodies_found"] += 1
	hud.toast("Bir asker ceset buldu!")
	make_noise(p, 17.0, null)
	if not level.sirens.is_empty() and by != null and alert_level < 2:
		_dispatch_runner(p, null)


func buddy_missing(g, post: Vector3) -> void:
	if alert_level < 1:
		set_alert_level(1)
	hud.toast("Bir nöbetçi arkadaşının kaybolduğunu fark etti!")
	for h in get_tree().get_nodes_in_group("guards"):
		if h != g and h.alive and h.state == &"patrol" and h.kind != "kule" and h.global_position.distance_to(post) < 21.0:
			h.hear_distraction(post + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))


func guard_woke(_g) -> void:
	hud.toast("Bayılan bir asker ayıldı!")
	if alert_level < 1:
		set_alert_level(1)


func scuffle(p: Vector3) -> void:
	## bogusma sesi: cok yakindakiler duyar
	for g in get_tree().get_nodes_in_group("guards"):
		if g.alive and g.global_position.distance_to(p) < 4.5 and g.state != &"combat":
			g.hear_distraction(p)


func make_noise(p: Vector3, radius: float, src) -> void:
	for g in get_tree().get_nodes_in_group("guards"):
		if g != src and g.alive and g.global_position.distance_to(p) < radius:
			g.hear_noise(p)
	if alert_level == 0:
		set_alert_level(1)


func distract(p: Vector3, radius: float) -> int:
	var n := 0
	for g in get_tree().get_nodes_in_group("guards"):
		if g.alive and g.global_position.distance_to(p) < radius and g.state != &"combat":
			g.hear_distraction(p)
			n += 1
	return n


func objective_done(o: Dictionary) -> void:
	hud.toast("Görev tamam: " + str(o.get("text", "")))


func win() -> void:
	if game_over:
		return
	game_over = true
	_capture(false)
	hud.show_end(true, "GÖREV BAŞARILI", stats, mission.elapsed)


func lose(text: String) -> void:
	if game_over:
		return
	game_over = true
	_capture(false)
	hud.show_end(false, text, stats, mission.elapsed if mission else 0.0)


# ---------------- dongu ----------------
func _process(delta: float) -> void:
	if world == null or loading or player == null:
		return
	if map_mode:
		_cone_t -= delta
		if _cone_t <= 0.0:
			_cone_t = 0.1
			for g in get_tree().get_nodes_in_group("guards"):
				g.update_cone()
		return
	if game_over or get_tree().paused:
		return
	# alarm sayaci
	if alert_level == 2:
		var fighting := false
		for g in get_tree().get_nodes_in_group("guards"):
			if g.alive and g.state == &"combat":
				fighting = true
				break
		alarm_t -= delta * (0.25 if fighting else 1.0)
		if alarm_t <= 0.0:
			set_alert_level(1)
			hud.set_alarm("")
		elif not fighting:
			hud.set_alarm("ALARM: Askerler arıyor (%d sn)" % ceili(alarm_t))
	var i := _pending.size() - 1
	while i >= 0:
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			_spawn_reinforcements(_pending[i][1], _pending[i][2], _pending[i][3])
			_pending.remove_at(i)
		i -= 1
	_update_interaction()


func _update_interaction() -> void:
	current_interaction = null
	if not player.alive:
		return
	var cp: Vector3 = player.global_position
	if player.carrying != null:
		current_interaction = {"text": "Cesedi bırak", "do": func(): player.drop_body()}
		return
	var m = mission.interaction(cp)
	if m != null:
		current_interaction = m
		return
	for pk in level.pickups:
		if not pk["taken"] and _flat(cp, pk["pos"]) < 1.6:
			current_interaction = {"text": "Al: " + _pickup_name(pk), "do": func(): _take_pickup(pk)}
			return
	for i in level.doors.size():
		var dr: Dictionary = level.doors[i]
		if _flat(cp, dr["pos"]) < 2.3:
			var it: String = dr["item"]
			if mission.items.get(it, 0) > 0:
				current_interaction = {"text": "Kapıyı aç (" + mission.item_name(it) + ")", "do": func(): level.open_door(i); hud.toast("Kapı açıldı")}
			else:
				current_interaction = {"text": "Kilitli – " + mission.item_name(it) + " gerek", "do": func(): pass}
			return
	if mission.items.get("tel_makasi", 0) > 0:
		pass
	for g in bodies:
		if not g.carried and _flat(cp, g.global_position) < 1.8:
			if g.knocked and not g.tied:
				current_interaction = {"text": "Bağla (bir daha ayılmaz)", "do": func(): g.tie_up(); hud.toast("Asker bağlandı")}
				return
			current_interaction = {"text": "Cesedi taşı", "do": func(): player.pick_body(g)}
			return


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _pickup_name(pk: Dictionary) -> String:
	match pk["type"]:
		"medkit":
			return "İlk yardım çantası"
		"ammo":
			return "Mermi"
		"key":
			return mission.item_name(str(pk.get("item", "anahtar")))
	return str(pk["type"])


func _take_pickup(pk: Dictionary) -> void:
	level.take_pickup(pk)
	match pk["type"]:
		"medkit":
			player.medkits += 1
			hud.toast("İlk yardım çantası alındı (H: kullan)")
		"ammo":
			player.ammo += 8
			hud.toast("Mermi alındı (+8)")
		"key", "item":
			var it: String = str(pk.get("item", "anahtar"))
			mission.items[it] = mission.items.get(it, 0) + int(pk.get("count", 1))
			hud.toast(mission.item_name(it) + " alındı")


func interact() -> void:
	if current_interaction != null and current_interaction.get("hold", 0.0) <= 0.0:
		current_interaction["do"].call()


func _unhandled_input(e: InputEvent) -> void:
	if menu_open or loading or player == null:
		return
	if e.is_action_pressed("menu"):
		if map_mode:
			toggle_map()
		elif not game_over:
			toggle_pause()
		return
	if game_over:
		return
	if e.is_action_pressed("harita"):
		toggle_map()
		return
	if map_mode:
		_map_input(e)
		return
	if get_tree().paused:
		return
	if e.is_action_pressed("etkilesim"):
		interact()
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not is_mobile():
		_capture(true)


func _map_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_map(0.85)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_map(1.18)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
	elif e is InputEventMouseMotion and _dragging:
		pan_map(e.relative)
	elif e is InputEventScreenDrag:
		pan_map(e.relative)


func pan_map(rel: Vector2) -> void:
	var k := map_cam.size / get_viewport().get_visible_rect().size.y
	map_cam.position.x -= rel.x * k
	map_cam.position.z -= rel.y * k


func zoom_map(f: float) -> void:
	_map_zoom = clampf(_map_zoom * f, 20.0, 400.0)
	map_cam.size = _map_zoom


func toggle_map() -> void:
	if game_over or player == null:
		return
	map_mode = not map_mode
	get_tree().paused = map_mode
	if map_mode:
		map_cam.position = Vector3(player.global_position.x, 80.0, player.global_position.z)
		map_cam.current = true
		_cone_t = 0.0
		_capture(false)
	else:
		for g in get_tree().get_nodes_in_group("guards"):
			g.clear_cone()
		player.cam.current = true
		_capture(true)
	hud.set_map_mode(map_mode)


func toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	hud.show_pause(p)
	_capture(not p)


func restart() -> void:
	start_level(level_path)


func to_menu() -> void:
	get_tree().paused = false
	_clear()
	menu_open = true
	game_over = false
	map_mode = false
	_capture(false)
	hud.show_menu()


func _capture(on: bool) -> void:
	if is_mobile() or DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


# ---------------- efektler ----------------
func _fx_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func gunshot_fx(from: Vector3, to: Vector3) -> void:
	if world == null:
		return
	var d := from.distance_to(to)
	if d < 0.1:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, d)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = _fx_mat(Color(1, 0.9, 0.6, 0.8))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = (from + to) / 2
	mi.look_at_from_position(mi.global_position, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	get_tree().create_timer(0.06, false).timeout.connect(mi.queue_free)


func blood_fx(p: Vector3) -> void:
	if world == null:
		return
	for i in 5:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 0.06)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _fx_mat(Color(0.6, 0.05, 0.05))
		world.add_child(mi)
		mi.global_position = p
		var tw := create_tween()
		tw.tween_property(mi, "global_position", p + Vector3(randf_range(-0.5, 0.5), randf_range(-1.2, 0.2), randf_range(-0.5, 0.5)), 0.35)
		tw.tween_callback(mi.queue_free)


func stone_fx(from: Vector3, to: Vector3) -> void:
	if world == null:
		return
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = _fx_mat(Color(0.5, 0.5, 0.48))
	world.add_child(mi)
	mi.global_position = from
	var tw := create_tween()
	tw.tween_property(mi, "global_position", to + Vector3(0, 0.05, 0), 0.5)
	tw.tween_interval(2.0)
	tw.tween_callback(mi.queue_free)


func explosion_fx(p: Vector3) -> void:
	if world == null:
		return
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = _fx_mat(Color(1, 0.55, 0.15, 0.85))
	world.add_child(mi)
	mi.global_position = p + Vector3(0, 1, 0)
	var li := OmniLight3D.new()
	li.light_color = Color(1, 0.6, 0.3)
	li.omni_range = 25.0
	li.light_energy = 6.0
	mi.add_child(li)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 6.0, 0.45)
	tw.parallel().tween_property(li, "light_energy", 0.0, 0.8)
	tw.tween_callback(mi.queue_free)
	hud.shake = 0.6
