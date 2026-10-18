shader_type spatial;
// Water (or Phyrexian oil): a flat plane with moving ripples, a fresnel sky tint and the same
// fog of war as the ground.
render_mode blend_mix, cull_disabled, shadows_disabled;

uniform vec3 deep : source_color = vec3(0.1, 0.25, 0.35);
uniform vec3 sky : source_color = vec3(0.7, 0.8, 0.9);
uniform float oil = 0.0;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform float map_size = 160.0;
uniform float fog_on = 1.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * (oil > 0.5 ? 0.15 : 0.5);
	float r = noise(wpos.xz * 0.8 + vec2(t, t * 0.7)) * 0.6 + noise(wpos.xz * 2.3 - vec2(t * 1.3, t * 0.4)) * 0.4;
	vec3 c = deep * (0.85 + r * 0.3);
	float spark = smoothstep(0.78, 0.95, r);
	c += sky * spark * (oil > 0.5 ? 0.25 : 0.35);
	if (oil > 0.5) {
		c += vec3(0.25, 0.05, 0.3) * smoothstep(0.4, 0.6, noise(wpos.xz * 0.3 + t)) * 0.3;
	}
	if (fog_on > 0.5) {
		float f = texture(fog_tex, wpos.xz / map_size).r;
		c *= mix(0.06, 1.0, smoothstep(0.0, 0.5, f)) * mix(0.5, 1.0, smoothstep(0.5, 1.0, f));
	}
	ALBEDO = c;
	ROUGHNESS = oil > 0.5 ? 0.05 : 0.12;
	SPECULAR = 0.8;
	ALPHA = 0.88;
}
