@tool
class_name RigPoint
extends Node2D
## One logic spine point, authored directly in the scene.
##
## The node's position is the rest offset from the creature origin (+x forward, +y belly).
## Points are baked in scene order; the first is not special — RigBlueprint names the
## front/centre/rear points explicitly. Only position is baked, not rotation/scale, because
## the solver owns the runtime transform.

@export var mass: float = 1.0:
    set(value):
        mass = value
        _refresh()

## -1 far side .. +1 near side. Reserved for the T7 depth layer.
@export var base_depth: float = 0.0:
    set(value):
        base_depth = clampf(value, -1.0, 1.0)
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
    var parent: Node = get_parent()
    if parent is RigBlueprint:
        (parent as RigBlueprint).queue_redraw()


func _draw() -> void:
    if not Engine.is_editor_hint():
        return
    var col: Color = Color(1.0, 0.86, 0.45)
    draw_circle(Vector2.ZERO, 8.0, Color(col, 0.14))
    draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, Color(col, 0.85), 1.5)
    draw_circle(Vector2.ZERO, 3.0, col)

    # Name above the dot, non-default data below it, both centred. Default mass/depth are
    # omitted so a normal spine reads as three names instead of six labels.
    RigDraw.text(self, Vector2(0.0, -14.0), name, 12, col, HORIZONTAL_ALIGNMENT_CENTER)
    var extra: String = _extra_text()
    if not extra.is_empty():
        RigDraw.text(self, Vector2(0.0, 20.0), extra, 10, Color(col, 0.8),
            HORIZONTAL_ALIGNMENT_CENTER)


func _extra_text() -> String:
    var parts: PackedStringArray = PackedStringArray()
    if not is_equal_approx(mass, 1.0):
        parts.append("m %.2f" % mass)
    if not is_zero_approx(base_depth):
        parts.append("d %+.1f" % base_depth)
    return "  ".join(parts)

