extends Node
## Gorev sistemi - Komando'nun mission.gd'si (ayni bolum verisi, ayni gorev turleri), FPS etkilesimiyle.
##   reach    - bir yere ulas ("say" konusma, "gives" esya)
##   take     - esyayi al (E)
##   rescue   - esiri kurtar (E), seni izler
##   destroy  - patlayici kur (E basili tut), 8 sn sonra patlar ("bridge": kopru indeksi)
##   have     - esyayi edin (askerden dusen anahtar)
##   sabotage - E basili tut "time" sn (kablo kes); "disables_barracks"
##   exit     - cikisa don (kurtarilanlar yaninda olmali)

const LV := preload("res://scripts/level3d.gd")
const PLANT_TIME := 2.0
const FUSE_TIME := 8.0
const BLAST_R := 5.5
const ITEM_NAMES := {
	"belge": "Gizli belge", "patlayici": "Patlayıcı", "tel_makasi": "Tel makası", "planlar": "Saldırı planları",
	"kodlar": "Radar kodları", "anahtar": "Anahtar",
}

var main
var objectives: Array = []
var items := {}
var bombs: Array = []             # [konum, kalan, gorev, dugum]
var npcs := {}                    # id -> npc
var markers := {}                 # gorev id -> Node3D
var elapsed := 0.0


func item_name(it: String) -> String:
	if ITEM_NAMES.has(it):
		return ITEM_NAMES[it]
	return it.replace("_", " ").capitalize()


func setup(level_data: Dictionary) -> void:
	var src: Array = level_data.get("objectives", [])
	if src.is_empty():
		src = [
			{"id": "belge", "type": "take", "text": "Gizli BELGEYİ çal", "pos": level_data["document"]},
			{"id": "kacis", "type": "exit", "text": "ÇIKIŞ bölgesine dön"},
		]
	for o in src:
		var d: Dictionary = o.duplicate(true)
		d["done"] = false
		if d.get("after") is String:
			d["after"] = [d["after"]]
		if d.has("pos"):
			d["p3"] = LV.P(d["pos"])
		d["r3"] = float(d.get("radius", 60)) * LV.S
		objectives.append(d)
		match d["type"]:
			"take":
				markers[d["id"]] = main.level.make_marker(d["p3"], item_name(d.get("item", "belge")).to_upper(), Color(1.0, 0.92, 0.4))
			"destroy":
				markers[d["id"]] = _target_marker(d["p3"], "HEDEF", Color(1, 0.45, 0.2))
			"sabotage":
				markers[d["id"]] = _target_marker(d["p3"], "SABOTAJ", Color(0.4, 0.8, 1))


func _target_marker(p: Vector3, text: String, c: Color) -> Node3D:
	var root := Node3D.new()
	root.position = p
	main.level.add_child(root)
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 1.4, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.3, 0.28)
	mi.material_override = m
	mi.position.y = 0.7
	root.add_child(mi)
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 40
	lab.pixel_size = 0.01
	lab.modulate = c
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position.y = 2.2
	root.add_child(lab)
	return root


func available(o: Dictionary) -> bool:
	for id in o.get("after", []):
		for p in objectives:
			if p["id"] == id and not p["done"]:
				return false
	return true


func required_left() -> int:
	var n := 0
	for o in objectives:
		if not o["done"] and not o.get("optional", false) and o["type"] != "exit":
			n += 1
	return n


func active_list() -> Array:
	var out: Array = []
	for o in objectives:
		if o["done"] or not available(o):
			continue
		if o["type"] == "exit" and required_left() > 0:
			continue
		out.append(o)
	return out


func _complete(o: Dictionary) -> void:
	o["done"] = true
	if markers.has(o["id"]) and o["type"] == "take":
		markers[o["id"]].queue_free()
		markers.erase(o["id"])
	main.objective_done(o)
	if o.has("done_say"):
		main.hud.show_dialog(o["done_say"])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _process(delta: float) -> void:
	if main.game_over or main.player == null:
		return
	elapsed += delta
	var c = main.player
	var cp: Vector3 = c.global_position
	for o in objectives:
		if o["done"] or not available(o):
			continue
		match o["type"]:
			"reach":
				if _flat(cp, o["p3"]) < maxf(o["r3"], 2.0):
					if o.has("gives"):
						var g: Dictionary = o["gives"]
						for k in g:
							items[k] = items.get(k, 0) + int(g[k])
							main.hud.toast("%s alındı (x%d)" % [item_name(k), int(g[k])])
					_complete(o)
					if o.has("say"):
						main.hud.show_dialog(o["say"])
			"have":
				if items.get(o["item"], 0) > 0:
					_complete(o)
			"exit":
				if required_left() == 0 and main.level.in_exit(cp):
					var ok := true
					for id in npcs:
						var n = npcs[id]
						if n.following and _flat(n.global_position, cp) > 8.0:
							ok = false
					if ok:
						_complete(o)
						main.win()
	var i := bombs.size() - 1
	var status := ""
	while i >= 0:
		bombs[i][1] -= delta
		status = "Patlama: %d" % ceili(bombs[i][1])
		if bombs[i][1] <= 0.0:
			_explode(bombs[i])
			bombs.remove_at(i)
		i -= 1
	main.hud.timer_text = status


func interaction(cp: Vector3):
	## oyuncunun yakinindaki gorev etkilesimi: {text, do, hold}
	for o in objectives:
		if o["done"] or not available(o):
			continue
		match o["type"]:
			"take":
				if _flat(cp, o["p3"]) < 1.8:
					return {"text": "Al: " + o["text"], "do": func(): _take(o)}
			"rescue":
				var n = npcs.get(o["npc"])
				if n != null and not n.following and _flat(cp, n.global_position) < 2.0:
					return {"text": "Kurtar: " + n.display_name, "do": func(): _rescue(o, n)}
			"sabotage":
				if _flat(cp, o["p3"]) < maxf(o["r3"], 2.2) and main.player.carrying == null:
					return {"text": "Sabotaj (basılı tut): " + o["text"], "hold": float(o.get("time", 4.0)), "do": func(): _sabotage(o)}
			"destroy":
				var planted := false
				for b in bombs:
					if b[2] == o:
						planted = true
				if not planted and _flat(cp, o["p3"]) < maxf(o["r3"], 2.5):
					if items.get("patlayici", 0) > 0 and main.player.carrying == null:
						return {"text": "Patlayıcı kur (basılı tut)", "hold": PLANT_TIME, "do": func(): _plant(o)}
					elif items.get("patlayici", 0) <= 0:
						return {"text": "Patlayıcı gerek", "do": func(): pass}
	return null


func _take(o: Dictionary) -> void:
	items[o.get("item", "belge")] = 1
	main.hud.toast(item_name(o.get("item", "belge")) + " alındı")
	_complete(o)


func _rescue(o: Dictionary, n) -> void:
	n.start_following()
	_complete(o)
	if o.has("say"):
		main.hud.show_dialog(o["say"])


func _sabotage(o: Dictionary) -> void:
	if o.has("disables_barracks"):
		var bi: int = int(o["disables_barracks"])
		if bi >= 0 and bi < main.level.barracks.size():
			main.level.barracks[bi][1] = 0
	main.hud.toast("Sabotaj tamam: " + o["text"])
	_complete(o)


func _plant(o: Dictionary) -> void:
	items["patlayici"] = items["patlayici"] - 1
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.2, 0.2)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.2, 0.1)
	m.emission_enabled = true
	m.emission = Color(1, 0.2, 0.1)
	mi.material_override = m
	main.level.add_child(mi)
	mi.global_position = main.player.global_position + Vector3(0, 0.1, 0)
	bombs.append([o["p3"], FUSE_TIME, o, mi])
	main.hud.toast("Patlayıcı kuruldu! 8 saniye – uzaklaş!")


func _explode(b: Array) -> void:
	var pos: Vector3 = b[0]
	var o: Dictionary = b[2]
	if is_instance_valid(b[3]):
		b[3].queue_free()
	main.explosion_fx(pos)
	if o.has("bridge"):
		main.level.break_bridge(int(o["bridge"]))
	if markers.has(o["id"]):
		markers[o["id"]].queue_free()
		markers.erase(o["id"])
	_complete(o)
	for g in get_tree().get_nodes_in_group("guards"):
		if g.alive and _flat(g.global_position, pos) < BLAST_R:
			g.kill()
	var u = main.player
	if u.alive and _flat(u.global_position, pos) < BLAST_R:
		u.take_damage(999.0, pos)
	main.make_noise(pos, 40.0, null)
	main.raise_alarm(pos, null)
