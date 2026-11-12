extends SceneTree
## Asker modeli yakin plan: devriye, nisan/ates, olum
var main
var out := "/tmp/asker"


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _snap(name: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "_" + name + ".png")
	print("kaydedildi ", name)


func _look(p, at: Vector3, side: float, dist: float) -> void:
	var g_dir: Vector3 = at
	var pos := g_dir + Vector3(cos(side), 0, sin(side)) * dist
	p.global_position = Vector3(pos.x, 0.05, pos.z)
	var to: Vector3 = at - p.global_position
	p.set_facing(atan2(to.z, to.x))
	p.pitch = -0.08
	p.head.rotation.x = p.pitch


func _run() -> void:
	main.start_level("res://levels/bolum0.json")
	while main.loading:
		await process_frame
	var gs = main.get_tree().get_nodes_in_group("guards")
	var g = null
	for h in gs:
		if h.waypoints.size() > 1:
			g = h
			break
	var p = main.player
	p.crouched = true
	for i in 120:
		await physics_frame
		_look(p, g.global_position, g.facing + PI / 2, 3.2)
	await _snap("devriye")
	p.crouched = false
	var fpos: Vector3 = g.global_position
	var fa: float = g.facing
	g.enter_combat(p)
	for i in 70:
		await physics_frame
		_look(p, g.global_position, fa + 1.15, 3.6)
	await _snap("nisan")
	for i in 40:
		await physics_frame
		if g.model._oneshot == "Pistol_Shoot":
			break
	await _snap("ates")
	g.kill()
	for i in 90:
		await physics_frame
	await _snap("olum")
	quit()
