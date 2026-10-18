shader_type spatial;
// Effects drawn in MultiMeshes (selection rings, order markers, dust, sparks, projectiles):
// unlit, coloured and faded by the instance's custom data, vertex colour as a pattern.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float glow = 1.0;
varying vec4 tint;

void vertex() {
	tint = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb * glow;
	ALPHA = clamp(tint.a * COLOR.a, 0.0, 1.0);
}
