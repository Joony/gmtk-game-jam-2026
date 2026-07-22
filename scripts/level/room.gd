class_name Room
extends Resource

# Rectangular room on the ship grid. Ported from GMTK 2025's V1/Room.gd, with the
# grid fields collapsed into a Rect2i and the GameTypes.TileType dependency dropped
# (that autoload isn't coming over, and the field was never actually read).
#
# COORDINATES: grid units are boundary coordinates — grid (x, y) is the CORNER of
# tile (x, y), and maps to world (x * tile_size, y * tile_size). Tile centres are at
# +0.5. There is no level-size centring; see RoomBuilder for why.

@export var id: String = ""
@export var rect: Rect2i = Rect2i(0, 0, 1, 1)
## Floor-to-ceiling height in metres.
@export var height: float = 3.0
@export var floor_color: Color = Color(0.30, 0.32, 0.36)
@export var wall_color: Color = Color(0.52, 0.55, 0.60)
@export var ceiling_color: Color = Color(0.24, 0.26, 0.30)


func _init(room_id: String = "", room_rect: Rect2i = Rect2i(0, 0, 1, 1), room_height: float = 3.0) -> void:
	id = room_id
	rect = room_rect
	height = room_height


## Centre in grid (boundary) coordinates.
func center() -> Vector2:
	return Vector2(rect.position) + Vector2(rect.size) * 0.5


func contains_tile(x: int, y: int) -> bool:
	return rect.has_point(Vector2i(x, y))


## The four perimeter walls, in grid boundary coordinates. Each is
## {start: Vector2, end: Vector2, side: String, inward: Vector2}.
##
## `inward` points from the wall line toward this room's interior. Each room builds
## its own wall skin on its own side, so a shared wall shows the correct colour in
## both rooms — see RoomBuilder.
func perimeter_walls() -> Array[Dictionary]:
	var x0 := float(rect.position.x)
	var y0 := float(rect.position.y)
	var x1 := x0 + float(rect.size.x)
	var y1 := y0 + float(rect.size.y)
	return [
		{"start": Vector2(x0, y0), "end": Vector2(x1, y0), "side": "north", "inward": Vector2(0, 1)},
		{"start": Vector2(x0, y1), "end": Vector2(x1, y1), "side": "south", "inward": Vector2(0, -1)},
		{"start": Vector2(x0, y0), "end": Vector2(x0, y1), "side": "west", "inward": Vector2(1, 0)},
		{"start": Vector2(x1, y0), "end": Vector2(x1, y1), "side": "east", "inward": Vector2(-1, 0)},
	]
