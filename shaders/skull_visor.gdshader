// Skull-behind-glass visor.
//
// Two problems, solved separately.
//
// DEPTH. The skull has to sit *inside* the helmet, not be painted on the front
// of it. Modelling an actual skull behind an actual glass shell means a second
// transparent surface, sorting between them, and a few hundred wasted triangles
// on something the player sees through a dark pane. Instead the interior is
// rendered by parallax offset: the visor's own UV is displaced along the
// tangent-space view vector, so as the camera orbits, the skull slides against
// the frame exactly as real geometry at that depth would. One surface, no
// sorting, and the illusion holds until the camera is nearly edge-on - at which
// point the Fresnel term below has already turned the glass opaque anyway.
//
// THE SKULL ITSELF. Drawn as a signed distance field rather than a texture.
// That means no atlas, no import step, no mip shimmer on a small screen
// element, and it stays crisp when a player walks right up to it. It also means
// the whole face is uniform-driven: socket tilt, jaw width and tooth count are
// parameters, so the three archetypes can share one material and still read as
// different skulls.
//
// The glass stays lit rather than unshaded, so it catches the same rim lights as
// the armour. Unshaded glass is the classic tell that a visor is a decal.

shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx,
	diffuse_lambert;

group_uniforms Framing;
// Maps the visor mesh's UV island onto the skull's 0..1 working square.
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform float skull_size : hint_range(0.2, 3.0) = 1.0;
// Apparent distance from the glass to the skull, in UV units.
uniform float cavity_depth : hint_range(0.0, 0.5) = 0.085;
// Tangent handedness varies with how the mesh was unwrapped; flip if the skull
// slides the wrong way vertically when the camera moves.
uniform float parallax_flip_y : hint_range(-1.0, 1.0) = 1.0;

group_uniforms Skull;
uniform vec3 skull_color : source_color = vec3(0.94, 0.96, 1.0);
uniform float skull_energy : hint_range(0.0, 12.0) = 1.6;
uniform float skull_visibility : hint_range(0.0, 1.0) = 1.0;
uniform float socket_tilt : hint_range(-0.6, 0.6) = 0.28;
uniform float jaw_width : hint_range(0.5, 1.5) = 1.0;
uniform float teeth_count : hint_range(3.0, 12.0) = 9.0;
// Chromatic split from viewing the interior through thick glass.
uniform bool use_dispersion = true;
uniform float dispersion : hint_range(0.0, 0.3) = 0.05;
// Drive to 1.0 for a damage flash or a firing pulse.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

group_uniforms Glass;
uniform vec3 glass_color : source_color = vec3(0.015, 0.016, 0.021);
uniform vec3 glass_rim_color : source_color = vec3(0.36, 0.44, 0.60);
uniform float glass_rim_energy : hint_range(0.0, 4.0) = 0.9;
uniform float glass_power : hint_range(1.0, 8.0) = 3.2;
// How completely a grazing view hides the interior.
uniform float glass_occlude : hint_range(0.0, 1.0) = 0.92;
uniform float glass_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.10;
uniform float sweep_speed : hint_range(0.0, 1.0) = 0.11;
uniform float sweep_width : hint_range(0.01, 0.6) = 0.16;
uniform float sweep_energy : hint_range(0.0, 3.0) = 0.5;

float sd_ellipse(vec2 p, vec2 r) {
	// Not an exact distance, but the gradient is smooth and every consumer below
	// antialiases with fwidth(), which rescales itself to whatever this returns.
	return (length(p / r) - 1.0) * min(r.x, r.y);
}

float sd_round_box(vec2 p, vec2 b, float rad) {
	vec2 d = abs(p) - b + vec2(rad);
	return min(max(d.x, d.y), 0.0) + length(max(d, vec2(0.0))) - rad;
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float mask_lt(float d) {
	// 1 where d < 0, antialiased across one pixel of the field's own gradient.
	float w = max(fwidth(d), 1e-5);
	return smoothstep(w, -w, d);
}

// Returns x = bone coverage, y = bone shading multiplier.
// Working space: p is centred on the pane, +y up, and the skull is authored to
// span roughly +/-0.33 across and -0.33..0.41 vertically.
vec2 eval_skull(vec2 p) {
	// Cranium, upper jaw and mandible blended into one mass. The blend radii
	// matter more than the shapes: too small and the mandible reads as a
	// separate box stuck under the face.
	float cranium = sd_ellipse(p - vec2(0.0, 0.145), vec2(0.325, 0.262));
	float maxilla = sd_ellipse(p - vec2(0.0, -0.060), vec2(0.278, 0.196));
	float mandible = sd_round_box(p - vec2(0.0, -0.232),
		vec2(0.196 * jaw_width, 0.094), 0.085);

	float bone = smin(cranium, maxilla, 0.105);
	bone = smin(bone, mandible, 0.090);

	// Pinch the temples so the cranium does not read as a plain egg.
	float temples = sd_ellipse(vec2(abs(p.x) - 0.380, p.y - 0.020), vec2(0.110, 0.150));
	bone = max(bone, -temples);

	// Eye sockets, mirrored then tilted inward for the scowl in the concept art.
	vec2 ep = vec2(abs(p.x) - 0.148, p.y - 0.055);
	float ca = cos(socket_tilt);
	float sa = sin(socket_tilt);
	vec2 er = vec2(ep.x * ca - ep.y * sa, ep.x * sa + ep.y * ca);
	float socket = sd_ellipse(er, vec2(0.108, 0.080));

	// Nasal aperture: an inverted teardrop, wide at the base, pinched at the top.
	vec2 np = p - vec2(0.0, -0.048);
	float nasal = max(abs(np.x) * 2.6 + np.y - 0.050, -np.y - 0.062) * 0.35;

	// Tooth separators and the gum line, confined to the jaw band.
	float band = max(abs(p.y + 0.205) - 0.062, abs(p.x) - 0.175 * jaw_width);
	float gaps = abs(fract(p.x * teeth_count + 0.5) - 0.5) / teeth_count - 0.006;
	float gum = max(abs(p.y + 0.143) - 0.006, abs(p.x) - 0.175 * jaw_width);
	float cuts = min(max(band, gaps), gum);

	float coverage = mask_lt(bone) * (1.0 - mask_lt(socket))
		* (1.0 - mask_lt(nasal)) * (1.0 - mask_lt(cuts));

	// Contact shading so the bone has volume rather than reading as a cutout:
	// darken into the socket and nasal edges, lift the cheekbones and brow, and
	// put a hot line right on the silhouette. The range is kept near 0..1 on
	// purpose - push the base up and every value clips to flat white after
	// tonemapping, which is exactly what the shading is there to avoid.
	float ao = smoothstep(0.0, 0.060, min(socket, nasal));
	float cheek = 1.0 - smoothstep(0.0, 0.110,
		sd_ellipse(vec2(abs(p.x) - 0.205, p.y - 0.010), vec2(0.080, 0.058)));
	float brow = 1.0 - smoothstep(0.0, 0.085,
		sd_ellipse(p - vec2(0.0, 0.200), vec2(0.215, 0.065)));
	float rim = 1.0 - smoothstep(0.0, 0.028, abs(bone));

	float shade = 0.24 + 0.40 * ao + 0.20 * cheek + 0.14 * brow + 0.38 * rim;
	return vec2(coverage, shade);
}


void fragment() {
	vec2 base_uv = (UV - uv_offset) / max(uv_scale, vec2(1e-4));

	// Tangent-space view vector. TANGENT/BINORMAL/NORMAL and VIEW are all in
	// view space here, so projecting VIEW onto that frame gives the direction
	// the eye is looking through the glass.
	vec3 tv = normalize(vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL)));
	tv.y *= parallax_flip_y;
	// Clamping z stops the offset exploding as the surface turns edge-on.
	vec2 parallax = tv.xy / max(abs(tv.z), 0.35);

	vec2 p_mid = ((base_uv - parallax * cavity_depth) - vec2(0.5)) / skull_size;
	vec2 skull = eval_skull(p_mid);

	vec3 bone_rgb = vec3(skull.x);
	if (use_dispersion) {
		// Sampling the interior at slightly different depths per channel splits
		// the edges the way a thick pane does.
		float d = cavity_depth * dispersion;
		vec2 p_r = ((base_uv - parallax * (cavity_depth - d)) - vec2(0.5)) / skull_size;
		vec2 p_b = ((base_uv - parallax * (cavity_depth + d)) - vec2(0.5)) / skull_size;
		bone_rgb = vec3(eval_skull(p_r).x, skull.x, eval_skull(p_b).x);
	}

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), glass_power);
	float hide = fres * glass_occlude;

	// Travelling highlight so the pane reads as a curved surface.
	float sweep_pos = fract(TIME * sweep_speed) * 1.6 - 0.3;
	float sweep = smoothstep(sweep_width, 0.0,
		abs((base_uv.x * 0.7 + base_uv.y * 0.3) - sweep_pos));

	float energy = skull_energy * (1.0 + pulse * 2.5);
	vec3 emitted = skull_color * bone_rgb * skull.y * energy * skull_visibility
		* (1.0 - hide);

	ALBEDO = glass_color;
	EMISSION = emitted
		+ glass_rim_color * fres * glass_rim_energy
		+ glass_rim_color * sweep * sweep_energy;
	// The interior only shows through where the surface is opaque enough to
	// carry it, so bone coverage has to push alpha up with it.
	ALPHA = clamp(mix(glass_alpha, 1.0, hide) + skull.x * skull.y * 0.35, 0.0, 1.0);
	ROUGHNESS = glass_roughness;
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
