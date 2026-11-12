extends CharacterBody3D
## Birinci sahis komando (Komando'daki commando.gd'nin FPS hali).
## Silahlar: 1 bicak (sessiz, arkadan tek vurus), 2 yumruk (bayiltir), 3 tabanca (gurultulu), 4 tas (dikkat dagitir)
## E: etkilesim (al / bagla / ceset tasi-birak / kapi / gorev), Ctrl-C: comel, Shift: kos, Z: islik

const LV := preload("res://scripts/level3d.gd")

const WALK := 3.0
const RUN := 5.6
const CROUCH := 1.6
const CARRY_MUL := 0.6
const EYE_STAND := 1.62
const EYE_CROUCH := 0.95
const MELEE_R := 1.7
const PISTOL_RANGE := 60.0
const PISTOL_DMG := 40.0
const PISTOL_COOLDOWN := 0.55
const PISTOL_NOISE := 21.0
const KNIFE_FRONT_DMG := 35.0
const THROW_RANGE := 16.0
const STONE_NOISE := 10.0
const WHISTLE_R := 10.0
const WHISTLE_CD := 5.0
const WEAPONS := ["bicak", "yumruk", "tabanca", "tas"]
const WEAPON_NAMES := {"bicak": "Bıçak", "yumruk": "Yumruk", "tabanca": "Tabanca", "tas": "Taş"}

var main
var alive := true
var hp := 100.0
var max_hp := 100.0
var ammo := 12
var stones := 4
var medkits := 0
var weapon := 0
var crouched := false
var running := false
var carrying = null
var head: Node3D
var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var sens := 0.0025
var touch_move := Vector2.ZERO          # dokunmatik joystick (-1..1)
var _cool := 0.0
var _whistle_t := 0.0
var _bob := 0.0
var _shape: CapsuleShape3D
var _cs: CollisionShape3D
var _hand: Node3D
var _hand_kick := 0.0
var _hold_t := 0.0                      # basili tutma (kurulum / sabotaj)
var hurt_t := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = LV.L_PLAYER
	collision_mask = LV.L_WORLD | LV.L_MOVE
	floor_snap_length = 0.3
	_cs = CollisionShape3D.new()
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.32
	_shape.height = 1.8
	_cs.shape = _shape
	_cs.position.y = 0.9
	add_child(_cs)
	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 160.0
	cam.cull_mask = 0xFFFFF & ~LV.V_MAP
	head.add_child(cam)
	_build_hand()


func _build_hand() -> void:
	_hand = Node3D.new()
	_hand.position = Vector3(0.28, -0.25, -0.45)
	cam.add_child(_hand)
	_refresh_hand()


func _refresh_hand() -> void:
	for c in _hand.get_children():
		c.queue_free()
	var w: String = WEAPONS[weapon]
	var col := Color(0.25, 0.27, 0.25)
	var sz := Vector3(0.05, 0.05, 0.3)
	match w:
		"bicak":
			col = Color(0.75, 0.77, 0.8)
			sz = Vector3(0.02, 0.04, 0.26)
		"yumruk":
			col = Color(0.8, 0.62, 0.5)
			sz = Vector3(0.09, 0.09, 0.11)
		"tabanca":
			col = Color(0.15, 0.15, 0.16)
			sz = Vector3(0.05, 0.1, 0.22)
		"tas":
			col = Color(0.5, 0.5, 0.48)
			sz = Vector3(0.08, 0.07, 0.08)
	var bm := BoxMesh.new()
	bm.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand.add_child(mi)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 0.35)
	var ai := MeshInstance3D.new()
	ai.mesh = arm
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.3, 0.34, 0.24)
	ai.material_override = am
	ai.position = Vector3(0.02, -0.04, 0.22)
	ai.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand.add_child(ai)


func set_facing(a: float) -> void:
	## 2D aci (0 = +x) -> kamera
	yaw = -a - PI / 2
	rotation.y = yaw


func is_crouching() -> bool:
	return crouched


func is_running() -> bool:
	return running and Vector2(velocity.x, velocity.z).length() > 3.5


func is_hidden() -> bool:
	return crouched and main.level.in_bush(global_position)


func aim_point() -> Vector3:
	## askerlerin bakip ates ettigi nokta (gogus)
	return global_position + Vector3(0, 0.62 if crouched else 1.3, 0)


func look(rel: Vector2) -> void:
	yaw -= rel.x * sens
	pitch = clampf(pitch - rel.y * sens, -1.45, 1.45)
	rotation.y = yaw
	head.rotation.x = pitch


func _unhandled_input(e: InputEvent) -> void:
	if not alive or main.map_mode or main.game_over or main.menu_open:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(e.relative)
	elif e.is_action_pressed("ates"):
		attack()
	elif e.is_action_pressed("comel"):
		toggle_crouch()
	elif e.is_action_pressed("islik"):
		whistle()
	elif e.is_action_pressed("silah_sonraki"):
		set_weapon((weapon + 1) % WEAPONS.size())
	elif e.is_action_pressed("silah_onceki"):
		set_weapon((weapon + WEAPONS.size() - 1) % WEAPONS.size())
	elif e.is_action_pressed("ilac"):
		use_medkit()
	else:
		for i in WEAPONS.size():
			if e.is_action_pressed("silah_%d" % (i + 1)):
				set_weapon(i)


func set_weapon(i: int) -> void:
	weapon = i
	_refresh_hand()


func toggle_crouch() -> void:
	if crouched:
		# kalkacak yer var mi
		var q := PhysicsShapeQueryParameters3D.new()
		var s := CapsuleShape3D.new()
		s.radius = 0.3
		s.height = 1.8
		q.shape = s
		q.transform = Transform3D(Basis(), global_position + Vector3(0, 0.95, 0))
		q.collision_mask = LV.L_WORLD
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return
	crouched = not crouched
	_shape.height = 1.1 if crouched else 1.8
	_cs.position.y = _shape.height / 2


func _physics_process(delta: float) -> void:
	_cool -= delta
	_whistle_t -= delta
	hurt_t = maxf(0.0, hurt_t - delta)
	if not alive or main.game_over:
		velocity = Vector3.ZERO
		return
	var inp := Input.get_vector("sol", "sag", "ileri", "geri")
	if touch_move.length() > 0.05:
		inp = touch_move
	running = Input.is_action_pressed("kos") or main.hud.touch_run
	if running and crouched and inp.length() > 0.1:
		toggle_crouch()
	var spd := CROUCH if crouched else (RUN if running else WALK)
	if carrying != null:
		spd = minf(spd, WALK) * CARRY_MUL
		running = false
	spd *= main.level.speed_mul(global_position)
	if main.map_mode or main.menu_open:
		inp = Vector2.ZERO
	var dir := (transform.basis * Vector3(inp.x, 0, inp.y))
	dir.y = 0
	dir = dir.normalized() * minf(inp.length(), 1.0)
	velocity.x = lerpf(velocity.x, dir.x * spd, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, dir.z * spd, minf(1.0, delta * 12.0))
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.3
	move_and_slide()
	global_position = main.level.clamp_inside(global_position)
	# kamera yuksekligi + yurume sallantisi
	var hv := Vector2(velocity.x, velocity.z).length()
	_bob += delta * hv * 2.2
	var eye_y := EYE_CROUCH if crouched else EYE_STAND
	head.position.y = lerpf(head.position.y, eye_y + sin(_bob * 2.0) * 0.03 * minf(hv / 3.0, 1.0), minf(1.0, delta * 10.0))
	_hand_kick = maxf(0.0, _hand_kick - delta * 4.0)
	_hand.position = Vector3(0.28, -0.25 + sin(_bob) * 0.008, -0.45 + _hand_kick * 0.12)
	_hand.rotation.x = _hand_kick * 0.6
	if carrying != null:
		carrying.global_position = global_position + transform.basis * Vector3(0.0, 0.0, 0.2)
		carrying.rotation.y = rotation.y
	_hold(delta)


func _hold(delta: float) -> void:
	## E basili tutulunca suren eylemler (patlayici kurma, sabotaj)
	if Input.is_action_pressed("etkilesim") or main.hud.touch_use_held:
		var it = main.current_interaction
		if it != null and it.get("hold", 0.0) > 0.0:
			_hold_t += delta
			main.hud.hold_progress = _hold_t / float(it["hold"])
			if _hold_t >= float(it["hold"]):
				_hold_t = 0.0
				main.hud.hold_progress = 0.0
				it["do"].call()
			return
	_hold_t = 0.0
	main.hud.hold_progress = 0.0


func aim_ray(dist: float, mask := LV.L_WORLD | LV.L_GUARD) -> Dictionary:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * dist
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	q.collide_with_areas = false
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		r = {"position": to, "collider": null}
	return r


func _guard_in_front(r: float):
	var best = null
	var bd := r
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	for g in get_tree().get_nodes_in_group("guards"):
		if not g.alive:
			continue
		var to: Vector3 = g.global_position - global_position
		to.y = 0
		var d := to.length()
		if d < bd and fwd.dot(to.normalized()) > 0.6 and main.level.has_los(cam.global_position, g.eye() - Vector3(0, 0.4, 0), true):
			bd = d
			best = g
	return best


func attack() -> void:
	if carrying != null:
		drop_body()
		return
	if _cool > 0.0:
		return
	var w: String = WEAPONS[weapon]
	_hand_kick = 1.0
	match w:
		"bicak", "yumruk":
			_cool = 0.6
			var g = _guard_in_front(MELEE_R)
			if g == null:
				return
			var from_behind: bool = absf(wrapf(g.angle_of(global_position - g.global_position) - g.facing, -PI, PI)) > 1.75
			var unaware: bool = g.state != &"combat" and g.suspicion < 0.95
			if w == "bicak":
				if from_behind or unaware:
					g.kill()
					main.stats["knife"] += 1
					main.scuffle(g.global_position)
				else:
					g.take_damage(KNIFE_FRONT_DMG, global_position)
			else:
				if from_behind or unaware:
					g.knock_out()
					main.stats["knockouts"] += 1
					main.scuffle(g.global_position)
					main.hud.toast("Asker bayıldı (~40 sn). Bağlamak için E.")
				else:
					g.take_damage(8.0, global_position)
		"tabanca":
			if ammo <= 0:
				main.hud.toast("Mermi yok")
				_cool = 0.3
				return
			ammo -= 1
			_cool = PISTOL_COOLDOWN
			main.stats["shots"] += 1
			var r := aim_ray(PISTOL_RANGE)
			main.gunshot_fx(cam.global_position - cam.global_transform.basis.z * 0.5 + cam.global_transform.basis.x * 0.25, r["position"])
			main.make_noise(global_position, PISTOL_NOISE, null)
			var col = r["collider"]
			if col != null and col.is_in_group("guards"):
				var head_shot: bool = r["position"].y > col.global_position.y + 1.5
				col.take_damage(PISTOL_DMG * (2.6 if head_shot else 1.0), global_position)
		"tas":
			if stones <= 0:
				main.hud.toast("Taş kalmadı")
				_cool = 0.3
				return
			stones -= 1
			_cool = 0.8
			var r2 := aim_ray(THROW_RANGE, LV.L_WORLD)
			var p: Vector3 = r2["position"]
			p.y = 0
			main.stone_fx(cam.global_position, p)
			get_tree().create_timer(0.5, false).timeout.connect(func(): main.distract(p, STONE_NOISE))


func whistle() -> void:
	if _whistle_t > 0.0:
		return
	_whistle_t = WHISTLE_CD
	var n: int = main.distract(global_position, WHISTLE_R)
	main.hud.toast("Islık çaldın" + (" – %d asker bakmaya geliyor" % n if n > 0 else ""))


func use_medkit() -> void:
	if medkits <= 0 or hp >= max_hp:
		return
	medkits -= 1
	hp = minf(max_hp, hp + 50.0)
	main.hud.toast("İlk yardım: +50 can")


func pick_body(g) -> void:
	carrying = g
	g.carried = true
	g.hidden_body = false
	main.hud.toast("Cesedi taşıyorsun (E / ateş: bırak). Çalılığa bırakırsan saklanır.")


func drop_body() -> void:
	if carrying == null:
		return
	var g = carrying
	carrying = null
	g.carried = false
	g.global_position = global_position + transform.basis * Vector3(0, 0, -0.9)
	g.global_position.y = global_position.y
	if main.level.in_bush(g.global_position):
		g.hidden_body = true
		main.hud.toast("Ceset çalılığa saklandı")


func take_damage(amount: float, _from: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	hurt_t = 0.5
	main.stats["damage"] += amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		drop_body()
		main.lose("Komando öldü")
