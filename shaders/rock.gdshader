shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Rock: dark, fractured, flecked with grey lichen, with snow lying on top and plastered on the
// windward side.

#include "res://shaders/common.gdshaderinc"
#include "res://shaders/bump.gdshaderinc"

uniform vec3 base : source_color = vec3(0.15, 0.155, 0.17);
uniform float snow_amount = 0.5;

varying vec3 wpos;
varying vec3 lpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = fbm3(lpos * 2.2);
	float fine = vnoise3(lpos * 21.0);
	float strata = vnoise3(vec3(lpos.x * 0.6, lpos.y * 9.0, lpos.z * 0.6));
	vec3 col = base * (0.5 + 0.8 * n) * (0.85 + 0.3 * fine) * (0.85 + 0.3 * strata);
	float lichen = smoothstep(0.64, 0.7, vnoise3(lpos * 4.0 + 2.0));
	col = mix(col, vec3(0.2, 0.21, 0.2), lichen * 0.6);
	float sn = snow_cover(wn, wpos, snow_amount);
	ALBEDO = mix(col, SNOW_ON_THINGS, sn);
	ROUGHNESS = mix(0.88, 0.8, sn);
	SPECULAR = 0.35;
	SSS_STRENGTH = sn * 0.3;
	float dist = length(VERTEX);
	float h = (n * 0.04 + fine * 0.012 + strata * 0.015) * (1.0 - sn * 0.8) * (1.0 - smoothstep(10.0, 30.0, dist));
	NORMAL = bump_normal(VERTEX, NORMAL, h);
}
