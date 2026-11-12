extends CharacterBody3D
## Dusman askeri - Komando (2D) yapay zekasinin 3D/FPS'e tasinmis hali.
## Durumlar ayni: devriye -> suphe -> arastirma -> arama (cok noktali) -> catisma -> geri donus,
## + sirene kosma (alarm_run). Rutbeler: er, kis, elit (SS), subay, kule.
## Komando'dan gelenler: kademeli tespit (mesafe/comelme/rutbe/alarm), cevresel algi, tetikte kalma,
## catismada atis + yaralaninca siper + kusatma, yakindakilere seslenme (subay duduk),
## ses/dikkat dagitma duyma, paylasimli cok noktali arama, tahminli arama, ceset bulma,
## kayip nobet arkadasi, bayilma/ayilma, baglama, anahtar dusurme.
## 3D'de gorus konisi gercek isinlarla (goz hizasindan) hesaplanir: alcak siperin arkasinda
## comelen oyuncu gercekten gorunmez.

const LV := preload("res://scripts/level3d.gd")
const SoldierModel := preload("res://scripts/soldier_model.gd")

const EYE := 1.62
const VIEW_RANGE := 24.0         # metre (er)
const VIEW_HALF := 0.56          # ~32 derece (yarim aci)
const NEAR_FRAC := 0.55          # comelen oyuncu yalniz koninin yakin kisminda gorulur
const BUSH_SEE := 4.0            # caliya saklanani bu mesafeden gorur
const PERIPHERAL := 2.3          # arkadan hissetme (ayakta + hareketli)
const WHISTLE := 16.0
const VIGIL_TIME := 45.0
const SPEED := 1.45              # devriye yurume hizi (m/sn)
const RAYS := 18

# rutbe -> [can, gorus carpani, tespit hizi, atis araligi (sn), hasar, isabet]
const RANKS := {
	"er":    [60.0,  1.0,  1.0,  1.35, 11.0, 0.74],
	"kis":   [60.0,  1.0,  1.0,  1.35, 11.0, 0.74],
	"elit":  [110.0, 1.15, 1.25, 1.05, 14.0, 0.82],
	"subay": [80.0,  1.1,  1.35, 1.1,  13.0, 0.80],
	"kule":  [60.0,  1.55, 1.15, 1.5,  12.0, 0.70],
}
const COLORS := {
	"er": Color(0.42, 0.45, 0.38), "kis": Color(0.82, 0.84, 0.86), "elit": Color(0.18, 0.19, 0.2),
	"subay": Color(0.48, 0.5, 0.44), "kule": Color(0.42, 0.45, 0.38),
}

var main
var nav_agent: NavigationAgent3D
var waypoints: Array = []
var wp_i := 0
var facing := 0.0                 # xz duzleminde aci (2D ile ayni: 0 = +x, PI/2 = +z)
var base_facing := 0.0
var state := &"patrol"
var alive := true
var discovered := false
var hidden_body := false
var carried := false
var suspicion := 0.0
var investigate_pos := Vector3.ZERO
var timer := 0.0
var t := 0.0
var kind := "er"
var hp := 60.0
var max_hp := 60.0
var target = null
var reinforcement := false
var buddy = null
var buddy_post := Vector3.ZERO
var _buddy_checked := false
var _buddy_dead_t := 0.0
var flank := 0.0
var _cover_pos = null
var _cover_t := 0.0
var _took_cover := false
var _last_dir := Vector3.ZERO
var drops := ""
var siren_pos := Vector3.ZERO
var vigilant_t := 0.0
var knocked := false
var tied := false
var _wake_t := 0.0
var shout_t := 0.0
var _fire_t := 0.0
var _lost_t := 0.0
var _search_pts: Array = []
var _scan_t := 0.0
var _ready_nav := false
var _slow := 1.0
var _slow_t := 0.0
var _far_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO

var model
var _label: Label3D
var _cone_mi: MeshInstance3D
var _imesh: ImmediateMesh
var _cone_mat: StandardMaterial3D
var _anim_far := false


func _stat(i: int) -> float:
	return float(RANKS.get(kind, RANKS["er"])[i])


func _ready() -> void:
	add_to_group("guards")
	collision_layer = LV.L_GUARD
	collision_mask = LV.L_WORLD | LV.L_MOVE
	max_hp = _stat(0)
	hp = max_hp
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 0.7
	nav_agent.radius = 0.4
	nav_agent.height = 1.7
	nav_agent.path_max_distance = 3.0
	add_child(nav_agent)
	_build_model()
	base_facing = facing
	_fire_t = randf() * 0.8
	_last_pos = global_position
	_apply_facing()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ready_nav = true
	if state == &"patrol":
		_go_patrol()
	elif state == &"investigate":
		nav_agent.target_position = investigate_pos


# ---------------- Govde (gecici: ilkel sekillerle asker; sonra CC0 3D model) ----------------
func _box(sz: Vector3, pos: Vector3, c: Color, parent: Node3D) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_model() -> void:
	model = SoldierModel.new()
	model.outfit = kind
	add_child(model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 72
	_label.pixel_size = 0.006
	_label.outline_size = 12
	_label.position = Vector3(0, 2.25, 0)
	_label.text = ""
	add_child(_label)
	# taktik harita konisi (yalniz harita kamerasi gorur)
	_imesh = ImmediateMesh.new()
	_cone_mi = MeshInstance3D.new()
	_cone_mi.mesh = _imesh
	_cone_mi.layers = LV.V_MAP
	_cone_mi.top_level = true
	_cone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone_mat = StandardMaterial3D.new()
	_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone_mat.vertex_color_use_as_albedo = true
	_cone_mat.no_depth_test = true
	add_child(_cone_mi)
	# haritada asker isareti
	var dm := CylinderMesh.new()
	dm.top_radius = 0.7
	dm.bottom_radius = 0.7
	dm.height = 0.05
	var dot := MeshInstance3D.new()
	dot.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(0.85, 0.2, 0.15) if kind != "subay" and kind != "elit" else Color(0.55, 0.05, 0.05)
	dmat.no_depth_test = true
	dot.material_override = dmat
	dot.layers = LV.V_MAP
	dot.position.y = 2.6
	add_child(dot)


func dir_vec(a: float) -> Vector3:
	return Vector3(cos(a), 0, sin(a))


static func angle_of(v: Vector3) -> float:
	return atan2(v.z, v.x)


func _apply_facing() -> void:
	rotation.y = -facing - PI / 2


func eye() -> Vector3:
	return global_position + Vector3(0, EYE, 0)


func view_range() -> float:
	var k := 1.0
	if main.alert_level == 1:
		k = 1.15
	elif main.alert_level >= 2:
		k = 1.3
	return VIEW_RANGE * _stat(1) * k


func _physics_process(delta: float) -> void:
	if not alive:
		if knocked and not tied and not carried and not main.game_over:
			_wake_t -= delta
			if _wake_t <= 0.0:
				_wake_up()
		return
	t += delta
	vigilant_t = maxf(0.0, vigilant_t - delta)
	shout_t = maxf(0.0, shout_t - delta)
	if not main.game_over and _ready_nav:
		_think(delta)
		_watch(delta)
	if kind != "kule":
		if not is_on_floor():
			velocity.y -= 18.0 * delta
		else:
			velocity.y = -0.5
		move_and_slide()
	_apply_facing()
	_animate(delta)
	_update_label()


func _animate(_delta: float) -> void:
	## 3D modelin hareketi: durum + hiz -> animasyon
	var far: bool = main.far_from_player(global_position)
	if far != _anim_far:
		_anim_far = far
		model.set_active(not far)
	if far:
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	var armed: bool = state == &"combat" or state == &"alarm_run" or (main.alert_level >= 2 and state != &"patrol")
	model.weapon_ready(armed)
	if hv > 3.0:
		model.play("Sprint", hv / 5.5)
	elif hv > 2.0:
		model.play("Jog_Fwd", hv / 3.2)
	elif hv > 0.15:
		model.play("Walk", hv / 1.45)
	elif state == &"combat":
		model.play("Pistol_Aim_Neutral")
	elif armed:
		model.play("Pistol_Idle")
	else:
		model.play("Idle")


func _update_label() -> void:
	var txt := ""
	var col := Color.WHITE
	if state == &"alarm_run":
		txt = "ALARM"
		col = Color(1, 0.2, 0.15)
	elif state == &"combat":
		txt = "ALARM!" if shout_t > 0.0 else "!"
		col = Color(1, 0.25, 0.2)
	elif suspicion > 0.0:
		txt = "!" if suspicion > 0.6 else "?"
		col = Color(1, 0.85, 0.2).lerp(Color(1, 0.3, 0.1), suspicion)
	elif state == &"investigate" or state == &"search":
		txt = "?"
		col = Color(1, 0.6, 0.2)
	_label.text = txt
	_label.modulate = col


# ---------------- Davranis ----------------
func _think(delta: float) -> void:
	match state:
		&"patrol":
			if waypoints.size() <= 1:
				if _walk(delta, 0.6):
					var amp := 0.8 if kind == "kule" else 0.9
					facing = lerp_angle(facing, base_facing + sin(t * (0.45 if kind == "kule" else 0.7)) * amp, minf(1.0, delta * 4.0))
			elif timer > 0.0:
				timer -= delta
				_stop()
				facing += sin(t * 2.0) * delta * 0.8
			elif _walk(delta, 1.0):
				wp_i = (wp_i + 1) % waypoints.size()
				timer = 1.4
				nav_agent.target_position = waypoints[wp_i]
		&"suspicious":
			_stop()
			facing = lerp_angle(facing, angle_of(investigate_pos - global_position), minf(1.0, delta * 5.0))
			if suspicion <= 0.15:
				_set_investigate(investigate_pos)
		&"investigate":
			if _walk(delta, 1.25 if main.alert_level == 0 else 1.6):
				_start_search()
		&"search":
			if timer > 0.0:
				timer -= delta
				_stop()
				facing += delta * 2.0
			elif _walk(delta, 1.0):
				if _search_pts.is_empty():
					_go_patrol()
				else:
					nav_agent.target_position = _search_pts.pop_front()
					timer = 1.2
		&"combat":
			_combat(delta)
		&"alarm_run":
			if _walk(delta, 1.75) or _flat_dist(global_position, siren_pos) < 1.3:
				main.siren_reached(self)
				_set_investigate(investigate_pos)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _combat(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		target = null
		_start_search()
		return
	var tp: Vector3 = target.global_position
	var d := _flat_dist(global_position, tp)
	var sees: bool = d < view_range() * 1.25 and _los_to(target)
	if _cover_pos != null:
		if _walk(delta, 1.8) or _flat_dist(global_position, _cover_pos) < 0.6:
			_stop()
			_cover_t -= delta
			facing = lerp_angle(facing, angle_of(tp - global_position), minf(1.0, delta * 6.0))
			if _cover_t <= 0.0:
				_cover_pos = null
		return
	if sees and not _took_cover and hp < max_hp * 0.4 and kind != "kule":
		_took_cover = true
		var cp = _find_cover(target)
		if cp != null:
			_cover_pos = cp
			_cover_t = 3.0
			nav_agent.target_position = cp
			return
	if sees:
		_lost_t = 0.0
		investigate_pos = tp
		var tv: Vector3 = target.velocity
		if Vector2(tv.x, tv.z).length() > 0.3:
			_last_dir = Vector3(tv.x, 0, tv.z).normalized()
		_stop()
		var want := angle_of(tp - global_position)
		facing = lerp_angle(facing, want, minf(1.0, delta * 10.0))
		_fire_t -= delta
		if _fire_t <= 0.0 and absf(wrapf(want - facing, -PI, PI)) < 0.3:
			var iv := _stat(3) * randf_range(0.85, 1.2)
			if main.alert_level >= 2:
				iv *= 0.85
			_fire_t = iv
			_shoot(target, d)
	else:
		_lost_t += delta
		var to_me := global_position - investigate_pos
		to_me.y = 0
		var side := investigate_pos
		if to_me.length() > 6.0:
			var orth := Vector3(-to_me.z, 0, to_me.x).normalized()
			side = investigate_pos + orth * flank * 4.0
		if _flat_dist(nav_agent.target_position, side) > 1.5:
			nav_agent.target_position = side
		if _walk(delta, 1.7) or _lost_t > 6.0:
			target = null
			_start_search()


func _los_to(u) -> bool:
	return main.level.has_los(eye(), u.aim_point())


func _find_cover(tgt):
	var map: RID = nav_agent.get_navigation_map()
	var away := angle_of(global_position - tgt.global_position)
	for r in [4.5, 8.0]:
		for i in 9:
			var a := away + (i - 4) * 0.55
			var q: Vector3 = NavigationServer3D.map_get_closest_point(map, global_position + dir_vec(a) * r)
			if _flat_dist(q, global_position) > 2.0 and not main.level.has_los(q + Vector3(0, 1.0, 0), tgt.aim_point()):
				return q
	return null


func _shoot(tgt, dist: float) -> void:
	var acc := clampf(_stat(5) - dist / 35.0 + (0.05 if main.alert_level >= 2 else 0.0), 0.2, 0.92)
	if tgt.has_method("is_crouching") and tgt.is_crouching():
		acc *= 0.7
	if tgt.has_method("is_hidden") and tgt.is_hidden():
		acc *= 0.6
	# hareket eden hedef zor vurulur (FPS: kosarak siper degistirmek ise yarasin)
	var tv: Vector3 = tgt.velocity
	if Vector2(tv.x, tv.z).length() > 3.0:
		acc *= 0.75
	var hit := randf() < acc
	model.fire()
	main.gunshot_fx(eye() + dir_vec(facing) * 0.7, tgt.aim_point() + (Vector3.ZERO if hit else Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 1.0), randf_range(-1.5, 1.5))))
	main.make_noise(global_position, 30.0, self)
	if hit:
		tgt.take_damage(_stat(4) * randf_range(0.8, 1.2), global_position)


func _start_search() -> void:
	state = &"search"
	timer = 1.5
	_search_pts.clear()
	var map0: RID = nav_agent.get_navigation_map()
	if _last_dir != Vector3.ZERO:
		_search_pts.append(NavigationServer3D.map_get_closest_point(map0, investigate_pos + _last_dir * 8.0))
		_last_dir = Vector3.ZERO
	var claimed: Array = []
	for g in get_tree().get_nodes_in_group("guards"):
		if g != self and g.alive and g.state == &"search" and _flat_dist(g.global_position, global_position) < 20.0:
			claimed.append_array(g._search_pts)
			claimed.append(g.nav_agent.target_position)
	var tries := 0
	var rk: float = [1.0, 1.6, 2.6][clampi(main.alert_level, 0, 2)]
	var want: int = [3, 4, 6][clampi(main.alert_level, 0, 2)] + (1 if vigilant_t > 0.0 else 0)
	while _search_pts.size() < want and tries < 24:
		tries += 1
		var p: Vector3 = investigate_pos + dir_vec(randf() * TAU) * randf_range(3.0, 8.5) * rk
		var q: Vector3 = NavigationServer3D.map_get_closest_point(map0, p)
		var ok := true
		for c in claimed:
			if _flat_dist(c, q) < 3.7:
				ok = false
				break
		if ok or tries > 18:
			_search_pts.append(q)
			claimed.append(q)
	vigilant_t = maxf(vigilant_t, VIGIL_TIME * 0.5)
	nav_agent.target_position = global_position


func _walk(delta: float, speed_mul: float) -> bool:
	## hedefe yuru; vardiysa true
	if kind == "kule":
		_stop()
		var tgt: Vector3 = nav_agent.target_position
		if _flat_dist(tgt, global_position) > 0.3:
			facing = lerp_angle(facing, angle_of(tgt - global_position), minf(1.0, delta * 3.0))
		return true
	if nav_agent.is_navigation_finished():
		_stop()
		return true
	var next: Vector3 = nav_agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0
	if dir.length() < 0.01:
		_stop()
		return nav_agent.is_navigation_finished()
	dir = dir.normalized()
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.25
		_slow = main.level.speed_mul(global_position)
		# takilma: 2 sn ilerleyemezse hedefi birak
		if _flat_dist(global_position, _last_pos) < 0.05:
			_stuck_t += 0.25
		else:
			_stuck_t = 0.0
		_last_pos = global_position
		if _stuck_t > 2.0:
			_stuck_t = 0.0
			_stop()
			return true
	var mul := speed_mul * (1.3 if main.alert_level > 0 else 1.0) * _slow
	velocity.x = dir.x * SPEED * mul
	velocity.z = dir.z * SPEED * mul
	facing = lerp_angle(facing, angle_of(dir), minf(1.0, delta * 5.0))
	return false


func _go_patrol() -> void:
	state = &"patrol"
	if reinforcement and waypoints.is_empty():
		waypoints = [investigate_pos]
	if waypoints.size() > 0:
		nav_agent.target_position = waypoints[wp_i]


func _set_investigate(p: Vector3) -> void:
	investigate_pos = p
	state = &"investigate"
	nav_agent.target_position = p


func enter_combat(tgt) -> void:
	if not alive:
		return
	var was := state == &"combat"
	state = &"combat"
	target = tgt
	suspicion = 1.0
	investigate_pos = tgt.global_position
	if not was:
		flank = randf_range(-1.0, 1.0)
		shout_t = 1.5
		_fire_t = [1.0, 0.7, 0.45][clampi(main.alert_level, 0, 2)] * (0.85 if kind == "elit" else 1.0)
		var wr := WHISTLE * (1.6 if kind == "subay" else 1.0)
		for g in get_tree().get_nodes_in_group("guards"):
			if g != self and g.alive and g.state != &"combat" and g.state != &"alarm_run" and _flat_dist(g.global_position, global_position) < wr:
				g.alerted_by(tgt)
		main.combat_alarm(tgt.global_position, self)


func alerted_by(tgt) -> void:
	if _los_to(tgt) and _flat_dist(global_position, tgt.global_position) < view_range() * 1.2:
		enter_combat(tgt)
	else:
		suspicion = 0.5
		_set_investigate(tgt.global_position)


func hear_noise(p: Vector3) -> void:
	if not alive or state == &"combat" or state == &"alarm_run" or carried:
		return
	_set_investigate(p)


func hear_distraction(p: Vector3) -> void:
	if not alive or carried or state == &"combat" or state == &"alarm_run":
		return
	suspicion = maxf(suspicion, 0.25)
	_set_investigate(p)


func run_to_siren(sp: Vector3, incident: Vector3) -> void:
	state = &"alarm_run"
	siren_pos = sp
	investigate_pos = incident
	nav_agent.target_position = sp


func sweep(p: Vector3) -> void:
	if not alive or carried:
		return
	vigilant_t = VIGIL_TIME
	_set_investigate(p + dir_vec(randf() * TAU) * randf_range(4.0, 16.0))


func knock_out() -> void:
	if not alive:
		return
	knocked = true
	_wake_t = 40.0
	kill()


func tie_up() -> void:
	tied = true
	_label.text = ""


func _wake_up() -> void:
	knocked = false
	alive = true
	hp = max_hp * 0.6
	main.bodies.erase(self)
	discovered = false
	hidden_body = false
	collision_layer = LV.L_GUARD
	model.revive()
	vigilant_t = VIGIL_TIME * 2.0
	suspicion = 0.6
	investigate_pos = global_position
	main.guard_woke(self)
	_start_search()


func take_damage(amount: float, from: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	main.blood_fx(global_position + Vector3(0, 1.2, 0))
	if hp <= 0.0:
		kill()
		return
	model.hit()
	var shooter = main.player
	if shooter != null and shooter.alive:
		enter_combat(shooter)


# ---------------- Algilama ----------------
func can_see_point(p: Vector3, crouched := false, need_soft := true) -> bool:
	var d := p - global_position
	d.y = 0
	var r := view_range() * (NEAR_FRAC if crouched else 1.0)
	if d.length() > r:
		return false
	if absf(wrapf(angle_of(d) - facing, -PI, PI)) > VIEW_HALF * (1.12 if vigilant_t > 0.0 else 1.0):
		return false
	if main.level.has_los(eye(), p):
		return true
	if not need_soft:
		return false
	var bush_r := BUSH_SEE * (0.7 if crouched else 1.0) * _stat(1)
	bush_r *= [1.0, 1.35, 1.75][clampi(main.alert_level, 0, 2)]
	if state == &"search" or state == &"investigate":
		bush_r *= 1.15
	return d.length() < bush_r and main.level.has_los(eye(), p, true)


func _watch(delta: float) -> void:
	if state == &"combat" or state == &"alarm_run":
		return
	if main.far_from_player(global_position):
		_far_t -= delta
		if _far_t > 0.0:
			return
		delta = 0.2 - _far_t
		_far_t = 0.2
	var u = main.player
	var spotted = null
	var sd := 0.0
	for v in main.targets():
		if not v.alive:
			continue
		var cr: bool = v.is_crouching()
		var dd := _flat_dist(global_position, v.global_position)
		var hv := Vector2(v.velocity.x, v.velocity.z).length()
		var feel: bool = dd < PERIPHERAL and not cr and hv > 0.5
		if feel or can_see_point(v.aim_point(), cr or v.is_hidden()):
			spotted = v
			sd = dd
			break
	if spotted != null:
		var near := clampf(1.0 - sd / view_range(), 0.15, 1.0)
		var rate := (0.7 + near * 2.6) * _stat(2)
		if vigilant_t > 0.0:
			rate *= 1.15
		if main.alert_level == 1:
			rate *= 1.4
		elif main.alert_level >= 2:
			rate *= 2.0
		suspicion += delta * rate
		investigate_pos = spotted.global_position
		if state != &"suspicious":
			state = &"suspicious"
			_stop()
		if suspicion >= 1.0:
			enter_combat(spotted)
			return
	else:
		suspicion = maxf(0.0, suspicion - delta * 0.35)

	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.25
	# kosan oyuncunun ayak sesi (duvar arkasindan da)
	if u != null and u.alive and u.is_running() and (state == &"patrol" or state == &"search"):
		if _flat_dist(global_position, u.global_position) < 7.5:
			_set_investigate(u.global_position)
			return
	for g in main.bodies:
		if not g.discovered and not g.hidden_body and not g.carried and can_see_point(g.global_position + Vector3(0, 0.3, 0), false, false):
			g.discovered = true
			_set_investigate(g.global_position)
			main.body_found(g.global_position, self)
			return
	if buddy != null and not _buddy_checked and (state == &"patrol" or state == &"search"):
		if not buddy.alive:
			_buddy_dead_t += 0.25
			if _buddy_dead_t > 6.0 and can_see_point(buddy_post + Vector3(0, 1.0, 0)):
				_buddy_checked = true
				main.buddy_missing(self, buddy_post)
				_set_investigate(buddy_post)
				return


func update_cone() -> void:
	## taktik harita icin goz hizasindan isinlarla gercek gorus alani
	_imesh.clear_surfaces()
	if not alive:
		return
	var c := cone_color()
	var e := eye()
	var r := view_range()
	var pts: Array = []
	for i in RAYS + 1:
		var a := facing - VIEW_HALF + (VIEW_HALF * 2.0) * float(i) / RAYS
		var hit: Vector3 = main.level.ray_end(e, e + dir_vec(a) * r)
		pts.append(Vector3(hit.x, 0.15, hit.z))
	var o := Vector3(global_position.x, 0.15, global_position.z)
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _cone_mat)
	for i in RAYS:
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(o)
		_imesh.surface_set_color(Color(c, c.a * 0.4))
		_imesh.surface_add_vertex(pts[i])
		_imesh.surface_set_color(Color(c, c.a * 0.4))
		_imesh.surface_add_vertex(pts[i + 1])
	_imesh.surface_end()


func clear_cone() -> void:
	_imesh.clear_surfaces()


func cone_color() -> Color:
	if state == &"combat" or state == &"alarm_run":
		return Color(1.0, 0.2, 0.15, 0.5)
	if state == &"investigate" or state == &"search":
		return Color(1.0, 0.6, 0.2, 0.42)
	if suspicion > 0.0:
		return Color(1.0, 0.85, 0.2, 0.4 + suspicion * 0.2)
	return Color(0.4, 0.8, 1.0, 0.35)


func kill() -> void:
	if not alive:
		return
	alive = false
	main.bodies.append(self)
	if drops != "":
		main.level.add_pickup({"type": "key", "item": drops, "pos": global_position + dir_vec(facing + 1.0) * 0.7, "count": 1})
		main.hud.toast("Asker bir anahtar düşürdü!")
	if state == &"alarm_run":
		main.runner_stopped(self)
	hp = 0.0
	suspicion = 0.0
	target = null
	_stop()
	_label.text = ""
	clear_cone()
	collision_layer = 0
	model.die()


func status_text() -> String:
	if knocked:
		return "bağlı" if tied else "baygın"
	return "ölü"
