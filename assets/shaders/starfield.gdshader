shader_type spatial;
// Unshaded: this is a view OUT of the ship, so the ship's own lighting (including the
// red alert state) must not tint it. cull_disabled so a window reads from either side.
render_mode unshaded, cull_disabled, shadows_disabled;

// Driven by ShipMotion — one shared material, so every window agrees on speed and heading.
uniform vec3 travel_direction = vec3(0.0, 0.0, -1.0);
/// Metres travelled. Stars sit at fixed world positions, so advancing this streams them past.
uniform float travelled = 0.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.5;
uniform float brightness : hint_range(0.0, 4.0) = 1.6;
uniform vec4 space_color : source_color = vec4(0.008, 0.010, 0.020, 1.0);
/// Elongates stars along the direction of travel as speed rises.
uniform float streak : hint_range(0.0, 8.0) = 0.0;
/// The destination, drawn as a soft point of light ahead. Brightness 0 hides it.
uniform float destination_brightness : hint_range(0.0, 4.0) = 0.0;
uniform float destination_size : hint_range(0.0005, 0.2) = 0.02;

varying vec3 world_position;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// A view ray through this fragment, so the field parallaxes as the player moves
	// past the window rather than looking like a painted backdrop.
	vec3 ray = normalize(world_position - CAMERA_POSITION_WORLD);
	vec3 dir = normalize(travel_direction);
	vec3 col = space_color.rgb;

	// Five slabs at increasing depth. Sampling the same world offset at different
	// depths gives parallax for free: near stars sweep past faster than far ones.
	// Each slab contributes at most one star per ray, so density comes from small
	// cells (the cell id changes rapidly across the view) rather than from big stars.
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float depth = 6.0 + fi * 8.0;
		float cell = 1.0 + fi * 1.3;

		vec3 p = ray * depth + dir * travelled;
		vec3 id = floor(p / cell);
		vec3 f = fract(p / cell);
		vec3 rnd = hash33(id);
		if (rnd.z > star_density) {
			continue;
		}

		// Distance from the RAY to the star, not from a sample point to the star.
		// Testing "is the sample inside the star" scales coverage with radius CUBED,
		// so small stars are essentially never hit and the field comes out empty.
		// A star is visible when the line of sight passes near it — radius squared.
		// Keep star centres away from cell edges: only the cell containing the sample is
		// tested, so a star straddling a boundary gets sliced and shows as a wedge.
		// Confining centres to [0.2, 0.8] means a 0.07 radius never reaches an edge.
		vec3 star_pos = rnd * 0.6 + vec3(0.2);
		vec3 to_star = f - star_pos;
		vec3 perp = to_star - ray * dot(to_star, ray);
		// Squash along the travel axis so fast travel smears stars into streaks.
		float along = dot(perp, dir);
		vec3 across = perp - dir * along;
		float dist = length(across + dir * (along / (1.0 + streak)));

		float falloff = 1.0 - fi * 0.15;
		// A star is a point, not a blob.
		col += vec3(smoothstep(0.07, 0.0, dist) * (0.35 + 0.65 * rnd.x) * falloff);
	}

	// Destination ahead: a soft disc on the travel axis, driven by step 12's distance.
	if (destination_brightness > 0.001) {
		float aim = max(dot(ray, dir), 0.0);
		col += vec3(smoothstep(1.0 - destination_size, 1.0, aim) * destination_brightness);
	}

	ALBEDO = col * brightness;
}
