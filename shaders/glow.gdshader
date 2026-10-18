shader_type spatial;
// Aether glow: vertex colour, unlit and brighter than white so the glow pass picks it up.
render_mode unshaded, cull_back;

uniform float energy = 2.2;

void fragment() {
	ALBEDO = COLOR.rgb * energy;
}
