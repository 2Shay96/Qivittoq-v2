shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;
// The mountains and the ice cap, kilometers away. They draw their own haze: most of the time
// they are exactly the color of the sky behind them, and only in a lull do they loom out of it.

#include "res://shaders/common.gdshaderinc"

uniform float contrast = 0.5;      // how far this ridgeline can stand out of the haze
uniform float base_height = 0.0;   // its foot is always lost in the haze
uniform float snow_line = 0.62;    // lower means more snow
uniform vec3 rock : source_color = vec3(0.16, 0.17, 0.2);
uniform vec3 snow : source_color = vec3(0.86, 0.89, 0.94);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 view_dir = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 behind = sky_color(view_dir);

	float n = fbm(wpos.xz * 0.004 + wpos.y * 0.002);
	float streak = vnoise(vec2(wpos.x * 0.002 + wpos.z * 0.002, wpos.y * 0.03));
	float on_snow = smoothstep(snow_line - 0.08, snow_line + 0.08, wn.y + (n - 0.5) * 0.5 + (streak - 0.5) * 0.25);
	vec3 base = mix(rock * (0.7 + 0.6 * n), snow, on_snow);
	float lit = 0.3 + 0.55 * clamp(dot(wn, normalize(light_dir)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = base * lit * mountain_light;

	// The feet are always lost in the haze; only the heights come out of it.
	float rise = smoothstep(base_height - 60.0, base_height + 800.0, wpos.y);
	float vis = clamp(mountain_reveal * contrast * rise, 0.0, 1.0);
	ALBEDO = mix(behind, col, vis);
}
