extends RefCounted
## Pure-code polyhedra for dice. No art assets.
##
## Every builder returns { "verts": PackedVector3Array, "faces": Array[PackedInt32Array] }
## Faces are wound counter-clockwise when seen from outside the solid.
## Vertices are scaled so the circumradius equals `radius`.

const PHI := 1.6180339887498949


static func build(sides: int, radius: float) -> Dictionary:
	var shape: Dictionary
	match sides:
		4: shape = tetrahedron()
		6: shape = cube()
		8: shape = octahedron()
		10: shape = trapezohedron(5)
		12: shape = dodecahedron()
		20: shape = icosahedron()
		_: push_error("Unsupported die: d%d" % sides); return {}
	return _scaled(shape, radius)


static func tetrahedron() -> Dictionary:
	var v := PackedVector3Array([
		Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)])
	var normals := []
	for p in v:
		normals.append(-p)  # each face sits opposite one vertex
	return {"verts": v, "faces": _faces_from_normals(v, normals)}


static func cube() -> Dictionary:
	var v := PackedVector3Array()
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				v.append(Vector3(x, y, z))
	var normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	return {"verts": v, "faces": _faces_from_normals(v, normals)}


static func octahedron() -> Dictionary:
	var v := PackedVector3Array([
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD])
	var normals := []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				normals.append(Vector3(x, y, z))
	return {"verts": v, "faces": _faces_from_normals(v, normals)}


static func _icosa_points(swap: bool) -> PackedVector3Array:
	# The two icosahedra (cyclic orderings) are duals of the standard dodecahedron.
	var a := PHI if swap else 1.0
	var b := 1.0 if swap else PHI
	var v := PackedVector3Array()
	for s1 in [-1, 1]:
		for s2 in [-1, 1]:
			v.append(Vector3(0, s1 * a, s2 * b))
			v.append(Vector3(s1 * b, 0, s2 * a))
			v.append(Vector3(s1 * a, s2 * b, 0))
	return v


static func _dodeca_points() -> PackedVector3Array:
	var v := PackedVector3Array()
	var ip := 1.0 / PHI
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				v.append(Vector3(x, y, z))
	for s1 in [-1, 1]:
		for s2 in [-1, 1]:
			v.append(Vector3(0, s1 * ip, s2 * PHI))
			v.append(Vector3(s1 * ip, s2 * PHI, 0))
			v.append(Vector3(s1 * PHI, 0, s2 * ip))
	return v


static func dodecahedron() -> Dictionary:
	var v := _dodeca_points()
	return {"verts": v, "faces": _faces_from_normals(v, Array(_icosa_points(true)))}


static func icosahedron() -> Dictionary:
	var v := _icosa_points(true)
	return {"verts": v, "faces": _faces_from_normals(v, Array(_dodeca_points()))}


## d10 shape: n kite faces on top, n on the bottom.
static func trapezohedron(n: int) -> Dictionary:
	var step := TAU / n
	var c := cos(step / 2.0)
	var h := 1.0
	var a := h * (1.0 - c) / (1.0 + c)  # ring height that keeps every kite planar
	var v := PackedVector3Array([Vector3(0, h, 0), Vector3(0, -h, 0)])
	for i in n:
		v.append(Vector3(cos(step * i), a, sin(step * i)))               # upper ring: 2 + 2i
		v.append(Vector3(cos(step * i + step / 2), -a, sin(step * i + step / 2)))  # lower ring: 3 + 2i
	var faces := []
	for i in n:
		var u0 := 2 + 2 * i
		var l0 := 3 + 2 * i
		var u1 := 2 + 2 * ((i + 1) % n)
		var l1 := 3 + 2 * ((i + 1) % n)
		faces.append(_orient(v, [0, u0, l0, u1]))
		faces.append(_orient(v, [1, l0, u1, l1]))
	return {"verts": v, "faces": faces}


## Axis-aligned box centred on the origin, as verts + faces (for chamfered furniture).
static func box(size: Vector3) -> Dictionary:
	var h := size / 2.0
	var v := PackedVector3Array()
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				v.append(Vector3(x * h.x, y * h.y, z * h.z))
	var normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	return {"verts": v, "faces": _faces_from_normals(v, normals)}


## Builds a chamfered (rounded-edge) mesh from a convex solid centred on the origin.
## Every face is moved in from its edges by `bevel`, and the gaps are filled with edge
## strips and corner caps whose normals blend between the neighbouring faces, so edges
## catch the light like worn, rounded corners.
## Returns { mesh, hull (the chamfered points), inset (per-face corner points), normals }.
static func chamfer(verts: PackedVector3Array, faces: Array, bevel: float) -> Dictionary:
	var inset := []
	var normals: Array[Vector3] = []
	var hull := PackedVector3Array()
	for f: PackedInt32Array in faces:
		var pts := PackedVector3Array()
		var n := face_normal(verts, f)
		for k in f.size():
			var v := verts[f[k]]
			var e1 := (verts[f[(k + f.size() - 1) % f.size()]] - v).normalized()
			var e2 := (verts[f[(k + 1) % f.size()]] - v).normalized()
			var bis := (e1 + e2).normalized()
			var sin_half := e1.cross(bis).length()
			pts.append(v + bis * bevel / maxf(sin_half, 0.05))
		inset.append(pts)
		normals.append(n)
		hull.append_array(pts)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in faces.size():
		var nn: Array[Vector3] = []
		for k in inset[i].size():
			nn.append(normals[i])
		_emit_poly(st, inset[i], nn)
	var edges := {}
	for i in faces.size():
		var f: PackedInt32Array = faces[i]
		for k in f.size():
			var a := f[k]
			var b := f[(k + 1) % f.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edges.has(key):
				edges[key] = []
			edges[key].append(i)
	for key: Vector2i in edges:
		var e: Array = edges[key]
		if e.size() != 2:
			continue
		var fa: int = e[0]
		var fb: int = e[1]
		var quad := PackedVector3Array([
			_corner_of(faces[fa], inset[fa], key.x), _corner_of(faces[fa], inset[fa], key.y),
			_corner_of(faces[fb], inset[fb], key.y), _corner_of(faces[fb], inset[fb], key.x)])
		var qn: Array[Vector3] = [normals[fa], normals[fa], normals[fb], normals[fb]]
		_emit_poly(st, quad, qn)
	for vi in verts.size():
		var pts: Array[Vector3] = []
		var nn: Array[Vector3] = []
		for i in faces.size():
			var idx: int = Array(faces[i]).find(vi)
			if idx != -1:
				pts.append(inset[i][idx])
				nn.append(normals[i])
		if pts.size() < 3:
			continue
		var axis := verts[vi].normalized()
		var t := (pts[0] - verts[vi]).normalized()
		var bt := axis.cross(t)
		var ang := func(p: Vector3) -> float: return atan2((p - verts[vi]).dot(bt), (p - verts[vi]).dot(t))
		var order := range(pts.size())
		order.sort_custom(func(x, y): return ang.call(pts[x]) < ang.call(pts[y]))
		var sp := PackedVector3Array()
		var sn: Array[Vector3] = []
		for o in order:
			sp.append(pts[o])
			sn.append(nn[o])
		_emit_poly(st, sp, sn)
	return {"mesh": st.commit(), "hull": hull, "inset": inset, "normals": normals}


static func _corner_of(face: PackedInt32Array, pts: PackedVector3Array, vi: int) -> Vector3:
	return pts[Array(face).find(vi)]


## Fan-triangulates a convex polygon, flipping it if needed so it faces outward
## (Godot treats clockwise triangles as front faces). Needs the solid centred on the origin.
static func _emit_poly(st: SurfaceTool, pts: PackedVector3Array, nn: Array[Vector3]) -> void:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var n := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	var ccw_out := n.dot(c) > 0.0
	for k in range(1, pts.size() - 1):
		var tri := [0, k + 1, k] if ccw_out else [0, k, k + 1]
		for j in tri:
			st.set_normal(nn[j])
			st.add_vertex(pts[j])


# ---------------------------------------------------------------- helpers

static func face_center(verts: PackedVector3Array, face: PackedInt32Array) -> Vector3:
	var c := Vector3.ZERO
	for i in face:
		c += verts[i]
	return c / face.size()


static func face_normal(verts: PackedVector3Array, face: PackedInt32Array) -> Vector3:
	var a := verts[face[0]]
	var b := verts[face[1]]
	var c := verts[face[2]]
	return (b - a).cross(c - a).normalized()


## Distance from the face centre to its nearest edge (used to size labels).
static func face_inradius(verts: PackedVector3Array, face: PackedInt32Array) -> float:
	var c := face_center(verts, face)
	var best := INF
	for k in face.size():
		var p := verts[face[k]]
		var q := verts[face[(k + 1) % face.size()]]
		var t := clampf((c - p).dot(q - p) / (q - p).length_squared(), 0.0, 1.0)
		best = minf(best, c.distance_to(p + (q - p) * t))
	return best


static func _faces_from_normals(verts: PackedVector3Array, normals: Array) -> Array:
	var faces := []
	for raw in normals:
		var n: Vector3 = raw.normalized()
		var best := -INF
		for p in verts:
			best = maxf(best, p.dot(n))
		var idx := []
		for i in verts.size():
			if verts[i].dot(n) > best - 1e-4:
				idx.append(i)
		faces.append(_sort_ccw(verts, idx, n))
	return faces


static func _orient(verts: PackedVector3Array, idx: Array) -> PackedInt32Array:
	var c := Vector3.ZERO
	for i in idx:
		c += verts[i]
	c /= idx.size()
	var n := (verts[idx[1]] - verts[idx[0]]).cross(verts[idx[2]] - verts[idx[0]]).normalized()
	if n.dot(c) < 0:
		n = -n
	return _sort_ccw(verts, idx, n)


static func _sort_ccw(verts: PackedVector3Array, idx: Array, n: Vector3) -> PackedInt32Array:
	var c := Vector3.ZERO
	for i in idx:
		c += verts[i]
	c /= idx.size()
	var t := (verts[idx[0]] - c).normalized()
	var bt := n.cross(t)
	var ang := func(i): return atan2((verts[i] - c).dot(bt), (verts[i] - c).dot(t))
	idx.sort_custom(func(x, y): return ang.call(x) < ang.call(y))
	return PackedInt32Array(idx)


static func _scaled(shape: Dictionary, radius: float) -> Dictionary:
	var v: PackedVector3Array = shape.verts
	var r := 0.0
	for p in v:
		r = maxf(r, p.length())
	var out := PackedVector3Array()
	for p in v:
		out.append(p * (radius / r))
	return {"verts": out, "faces": shape.faces}
