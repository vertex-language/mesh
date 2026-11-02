package height

import (
    "math/geom"
    "mesh"
)

/// Chunk is a square tile of the ground as a mesh: `cells` points' worth
/// along X and Z from point (x, z), every `step`th point (1 full detail,
/// 2 half, …), in world coordinates. Normals come from the whole field,
/// so tiles meet without a crease. UVs are world X and Z times uvScale,
/// so a texture tiles across tiles seamlessly. A skirt (meters) hangs a
/// strip down from the tile's edges, hiding the cracks where a tile meets
/// a coarser neighbor.
public func Chunk(f: Field, x: int, z: int, cells: int, step: int = 1, uvScale: float32 = 0.25, skirt: float32 = 0) -> mesh.Mesh {
    let s = max(1, step)
    let n = max(1, cells / s)
    var m = mesh.Mesh()
    let row = n + 1
    for b in 0...n {
        for a in 0...n {
            let i = min(f.Width - 1, x + a * s), j = min(f.Depth - 1, z + b * s)
            let p = f.Point(i, j)
            m.Positions.append(p)
            m.Normals.append(f.NormalAt(i, j))
            m.UVs.append(geom.Vec2(p.X * uvScale, p.Z * uvScale))
        }
    }
    // Two triangles a cell, facing up (counter-clockwise seen from above).
    for b in 0..<n {
        for a in 0..<n {
            let p0 = uint32(b * row + a), p1 = p0 + 1, p2 = p0 + uint32(row), p3 = p2 + 1
            m.Indices += [p0, p2, p1, p1, p2, p3]
        }
    }
    if skirt > 0 {
        // Round the edge in order, each edge point and one hung below it.
        var ring: [int] = []
        for a in 0...n { ring.append(a) }
        for b in 1...n { ring.append(b * row + n) }
        for a in stride(from: n - 1, through: 0, by: -1) { ring.append(n * row + a) }
        for b in stride(from: n - 1, through: 1, by: -1) { ring.append(b * row) }
        ring.append(0)
        var below: [uint32] = []
        for k in ring {
            below.append(uint32(m.Positions.count))
            m.Positions.append(m.Positions[k] - geom.Vec3(0, skirt, 0))
            m.Normals.append(m.Normals[k])
            m.UVs.append(m.UVs[k])
        }
        for k in 0..<(ring.count - 1) {
            let a = uint32(ring[k]), b = uint32(ring[k + 1])
            // Both ways round: seen from either side.
            m.Indices += [a, below[k], b, b, below[k], below[k + 1]]
            m.Indices += [a, b, below[k], b, below[k + 1], below[k]]
        }
    }
    return m
}
