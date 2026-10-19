shader_type spatial;
// Glowing parts of units and buildings (eyes, aether, magic): like glow.gdshader, but moved
// with the rigged parts (rig.gdshaderinc) and dimmed on corpses.
render_mode unshaded, cull_back;

#include "res://shaders/rig.gdshaderinc"

uniform float energy = 2.2;

varying float dim;

void vertex() {
	rig(VERTEX, NORMAL, UV, UV2, INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w, COLOR.a, TIME);
	COLOR.a = 1.0;
	dim = 1.0 + min(INSTANCE_CUSTOM.y, 0.0) * 2.0;
}

void fragment() {
	ALBEDO = COLOR.rgb * energy * max(dim, 0.1);
}
