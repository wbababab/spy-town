class_name SoldierMaterials extends RefCounted

## Builds and caches the shader materials a soldier needs.
##
## A character uses four materials and therefore four draw calls: body, lenses,
## visor, plumes. That is the entire per-character cost, and it does not grow
## with the number of pouches, plates or lamps on the model, because everything
## sharing a material is welded into one surface by LowPoly.commit_surface().
##
## The flame noise texture is generated once with FastNoiseLite and shared by
## every plume in the level, so the repository carries no binary image assets.

const SH_VANTABLACK := preload("res://shaders/vantablack.gdshader")
const SH_SILHOUETTE := preload("res://shaders/silhouette_edge.gdshader")
const SH_OCULAR := preload("res://shaders/ocular.gdshader")
const SH_FLARE := preload("res://shaders/ocular_flare.gdshader")
const SH_VISOR := preload("res://shaders/skull_visor.gdshader")
const SH_FLAME := preload("res://shaders/black_flame.gdshader")

static var _noise_tex: NoiseTexture2D = null


## Shared tiling noise for every black-flame plume. Generated procedurally so
## there is no image file to import, and small on purpose - the plumes are
## heavily masked by their taper, so 128px is more than the silhouette can show.
static func flame_noise() -> NoiseTexture2D:
	if _noise_tex:
		return _noise_tex
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.020
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55

	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 128
	_noise_tex.height = 128
	# Seamless matters: the shader scrolls this forever in Y.
	_noise_tex.seamless = true
	_noise_tex.generate_mipmaps = false
	_noise_tex.noise = noise
	return _noise_tex


## Vantablack body/armour, with the constant-width silhouette pass chained on.
static func body(profile: SoldierProfile) -> ShaderMaterial:
	var edge := ShaderMaterial.new()
	edge.shader = SH_SILHOUETTE
	# Deliberately lighter than the body. A dark outline on a black character in
	# a black corridor separates nothing.
	edge.set_shader_parameter("edge_color", Color(0.34, 0.38, 0.48))
	edge.set_shader_parameter("edge_alpha", 0.55)
	edge.set_shader_parameter("edge_width", 0.0012)

	var mat := ShaderMaterial.new()
	mat.shader = SH_VANTABLACK
	mat.next_pass = edge
	# Bulkier characters get marginally more form light, otherwise the heavy's
	# mass is completely lost and he reads no larger than the marksman.
	var form: float = clamp(0.07 + (profile.bulk - 1.0) * 0.06, 0.04, 0.20)
	mat.set_shader_parameter("form_light", form)
	mat.set_shader_parameter("absorption", 0.94)
	return mat


## Weapon steel. Same shader as the body, dialled toward plate: guns are the one
## thing on these characters that should catch a hard highlight, because that is
## what tells the player where the muzzle is pointing.
static func weapon() -> ShaderMaterial:
	var edge := ShaderMaterial.new()
	edge.shader = SH_SILHOUETTE
	edge.set_shader_parameter("edge_color", Color(0.30, 0.34, 0.43))
	edge.set_shader_parameter("edge_alpha", 0.45)
	edge.set_shader_parameter("edge_width", 0.0009)

	var mat := ShaderMaterial.new()
	mat.shader = SH_VANTABLACK
	mat.next_pass = edge
	mat.set_shader_parameter("absorption", 0.88)
	mat.set_shader_parameter("form_light", 0.16)
	mat.set_shader_parameter("plate_glint", 0.9)
	mat.set_shader_parameter("plate_roughness", 0.28)
	mat.set_shader_parameter("kicker_strength", 3.1)
	return mat


static func ocular(profile: SoldierProfile) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_OCULAR
	mat.set_shader_parameter("core_color", profile.ocular_color)
	mat.set_shader_parameter("halo_color", profile.ocular_halo)
	mat.set_shader_parameter("energy", profile.ocular_energy)
	return mat


static func flare(profile: SoldierProfile) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_FLARE
	mat.set_shader_parameter("flare_color", profile.ocular_halo)
	mat.set_shader_parameter("energy", clampf(profile.ocular_energy * 0.11, 0.15, 1.2))
	return mat


static func visor(profile: SoldierProfile) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_VISOR
	mat.set_shader_parameter("skull_color", profile.ocular_color)
	mat.set_shader_parameter("skull_energy", clampf(profile.ocular_energy * 0.19, 0.7, 2.4))
	return mat


static func flame(profile: SoldierProfile) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SH_FLAME
	mat.set_shader_parameter("noise_tex", flame_noise())
	mat.set_shader_parameter("opacity", profile.flame_opacity)
	return mat
