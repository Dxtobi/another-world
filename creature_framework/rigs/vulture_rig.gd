class_name VultureRig
extends RefCounted
## Builds the Vulture rig in code (no .tres hand-editing). A new creature is just another file like this.


static func build() -> CreatureRig:
    var rig: CreatureRig = CreatureRig.new()
    rig.front_point = 0
    rig.center_point = 1
    rig.rear_point = 2

    # 3-point spine, fixed segment length 40
    rig.points.append(_point(&"front", Vector2(40.0, 0.0), 1.0, 0.0))
    rig.points.append(_point(&"center", Vector2(0.0, 0.0), 1.5, 0.0))
    rig.points.append(_point(&"rear", Vector2(-40.0, 0.0), 1.0, 0.0))

    rig.links.append(_link(0, 1, 40.0, 1.0))
    rig.links.append(_link(1, 2, 40.0, 1.0))
    rig.links.append(_link(0, 2, 80.0, 0.15))   # weak bend-resist link: spine can flex but not fold

    # Wings at the shoulders (centre point), legs at the hips (rear point), so the
    # four limbs are not a star from one dot.
    rig.limbs.append(_limb(&"wing_far", &"wing", 1, Vector2(2.0, -7.0), 95.0, -1))
    rig.limbs.append(_limb(&"wing_near", &"wing", 1, Vector2(2.0, -7.0), 95.0, 1))
    rig.limbs.append(_limb(&"leg_far", &"leg", 2, Vector2(-4.0, 5.0), 55.0, -1))
    rig.limbs.append(_limb(&"leg_near", &"leg", 2, Vector2(1.0, 8.0), 55.0, 1))

    rig.locomotors.append(FlyLocomotor)
    rig.locomotors.append(ClimbLocomotor)
    return rig


static func _point(n: StringName, offset: Vector2, mass: float, depth: float) -> PointDef:
    var p: PointDef = PointDef.new()
    p.name = n
    p.offset = offset
    p.mass = mass
    p.base_depth = depth
    return p


static func _link(a: int, b: int, length: float, stiffness: float) -> LinkDef:
    var l: LinkDef = LinkDef.new()
    l.a = a
    l.b = b
    l.rest_length = length
    l.stiffness = stiffness
    return l


static func _limb(n: StringName, kind: StringName, anchor: int, offset: Vector2, reach: float, lane: int) -> LimbDef:
    var lm: LimbDef = LimbDef.new()
    lm.name = n
    lm.kind = kind
    lm.anchor_point = anchor
    lm.local_offset = offset
    lm.reach = reach
    lm.lane = lane
    return lm
