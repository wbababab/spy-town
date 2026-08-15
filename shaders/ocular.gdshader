// Emissive ocular lens - the NVG lamp cluster, the marksman's single eye, and
// the small indicator lights on the weapons all run this one material.
//
// The bloom does not come from this shader. It comes from writing colour above
// the WorldEnvironment's glow HDR threshold and letting the existing glow pass
// spread it, which costs nothing extra per lamp. That is why `energy` sits well
// above 1.0 - at energy 1.0 these read as flat white circles with no halo.
//
// Opaque and unshaded on purpose: no blending, no sorting, no lighting. A lamp
// is one of the cheapest things in the frame.

shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, ambient_light_disabled,
	specular_disabled;

group_uniforms Lens;
uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
// Real lamps go cooler off-axis; this is what stops the lens reading as a decal.
uniform vec3 halo_color : source_color = vec3(0.62, 0.76, 1.0);
uniform vec3 bezel_color : source_color = vec3(0.014, 0.014, 0.018);
uniform float energy : hint_range(0.0, 24.0) = 6.5;
uniform float core_radius : hint_range(0.0, 0.5) = 0.16;
uniform float lens_radius : hint_range(0.0, 0.5) = 0.40;
uniform float falloff : hint_range(0.5, 6.0) = 2.2;

group_uniforms Behaviour;
// Lamps dim off-axis because you are seeing less of the emitter's face.
uniform float grazing_dim : hint_range(0.0, 1.0) = 0.55;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.06;
uniform float flicker_speed : hint_range(0.0, 40.0) = 11.0;
// Horizontal sensor sweep. Subtle, but it makes the lens read as active optics.
uniform float scan_amount : hint_range(0.0, 1.0) = 0.12;
uniform float scan_speed : hint_range(0.0, 4.0) = 0.7;
// 0 = powered down, 1 = full. Drive this to spin an optic up before a shot.
uniform float charge : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);

	// Hot centre, cooling toward the lens rim, then a dead bezel.
	float core = 1.0 - smoothstep(0.0, core_radius, r);
	float lens = 1.0 - smoothstep(core_radius, lens_radius, r);
	lens = pow(max(lens, 0.0), falloff);

	float flicker = 1.0 + sin(TIME * flicker_speed) * sin(TIME * flicker_speed * 0.37)
		* flicker_amount;
	float scan = 1.0 - scan_amount
		* smoothstep(0.85, 1.0, sin((UV.y - TIME * scan_speed) * 18.0));

	float off_axis = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float facing = mix(1.0 - grazing_dim, 1.0, off_axis);

	vec3 emit = mix(halo_color, core_color, core);
	float gain = (core * 0.85 + lens) * energy * flicker * scan * facing * charge;

	ALBEDO = mix(bezel_color, emit * gain, clamp(core + lens, 0.0, 1.0));
}
