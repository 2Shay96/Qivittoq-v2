shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back, shadows_disabled;
// The bay: dark, cold water under a slow swell, slush and thin pancake ice along the shore.

#include "res://shaders/common.gdshaderinc"

const vec3 WATER = vec3(0.004, 0.0065, 0.009);
const vec3 SLUSH = vec3(0.34, 0.39, 0.44);

varying vec3 wpos;
varying float out_from_shore;

float wave(vec2 p, vec2 d, float k, float w, float a, float t, inout vec2 grad) {
	float ph = dot(p, d) * k + t * w;
	grad += d * k * a * cos(ph);
	return a * sin(ph);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sd = shore_x(wp.z) - wp.x;
	// The swell rolls in from the west and dies in the shallows and the slush.
	float calm = smoothstep(-2.0, 30.0, sd) * (1.0 - ice_cover * 0.85);
	vec2 g = vec2(0.0);
	float h = 0.0;
	h += wave(wp.xz, normalize(vec2(1.0, 0.22)), 0.09, 0.42, 0.2, TIME, g);
	h += wave(wp.xz, normalize(vec2(0.9, -0.45)), 0.17, 0.66, 0.08, TIME, g);
	h += wave(wp.xz, normalize(vec2(0.55, 0.83)), 0.31, 0.95, 0.035, TIME, g);
	VERTEX.y += h * calm;
	g *= calm;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	wpos = wp + vec3(0.0, h * calm, 0.0);
	out_from_shore = sd;
}

// Pancake ice: rounded plates with raised rims, drifting a little on the swell.
float pancakes(vec2 p, out float rim) {
	vec2 c = p * 0.62 + vec2(vnoise(p * 0.7), vnoise(p * 0.7 + 7.3)) * 0.6;
	vec2 ci = floor(c);
	float best = 9.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 jitter = vec2(hash12(ci + o), hash12(ci + o + 19.7));
			float d = length(c - ci - o - jitter);
			if (d < best) {
				best = d;
				id = hash12(ci + o + 3.1);
			}
		}
	}
	float size = mix(0.3, 0.52, id);
	rim = smoothstep(size - 0.08, size - 0.02, best) * smoothstep(size + 0.01, size - 0.02, best);
	return smoothstep(size + 0.01, size - 0.03, best) * step(0.2, id);
}

void fragment() {
	float dist = length(CAMERA_POSITION_WORLD - wpos);
	float detail = 1.0 - smoothstep(25.0, 120.0, dist);
	vec2 p = wpos.xz + wind_offset * 0.04;

	// Ripples blown across the swell.
	float e = 0.1;
	float r0 = fbm(p * 0.7);
	float rx = fbm((p + vec2(e, 0.0)) * 0.7);
	float rz = fbm((p + vec2(0.0, e)) * 0.7);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 grad = vec2(rx - r0, rz - r0) / e * (0.12 + 0.18 * wind_strength) * detail;

	// Slush thickening toward the beach, and scattered plates of new ice further out.
	float n = fbm(wpos.xz * 0.06);
	float slush = 1.0 - smoothstep(2.0, 16.0, out_from_shore + (n - 0.5) * 16.0);
	float rim;
	float plates = pancakes(wpos.xz, rim) * (1.0 - smoothstep(10.0, 45.0, out_from_shore + (n - 0.5) * 30.0));
	float ice = clamp(max(slush * (0.55 + 0.45 * vnoise(wpos.xz * 1.3)), plates) + ice_cover, 0.0, 1.0);

	grad *= 1.0 - ice * 0.85;
	wn = normalize(wn + vec3(-grad.x, 0.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	vec3 slush_col = SLUSH * (0.65 + 0.45 * vnoise(wpos.xz * 2.7)) * (1.0 + rim * 0.35);
	ALBEDO = mix(WATER, slush_col, ice);
	ROUGHNESS = mix(0.07, 0.75, ice);
	SPECULAR = 0.5;
}
