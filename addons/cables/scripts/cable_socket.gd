class_name CableSocket
extends Node3D
## A snap point a cable plug seats into: pure bookkeeping + a runtime-built
## receptacle visual. The socket is NOT a physics body (v1) — the PLUG drives
## the physical part of seating (freeze + server transform set) and calls
## seat()/unseat() here; the socket only tracks occupancy and emits signals.
## Plug parameters are duck-typed Node3D so the addon stays game-independent.
##
## ORIENTATION CONVENTION: snap_transform() is this node's own global_transform,
## taken verbatim by the seated plug's body. A plug's nose is its local -Z, so
## author a socket with -Z pointing INTO the mounting surface (+Z facing out
## into the room): the plug then seats nose-first into the mount.
##
## POWER: `powered` is is_power_source OR an external feed via set_fed() (the
## cable propagates one hop, Cable3D._recompute_power); transitions emit
## power_changed. A source announces power_changed(true) once at ready
## (deferred, so listeners connected in their own _ready still receive it).

signal plugged(plug: Node3D)
signal unplugged(plug: Node3D)
signal power_changed(is_powered: bool)

## A held plug within this distance of the socket origin snaps on release.
@export var snap_radius := 0.35
## A source is always powered and (Phase 4) feeds whatever plugs into it.
@export var is_power_source := false

## The seated plug, or null while the socket is free.
var occupied_by: Node3D = null
## True while this socket is a source or is externally fed (see set_fed).
var powered := false

var _preview: MeshInstance3D = null


func _ready() -> void:
	add_to_group("cable_sockets")
	powered = is_power_source
	if is_power_source:
		# Deferred so adapters/listeners that connect in their own _ready
		# (possibly later in tree order) still get the initial announcement.
		power_changed.emit.call_deferred(true)
	_build_visuals()


## External power feed (Phase 4 propagation calls this). A source stays
## powered regardless of the feed.
func set_fed(fed: bool) -> void:
	var now := is_power_source or fed
	if now == powered:
		return
	powered = now
	power_changed.emit(powered)


## The global transform a seated plug's BODY takes (see the orientation
## convention above).
func snap_transform() -> Transform3D:
	return global_transform


## The first PhysicsBody3D above this socket in the tree, or null for a
## free-standing / non-body mount. This is what distinguishes a SEATED end
## from an ATTACHED one (ADR 0046): a socket with no body (or a static one)
## makes the seated plug an infinite-mass anchor — no cable force applies —
## while a socket mounted on a dynamic body (e.g. a cube face) makes that
## MOUNT the receiver of the cable's endpoint tension, so a taut cable drags
## the cube around by its socket.
func mount_body() -> PhysicsBody3D:
	var node := get_parent()
	while node != null:
		var body := node as PhysicsBody3D
		if body != null:
			return body
		node = node.get_parent()
	return null


func can_accept(plug: Node3D) -> bool:
	return plug != null and occupied_by == null


## Claim the socket for `plug`. Bookkeeping only — the plug has already frozen
## and moved itself onto snap_transform().
func seat(plug: Node3D) -> void:
	occupied_by = plug
	plugged.emit(plug)


## Release the seated plug (bookkeeping only; the plug unfreezes itself).
func unseat() -> void:
	if occupied_by == null:
		return
	var plug := occupied_by
	occupied_by = null
	unplugged.emit(plug)


## Toggle the snap-preview highlight a held plug lights while in snap range.
func set_preview(on: bool) -> void:
	if _preview != null:
		_preview.visible = on


## Runtime-built receptacle ring + hidden preview ring, so .tscn authoring
## stays a bare CableSocket node.
func _build_visuals() -> void:
	# A torus lies in the local XZ plane (hole along Y); rotate it to face ±Z.
	var facing := Basis(Vector3.RIGHT, PI / 2.0)

	var ring := MeshInstance3D.new()
	ring.name = "Receptacle"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.05
	ring_mesh.outer_radius = 0.09
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.12, 0.12, 0.14)
	ring_mat.metallic = 0.6
	ring_mat.roughness = 0.4
	ring.material_override = ring_mat
	ring.transform = Transform3D(facing, Vector3.ZERO)
	add_child(ring)

	_preview = MeshInstance3D.new()
	_preview.name = "SnapPreview"
	var glow_mesh := TorusMesh.new()
	glow_mesh.inner_radius = 0.09
	glow_mesh.outer_radius = 0.13
	_preview.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = Color(0.2, 0.9, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.2, 0.9, 1.0)
	glow_mat.emission_energy_multiplier = 2.0
	_preview.material_override = glow_mat
	_preview.transform = Transform3D(facing, Vector3.ZERO)
	_preview.visible = false
	add_child(_preview)
