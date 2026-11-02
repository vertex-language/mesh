// mesh: boxes wind outward with the right normals and texture corners;
// appending, transforming and bounds. mesh/height: sampling, normals,
// generating from a recipe, erosion, tiles.
package main

import (
    "math"
    "math/geom"
    "mesh"
    "mesh/height"
    "time"
)

var failures = 0

func check(ok: bool, what: string) {
    print(ok ? "ok    \(what)" : "FAIL  \(what)")
    if !ok { failures += 1 }
}

func near(a: geom.Vec3, b: geom.Vec3) -> bool {
    return math.Abs(a.X - b.X) < 1e-5 && math.Abs(a.Y - b.Y) < 1e-5 && math.Abs(a.Z - b.Z) < 1e-5
}

func main() -> int32 {
    let b = mesh.Box(geom.AABB(min: geom.Vec3(-1, 0, -2), max: geom.Vec3(1, 3, 2)))
    check(b.VertexCount == 24 && b.TriangleCount == 12, "a box is 24 vertices and 12 triangles")

    // Every triangle winds counter-clockwise seen from outside: its face
    // normal points away from the box's center, and matches the vertex normals.
    let c = b.Bounds().Center()
    var outward = true, matches = true
    var i = 0
    while i < b.Indices.count {
        let p0 = b.Positions[int(b.Indices[i])], p1 = b.Positions[int(b.Indices[i + 1])], p2 = b.Positions[int(b.Indices[i + 2])]
        let n = (p1 - p0).Cross(p2 - p0).Normalized()
        if n.Dot((p0 + p1 + p2) / 3 - c) <= 0 { outward = false }
        if !near(n, b.Normals[int(b.Indices[i])]) { matches = false }
        i += 3
    }
    check(outward, "every triangle faces out of the box")
    check(matches, "vertex normals match their faces")
    check(b.Bounds() == geom.AABB(min: geom.Vec3(-1, 0, -2), max: geom.Vec3(1, 3, 2)), "Bounds is the box")

    // Texture: the front (-Z) face's top-left corner, seen from outside, is
    // its region's (U0, V0); for the front, that's the +X, top corner.
    let tile = mesh.Rect.Tile(2, 1, of: 4)
    var uv = mesh.BoxUV(all: mesh.Rect.Whole)
    uv.NegZ = tile
    let front = mesh.Box(geom.AABB(min: geom.Vec3.Zero, max: geom.Vec3.One), uv: uv)
    var found = false
    for (k, p) in front.Positions.enumerated() where front.Normals[k] == geom.Vec3(0, 0, -1) && p == geom.Vec3(1, 1, 0) {
        found = front.UVs[k] == geom.Vec2(0.5, 0.25)
    }
    check(found && tile == mesh.Rect(0.5, 0.25, 0.75, 0.5), "a face's region is laid with its top-left at the face's top-left")

    var two = b
    two.Append(b.Transformed(by: geom.Translation(geom.Vec3(10, 0, 0))))
    check(two.TriangleCount == 24 && two.Bounds().Max.X == 11 && two.Indices.last == 47, "Append offsets the second mesh's indices")

    let turned = b.Transformed(by: geom.RotationY(float32(math.Pi) / 2) * geom.Scale(geom.Vec3(1, 1, 3)))
    var unit = true
    for n in turned.Normals where math.Abs(n.Length() - 1) > 1e-4 { unit = false }
    check(unit && near(turned.Bounds().Max, geom.Vec3(6, 3, 1)), "a scaled, turned box keeps unit normals (bounds \(turned.Bounds().Max))")

    sweeps()
    heights()

    print(failures == 0 ? "all passed" : "\(failures) failed")
    return failures == 0 ? 0 : 1
}

func heights() {
    // A ramp: height = x / 2 over 0…10 m.
    var ramp = height.Field(width: 11, depth: 11, spacing: 1)
    for j in 0..<11 { for i in 0..<11 { ramp.Set(i, j, float32(i) / 2) } }
    check(math.Abs(ramp.Sample(3.5, 4.2) - 1.75) < 1e-5 && ramp.Sample(-5, 0) == 0 && ramp.Sample(50, 0) == 5,
          "Sample is bilinear between points and clamps at the edges")
    let n = ramp.Normal(5, 5)
    let want = geom.Vec3(-0.5, 1, 0).Normalized()
    check(near(n, want) && math.Abs(ramp.Slope(5, 5) - (1 - want.Y)) < 1e-5, "Normal faces up the ramp's slope (\(n))")
    let hit = ramp.Raycast(origin: geom.Vec3(8, 10, 5), direction: geom.Vec3(-1, -1, 0), maxDistance: 30)
    // x - t/√2 hits ground at height (x)/2 where 10 - t/√2 = (8 - t/√2)/2: t/√2 = 12 … beyond the edge; use straight down instead.
    let down = ramp.Raycast(origin: geom.Vec3(6, 10, 5), direction: geom.Vec3(0, -1, 0), maxDistance: 30)
    check(down != nil && math.Abs(down! - 7) < 0.01 && hit != nil, "Raycast finds the ground (straight down: \(down ?? -1) m)")

    // A recipe: JSON both ways, the same seed the same ground.
    var r = height.Recipe()
    r.Size = 128
    r.Seed = 9
    var hills = height.Layer()
    hills.Amplitude = 12
    hills.Wavelength = 90
    hills.Warp = 25
    r.Layers = [hills]
    var bumps = height.Layer()
    bumps.Kind = .ridged
    bumps.Amplitude = 2
    bumps.Wavelength = 15
    bumps.Seed = 3
    r.Layers.append(bumps)
    let again: height.Recipe
    do { again = try height.DecodeRecipe(r.Encode()) } catch { check(false, "a recipe decodes: \(error)"); return }
    check(again.Layers.count == 2 && again.Layers[1].Kind == .ridged && again.Layers[0].Warp == 25 && again.Seed == 9,
          "a recipe survives JSON")
    let a = height.Generate(r), b = height.Generate(again)
    let range = a.Range()
    check(a.Width == 129 && a.Heights == b.Heights && range.high - range.low > 8 && range.high < 15 && range.low > -15,
          "a recipe makes the same ground every time, within its amplitude (\(range.low)…\(range.high) m)")

    // Thermal erosion: a spike slumps into a cone no steeper than the talus.
    var spike = height.Field(width: 21, depth: 21, spacing: 1)
    spike.Set(10, 10, 10)
    var t = height.ThermalErosion()
    t.Passes = 400
    t.Talus = 0.5
    t.Rate = 0.5
    let before = total(spike)
    height.Slump(&spike, t)
    var steepest: float32 = 0
    for j in 1..<20 { for i in 1..<20 {
        steepest = max(steepest, abs(spike.At(i, j) - spike.At(i + 1, j)), abs(spike.At(i, j) - spike.At(i, j + 1)))
    } }
    check(steepest < 0.6 && abs(total(spike) - before) < 0.01, "thermal erosion slumps a spike to the talus slope, keeping its soil (steepest \(steepest))")

    // Hydraulic erosion: soil moves, about none is lost, and it runs downhill.
    var g = height.Generate(r)
    var rain = height.HydraulicErosion()
    rain.Drops = 4000
    let soil = total(g)
    let t0 = time.Instant.Now()
    height.Rain(&g, rain, seed: 1)
    let ms = t0.Elapsed().AsMilliseconds()
    var moved: float32 = 0
    for k in 0..<g.Heights.count { moved += abs(g.Heights[k] - a.Heights[k]) }
    check(moved > 10 && abs(total(g) - soil) < moved * 0.5, "hydraulic erosion moves soil about (\(Int(moved)) m³ moved, \(Int(total(g) - soil)) net, 4000 drops in \(ms) ms)")

    // Tiles: positions from the field, facing up, skirts below.
    let tile = height.Chunk(a, x: 0, z: 0, cells: 32)
    check(tile.VertexCount == 33 * 33 && tile.TriangleCount == 32 * 32 * 2 && near(tile.Positions[34], a.Point(1, 1)),
          "a tile is the field's points, two triangles a cell")
    var up = true
    for (p0, p1, p2) in tile.Triangles() where (p1 - p0).Cross(p2 - p0).Y <= 0 { up = false }
    check(up, "a tile's triangles face up")
    let coarse = height.Chunk(a, x: 32, z: 32, cells: 32, step: 4, skirt: 2)
    check(coarse.VertexCount == 9 * 9 + 33 && near(coarse.Positions[1], a.Point(36, 32)) && coarse.Positions[81].Y == coarse.Positions[0].Y - 2,
          "a coarse tile takes every 4th point, its skirt hangs 2 m below its edge")
    let big = height.Recipe()
    let t1 = time.Instant.Now()
    var full = big
    full.Layers = [hills]
    let f = height.Generate(full)
    print("      a \(f.Width)² field of one warped layer in \(t1.Elapsed().AsMilliseconds()) ms")
}

func total(f: height.Field) -> float32 {
    var s: float32 = 0
    for h in f.Heights { s += h }
    return s
}

func sweeps() {
    // A bent tube: up, then out sideways; tapering to a point.
    let path = [geom.Vec3(0, 0, 0), geom.Vec3(0, 1, 0), geom.Vec3(0.5, 1.8, 0), geom.Vec3(1.5, 2.2, 0)]
    let t = mesh.Sweep(path, radii: [0.2, 0.15, 0.1, 0], sides: 6, uv: mesh.Rect(0.5, 0, 0.75, 1), capStart: true)
    check(t.VertexCount == 4 * 7 + 1 && t.TriangleCount == 3 * 6 * 2 + 6, "a swept tube is a ring a point, two triangles a side a span, and a cap")
    var outward = true, radius = true
    for i in 0..<4 {
        for s in 0...6 {
            let k = i * 7 + s
            let off = t.Positions[k] - path[i]
            if off.Length() > 1e-4 && off.Normalized().Dot(t.Normals[k]) < 0.999 { outward = false }
            if abs(off.Length() - [float32(0.2), 0.15, 0.1, 0][i]) > 1e-4 { radius = false }
        }
    }
    check(outward && radius, "its rings are at their radii, normals pointing out")
    var faces = true
    for (a, b, c) in t.Triangles() {
        let n = (b - a).Cross(c - a)
        let mid = (a + b + c) / 3
        // Out from the nearest point of the path's spine (a rough test).
        var best = path[0]
        for p in path where (p - mid).Length() < (best - mid).Length() { best = p }
        if n.LengthSquared() > 1e-10 && n.Dot(mid - best) < -1e-4 { faces = false }
    }
    check(faces, "its triangles face out")
    var inRegion = true
    for uv in t.UVs where uv.X < 0.5 - 1e-5 || uv.X > 0.75 + 1e-5 || uv.Y < -1e-5 || uv.Y > 1 + 1e-5 { inRegion = false }
    check(inRegion, "its UVs stay inside the atlas region given")
}
