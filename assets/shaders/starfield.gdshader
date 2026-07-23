shader_type spatial;
// Unshaded: this is a view OUT of the ship, so the ship's own lighting (including the
// red alert state) must not tint it. cull_disabled so a window reads from either side.
render_mode unshaded, cull_disabled, shadows_disabled;

// Driven by ShipMotion — one shared material, so every window agrees on speed and heading.
uniform vec3 travel_direction = vec3(0.0, 0.0, -1.0);
/// Metres travelled. Stars sit at fixed world positions, so advancing this streams them past.
uniform float travelled = 0.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.15;
uniform float brightness : hint_range(0.0, 4.0) = 1.6;
uniform vec4 space_color : source_color = vec4(0.006, 0.008, 0.016, 1.0);
/// Elongates stars along the direction of travel as speed rises.
uniform float streak : hint_range(0.0, 40.0) = 0.0;
/// Apparent size of a star, in radians. Small: a star is a point of light, not a disc.
uniform float star_angular_size : hint_range(0.0002, 0.02) = 0.0018;
/// World spacing of the star grid, and how far out the field is sampled.
uniform float cell_size = 45.0;
/// Stars start FAR away. Close stars sweep across the view in a second and read as
/// specks flying past the hull rather than a distant sky.
uniform float near_distance = 15.0;
// --- Nebula ---------------------------------------------------------------------
// Computed from the view DIRECTION only, never from position, so it behaves as if
// infinitely far away: it does not slide past as the ship travels, which is correct
// for a galaxy. That is exactly what a skybox would give, without needing one.
/// Perpendicular to the galactic plane. Tilted so the band does not sit parallel to
/// any world axis, which would read as artificial.
uniform vec3 nebula_pole = vec3(0.35, 0.9, -0.25);
uniform vec4 nebula_color : source_color = vec4(0.09, 0.15, 0.38, 1.0);
uniform vec4 nebula_core_color : source_color = vec4(0.30, 0.20, 0.46, 1.0);
uniform float nebula_strength : hint_range(0.0, 3.0) = 1.5;
/// Half-thickness of the band, as |cos| from the galactic plane. Larger is wider.
uniform float nebula_width : hint_range(0.05, 1.0) = 0.55;
uniform float nebula_scale : hint_range(0.5, 12.0) = 3.0;

/// The destination, drawn as a soft point of light ahead. Brightness 0 hides it.
uniform float destination_brightness : hint_range(0.0, 4.0) = 0.0;
uniform float destination_size : hint_range(0.0005, 0.2) = 0.02;

// Marching this many cells along the ray. Step length == cell size, so every cell the
// ray passes through IS sampled — that is what stops stars popping in and out.
const int STEPS = 24;

varying vec3 world_position;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// Three octaves is enough for soft cloud structure and keeps the cost down — the
// shell can cover a lot of screen before the walls reject it by depth.
float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

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

	// Galactic band. Direction-only, so it sits at infinity and never slides past.
	vec3 pole = normalize(nebula_pole);
	float from_plane = abs(dot(ray, pole));
	float band = smoothstep(nebula_width, 0.0, from_plane);
	if (band > 0.001) {
		float clouds = fbm(ray * nebula_scale);
		// A second, coarser layer carves dust lanes so the band is not a smooth smear.
		float lanes = smoothstep(0.30, 0.62, fbm(ray * (nebula_scale * 0.55) + vec3(11.7)));
		float density = band * smoothstep(0.34, 0.78, clouds) * mix(0.35, 1.0, lanes);
		vec3 tint = mix(nebula_color.rgb, nebula_core_color.rgb, smoothstep(0.45, 0.85, clouds));
		// Deliberately dim: this is depth behind the stars, not a light source.
		col += tint * density * nebula_strength;
	}

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

		// Smear with speed, along the direction the star APPEARS to move — which is
		// away from the point you are travelling toward, not along the travel axis.
		// Stretching along `dir` itself does nothing when looking straight ahead
		// (offsets are perpendicular to the ray, hence to `dir` too), so head-on there
		// were no streaks at all. Projecting `dir` into the plane perpendicular to the
		// ray gives radial streaks ahead and lateral ones out of a side window, both
		// from one expression.
		float angle;
		vec3 stretch = dir - ray * dot(dir, ray);
		float stretch_len = length(stretch);
		if (stretch_len > 0.0001 && streak > 0.001) {
			stretch /= stretch_len;
			float axial = dot(offset, stretch);
			vec3 lateral = offset - stretch * axial;
			angle = length(lateral + stretch * (axial / (1.0 + streak))) / along;
		} else {
			// Dead ahead there is no apparent motion, so no stretch.
			angle = length(offset) / along;
		}

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
