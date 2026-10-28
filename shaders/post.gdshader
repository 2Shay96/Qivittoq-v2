shader_type canvas_item;
// Over the whole picture: a soft vignette and very faint film grain. No dithering.

uniform float vignette = 0.38;
uniform float grain = 0.03;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(0.3, 1.05, length(uv) * 1.15) * vignette;
	float g = hash(FRAGCOORD.xy + fract(TIME * 7.3) * 413.0);
	float a = v + grain * (1.0 - v);
	COLOR = vec4(vec3(g) * grain * (1.0 - v) / max(a, 0.0001), a);
}
