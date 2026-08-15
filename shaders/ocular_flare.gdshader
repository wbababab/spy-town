// Additive flare card sitting behind each ocular lens.
//
// Post-process glow spreads a lamp evenly in all directions. Real optics behind
// a faceplate throw an anamorphic streak, and that streak is most of what sells
// "lit lamp" over "white dot". This is one camera-facing quad per lamp with no
// texture fetch, so it is affordable even on the low preset - but it is still
// the first thing SoldierRig drops at distance, since a streak that is three
// pixels wide is not worth a transparent draw.

shader_type spatial;
// Depth *testing* stays on: a flare that draws through walls is a wallhack,
// not a lighting effect. Depth writing stays off so it never occludes.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never,
	shadows_disabled, ambient_light_disabled;

uniform vec3 flare_color : source_color = vec3(0.70, 0.82, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.15;
uniform float bloom_falloff : hint_range(0.5, 8.0) = 3.0;
// Horizontal stretch of the streak, in UV units.
uniform float streak_length : hint_range(0.0, 0.5) = 0.34;
uniform float streak_thickness : hint_range(0.001, 0.2) = 0.022;
uniform float streak_energy : hint_range(0.0, 4.0) = 0.85;
uniform float global_fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Full billboard - a flare has no up vector of its own.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV - vec2(0.5);

	float bloom = pow(clamp(1.0 - length(p) * 2.0, 0.0, 1.0), bloom_falloff);
	// Streak: tight in Y, long in X, faded along its length.
	float streak = clamp(1.0 - abs(p.y) / streak_thickness, 0.0, 1.0)
		* clamp(1.0 - abs(p.x) / streak_length, 0.0, 1.0);

	ALBEDO = flare_color * (bloom + streak * streak_energy) * energy * global_fade;
	ALPHA = 1.0;
}
