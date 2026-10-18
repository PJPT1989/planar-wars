shader_type spatial;
// Units and buildings, drawn in MultiMeshes. Vertex colour, except that parts painted in the
// marker colour (magenta: equal red and blue, no green) take the owner's team colour from the
// instance's custom data, scaled by the marker's brightness. Custom alpha above zero flashes
// the model (a fresh hit); below zero it darkens it (an unfinished building). With `gloss` on
// (porcelain, brass, oil) it also gets a sharp highlight and a cheap reflection of the sky.
render_mode cull_back;

uniform float gloss = 0.0;
uniform vec3 sky_top : source_color = vec3(0.3, 0.45, 0.8);
uniform vec3 sky_horizon : source_color = vec3(0.8, 0.82, 0.88);
uniform vec3 sky_ground : source_color = vec3(0.3, 0.3, 0.25);

varying vec4 team;

void vertex() {
	team = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float marker = step(COLOR.g, 0.03) * step(abs(COLOR.r - COLOR.b), 0.03) * step(0.25, COLOR.r);
	c = mix(c, team.rgb * COLOR.r, marker);
	c *= 1.0 + min(team.a, 0.0);
	ALBEDO = c;
	ROUGHNESS = mix(0.72, 0.18, gloss);
	METALLIC = 0.25 * gloss;
	SPECULAR = mix(0.45, 0.8, gloss);
	vec3 em = vec3(max(team.a, 0.0)) * 0.5;
	if (gloss > 0.0) {
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 r = reflect(-v, n);
		vec3 env = r.y > 0.0 ? mix(sky_horizon, sky_top, sqrt(r.y)) : mix(sky_horizon, sky_ground, sqrt(-r.y) * 1.5);
		float fres = 0.1 + 0.9 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
		em += env * fres * 0.45 * gloss;
	}
	EMISSION = em;
}
