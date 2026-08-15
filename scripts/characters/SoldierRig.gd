class_name SoldierRig extends Node3D

## Assembles a soldier at runtime: skeleton, skinned body, weapon, ocular flare
## and flame plumes, plus the distance-based quality falloff.
##
## Nothing here is baked into a .tscn. A profile resource plus this script is the
## whole character, so a new archetype costs one .tres and no scene work, and the
## mesh is regenerated at load rather than shipped - which is why the repository
## contains no model files.
##
## COST. Per character on the high preset: three surfaces for the body, one for
## the weapon, one for the weapon lamps, one flare card, and one draw per flame
## plume. Everything beyond the six static surfaces is dropped by distance before
## it can add up, because the expensive parts are exactly the parts that stop
## being legible past a few metres.

const B := SoldierMeshFactory.B

enum Quality {
	LOW,    ## No flare card, no ocular light, plumes without screen-space work.
	MEDIUM, ## Flare and light on; plumes still skip refraction.
	HIGH,   ## Everything.
}

@export var profile: SoldierProfile
@export var quality: Quality = Quality.HIGH
## Rebuild whenever the node enters the tree. Turn off if you intend to call
## rebuild() yourself after configuring the profile in code.
@export var build_on_ready: bool = true

@export_group("Detail falloff")
## Beyond this, plumes are hidden outright. They are a silhouette effect and a
## plume six pixels wide is noise, not atmosphere.
@export var flame_distance: float = 18.0
## Beyond this, plumes stop sampling the screen and depth buffers.
@export var flame_detail_distance: float = 9.0
@export var flare_distance: float = 14.0
@export var light_distance: float = 12.0

var skeleton: Skeleton3D
var body: MeshInstance3D
var weapon: MeshInstance3D
var muzzle: Marker3D

var _flare: MeshInstance3D
var _ocular_light: OmniLight3D
var _muzzle_light: OmniLight3D
var _plumes: Array[MeshInstance3D] = []

var _mat_body: ShaderMaterial
var _mat_ocular: ShaderMaterial
var _mat_visor: ShaderMaterial
var _mat_flame: ShaderMaterial

var _stance_pose: Dictionary = {}
var _tri_count: int = 0
var _idle_phase: float = 0.0
var _muzzle_flash: float = 0.0
var _last_detail := -1
# The Compatibility renderer does not share Forward+'s depth-buffer convention,
# so the plumes' soft-edge path would erase them there rather than soften them.
var _has_depth_fx := RenderingServer.get_current_rendering_method() != "gl_compatibility"


func _ready() -> void:
	_idle_phase = randf() * TAU
	if build_on_ready and profile:
		rebuild()


## Total triangles in the character and its weapon. Printed by the forge scene.
func triangle_count() -> int:
	return _tri_count


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_plumes.clear()
	if profile == null:
		push_warning("SoldierRig has no profile; nothing to build.")
		return

	_mat_body = SoldierMaterials.body(profile)
	_mat_ocular = SoldierMaterials.ocular(profile)
	_mat_visor = SoldierMaterials.visor(profile)
	_mat_flame = SoldierMaterials.flame(profile)

	var build := SoldierMeshFactory.build(profile, _mat_body, _mat_ocular, _mat_visor)
	_tri_count = build.tris

	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	_populate_bones(build.bones)

	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = build.mesh
	skeleton.add_child(body)
	# Bind poses come straight from the rest transforms because the geometry was
	# authored in model space at rest; see the rigid-binding note in LowPoly.
	body.skin = skeleton.create_skin_from_rest_transforms()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_apply_stance(profile.stance)
	_build_weapon(build.attachments)
	_build_head_effects(build.attachments, build.bones)
	_build_plumes(build.attachments, build.bones)
	set_quality(quality)


func _populate_bones(bones: Array) -> void:
	for i in bones.size():
		skeleton.add_bone(bones[i].name)
	for i in bones.size():
		var parent: int = bones[i].parent
		skeleton.set_bone_parent(i, parent)
		# Rest bases are identity throughout, so a bone's local rest is just the
		# offset from its parent's joint. Rotating a bone then pivots about that
		# joint, which is exactly what the stance tables assume.
		var local: Vector3 = bones[i].position
		if parent >= 0:
			local -= bones[parent].position
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
	skeleton.reset_bone_poses()


# ── Weapon ────────────────────────────────────────────────────────────────────

func _build_weapon(attachments: Dictionary) -> void:
	var built := WeaponMeshFactory.build(profile.weapon, SoldierMaterials.weapon(),
		_mat_ocular)
	_tri_count += built.tris

	var attach := BoneAttachment3D.new()
	attach.name = "HandR"
	attach.bone_idx = attachments.hand_bone
	skeleton.add_child(attach)

	weapon = MeshInstance3D.new()
	weapon.name = "Weapon"
	weapon.mesh = built.mesh
	attach.add_child(weapon)

	# Rather than hand-tuning a grip offset per stance, cancel out whatever
	# rotation the stance left on the hand and re-aim the weapon in model space.
	# Change the arm pose freely and the muzzle still points forward.
	var hand_basis := skeleton.get_bone_global_pose(attachments.hand_bone).basis
	var aim := Basis.from_euler(Vector3(deg_to_rad(-4.0), deg_to_rad(-5.0), 0.0))
	weapon.transform = Transform3D(hand_basis.inverse() * aim,
		Vector3(0.0, 0.02, -0.05))

	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.transform = built.muzzle
	weapon.add_child(muzzle)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "MuzzleFlash"
	_muzzle_light.omni_range = 4.5
	_muzzle_light.light_color = Color(1.0, 0.82, 0.55)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.shadow_enabled = false
	muzzle.add_child(_muzzle_light)


# ── Head effects ──────────────────────────────────────────────────────────────

func _build_head_effects(attachments: Dictionary, bones: Array) -> void:
	var attach := BoneAttachment3D.new()
	attach.name = "Head"
	attach.bone_idx = attachments.head_bone
	skeleton.add_child(attach)

	# Model-space rest origin of the head joint, taken from the build data rather
	# than queried off the skeleton: the attachment transforms below are relative
	# to this, and reading it back from a skeleton that has already been posed
	# would fold the stance in twice.
	var head_rest: Vector3 = bones[attachments.head_bone].position

	var flare_data = attachments.flare
	if flare_data != null:
		var lp := LowPoly.new().begin(false)
		lp.card(Vector3.ZERO, flare_data.size)
		var mesh := ArrayMesh.new()
		lp.commit_surface(mesh, SoldierMaterials.flare(profile))

		_flare = MeshInstance3D.new()
		_flare.name = "OcularFlare"
		_flare.mesh = mesh
		_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Attachment transforms arrive in model space; the BoneAttachment3D
		# already supplies the head's pose, so subtract its rest origin.
		var xf: Transform3D = flare_data.xform
		_flare.transform = Transform3D(xf.basis, xf.origin - head_rest)
		attach.add_child(_flare)

	# One light for the whole lamp cluster, not one per lamp. Four omni lights on
	# a helmet is four shadow-less light passes for a pool of light the player
	# reads as a single source anyway.
	_ocular_light = OmniLight3D.new()
	_ocular_light.name = "OcularLight"
	_ocular_light.omni_range = 3.2
	_ocular_light.light_color = profile.ocular_halo
	_ocular_light.light_energy = 1.4
	_ocular_light.shadow_enabled = false
	# Engine-side fade, so this costs nothing to maintain per frame.
	_ocular_light.distance_fade_enabled = true
	_ocular_light.distance_fade_begin = light_distance * 0.7
	_ocular_light.distance_fade_length = light_distance * 0.3
	_ocular_light.position = Vector3(0.0, 0.20, -0.18)
	attach.add_child(_ocular_light)


# ── Flame plumes ──────────────────────────────────────────────────────────────

func _build_plumes(attachments: Dictionary, bones: Array) -> void:
	var points: Array = attachments.flames
	if points.is_empty():
		return

	var attach := BoneAttachment3D.new()
	attach.name = "Chest"
	attach.bone_idx = B.CHEST
	skeleton.add_child(attach)
	var chest_rest: Vector3 = bones[B.CHEST].position

	for i in points.size():
		var lp := LowPoly.new().begin(false)
		# Vary the silhouette per emitter so a row of plumes does not read as a
		# repeated stamp; the shader's `phase` handles the temporal half.
		var jitter := 0.75 + 0.5 * SoldierMeshFactory._hash01(97, i)
		lp.flame_quad(Vector3.ZERO, profile.flame_height * jitter,
			profile.flame_width * (1.9 - jitter))
		var mesh := ArrayMesh.new()
		lp.commit_surface(mesh, _mat_flame)

		var mi := MeshInstance3D.new()
		mi.name = "Plume%d" % i
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Billboarded geometry has no meaningful bounds, so give it a generous
		# custom AABB or it pops out at the screen edge.
		mi.custom_aabb = AABB(Vector3(-1.0, -0.5, -1.0), Vector3(2.0, 3.0, 2.0))
		mi.position = (points[i] as Transform3D).origin - chest_rest
		mi.set_instance_shader_parameter("phase", SoldierMeshFactory._hash01(53, i) * 40.0)
		attach.add_child(mi)
		_plumes.append(mi)


# ── Stance ────────────────────────────────────────────────────────────────────

## Rotations are applied on top of the neutral rest pose, in degrees, XYZ Euler.
## Positive X on a hanging limb swings it forward.
static func stance_table(stance: SoldierProfile.Stance) -> Dictionary:
	match stance:
		SoldierProfile.Stance.KNEEL:
			return {
				"root_offset": Vector3(0.0, -0.40, 0.02),
				B.SPINE: Vector3(-14, 0, 0),
				B.CHEST: Vector3(-8, 10, 0),
				B.NECK: Vector3(6, 0, 0),
				B.HEAD: Vector3(10, -8, 0),
				# Right leg forward with the foot planted, left knee on the deck.
				# These angles are solved against the reference skeleton rather
				# than eyeballed: with the hips dropped 0.40, a 75-degree thigh
				# puts the lead knee at the right height for the shin to reach
				# the ground, and -25 on the trailing thigh sets the rear knee
				# down at pad height with the shin flat behind it.
				B.THIGH_R: Vector3(75, -4, 0),
				B.SHIN_R: Vector3(-108, 0, 0),
				B.FOOT_R: Vector3(25, 0, 0),
				B.THIGH_L: Vector3(-25, 6, 0),
				B.SHIN_L: Vector3(-65, 0, 0),
				B.FOOT_L: Vector3(75, 0, 0),
				B.CLAVICLE_R: Vector3(0, 0, -5),
				B.UPPERARM_R: Vector3(14, 0, 10),
				B.FOREARM_R: Vector3(68, -34, 0),
				B.HAND_R: Vector3(0, -12, 0),
				B.CLAVICLE_L: Vector3(0, 0, 7),
				B.UPPERARM_L: Vector3(30, 0, -20),
				B.FOREARM_L: Vector3(72, 42, 0),
				B.HAND_L: Vector3(0, 16, 0),
			}
		SoldierProfile.Stance.HIPFIRE:
			return {
				"root_offset": Vector3(0.0, -0.06, 0.0),
				B.SPINE: Vector3(-5, -6, 0),
				B.CHEST: Vector3(-4, -14, 0),
				B.HEAD: Vector3(2, 14, 0),
				# Wide braced base to absorb recoil.
				B.THIGH_R: Vector3(14, 0, -13),
				B.SHIN_R: Vector3(-18, 0, 0),
				B.FOOT_R: Vector3(6, 0, 0),
				B.THIGH_L: Vector3(-16, 0, 12),
				B.SHIN_L: Vector3(-14, 0, 0),
				B.FOOT_L: Vector3(12, 0, 0),
				# Weapon carried low at the hip, support hand on the front handle.
				B.CLAVICLE_R: Vector3(0, 0, -8),
				B.UPPERARM_R: Vector3(6, 0, 14),
				B.FOREARM_R: Vector3(58, -42, 0),
				B.HAND_R: Vector3(0, -14, 0),
				B.CLAVICLE_L: Vector3(0, 0, 10),
				B.UPPERARM_L: Vector3(34, 0, -24),
				B.FOREARM_L: Vector3(66, 46, 0),
				B.HAND_L: Vector3(0, 18, 0),
			}
		_:
			return {
				"root_offset": Vector3.ZERO,
				B.SPINE: Vector3(-4, 0, 0),
				B.CHEST: Vector3(-3, 9, 0),
				B.NECK: Vector3(2, 0, 0),
				B.HEAD: Vector3(3, -7, 0),
				# Mid-stride: right leg forward, left trailing.
				B.THIGH_R: Vector3(20, 0, -3),
				B.SHIN_R: Vector3(-26, 0, 0),
				B.FOOT_R: Vector3(8, 0, 0),
				B.THIGH_L: Vector3(-15, 0, 3),
				B.SHIN_L: Vector3(-13, 0, 0),
				B.FOOT_L: Vector3(19, 0, 0),
				# Weapon held across the chest. Almost all of the bend lives in the
				# forearms: swinging the upper arms forward instead points both
				# limbs at the camera, where they foreshorten into blocks and drag
				# the pauldrons off the shoulders with them.
				B.CLAVICLE_R: Vector3(0, 0, -5),
				B.UPPERARM_R: Vector3(18, 0, 12),
				B.FOREARM_R: Vector3(72, -38, 0),
				B.HAND_R: Vector3(0, -14, 0),
				B.CLAVICLE_L: Vector3(0, 0, 6),
				B.UPPERARM_L: Vector3(26, 0, -18),
				B.FOREARM_L: Vector3(78, 40, 0),
				B.HAND_L: Vector3(0, 16, 0),
			}


func _apply_stance(stance: SoldierProfile.Stance) -> void:
	_stance_pose.clear()
	var table := stance_table(stance)
	for key in table:
		if key is String:
			continue
		var q := Quaternion.from_euler(Vector3(
			deg_to_rad(table[key].x), deg_to_rad(table[key].y), deg_to_rad(table[key].z)))
		_stance_pose[key] = q
		skeleton.set_bone_pose_rotation(key, q)

	var offset: Vector3 = table.get("root_offset", Vector3.ZERO)
	if offset != Vector3.ZERO:
		skeleton.set_bone_pose_position(B.HIPS,
			skeleton.get_bone_rest(B.HIPS).origin + offset)


# ── Quality and runtime ───────────────────────────────────────────────────────

func set_quality(level: Quality) -> void:
	quality = level
	if _flare:
		_flare.visible = level != Quality.LOW
	if _ocular_light:
		_ocular_light.visible = level != Quality.LOW
	if body:
		body.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if level == Quality.LOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	# Force the per-frame detail check to re-apply on the next tick.
	_last_detail = -1


func set_ocular_charge(value: float) -> void:
	_mat_ocular.set_shader_parameter("charge", clampf(value, 0.0, 1.0))


## Flashes the skull behind the visor. Drive on damage or on firing.
func set_visor_pulse(value: float) -> void:
	_mat_visor.set_shader_parameter("pulse", clampf(value, 0.0, 1.0))


func fire_flash(strength: float = 1.0) -> void:
	_muzzle_flash = clampf(strength, 0.0, 1.0)
	set_visor_pulse(_muzzle_flash * 0.6)


func _process(delta: float) -> void:
	_idle_phase += delta

	if skeleton:
		_apply_idle()

	if _muzzle_flash > 0.0:
		_muzzle_flash = maxf(0.0, _muzzle_flash - delta * 7.0)
		if _muzzle_light:
			_muzzle_light.light_energy = _muzzle_flash * 6.0
		set_visor_pulse(_muzzle_flash * 0.6)

	_update_detail()


## Breathing and a slow head scan, layered on top of the stance rather than
## replacing it. Cheap enough to leave running, and a soldier that is perfectly
## still reads as a statue no matter how good the shading is.
func _apply_idle() -> void:
	var breath := sin(_idle_phase * 1.1) * 0.012
	var scan := sin(_idle_phase * 0.37) * 0.09

	_offset_pose(B.SPINE, Vector3(breath, 0.0, 0.0))
	_offset_pose(B.CHEST, Vector3(breath * 1.6, 0.0, 0.0))
	_offset_pose(B.HEAD, Vector3(sin(_idle_phase * 0.8) * 0.02, scan, 0.0))
	_offset_pose(B.UPPERARM_L, Vector3(breath * 0.8, 0.0, 0.0))
	_offset_pose(B.UPPERARM_R, Vector3(breath * 0.8, 0.0, 0.0))


func _offset_pose(bone: int, radians: Vector3) -> void:
	var base: Quaternion = _stance_pose.get(bone, Quaternion.IDENTITY)
	skeleton.set_bone_pose_rotation(bone, base * Quaternion.from_euler(radians))


## Distance-driven feature culling. The three thresholds are staged so the most
## expensive thing goes first: screen-space work in the plumes, then the plumes
## themselves, then the flare card.
func _update_detail() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist := global_position.distance_to(cam.global_position)

	var tier := 0
	if dist > flame_distance:
		tier = 3
	elif dist > flare_distance:
		tier = 2
	elif dist > flame_detail_distance:
		tier = 1
	if tier == _last_detail:
		return
	_last_detail = tier

	var want_screen_fx := tier == 0 and quality == Quality.HIGH
	_mat_flame.set_shader_parameter("use_refraction", want_screen_fx)
	_mat_flame.set_shader_parameter("use_soft_edge",
		_has_depth_fx and tier <= 1 and quality != Quality.LOW)

	for plume in _plumes:
		plume.visible = tier < 3
	if _flare:
		_flare.visible = tier < 2 and quality != Quality.LOW
