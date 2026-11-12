extends SceneTree
## Otomatik oyun testi (headless):  godot --headless -s res://tests/sim.gd [-- --test-level=res://levels/bolumN.json]
## 1) bolum kurulur, navmesh olusur, devriyeler yurur
## 2) asker onunde ayakta duran oyuncuyu fark eder (catisma)
## 3) arkadan bicak: sessiz, alarm yok
## 4) gorev: belgeyi al, cikisa git -> kazan

var main
var fails := 0
var level := "res://levels/bolum0.json"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test-level="):
			level = a.substr(13)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	if cond:
		print("  TAMAM  ", msg)
	else:
		fails += 1
		print("  HATA   ", msg)


func wait(sec: float) -> void:
	var n := int(sec * 60.0)
	for i in n:
		await physics_frame


func _start() -> void:
	var t0 := Time.get_ticks_msec()
	main.start_level(level)
	while main.loading:
		await process_frame
	print("  bolum yuklendi: %d ms" % (Time.get_ticks_msec() - t0))
	await wait(0.2)


func _guards() -> Array:
	return main.get_tree().get_nodes_in_group("guards")


func _run() -> void:
	print("== KomandoFPS testi: ", level)
	await _start()
	var gs := _guards()
	ok(gs.size() == main.level.data["guards"].size(), "asker sayisi %d" % gs.size())
	var nm: NavigationMesh = main.level.nav.navigation_mesh
	ok(nm.get_polygon_count() > 20, "navmesh poligon: %d" % nm.get_polygon_count())
	# oyuncuyu uzak bir koseye koy ki testi bozmasin
	main.player.global_position = main.level.start
	var walker = null
	for g in gs:
		if g.waypoints.size() > 1:
			walker = g
			break
	var p0: Vector3 = walker.global_position
	await wait(4.0)
	ok(walker.global_position.distance_to(p0) > 2.0, "devriye yuruyor (%.1f m)" % walker.global_position.distance_to(p0))

	# 2) gorulme
	var g = walker
	var front: Vector3 = g.global_position + g.dir_vec(g.facing) * 7.0
	front.y = g.global_position.y
	var los: bool = main.level.has_los(g.eye(), front + Vector3(0, 1.3, 0))
	main.player.global_position = front
	var seen := false
	for i in 240:
		await physics_frame
		if g.state == &"combat" or g.state == &"suspicious":
			seen = true
		if g.state == &"combat":
			break
	ok(not los or seen, "onundeki ayakta oyuncuyu fark etti (gorus=%s, durum=%s, suphe=%.2f)" % [los, g.state, g.suspicion])
	ok(g.state == &"combat" or g.state == &"alarm_run" or not los, "catismaya girdi / sirene kostu")

	# 3) arkadan bicak
	await _start()
	main.player.global_position = main.level.start
	await wait(0.5)
	gs = _guards()
	# en yalniz sabit nobetci (baskasi cesedi gormesin)
	var v = gs[0]
	var best := -1.0
	for h in gs:
		if h.kind == "kule" or h.waypoints.size() > 1:
			continue
		var nd := INF
		for k in gs:
			if k != h:
				nd = minf(nd, h.global_position.distance_to(k.global_position))
		if nd > best:
			best = nd
			v = h
	var behind: Vector3 = v.global_position - v.dir_vec(v.facing) * 1.1
	main.player.global_position = Vector3(behind.x, v.global_position.y, behind.z)
	main.player.set_facing(v.facing)
	main.player.set_weapon(0)
	await physics_frame
	main.player.attack()
	await wait(0.3)
	ok(not v.alive, "arkadan bicak oldurdu")
	ok(main.alert_level < 2, "kirmizi alarm yok (seviye %d)" % main.alert_level)
	# ceset tasima
	main.player.global_position = v.global_position + Vector3(0.5, 0, 0)
	await wait(0.1)
	var it = main.current_interaction
	ok(it != null and str(it["text"]).contains("Cesedi"), "ceset etkilesimi: %s" % (it["text"] if it else "yok"))

	# 4) gorev akisi (bolum 0: belge + cikis)
	if level.ends_with("bolum0.json"):
		var doc: Dictionary = main.mission.objectives[0]
		main.player.global_position = doc["p3"] + Vector3(0.6, 0.05, 0)
		await wait(0.1)
		it = main.current_interaction
		ok(it != null and str(it["text"]).begins_with("Al"), "belge etkilesimi: %s" % (it["text"] if it else "yok"))
		if it != null:
			main.interact()
		ok(main.mission.items.get("belge", 0) == 1, "belge alindi")
		main.player.global_position = Vector3(main.level.exit_rect.get_center().x, 0.05, main.level.exit_rect.get_center().y)
		await wait(0.3)
		ok(main.game_over and main.mission.required_left() == 0, "cikista kazandi")

	print("== SONUC: %s (%d hata)" % ["GECTI" if fails == 0 else "KALDI", fails])
	quit(1 if fails > 0 else 0)
