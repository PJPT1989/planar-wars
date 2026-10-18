shader_type spatial;
// Gloss: Phyrexian porcelain, glistening oil and polished armour. Vertex colour, a sharp sun
// highlight and a cheap reflection of the plane's sky (three gradient colours, set per plane),
// stronger at grazing angles. Dark colours (oil, black steel) read as wetter and glossier.

uniform vec3 sky_top : source_color = vec3(0.2, 0.3, 0.6);
uniform vec3 sky_horizon : source_color = vec3(0.7, 0.75, 0.85);
uniform vec3 sky_ground : source_color = vec3(0.2, 0.2, 0.2);
uniform float reflect_strength = 0.5;

void fragment() {
	ALBEDO = COLOR.rgb;
	float dark = 1.0 - clamp(dot(COLOR.rgb, vec3(0.33)) * 2.0, 0.0, 1.0);
	ROUGHNESS = mix(0.3, 0.08, dark);
	METALLIC = mix(0.15, 0.45, dark);
	SPECULAR = 0.8;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec3 env = r.y > 0.0 ? mix(sky_horizon, sky_top, sqrt(r.y)) : mix(sky_horizon, sky_ground, sqrt(-r.y) * 1.5);
	float fres = 0.1 + 0.9 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
	EMISSION = env * fres * reflect_strength * mix(0.5, 1.3, dark);
}
