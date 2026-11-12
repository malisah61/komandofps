extends CharacterBody3D
## Dost karakter (direnisci, esir pilot, esir subay). Kurtarilinca oyuncuyu izler.
## Askerler izleyen dostu da gorebilir (Komando'daki gibi): gorulurse catisma baslar.

const LV := preload("res://scripts/level3d.gd")
const SoldierModel := preload("res://scripts/soldier_model.gd")
const OUTFITS := {
	"direnisci": Color(0.35, 0.3, 0.25), "pilot": Color(0.45, 0.36, 0.22), "komando": Color(0.3, 0.36, 0.22),
	"alman_subay": Color(0.48, 0.5, 0.44),
}

var main
var id := ""
var display_name := ""
var outfit := "direnisci"
var facing := 0.0
var following := false
var alive := true
var hp := 80.0
var nav_agent: NavigationAgent3D
var _repath := 0.0
var _crouch := false
var _body


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = 0
	collision_mask = LV.L_WORLD | LV.L_MOVE
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.88
	add_child(cs)
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 1.6
	nav_agent.radius = 0.4
	add_child(nav_agent)
	_body = SoldierModel.new()
	_body.outfit = outfit
	add_child(_body)
	var lab := Label3D.new()
	lab.text = display_name
	lab.font_size = 36
	lab.pixel_size = 0.007
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color(0.6, 1, 0.6)
	lab.position.y = 2.15
	add_child(lab)
	rotation.y = -facing - PI / 2


func start_following() -> void:
	following = true
	collision_layer = LV.L_PLAYER


func is_crouching() -> bool:
	return _crouch


func is_running() -> bool:
	return false


func is_hidden() -> bool:
	return _crouch and main.level.in_bush(global_position)


func aim_point() -> Vector3:
	return global_position + Vector3(0, 0.62 if _crouch else 1.3, 0)


func take_damage(amount: float, _from: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		alive = false
		_body.die()
		main.lose(display_name + " öldü")


func _physics_process(delta: float) -> void:
	if not alive or not following or main.game_over:
		velocity = Vector3.ZERO
		if alive and not following:
			_body.play("Sitting_Idle" if outfit == "pilot" or outfit == "komando" else "Idle")
		return
	var p = main.player
	_crouch = p.is_crouching()
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.4
		nav_agent.target_position = p.global_position - p.transform.basis.z * -1.4
	var d := Vector2(global_position.x - p.global_position.x, global_position.z - p.global_position.z).length()
	if d > 2.0 and not nav_agent.is_navigation_finished():
		var nx := nav_agent.get_next_path_position() - global_position
		nx.y = 0
		var spd := 1.7 if _crouch else (5.0 if d > 6.0 else 3.0)
		velocity.x = nx.normalized().x * spd
		velocity.z = nx.normalized().z * spd
		rotation.y = lerp_angle(rotation.y, atan2(-nx.x, -nx.z), minf(1.0, delta * 8.0))
	else:
		velocity.x = 0
		velocity.z = 0
	velocity.y = -0.5 if is_on_floor() else velocity.y - 18.0 * delta
	var hv := Vector2(velocity.x, velocity.z).length()
	if _crouch:
		_body.play("Crouch_Fwd" if hv > 0.2 else "Crouch_Idle", maxf(hv / 1.4, 0.6))
	elif hv > 3.5:
		_body.play("Sprint", hv / 5.5)
	elif hv > 0.2:
		_body.play("Walk", hv / 1.45)
	else:
		_body.play("Idle")
	move_and_slide()
