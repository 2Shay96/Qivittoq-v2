shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Walrus: thick wrinkled hide, and where the hunters cut, blubber and raw meat.
// COLOR.rgb holds the color of each part; COLOR.a is 1 where the flesh is wet.

#include "res://shaders/common.gdshaderinc"
#include "res://shaders/bump.gdshaderinc"

uniform float snow_amount = 0.35;

varying vec3 wpos;
varying vec3 lpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float wrinkles = vnoise(vec2(lpos.x * 14.0, (lpos.y + lpos.z) * 4.0)) * 0.6 + vnoise3(lpos * 30.0) * 0.4;
	float blotch = fbm3(lpos * 2.0);
	vec3 col = COLOR.rgb * COLOR.rgb * (0.75 + 0.35 * blotch) * (0.85 + 0.25 * wrinkles);  // sRGB to linear
	float wet = COLOR.a;
	float sn = snow_cover(wn, wpos, snow_amount) * (1.0 - wet * 0.7) * 0.45;  // a dusting, no more
	ALBEDO = mix(col, SNOW_ON_THINGS, sn);
	ROUGHNESS = mix(mix(0.7, 0.32, wet), 0.8, sn);
	SPECULAR = mix(0.4, 0.6, wet);
	float h = wrinkles * 0.012 * (1.0 - sn) * (1.0 - smoothstep(4.0, 14.0, length(VERTEX)));
	NORMAL = bump_normal(VERTEX, NORMAL, h);
}
