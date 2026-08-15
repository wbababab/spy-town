class_name LowPoly extends RefCounted

## Flat-shaded primitive builder for hand-authored low-poly meshes.
##
## Everything the soldiers and their weapons are made of comes out of this file:
## tapered boxes, faceted tubes, thin bevelled plates and lens discs. Each face
## gets its own vertices and its own hard normal, which is what gives the faceted
## PS1-era read and, incidentally, means no normal smoothing groups to maintain.
##
## Three things are worth knowing before editing:
##
## WINDING. Godot treats clockwise-on-screen as front-facing. Every primitive
## here emits that order, and `quad()` derives its flat normal from the winding
## rather than taking one as an argument, so a face can never end up lit on the
## side that is culled.
##
## VERTEX COLOUR IS MATERIAL DATA, NOT TINT. vantablack.gdshader reads
## COLOR.r as an armour-plate mask, COLOR.g as a cloth mask and COLOR.b as dust
## wear. That is how one material covers plate, cloak and webbing with no texture
## fetch and no extra draw call. Use the constants below rather than raw colours.
##
## SKINNING IS RIGID. Every vertex is bound to exactly one bone at weight 1.0.
## Smooth skinning on a mesh this coarse buys nothing - there are not enough
## vertices across a joint for a gradient to read - and rigid binding means the
## limbs stay crisply faceted when animated, which is the look we want anyway.

# ── Material masks (r = plate, g = cloth, b = wear) ────────────────────────────
const PLATE := Color(1.00, 0.00, 0.10, 1.0)   ## Hard armour: tight bright glint.
const CLOTH := Color(0.05, 1.00, 0.06, 1.0)   ## Cloak, ghillie, shroud.
const STRAP := Color(0.30, 0.55, 0.02, 1.0)   ## Webbing, pouches, slings.
const RUBBER := Color(0.08, 0.18, 0.00, 1.0)  ## Boot soles, grips, seals.
const METAL := Color(1.00, 0.00, 0.45, 1.0)   ## Weapon receivers and barrels.
const GRIME := Color(0.20, 0.35, 0.85, 1.0)   ## Heavily dusted lower legs.

var st := SurfaceTool.new()

var _skinned := false
var _bone := 0
var _color := PLATE
var _stack: Array[Transform3D] = [Transform3D.IDENTITY]
var _tris := 0


## Starts a new surface. Pass `true` when the result will be driven by a
## Skeleton3D; every vertex then carries bone indices and weights.
func begin(skinned: bool = false) -> LowPoly:
	_skinned = skinned
	_tris = 0
	_stack = [Transform3D.IDENTITY]
	st.clear()
	# Must precede begin(); SurfaceTool refuses the call once a surface is open.
	if skinned:
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return self


## Bone that subsequent geometry binds to. Ignored on unskinned surfaces.
func bone(index: int) -> LowPoly:
	_bone = index
	return self


## Material mask for subsequent geometry. Use the constants above.
func mat(c: Color) -> LowPoly:
	_color = c
	return self


func push(xform: Transform3D) -> LowPoly:
	_stack.push_back(_stack[-1] * xform)
	return self


func pop() -> LowPoly:
	if _stack.size() > 1:
		_stack.pop_back()
	return self


func xform() -> Transform3D:
	return _stack[-1]


func triangle_count() -> int:
	return _tris


func _emit(p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_color(_color)
	st.set_normal(n)
	st.set_uv(uv)
	if _skinned:
		st.set_bones(PackedInt32Array([_bone, 0, 0, 0]))
		st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	st.add_vertex(p)


## Planar quad, corners in clockwise order as seen from the visible side.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> LowPoly:
	var t := _stack[-1]
	var pa := t * a
	var pb := t * b
	var pc := t * c
	var pd := t * d

	# Right-hand rule gives the normal for counter-clockwise winding; ours is
	# clockwise, so the outward direction is the negation.
	var n := -(pb - pa).cross(pc - pa)
	if n.length_squared() < 1e-12:
		return self
	n = n.normalized()

	_emit(pa, n, Vector2(0, 0))
	_emit(pb, n, Vector2(1, 0))
	_emit(pc, n, Vector2(1, 1))

	_emit(pa, n, Vector2(0, 0))
	_emit(pc, n, Vector2(1, 1))
	_emit(pd, n, Vector2(0, 1))
	_tris += 2
	return self


## Quad with explicit per-corner UVs, for surfaces where the UV island has to
## span more than one face - anything read by a shader that treats UV as a
## coordinate system rather than a texture lookup. The visor pane needs this:
## with quad()'s per-face 0..1 UVs, each of its faces would draw its own
## complete skull.
func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2) -> LowPoly:
	var t := _stack[-1]
	var pa := t * a
	var pb := t * b
	var pc := t * c
	var pd := t * d

	var n := -(pb - pa).cross(pc - pa)
	if n.length_squared() < 1e-12:
		return self
	n = n.normalized()

	_emit(pa, n, uv_a)
	_emit(pb, n, uv_b)
	_emit(pc, n, uv_c)

	_emit(pa, n, uv_a)
	_emit(pc, n, uv_c)
	_emit(pd, n, uv_d)
	_tris += 2
	return self


func tri(a: Vector3, b: Vector3, c: Vector3) -> LowPoly:
	var t := _stack[-1]
	var pa := t * a
	var pb := t * b
	var pc := t * c
	var n := -(pb - pa).cross(pc - pa)
	if n.length_squared() < 1e-12:
		return self
	n = n.normalized()
	_emit(pa, n, Vector2(0, 0))
	_emit(pb, n, Vector2(1, 0))
	_emit(pc, n, Vector2(0.5, 1))
	_tris += 1
	return self


## Tapered box between two points - the workhorse for limbs, torsos, barrels and
## stocks. `half_a`/`half_b` are half-extents across the segment at each end, so
## a limb can thin toward the wrist just by shrinking the second one.
## 12 triangles capped, 8 open.
func frustum(from: Vector3, to: Vector3, half_a: Vector2, half_b: Vector2,
		up_hint: Vector3 = Vector3.UP, cap_start: bool = true,
		cap_end: bool = true) -> LowPoly:
	var fwd := to - from
	var length := fwd.length()
	if length < 1e-6:
		return self
	fwd /= length

	var right := up_hint.cross(fwd)
	if right.length_squared() < 1e-8:
		# up_hint is parallel to the segment; any perpendicular will do.
		right = Vector3.RIGHT.cross(fwd)
		if right.length_squared() < 1e-8:
			right = Vector3.FORWARD.cross(fwd)
	right = right.normalized()
	var up := fwd.cross(right).normalized()

	# Counter-clockwise in the (right, up) plane. Sides then wind clockwise when
	# viewed from outside; see the module note on winding.
	var offs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for o: Vector2 in offs:
		a.append(from + right * (o.x * half_a.x) + up * (o.y * half_a.y))
		b.append(to + right * (o.x * half_b.x) + up * (o.y * half_b.y))

	for i in 4:
		var j := (i + 1) % 4
		quad(a[i], b[i], b[j], a[j])
	if cap_start:
		quad(a[0], a[1], a[2], a[3])
	if cap_end:
		quad(b[3], b[2], b[1], b[0])
	return self


## Axis-aligned box centred on `center`. `size` is the full extent.
func box(center: Vector3, size: Vector3) -> LowPoly:
	var h := size * 0.5
	return frustum(center - Vector3(0, 0, h.z), center + Vector3(0, 0, h.z),
		Vector2(h.x, h.y), Vector2(h.x, h.y), Vector3.UP)


## Thin armour panel with a bevelled outer face. The bevel is what catches the
## grazing glint in vantablack.gdshader, so panels read as hard-edged even
## though the surface itself is almost pure absorption.
func plate(center: Vector3, size: Vector3, bevel: float = 0.35) -> LowPoly:
	var h := size * 0.5
	var inset := Vector2(h.x, h.y) * (1.0 - clampf(bevel, 0.0, 0.9))
	return frustum(center - Vector3(0, 0, h.z), center + Vector3(0, 0, h.z),
		Vector2(h.x, h.y), inset, Vector3.UP)


## Faceted tube. Six sides is the sweet spot for barrels and suppressors: the
## silhouette reads round and it costs 24 triangles capped.
func tube(from: Vector3, to: Vector3, radius_a: float, radius_b: float,
		sides: int = 6, up_hint: Vector3 = Vector3.UP,
		capped: bool = true) -> LowPoly:
	var fwd := to - from
	var length := fwd.length()
	if length < 1e-6 or sides < 3:
		return self
	fwd /= length

	var right := up_hint.cross(fwd)
	if right.length_squared() < 1e-8:
		right = Vector3.RIGHT.cross(fwd)
		if right.length_squared() < 1e-8:
			right = Vector3.FORWARD.cross(fwd)
	right = right.normalized()
	var up := fwd.cross(right).normalized()

	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for i in sides:
		var ang := TAU * float(i) / float(sides)
		var dir := right * cos(ang) + up * sin(ang)
		a.append(from + dir * radius_a)
		b.append(to + dir * radius_b)

	for i in sides:
		var j := (i + 1) % sides
		quad(a[i], b[i], b[j], a[j])

	if capped:
		for i in range(1, sides - 1):
			quad(a[0], a[i], a[i + 1], a[0])
			quad(b[0], b[i + 1], b[i], b[0])
	return self


## Flat disc facing local +Z, UV mapped 0..1 across its bounding square so the
## radial gradient in ocular.gdshader lands where it expects.
func disc(center: Vector3, radius: float, sides: int = 10) -> LowPoly:
	if sides < 3:
		return self
	var t := _stack[-1]
	var n := (t.basis * Vector3.BACK).normalized()
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i in sides:
		# Negative sweep so the fan is clockwise seen from +Z.
		var ang := -TAU * float(i) / float(sides)
		var local := center + Vector3(cos(ang), sin(ang), 0.0) * radius
		pts.append(t * local)
		uvs.append(Vector2(0.5 + cos(ang) * 0.5, 0.5 - sin(ang) * 0.5))

	for i in range(1, sides - 1):
		_emit(pts[0], n, uvs[0])
		_emit(pts[i], n, uvs[i])
		_emit(pts[i + 1], n, uvs[i + 1])
		_tris += 1
	return self


## Upright quad for a flame plume. UV.y is 0 at the base and 1 at the tip, which
## is the convention black_flame.gdshader assumes for its taper and dissolve.
## Emitted double-sided via cull_disabled in that shader, so one quad is enough.
func flame_quad(base: Vector3, height: float, width: float) -> LowPoly:
	var t := _stack[-1]
	var n := (t.basis * Vector3.BACK).normalized()
	var hw := width * 0.5
	var p0 := t * (base + Vector3(-hw, 0.0, 0.0))
	var p1 := t * (base + Vector3(hw, 0.0, 0.0))
	var p2 := t * (base + Vector3(hw, height, 0.0))
	var p3 := t * (base + Vector3(-hw, height, 0.0))

	_emit(p0, n, Vector2(0, 0))
	_emit(p3, n, Vector2(0, 1))
	_emit(p2, n, Vector2(1, 1))
	_emit(p0, n, Vector2(0, 0))
	_emit(p2, n, Vector2(1, 1))
	_emit(p1, n, Vector2(1, 0))
	_tris += 2
	return self


## Centred quad facing local +Z with a full 0..1 UV square. Used for flare cards
## and the visor pane.
func card(center: Vector3, size: Vector2) -> LowPoly:
	var h := size * 0.5
	var t := _stack[-1]
	var n := (t.basis * Vector3.BACK).normalized()
	var p0 := t * (center + Vector3(-h.x, -h.y, 0.0))
	var p1 := t * (center + Vector3(h.x, -h.y, 0.0))
	var p2 := t * (center + Vector3(h.x, h.y, 0.0))
	var p3 := t * (center + Vector3(-h.x, h.y, 0.0))

	_emit(p0, n, Vector2(0, 1))
	_emit(p3, n, Vector2(0, 0))
	_emit(p2, n, Vector2(1, 0))
	_emit(p0, n, Vector2(0, 1))
	_emit(p2, n, Vector2(1, 0))
	_emit(p1, n, Vector2(1, 1))
	_tris += 2
	return self


## Appends the accumulated geometry to `mesh` as one new surface and assigns
## `material` to it. Returns the surface index.
##
## Keeping every part of a character in as few surfaces as possible is the whole
## draw-call budget: one for the vantablack body, one for the lenses, one for the
## visor, one for the plumes. Do not commit per body part.
func commit_surface(mesh: ArrayMesh, material: Material = null,
		with_tangents: bool = false) -> int:
	if _tris == 0:
		return -1
	if with_tangents:
		st.generate_tangents()
	st.commit(mesh)
	var idx := mesh.get_surface_count() - 1
	if material:
		mesh.surface_set_material(idx, material)
	return idx
