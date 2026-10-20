package mesh

import (
    "math"
    "math/geom"
)

/// Sweep is a tube along a path: a ring of `sides` vertices round each
/// point, `radii[i]` from it (the last radius repeats if there are fewer),
/// turned along the path without twisting. UVs: U round the tube, V along
/// it by length, both mapped into `uv` (an atlas region; V spans the
/// region once over the whole tube). A radius of 0 makes a point, as at a
/// branch's tip; `capStart` closes the first ring with a disc.
public func Sweep(_ path: [geom.Vec3], radii: [float32], sides: int = 8, uv: Rect = Rect.Whole, capStart: bool = false) -> Mesh {
    var m = Mesh()
    let n = path.count
    if n < 2 || radii.isEmpty { return m }
    let k = max(3, sides)
    // Lengths along the path, for V.
    var along: [float32] = [0]
    for i in 1..<n { along.append(along[i - 1] + (path[i] - path[i - 1]).Length()) }
    let total = math.Max(along[n - 1], 1e-6)
    // A frame carried along the path (parallel transport): no twist.
    var t = (path[1] - path[0]).Normalized()
    var side = math.Abs(t.Y) < 0.9 ? t.Cross(geom.Vec3.UnitY).Normalized() : t.Cross(geom.Vec3.UnitX).Normalized()
    for i in 0..<n {
        let dir: geom.Vec3
        if i == 0 {
            dir = (path[1] - path[0]).Normalized()
        } else if i == n - 1 {
            dir = (path[n - 1] - path[n - 2]).Normalized()
        } else {
            dir = (path[i + 1] - path[i - 1]).Normalized()
        }
        // Turn the side vector by the turn from t to dir.
        let c = t.Cross(dir)
        if c.LengthSquared() > 1e-10 {
            let q = geom.FromTo(t, dir)
            side = q.Rotate(side)
        }
        t = dir
        let up = dir.Cross(side).Normalized()
        side = up.Cross(dir).Normalized()
        let r = radii[min(i, radii.count - 1)]
        let v = uv.V0 + (uv.V1 - uv.V0) * (along[i] / total)
        for s in 0...k {
            let a = float32(s) / float32(k) * 2 * float32(math.Pi)
            let out = side * math.Cos(a) + up * math.Sin(a)
            m.Positions.append(path[i] + out * r)
            m.Normals.append(out)
            m.UVs.append(geom.Vec2(uv.U0 + (uv.U1 - uv.U0) * float32(s) / float32(k), v))
        }
    }
    let row = uint32(k + 1)
    for i in 0..<(n - 1) {
        for s in 0..<k {
            let a = uint32(i) * row + uint32(s), b = a + 1, c = a + row, d = c + 1
            // Counter-clockwise seen from outside.
            m.Indices += [a, b, c, b, d, c]
        }
    }
    if capStart {
        let center = uint32(m.Positions.count)
        let back = -(path[1] - path[0]).Normalized()
        m.Positions.append(path[0])
        m.Normals.append(back)
        m.UVs.append(geom.Vec2((uv.U0 + uv.U1) / 2, uv.V0))
        for s in 0..<k { m.Indices += [center, uint32(s + 1), uint32(s)] }
    }
    return m
}
