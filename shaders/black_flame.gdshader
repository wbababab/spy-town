// Black flame shader.
//
// Fire is normally additive, and you cannot add darkness. What the concept art
// actually shows is not burning light but burning *soot*: a plume that absorbs
// the fog behind it and warps it with heat. So this renders as an absorber, not
// an emitter:
//
//   * background is sampled, darkened by the plume density, and written back,
//   * the sample is displaced by the flame's own noise gradient, giving the heat
//     shimmer that makes a black plume readable against a black character,
//   * only the thin dissolving edge lifts toward grey, where real soot catches
//     ambient light.
//
// The two screen-space fetches are the only expensive part, so both are behind
// uniform-coherent switches that SoldierRig turns off at distance or on the low
// quality preset. With both off this is a scrolling-noise alpha billboard and
// costs about as much as a smoke puff.
//
// Quad convention: UV.y = 0 at the plume base, 1 at the tip. LowPoly.flame_quad
// builds them that way.

shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never,
	shadows_disabled, ambient_light_disabled;

group_uniforms Shape;
uniform sampler2D noise_tex : hint_default_black, repeat_enable, filter_linear;
uniform float rise_speed : hint_range(0.0, 4.0) = 0.85;
uniform float noise_scale : hint_range(0.1, 8.0) = 1.7;
uniform float turbulence : hint_range(0.0, 2.0) = 0.58;
// How aggressively the plume eats itself toward the tip.
uniform float dissolve : hint_range(0.0, 3.0) = 0.55;
uniform float sway : hint_range(0.0, 0.5) = 0.11;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.6;
uniform float edge_softness : hint_range(0.01, 0.6) = 0.22;

group_uniforms Colour;
uniform vec3 core_color : source_color = vec3(0.008, 0.008, 0.010);
// Soot at the dissolving edge picks up a little of the ambient haze.
uniform vec3 ash_color : source_color = vec3(0.38, 0.40, 0.47);
// Width of the luminous soot rim. This is the only part of a black flame that
// is self-visible: against a lit backdrop the plume reads by absorption, but
// over a night sky the absorber has nothing to subtract, and without a visible
// ash edge the whole effect disappears.
uniform float ash_width : hint_range(0.0, 1.0) = 0.46;
uniform float absorb : hint_range(0.0, 1.0) = 0.88;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float global_fade : hint_range(0.0, 1.0) = 1.0;

group_uniforms Quality;
uniform bool use_refraction = true;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.018;
// Forward+ / Mobile only. The depth-buffer convention differs on the
// Compatibility renderer, where this recipe reads a near-zero scene depth and
// erases the plume entirely - so SoldierRig enables it only after checking
// RenderingServer.get_current_rendering_method(). Default off so a plume never
// silently vanishes on a backend that cannot support it.
uniform bool use_soft_edge = false;
uniform float soft_distance : hint_range(0.01, 2.0) = 0.35;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

// Per-instance so every plume on every soldier can share one material and still
// burn out of step. Without this, plumes driven by the same TIME are frame-exact
// copies of each other and the effect reads as wallpaper.
instance uniform float phase = 0.0;

void vertex() {
	// Y-locked billboard: the plume always faces the camera but stays upright,
	// so it never lies down flat when viewed from above.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	// Billboarding discards the model basis, so re-apply its scale by hand.
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

// Two counter-scrolling octaves. Cheaper than real fbm and, once the taper mask
// is applied, indistinguishable at the sizes these plumes are drawn.
float plume_noise(vec2 uv, float t) {
	float a = texture(noise_tex, uv * noise_scale + vec2(0.0, -t * rise_speed)).r;
	float b = texture(noise_tex, uv * noise_scale * 2.3
		+ vec2(0.13, -t * rise_speed * 1.7)).r;
	return a * 0.65 + b * 0.35;
}

void fragment() {
	float t = TIME + phase;
	float h = clamp(UV.y, 0.0, 1.0);

	// Lateral drift grows with height so the plume trails instead of shearing.
	float drift = sin(t * sway_speed + h * 5.5) * sway * h * h;
	vec2 uv = vec2(UV.x + drift, UV.y);

	// Width envelope: pinched at the emitter, widest just above it, tapering to a
	// point. The fractional power keeps the plume broad through the middle
	// instead of collapsing into a spike as soon as it leaves the shoulder.
	float width = (0.18 + 0.82 * smoothstep(0.0, 0.22, h)) * pow(1.0 - h, 0.65);
	float across = abs(uv.x - 0.5) * 2.0 / max(width, 0.001);

	float n = plume_noise(vec2(uv.x, uv.y * 0.55), t);
	// Density falls off sideways, is chewed up by noise, and burns away upward.
	float density = (1.0 - across) + (n - 0.5) * 2.0 * turbulence - h * dissolve;

	float alpha = smoothstep(0.0, edge_softness, density);
	if (use_soft_edge) {
		float scene_z = texture(depth_tex, SCREEN_UV).r;
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_z, 1.0);
		view.xyz /= view.w;
		// Fade where the billboard intersects geometry, so plumes growing out of
		// the shoulders do not show a hard cut line across the armour.
		alpha *= clamp((-view.z - (-VERTEX.z)) / soft_distance, 0.0, 1.0);
	}
	alpha *= opacity * global_fade;

	// The outermost sliver of the plume is thin enough to catch haze.
	float ash = 1.0 - smoothstep(0.0, ash_width, density);
	vec3 flame = mix(core_color, ash_color, ash * ash);

	if (use_refraction) {
		// Displace along the noise gradient: the plume bends what is behind it.
		vec2 grad = vec2(n - 0.5, plume_noise(vec2(uv.x + 0.04, uv.y * 0.55), t) - 0.5);
		vec2 warped = SCREEN_UV + grad * refraction_strength * alpha;
		vec3 bg = textureLod(screen_tex, clamp(warped, vec2(0.001), vec2(0.999)), 0.0).rgb;
		ALBEDO = mix(bg * (1.0 - absorb), flame, ash * ash);
	} else {
		ALBEDO = flame;
	}
	ALPHA = clamp(alpha, 0.0, 1.0);
}
