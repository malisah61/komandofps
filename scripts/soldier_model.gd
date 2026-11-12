extends Node3D
## 3D asker modeli: Quaternius Universal Animation Library (CC0) iskeleti + hareketleri,
## ustune kiyafet (kemik agirligina gore boyama: ceket, pantolon, cizme, ten) ve teçhizat
## (Stahlhelm / subay kasketi, sirt cantasi, tufek, MP40, matara). Komando'daki Blender
## asker2.py ile ayni kiyafet mantigi; burada calisma aninda, golgelendiricide yapiliyor.

const UAL := preload("res://assets/models/ual.glb")

# rutbe -> kiyafet
const OUTFITS := {
	"er":    {"top": Color(0.38, 0.41, 0.34), "pants": Color(0.32, 0.34, 0.29), "boots": Color(0.08, 0.07, 0.06),
			  "head": "stahlhelm", "head_color": Color(0.28, 0.31, 0.26), "rifle": true},
	"kule":  {"top": Color(0.38, 0.41, 0.34), "pants": Color(0.32, 0.34, 0.29), "boots": Color(0.08, 0.07, 0.06),
			  "head": "stahlhelm", "head_color": Color(0.28, 0.31, 0.26), "rifle": true},
	"kis":   {"top": Color(0.86, 0.87, 0.88), "pants": Color(0.78, 0.79, 0.8), "boots": Color(0.1, 0.09, 0.08),
			  "head": "stahlhelm", "head_color": Color(0.9, 0.9, 0.92), "rifle": true},
	"elit":  {"top": Color(0.2, 0.22, 0.19), "pants": Color(0.17, 0.18, 0.16), "boots": Color(0.05, 0.05, 0.05),
			  "head": "stahlhelm", "head_color": Color(0.16, 0.17, 0.15), "rifle": true},
	"subay": {"top": Color(0.44, 0.46, 0.4), "pants": Color(0.25, 0.26, 0.24), "boots": Color(0.04, 0.04, 0.04),
			  "head": "cap", "head_color": Color(0.36, 0.38, 0.33), "rifle": false},
	"komando": {"top": Color(0.3, 0.33, 0.22), "pants": Color(0.27, 0.29, 0.2), "boots": Color(0.15, 0.11, 0.08),
			  "head": "beret", "head_color": Color(0.12, 0.25, 0.12), "rifle": false},
	"direnisci": {"top": Color(0.33, 0.27, 0.22), "pants": Color(0.22, 0.22, 0.25), "boots": Color(0.12, 0.09, 0.07),
			  "head": "beret", "head_color": Color(0.1, 0.1, 0.12), "rifle": false},
	"pilot": {"top": Color(0.42, 0.32, 0.2), "pants": Color(0.3, 0.3, 0.26), "boots": Color(0.1, 0.08, 0.06),
			  "head": "none", "head_color": Color.BLACK, "rifle": false},
	"alman_subay": {"top": Color(0.44, 0.46, 0.4), "pants": Color(0.25, 0.26, 0.24), "boots": Color(0.04, 0.04, 0.04),
			  "head": "cap", "head_color": Color(0.36, 0.38, 0.33), "rifle": false},
}

const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 c_skin : source_color;
uniform vec4 c_top : source_color;
uniform vec4 c_pants : source_color;
uniform vec4 c_boots : source_color;
uniform vec4 c_belt : source_color;
uniform float bone_part[64];
varying vec3 col;
void vertex() {
	int bi = int(BONE_INDICES.x);
	float w = BONE_WEIGHTS.x;
	if (BONE_WEIGHTS.y > w) { bi = int(BONE_INDICES.y); w = BONE_WEIGHTS.y; }
	if (BONE_WEIGHTS.z > w) { bi = int(BONE_INDICES.z); w = BONE_WEIGHTS.z; }
	if (BONE_WEIGHTS.w > w) { bi = int(BONE_INDICES.w); w = BONE_WEIGHTS.w; }
	float p = bone_part[clamp(bi, 0, 63)];
	if (p < 0.5) col = c_skin.rgb;
	else if (p < 1.5) col = c_top.rgb;
	else if (p < 2.5) col = c_pants.rgb;
	else if (p < 3.5) col = c_boots.rgb;
	else col = c_belt.rgb;
}
void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.88;
}
"""

static var _shader: Shader

var outfit := "er"
var anim: AnimationPlayer
var skel: Skeleton3D
var mesh: MeshInstance3D
var _cur := ""
var _oneshot := ""
var _hand_gun: Node3D
var _back_rifle: Node3D
var muzzle: OmniLight3D
var _flash: MeshInstance3D
var _dead := false

const LOOPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Fwd", "Crouch_Idle", "Pistol_Idle", "Pistol_Aim_Neutral", "Idle_Torch", "Fixing_Kneeling", "Sitting_Idle"]


func _ready() -> void:
	var inst := UAL.instantiate()
	add_child(inst)
	# gltf ileri yonu +Z; oyunda ileri -Z
	inst.rotation.y = PI
	skel = inst.find_child("Skeleton3D", true, false)
	mesh = inst.find_child("Mannequin", true, false)
	anim = inst.find_child("AnimationPlayer", true, false)
	for n in LOOPS:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_finished)
	_paint()
	_gear()
	mesh.visibility_range_end = 140.0
	play("Idle")


func _part(bone: String) -> float:
	var b := bone.to_lower()
	if "head" in b or "neck" in b or "hand" in b or "f_" in b or "thumb" in b:
		return 0.0
	if "foot" in b or "toe" in b or "shin" in b:
		return 3.0          # cizme (Alman yuruyus cizmesi incige kadar)
	if "thigh" in b:
		return 2.0
	if "hips" in b:
		return 4.0          # kemer / pantolon ust
	return 1.0


func _paint() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var o: Dictionary = OUTFITS.get(outfit, OUTFITS["er"])
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("c_skin", Color(0.82, 0.65, 0.52))
	m.set_shader_parameter("c_top", o["top"])
	m.set_shader_parameter("c_pants", o["pants"])
	m.set_shader_parameter("c_boots", o["boots"])
	m.set_shader_parameter("c_belt", o["pants"].darkened(0.15))
	var parts := PackedFloat32Array()
	parts.resize(64)
	var sk: Skin = mesh.skin
	for i in mini(sk.get_bind_count(), 64):
		var bn := String(sk.get_bind_name(i))
		if bn == "":
			var bb := sk.get_bind_bone(i)
			bn = skel.get_bone_name(bb) if bb >= 0 else ""
		parts[i] = _part(bn)
	m.set_shader_parameter("bone_part", parts)
	mesh.material_override = m


func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	return ba


func _part_mesh(m: Mesh, mat: Material, parent: Node3D, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


func _gear() -> void:
	var o: Dictionary = OUTFITS.get(outfit, OUTFITS["er"])
	var head := _attach("DEF-head")
	var hc: Color = o["head_color"]
	match o["head"]:
		"stahlhelm":
			var s := SphereMesh.new()
			s.radius = 0.155
			s.height = 0.2
			s.is_hemisphere = true
			_part_mesh(s, _mat(hc, 0.55, 0.15), head, Vector3(0, 0.13, 0.005), Vector3.ZERO, Vector3(1, 1.15, 1.08))
			var rim := CylinderMesh.new()
			rim.top_radius = 0.17
			rim.bottom_radius = 0.185
			rim.height = 0.05
			rim.radial_segments = 16
			_part_mesh(rim, _mat(hc, 0.55, 0.15), head, Vector3(0, 0.12, 0.005))
		"cap":
			var c := CylinderMesh.new()
			c.top_radius = 0.135
			c.bottom_radius = 0.115
			c.height = 0.09
			_part_mesh(c, _mat(hc, 0.7), head, Vector3(0, 0.18, 0))
			_part_mesh(_box(Vector3(0.17, 0.015, 0.09)), _mat(Color(0.04, 0.04, 0.04), 0.3), head, Vector3(0, 0.145, 0.11), Vector3(0.25, 0, 0))
		"beret":
			var bs := SphereMesh.new()
			bs.radius = 0.13
			bs.height = 0.1
			_part_mesh(bs, _mat(hc, 0.9), head, Vector3(0.02, 0.17, 0), Vector3(0, 0, -0.25))
	var spine := _attach("DEF-spine.003")
	if o["head"] == "stahlhelm":
		_part_mesh(_box(Vector3(0.28, 0.3, 0.13)), _mat(Color(0.3, 0.27, 0.2)), spine, Vector3(0, 0.05, -0.16))
	var hips := _attach("DEF-hips")
	_part_mesh(_box(Vector3(0.36, 0.06, 0.24)), _mat(Color(0.12, 0.1, 0.08), 0.5), hips, Vector3(0, 0.08, 0.0))
	var can := CylinderMesh.new()
	can.top_radius = 0.045
	can.bottom_radius = 0.05
	can.height = 0.14
	_part_mesh(can, _mat(Color(0.3, 0.32, 0.25)), hips, Vector3(0.17, 0.0, -0.06))
	# sirttaki tufek (Kar98k): devriyede
	if o["rifle"]:
		_back_rifle = Node3D.new()
		spine.add_child(_back_rifle)
		_back_rifle.position = Vector3(0.04, 0.0, -0.2)
		_back_rifle.rotation = Vector3(0, 0, 0.45)
		_rifle_mesh(_back_rifle)
	# eldeki silah (MP40 / Luger): catismada
	var hand := _attach("DEF-hand.R")
	_hand_gun = Node3D.new()
	hand.add_child(_hand_gun)
	# el kemigi: +Y parmaklar (ileri), +Z yukari -> silahin namlusu (+Z) ileri, ust yuzu (+Y) yukari
	_hand_gun.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	_hand_gun.position = Vector3(0.0, 0.06, 0.04)
	var metal := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.6)
	if o["rifle"]:
		_part_mesh(_box(Vector3(0.05, 0.08, 0.45)), metal, _hand_gun, Vector3(0, 0, 0.12))
		_part_mesh(_box(Vector3(0.03, 0.18, 0.04)), metal, _hand_gun, Vector3(0, -0.11, 0.18))      # sarjor
		_part_mesh(_box(Vector3(0.02, 0.02, 0.2)), metal, _hand_gun, Vector3(0, 0.03, 0.42))
	else:
		_part_mesh(_box(Vector3(0.035, 0.05, 0.2)), metal, _hand_gun, Vector3(0, 0, 0.06))
	_hand_gun.visible = false
	muzzle = OmniLight3D.new()
	muzzle.light_color = Color(1, 0.8, 0.45)
	muzzle.omni_range = 5.0
	muzzle.light_energy = 0.0
	muzzle.position = Vector3(0, 0.03, 0.56 if o["rifle"] else 0.2)
	_hand_gun.add_child(muzzle)
	var fm := SphereMesh.new()
	fm.radius = 0.07
	fm.height = 0.25
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1, 0.85, 0.4)
	_flash = _part_mesh(fm, fmat, _hand_gun, muzzle.position + Vector3(0, 0, 0.08), Vector3(PI / 2, 0, 0))
	_flash.visible = false


func _rifle_mesh(parent: Node3D) -> void:
	var wood := _mat(Color(0.38, 0.24, 0.12), 0.6)
	var metal := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.6)
	_part_mesh(_box(Vector3(0.05, 0.9, 0.06)), wood, parent, Vector3.ZERO)
	_part_mesh(_box(Vector3(0.025, 0.35, 0.025)), metal, parent, Vector3(0, 0.55, 0.01))


func weapon_ready(on: bool) -> void:
	if _hand_gun == null:
		return
	_hand_gun.visible = on and not _dead
	if _back_rifle != null:
		_back_rifle.visible = not on


func play(n: String, speed := 1.0, blend := 0.2) -> void:
	if _dead or _oneshot != "":
		anim.speed_scale = speed if _oneshot == "" else 1.0
		return
	if n != _cur:
		_cur = n
		anim.play(n, blend)
	anim.speed_scale = speed


func one_shot(n: String, blend := 0.08) -> void:
	if _dead:
		return
	_oneshot = n
	anim.speed_scale = 1.0
	anim.play(n, blend)
	anim.seek(0.0, true)


func fire() -> void:
	if muzzle == null:
		return
	muzzle.light_energy = 4.0
	_flash.visible = true
	one_shot("Pistol_Shoot")
	get_tree().create_timer(0.05, false).timeout.connect(func():
		if is_instance_valid(_flash):
			_flash.visible = false
			muzzle.light_energy = 0.0)


func hit() -> void:
	one_shot("Hit_Chest")


func die() -> void:
	_oneshot = ""
	_dead = true
	weapon_ready(false)
	anim.speed_scale = 1.0
	anim.play("Death01", 0.1)


func revive() -> void:
	_dead = false
	_cur = ""
	play("Idle")


func set_active(on: bool) -> void:
	## uzaktaki askerlerin animasyonu durur (performans)
	if anim.active != on:
		anim.active = on


func _on_finished(n: StringName) -> void:
	if String(n) == _oneshot:
		_oneshot = ""
		var c := _cur
		_cur = ""
		play(c if c != "" else "Idle")
