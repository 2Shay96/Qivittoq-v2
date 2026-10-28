shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;
// Blowing snow, drawn three ways from one shader:
//   0  fine streaks, stretched along their flight like a short exposure
//   1  big flakes tumbling past close to the eyes
//   2  spindrift: low sheets of snow streaming along the ground

#include "res://shaders/common.gdshaderinc"

uniform int mode = 0;
uniform float size = 0.012;
uniform float opacity = 0.6;
uniform vec3 tint : source_color = vec3(0.93, 0.95, 1.0);

varying float fade;
varying float seed;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	float d = max(length(to_cam), 0.001);
	to_cam /= d;
	vec2 c = vec2(UV.x - 0.5, 0.5 - UV.y);
	vec3 wp;
	if (mode == 0) {
		vec3 axis = normalize(MODEL_MATRIX[1].xyz);
		vec3 side = normalize(cross(axis, to_cam));
		float len = (0.06 + 0.42 * wind_strength) * s;
		wp = center + side * c.x * size * s * 2.0 + axis * c.y * len;
	} else if (mode == 1) {
		vec3 right = INV_VIEW_MATRIX[0].xyz;
		vec3 up = INV_VIEW_MATRIX[1].xyz;
		wp = center + (right * c.x + up * c.y) * size * s * 2.0;
	} else {
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
		wp = center + side * c.x * size * s * 2.0 + vec3(0.0, (c.y + 0.5) * size * s * 0.3, 0.0);
	}
	VERTEX = wp;
	// Lit like the snow they came from, from above, so a flake against the sky never turns dark.
	NORMAL = normalize(to_cam * 0.4 + vec3(0.0, 1.0, 0.0));
	float near = mode == 1 ? smoothstep(0.08, 0.35, d) : smoothstep(0.3, 1.2, d);
	fade = near * (1.0 - smoothstep(26.0, 40.0, d)) * COLOR.a;
	seed = float(INSTANCE_ID) * 0.6180339;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float a;
	if (mode == 0) {
		a = (1.0 - c.x * c.x) * (1.0 - c.y * c.y);
	} else if (mode == 1) {
		a = smoothstep(1.0, 0.15, length(c));
	} else {
		vec2 p = vec2(UV.x * 2.5 + fract(seed) * 10.0 + TIME * 0.6, UV.y * 1.2);
		float wisps = smoothstep(0.35, 0.8, fbm(p * 2.0));
		a = wisps * (1.0 - c.x * c.x) * smoothstep(-1.0, 0.2, c.y) * smoothstep(1.0, 0.5, c.y);
	}
	ALBEDO = tint;
	ALPHA = clamp(a * opacity * fade, 0.0, 1.0);
}
