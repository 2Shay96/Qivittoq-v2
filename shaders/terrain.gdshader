shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The ground: snow, dark rock and grey gravel, blended by slope, height and noise.

#include "res://shaders/common.gdshaderinc"

const vec3 SNOW = vec3(0.78, 0.82, 0.88);
const vec3 SNOW_SHADE = vec3(0.56, 0.64, 0.76);
const vec3 ROCK = vec3(0.040, 0.043, 0.050);
const vec3 GRAVEL = vec3(0.13, 0.13, 0.135);
const vec3 WET = vec3(0.035, 0.037, 0.040);

uniform float detail_distance = 40.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Wind ripples in the snow, lying across the wind, with a finer grain on top.
float ripples(vec2 p) {
	vec2 w = normalize(wind_dir);
	vec2 q = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));
	return vnoise(q * vec2(0.3, 0.09)) * 1.6 + vnoise(q * vec2(1.6, 0.4)) * 0.45
		+ vnoise(q * vec2(5.0, 1.4)) * 0.12;
}

// Beach pebbles: rounded stones of different greys, dark in the gaps between them.
vec2 pebbles(vec2 p) {
	vec2 c = p * 15.0;
	vec2 ci = floor(c);
	float best = 9.0;
	float second = 9.0;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 jitter = vec2(hash12(ci + o), hash12(ci + o + 19.7)) * 0.8 + 0.1;
			float d = length(c - ci - o - jitter);
			if (d < best) {
				second = best;
				best = d;
				id = hash12(ci + o + 5.3);
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2(id, best);
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float d_shore = wpos.x - shore_x(wpos.z);
	float big = fbm(wpos.xz * 0.045);
	float mid = vnoise(wpos.xz * 0.6);
	float slope = 1.0 - wn.y;

	// The grey gravel beach, dark and wet at the waterline, with snow lying on it in patches.
	float above_sea = wpos.y + 0.12;
	float beach = (1.0 - smoothstep(0.35, 0.8, above_sea + (big - 0.5) * 0.5)) * (1.0 - smoothstep(10.0, 18.0, d_shore));
	float patches = beach > 0.01 ? smoothstep(0.55, 0.7, fbm(wpos.xz * 0.32) + above_sea * 0.25 - 0.1) : 1.0;
	// Dark rock shows wherever the ground is too steep to hold snow.
	float rock = smoothstep(0.2, 0.32, slope + (big - 0.5) * 0.2 + (mid - 0.5) * 0.06);
	float snow = (1.0 - rock) * mix(1.0, patches, beach);

	vec2 pb = beach > 0.01 && dist < 60.0 ? pebbles(wpos.xz) : vec2(0.5, 0.3);
	// Rounded stones: lighter in the middle, dark where they meet; the pattern melts with distance.
	float stone = mix(0.75, smoothstep(0.75, 0.15, pb.y), 1.0 - smoothstep(6.0, 25.0, dist));
	float grit = vnoise(wpos.xz * 37.0);
	vec3 gravel = GRAVEL * mix(1.0, 0.55 + 0.9 * pb.x, 1.0 - smoothstep(10.0, 30.0, dist))
		* (0.75 + 0.5 * mid) * (0.4 + 0.6 * stone) * (0.85 + 0.3 * grit);
	float wet = 1.0 - smoothstep(0.0, 0.18, above_sea + (mid - 0.5) * 0.08);
	gravel = mix(gravel, WET, wet);
	vec3 rock_col = ROCK * (0.65 + 0.7 * vnoise(wpos.xz * 1.7 + wpos.y * 0.9));
	vec3 ground = mix(gravel, rock_col, rock);

	float detail = 1.0 - smoothstep(detail_distance * 0.3, detail_distance, dist);
	float r0 = dist < detail_distance * 2.5 ? ripples(wpos.xz) : 1.0;
	vec3 snow_col = mix(SNOW_SHADE, SNOW, smoothstep(0.35, 1.5, r0 * 0.7 + big * 0.5));
	ALBEDO = mix(ground, snow_col, snow);

	// Fine relief in the normal, fading out with distance so it never shimmers.
	if (detail > 0.001) {
		float e = 0.04;
		float rx = ripples(wpos.xz + vec2(e, 0.0));
		float rz = ripples(wpos.xz + vec2(0.0, e));
		float amp = mix(0.03, 0.04, snow);
		vec2 grad = vec2(rx - r0, rz - r0) / e * amp * detail;
		wn = normalize(wn + vec3(-grad.x, 0.0, -grad.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}

	// A faint sparkle: now and then an ice crystal catches the light.
	float glint = 0.0;
	vec2 gc = floor(wpos.xz * 24.0);
	if (hash12(gc) > 0.982 && detail > 0.001) {
		vec3 facet = normalize(vec3(hash12(gc + 7.1) - 0.5, 1.1, hash12(gc + 3.3) - 0.5));
		vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
		vec3 refl = reflect(-v, facet);
		glint = smoothstep(0.93, 0.99, dot(refl, normalize(light_dir))) * snow * detail;
	}
	ROUGHNESS = clamp(mix(mix(0.92, 0.5, wet), 0.8, snow) - glint * 0.7, 0.05, 1.0);
	SPECULAR = 0.3 + glint * 0.7;
	EMISSION = vec3(0.9, 0.95, 1.0) * glint * snow_glint;
	SSS_STRENGTH = snow * 0.3;
}
