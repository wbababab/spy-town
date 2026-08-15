// Constant-width silhouette pass for near-black characters.
//
// Used as next_pass on vantablack.gdshader. The stock inverted-hull outline
// expands in view space, so its on-screen width shrinks with distance - which
// is the wrong behaviour here, because distance is exactly when a vantablack
// figure dissolves into the background. This expands in clip space instead, so
// the edge holds a fixed pixel width at any range, then fades out past a set
// distance so a crowd of soldiers does not turn into a field of outlines.
//
// Note the colour default is *light*, not dark. A dark outline on a dark
// character against a dark level adds nothing; a pale one is what separates the
// silhouette from the fog.

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled,
	ambient_light_disabled;

uniform vec3 edge_color : source_color = vec3(0.34, 0.38, 0.48);
uniform float edge_alpha : hint_range(0.0, 1.0) = 0.55;
// Width in fraction of viewport height, so it is resolution independent.
uniform float edge_width : hint_range(0.0, 0.02) = 0.0012;
// Clamp so the edge cannot balloon when the camera is right on top of a model.
uniform float max_world_width : hint_range(0.0, 0.2) = 0.02;
uniform float fade_begin : hint_range(0.0, 200.0) = 28.0;
uniform float fade_end : hint_range(0.0, 200.0) = 55.0;

varying float v_fade;

void vertex() {
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);

	float dist = length(view_pos.xyz);
	// Expanding by a width proportional to depth keeps the projected size fixed.
	float world_width = min(edge_width * dist, max_world_width);
	view_pos.xyz += view_normal * world_width;

	POSITION = PROJECTION_MATRIX * view_pos;
	v_fade = 1.0 - smoothstep(fade_begin, fade_end, dist);
}

void fragment() {
	ALBEDO = edge_color;
	ALPHA = edge_alpha * v_fade;
}
