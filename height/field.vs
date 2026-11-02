// Package height is heightfields: ground as a grid of heights, a fixed
// distance apart, the way every open-world engine keeps its outdoor
// terrain. A field is cheap to store, to ask ("how high is the ground
// here, which way does it face?"), to collide with and to draw in tiles.
//
// It makes fields too: noise layers from a JSON recipe (Generate), then
// erosion, thermal (steep slopes slump) and hydraulic (raindrops carve
// gullies and fill hollows), which is what makes generated ground look
// like land and not like noise. Chunk turns a tile of it into a
// mesh.Mesh to draw.
//
//     let f = height.Generate(try height.DecodeRecipe(text))
//     let y = f.Sample(x, z)
//     let tile = height.Chunk(f, x: 0, z: 0, cells: 64)
//
// Pure Vertex, no gpu: a server, a test or a map tool uses it as a game
// does.
package height

import (
    "math"
    "math/geom"
)

/// Field is a grid of heights: Width × Depth points, Spacing meters
/// apart, point (0, 0) at Origin (X and Z; heights are Y, in meters).
public struct Field {
    public let Width: int
    public let Depth: int
    public let Spacing: float32
    public let Origin: geom.Vec2
    /// Row by row: point (i, j) is Heights[j * Width + i], i along X, j along Z.
    public var Heights: [float32]

    public init(width: int, depth: int, spacing: float32 = 1, origin: geom.Vec2 = geom.Vec2.Zero, fill: float32 = 0) {
        Width = max(2, width)
        Depth = max(2, depth)
        Spacing = spacing
        Origin = origin
        Heights = [float32](repeating: fill, count: Width * Depth)
    }

    /// Size is how far the field reaches, meters, in X and Z.
    public var Size: geom.Vec2 {
        return geom.Vec2(float32(Width - 1) * Spacing, float32(Depth - 1) * Spacing)
    }

    /// At is point (i, j)'s height; points off the edge take the edge's.
    @inlinable public func At(i: int, j: int) -> float32 {
        let x = i < 0 ? 0 : (i >= Width ? Width - 1 : i)
        let z = j < 0 ? 0 : (j >= Depth ? Depth - 1 : j)
        return Heights[z * Width + x]
    }

    /// Set changes point (i, j)'s height.
    public mutating func Set(i: int, j: int, h: float32) {
        if i < 0 || j < 0 || i >= Width || j >= Depth { return }
        Heights[j * Width + i] = h
    }

    /// Point is where point (i, j) is in the world.
    public func Point(i: int, j: int) -> geom.Vec3 {
        return geom.Vec3(Origin.X + float32(i) * Spacing, At(i, j), Origin.Y + float32(j) * Spacing)
    }

    /// Contains is whether the world's (x, z) is over the field.
    public func Contains(x: float32, z: float32) -> bool {
        let s = Size
        return x >= Origin.X && z >= Origin.Y && x <= Origin.X + s.X && z <= Origin.Y + s.Y
    }

    /// Sample is the ground's height under the world's (x, z), between
    /// points bilinearly (clamped at the edges).
    public func Sample(x: float32, z: float32) -> float32 {
        let fx = (x - Origin.X) / Spacing, fz = (z - Origin.Y) / Spacing
        let i = int(math.Floor(fx)), j = int(math.Floor(fz))
        let tx = fx - float32(i), tz = fz - float32(j)
        let a = At(i, j), b = At(i + 1, j), c = At(i, j + 1), d = At(i + 1, j + 1)
        return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz
    }

    /// Normal is which way the ground faces at the world's (x, z).
    public func Normal(x: float32, z: float32) -> geom.Vec3 {
        let e = Spacing
        let dx = Sample(x + e, z) - Sample(x - e, z)
        let dz = Sample(x, z + e) - Sample(x, z - e)
        return geom.Vec3(-dx, 2 * e, -dz).Normalized()
    }

    /// NormalAt is which way the ground faces at point (i, j).
    public func NormalAt(i: int, j: int) -> geom.Vec3 {
        let dx = At(i + 1, j) - At(i - 1, j)
        let dz = At(i, j + 1) - At(i, j - 1)
        return geom.Vec3(-dx, 2 * Spacing, -dz).Normalized()
    }

    /// Slope is how steep the ground is at the world's (x, z): 0 level,
    /// 1 a wall (one minus the normal's Y).
    public func Slope(x: float32, z: float32) -> float32 {
        return 1 - Normal(x, z).Y
    }

    /// Range is the lowest and highest heights.
    public func Range() -> (low: float32, high: float32) {
        var lo: float32 = 1e30, hi: float32 = -1e30
        for h in Heights {
            if h < lo { lo = h }
            if h > hi { hi = h }
        }
        return (low: lo, high: hi)
    }

    /// Bounds is the box the ground fills.
    public func Bounds() -> geom.AABB {
        let r = Range(), s = Size
        return geom.AABB(min: geom.Vec3(Origin.X, r.low, Origin.Y), max: geom.Vec3(Origin.X + s.X, r.high, Origin.Y + s.Y))
    }

    /// Raycast is where a ray first meets the ground within maxDistance,
    /// stepping half a spacing at a time and refining between the last
    /// two steps; nil if it doesn't.
    public func Raycast(origin: geom.Vec3, direction: geom.Vec3, maxDistance: float32) -> float32? {
        let d = direction.Normalized()
        let step = Spacing * 0.5
        var t: float32 = 0
        var prev = origin.Y - Sample(origin.X, origin.Z)
        if prev < 0 { return nil }
        while t < maxDistance {
            let nt = math.Min(t + step, maxDistance)
            let p = origin + d * nt
            let above = p.Y - Sample(p.X, p.Z)
            if above <= 0 {
                // Between t (above by prev) and nt (below by -above).
                return t + (nt - t) * prev / (prev - above)
            }
            prev = above
            t = nt
        }
        return nil
    }
}
