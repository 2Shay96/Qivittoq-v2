shader_type canvas_item;
// Frost creeping in from the edges of Eske's sight as he gets colder.

uniform float amount : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.7778;
	float r = length(uv);
	float n = value_noise(UV * 38.0) * 0.55 + value_noise(UV * 95.0) * 0.45;
	float reach = mix(1.15, 0.45, amount);
	float edge = smoothstep(reach, reach + 0.35, r * 1.35 + n * 0.3);
	COLOR = vec4(0.86, 0.93, 1.0, edge * amount * 0.92);
}
