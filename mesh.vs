// Package mesh is triangle meshes as plain data: positions, normals and
// texture coordinates per vertex, and indices three to a triangle. It
// builds the simple shapes models are made of, transforms and joins
// meshes, and knows nothing about a GPU: a renderer turns a Mesh into
// whatever vertex layout it draws.
//
// Conventions are math/geom's: right-handed, Y up. Triangles wind
// counter-clockwise seen from the side their normal points to. Texture
// coordinates have V = 0 at the top of the image.
package mesh

import (
    "math/geom"
)

/// Mesh is an indexed triangle mesh.
public struct Mesh {
    public var Positions: [geom.Vec3] = []
    public var Normals: [geom.Vec3] = []
    public var UVs: [geom.Vec2] = []
    /// A second set of texture coordinates, or empty: baked lighting and
    /// occlusion laid out apart from the first (glTF's TEXCOORD_1).
    public var UV2s: [geom.Vec2] = []
    /// Linear RGBA per vertex, or empty: paint without a texture.
    public var Colors: [geom.Vec4] = []
    /// Three per triangle, indexing the vertex arrays.
    public var Indices: [uint32] = []

    public init() {}

    /// VertexCount is how many vertices it has.
    public var VertexCount: int { return Positions.count }

    /// TriangleCount is how many triangles it has.
    public var TriangleCount: int { return Indices.count / 3 }
}

extension Mesh {
    /// Append adds another mesh's triangles to this one.
    public mutating func Append(_ m: Mesh) {
        let base = uint32(Positions.count)
        Positions += m.Positions
        Normals += m.Normals
        UVs += m.UVs
        Colors += m.Colors
        // A second UV set on either side: the other side's vertices get
        // zeros, so the sets stay one a vertex.
        if !UV2s.isEmpty || !m.UV2s.isEmpty {
            while UV2s.count < int(base) { UV2s.append(geom.Vec2.Zero) }
            UV2s += m.UV2s
            while UV2s.count < Positions.count { UV2s.append(geom.Vec2.Zero) }
        }
        for i in m.Indices { Indices.append(base + i) }
    }

    /// Transformed is the mesh moved by m: positions as points, normals as
    /// directions (by m's inverse transpose, so scaling keeps them square
    /// to their faces).
    public func Transformed(by m: geom.Mat4) -> Mesh {
        var out = self
        let normalMatrix = m.Inverse()?.Transposed() ?? m
        for i in 0..<out.Positions.count {
            out.Positions[i] = m.TransformPoint(Positions[i])
            if i < Normals.count { out.Normals[i] = normalMatrix.TransformDirection(Normals[i]).Normalized() }
        }
        return out
    }

    /// Bounds is the smallest box holding every vertex; a zero box at the
    /// origin for an empty mesh.
    public func Bounds() -> geom.AABB {
        guard let first = Positions.first else { return geom.AABB(min: geom.Vec3.Zero, max: geom.Vec3.Zero) }
        var lo = first, hi = first
        for p in Positions {
            lo = geom.Min(lo, p)
            hi = geom.Max(hi, p)
        }
        return geom.AABB(min: lo, max: hi)
    }

    /// Triangles is every triangle's three corners, unindexed, in order.
    public func Triangles() -> [(geom.Vec3, geom.Vec3, geom.Vec3)] {
        var out: [(geom.Vec3, geom.Vec3, geom.Vec3)] = []
        var i = 0
        while i + 2 < Indices.count {
            out.append((Positions[int(Indices[i])], Positions[int(Indices[i + 1])], Positions[int(Indices[i + 2])]))
            i += 3
        }
        return out
    }
}

// ---- building ----

/// Rect is a region of a texture: U0, V0 its top-left, U1, V1 its
/// bottom-right, each 0…1.
public struct Rect: Equatable {
    public var U0: float32
    public var V0: float32
    public var U1: float32
    public var V1: float32

    public init(_ u0: float32, _ v0: float32, _ u1: float32, _ v1: float32) {
        U0 = u0
        V0 = v0
        U1 = u1
        V1 = v1
    }

    /// Whole is the entire texture.
    public static let Whole = Rect(0, 0, 1, 1)

    /// Tile is cell (column, row) of a texture cut into a grid of n × n.
    public static func Tile(_ column: int, _ row: int, of n: int) -> Rect {
        let s = 1 / float32(n)
        return Rect(float32(column) * s, float32(row) * s, float32(column + 1) * s, float32(row + 1) * s)
    }
}

/// BoxUV is the texture region on each face of a box. Seen from outside,
/// the side faces have their top up (+Y); the top face has its top toward
/// -Z, and the bottom face too.
public struct BoxUV {
    public var PosX: Rect
    public var NegX: Rect
    public var PosY: Rect
    public var NegY: Rect
    public var PosZ: Rect
    public var NegZ: Rect

    public init(posX: Rect, negX: Rect, posY: Rect, negY: Rect, posZ: Rect, negZ: Rect) {
        PosX = posX
        NegX = negX
        PosY = posY
        NegY = negY
        PosZ = posZ
        NegZ = negZ
    }

    /// All is the same region on every face.
    public init(all r: Rect) {
        self.init(posX: r, negX: r, posY: r, negY: r, posZ: r, negZ: r)
    }
}

/// Quad is a rectangle from four corners counter-clockwise seen from in
/// front (left-bottom, right-bottom, right-top, left-top) and the texture
/// region stretched over it.
public func Quad(_ lb: geom.Vec3, _ rb: geom.Vec3, _ rt: geom.Vec3, _ lt: geom.Vec3, uv: Rect = Rect.Whole) -> Mesh {
    var m = Mesh()
    let n = (rb - lb).Cross(lt - lb).Normalized()
    m.Positions = [lb, rb, rt, lt]
    m.Normals = [n, n, n, n]
    m.UVs = [geom.Vec2(uv.U0, uv.V1), geom.Vec2(uv.U1, uv.V1), geom.Vec2(uv.U1, uv.V0), geom.Vec2(uv.U0, uv.V0)]
    m.Indices = [0, 1, 2, 0, 2, 3]
    return m
}

/// Box is the six faces of an axis-aligned box, each textured with its
/// region of `uv`.
public func Box(_ b: geom.AABB, uv: BoxUV = BoxUV(all: Rect.Whole)) -> Mesh {
    let x0 = b.Min.X, y0 = b.Min.Y, z0 = b.Min.Z
    let x1 = b.Max.X, y1 = b.Max.Y, z1 = b.Max.Z
    func v(_ x: float32, _ y: float32, _ z: float32) -> geom.Vec3 { return geom.Vec3(x, y, z) }
    var m = Mesh()
    m.Append(Quad(v(x1, y0, z1), v(x1, y0, z0), v(x1, y1, z0), v(x1, y1, z1), uv: uv.PosX))
    m.Append(Quad(v(x0, y0, z0), v(x0, y0, z1), v(x0, y1, z1), v(x0, y1, z0), uv: uv.NegX))
    m.Append(Quad(v(x0, y1, z1), v(x1, y1, z1), v(x1, y1, z0), v(x0, y1, z0), uv: uv.PosY))
    m.Append(Quad(v(x1, y0, z1), v(x0, y0, z1), v(x0, y0, z0), v(x1, y0, z0), uv: uv.NegY))
    m.Append(Quad(v(x0, y0, z1), v(x1, y0, z1), v(x1, y1, z1), v(x0, y1, z1), uv: uv.PosZ))
    m.Append(Quad(v(x1, y0, z0), v(x0, y0, z0), v(x0, y1, z0), v(x1, y1, z0), uv: uv.NegZ))
    return m
}
