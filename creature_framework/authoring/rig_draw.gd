class_name RigDraw
extends RefCounted
## Small drawing helpers shared by the @tool rig authoring nodes.
##
## Labels get a dark outline so they stay readable on any background, and alignment is
## resolved from an anchor point rather than a fixed offset. That lets `RigPoint` centre
## its name over the dot while `RigLimb` prints beside its own shaft — far limbs to the
## left, near limbs to the right — so a pair of limbs never prints on top of itself.


const OUTLINE: Color = Color(0.07, 0.08, 0.10, 0.85)


## Draw `body` at `anchor`. `anchor.y` is the text baseline; `anchor.x` is the left edge,
## centre or right edge depending on `align`.
static func text(canvas: CanvasItem, anchor: Vector2, body: String, size: int,
        color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
    var font: Font = ThemeDB.fallback_font
    var width: float = font.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    var x: float = anchor.x
    if align == HORIZONTAL_ALIGNMENT_CENTER:
        x -= width * 0.5
    elif align == HORIZONTAL_ALIGNMENT_RIGHT:
        x -= width
    var at: Vector2 = Vector2(x, anchor.y)
    canvas.draw_string_outline(font, at, body, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
        4, OUTLINE)
    canvas.draw_string(font, at, body, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
