// Shared by unit.gdshader and unit_glow.gdshader: moves the rigged parts of a unit or building.
// Each vertex carries its part in UV.x and the part's pivot in (UV.y, UV2.x, UV2.y), set by
// MeshKit.rig. The instance carries the animation: INSTANCE_CUSTOM.z is the cycle phase
// (radians: steps, wing beats, wheel turns), INSTANCE_CUSTOM.w the attack swing (0 none, then
// 0..1 through one blow) and the instance colour's alpha (COLOR.a here) how much it walks.
// The part numbers match Models.P_*.

uniform vec3 slot_cols[9];

mat3 rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 rot_y(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
}

mat3 rot_z(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

// Turns the part forward: what hangs below the pivot swings towards +Z.
mat3 fwd(float a) {
	return rot_x(-a);
}

// One blow: wind up to `up`, strike down to `down`, then back to rest.
float blow(float p, float up, float down) {
	if (p <= 0.0) {
		return 0.0;
	}
	if (p < 0.4) {
		return up * smoothstep(0.0, 0.4, p);
	}
	if (p < 0.6) {
		return mix(up, down, smoothstep(0.4, 0.6, p));
	}
	return down * (1.0 - smoothstep(0.6, 1.0, p));
}

void rig(inout vec3 v, inout vec3 n, vec2 uv, vec2 uv2, float ph, float sw, float walk, float t) {
	int part = int(uv.x + 0.5);
	if (part == 0) {
		return;
	}
	vec3 piv = vec3(uv.y, uv2.x, uv2.y);
	float side = piv.x >= 0.0 ? 1.0 : -1.0;
	float hit = sw > 0.0 ? sin(clamp(sw, 0.0, 1.0) * 3.14159) : 0.0;
	mat3 r = mat3(1.0);
	vec3 move = vec3(0.0);
	if (part == 1) {
		// leg: the two sides step in turn
		r = fwd(sin(ph + (side > 0.0 ? 3.14159 : 0.0)) * 0.55 * walk);
	} else if (part == 2) {
		// weapon arm: swings against the legs, chops on a blow
		r = fwd(sin(ph + (side > 0.0 ? 0.0 : 3.14159)) * 0.35 * walk + blow(sw, 2.3, -0.25));
	} else if (part == 3) {
		// shield arm: swings a little, braces forward on a blow
		r = fwd(sin(ph + (side > 0.0 ? 0.0 : 3.14159)) * 0.25 * walk + hit * 0.35);
	} else if (part == 4) {
		// spear arm: draws back, then thrusts
		float th = sw > 0.0 ? (sw < 0.35 ? -smoothstep(0.0, 0.35, sw) * 0.3 : mix(-0.3, 0.55, smoothstep(0.35, 0.55, sw)) * (1.0 - smoothstep(0.6, 1.0, sw))) : 0.0;
		r = fwd(sin(ph + (side > 0.0 ? 0.0 : 3.14159)) * 0.15 * walk - th * 0.4);
		move = vec3(0.0, 0.0, th);
	} else if (part == 5) {
		// aiming arms (bows, guns, nozzles): kick back as the shot leaves
		r = fwd(sin(ph) * 0.06 * walk - hit * 0.25);
		move = vec3(0.0, 0.0, -hit * 0.1);
	} else if (part == 6) {
		// casting arm: lifted up and forward on a blow, staff and all
		r = fwd(sin(ph + (side > 0.0 ? 0.0 : 3.14159)) * 0.2 * walk + hit * 0.7);
		move = vec3(0.0, hit * 0.3, hit * 0.1);
	} else if (part == 7) {
		// wing: beats on the cycle, harder when flying forward
		r = rot_z(side * (sin(ph) * (0.35 + 0.2 * walk) + 0.05));
	} else if (part == 8) {
		// four legs: diagonal pairs together
		float pair = side * (piv.z >= 0.0 ? 1.0 : -1.0);
		r = fwd(sin(ph + (pair > 0.0 ? 0.0 : 3.14159)) * 0.6 * walk);
	} else if (part == 9) {
		// wheel: rolls with the distance driven
		r = rot_x(ph);
	} else if (part == 10) {
		// barrel or maw: recoils on a shot
		move = vec3(0.0, 0.0, -hit * 0.35);
	} else if (part == 11) {
		// head: nods with the gait, lunges on a bite
		r = fwd(sin(ph * 2.0) * 0.08 * walk - hit * 0.3);
	} else if (part == 12) {
		// tail: sways
		r = rot_y(sin(ph + t * 1.5) * (0.15 + 0.25 * walk));
	} else if (part == 13) {
		// banner: flutters in the wind (buildings get the time as their phase)
		r = rot_y(sin(ph * 2.0 + piv.x * 1.3 + piv.z) * 0.22);
	} else if (part == 14) {
		// gear or rotor: turns about the axis facing +Z
		r = rot_z(ph * 0.6 * side);
	} else if (part == 15) {
		// rotor or orbit: turns about the up axis
		r = rot_y(ph * 0.8);
	}
	v = r * (v - piv) + piv + move;
	n = r * n;
}
