// Plain lit tube material for cables (ADR 0045 two-real-room renderer).
//
// The straddle renderer no longer separates a tube's two halves in a shader:
// each half is REAL geometry built at its real world position in its real room
// (the near mesh in room A, the far mesh in room B — the latter shown through
// the portal by the room-B portal camera). So this shader is just a plain lit
// albedo + emission material; there is no portal-plane clip and no run-filter.
// (The old PORTALCLIP include and run_filter/run_keep uniforms are gone with the
// shared-mesh scheme they served.)
//
// emission_energy is driven by Cable3D's power code (0 when dead, a warm glow
// when the cable carries power).
//
// cull_disabled: the tube is a thin open surface, so rendering both faces shows
// the wall rather than a hole at an open end.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.13, 0.13, 0.15, 1.0);
uniform vec4 emission_color : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform float emission_energy = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = emission_color.rgb * emission_energy;
}
