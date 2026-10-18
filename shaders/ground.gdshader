shader_type spatial;
// Ground: vertex colour broken up by world-space noise at three scales, so the ground stays
// crisp up close without any texture files. UV.x is how paved a vertex is (cobbles), UV.y how
// rocky (cracked cliff stone). The fog of war texture darkens what the player has not seen.

uniform float detail = 1.0;
uniform vec3 cobble_dark : source_color = vec3(0.2, 0.18, 0.16);
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 160.0;
uniform float fog_on = 1.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.0));   // map colours are written in sRGB
	float n1 = noise(wpos.xz * 0.35);
	float n2 = noise(wpos.xz * 1.9);
	float n3 = noise(wpos.xz * 7.0);
	c *= 1.0 + ((n1 - 0.5) * 0.25 + (n2 - 0.5) * 0.2 + (n3 - 0.5) * 0.14) * detail;
	float pave = UV.x;
	if (pave > 0.02) {
		float e = cells(wpos.xz * 1.1);
		float seam = 1.0 - smoothstep(0.02, 0.1, e);
		c = mix(c, cobble_dark, seam * pave * 0.7);
		c *= 1.0 + (hash(floor(wpos.xz * 1.1)) - 0.5) * 0.2 * pave;
	}
	float rock = UV.y;
	if (rock > 0.02) {
		float e = cells(wpos.xz * 0.6 + wpos.y * 0.3);
		c *= 1.0 - (1.0 - smoothstep(0.0, 0.08, e)) * 0.45 * rock;
	}
	if (fog_on > 0.5) {
		float f = texture(fog_tex, wpos.xz / map_size).r;
		c *= mix(0.06, 1.0, smoothstep(0.0, 0.5, f)) * mix(0.5, 1.0, smoothstep(0.5, 1.0, f));
	}
	ALBEDO = c;
	ROUGHNESS = 0.93;
	SPECULAR = 0.2;
}
