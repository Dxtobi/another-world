@tool
class_name RigLimb
extends Node2D
## A limb authored as a CHILD OF ITS ANCHOR POINT.
##
## The parent RigPoint is the anchor, and this node's position is `local_offset` in the
## spine frame (+x forward, +y belly). Reach is the nominal length; the locomotor decides
## where the tip actually goes each tick. The dashed editor line is only a size guide.
##
## `style` comes from LimbStyleCatalog. `kind` is the coarse debug/collision family.

@export_enum("wing", "leg", "tentacle", "claw", "fin") var kind: String = "leg":
    set(value):
        kind = value
        _refresh()

@export_enum("default", "flap", "walk2", "reach", "dangle", "tentacle") var style: String = "walk2":
    set(value):
        style = value
        _refresh()

@export_enum("Far:-1", "Near:1") var lane: int = 1:
    set(value):
        lane = value
        _refresh()

@export_range(1.0, 400.0, 0.5, "or_greater") var reach: float = 40.0:
    set(value):
        reach = value
        _refresh()

@export var show_reach: bool = true:
    set(value):
        show_reach = value
        _refresh()


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
    var blueprint: Node = get_parent()
    if blueprint is RigBlueprint:
        (blueprint as RigBlueprint).queue_redraw()


func _draw() -> void:
    if not Engine.is_editor_hint():
        return
    var near: bool = lane >= 0
    var col: Color = _kind_color()
    if not near:
        col = col.darkened(0.25)

    # Link back to the anchor point so a limb is never a floating dot.
    if get_parent() is RigPoint:
        draw_line(-position, Vector2.ZERO, Color(col, 0.45), 1.0)

    draw_circle(Vector2.ZERO, 5.0, Color(col, 0.2))
    draw_circle(Vector2.ZERO, 3.0, col)

    # Shaft: the near part solid (this is the limb), the rest a dashed size guide.
    # The label sits beside the TIP, not the anchor: tip height already encodes reach, so
    # the four limbs of a pair of pairs land on four separate rows instead of one pile.
    var label_at: Vector2
    var label: String
    if show_reach:
        var tip: Vector2 = Vector2.DOWN * reach
        var solid: Vector2 = Vector2.DOWN * minf(reach * 0.35, 24.0)
        draw_line(Vector2.ZERO, solid, Color(col, 0.8), 2.0)
        draw_dashed_line(solid, tip, Color(col, 0.5), 1.0, 5.0)
        draw_line(tip + Vector2(-3.0, 0.0), tip + Vector2(3.0, 0.0), Color(col, 0.9), 1.5)
        label_at = tip + Vector2(7.0 if near else -7.0, 4.0)
        label = "%s  %s  %.0f" % [name, style, reach]
    else:
        label_at = Vector2(7.0 if near else -7.0, -4.0)
        label = String(name)

    # Far limbs print to the left of their tip, near limbs to the right, so the two halves
    # of a pair never print on top of each other.
    RigDraw.text(self, label_at, label, 10, col,
        HORIZONTAL_ALIGNMENT_LEFT if near else HORIZONTAL_ALIGNMENT_RIGHT)




func _kind_color() -> Color:
    match StringName(kind):
        &"wing":
            return Color(0.55, 0.82, 1.0)
        &"tentacle":
            return Color(0.80, 0.58, 1.0)
        &"claw":
            return Color(1.0, 0.52, 0.52)
        &"fin":
            return Color(0.45, 0.95, 0.85)
        _:
            return Color(0.95, 0.72, 0.42)
