// Vantablack body/armour shader.
//
// The physical reference absorbs ~99.965% of incident light. Rendered literally
// that gives a flat hole in the frame: no form, no readable silhouette against a
// dark level, and players cannot tell where a character is facing. This shader
// keeps the *look* of total absorption while putting back the three cues that
// survive on a real ultra-black surface:
//
//   1. grazing-angle scatter  - a very tight Fresnel that only opens up within a
//      few degrees of the silhouette edge,
//   2. backlight kicker       - per-light rim that peaks when the light sits
//      behind the subject, which is why the concept art lights these figures
//      from behind rather than from the front,
//   3. material breaks        - hard armour edges catch a sliver where cloth
//      does not, driven by vertex colour so it costs no texture fetch.
//
// Vertex colour channels (written by LowPoly.gd):
//   COLOR.r = plate mask - hard armour, tight bright glint
//   COLOR.g = cloth mask - cloak/ghillie, broad dim sheen
//   COLOR.b = wear mask  - dust settled in crevices, tiny albedo lift

shader_type spatial;
render_mode cull_back, specular_schlick_ggx, diffuse_lambert, ambient_light_disabled;

group_uniforms Absorption;
// 1.0 = true vantablack (silhouette only). Dial down for gameplay readability.
uniform float absorption : hint_range(0.0, 1.0) = 0.94;
uniform vec3 base_color : source_color = vec3(0.020, 0.021, 0.026);
// Cloth reads a touch warmer and less absorbent than armour plate.
uniform vec3 cloth_color : source_color = vec3(0.035, 0.033, 0.038);
uniform vec3 dust_color : source_color = vec3(0.16, 0.16, 0.19);
uniform float dust_amount : hint_range(0.0, 1.0) = 0.25;

group_uniforms Edge;
// Ambient scatter at the silhouette. This is light-independent on purpose: it
// stands in for environment bounce, so the figure never fully vanishes.
uniform vec3 edge_color : source_color = vec3(0.42, 0.46, 0.58);
uniform float edge_strength : hint_range(0.0, 4.0) = 0.40;
// High power keeps the band hugging the silhouette instead of washing the form.
uniform float edge_power : hint_range(1.0, 16.0) = 8.0;

group_uniforms Kicker;
// Per-light rim. Peaks when the light is behind the subject.
uniform vec3 kicker_color : source_color = vec3(0.78, 0.84, 1.0);
uniform float kicker_strength : hint_range(0.0, 8.0) = 1.05;
uniform float kicker_power : hint_range(1.0, 16.0) = 6.0;
// How much direct light survives absorption to describe volume.
uniform float form_light : hint_range(0.0, 1.0) = 0.10;
uniform float form_tighten : hint_range(1.0, 8.0) = 3.0;

group_uniforms Plate;
uniform float plate_glint : hint_range(0.0, 2.0) = 0.55;
uniform float plate_roughness : hint_range(0.0, 1.0) = 0.34;
uniform float cloth_roughness : hint_range(0.0, 1.0) = 0.92;

varying float v_plate;
varying float v_cloth;
varying float v_wear;

void vertex() {
	v_plate = COLOR.r;
	v_cloth = COLOR.g;
	v_wear = COLOR.b;
}

void fragment() {
	vec3 albedo = mix(base_color, cloth_color, v_cloth);
	albedo += dust_color * (v_wear * dust_amount);
	// Absorption crushes everything toward zero; 0 leaves the authored colour.
	ALBEDO = albedo * (1.0 - absorption);

	ROUGHNESS = mix(plate_roughness, cloth_roughness, v_cloth);
	METALLIC = 0.0;
	// Nanotube forests have no coherent specular lobe; only the plate edges,
	// which are ordinary machined material, get one.
	SPECULAR = 0.5 * plate_glint * v_plate;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);
	// Plate edges scatter more at grazing than cloth does.
	float edge_gain = mix(0.40, 1.0, v_plate);
	EMISSION = edge_color * (fresnel * edge_strength * edge_gain);
}

void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);

	// Volume hint: compressed so mid-tones stay crushed and only near-normal
	// incidence lifts at all. Without this the figure has no readable mass.
	float form = pow(n_dot_l, form_tighten) * form_light;
	DIFFUSE_LIGHT += ALBEDO * form * ATTENUATION * LIGHT_COLOR;

	// Backlight kicker. dot(LIGHT, VIEW) goes negative as the light moves behind
	// the subject relative to the camera, which is exactly when a real matte
	// black object shows its edge.
	float behind = clamp(-dot(LIGHT, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), kicker_power);
	// Cloth scatters far more diffusely than a machined edge, so it gets a
	// fraction of the kick; without this the cloak tatters read as chrome.
	float kick = rim * behind * kicker_strength * mix(0.40, 1.35, v_plate);
	SPECULAR_LIGHT += kicker_color * kick * ATTENUATION * LIGHT_COLOR;
}
