extends Node3D
## Komando bolum dosyalarini (levels/*.json, 2D piksel koordinat) 3D dunyaya cevirir.
## Ayni veri dosyalari iki oyunda da kullanilir: 1 piksel = 5 cm (S).
## 2D (x, y)  ->  3D (x * S, 0, y * S)   (y asagi = +z)
##
## Fizik katmanlari:
##   1 (deger 1)  dunya: gorusu ve hareketi engeller
##   2 (deger 2)  askerler
##   3 (deger 4)  oyuncu
##   4 (deger 8)  yumusak engel (cali): hareketi engellemez, gorusu engeller, saklanma alani
## Gorsel katmanlar:
##   1 her sey, 2 yalniz taktik harita (koniler, isaretler), 3 yalniz FPS (cati, agac tepesi)

const S := 0.05
const WALL_T := 0.3
const WALL_H := 3.2
const DOOR_W := 1.7
const DOOR_H := 2.3

const L_WORLD := 1
const L_GUARD := 2
const L_PLAYER := 4
const L_SOFT := 8
const L_MOVE := 16        # yalniz hareketi engeller (su, dikenli tel): gorus gecer
const V_MAP := 2
const V_FPS := 4

# tur -> [hareketi engeller, gorusu engeller, yukseklik (m), renk]
const TYPES := {
	"hedge":   [true,  true,  1.8, Color(0.2, 0.36, 0.15)],
	"wall":    [true,  true,  2.4, Color(0.62, 0.6, 0.55)],
	"sandbag": [true,  true,  0.85, Color(0.74, 0.66, 0.46)],
	"bush":    [false, true,  1.35, Color(0.24, 0.44, 0.18)],
	"crate":   [true,  true,  1.2, Color(0.6, 0.45, 0.25)],
	"tree":    [true,  true,  7.0, Color(0.17, 0.33, 0.13)],
	"water":   [true,  false, 1.0, Color(0.22, 0.38, 0.5)],
	"fence":   [true,  true,  1.0, Color(0.48, 0.36, 0.22)],
	"tent":    [true,  true,  2.3, Color(0.44, 0.46, 0.32)],
	"truck":   [true,  true,  2.5, Color(0.31, 0.34, 0.25)],
	"tank":    [true,  true,  2.3, Color(0.37, 0.39, 0.34)],
	"rock":    [true,  true,  1.3, Color(0.52, 0.52, 0.5)],
	"tower":   [true,  false, 5.5, Color(0.45, 0.33, 0.2)],
	"tel":     [true,  false, 1.1, Color(0.5, 0.5, 0.48)],
	"projektor": [true, false, 5.0, Color(0.4, 0.42, 0.4)],
}

var data := {}
var size := Vector2(1600, 1100)          # piksel
var start := Vector3.ZERO
var exit_rect := Rect2()                 # metre (x, z)
var sirens: Array = []                   # Vector3
var barracks: Array = []                 # [pos, kalan, tur, gecikme]
var pickups: Array = []                  # {type, pos, node, taken, item, count}
var bushes: Array = []                   # [merkez Vector3, yaricap] ya da {poly}
var surfaces: Array = []                 # {poly: PackedVector2Array (m), type}
var bridges: Array = []                  # {rect, node}
var doors: Array = []                    # {pos, item, node} kilitli kapilar
var towers: Array = []                   # Vector3 platform ustu
var nav: NavigationRegion3D
var theme_name := ""
var _mats := {}


static func P(v) -> Vector3:
	return Vector3(float(v[0]) * S, 0.0, float(v[1]) * S)


static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func load_level(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Bolum acilamadi: " + path)
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("Bolum okunamadi: " + path)
		return false
	data = parsed
	size = Vector2(data["size"][0], data["size"][1])
	theme_name = str(data.get("theme", ""))
	start = P(data["start"])
	var e: Array = data["exit"]
	exit_rect = Rect2(e[0] * S, e[1] * S, e[2] * S, e[3] * S)

	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.region_min_size = 4.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = L_WORLD | L_MOVE
	nm.filter_baking_aabb = AABB(Vector3(-2, -1, -2), Vector3(size.x * S + 4, 8, size.y * S + 4))
	nav.navigation_mesh = nm
	add_child(nav)

	_build_ground()
	for r in data.get("roads", []):
		_flat_box(Rect2(r[0] * S, r[1] * S, r[2] * S, r[3] * S), 0.012, _road_color())
	for s in data.get("surfaces", []):
		var poly := _poly(s["points"])
		surfaces.append({"poly": poly, "type": s["type"]})
		var c := Color(0.36, 0.27, 0.17) if s["type"] == "mud" else (Color(0.55, 0.55, 0.53) if s["type"] == "beton" else Color(0.92, 0.94, 0.97))
		_flat_poly(poly, 0.016, c)
	var water_polys: Array = []
	var bridge_rects: Array = []
	for b in data.get("bridges", []):
		bridge_rects.append(Rect2(b[0] * S, b[1] * S, b[2] * S, b[3] * S))
	for o in data.get("obstacles", []):
		if o["type"] == "water":
			water_polys.append(_poly(o["points"]))
		else:
			_build_obstacle(o)
	_build_water(water_polys, bridge_rects)
	for b in data.get("buildings", []):
		_build_building(b)
	for sp in data.get("sirens", []):
		var p := P(sp)
		sirens.append(p)
		_build_siren(p)
	for bk in data.get("barracks", []):
		barracks.append([P(bk["pos"]), int(bk.get("count", 3)), str(bk.get("type", "er")), float(bk.get("delay", 8))])
		_build_barracks_marker(P(bk["pos"]))
	for pk in data.get("pickups", []):
		_add_pickup({"type": pk["type"], "pos": P(pk["pos"]), "item": pk.get("item", ""), "count": int(pk.get("count", 1))})
	_build_exit()
	_build_light()
	return true


func bake_nav(on_thread := false) -> void:
	nav.bake_navigation_mesh(on_thread)


# ---------------- sorgular ----------------
func has_los(a: Vector3, b: Vector3, ignore_soft := false) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, L_WORLD | (0 if ignore_soft else L_SOFT))
	q.collide_with_areas = not ignore_soft
	q.collide_with_bodies = true
	q.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func ray_end(a: Vector3, b: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(a, b, L_WORLD | L_SOFT)
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return b if r.is_empty() else r["position"]


func in_bush(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for b in bushes:
		if b is Array:
			if q.distance_to(flat(b[0])) < b[1]:
				return true
		elif Geometry2D.is_point_in_polygon(q, b["poly"]):
			return true
	return false


func surface_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for s in surfaces:
		if Geometry2D.is_point_in_polygon(q, s["poly"]):
			return s["type"]
	return ""


func speed_mul(p: Vector3) -> float:
	var s := surface_at(p)
	if s == "mud":
		return 0.75
	if s == "snow":
		return 0.85
	return 1.0


func in_exit(p: Vector3) -> bool:
	return exit_rect.has_point(Vector2(p.x, p.z))


func clamp_inside(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, 0.5, size.x * S - 0.5), p.y, clampf(p.z, 0.5, size.y * S - 0.5))


# ---------------- yapim ----------------
func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var k := "%s%s" % [c.to_html(), unshaded]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[k] = m
	return m


func _road_color() -> Color:
	return Color(0.8, 0.82, 0.86) if theme_name == "kar" else Color(0.42, 0.38, 0.3)


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0], p[1]) * S)
	return out


func _mesh(m: Mesh, pos: Vector3, c: Color, parent: Node = null, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat(c)
	mi.position = pos
	mi.layers = layers
	(parent if parent != null else nav).add_child(mi)
	return mi


func _solid_box(center: Vector3, sz: Vector3, c: Color, visible_mesh := true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = L_WORLD
	sb.collision_mask = 0
	sb.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	sb.add_child(cs)
	if visible_mesh:
		var bm := BoxMesh.new()
		bm.size = sz
		_mesh(bm, Vector3.ZERO, c, sb)
	nav.add_child(sb)
	return sb


func _build_ground() -> void:
	var w := size.x * S
	var h := size.y * S
	var gc := Color(0.27, 0.34, 0.19)
	if theme_name == "kar":
		gc = Color(0.86, 0.88, 0.92)
	elif theme_name == "liman":
		gc = Color(0.4, 0.42, 0.34)
	var g := _solid_box(Vector3(w / 2, -0.5, h / 2), Vector3(w + 40, 1.0, h + 40), gc)
	g.name = "Zemin"
	# harita sinirlari (gorunmez duvar)
	for r in [[w / 2, -0.5, w + 2, 1.0], [w / 2, h + 0.5, w + 2, 1.0], [-0.5, h / 2, 1.0, h + 2], [w + 0.5, h / 2, 1.0, h + 2]]:
		_solid_box(Vector3(r[0], 2.0, r[1]), Vector3(r[2], 4.0, r[3]), Color.BLACK, false)


func _flat_box(r: Rect2, y: float, c: Color) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x, 0.02, r.size.y)
	_mesh(bm, Vector3(r.get_center().x, y, r.get_center().y), c)


func _flat_poly(poly: PackedVector2Array, y: float, c: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in range(0, idx.size(), 3):
		for k in [0, 2, 1]:
			var p := poly[idx[i + k]]
			st.add_vertex(Vector3(p.x, y, p.y))
	_mesh(st.commit(), Vector3.ZERO, c)


func _prism_faces(poly: PackedVector2Array, h: float) -> PackedVector3Array:
	## cokgeni yukari dogru uzatir: yan yuzler + ust (ucgen listesi)
	var out := PackedVector3Array()
	var n := poly.size()
	var cw := Geometry2D.is_polygon_clockwise(poly)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var a0 := Vector3(a.x, 0, a.y)
		var b0 := Vector3(b.x, 0, b.y)
		var a1 := a0 + Vector3.UP * h
		var b1 := b0 + Vector3.UP * h
		if cw:
			out.append_array([a0, b1, b0, a0, a1, b1])
		else:
			out.append_array([a0, b0, b1, a0, b1, a1])
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var order := [0, 1, 2] if cw else [0, 2, 1]
		for k in order:
			var p := poly[idx[i + k]]
			out.append(Vector3(p.x, h, p.y))
	return out


func _prism_mesh(poly: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in _prism_faces(poly, h):
		st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _solid_prism(poly: PackedVector2Array, h: float, c: Color, show := true, layer := L_WORLD) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shp := ConcavePolygonShape3D.new()
	shp.backface_collision = true
	shp.set_faces(_prism_faces(poly, h))
	cs.shape = shp
	sb.add_child(cs)
	if show:
		_mesh(_prism_mesh(poly, h), Vector3.ZERO, c, sb)
	nav.add_child(sb)
	return sb


func _rect_of(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


func _build_obstacle(o: Dictionary) -> void:
	var t: String = o["type"]
	var spec: Array = TYPES.get(t, [true, true, 1.0, Color(0.5, 0.5, 0.5)])
	var c: Color = spec[3]
	if theme_name == "kar" and t in ["hedge", "bush", "tree"]:
		c = c.lerp(Color(0.85, 0.9, 0.95), 0.25)
	var h: float = spec[2]
	if o.has("circle"):
		var cc: Array = o["circle"]
		var p := P(cc)
		var r: float = float(cc[2]) * S
		match t:
			"tree":
				var trunk := CylinderShape3D.new()
				trunk.radius = clampf(r * 0.22, 0.2, 0.45)
				trunk.height = 3.2
				var sb := StaticBody3D.new()
				sb.collision_layer = L_WORLD
				sb.position = p + Vector3(0, 1.6, 0)
				var cs := CollisionShape3D.new()
				cs.shape = trunk
				sb.add_child(cs)
				var cm := CylinderMesh.new()
				cm.top_radius = trunk.radius * 0.8
				cm.bottom_radius = trunk.radius
				cm.height = 3.2
				cm.radial_segments = 8
				_mesh(cm, Vector3.ZERO, Color(0.3, 0.22, 0.14), sb)
				nav.add_child(sb)
				var sm := SphereMesh.new()
				sm.radius = maxf(r * 1.1, 1.4)
				sm.height = sm.radius * 1.7
				sm.radial_segments = 10
				sm.rings = 6
				_mesh(sm, p + Vector3(0, 3.4 + sm.radius * 0.6, 0), c, null, V_FPS)
			"bush":
				_soft_bush(p, r, h, c)
			"projektor":
				_solid_box(p + Vector3(0, h / 2, 0), Vector3(0.3, h, 0.3), c)
				var lb := BoxMesh.new()
				lb.size = Vector3(0.6, 0.5, 0.6)
				_mesh(lb, p + Vector3(0, h + 0.2, 0), Color(0.9, 0.9, 0.7))
			_:
				var cy := CylinderShape3D.new()
				cy.radius = r
				cy.height = h
				var sb2 := StaticBody3D.new()
				sb2.collision_layer = L_WORLD
				sb2.position = p + Vector3(0, h / 2, 0)
				var cs2 := CollisionShape3D.new()
				cs2.shape = cy
				sb2.add_child(cs2)
				var sm2 := SphereMesh.new()
				sm2.radius = r
				sm2.height = h * 2.0
				sm2.radial_segments = 9
				sm2.rings = 5
				_mesh(sm2, Vector3(0, -h / 2, 0), c, sb2)
				nav.add_child(sb2)
		return
	var poly := _poly(o["points"])
	if t == "bush":
		var rr := _rect_of(poly)
		bushes.append({"poly": poly})
		var a := Area3D.new()
		a.collision_layer = L_SOFT
		a.collision_mask = 0
		var cs3 := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(rr.size.x, h, rr.size.y)
		cs3.shape = bx
		a.position = Vector3(rr.get_center().x, h / 2, rr.get_center().y)
		a.add_child(cs3)
		add_child(a)
		_mesh(_prism_mesh(poly, h), Vector3.ZERO, c)
		return
	match t:
		"tower":
			var r2 := _rect_of(poly)
			var cen := Vector3(r2.get_center().x, 0, r2.get_center().y)
			var hw := r2.size.x / 2 - 0.15
			var hd := r2.size.y / 2 - 0.15
			for sx in [-1, 1]:
				for sz in [-1, 1]:
					_solid_box(cen + Vector3(sx * hw, h / 2, sz * hd), Vector3(0.25, h, 0.25), c)
			_solid_box(cen + Vector3(0, h, 0), Vector3(r2.size.x + 0.4, 0.2, r2.size.y + 0.4), c)
			_solid_box(cen + Vector3(0, h + 0.55, -r2.size.y / 2 - 0.15), Vector3(r2.size.x + 0.4, 0.9, 0.1), c)
			var roof := BoxMesh.new()
			roof.size = Vector3(r2.size.x + 0.8, 0.15, r2.size.y + 0.8)
			_mesh(roof, cen + Vector3(0, h + 2.4, 0), c.darkened(0.3), null, V_FPS)
			towers.append(cen + Vector3(0, h + 0.1, 0))
		"tel":
			_solid_prism(poly, h, c, false, L_MOVE)
			var rr2 := _rect_of(poly)
			var wm := BoxMesh.new()
			wm.size = Vector3(rr2.size.x, h * 0.8, rr2.size.y)
			var mi := _mesh(wm, Vector3(rr2.get_center().x, h * 0.45, rr2.get_center().y), Color(0.45, 0.45, 0.43, 0.55))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"tent":
			var rt := _rect_of(poly)
			_solid_box(Vector3(rt.get_center().x, h * 0.35, rt.get_center().y), Vector3(rt.size.x, h * 0.7, rt.size.y), c, false)
			var pm := PrismMesh.new()
			var along_x := rt.size.x >= rt.size.y
			pm.size = Vector3(rt.size.y if along_x else rt.size.x, h, rt.size.x if along_x else rt.size.y)
			var tm := _mesh(pm, Vector3(rt.get_center().x, h / 2, rt.get_center().y), c)
			if along_x:
				tm.rotation.y = PI / 2
		"truck", "tank":
			var rk := _rect_of(poly)
			var cen2 := Vector3(rk.get_center().x, 0, rk.get_center().y)
			_solid_box(cen2 + Vector3(0, h * 0.4, 0), Vector3(rk.size.x, h * 0.6, rk.size.y), c)
			var top := BoxMesh.new()
			if t == "tank":
				top.size = Vector3(rk.size.x * 0.5, h * 0.35, rk.size.y * 0.6)
				_mesh(top, cen2 + Vector3(0, h * 0.85, 0), c.darkened(0.1))
				var gun := BoxMesh.new()
				gun.size = Vector3(rk.size.x * 0.6, 0.18, 0.18) if rk.size.x > rk.size.y else Vector3(0.18, 0.18, rk.size.y * 0.6)
				_mesh(gun, cen2 + Vector3(rk.size.x * 0.35 if rk.size.x > rk.size.y else 0, h * 0.85, 0 if rk.size.x > rk.size.y else rk.size.y * 0.35), c.darkened(0.2))
			else:
				top.size = Vector3(rk.size.x * 0.65, h * 0.35, rk.size.y * 0.95) if rk.size.x > rk.size.y else Vector3(rk.size.x * 0.95, h * 0.35, rk.size.y * 0.65)
				_mesh(top, cen2 + Vector3(0, h * 0.87, 0), Color(0.36, 0.4, 0.3))
		_:
			_solid_prism(poly, h, c)


func _soft_bush(p: Vector3, r: float, h: float, c: Color) -> void:
	bushes.append([p, r])
	var a := Area3D.new()
	a.collision_layer = L_SOFT
	a.collision_mask = 0
	a.position = p + Vector3(0, h / 2, 0)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	cs.shape = cy
	a.add_child(cs)
	add_child(a)
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = h * 1.6
	sm.radial_segments = 10
	sm.rings = 5
	_mesh(sm, p + Vector3(0, h * 0.35, 0), c)


func _build_water(polys: Array, bridge_rects: Array) -> void:
	for poly in polys:
		_flat_poly(poly, 0.03, Color(0.2, 0.36, 0.5))
		var pieces: Array = [poly]
		for br in bridge_rects:
			var rp := PackedVector2Array([br.position, Vector2(br.end.x, br.position.y), br.end, Vector2(br.position.x, br.end.y)])
			var next: Array = []
			for pc in pieces:
				for q in Geometry2D.clip_polygons(pc, rp):
					next.append(q)
			pieces = next
		for pc in pieces:
			if pc.size() >= 3:
				_solid_prism(pc, 1.0, Color.BLACK, false, L_MOVE)
	for br in bridge_rects:
		var deck := BoxMesh.new()
		deck.size = Vector3(br.size.x, 0.12, br.size.y)
		var mi := _mesh(deck, Vector3(br.get_center().x, 0.08, br.get_center().y), Color(0.45, 0.32, 0.2))
		var rails: Array = []
		var along_x: bool = br.size.x > br.size.y
		for s in [-1, 1]:
			var off := Vector3(0, 0, s * (br.size.y / 2 - 0.1)) if along_x else Vector3(s * (br.size.x / 2 - 0.1), 0, 0)
			var rsz := Vector3(br.size.x, 1.0, 0.12) if along_x else Vector3(0.12, 1.0, br.size.y)
			rails.append(_solid_box(Vector3(br.get_center().x, 0.5, br.get_center().y) + off, rsz, Color(0.38, 0.27, 0.16)))
		bridges.append({"rect": br, "node": mi, "rails": rails, "broken": false})


func break_bridge(i: int) -> void:
	if i < 0 or i >= bridges.size() or bridges[i]["broken"]:
		return
	var b: Dictionary = bridges[i]
	b["broken"] = true
	b["node"].queue_free()
	for r in b["rails"]:
		r.queue_free()
	var br: Rect2 = b["rect"]
	var blk := _solid_box(Vector3(br.get_center().x, 0.5, br.get_center().y), Vector3(br.size.x, 1.0, br.size.y), Color(0.2, 0.36, 0.5))
	blk.name = "YikikKopru"
	bake_nav.call_deferred(true)


func _build_building(b: Dictionary) -> void:
	var r: Array = b["rect"]
	var x0: float = r[0] * S
	var z0: float = r[1] * S
	var w: float = r[2] * S
	var d: float = r[3] * S
	var side: String = b.get("door", "S")
	var wc := Color(0.7, 0.66, 0.58)
	if str(b.get("style", "")) != "":
		wc = Color(0.58, 0.58, 0.56)
	var rc_a: Array = b.get("roof", [0.58, 0.3, 0.24])
	var rc := Color(rc_a[0], rc_a[1], rc_a[2])
	var hh := WALL_H
	# taban
	var fl := BoxMesh.new()
	fl.size = Vector3(w, 0.04, d)
	_mesh(fl, Vector3(x0 + w / 2, 0.02, z0 + d / 2), Color(0.42, 0.34, 0.25))
	# duvarlar: kapi tarafinda ortada bosluk
	var walls := {
		"N": [Vector2(x0, z0), Vector2(x0 + w, z0)],
		"S": [Vector2(x0, z0 + d), Vector2(x0 + w, z0 + d)],
		"W": [Vector2(x0, z0), Vector2(x0, z0 + d)],
		"E": [Vector2(x0 + w, z0), Vector2(x0 + w, z0 + d)],
	}
	var door_pos := Vector3.ZERO
	for k in walls:
		var a: Vector2 = walls[k][0]
		var e: Vector2 = walls[k][1]
		var horiz: bool = k == "N" or k == "S"
		var length: float = w if horiz else d
		if k == side:
			var mid := (a + e) / 2
			door_pos = Vector3(mid.x, 0, mid.y)
			var seg := (length - DOOR_W) / 2
			for s in [-1, 1]:
				var c := mid + (Vector2(s * (DOOR_W / 2 + seg / 2), 0) if horiz else Vector2(0, s * (DOOR_W / 2 + seg / 2)))
				var sz := Vector3(seg, hh, WALL_T) if horiz else Vector3(WALL_T, hh, seg)
				_solid_box(Vector3(c.x, hh / 2, c.y), sz, wc)
			var lin := Vector3(DOOR_W, hh - DOOR_H, WALL_T) if horiz else Vector3(WALL_T, hh - DOOR_H, DOOR_W)
			_solid_box(Vector3(mid.x, DOOR_H + (hh - DOOR_H) / 2, mid.y), lin, wc)
		else:
			var c2 := (a + e) / 2
			var sz2 := Vector3(length + WALL_T, hh, WALL_T) if horiz else Vector3(WALL_T, hh, length + WALL_T)
			_solid_box(Vector3(c2.x, hh / 2, c2.y), sz2, wc)
			# pencere izi (gorsel)
			if length > 5.0:
				var win := BoxMesh.new()
				win.size = Vector3(1.0, 0.8, WALL_T + 0.04) if horiz else Vector3(WALL_T + 0.04, 0.8, 1.0)
				for f in [-0.25, 0.25]:
					var wp: Vector2 = c2 + ((e - a) * f)
					_mesh(win, Vector3(wp.x, 1.7, wp.y), Color(0.15, 0.17, 0.2))
	# cati: yalniz FPS gorunumunde (taktik haritada ici gorunsun)
	var roof := BoxMesh.new()
	roof.size = Vector3(w + 0.6, 0.25, d + 0.6)
	_mesh(roof, Vector3(x0 + w / 2, hh + 0.12, z0 + d / 2), rc, null, V_FPS)
	var pm := PrismMesh.new()
	var along_x := w >= d
	pm.size = Vector3(d + 0.6 if along_x else w + 0.6, 1.4, w + 0.6 if along_x else d + 0.6)
	var pr := _mesh(pm, Vector3(x0 + w / 2, hh + 0.95, z0 + d / 2), rc, null, V_FPS)
	if along_x:
		pr.rotation.y = PI / 2
	# tavan (icerden karanlik olsun, golge versin): cati ile ayni katman
	var lock: String = str(b.get("locked", ""))
	if lock != "":
		var horiz2: bool = side == "N" or side == "S"
		var dsz := Vector3(DOOR_W, DOOR_H, 0.12) if horiz2 else Vector3(0.12, DOOR_H, DOOR_W)
		var dn := _solid_box(door_pos + Vector3(0, DOOR_H / 2, 0), dsz, Color(0.35, 0.22, 0.12))
		dn.name = "KilitliKapi"
		doors.append({"pos": door_pos, "item": lock, "node": dn, "name": b.get("name", "")})
	# bina adi tabelasi
	var lab := Label3D.new()
	lab.text = str(b.get("name", ""))
	lab.font_size = 48
	lab.pixel_size = 0.01
	lab.modulate = Color(1, 1, 1, 0.75)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(x0 + w / 2, hh + 2.6, z0 + d / 2)
	lab.layers = V_MAP
	lab.fixed_size = true
	lab.pixel_size = 0.0012
	lab.no_depth_test = true
	add_child(lab)


func open_door(i: int) -> void:
	var dr: Dictionary = doors[i]
	if is_instance_valid(dr["node"]):
		dr["node"].queue_free()
	doors.remove_at(i)
	bake_nav.call_deferred(true)


func _build_siren(p: Vector3) -> void:
	_solid_box(p + Vector3(0, 1.6, 0), Vector3(0.2, 3.2, 0.2), Color(0.3, 0.3, 0.3))
	var hm := CylinderMesh.new()
	hm.top_radius = 0.35
	hm.bottom_radius = 0.15
	hm.height = 0.5
	var mi := _mesh(hm, p + Vector3(0.3, 3.1, 0), Color(0.75, 0.15, 0.1))
	mi.rotation.z = -PI / 2
	var lab := Label3D.new()
	lab.text = "SİREN"
	lab.font_size = 40
	lab.pixel_size = 0.012
	lab.modulate = Color(1, 0.3, 0.25)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = p + Vector3(0, 4.2, 0)
	lab.layers = V_MAP
	lab.fixed_size = true
	lab.pixel_size = 0.0012
	add_child(lab)


func _build_barracks_marker(p: Vector3) -> void:
	var lab := Label3D.new()
	lab.text = "KIŞLA"
	lab.font_size = 40
	lab.pixel_size = 0.012
	lab.modulate = Color(1, 0.7, 0.3)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = p + Vector3(0, 4.0, 0)
	lab.layers = V_MAP
	lab.fixed_size = true
	lab.pixel_size = 0.0012
	add_child(lab)


func _add_pickup(pk: Dictionary) -> void:
	var c := Color(0.9, 0.9, 0.9)
	var sz := Vector3(0.4, 0.25, 0.3)
	match pk["type"]:
		"medkit":
			c = Color(0.95, 0.95, 0.95)
		"ammo":
			c = Color(0.35, 0.4, 0.25)
		"key":
			c = Color(0.95, 0.8, 0.2)
			sz = Vector3(0.2, 0.05, 0.1)
		"stone", "stones":
			c = Color(0.55, 0.55, 0.52)
	var bm := BoxMesh.new()
	bm.size = sz
	var mi := _mesh(bm, pk["pos"] + Vector3(0, 0.55 if pk["type"] != "key" else 0.05, 0), c, self)
	if pk["type"] == "medkit":
		var cr := BoxMesh.new()
		cr.size = Vector3(0.25, 0.27, 0.07)
		_mesh(cr, Vector3.ZERO, Color(0.85, 0.1, 0.1), mi)
	if pk["type"] != "key":
		var tbl := BoxMesh.new()
		tbl.size = Vector3(0.7, 0.42, 0.5)
		_mesh(tbl, Vector3(0, -0.34, 0), Color(0.4, 0.3, 0.2), mi)
	pk["node"] = mi
	pk["taken"] = false
	pickups.append(pk)


func add_pickup(pk: Dictionary) -> void:
	_add_pickup(pk)


func take_pickup(pk: Dictionary) -> void:
	pk["taken"] = true
	if is_instance_valid(pk["node"]):
		pk["node"].queue_free()


func make_marker(p: Vector3, text: String, c: Color) -> Node3D:
	## gorev nesnesi: masa + parlak isaret (FPS'te belli olsun)
	var root := Node3D.new()
	root.position = p
	add_child(root)
	var tbl := BoxMesh.new()
	tbl.size = Vector3(0.9, 0.75, 0.6)
	_mesh(tbl, Vector3(0, 0.375, 0), Color(0.4, 0.3, 0.2), root)
	var it := BoxMesh.new()
	it.size = Vector3(0.32, 0.05, 0.24)
	var m := _mesh(it, Vector3(0, 0.78, 0), c, root)
	m.material_override = _mat(c, true)
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = 36
	lab.pixel_size = 0.008
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = c
	lab.position = Vector3(0, 1.5, 0)
	lab.no_depth_test = true
	root.add_child(lab)
	return root


func _build_exit() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(exit_rect.size.x, 0.05, exit_rect.size.y)
	var mi := _mesh(bm, Vector3(exit_rect.get_center().x, 0.03, exit_rect.get_center().y), Color(0.2, 0.9, 0.3, 0.35), self)
	mi.material_override = _mat(Color(0.2, 0.9, 0.3, 0.35), true)
	var lab := Label3D.new()
	lab.text = "ÇIKIŞ"
	lab.font_size = 64
	lab.pixel_size = 0.012
	lab.modulate = Color(0.4, 1, 0.5)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = Vector3(exit_rect.get_center().x, 2.5, exit_rect.get_center().y)
	add_child(lab)


func _build_light() -> void:
	var amb: Array = data.get("ambient", [1.0, 0.97, 0.9]) if data.get("ambient") is Array else [1.0, 0.97, 0.9]
	var ac := Color(amb[0], amb[1], amb[2])
	var sun := DirectionalLight3D.new()
	sun.name = "Gunes"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = ac
	sun.light_energy = 0.85 if ac.v > 0.75 else 0.5
	sun.shadow_enabled = not OS.has_feature("mobile")
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.35, 0.5, 0.75) * ac
	ps.sky_horizon_color = Color(0.7, 0.75, 0.8) * ac
	ps.ground_horizon_color = Color(0.5, 0.5, 0.45) * ac
	sky.sky_material = ps
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.72, 0.76) * ac
	env.fog_density = 0.008 if theme_name != "kar" else 0.014
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
