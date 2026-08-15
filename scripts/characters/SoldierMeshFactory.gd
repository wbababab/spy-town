class_name SoldierMeshFactory extends RefCounted

## Builds a complete soldier - skeleton, body, head assembly and cloth - from a
## SoldierProfile.
##
## SURFACE LAYOUT. Everything lands in one ArrayMesh with at most three surfaces:
## the vantablack body, the emissive lenses, and (skull archetype only) the visor
## pane. Three draw calls for a whole character, and that number does not change
## when you add pouches, plates or lamps, because geometry sharing a material is
## welded together by LowPoly rather than parented as separate MeshInstances.
##
## WHAT IS *NOT* IN THE MESH. Two things have to be their own nodes and cannot be
## welded in, both for the same reason: their shaders billboard around
## MODEL_MATRIX[3]. Bake several of them into one mesh and they all pivot about
## the character's origin instead of their own, collapsing into a single card.
## So the ocular flare and the flame plumes are separate MeshInstance3Ds, built
## by SoldierRig. The lens discs themselves are opaque and do not billboard, so
## those *are* welded in.
##
## POSE. The rest pose is neutral - arms hanging, legs straight - and stances are
## applied afterwards by rotating bones. Baking a stance into the rest would make
## the bind pose meaningless and any future animation clip fight it.

enum B {
	HIPS, SPINE, CHEST, NECK, HEAD,
	CLAVICLE_L, UPPERARM_L, FOREARM_L, HAND_L,
	CLAVICLE_R, UPPERARM_R, FOREARM_R, HAND_R,
	THIGH_L, SHIN_L, FOOT_L,
	THIGH_R, SHIN_R, FOOT_R,
	CLOAK,
}

const BONE_NAMES := [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"Clavicle.L", "UpperArm.L", "Forearm.L", "Hand.L",
	"Clavicle.R", "UpperArm.R", "Forearm.R", "Hand.R",
	"Thigh.L", "Shin.L", "Foot.L",
	"Thigh.R", "Shin.R", "Foot.R",
	"Cloak",
]

## Parent index per bone. -1 is the root. Parents always precede children, which
## Skeleton3D requires.
const BONE_PARENTS := [
	-1, B.HIPS, B.SPINE, B.CHEST, B.NECK,
	B.CHEST, B.CLAVICLE_L, B.UPPERARM_L, B.FOREARM_L,
	B.CHEST, B.CLAVICLE_R, B.UPPERARM_R, B.FOREARM_R,
	B.HIPS, B.THIGH_L, B.SHIN_L,
	B.HIPS, B.THIGH_R, B.SHIN_R,
	B.CHEST,
]

## The character's left is +X; forward is -Z, matching Node3D convention.
const LEFT := 1.0
const RIGHT := -1.0


## Returns:
##   mesh        : ArrayMesh with the body/lens/visor surfaces
##   bones       : Array of { name, parent, position } in model space
##   attachments : { flare, flames, hand_bone, head_bone, head_height }
##   tris        : total triangle count
static func build(profile: SoldierProfile, body_mat: Material, lens_mat: Material,
		visor_mat: Material) -> Dictionary:
	var P := _proportions(profile)

	var body := LowPoly.new().begin(true)
	var lens := LowPoly.new().begin(true)
	var visor := LowPoly.new().begin(true)

	_torso(body, P, profile)
	_legs(body, P, profile)
	_arms(body, P, profile)
	_gear(body, P, profile)

	var head_result := _head(body, lens, visor, P, profile)

	if profile.has_cloak:
		_cloak(body, P, profile)
	if profile.has_shroud:
		_shroud(body, P, profile)

	var mesh := ArrayMesh.new()
	body.commit_surface(mesh, body_mat)
	lens.commit_surface(mesh, lens_mat)
	# Tangents are required only here: skull_visor.gdshader projects the view
	# vector into tangent space to drive the parallax interior.
	visor.commit_surface(mesh, visor_mat, true)

	var flames: Array[Transform3D] = []
	for pt: Vector3 in profile.flame_points:
		flames.append(Transform3D(Basis.IDENTITY, pt * P.s))

	return {
		"mesh": mesh,
		"bones": _bone_defs(P),
		"attachments": {
			"flare": head_result.get("flare", null),
			"flames": flames,
			"hand_bone": B.HAND_R,
			"head_bone": B.HEAD,
			"head_height": P.head,
		},
		"tris": body.triangle_count() + lens.triangle_count() + visor.triangle_count(),
	}


# ── Proportions ───────────────────────────────────────────────────────────────

static func _proportions(p: SoldierProfile) -> Dictionary:
	# Authored against a 1.85 m reference figure. `s` scales the vertical
	# skeleton; `bulk` scales cross-sections only, so a heavier soldier gets
	# thicker rather than taller. Shoulder span is absolute, not scaled, so it
	# stays a directly dialled silhouette control.
	var s := p.scale_factor()
	var bw := p.bulk
	var half_span: float = p.shoulder_width * 0.5
	return {
		"s": s,
		"bw": bw,
		"ankle": 0.085 * s,
		"knee": 0.470 * s,
		"hip": 0.940 * s,
		"spine": 1.075 * s,
		"chest": 1.240 * s,
		"neck": 1.470 * s,
		"head": 1.545 * s,
		"hip_x": 0.098 * s,
		"clav_y": 1.430 * s,
		"clav_x": 0.072 * s,
		"sh_x": half_span,
		"elbow_y": 1.160 * s,
		"elbow_x": half_span + 0.026,
		"wrist_y": 0.905 * s,
		"wrist_x": half_span + 0.038,
	}


static func _bone_defs(P: Dictionary) -> Array:
	var pos := {
		B.HIPS: Vector3(0, P.hip, 0),
		B.SPINE: Vector3(0, P.spine, 0),
		B.CHEST: Vector3(0, P.chest, 0),
		B.NECK: Vector3(0, P.neck, 0),
		B.HEAD: Vector3(0, P.head, 0),
		B.CLAVICLE_L: Vector3(LEFT * P.clav_x, P.clav_y, 0),
		B.UPPERARM_L: Vector3(LEFT * P.sh_x, P.clav_y, 0),
		B.FOREARM_L: Vector3(LEFT * P.elbow_x, P.elbow_y, 0),
		B.HAND_L: Vector3(LEFT * P.wrist_x, P.wrist_y, 0),
		B.CLAVICLE_R: Vector3(RIGHT * P.clav_x, P.clav_y, 0),
		B.UPPERARM_R: Vector3(RIGHT * P.sh_x, P.clav_y, 0),
		B.FOREARM_R: Vector3(RIGHT * P.elbow_x, P.elbow_y, 0),
		B.HAND_R: Vector3(RIGHT * P.wrist_x, P.wrist_y, 0),
		B.THIGH_L: Vector3(LEFT * P.hip_x, P.hip, 0),
		B.SHIN_L: Vector3(LEFT * P.hip_x, P.knee, 0),
		B.FOOT_L: Vector3(LEFT * P.hip_x, P.ankle, 0),
		B.THIGH_R: Vector3(RIGHT * P.hip_x, P.hip, 0),
		B.SHIN_R: Vector3(RIGHT * P.hip_x, P.knee, 0),
		B.FOOT_R: Vector3(RIGHT * P.hip_x, P.ankle, 0),
		B.CLOAK: Vector3(0, P.chest, 0.04),
	}
	var out := []
	for i in BONE_NAMES.size():
		out.append({
			"name": BONE_NAMES[i],
			"parent": BONE_PARENTS[i],
			"position": pos[i],
		})
	return out


# ── Torso ─────────────────────────────────────────────────────────────────────

static func _torso(b: LowPoly, P: Dictionary, p: SoldierProfile) -> void:
	var bw: float = P.bw
	# Vertical segments take Vector3.BACK as their up hint so that half-extents
	# read as (width across X, depth through Z). Passing UP would leave the
	# cross-section axes chosen arbitrarily by the fallback in LowPoly.frustum.
	var back := Vector3.BACK

	b.bone(B.HIPS).mat(LowPoly.PLATE)
	b.frustum(Vector3(0, P.hip - 0.045, 0), Vector3(0, P.hip + 0.070, 0),
		Vector2(0.148 * bw, 0.098 * bw), Vector2(0.140 * bw, 0.094 * bw), back)
	# Belt.
	b.mat(LowPoly.STRAP)
	b.frustum(Vector3(0, P.hip + 0.058, 0), Vector3(0, P.hip + 0.092, 0),
		Vector2(0.146 * bw, 0.100 * bw), Vector2(0.144 * bw, 0.099 * bw), back)

	b.bone(B.SPINE).mat(LowPoly.PLATE)
	b.frustum(Vector3(0, P.spine - 0.010, 0), Vector3(0, P.spine + 0.110, 0),
		Vector2(0.142 * bw, 0.094 * bw), Vector2(0.166 * bw, 0.104 * bw), back)

	b.bone(B.CHEST)
	# Ribcage flaring out toward the shoulders...
	b.frustum(Vector3(0, P.chest - 0.055, 0), Vector3(0, P.clav_y - 0.055, 0),
		Vector2(0.166 * bw, 0.104 * bw),
		Vector2(P.sh_x * 0.84, 0.112 * bw), back)
	# ...then a trapezius yoke narrowing back in to the neck. Capping the chest
	# flat at full shoulder width instead leaves a horizontal slab whose top face
	# catches the backlight and reads as a bright bar laid across the collarbones.
	b.frustum(Vector3(0, P.clav_y - 0.055, 0), Vector3(0, P.clav_y + 0.038, 0),
		Vector2(P.sh_x * 0.84, 0.112 * bw),
		Vector2(0.078 * bw, 0.082 * bw), back)
	# Chest armour panel, bevelled so it catches a grazing highlight.
	b.push(Transform3D(Basis(Vector3.UP, PI), Vector3(0, P.chest + 0.040, -0.104 * bw)))
	b.plate(Vector3.ZERO, Vector3(P.sh_x * 1.28, 0.230 * P.s, 0.030), 0.30)
	b.pop()
	# Upper back plate.
	b.push(Transform3D(Basis.IDENTITY, Vector3(0, P.chest + 0.055, 0.102 * bw)))
	b.plate(Vector3.ZERO, Vector3(P.sh_x * 1.20, 0.210 * P.s, 0.026), 0.35)
	b.pop()

	b.bone(B.NECK).mat(LowPoly.STRAP)
	b.frustum(Vector3(0, P.neck - 0.020, 0), Vector3(0, P.head, 0),
		Vector2(0.056 * bw, 0.052 * bw), Vector2(0.050 * bw, 0.048 * bw), back)


# ── Legs ──────────────────────────────────────────────────────────────────────

static func _legs(b: LowPoly, P: Dictionary, p: SoldierProfile) -> void:
	var bw: float = P.bw
	var back := Vector3.BACK
	var thigh_bones := [B.THIGH_L, B.THIGH_R]
	var shin_bones := [B.SHIN_L, B.SHIN_R]
	var foot_bones := [B.FOOT_L, B.FOOT_R]

	for i in 2:
		var sx: float = [LEFT, RIGHT][i] * P.hip_x

		b.bone(thigh_bones[i]).mat(LowPoly.PLATE)
		b.frustum(Vector3(sx, P.hip, 0), Vector3(sx, P.knee + 0.030, 0),
			Vector2(0.078 * bw, 0.082 * bw), Vector2(0.060 * bw, 0.064 * bw), back)
		# Thigh pouch/armour wrap.
		b.mat(LowPoly.STRAP)
		b.frustum(Vector3(sx, P.hip - 0.090, 0), Vector3(sx, P.hip - 0.180, 0),
			Vector2(0.082 * bw, 0.086 * bw), Vector2(0.076 * bw, 0.080 * bw), back)

		b.bone(shin_bones[i]).mat(LowPoly.PLATE)
		b.frustum(Vector3(sx, P.knee + 0.030, 0), Vector3(sx, P.ankle + 0.020, 0),
			Vector2(0.058 * bw, 0.062 * bw), Vector2(0.044 * bw, 0.048 * bw), back)
		# Knee pad, pushed forward off the joint.
		b.push(Transform3D(Basis(Vector3.UP, PI), Vector3(sx, P.knee + 0.010, -0.062 * bw)))
		b.plate(Vector3.ZERO, Vector3(0.104 * bw, 0.115 * P.s, 0.034), 0.40)
		b.pop()
		# Shin guard.
		b.push(Transform3D(Basis(Vector3.UP, PI),
			Vector3(sx, (P.knee + P.ankle) * 0.5 - 0.040, -0.056 * bw)))
		b.mat(LowPoly.GRIME)
		b.plate(Vector3.ZERO, Vector3(0.086 * bw, 0.200 * P.s, 0.022), 0.35)
		b.pop()

		b.bone(foot_bones[i]).mat(LowPoly.RUBBER)
		# Boot: upper, then a wider sole that reads at ground level.
		b.frustum(Vector3(sx, P.ankle + 0.020, 0), Vector3(sx, P.ankle - 0.030, -0.030),
			Vector2(0.046 * bw, 0.050 * bw), Vector2(0.052 * bw, 0.090 * bw), back)
		b.box(Vector3(sx, P.ankle - 0.052, -0.040), Vector3(0.108 * bw, 0.044, 0.250 * P.s))
		b.box(Vector3(sx, P.ankle - 0.076, -0.040), Vector3(0.116 * bw, 0.020, 0.262 * P.s))


# ── Arms ──────────────────────────────────────────────────────────────────────

static func _arms(b: LowPoly, P: Dictionary, p: SoldierProfile) -> void:
	var bw: float = P.bw
	var back := Vector3.BACK
	var clav := [B.CLAVICLE_L, B.CLAVICLE_R]
	var upper := [B.UPPERARM_L, B.UPPERARM_R]
	var fore := [B.FOREARM_L, B.FOREARM_R]
	var hand := [B.HAND_L, B.HAND_R]

	for i in 2:
		var side: float = [LEFT, RIGHT][i]
		var sh_x: float = side * P.sh_x
		var el_x: float = side * P.elbow_x
		var wr_x: float = side * P.wrist_x

		# Pauldron: a layered pair of plates, which is what makes the shoulder
		# read as armour rather than as the top of a sleeve.
		#
		# Bound to the upper arm, not the clavicle. Real pauldrons ride the
		# deltoid, and binding them to the torso leaves them hanging in the air
		# over nothing the moment a stance swings the arm forward.
		b.bone(upper[i]).mat(LowPoly.PLATE)
		b.push(Transform3D(Basis(Vector3.FORWARD, side * -0.20),
			Vector3(sh_x, P.clav_y + 0.026, 0)))
		b.frustum(Vector3(0, 0.030, 0), Vector3(0, -0.060 * P.s, 0),
			Vector2(0.066 * bw, 0.070 * bw), Vector2(0.076 * bw, 0.076 * bw), back)
		b.frustum(Vector3(0, -0.054 * P.s, 0), Vector3(0, -0.118 * P.s, 0),
			Vector2(0.074 * bw, 0.074 * bw), Vector2(0.058 * bw, 0.060 * bw), back)
		b.pop()

		b.bone(upper[i])
		b.frustum(Vector3(sh_x, P.clav_y - 0.040, 0), Vector3(el_x, P.elbow_y, 0),
			Vector2(0.056 * bw, 0.060 * bw), Vector2(0.044 * bw, 0.048 * bw), back)

		b.bone(fore[i])
		b.frustum(Vector3(el_x, P.elbow_y, 0), Vector3(wr_x, P.wrist_y, 0),
			Vector2(0.046 * bw, 0.050 * bw), Vector2(0.036 * bw, 0.040 * bw), back)
		# Forearm guard.
		b.push(Transform3D(Basis(Vector3.UP, PI),
			Vector3((el_x + wr_x) * 0.5, (P.elbow_y + P.wrist_y) * 0.5, -0.046 * bw)))
		b.plate(Vector3.ZERO, Vector3(0.078 * bw, 0.170 * P.s, 0.026), 0.38)
		b.pop()

		b.bone(hand[i]).mat(LowPoly.RUBBER)
		# Gloved fist: palm block plus a knuckle ridge.
		b.frustum(Vector3(wr_x, P.wrist_y, 0), Vector3(wr_x, P.wrist_y - 0.090 * P.s, -0.010),
			Vector2(0.036 * bw, 0.044 * bw), Vector2(0.038 * bw, 0.052 * bw), back)
		b.box(Vector3(wr_x, P.wrist_y - 0.100 * P.s, -0.024),
			Vector3(0.072 * bw, 0.048, 0.060))


# ── Webbing and pouches ───────────────────────────────────────────────────────

static func _gear(b: LowPoly, P: Dictionary, p: SoldierProfile) -> void:
	var bw: float = P.bw
	b.bone(B.CHEST).mat(LowPoly.STRAP)

	# Magazine pouches across the front of the chest rig.
	if p.chest_pouches > 0:
		var span: float = P.sh_x * 1.05
		for i in p.chest_pouches:
			var t := 0.5 if p.chest_pouches == 1 else float(i) / float(p.chest_pouches - 1)
			var x: float = lerp(-span, span, t)
			b.box(Vector3(x, P.chest - 0.010, -0.118 * bw),
				Vector3(span * 0.62, 0.115 * P.s, 0.052))

	# Shoulder straps running over the chest plate.
	for side in [LEFT, RIGHT]:
		b.frustum(Vector3(side * P.sh_x * 0.55, P.clav_y - 0.020, -0.070 * bw),
			Vector3(side * 0.030, P.chest - 0.090, -0.112 * bw),
			Vector2(0.038, 0.018), Vector2(0.034, 0.018), Vector3.BACK)

	if p.has_backpack:
		b.mat(LowPoly.PLATE)
		b.push(Transform3D(Basis.IDENTITY, Vector3(0, P.chest + 0.030, 0.170 * bw)))
		b.plate(Vector3.ZERO, Vector3(P.sh_x * 1.30, 0.330 * P.s, 0.110), 0.22)
		b.pop()
		b.mat(LowPoly.STRAP)
		# Two canister cells clamped to the pack.
		for side in [LEFT, RIGHT]:
			b.tube(Vector3(side * P.sh_x * 0.52, P.chest + 0.150, 0.215 * bw),
				Vector3(side * P.sh_x * 0.52, P.chest - 0.100, 0.215 * bw),
				0.040 * bw, 0.040 * bw, 6, Vector3.BACK)

	if p.has_thigh_holster:
		b.bone(B.THIGH_R).mat(LowPoly.STRAP)
		b.box(Vector3(RIGHT * (P.hip_x + 0.070 * bw), P.hip - 0.230, 0.010),
			Vector3(0.060, 0.170 * P.s, 0.086))


# ── Head assemblies ───────────────────────────────────────────────────────────

## Builds the helmet shared by all three archetypes, then dispatches to the
## style-specific face. All head geometry is authored in a local frame with the
## origin at the neck joint, which keeps the numbers small and readable.
static func _head(b: LowPoly, lens: LowPoly, visor: LowPoly, P: Dictionary,
		p: SoldierProfile) -> Dictionary:
	var s: float = P.s
	var head_origin := Vector3(0, P.head, 0)

	b.bone(B.HEAD)
	lens.bone(B.HEAD)
	visor.bone(B.HEAD)

	b.push(Transform3D(Basis.IDENTITY, head_origin))
	lens.push(Transform3D(Basis.IDENTITY, head_origin))
	visor.push(Transform3D(Basis.IDENTITY, head_origin))

	var back := Vector3.BACK
	b.mat(LowPoly.PLATE)
	# Jaw guard, cranium dome, crown cap. Three stacked frusta give the faceted
	# helmet profile from the concept art in 36 triangles.
	b.frustum(Vector3(0, 0.020 * s, 0), Vector3(0, 0.115 * s, 0.006),
		Vector2(0.076, 0.084), Vector2(0.094, 0.100), back)
	b.frustum(Vector3(0, 0.115 * s, 0.006), Vector3(0, 0.235 * s, 0.004),
		Vector2(0.094, 0.100), Vector2(0.080, 0.088), back)
	b.frustum(Vector3(0, 0.235 * s, 0.004), Vector3(0, 0.272 * s, 0.002),
		Vector2(0.080, 0.088), Vector2(0.050, 0.058), back)
	# Rear counterweight, present on all three so the helmet is not front-heavy.
	b.box(Vector3(0, 0.170 * s, 0.092), Vector3(0.086, 0.070, 0.040))

	var result := {}
	match p.head_style:
		SoldierProfile.Head.NVG_CLUSTER:
			result = _face_nvg(b, lens, P, p)
		SoldierProfile.Head.SINGLE_OCULAR:
			result = _face_ocular(b, lens, P, p)
		SoldierProfile.Head.SKULL_VISOR:
			result = _face_skull(b, lens, visor, P, p)

	# Attachment transforms come back in head-local space; lift them into model
	# space so SoldierRig can hang nodes off the head BoneAttachment3D.
	if result.has("flare") and result.flare != null:
		var f: Dictionary = result.flare
		f.xform = Transform3D(f.xform.basis, head_origin + f.xform.origin)

	b.pop()
	lens.pop()
	visor.pop()
	return result


## Four-lamp night-vision rack on a forehead mount.
static func _face_nvg(b: LowPoly, lens: LowPoly, P: Dictionary,
		p: SoldierProfile) -> Dictionary:
	var s: float = P.s

	b.mat(LowPoly.PLATE)
	# Mount bracket.
	b.box(Vector3(0, 0.196 * s, -0.086), Vector3(0.132, 0.052, 0.046))
	# Respirator across the lower face.
	b.mat(LowPoly.RUBBER)
	b.box(Vector3(0, 0.080 * s, -0.082), Vector3(0.104, 0.070, 0.044))
	b.mat(LowPoly.STRAP)
	# Filter canisters either side of the jaw.
	for side in [LEFT, RIGHT]:
		b.tube(Vector3(side * 0.056, 0.078 * s, -0.084),
			Vector3(side * 0.056, 0.078 * s, -0.104), 0.020, 0.018, 6)

	# Lamp housings and lenses. Facing -Z means rotating the local frame by PI
	# about Y, since LowPoly.disc builds facing local +Z.
	var facing := Basis(Vector3.UP, PI)
	var xs := [-0.051, -0.017, 0.017, 0.051]
	b.mat(LowPoly.METAL)
	for x: float in xs:
		b.tube(Vector3(x, 0.196 * s, -0.100), Vector3(x, 0.196 * s, -0.122),
			0.021, 0.023, 6)
		lens.push(Transform3D(facing, Vector3(x, 0.196 * s, -0.1235)))
		lens.disc(Vector3.ZERO, p.ocular_radius, 8)
		lens.pop()

	# One flare card spanning the whole rack rather than four. The lamps sit
	# close enough that four separate streaks overlap into mush anyway, and this
	# keeps the character at a single extra transparent draw.
	return {
		"flare": {
			"xform": Transform3D(facing, Vector3(0.0, 0.196 * s, -0.130)),
			"size": Vector2(0.17, 0.075),
		}
	}


## Single large ranging optic under a draped shroud.
static func _face_ocular(b: LowPoly, lens: LowPoly, P: Dictionary,
		p: SoldierProfile) -> Dictionary:
	var s: float = P.s
	var facing := Basis(Vector3.UP, PI)
	# The marksman's eye sits off-centre, which is most of why this silhouette
	# reads as a different character rather than a resized one.
	var eye_x: float = LEFT * 0.036

	b.mat(LowPoly.RUBBER)
	# Face wrap under the shroud.
	b.box(Vector3(0, 0.110 * s, -0.078), Vector3(0.150, 0.130, 0.040))

	b.mat(LowPoly.METAL)
	# Heavy optic housing with a stepped bell.
	b.tube(Vector3(eye_x, 0.150 * s, -0.086), Vector3(eye_x, 0.150 * s, -0.126),
		0.038, 0.044, 8)
	b.tube(Vector3(eye_x, 0.150 * s, -0.126), Vector3(eye_x, 0.150 * s, -0.138),
		0.046, 0.042, 8)
	lens.push(Transform3D(facing, Vector3(eye_x, 0.150 * s, -0.1395)))
	lens.disc(Vector3.ZERO, p.ocular_radius, 10)
	lens.pop()

	# Small ranging emitter beside the main optic.
	b.tube(Vector3(RIGHT * 0.052, 0.148 * s, -0.084),
		Vector3(RIGHT * 0.052, 0.148 * s, -0.100), 0.014, 0.015, 6)
	lens.push(Transform3D(facing, Vector3(RIGHT * 0.052, 0.148 * s, -0.1015)))
	lens.disc(Vector3.ZERO, p.ocular_radius * 0.38, 6)
	lens.pop()

	return {
		"flare": {
			"xform": Transform3D(facing, Vector3(eye_x, 0.150 * s, -0.146)),
			"size": Vector2(0.13, 0.065),
		}
	}


## Full-face pane with the skull rendered behind it by skull_visor.gdshader.
static func _face_skull(b: LowPoly, lens: LowPoly, visor: LowPoly, P: Dictionary,
		p: SoldierProfile) -> Dictionary:
	var s: float = P.s
	b.mat(LowPoly.PLATE)

	# Brow ridge and cheek rails frame the pane. Without a frame the visor reads
	# as a hole cut in the helmet rather than as a fitted faceplate.
	b.box(Vector3(0, 0.224 * s, -0.100), Vector3(0.180, 0.036, 0.052))
	b.box(Vector3(0, 0.036 * s, -0.076), Vector3(0.150, 0.040, 0.050))
	for side in [LEFT, RIGHT]:
		b.frustum(Vector3(side * 0.099, 0.220 * s, -0.070),
			Vector3(side * 0.088, 0.040 * s, -0.062),
			Vector2(0.021, 0.048), Vector2(0.020, 0.044), Vector3.BACK)
	# Chin cowl.
	b.mat(LowPoly.RUBBER)
	b.box(Vector3(0, 0.014 * s, -0.052), Vector3(0.126, 0.044, 0.070))

	# The pane is curved, not flat. A flat pane has one normal, so its Fresnel
	# term is constant across the whole surface and the glass reads as a sticker;
	# curvature is what makes the edges flare and the centre stay clear.
	#
	# It also sits *proud* of the shared helmet shell, whose front face is around
	# z = -0.09. Tucked inside that, the pane is occluded by the very helmet it
	# belongs to and only the tip of its bulge shows through.
	_curved_pane(visor, Vector3(0.0, 0.130 * s, -0.100), Vector2(0.168, 0.190),
		0.018, 4, 4)

	return {"flare": null}


## Shallow dome of quads facing -Z, UV mapped 0..1 across the whole pane.
static func _curved_pane(v: LowPoly, center: Vector3, size: Vector2, curve: float,
		cols: int, rows: int) -> void:
	var pts := []
	var uvs := []
	for j in rows + 1:
		var row := []
		var uv_row := []
		for i in cols + 1:
			var u := float(i) / float(cols)
			var w := float(j) / float(rows)
			var dx := (u - 0.5) * 2.0
			var dy := (w - 0.5) * 2.0
			# Bulge forward (-Z) at the centre, flattening toward the rim.
			var bulge: float = -curve * max(0.0, 1.0 - dx * dx * 0.85 - dy * dy * 0.55)
			row.append(center + Vector3((u - 0.5) * size.x, (w - 0.5) * size.y, bulge))
			# One continuous 0..1 island across the pane, running bottom-up.
			# UV here is the skull's coordinate system, not a texture lookup, so
			# it follows world +y; the usual y-down image convention would draw
			# the whole face upside down.
			uv_row.append(Vector2(u, w))
		pts.append(row)
		uvs.append(uv_row)

	for j in rows:
		for i in cols:
			# (p00, p10, p11, p01) is clockwise seen from -Z; see LowPoly's note.
			v.quad_uv(pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i],
				uvs[j][i], uvs[j][i + 1], uvs[j + 1][i + 1], uvs[j + 1][i])


# ── Cloth ─────────────────────────────────────────────────────────────────────

## Torn cloak hanging from the shoulders, and the marksman's head shroud.
##
## Built as independent vertical ribbons rather than one skirt: the gaps between
## ribbons are the tatters, so the shredded silhouette costs nothing extra. Both
## faces are emitted with opposite winding so the cloth is visible from behind
## without needing a second cull_disabled material.
static func _cloth_strips(b: LowPoly, bone: int, top_y: float, top_r: float,
		bottom_r: float, length: float, strips: int, shred: float,
		ang_min: float, ang_max: float, seed: int, segments: int = 4) -> void:
	if strips < 2:
		return
	b.bone(bone).mat(LowPoly.CLOTH)
	var gap := (ang_max - ang_min) / float(strips)

	for i in strips:
		var ang: float = ang_min + gap * (float(i) + 0.5)
		var half_w: float = gap * 0.56
		# Ribbons are individually shortened so the hem is ragged, and the
		# outermost ones are cut back hardest, which keeps the shoulders clean.
		var edge: float = abs(float(i) / float(strips - 1) - 0.5) * 2.0
		var len_i: float = length * (1.0 - shred * (0.20 + 0.75 * _hash01(seed, i)))
		len_i *= lerp(1.0, 0.55, edge * 0.8)

		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for j in segments + 1:
			var t := float(j) / float(segments)
			var y: float = top_y - len_i * t
			var radius: float = lerp(top_r, bottom_r, t)
			# Per-segment sway so the cloth is not a perfect cone.
			var wobble: float = (_hash01(seed + 31, i * 16 + j) - 0.5) * 0.055 * t
			# Wide and overlapping at the shoulder, narrowing into separate
			# tatters lower down - a cloak that is shredded all the way to the
			# collar reads as a grass skirt.
			var hw: float = half_w * lerp(1.45, 0.40, t * t)
			var la: float = ang - hw + wobble
			var ra: float = ang + hw + wobble
			var l := Vector3(sin(la) * radius, y, cos(la) * radius)
			var r := Vector3(sin(ra) * radius, y, cos(ra) * radius)
			if j > 0:
				b.quad(prev_l, prev_r, r, l)
				b.quad(l, r, prev_r, prev_l)
			prev_l = l
			prev_r = r


static func _cloak(b: LowPoly, P: Dictionary, p: SoldierProfile) -> void:
	_cloth_strips(b, B.CLOAK, P.clav_y - 0.020,
		P.sh_x * 0.95, P.sh_x * 1.35 + 0.06,
		p.cloak_length * P.s, p.cloak_strips, p.cloak_shred,
		-2.55, 2.55, 1207)


static func _shroud(b: LowPoly, P: Dictionary, p: SoldierProfile) -> void:
	# Netting over the helmet, and a second shorter layer over the shoulders.
	# The head layer has to start wider than the helmet it drapes over - the
	# helmet is ~0.10 in half-depth, so anything tighter than that is authored
	# inside the skull and never seen.
	_cloth_strips(b, B.HEAD, P.head + 0.262 * P.s, 0.108, 0.170,
		0.42 * P.s, 12, 0.75, -2.9, 2.9, 4409, 3)
	_cloth_strips(b, B.CHEST, P.clav_y + 0.010, P.sh_x * 0.90, P.sh_x * 1.15,
		0.44 * P.s, 10, 0.85, -2.7, 2.7, 8821, 3)


## Deterministic value hash. Keeps a given profile's tatters identical between
## runs and between clients, which matters because this geometry is rebuilt
## locally rather than replicated.
static func _hash01(a: int, b: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663)
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0
