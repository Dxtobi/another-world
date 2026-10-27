@tool
class_name RigBodyPart
extends Node2D
## A tail or tentacle authored as ONE node under its anchor point.
##
## `length` is the number of EXTRA points: a length of 4 adds four body points after the
## anchor, so the baked chain is anchor -> p1 .. p4. Those points are real logic
## (`PointDef`s joined by `LinkDef`s), not a cosmetic follower: they have mass, swing with
## momentum and take part in collisions. Only the DRAWING stays debug until T9.
##
## Aim: this node's position is a direction handle, not an offset. Point the node where the
## chain should rest (a tail normally points backwards); the handle's length is ignored.
## `auto_direction` uses the handle, otherwise `direction` is used. The chain always starts
## one `spacing` from the anchor. Only position is baked, matching the rest of the
## authoring layer: rotation and scale are rejected by `RigBlueprint.validate()`.

@export_enum("tail", "tentacle") var kind: String = "tail":
    set(value):
        kind = value
        _refresh()

## Extra points after the anchor. The baked chain has `length + 1` points (anchor included).
@export_range(1, 32, 1, "or_greater") var length: int = 4:
    set(value):
        length = value
        _refresh()

## Rest distance between consecutive chain points.
@export_range(1.0, 400.0, 0.5, "or_greater") var spacing: float = 12.0:
    set(value):
        spacing = value
        _refresh()

## Aim from this node's position (drag the node to aim the chain).
@export var auto_direction: bool = true:
    set(value):
        auto_direction = value
        _refresh()

## Spine-frame direction (+x forward, +y belly) used when `auto_direction` is off, or when
## the node sits exactly on its anchor. -x is backwards.
@export var direction: Vector2 = Vector2.LEFT:
    set(value):
        direction = value
        _refresh()

## Mass of the first generated point; the chain interpolates to `tip_mass`. Keep a chain
## light: it hangs from the body, so a tail as heavy as the spine drags the gait and
## stretches its own links against the floor.
@export_range(0.01, 50.0, 0.01, "or_greater") var base_mass: float = 0.5

## Mass of the last generated point.
@export_range(0.01, 50.0, 0.01, "or_greater") var tip_mass: float = 0.15

@export var show_chain: bool = true:
    set(value):
        show_chain = value
        _refresh()


## Rest direction of the chain in the spine frame (+x forward, +y belly).
func rest_dir() -> Vector2:
    var d: Vector2 = direction
    if auto_direction and position.length_squared() > 0.000001:
        d = position
    if d.length_squared() < 0.000001:
        return Vector2.LEFT
    return d.normalized()


## Rest offset of generated point `index` (1..length) FROM THE ANCHOR, in the spine frame.
func point_offset(index: int) -> Vector2:
    return rest_dir() * spacing * float(index)


## Rest mass of generated point `index` (1..length), falling off base -> tip.
func point_mass(index: int) -> float:
    if length <= 1:
        return base_mass
    return lerpf(base_mass, tip_mass, float(index - 1) / float(length - 1))


## Baked point name for generated point `index` (1..length).
func point_name(index: int) -> StringName:
    return StringName("%s_%d" % [name, index])


func _enter_tree() -> void:
    set_notify_transform(true)


func _ready() -> void:
    _refresh()


func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSFORM_CHANGED:
        _refresh()


func _refresh() -> void:
    if not Engine.is_editor_hint() or not is_inside_tree():
        return
    queue_redraw()
    var parent: Node = get_parent()
    if parent is RigBlueprint:
        (parent as RigBlueprint).queue_redraw()


func _draw() -> void:
    if not Engine.is_editor_hint() or not show_chain or length < 1:
        return
    var col: Color = _kind_color()
    var dir: Vector2 = rest_dir()
    # The anchor sits at -position in this node's local space; generated points are anchor
    # offsets, so subtract the handle to draw the chain around this node.
    var anchor: Vector2 = -position
    var pts: PackedVector2Array = PackedVector2Array()
    pts.append(anchor)
    for i in range(1, length + 1):
        pts.append(anchor + point_offset(i))

    draw_line(anchor, pts[1], Color(col, 0.65), 2.0)
    for i in range(1, pts.size() - 1):
        draw_line(pts[i], pts[i + 1], Color(col, 0.55), 2.0)
    # Direction handle: the anchor's cross and a short tick back to this node's origin.
    draw_circle(anchor, 3.0, Color(col, 0.9))
    draw_line(anchor, anchor + dir * minf(spacing * 0.6, 10.0), Color(col, 0.9), 1.0)

    for i in range(1, pts.size()):
        var t: float = float(i - 1) / float(maxi(length - 1, 1))
        draw_circle(pts[i], lerpf(3.5, 1.8, t), col)
    draw_circle(pts[1], 2.0, Color.WHITE)
    draw_circle(pts[pts.size() - 1], 2.0, Color.WHITE)

    var tip: Vector2 = pts[pts.size() - 1]
    RigDraw.text(self, tip + Vector2(-7.0, 4.0),
        "%s  %s  %d pts  %.0f" % [name, kind, length, spacing],
        10, col, HORIZONTAL_ALIGNMENT_RIGHT)


func _kind_color() -> Color:
    match StringName(kind):
        &"tentacle":
            return Color(0.80, 0.58, 1.0)
        _:
            return Color(0.62, 0.55, 0.42)
