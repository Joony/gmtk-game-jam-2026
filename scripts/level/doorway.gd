class_name Doorway
extends Resource

# A gap cut through a wall, with a lintel above it. Ported from the wall-intersection
# maths in GMTK 2025's V1/SlidingDoor.gd; the sliding panels, control panel, detection
# area and animation state stayed behind (that was DoorManager's job, and we don't
# need moving doors yet).
#
# Renamed from SlidingDoor because nothing here slides — it cuts an opening.

## Which axis the opening SPANS. A doorway spanning X cuts walls that run along X
## (a room's north/south walls); one spanning Z cuts west/east walls.
enum Axis { X, Z }

@export var position: Vector2 = Vector2.ZERO
@export var axis: Axis = Axis.X
## Opening width in grid units.
@export var width: float = 1.6
@export var id: String = ""


func _init(pos: Vector2 = Vector2.ZERO, span_axis: Axis = Axis.X, opening_width: float = 1.6, doorway_id: String = "") -> void:
	position = pos
	axis = span_axis
	width = opening_width
	id = doorway_id if doorway_id != "" else "door_%.1f_%.1f" % [pos.x, pos.y]


## The opening's extent along its span axis, in grid coordinates.
func bounds() -> Dictionary:
	var half := width * 0.5
	if axis == Axis.X:
		return {"start": Vector2(position.x - half, position.y), "end": Vector2(position.x + half, position.y)}
	return {"start": Vector2(position.x, position.y - half), "end": Vector2(position.x, position.y + half)}


## True when this opening lies on the given wall and overlaps it. The wall must run
## along the same axis the opening spans.
func intersects_wall(wall_start: Vector2, wall_end: Vector2, tolerance: float = 0.05) -> bool:
	var wall_runs_along_x := absf(wall_end.x - wall_start.x) > absf(wall_end.y - wall_start.y)
	var half := width * 0.5

	if wall_runs_along_x and axis == Axis.X:
		if absf(position.y - wall_start.y) >= tolerance:
			return false
		return position.x + half > minf(wall_start.x, wall_end.x) \
			and position.x - half < maxf(wall_start.x, wall_end.x)

	if not wall_runs_along_x and axis == Axis.Z:
		if absf(position.x - wall_start.x) >= tolerance:
			return false
		return position.y + half > minf(wall_start.y, wall_end.y) \
			and position.y - half < maxf(wall_start.y, wall_end.y)

	return false
