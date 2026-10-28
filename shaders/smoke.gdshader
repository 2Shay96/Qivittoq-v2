shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;
// Smoke from the fire: soft lit billboards, thicker and darker when blubber burns.

#include "res://shaders/common.gdshaderinc"

uniform float size = 0.9;
uniform vec3 tint : source_color = vec3(0.26, 0.26, 0.27);

varying float seed;
varying float life;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec2 c = vec2(UV.x - 0.5, 0.5 - UV.y);
	VERTEX = center + (INV_VIEW_MATRIX[0].xyz * c.x + INV_VIEW_MATRIX[1].xyz * c.y) * size * s;
	NORMAL = normalize(CAMERA_POSITION_WORLD - center);
	seed = float(INSTANCE_ID) * 0.6180339;
	life = COLOR.a;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float n = fbm(UV * 2.2 + vec2(fract(seed) * 9.0, -TIME * 0.15));
	float a = smoothstep(1.0, 0.2, length(c) + (n - 0.5) * 0.7);
	ALBEDO = tint;
	ALPHA = clamp(a * life, 0.0, 1.0);
}
