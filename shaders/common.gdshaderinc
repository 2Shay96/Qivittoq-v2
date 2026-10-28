// Shared by Qivittoq's shaders: the wind, the sky, the coastline and some noise.
// The globals are set every frame by scripts/weather.gd and scripts/look.gd.

global uniform vec2 wind_dir;          // where the snow blows to, on the ground plane
global uniform float wind_strength;    // 0 still air, 1 a full blizzard
global uniform vec2 wind_offset;       // how far the wind has carried things so far, in meters
global uniform float gust;             // 0 to 1: how white the near world is right now
global uniform vec3 sky_zenith;        // linear colors
global uniform vec3 sky_horizon;
global uniform float mountain_reveal;  // 0 hidden, 1 a full lull
global uniform vec3 mountain_light;
global uniform vec3 light_dir;         // toward the (hidden) sun or moon
global uniform float snow_glint;
global uniform float fire_heat;        // 0 dead, 1 roaring
global uniform float ice_cover;        // how far the bay has frozen

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x),
		mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x),
		mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s / 0.9375;
}

float fbm3(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise3(p);
		p = p * 2.07 + vec3(17.1, 9.3, 4.7);
		a *= 0.5;
	}
	return s / 0.875;
}

// The coastline: the same curve as shore_x() in scripts/world_builder.gd.
float shore_x(float z) {
	return -30.0 + 5.0 * sin(z * 0.021) + 3.0 * sin(z * 0.053 + 1.3)
		- 16.0 * exp(-pow((z + 70.0) / 22.0, 2.0));
}

// The overcast sky: palest just above the horizon, a little darker overhead, and darker again
// below the horizon where the haze lies over the sea.
vec3 sky_color(vec3 dir) {
	float y = dir.y;
	vec3 c = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.55, y));
	return mix(c, sky_horizon * 0.86, smoothstep(0.0, -0.25, y));
}

// Snow lying on a surface, from its world normal: on top, and plastered on the windward side.
float snow_cover(vec3 wn, vec3 wpos, float amount) {
	float n = vnoise(wpos.xz * 3.1 + wpos.y * 1.7) * 0.6 + vnoise(wpos.xz * 11.0) * 0.4;
	float windward = max(0.0, dot(wn.xz, -normalize(wind_dir))) * 0.35;
	return smoothstep(0.55, 0.85, wn.y + windward + (n - 0.5) * 0.45 + (amount - 0.5) * 0.6);
}

const vec3 SNOW_ON_THINGS = vec3(0.76, 0.8, 0.86);
