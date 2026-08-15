class_name WeaponMeshFactory extends RefCounted

## Builds the three weapons from the concept art as flat-shaded low-poly meshes.
##
## Authoring frame matches Node3D convention: origin at the firing hand's grip,
## -Z toward the muzzle, +Y up, +X to the shooter's right. That means the result
## can be dropped straight onto a BoneAttachment3D with no correction basis, and
## `muzzle_transform()` points the right way for a flash or a raycast.
##
## Weapons are deliberately kept as their own MeshInstance3D rather than welded
## into the character mesh. Welding them into the hand bone would save two draw
## calls, but it also freezes the loadout into the character - and a weapon
## needs its own muzzle node, its own visibility, and the option to be dropped.
## For a squad of three that trade is not worth two draw calls; for a horde of
## sixty identical grunts it would be, and the builder is structured so the same
## geometry can be committed into a character's LowPoly instead.

const IND_GREEN := Color(0.35, 1.0, 0.45)
const IND_AMBER := Color(1.0, 0.68, 0.25)
const IND_CYAN := Color(0.35, 0.85, 1.0)


## Returns { mesh: ArrayMesh, muzzle: Transform3D, tris: int }.
## `metal` and `lights` are the materials for the two surfaces.
static func build(weapon: SoldierProfile.Weapon, metal: Material,
		lights: Material) -> Dictionary:
	var body := LowPoly.new().begin(false).mat(LowPoly.METAL)
	var lamp := LowPoly.new().begin(false).mat(LowPoly.METAL)
	var muzzle_z := 0.0

	match weapon:
		SoldierProfile.Weapon.MARKSMAN:
			muzzle_z = _marksman(body, lamp)
		SoldierProfile.Weapon.HEAVY:
			muzzle_z = _heavy(body, lamp)
		_:
			muzzle_z = _carbine(body, lamp)

	var mesh := ArrayMesh.new()
	body.commit_surface(mesh, metal)
	lamp.commit_surface(mesh, lights)

	return {
		"mesh": mesh,
		"muzzle": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, muzzle_z)),
		"tris": body.triangle_count() + lamp.triangle_count(),
	}


# ── Shared sub-assemblies ─────────────────────────────────────────────────────

## Pistol grip raked back from the receiver.
static func _grip(b: LowPoly, at_z: float, length: float, rake: float) -> void:
	b.push(Transform3D(Basis(Vector3.RIGHT, rake), Vector3(0.0, -0.02, at_z)))
	b.mat(LowPoly.RUBBER)
	b.frustum(Vector3.ZERO, Vector3(0, -length, 0.0),
		Vector2(0.020, 0.030), Vector2(0.018, 0.026), Vector3.BACK)
	b.mat(LowPoly.METAL)
	b.pop()


## Trigger guard: a thin loop approximated with three bars.
static func _trigger_guard(b: LowPoly, at_z: float) -> void:
	b.box(Vector3(0.0, -0.052, at_z - 0.035), Vector3(0.016, 0.008, 0.075))
	b.box(Vector3(0.0, -0.030, at_z - 0.072), Vector3(0.016, 0.048, 0.008))


## Box magazine, optionally raked forward like a curved STANAG.
static func _magazine(b: LowPoly, at_z: float, depth: float, width: float,
		rake: float) -> void:
	b.push(Transform3D(Basis(Vector3.RIGHT, rake), Vector3(0.0, -0.035, at_z)))
	b.mat(LowPoly.STRAP)
	b.frustum(Vector3.ZERO, Vector3(0, -depth, 0),
		Vector2(width, 0.030), Vector2(width * 0.92, 0.026), Vector3.BACK)
	b.mat(LowPoly.METAL)
	b.pop()


## Small indicator lamp on a housing. These are what give the black weapons a
## point of colour, and they cost four triangles each.
static func _indicator(lamp: LowPoly, pos: Vector3, radius: float) -> void:
	lamp.push(Transform3D(Basis(Vector3.UP, -PI * 0.5), pos))
	lamp.disc(Vector3.ZERO, radius, 6)
	lamp.pop()


## Segmented suppressor. The rings are what read at distance; a smooth tube of
## the same silhouette reads as a length of pipe.
static func _suppressor(b: LowPoly, from_z: float, to_z: float, radius: float,
		segments: int) -> void:
	b.tube(Vector3(0, 0, from_z), Vector3(0, 0, to_z), radius, radius, 8)
	var span := (to_z - from_z) / float(segments)
	for i in range(1, segments):
		var z := from_z + span * float(i)
		b.tube(Vector3(0, 0, z + 0.004), Vector3(0, 0, z - 0.004),
			radius * 1.14, radius * 1.14, 8, Vector3.UP, false)


# ── Marksman: long suppressed precision rifle on a bipod ──────────────────────

static func _marksman(b: LowPoly, lamp: LowPoly) -> float:
	# Receiver and rail.
	b.frustum(Vector3(0, 0, 0.12), Vector3(0, 0, -0.30),
		Vector2(0.034, 0.050), Vector2(0.030, 0.044))
	b.box(Vector3(0.0, 0.052, -0.10), Vector3(0.030, 0.012, 0.34))

	# Barrel disappearing into a heavy suppressor.
	b.tube(Vector3(0, 0, -0.30), Vector3(0, 0, -0.46), 0.015, 0.014, 6)
	_suppressor(b, -0.40, -0.88, 0.033, 4)

	# Boxy rangefinder optic. In the concept art this is the largest single
	# feature on the weapon, so it carries the silhouette.
	b.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.098, 0.0)))
	b.frustum(Vector3(0, 0, 0.04), Vector3(0, 0, -0.30),
		Vector2(0.040, 0.038), Vector2(0.038, 0.036))
	# Objective bell and lens.
	b.tube(Vector3(0, 0, -0.30), Vector3(0, 0, -0.35), 0.036, 0.042, 8)
	b.pop()
	lamp.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.098, -0.352)))
	lamp.disc(Vector3.ZERO, 0.038, 10)
	lamp.pop()

	# Status lamps down the left flank of the optic housing.
	for i in 3:
		_indicator(lamp, Vector3(-0.041, 0.112 - float(i) * 0.026, -0.13), 0.007)

	# Folding bipod, splayed under the suppressor.
	for side in [-1.0, 1.0]:
		b.mat(LowPoly.STRAP)
		b.frustum(Vector3(0.0, -0.030, -0.52),
			Vector3(side * 0.115, -0.235, -0.545),
			Vector2(0.010, 0.010), Vector2(0.008, 0.008), Vector3.BACK)
		# Foot pad.
		b.mat(LowPoly.RUBBER)
		b.box(Vector3(side * 0.118, -0.243, -0.545), Vector3(0.030, 0.012, 0.030))
		b.mat(LowPoly.METAL)

	_grip(b, 0.02, 0.115, 0.32)
	_trigger_guard(b, 0.02)
	_magazine(b, -0.08, 0.135, 0.030, 0.10)

	# Skeleton stock with an adjustable cheek riser.
	b.frustum(Vector3(0, 0, 0.12), Vector3(0, -0.012, 0.30),
		Vector2(0.026, 0.044), Vector2(0.022, 0.030))
	b.box(Vector3(0.0, 0.040, 0.26), Vector3(0.038, 0.030, 0.150))
	b.frustum(Vector3(0, -0.012, 0.30), Vector3(0, -0.030, 0.42),
		Vector2(0.022, 0.030), Vector2(0.028, 0.052))
	return -0.88


# ── Carbine: compact suppressed assault weapon ────────────────────────────────

static func _carbine(b: LowPoly, lamp: LowPoly) -> float:
	b.frustum(Vector3(0, 0, 0.08), Vector3(0, 0, -0.26),
		Vector2(0.031, 0.048), Vector2(0.029, 0.042))
	b.box(Vector3(0.0, 0.050, -0.08), Vector3(0.028, 0.010, 0.30))

	# Handguard with rail slots. The slots are raised fins rather than cut
	# geometry - same read at a fraction of the triangles.
	b.frustum(Vector3(0, 0, -0.26), Vector3(0, 0, -0.50),
		Vector2(0.029, 0.034), Vector2(0.027, 0.031))
	for i in 4:
		var z := -0.29 - float(i) * 0.045
		b.box(Vector3(0.0, 0.036, z), Vector3(0.034, 0.008, 0.016))

	_suppressor(b, -0.50, -0.68, 0.027, 3)

	# Low-profile optic.
	b.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.080, 0.0)))
	b.frustum(Vector3(0, 0, 0.00), Vector3(0, 0, -0.15),
		Vector2(0.026, 0.026), Vector2(0.026, 0.026))
	b.pop()
	lamp.push(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.080, -0.152)))
	lamp.disc(Vector3.ZERO, 0.023, 8)
	lamp.pop()
	_indicator(lamp, Vector3(-0.028, 0.094, -0.06), 0.006)

	_grip(b, 0.00, 0.108, 0.30)
	_trigger_guard(b, 0.00)
	_magazine(b, -0.09, 0.150, 0.028, 0.14)

	# Angled foregrip under the handguard.
	b.push(Transform3D(Basis(Vector3.RIGHT, -0.42), Vector3(0.0, -0.030, -0.40)))
	b.mat(LowPoly.RUBBER)
	b.frustum(Vector3.ZERO, Vector3(0, -0.090, 0),
		Vector2(0.017, 0.017), Vector2(0.015, 0.015), Vector3.BACK)
	b.mat(LowPoly.METAL)
	b.pop()

	# Collapsible stock: two thin rails and a pad, not a solid block.
	for side in [-1.0, 1.0]:
		b.frustum(Vector3(side * 0.018, 0.006, 0.08), Vector3(side * 0.018, -0.004, 0.26),
			Vector2(0.008, 0.010), Vector2(0.008, 0.010))
	b.frustum(Vector3(0, -0.004, 0.26), Vector3(0, -0.014, 0.32),
		Vector2(0.026, 0.046), Vector2(0.024, 0.052))
	return -0.68


# ── Heavy: vented support gun with a side energy cell ─────────────────────────

static func _heavy(b: LowPoly, lamp: LowPoly) -> float:
	b.frustum(Vector3(0, 0, 0.14), Vector3(0, 0, -0.32),
		Vector2(0.050, 0.068), Vector2(0.046, 0.060))
	b.box(Vector3(0.0, 0.070, -0.10), Vector3(0.040, 0.014, 0.38))

	# Barrel shroud with cooling fins.
	b.tube(Vector3(0, 0, -0.32), Vector3(0, 0, -0.72), 0.046, 0.042, 8)
	for i in 5:
		var z := -0.36 - float(i) * 0.070
		b.tube(Vector3(0, 0, z + 0.006), Vector3(0, 0, z - 0.006),
			0.053, 0.053, 8, Vector3.UP, false)

	# Muzzle brake: stepped, with a wide port ring.
	b.tube(Vector3(0, 0, -0.72), Vector3(0, 0, -0.80), 0.040, 0.052, 8)
	b.tube(Vector3(0, 0, -0.80), Vector3(0, 0, -0.86), 0.052, 0.046, 8)

	# Energy cell on the left flank - the one cyan accent on the model.
	b.mat(LowPoly.PLATE)
	b.box(Vector3(-0.062, 0.010, -0.10), Vector3(0.030, 0.084, 0.170))
	b.mat(LowPoly.METAL)
	lamp.push(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-0.078, 0.010, -0.10)))
	lamp.card(Vector3.ZERO, Vector2(0.140, 0.058))
	lamp.pop()

	_grip(b, 0.04, 0.125, 0.28)
	_trigger_guard(b, 0.04)

	# Drum-fed box magazine.
	b.mat(LowPoly.STRAP)
	b.frustum(Vector3(0, -0.055, -0.08), Vector3(0, -0.190, -0.06),
		Vector2(0.052, 0.060), Vector2(0.048, 0.056), Vector3.BACK)
	b.mat(LowPoly.METAL)

	# Forward carry handle, gripped by the support hand in the hipfire stance.
	b.push(Transform3D(Basis(Vector3.RIGHT, -0.30), Vector3(0.0, -0.052, -0.44)))
	b.mat(LowPoly.RUBBER)
	b.frustum(Vector3.ZERO, Vector3(0, -0.085, 0),
		Vector2(0.020, 0.020), Vector2(0.018, 0.018), Vector3.BACK)
	b.mat(LowPoly.METAL)
	b.pop()

	# Solid shoulder stock.
	b.frustum(Vector3(0, 0, 0.14), Vector3(0, -0.014, 0.34),
		Vector2(0.042, 0.058), Vector2(0.038, 0.062))
	return -0.86
