extends Node3D

## Turntable preview for the three soldier archetypes.
##
## The lighting rig here is not decoration - it is the point. A vantablack
## character lit conventionally, with a bright key from behind the camera, is a
## silhouette-shaped hole: the key light has nothing to reflect off. What makes
## these characters read is light coming from *behind* them, catching the
## grazing edge, which is exactly how the concept art is lit. So the rig below
## is deliberately backwards from a normal three-point setup: strong cool
## backlight, hard rim kickers at the rear quarters, and a fill from the front
## so weak it only just keeps the chest from disappearing.
##
## Run it directly:
##   godot --path . scenes/dev/CharacterForge.tscn
##
## Controls: A/D orbit, W/S zoom, R toggle auto-orbit, 1/2/3 quality preset,
## Space muzzle flash, Tab cycle the framed character.
##
## Pass --capture <file.png> to render a few frames, write a screenshot and
## quit, which is how this scene doubles as a visual regression check.

const PROFILES := [
	preload("res://resources/soldiers/wraith_marksman.tres"),
	preload("res://resources/soldiers/spectre_operator.tres"),
	preload("res://resources/soldiers/reaper_heavy.tres"),
]

var _rigs: Array[SoldierRig] = []
var _camera: Camera3D
var _label: Label
var _orbit: float = 0.35
var _radius: float = 5.4
var _auto_orbit: bool = true
var _focus: int = -1


func _ready() -> void:
	_build_environment()
	_build_lighting()
	_build_ground()
	_build_squad()
	_build_camera()
	_build_hud()

	var capture := _capture_path()
	if capture != "":
		_focus = _cmdline_int("--focus", -1)
		var q := _cmdline_int("--quality", -1)
		if q >= 0:
			_set_quality(q as SoldierRig.Quality)
		_run_capture(capture)


# ── Scene construction ────────────────────────────────────────────────────────

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Not pure black. A black-flame plume works by absorbing what is behind it,
	# so a truly black backdrop leaves it nothing to subtract from.
	env.background_color = Color(0.062, 0.068, 0.086)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.24, 0.34)
	# Almost no ambient. Ambient light is flat by definition, and flat light on
	# an absorbing surface produces a uniform grey card.
	env.ambient_light_energy = 0.10

	env.fog_enabled = true
	env.fog_light_color = Color(0.28, 0.32, 0.40)
	env.fog_light_energy = 0.55
	env.fog_density = 0.014
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0

	# Glow is what turns the oculars from white dots into lamps. The threshold
	# sits just under 1.0 so only genuinely HDR pixels - the lenses, the flare,
	# the skull - bloom, and the fog does not.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


func _build_lighting() -> void:
	# Cool backlight, high and behind the squad. This is the key.
	var back := DirectionalLight3D.new()
	back.name = "Backlight"
	back.light_color = Color(0.74, 0.83, 1.0)
	back.light_energy = 0.60
	back.shadow_enabled = true
	back.rotation_degrees = Vector3(-28, 172, 0)
	add_child(back)

	# Rear-quarter kickers. These are what draw the plate edges.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var kick := OmniLight3D.new()
		kick.name = "Kicker%d" % i
		kick.light_color = Color(0.62, 0.74, 1.0)
		# Kickers are read through the shader's grazing term, which is already a
		# multiplier - push these much past 1.5 and the "unlit" side of the
		# absorption blows straight through to white.
		kick.light_energy = 0.90
		kick.omni_range = 7.0
		kick.shadow_enabled = false
		kick.position = Vector3(side * 2.6, 1.9, 2.9)
		add_child(kick)

	# Barely-there frontal fill. Raise this and the characters stop reading as
	# vantablack almost immediately - it is the single most sensitive value here.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.55, 0.60, 0.74)
	fill.light_energy = 0.10
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18, -14, 0)
	add_child(fill)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.030, 0.032, 0.040)
	mat.roughness = 0.85
	mat.metallic = 0.0

	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = mat
	add_child(mi)


func _build_squad() -> void:
	var spacing := 1.5
	for i in PROFILES.size():
		var rig := SoldierRig.new()
		rig.name = "Soldier_%s" % PROFILES[i].profile_id
		rig.profile = PROFILES[i]
		rig.position = Vector3((float(i) - 1.0) * spacing, 0.0, 0.0)
		# Splay the flanks inward so the group reads as a squad rather than a
		# line-up, which is also how the concept art stages them.
		rig.rotation_degrees = Vector3(0, (1.0 - float(i)) * 18.0, 0)
		add_child(rig)
		_rigs.append(rig)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 48.0
	_camera.current = true
	add_child(_camera)
	_update_camera()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.92))
	_label.add_theme_font_size_override("font_size", 14)
	layer.add_child(_label)
	_refresh_hud()


func _refresh_hud() -> void:
	if _label == null:
		return
	var lines := ["SOLDIER FORGE  -  A/D orbit  W/S zoom  R auto-orbit  "
		+ "1/2/3 quality  Space fire  Tab focus", ""]
	var total := 0
	for rig in _rigs:
		var tris := rig.triangle_count()
		total += tris
		lines.append("%-10s %5d tris   %s" % [
			rig.profile.display_name, tris, rig.profile.callsign])
	lines.append("")
	lines.append("squad total %d tris   quality %s" % [
		total, SoldierRig.Quality.keys()[_rigs[0].quality] if _rigs else "-"])
	_label.text = "\n".join(lines)


# ── Runtime ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _auto_orbit:
		_orbit += delta * 0.22
	if Input.is_key_pressed(KEY_A):
		_orbit -= delta * 1.1
	if Input.is_key_pressed(KEY_D):
		_orbit += delta * 1.1
	if Input.is_key_pressed(KEY_W):
		_radius = maxf(1.6, _radius - delta * 3.0)
	if Input.is_key_pressed(KEY_S):
		_radius = minf(24.0, _radius + delta * 3.0)
	_update_camera()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			_auto_orbit = not _auto_orbit
		KEY_1:
			_set_quality(SoldierRig.Quality.LOW)
		KEY_2:
			_set_quality(SoldierRig.Quality.MEDIUM)
		KEY_3:
			_set_quality(SoldierRig.Quality.HIGH)
		KEY_SPACE:
			for rig in _rigs:
				rig.fire_flash(1.0)
		KEY_TAB:
			_focus = -1 if _focus >= _rigs.size() - 1 else _focus + 1
		KEY_ESCAPE:
			get_tree().quit()


func _set_quality(level: SoldierRig.Quality) -> void:
	for rig in _rigs:
		rig.set_quality(level)
	_refresh_hud()


func _update_camera() -> void:
	if _camera == null:
		return
	var target := Vector3(0.0, 1.05, 0.0)
	var radius := _radius
	if _focus >= 0 and _focus < _rigs.size():
		target = _rigs[_focus].position + Vector3(0.0, 0.95, 0.0)
		radius = _radius * 0.55
	_camera.position = target + Vector3(
		sin(_orbit) * radius, 0.35, cos(_orbit) * radius)
	_camera.look_at(target, Vector3.UP)


# ── Screenshot capture ────────────────────────────────────────────────────────

func _capture_path() -> String:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var idx := args.find("--capture")
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1]
	return ""


func _cmdline_int(flag: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	var idx := args.find(flag)
	if idx >= 0 and idx + 1 < args.size():
		return int(args[idx + 1])
	return fallback


func _run_capture(path: String) -> void:
	_auto_orbit = false
	_orbit = PI + 0.40
	_update_camera()
	# The noise texture generates on a worker thread and the plumes read it, so
	# give the renderer a handful of frames before sampling the buffer.
	for i in 12:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("FORGE_CAPTURE=%s err=%d size=%s" % [path, err, img.get_size()])
	for rig in _rigs:
		print("FORGE_TRIS %s=%d" % [rig.profile.display_name, rig.triangle_count()])
	get_tree().quit()
