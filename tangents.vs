package mesh

import (
    "math/geom"
)

extension Mesh {
    /// Tangents is a tangent per vertex for normal mapping: XYZ along the
    /// texture's +U on the surface, square to the normal, and W the sign
    /// that makes the bitangent (cross(N, T) · W) point along +V. Each
    /// triangle's tangent is summed into its corners and orthonormalized,
    /// the usual per-vertex scheme (close to MikkTSpace for smooth meshes
    /// without mirrored UVs inside a triangle fan). Needs normals and UVs.
    public func Tangents() -> [geom.Vec4] {
        let n = Positions.count
        var t = [geom.Vec3](repeating: geom.Vec3.Zero, count: n)
        var b = [geom.Vec3](repeating: geom.Vec3.Zero, count: n)
        if UVs.count < n || Normals.count < n { return [geom.Vec4](repeating: geom.Vec4(1, 0, 0, 1), count: n) }
        var i = 0
        while i + 2 < Indices.count {
            let i0 = int(Indices[i]), i1 = int(Indices[i + 1]), i2 = int(Indices[i + 2])
            let e1 = Positions[i1] - Positions[i0], e2 = Positions[i2] - Positions[i0]
            let du1 = UVs[i1].X - UVs[i0].X, dv1 = UVs[i1].Y - UVs[i0].Y
            let du2 = UVs[i2].X - UVs[i0].X, dv2 = UVs[i2].Y - UVs[i0].Y
            let det = du1 * dv2 - du2 * dv1
            if det != 0 {
                let r = 1 / det
                let tu = (e1 * dv2 - e2 * dv1) * r
                let tv = (e2 * du1 - e1 * du2) * r
                for k in [i0, i1, i2] {
                    t[k] += tu
                    b[k] += tv
                }
            }
            i += 3
        }
        var out: [geom.Vec4] = []
        out.reserveCapacity(n)
        for v in 0..<n {
            let nn = Normals[v]
            var tt = t[v] - nn * nn.Dot(t[v])
            if tt.LengthSquared() < 1e-12 {
                // No UV direction here: any square to the normal.
                tt = abs(nn.Y) < 0.9 ? geom.Vec3.UnitY.Cross(nn) : geom.Vec3.UnitX.Cross(nn)
            }
            tt = tt.Normalized()
            // V grows downwards in texture space (V = 0 at the top), so
            // the bitangent that follows +V is the one the sign picks.
            let w: float32 = nn.Cross(tt).Dot(b[v]) < 0 ? -1 : 1
            out.append(geom.Vec4(tt.X, tt.Y, tt.Z, w))
        }
        return out
    }
}
