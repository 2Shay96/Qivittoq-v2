shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Woven canvas and hides. The canvas lets light through from behind, so the fire glows through
// the tent from outside and the candle from inside. COLOR.a says how free the cloth is to move.
// UVs are in meters.

#include "res://shaders/common.gdshaderinc"
#include "res://shaders/bump.gdshaderinc"

uniform vec3 base : source_color = vec3(0.4, 0.38, 0.34);
uniform float weave = 1.0;
uniform float flutter = 0.0;
uniform float snow_amount = 0.5;
uniform float glow_through = 0.6;
uniform float fur = 0.0;

varying vec3 wpos;

void vertex() {
	float w = flutter * COLOR.a * (0.25 + wind_strength * 0.6 + gust * 1.4);
	float ripple = sin(TIME * 6.3 + VERTEX.x * 3.1 + VERTEX.y * 2.3) * 0.6
		+ sin(TIME * 10.7 + VERTEX.x * 6.7 - VERTEX.z * 2.1) * 0.4;
	VERTEX += NORMAL * ripple * w * 0.018;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float cycles = max(fwidth(UV.x), fwidth(UV.y)) * 420.0 / 6.2832;
	float fine = 1.0 - smoothstep(0.15, 0.4, cycles);
	float threads = mix(0.25, (sin(UV.x * 420.0) * 0.5 + 0.5) * (sin(UV.y * 420.0 + sin(UV.x * 3.0)) * 0.5 + 0.5), fine);
	float stains = fbm(UV * 1.3);
	float hair = vnoise(vec2(UV.x * 90.0, UV.y * 12.0));
	float slub = vnoise(vec2(UV.x * 60.0, UV.y * 7.0)) * 0.5 + vnoise(vec2(UV.x * 7.0, UV.y * 60.0)) * 0.5;
	vec3 col = base * (0.9 + 0.12 * slub * weave + 0.04 * threads * weave) * (0.72 + 0.4 * stains);
	col *= mix(1.0, 0.7 + 0.5 * hair, fur);
	float drift = fbm(wpos.xz * 1.7 + wpos.y * 0.9);
	float dust = smoothstep(0.25, 0.95, wn.y + (drift - 0.5) * 0.45 + (snow_amount - 0.5) * 0.5);
	float sn = FRONT_FACING ? dust * 0.85 : 0.0;
	ALBEDO = mix(col, SNOW_ON_THINGS, sn);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	BACKLIGHT = base * glow_through * (1.0 - sn);
	float h = (threads * 0.0004 * weave + slub * 0.0012 * weave + hair * 0.006 * fur) * (1.0 - smoothstep(2.0, 8.0, length(VERTEX)));
	NORMAL = bump_normal(VERTEX, NORMAL, h);
}
