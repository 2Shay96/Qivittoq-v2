shader_type fog;
// The near blizzard: a volume of blowing snow that travels with Eske. Its density follows the
// gusts, carried along by the wind, so a gust whites out the world and then eases.

#include "res://shaders/common.gdshaderinc"

uniform sampler3D puffs : repeat_enable, filter_linear;
uniform float base_density = 0.006;
uniform float gust_density = 0.34;
uniform float ground_y = 0.0;

void fog() {
	vec3 p = WORLD_POSITION;
	vec3 q = vec3(p.x - wind_offset.x, p.y * 1.4 + TIME * 0.4, p.z - wind_offset.y);
	float n = texture(puffs, q * 0.019).r;
	float n2 = texture(puffs, q * 0.061 + vec3(0.31, 0.17, 0.53)).r;
	float cloud = smoothstep(0.25, 0.85, n * 0.7 + n2 * 0.3);
	// Thickest near the ground, where the drift streams.
	float height = clamp(1.25 - (p.y - ground_y) / 22.0, 0.1, 1.0);
	// No hard walls at the edges of the box.
	float edge = 1.0 - smoothstep(0.75, 1.0, length(UVW.xz * 2.0 - 1.0));
	float d = base_density * (0.5 + cloud) + gust_density * gust * (0.3 + 0.7 * cloud)
		+ 0.012 * wind_strength * cloud;
	DENSITY = d * height * edge;
	ALBEDO = vec3(1.0);
}
