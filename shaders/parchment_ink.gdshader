// Parchment & ink post-process for 3D scenes.
//
// Put this on a 2x2 QuadMesh (flip_faces = true, big extra_cull_margin) that is a
// child of the Camera3D. It reads the screen colour, depth and normal buffers and
// repaints the frame as an old manuscript illustration:
//   * ink outlines from depth + normal discontinuities, with hand-drawn wobble;
//     silhouettes are drawn heavier than creases, with a grainy ink halo
//   * three flat tone bands (paper / single hatch / cross hatch) plus stipple
//     instead of smooth lighting
//   * desaturated parchment, except saturated reds / ambers / greens / blues which
//     become ink washes of that hue
//   * procedural paper: grain, mottled cells, stains, speckles and a warm vignette
//
// Requires the Forward+ renderer (normal-roughness buffer).

shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

group_uniforms Palette;
uniform vec3 parchment_light : source_color = vec3(0.99, 0.90, 0.72);
uniform vec3 parchment_dark : source_color = vec3(0.86, 0.72, 0.52);
uniform vec3 ink_color : source_color = vec3(0.06, 0.04, 0.03);
uniform vec3 accent_red : source_color = vec3(0.80, 0.22, 0.14);
uniform vec3 accent_amber : source_color = vec3(0.97, 0.64, 0.20);
uniform vec3 accent_green : source_color = vec3(0.45, 0.52, 0.30);
uniform vec3 accent_blue : source_color = vec3(0.30, 0.40, 0.58);
// Scene colours more saturated than this (gamma space) keep their hue as an ink wash.
uniform float accent_saturation_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float accent_strength : hint_range(0.0, 1.0) = 1.0;
// How opaque the wash is over the paper (1 = flat, solid colour).
uniform float accent_opacity : hint_range(0.0, 1.0) = 0.95;
// Added brightness for accent surfaces before banding, so a red cloak in
// sunlight is not hatched just for being red.
uniform float accent_shade_lift : hint_range(0.0, 0.5) = 0.12;

group_uniforms Ink_Lines;
// Silhouettes (depth steps) are drawn with silhouette_width, creases (normal
// changes on the same surface) with line_width. Both in pixels.
uniform float silhouette_width : hint_range(0.5, 5.0) = 2.0;
uniform float line_width : hint_range(0.5, 4.0) = 1.3;
uniform float depth_edge_sensitivity : hint_range(0.0, 60.0) = 12.0;
uniform float normal_edge_sensitivity : hint_range(0.0, 10.0) = 1.6;
uniform float line_strength : hint_range(0.0, 1.0) = 1.0;
// Soft grainy ink bleed around the lines; radius is a multiple of silhouette_width.
uniform float line_halo : hint_range(0.0, 1.0) = 0.12;
uniform float line_halo_radius : hint_range(1.0, 6.0) = 3.0;
// Hand-drawn jitter of the lines, in pixels, and how many wiggles across the screen.
uniform float wobble_amount : hint_range(0.0, 8.0) = 1.0;
uniform float wobble_scale : hint_range(1.0, 200.0) = 45.0;
// > 0 makes the lines "boil" like hand-drawn animation.
uniform float line_boil_speed : hint_range(0.0, 10.0) = 0.0;

group_uniforms Shading;
// Brightness (gamma space) below which a pixel gets single hatching / cross
// hatching / solid ink.
uniform float shade_light_threshold : hint_range(0.0, 1.5) = 0.72;
uniform float shade_dark_threshold : hint_range(0.0, 1.5) = 0.40;
uniform float solid_ink_threshold : hint_range(0.0, 0.5) = 0.22;
// 0 = tone bands come from the rendered lighting (includes shadows),
// 1 = from surface normals vs. light_dir_view (cleaner, no shadows).
uniform float shade_from_normals : hint_range(0.0, 1.0) = 0.1;
uniform vec3 light_dir_view = vec3(0.3, 0.8, 0.5);
uniform float scene_exposure : hint_range(0.1, 4.0) = 1.0;
uniform float hatch_spacing : hint_range(2.0, 30.0) = 7.0;
uniform float hatch_width : hint_range(0.5, 5.0) = 1.0;
uniform float hatch_angle : hint_range(0.0, 3.1416) = 0.75;
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.85;
// Random ink dots inside the shaded bands and the line halo (pen stipple).
uniform float stipple_strength : hint_range(0.0, 1.0) = 0.15;
// Flat darkening of the hatched bands, on top of the hatch lines.
uniform float tone_strength : hint_range(0.0, 1.0) = 0.2;

group_uniforms Paper;
uniform float paper_grain : hint_range(0.0, 1.0) = 0.3;
// Fine brightness noise over everything, ink and washes included (printed/scanned look).
uniform float surface_grain : hint_range(0.0, 1.0) = 0.1;
// Faint cell pattern in the paper, like plaster or cobbles.
uniform float paper_mottle : hint_range(0.0, 1.0) = 0.06;
uniform float paper_mottle_scale : hint_range(1.0, 60.0) = 22.0;
uniform float paper_stains : hint_range(0.0, 1.0) = 0.3;
// Sparse dark flecks on the page.
uniform float ink_speckle : hint_range(0.0, 1.0) = 0.15;
uniform float paper_scale : hint_range(0.5, 10.0) = 3.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
// 0 shows the plain 3D render, 1 the full effect.
uniform float effect_mix : hint_range(0.0, 1.0) = 1.0;

group_uniforms Plague;
// 0..1: a red-brown wash that blooms in from the page edges (the District's
// Infection drives it). Noise-shaped, under the ink lines, and never inside
// the central ~60% of the screen. 0 costs nothing.
uniform float plague_stain : hint_range(0.0, 1.0) = 0.0;
uniform vec3 plague_stain_color : source_color = vec3(0.62, 0.30, 0.20);
// > 0: very bright glowing amber (lanterns) is washed paler the brighter it
// renders, so an emission flicker shows. 0 = the old flat amber.
uniform float glow_lift : hint_range(0.0, 1.0) = 0.0;

// ---------------------------------------------------------------- noise helpers
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.3);
		amp *= 0.5;
	}
	return v;
}

// Returns (distance to nearest cell border, random value of the cell).
vec2 voronoi(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = i + g;
			vec2 o = vec2(hash21(c), hash21(c + vec2(7.1, 3.3)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash21(c + vec2(1.7, 9.2));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(d2 - d1, id);
}

// ---------------------------------------------------------------- buffer helpers
float linear_depth(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_texture, suv).x;
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

vec3 view_normal(vec2 suv) {
	return normalize(texture(normal_roughness_texture, suv).xyz * 2.0 - 1.0);
}

// Edge strength at `suv` sampling `o` pixels away. Returns (silhouette, crease).
vec2 edges(vec2 suv, vec2 o, mat4 inv_proj) {
	float dc = linear_depth(suv, inv_proj);
	float dl = linear_depth(suv - vec2(o.x, 0.0), inv_proj);
	float dr = linear_depth(suv + vec2(o.x, 0.0), inv_proj);
	float du = linear_depth(suv - vec2(0.0, o.y), inv_proj);
	float dd = linear_depth(suv + vec2(0.0, o.y), inv_proj);
	float grad = abs(dl - dr) + abs(du - dd);
	// Relative to the nearest sampled depth so distant and near objects get similar lines.
	float depth_edge = grad / max(min(dc, min(min(dl, dr), min(du, dd))), 0.01);
	depth_edge = smoothstep(0.0, 1.0, depth_edge * depth_edge_sensitivity * 0.1);

	vec3 nl = view_normal(suv - vec2(o.x, 0.0));
	vec3 nr = view_normal(suv + vec2(o.x, 0.0));
	vec3 nu = view_normal(suv - vec2(0.0, o.y));
	vec3 nd = view_normal(suv + vec2(0.0, o.y));
	float normal_edge = (1.0 - dot(nl, nr)) + (1.0 - dot(nu, nd));
	normal_edge = smoothstep(0.1, 0.6, normal_edge * normal_edge_sensitivity * 0.5);
	return vec2(depth_edge, normal_edge);
}

// Distance-to-nearest-line based hatch: 1.0 on the line, 0.0 between lines.
float hatch_line(vec2 pix, float angle, float spacing, float width) {
	float d = dot(pix, vec2(cos(angle), sin(angle)));
	float f = abs(fract(d / spacing) - 0.5) * spacing;
	return 1.0 - smoothstep(width * 0.5 - 0.5, width * 0.5 + 0.5, f);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 uv = SCREEN_UV;
	vec2 auv = uv * vec2(aspect, 1.0);

	// ---- hand-drawn wobble applied to where we look up edges and hatching
	float t = TIME * line_boil_speed;
	vec2 wob = vec2(
		vnoise(auv * wobble_scale + vec2(t, 0.0)),
		vnoise(auv * wobble_scale + vec2(37.2, 11.7 + t))) - 0.5;
	vec2 wuv = uv + wob * wobble_amount * px * 2.0;
	vec2 pix = wuv * VIEWPORT_SIZE;

	// ---- scene buffers
	vec3 scene = texture(screen_texture, uv).rgb;
	float raw_depth = texture(depth_texture, wuv).x;
	bool is_sky = raw_depth < 0.000001;
	vec3 nc = view_normal(wuv);

	// ---- ink outlines: heavy silhouettes, lighter creases, grainy halo
	vec2 e_sil = edges(wuv, px * silhouette_width, INV_PROJECTION_MATRIX);
	vec2 e_crease = edges(wuv, px * line_width, INV_PROJECTION_MATRIX);
	float edge = max(e_sil.x, e_crease.y * 0.85);
	float line_grain = 0.7 + 0.3 * vnoise(pix * 0.35);
	float ink = clamp(edge * line_grain, 0.0, 1.0) * line_strength;

	vec2 e_halo = edges(wuv, px * silhouette_width * line_halo_radius, INV_PROJECTION_MATRIX);
	float halo = clamp(max(e_halo.x, e_halo.y * 0.6) - edge, 0.0, 1.0) * line_halo;
	halo *= 0.4 + 0.6 * vnoise(pix * 0.5);

	// ---- colour analysis of the rendered pixel, in gamma space so that the
	// saturation / brightness thresholds match what the artist picked in the colour picker
	vec3 s = pow(max(scene / scene_exposure, vec3(0.0)), vec3(1.0 / 2.2));
	float v = max(s.r, max(s.g, s.b));
	float mn = min(s.r, min(s.g, s.b));
	float sat = v > 0.0001 ? (v - mn) / v : 0.0;
	float hue = 0.0;
	if (sat > 0.0001) {
		float delta = v - mn;
		if (s.r >= s.g && s.r >= s.b) {
			hue = mod((s.g - s.b) / delta, 6.0);
		} else if (s.g >= s.b) {
			hue = (s.b - s.r) / delta + 2.0;
		} else {
			hue = (s.r - s.g) / delta + 4.0;
		}
		hue /= 6.0;
	}
	float red_dist = min(hue, 1.0 - hue);
	float red_w = 1.0 - smoothstep(0.035, 0.07, red_dist);
	float amber_w = smoothstep(0.035, 0.07, hue) * (1.0 - smoothstep(0.16, 0.21, hue));
	float green_w = smoothstep(0.17, 0.22, hue) * (1.0 - smoothstep(0.45, 0.50, hue));
	float blue_w = smoothstep(0.5, 0.56, hue) * (1.0 - smoothstep(0.72, 0.78, hue));
	float hue_w = red_w + amber_w + green_w + blue_w;
	float accent_w = smoothstep(accent_saturation_threshold - 0.1, accent_saturation_threshold + 0.1, sat)
		* accent_strength * clamp(hue_w, 0.0, 1.0);
	vec3 accent = (accent_red * red_w + accent_amber * amber_w + accent_green * green_w + accent_blue * blue_w)
		/ max(hue_w, 0.0001);

	// ---- tone bands
	float ndl = clamp(dot(nc, normalize(light_dir_view)), 0.0, 1.0);
	float shade = mix(clamp(v, 0.0, 1.5), ndl, shade_from_normals);
	shade += accent_w * accent_shade_lift;
	shade += (vnoise(uv * VIEWPORT_SIZE / 5.0) - 0.5) * 0.08;
	if (is_sky) {
		shade = 1.5;
	}
	float mid = 1.0 - smoothstep(shade_light_threshold - 0.03, shade_light_threshold + 0.03, shade);
	float dark = 1.0 - smoothstep(shade_dark_threshold - 0.03, shade_dark_threshold + 0.03, shade);
	float solid = 1.0 - smoothstep(solid_ink_threshold - 0.02, solid_ink_threshold + 0.02, v);
	if (is_sky) {
		solid = 0.0;
	}

	float h1 = hatch_line(pix, hatch_angle, hatch_spacing, hatch_width);
	float h2 = hatch_line(pix, hatch_angle + 1.35, hatch_spacing, hatch_width);
	float hatch = max(h1 * mid, h2 * dark) * hatch_strength;
	// Glowing amber (lamps, windows) is never hatched.
	float glow = amber_w * accent_w * smoothstep(0.95, 1.3, v);
	hatch *= 1.0 - glow;

	// Pen stipple: random dots, denser the darker the band, plus in the line halo.
	float dot_density = (0.12 * mid + 0.22 * dark + 0.35 * halo) * stipple_strength * (1.0 - glow);
	float stipple = step(hash21(floor(pix * 0.5)), dot_density);

	// ---- paper
	vec2 pp = auv * paper_scale;
	float grain = fbm(pp * 6.0);
	float fibres = vnoise(uv * VIEWPORT_SIZE * vec2(0.9, 0.15)) * 0.5 + vnoise(uv * VIEWPORT_SIZE * 0.6) * 0.5;
	float paper_t = 0.6 + (grain - 0.5) * 1.6 * paper_grain + (fibres - 0.5) * 0.35 * paper_grain;
	vec2 cells = voronoi(auv * paper_mottle_scale + vec2(fbm(pp * 2.0) - 0.5, fbm(pp * 2.0 + 5.0) - 0.5) * 0.6);
	float cell_border = 1.0 - smoothstep(0.0, 0.12, cells.x);
	paper_t += ((cells.y - 0.5) * 0.3 - cell_border * 0.35) * paper_mottle;
	vec3 paper = mix(parchment_dark, parchment_light, clamp(paper_t, 0.0, 1.0));
	float stain = smoothstep(0.52, 0.72, fbm(pp * 1.1 + vec2(7.0, 3.0))) * paper_stains;
	float spots = smoothstep(0.78, 0.9, fbm(pp * 4.0 + vec2(2.0, 9.0))) * paper_stains;
	float speckle = step(1.0 - ink_speckle * 0.012, hash21(floor(uv * VIEWPORT_SIZE / 1.5) + 3.0));

	// ---- compose
	vec3 base = mix(paper, accent * (0.75 + 0.25 * paper_t), accent_w * accent_opacity);
	float tone = max(mid * 0.5, dark) * tone_strength * (1.0 - glow);
	base = mix(base, base * parchment_dark / parchment_light, tone);
	if (glow_lift > 0.0) {
		float lift = glow * clamp((v - 1.62) * 3.5, 0.0, 1.0) * glow_lift;
		base = mix(base, vec3(1.0, 0.93, 0.66), lift);
	}
	if (plague_stain > 0.001) {
		// 0 at the centre, 1 at the screen edge (box distance, a little rounded).
		vec2 c = abs(uv - 0.5) * 2.0;
		float e = max(c.x, c.y) * 0.8 + length(c) * 0.14;
		float n = fbm(auv * 2.3 + vec2(31.0, 17.0)) - 0.5;
		float front = 1.0 - plague_stain * 0.42 + n * 0.3;
		float wash = smoothstep(front, front + 0.07, e) * smoothstep(0.6, 0.7, e);
		// Darker tide line where the wash ends, like dried watercolour.
		float tide = wash * (1.0 - wash) * 4.0;
		// Multiplied in like a stain soaking the page, so washes keep their hue.
		vec3 tint = plague_stain_color * (1.25 + 0.2 * paper_t);
		base *= mix(vec3(1.0), tint, wash * (0.32 + 0.18 * grain));
		base = mix(base, base * vec3(0.72, 0.56, 0.48), tide * 0.45);
	}
	vec3 color = base;
	color = mix(color, ink_color, hatch);
	color = mix(color, ink_color, stipple * 0.7);
	color = mix(color, ink_color, halo * 0.5);
	color = mix(color, ink_color, solid * 0.97);
	color = mix(color, ink_color, ink);
	color = mix(color, ink_color, speckle * 0.45);
	color = mix(color, color * vec3(0.82, 0.70, 0.52), stain * 0.6 + spots * 0.5);
	// Fine grain over everything, like a scan of a printed page.
	float sg = vnoise(uv * VIEWPORT_SIZE * 0.8) * 0.6 + hash21(floor(uv * VIEWPORT_SIZE)) * 0.4;
	color *= 1.0 + (sg - 0.5) * surface_grain * 0.6;
	float vig = smoothstep(0.35, 1.1, length(uv - 0.5) * 1.45);
	color = mix(color, color * vec3(0.72, 0.58, 0.40), vig * vignette_strength);

	ALBEDO = mix(scene, color, effect_mix);
}
