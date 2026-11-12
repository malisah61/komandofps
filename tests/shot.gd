extends SceneTree
## Ekran goruntusu:  xvfb-run godot -s res://tests/shot.gd -- --test-level=... --out=/tmp/x
var main
var level := "res://levels/bolum0.json"
var out := "/tmp/shot"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test-level="):
			level = a.substr(13)
		if a.begins_with("--out="):
			out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _snap(name: String) -> void:
	for i in 12:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out + "_" + name + ".png")
	print("kaydedildi ", out + "_" + name + ".png")


func _run() -> void:
	main.start_level(level)
	while main.loading:
		await process_frame
	for i in 90:
		await physics_frame
	await _snap("fps")
	# bir askere bak
	var g = main.get_tree().get_nodes_in_group("guards")[1]
	var p = main.player
	var at: Vector3 = g.global_position + g.dir_vec(g.facing + 2.5) * 9.0
	p.global_position = Vector3(at.x, 0.05, at.z)
	var to: Vector3 = g.global_position - p.global_position
	p.set_facing(atan2(to.z, to.x))
	p.crouched = false
	for i in 50:
		await physics_frame
	await _snap("asker")
	main.toggle_map()
	main.zoom_map(0.8)
	await _snap("harita")
	quit()
