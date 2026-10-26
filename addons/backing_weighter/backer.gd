@tool
class_name BackingWeight
extends RefCounted

# Auto-weights a rest-pose backing Polygon2D to a Skeleton2D.
# Rigid zones go 100% to the nearest bone; vertices within blend_radius
# of a joint blend between that joint's parent/child bones only.

static func weight(poly: Polygon2D, sk: Skeleton2D, blend_radius: float = 10.0, leaf_stub: float = 15.0, root_bone: Bone2D = null) -> Dictionary:
	var bones: Array[Bone2D] = []
	if root_bone == null:
		_collect(sk, bones)
	else:
		# Region mesh: only the subtree plus the parent (for the base joint).
		var par := root_bone.get_parent()
		if par is Bone2D:
			bones.append(par)
		bones.append(root_bone)
		_collect(root_bone, bones)
	if bones.is_empty():
		return {"ok": false, "error": "no bones"}
	for b in bones:
		if not b.transform.origin.is_equal_approx(b.rest.origin):
			push_warning("Backing Weighter: %s off rest origin. Use Skeleton2D > Make Rest Pose first." % b.name)
		elif absf(wrapf(b.rotation - b.rest.get_rotation(), -PI, PI)) > 0.02:
			push_warning("Backing Weighter: %s off rest rotation. Use Skeleton2D > Make Rest Pose first." % b.name)
	# Rest segments per bone: origin -> child origin, or stub along rest rotation.
	var segs := {}  # Bone2D -> [Vector2 a, Vector2 b]
	for b in bones:
		var o := (b as Node2D).global_position
		var tip := Vector2.INF
		for c in b.get_children():
			if c is Bone2D:
				tip = (c as Node2D).global_position
				break
		if tip == Vector2.INF:
			tip = o + Vector2.RIGHT.rotated((b as Node2D).global_rotation) * leaf_stub
		segs[b] = [o, tip]
	# Joints: every bone with a Bone2D parent. J = child origin.
	var joints: Array = []  # [Vector2 J, Bone2D parent, Bone2D child]
	for b in bones:
		var p := b.get_parent()
		if p is Bone2D:
			joints.append([(b as Node2D).global_position, p, b])
	var n := poly.polygon.size()
	if n == 0:
		return {"ok": false, "error": "backing has no polygon; draw it first"}
	# Per-vertex bone weights.
	var w: Array = []  # Array of Dictionary {Bone2D: float}
	w.resize(n)
	var blended := 0
	for i in n:
		var v: Vector2 = poly.to_global(poly.polygon[i])
		var nb: Bone2D = null
		var nd := INF
		for b in bones:
			var s: Array = segs[b]
			var d := _seg_dist(v, s[0], s[1])
			if d < nd:
				nd = d
				nb = b
		var assign := {nb: 1.0}
		# Blend only across the nearest joint whose pair owns this vertex.
		var bj: Array = []
		var bd := INF
		for jt in joints:
			var dj: float = v.distance_to(jt[0])
			if dj < bd and dj <= blend_radius and (nb == jt[1] or nb == jt[2]):
				bd = dj
				bj = jt
		if not bj.is_empty():
			var p: Bone2D = bj[1]
			var c: Bone2D = bj[2]
			var ax: Vector2 = (bj[0] - (p as Node2D).global_position)
			if ax.length() < 0.001:
				ax = Vector2.RIGHT.rotated((c as Node2D).global_rotation)
			ax = ax.normalized()
			var t := clampf((v - bj[0]).dot(ax) / blend_radius * 0.5 + 0.5, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			assign = {p: 1.0 - t, c: t}
			blended += 1
		w[i] = assign
	poly.skeleton = poly.get_path_to(sk)
	poly.clear_bones()
	var used: Array[Bone2D] = []
	for b in bones:
		var arr := PackedFloat32Array()
		arr.resize(n)
		var any := false
		for i in n:
			var val: float = (w[i] as Dictionary).get(b, 0.0)
			arr[i] = val
			if val > 0.0:
				any = true
		if any:
			used.append(b)
			poly.add_bone(sk.get_path_to(b), arr)
	return {"ok": true, "verts": n, "bones": used.size(), "blended": blended}


static func _collect(n: Node, out: Array[Bone2D]) -> void:
	for c in n.get_children():
		if c is Bone2D:
			out.append(c)
			_collect(c, out)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)
