shader_type spatial;
// Unshaded: this is a view OUT of the ship, so the ship's own lighting (including the
// red alert state) must not tint it. cull_disabled so a window reads from either side.
render_mode unshaded, cull_disabled, shadows_disabled;

// Driven by ShipMotion — one shared material, so every window agrees on speed and heading.
uniform vec3 travel_direction = vec3(0.0, 0.0, -1.0);
/// Metres travelled. Stars sit at fixed world positions, so advancing this streams them past.
uniform float travelled = 0.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.85;
uniform float brightness : hint_range(0.0, 4.0) = 1.6;
uniform vec4 space_color : source_color = vec4(0.006, 0.008, 0.016, 1.0);
/// Elongates stars along the direction of travel as speed rises.
uniform float streak : hint_range(0.0, 12.0) = 0.0;
/// Apparent size of a star, in radians. Small: a star is a point of light, not a disc.
uniform float star_angular_size : hint_range(0.0002, 0.02) = 0.0018;
/// World spacing of the star grid, and how far out the field is sampled.
uniform float cell_size = 45.0;
/// Stars start FAR away. Close stars sweep across the view in a second and read as
/// specks flying past the hull rather than a distant sky.
uniform float near_distance = 15.0;
/// The destination, drawn as a soft point of light ahead. Brightness 0 hides it.
uniform float destination_brightness : hint_range(0.0, 4.0) = 0.0;
uniform float destination_size : hint_range(0.0005, 0.2) = 0.02;

// Marching this many cells along the ray. Step length == cell size, so every cell the
// ray passes through IS sampled — that is what stops stars popping in and out.
const int STEPS = 24;

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
	// The ship's position within the star field. Stars are fixed; we move.
	vec3 eye = dir * travelled;
	vec3 col = space_color.rgb;

	// March cell by cell along the ray. Previously a single sample per depth slab meant
	// a star was only visible while it sat in that one thin slice, so stars appeared,
	// drifted briefly and vanished. Marching keeps each star visible for as long as the
	// line of sight actually passes near it.
	for (int i = 0; i < STEPS; i++) {
		float t = near_distance + float(i) * cell_size;
		vec3 id = floor((ray * t + eye) / cell_size);
		vec3 rnd = hash33(id);
		if (rnd.z > star_density) {
			continue;
		}

		// Star centres are held away from cell edges so a star cannot be sliced by a
		// boundary (only the cell containing the sample is tested). The margin must
		// scale with the star's WORLD radius, which grows with distance: a fixed
		// margin is enormous at close range — at 15m a 20% margin spans ~69 degrees of
		// view — and carves a cross of empty sky along the world axes through the eye.
		// Sized this way the dead band is a constant ~3x the star size, i.e. invisible.
		float margin = clamp(star_angular_size * t / cell_size * 1.5, 0.004, 0.25);
		vec3 star = (id + rnd * (1.0 - 2.0 * margin) + vec3(margin)) * cell_size;
		vec3 rel = star - eye;
		float along = dot(rel, ray);
		if (along < 1.0) {
			continue;
		}

		// ANGULAR distance from the line of sight: this is what makes stars read as
		// distant points. A star far away is small; the same star close is large.
		vec3 offset = rel - ray * along;
		// Smear along the travel axis with speed.
		float axial = dot(offset, dir);
		vec3 lateral = offset - dir * axial;
		float angle = length(lateral + dir * (axial / (1.0 + streak))) / along;

		// Fade to NOTHING at both ends of the marched range. A hard cutoff makes stars
		// wink out as they cross the limit, which is most of what reads as flicker.
		float far_limit = near_distance + float(STEPS) * cell_size;
		float fade = smoothstep(far_limit, far_limit * 0.5, along)
			* smoothstep(near_distance * 0.6, near_distance * 2.0, along);
		col += vec3(smoothstep(star_angular_size, 0.0, angle) * (0.25 + 0.75 * rnd.x) * fade);
	}

	// Destination ahead: a soft disc on the travel axis, driven by step 12's distance.
	if (destination_brightness > 0.001) {
		float aim = max(dot(ray, dir), 0.0);
		col += vec3(smoothstep(1.0 - destination_size, 1.0, aim) * destination_brightness);
	}

	ALBEDO = col * brightness;
}
