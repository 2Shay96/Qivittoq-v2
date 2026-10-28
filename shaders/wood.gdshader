shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Wood: bleached driftwood, logs charring in the fire, the færing's tarred planks, poles.
// UV.x runs along the grain in meters, UV.y around it. COLOR.rgb tints each piece; COLOR.a says
// how close a log lies to the heart of the fire.

#include "res://shaders/common.gdshaderinc"
#include "res://shaders/bump.gdshaderinc"

uniform vec3 base : source_color = vec3(0.52, 0.5, 0.47);
uniform float snow_amount = 0.3;
uniform float char_amount = 0.0;
uniform float grain_depth = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float grain = vnoise(vec2(UV.x * 2.5, UV.y * 38.0)) * 0.6 + vnoise(vec2(UV.x * 9.0, UV.y * 120.0)) * 0.4;
	float split = 1.0 - smoothstep(0.0, 0.04, abs(vnoise(vec2(UV.x * 0.9, UV.y * 9.0)) - 0.5));
	vec3 col = base * COLOR.rgb * (0.7 + 0.45 * grain) * (1.0 - split * 0.55 * grain_depth);

	float ch = char_amount * smoothstep(0.15, 0.85, COLOR.a + (grain - 0.5) * 0.35);
	col = mix(col, vec3(0.018, 0.016, 0.015), ch);
	float embers = smoothstep(0.55, 0.95, ch) * smoothstep(0.55, 0.75, vnoise(vec2(UV.x * 14.0, UV.y * 30.0) + TIME * 0.2));
	EMISSION = vec3(1.0, 0.3, 0.06) * embers * fire_heat * 5.0;

	float sn = snow_cover(wn, wpos, snow_amount) * (1.0 - ch);
	ALBEDO = mix(col, SNOW_ON_THINGS, sn);
	ROUGHNESS = mix(0.82, 0.8, sn);
	SPECULAR = 0.3;
	float h = (grain * 0.006 + split * 0.01) * grain_depth * (1.0 - sn) * (1.0 - smoothstep(4.0, 14.0, length(VERTEX)));
	NORMAL = bump_normal(VERTEX, NORMAL, h);
}
