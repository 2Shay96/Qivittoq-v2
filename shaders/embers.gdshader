shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The bed of the fire: ash and charcoal, glowing through its cracks while the fire lives.

#include "res://shaders/common.gdshaderinc"

uniform float heat = 1.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec2 p = lpos.xz * 9.0;
	float n = fbm(p + vec2(0.0, TIME * 0.05));
	float cracks = 1.0 - smoothstep(0.0, 0.08, abs(vnoise(p * 1.7 + 3.0) - 0.5));
	float centre = 1.0 - smoothstep(0.05, 0.4, length(lpos.xz));
	float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + n * 12.0);
	float glow = clamp((cracks * 0.7 + smoothstep(0.55, 0.8, n) * 0.6) * centre * pulse, 0.0, 1.0);
	vec3 ash = mix(vec3(0.03, 0.028, 0.027), vec3(0.12, 0.12, 0.12), smoothstep(0.2, 0.45, length(lpos.xz)) * n);
	ALBEDO = ash;
	ROUGHNESS = 1.0;
	EMISSION = vec3(1.0, 0.33, 0.07) * glow * glow * 7.0 * heat;
}
