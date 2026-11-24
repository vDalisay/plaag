// Grimdark gothic woodcut & parchment post-process for 3D scenes.
//
// Reads screen colour, depth and normal buffers and repaints the frame as a
// moody dark-medieval woodcut engraving with genuine 3D sculptural depth:
//   * heavy ink silhouettes + lighter creases from depth/normal discontinuities
//   * screen-space crevice / contact darkening from depth concavity (grounds
//     buildings, props and swarms into the street)
//   * continuous lighting + shadow value preserved beneath multi-band woodcut
//     hatching and cool nocturnal shadow tinting
//   * darker soot-aged vellum ground so glowing crimson plague and warm amber
//     lanterns pop dramatically out of the gloom
//
// Requires the Forward+ renderer (normal-roughness buffer).

shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

group_uniforms Palette;
uniform vec3 parchment_light : source_color = vec3(0.66, 0.59, 0.49);
uniform vec3 parchment_dark : source_color = vec3(0.28, 0.23, 0.19);
uniform vec3 shadow_tint : source_color = vec3(0.16, 0.17, 0.21);
uniform vec3 ink_color : source_color = vec3(0.035, 0.028, 0.025);
uniform vec3 accent_red : source_color = vec3(0.84, 0.15, 0.11);
uniform vec3 accent_amber : source_color = vec3(0.98, 0.64, 0.18);
uniform vec3 accent_green : source_color = vec3(0.34, 0.48, 0.26);
uniform vec3 accent_blue : source_color = vec3(0.24, 0.34, 0.48);
// Scene colours more saturated than this (gamma space) keep their hue as an ink wash.
uniform float accent_saturation_threshold : hint_range(0.0, 1.0) = 0.48;
uniform float accent_strength : hint_range(0.0, 1.0) = 1.0;
// How opaque the wash is over the paper (1 = flat, solid colour).
uniform float accent_opacity : hint_range(0.0, 1.0) = 0.92;
// Added brightness for accent surfaces before banding, so a red cloak in
// sunlight is not hatched just for being red.
uniform float accent_shade_lift : hint_range(0.0, 0.5) = 0.16;

group_uniforms Ink_Lines;
uniform float silhouette_width : hint_range(0.5, 5.0) = 1.9;
uniform float line_width : hint_range(0.5, 4.0) = 1.2;
uniform float depth_edge_sensitivity : hint_range(0.0, 60.0) = 13.0;
uniform float normal_edge_sensitivity : hint_range(0.0, 10.0) = 1.85;
uniform float line_strength : hint_range(0.0, 1.0) = 0.96;
uniform float line_halo : hint_range(0.0, 1.0) = 0.16;
uniform float line_halo_radius : hint_range(1.0, 6.0) = 3.0;
uniform float wobble_amount : hint_range(0.0, 8.0) = 0.85;
uniform float wobble_scale : hint_range(1.0, 200.0) = 48.0;
uniform float line_boil_speed : hint_range(0.0, 10.0) = 0.0;

group_uniforms Shading;
// Brightness (gamma space) below which a pixel gets single / cross hatching / solid ink.
uniform float shade_light_threshold : hint_range(0.0, 1.5) = 0.74;
uniform float shade_dark_threshold : hint_range(0.0, 1.5) = 0.42;
uniform float solid_ink_threshold : hint_range(0.0, 0.5) = 0.18;
// 0 = tone bands come from rendered lighting (includes shadows), 1 = normals only.
uniform float shade_from_normals : hint_range(0.0, 1.0) = 0.18;
uniform vec3 light_dir_view = vec3(0.3, 0.8, 0.5);
uniform float scene_exposure : hint_range(0.1, 4.0) = 1.05;
uniform float hatch_spacing : hint_range(2.0, 30.0) = 6.5;
uniform float hatch_width : hint_range(0.5, 5.0) = 0.95;
uniform float hatch_angle : hint_range(0.0, 3.1416) = 0.75;
uniform float hatch_strength : hint_range(0.0, 1.0) = 0.75;
uniform float stipple_strength : hint_range(0.0, 1.0) = 0.16;
// Sculptural depth: darkens shaded bands and preserves continuous 3D lighting.
uniform float tone_strength : hint_range(0.0, 1.0) = 0.68;
uniform float luma_preserve : hint_range(0.0, 1.0) = 0.46;
// Screen-space crevice / contact darkening from depth concavity.
uniform float crevice_ao_strength : hint_range(0.0, 1.0) = 0.55;

group_uniforms Paper;
uniform float paper_grain : hint_range(0.0, 1.0) = 0.28;
uniform float surface_grain : hint_range(0.0, 1.0) = 0.11;
uniform float paper_mottle : hint_range(0.0, 1.0) = 0.05;
uniform float paper_mottle_scale : hint_range(1.0, 60.0) = 24.0;
uniform float paper_stains : hint_range(0.0, 1.0) = 0.34;
uniform float ink_speckle : hint_range(0.0, 1.0) = 0.14;
uniform float paper_scale : hint_range(0.5, 10.0) = 3.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.56;
uniform float effect_mix : hint_range(0.0, 1.0) = 1.0;

group_uniforms Plague;
uniform float plague_stain : hint_range(0.0, 1.0) = 0.0;
uniform vec3 plague_stain_color : source_color = vec3(0.58, 0.16, 0.12);
uniform float glow_lift : hint_range(0.0, 1.0) = 0.85;

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

// Returns (silhouette, crease, crevice_ao).
vec3 edges_and_ao(vec2 suv, vec2 o, mat4 inv_proj) {
	float dc = linear_depth(suv, inv_proj);
	float dl = linear_depth(suv - vec2(o.x, 0.0), inv_proj);
	float dr = linear_depth(suv + vec2(o.x, 0.0), inv_proj);
	float du = linear_depth(suv - vec2(0.0, o.y), inv_proj);
	float dd = linear_depth(suv + vec2(0.0, o.y), inv_proj);
	float grad = abs(dl - dr) + abs(du - dd);
	float nearest = max(min(dc, min(min(dl, dr), min(du, dd))), 0.01);
	float depth_edge = grad / nearest;
	depth_edge = smoothstep(0.0, 1.0, depth_edge * depth_edge_sensitivity * 0.1);

	// Concavity: pixels deeper than their immediate neighbours sit inside a crevice/contact shadow.
	float avg_d = 0.25 * (dl + dr + du + dd);
	float concavity = clamp((dc - avg_d) / max(dc * 0.055, 0.02), 0.0, 1.0);
	float crevice = smoothstep(0.08, 0.9, concavity);

	vec3 nl = view_normal(suv - vec2(o.x, 0.0));
	vec3 nr = view_normal(suv + vec2(o.x, 0.0));
	vec3 nu = view_normal(suv - vec2(0.0, o.y));
	vec3 nd = view_normal(suv + vec2(0.0, o.y));
	float normal_edge = (1.0 - dot(nl, nr)) + (1.0 - dot(nu, nd));
	normal_edge = smoothstep(0.1, 0.6, normal_edge * normal_edge_sensitivity * 0.5);
	return vec3(depth_edge, normal_edge, crevice);
}

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

	// ---- hand-drawn wobble applied to edges and hatching
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
	float z_lin = is_sky ? 120.0 : linear_depth(uv, INV_PROJECTION_MATRIX);
	vec3 nc = view_normal(wuv);

	// ---- ink outlines & screen-space crevice darkening
	vec3 e_sil = edges_and_ao(wuv, px * silhouette_width, INV_PROJECTION_MATRIX);
	vec3 e_crease = edges_and_ao(wuv, px * line_width, INV_PROJECTION_MATRIX);
	float edge = max(e_sil.x, e_crease.y * 0.85);
	float line_grain = 0.72 + 0.28 * vnoise(pix * 0.35);
	float ink = clamp(edge * line_grain, 0.0, 1.0) * line_strength;

	vec3 e_halo = edges_and_ao(wuv, px * silhouette_width * line_halo_radius, INV_PROJECTION_MATRIX);
	float halo = clamp(max(e_halo.x, e_halo.y * 0.6) - edge, 0.0, 1.0) * line_halo;
	halo *= 0.4 + 0.6 * vnoise(pix * 0.5);
	float crevice_ao = is_sky ? 0.0 : max(e_sil.z * 0.75, e_halo.z) * crevice_ao_strength;

	// ---- colour analysis in gamma space
	vec3 s = pow(max(scene / scene_exposure, vec3(0.0)), vec3(1.0 / 2.2));
	float v = max(s.r, max(s.g, s.b));
	float mn = min(s.r, min(s.g, s.b));
	float sat = v > 0.0001 ? (v - mn) / v : 0.0;
	float luma = dot(s, vec3(0.299, 0.587, 0.114));
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
	float red_w = 1.0 - smoothstep(0.035, 0.075, red_dist);
	float amber_w = smoothstep(0.035, 0.075, hue) * (1.0 - smoothstep(0.16, 0.21, hue));
	float green_w = smoothstep(0.17, 0.22, hue) * (1.0 - smoothstep(0.45, 0.50, hue));
	float blue_w = smoothstep(0.5, 0.56, hue) * (1.0 - smoothstep(0.72, 0.78, hue));
	float hue_w = red_w + amber_w + green_w + blue_w;
	float accent_w = smoothstep(accent_saturation_threshold - 0.1, accent_saturation_threshold + 0.1, sat)
		* accent_strength * clamp(hue_w, 0.0, 1.0);
	vec3 accent = (accent_red * red_w + accent_amber * amber_w + accent_green * green_w + accent_blue * blue_w)
		/ max(hue_w, 0.0001);

	// ---- sculptural lighting + tone bands (preserves 3D depth)
	float ndl = clamp(dot(nc, normalize(light_dir_view)), 0.0, 1.0);
	float shade = mix(clamp(luma * 1.15, 0.0, 1.5), ndl, shade_from_normals);
	shade += accent_w * accent_shade_lift;
	shade -= crevice_ao * 0.22;
	shade += (vnoise(uv * VIEWPORT_SIZE / 5.0) - 0.5) * 0.06;
	if (is_sky) {
		shade = 1.3;
	}
	float mid = 1.0 - smoothstep(shade_light_threshold - 0.05, shade_light_threshold + 0.05, shade);
	float dark = 1.0 - smoothstep(shade_dark_threshold - 0.05, shade_dark_threshold + 0.05, shade);
	float solid = 1.0 - smoothstep(solid_ink_threshold - 0.02, solid_ink_threshold + 0.02, v);
	if (is_sky) {
		solid = 0.0;
	}

	float h1 = hatch_line(pix, hatch_angle, hatch_spacing, hatch_width);
	float h2 = hatch_line(pix, hatch_angle + 1.35, hatch_spacing, hatch_width);
	float hatch = max(h1 * mid * 0.85, h2 * dark) * hatch_strength;
	// Glowing amber (lamps, windows, fire) and bright hit-flashes are never hatched.
	float glow = amber_w * accent_w * smoothstep(0.92, 1.25, v);
	float flash_hi = smoothstep(1.25, 1.55, v) * (1.0 - sat * 0.6);
	float unhatched = clamp(glow + flash_hi, 0.0, 1.0);
	hatch *= 1.0 - unhatched;

	float dot_density = (0.10 * mid + 0.22 * dark + 0.35 * halo + 0.20 * crevice_ao) * stipple_strength * (1.0 - unhatched);
	float stipple = step(hash21(floor(pix * 0.5)), dot_density);

	// ---- dark weathered paper base
	vec2 pp = auv * paper_scale;
	float grain = fbm(pp * 6.0);
	float fibres = vnoise(uv * VIEWPORT_SIZE * vec2(0.9, 0.15)) * 0.5 + vnoise(uv * VIEWPORT_SIZE * 0.6) * 0.5;
	float paper_t = 0.58 + (grain - 0.5) * 1.45 * paper_grain + (fibres - 0.5) * 0.3 * paper_grain;
	vec2 cells = voronoi(auv * paper_mottle_scale + vec2(fbm(pp * 2.0) - 0.5, fbm(pp * 2.0 + 5.0) - 0.5) * 0.6);
	float cell_border = 1.0 - smoothstep(0.0, 0.12, cells.x);
	paper_t += ((cells.y - 0.5) * 0.28 - cell_border * 0.3) * paper_mottle;
	vec3 paper = mix(parchment_dark, parchment_light, clamp(paper_t, 0.0, 1.0));
	float stain = smoothstep(0.50, 0.72, fbm(pp * 1.1 + vec2(7.0, 3.0))) * paper_stains;
	float spots = smoothstep(0.76, 0.90, fbm(pp * 4.0 + vec2(2.0, 9.0))) * paper_stains;
	float speckle = step(1.0 - ink_speckle * 0.012, hash21(floor(uv * VIEWPORT_SIZE / 1.5) + 3.0));

	// ---- compose with preserved 3D sculptural shading + cool shadow depth
	vec3 base = mix(paper, accent * (0.76 + 0.24 * paper_t), accent_w * accent_opacity);

	// Continuous 3D value modulation so roofs, facades, cobbles and figures have real volume.
	float val_mod = mix(1.0, clamp(0.44 + luma * 0.85, 0.36, 1.24), luma_preserve * (1.0 - unhatched));
	base *= val_mod;

	// Banded cool-umber shadow darkening + screen-space crevice shadow.
	float tone = clamp(max(mid * 0.45, dark) * tone_strength + crevice_ao * 0.55, 0.0, 0.92) * (1.0 - unhatched);
	vec3 deep_shadow = mix(base * (parchment_dark / max(parchment_light, vec3(0.01))), shadow_tint, 0.42);
	base = mix(base, deep_shadow, tone);

	// Warm luminous lift on lanterns, torches, lit windows, and hit-flashes.
	if (glow_lift > 0.0) {
		float lift = glow * clamp((v - 1.15) * 1.8, 0.0, 1.0) * glow_lift;
		base = mix(base, vec3(1.0, 0.84, 0.46), lift);
	}
	if (flash_hi > 0.01) {
		base = mix(base, vec3(0.98, 0.92, 0.82), flash_hi * 0.85);
	}
	// Subtle atmospheric depth gloom in far corners of the larger district.
	float depth_fog = smoothstep(38.0, 88.0, z_lin) * (is_sky ? 0.0 : 0.32);
	base = mix(base, shadow_tint * 0.85, depth_fog);

	if (plague_stain > 0.001) {
		vec2 c = abs(uv - 0.5) * 2.0;
		float e = max(c.x, c.y) * 0.8 + length(c) * 0.14;
		float n = fbm(auv * 2.3 + vec2(31.0, 17.0)) - 0.5;
		float front = 1.0 - plague_stain * 0.44 + n * 0.3;
		float wash = smoothstep(front, front + 0.07, e) * smoothstep(0.58, 0.68, e);
		float tide = wash * (1.0 - wash) * 4.0;
		vec3 tint = plague_stain_color * (1.15 + 0.2 * paper_t);
		base *= mix(vec3(1.0), tint, wash * (0.42 + 0.2 * grain));
		base = mix(base, base * vec3(0.65, 0.42, 0.36), tide * 0.5);
	}
	vec3 color = base;
	color = mix(color, ink_color, hatch);
	color = mix(color, ink_color, stipple * 0.72);
	color = mix(color, ink_color, halo * 0.55);
	color = mix(color, ink_color, solid * 0.96 * (1.0 - flash_hi));
	color = mix(color, ink_color, ink * (1.0 - flash_hi * 0.5));
	color = mix(color, ink_color, speckle * 0.42);
	color = mix(color, color * vec3(0.76, 0.64, 0.48), stain * 0.55 + spots * 0.48);
	// Fine print grain + brooding gothic vignette.
	float sg = vnoise(uv * VIEWPORT_SIZE * 0.8) * 0.6 + hash21(floor(uv * VIEWPORT_SIZE)) * 0.4;
	color *= 1.0 + (sg - 0.5) * surface_grain * 0.55;
	float vig = smoothstep(0.28, 1.08, length(uv - 0.5) * 1.45);
	color = mix(color, color * vec3(0.36, 0.30, 0.26), vig * vignette_strength);

	ALBEDO = mix(scene, color, effect_mix);
}
