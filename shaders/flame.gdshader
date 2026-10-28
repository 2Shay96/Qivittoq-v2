shader_type spatial;
render_mode world_vertex_coords, blend_premul_alpha, depth_draw_never, cull_disabled, unshaded, fog_disabled;
// Tongues of flame on upright billboards, and the sparks and smoke above a fire.
//   0  flame   1  spark   2  smoke (blended, not added)

#include "res://shaders/common.gdshaderinc"

uniform int mode = 0;
uniform float width = 0.32;
uniform float height = 0.55;
uniform float intensity = 1.0;

varying float seed;
varying float life;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 up = mode == 1 ? INV_VIEW_MATRIX[1].xyz : vec3(0.0, 1.0, 0.0);
	if (mode == 1) {
		side = INV_VIEW_MATRIX[0].xyz;
	}
	vec2 c = vec2(UV.x - 0.5, 0.5 - UV.y);
	VERTEX = center + side * c.x * width * s + up * (c.y + (mode == 0 ? 0.45 : 0.0)) * height * s;
	seed = float(INSTANCE_ID) * 0.6180339;
	life = COLOR.a;
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec3 col;
	if (mode == 0) {
		float n = fbm(vec2(uv.x * 2.0 + fract(seed) * 7.0, uv.y * 1.3 - TIME * 2.0));
		float x = (uv.x - 0.5) * 2.0 + (n - 0.5) * 0.8 * uv.y;
		float w = mix(0.95, 0.12, pow(uv.y, 0.8));
		float body = 1.0 - smoothstep(0.0, w, abs(x));
		body *= smoothstep(0.0, 0.25, uv.y) * (1.0 - smoothstep(0.3, 1.0, uv.y + (n - 0.5) * 0.45));
		vec3 edge = vec3(0.85, 0.2, 0.035);
		vec3 core = vec3(1.0, 0.6, 0.24);
		col = mix(edge, core, body) * body * 1.3 * life;
		ALPHA = clamp(body * life * 0.55, 0.0, 1.0);
	} else {
		float d = length(UV * 2.0 - 1.0);
		col = vec3(1.0, 0.55, 0.18) * 5.0 * smoothstep(1.0, 0.0, d) * life;
		ALPHA = 0.0;
	}
	ALBEDO = col * intensity;
}
