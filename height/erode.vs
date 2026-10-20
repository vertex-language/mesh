package height

import (
    "math"
    "math/rand"
)

/// Slump is thermal erosion: wherever ground is steeper than t.Talus,
/// some of the excess moves to the lower neighbors, pass after pass, so
/// sharp crests round off and slopes settle at a natural angle.
public func Slump(_ f: inout Field, _ t: ThermalErosion) {
    let w = f.Width, d = f.Depth
    let limit = t.Talus * f.Spacing
    var delta = [float32](repeating: 0, count: w * d)
    for _ in 0..<t.Passes {
        for k in 0..<delta.count { delta[k] = 0 }
        for j in 0..<d {
            for i in 0..<w {
                let c = j * w + i
                let h = f.Heights[c]
                // How far over the limit each lower neighbor is (left,
                // right, below, above; 0 where it isn't, or there's none).
                let o0 = i > 0 ? h - f.Heights[c - 1] - limit : 0
                let o1 = i < w - 1 ? h - f.Heights[c + 1] - limit : 0
                let o2 = j > 0 ? h - f.Heights[c - w] - limit : 0
                let o3 = j < d - 1 ? h - f.Heights[c + w] - limit : 0
                let a0 = math.Max(o0, 0), a1 = math.Max(o1, 0), a2 = math.Max(o2, 0), a3 = math.Max(o3, 0)
                let total = a0 + a1 + a2 + a3
                if total <= 0 { continue }
                // Move half the worst excess (so it doesn't overshoot),
                // shared by how far over each neighbor is.
                let most = math.Max(math.Max(a0, a1), math.Max(a2, a3))
                let moved = most * 0.5 * t.Rate
                delta[c] -= moved
                if a0 > 0 { delta[c - 1] += moved * a0 / total }
                if a1 > 0 { delta[c + 1] += moved * a1 / total }
                if a2 > 0 { delta[c - w] += moved * a2 / total }
                if a3 > 0 { delta[c + w] += moved * a3 / total }
            }
        }
        for k in 0..<delta.count { f.Heights[k] += delta[k] }
    }
}

/// Rain is hydraulic erosion: h.Drops raindrops, each landing at random,
/// running downhill with some inertia, picking soil up where it speeds up
/// and down where it slows or climbs, and drying as it goes. Gullies
/// form where drops gather; hollows fill with what they drop.
public func Rain(_ f: inout Field, _ h: HydraulicErosion, seed: uint32) {
    let w = f.Width, d = f.Depth
    var g = rand.Xorshift128Plus(seed: uint64(seed) &* 2654435761 &+ 1)
    // The brush a drop wears the ground with: points within Radius,
    // weighted by nearness, summing to 1.
    var bi: [int] = []
    var bj: [int] = []
    var bw: [float32] = []
    let r = max(1, h.Radius)
    var sum: float32 = 0
    for j in -r...r {
        for i in -r...r {
            let dist = math.Sqrt(float32(i * i + j * j))
            if dist > float32(r) { continue }
            let weight = 1 - dist / float32(r)
            if weight <= 0 { continue }
            bi.append(i)
            bj.append(j)
            bw.append(weight)
            sum += weight
        }
    }
    for k in 0..<bw.count { bw[k] /= sum }

    // Heights are meters but distances here are points: slopes in meters
    // a point. Spacing scales the soil a drop carries per meter of drop.
    for _ in 0..<h.Drops {
        var px = float32(g.Float64()) * float32(w - 1)
        var pz = float32(g.Float64()) * float32(d - 1)
        var dx: float32 = 0, dz: float32 = 0
        var speed: float32 = 1, water: float32 = 1, sediment: float32 = 0
        var lastI = int(px), lastJ = int(pz)
        for _ in 0..<h.Lifetime {
            let ni = int(px), nj = int(pz)
            lastI = ni
            lastJ = nj
            let u = px - float32(ni), v = pz - float32(nj)
            let here = heightAndGradient(f, px, pz)
            // Heading: mostly downhill, a little of where it was going.
            dx = dx * h.Inertia - here.gx * (1 - h.Inertia)
            dz = dz * h.Inertia - here.gz * (1 - h.Inertia)
            let len = math.Sqrt(dx * dx + dz * dz)
            if len < 1e-6 { break }
            dx /= len
            dz /= len
            px += dx
            pz += dz
            if px < 0 || pz < 0 || px >= float32(w - 1) || pz >= float32(d - 1) { break }
            let change = heightAndGradient(f, px, pz).h - here.h
            let capacity = math.Max(-change * speed * water * h.Capacity, h.MinSlope)
            if sediment > capacity || change > 0 {
                // Uphill: fill the dip it climbs out of; or too laden: drop some.
                let put = change > 0 ? math.Min(change, sediment) : (sediment - capacity) * h.Deposit
                sediment -= put
                f.Heights[nj * w + ni] += put * (1 - u) * (1 - v)
                f.Heights[nj * w + ni + 1] += put * u * (1 - v)
                f.Heights[(nj + 1) * w + ni] += put * (1 - u) * v
                f.Heights[(nj + 1) * w + ni + 1] += put * u * v
            } else {
                // Downhill with room to carry: wear the ground under the brush.
                let take = math.Min((capacity - sediment) * h.Erode, -change)
                for k in 0..<bw.count {
                    let x = ni + bi[k], z = nj + bj[k]
                    if x < 0 || z < 0 || x >= w || z >= d { continue }
                    f.Heights[z * w + x] -= take * bw[k]
                }
                sediment += take
            }
            // Faster downhill, slower up; drying all the while.
            speed = math.Sqrt(math.Max(0, speed * speed - change * h.Gravity))
            water *= 1 - h.Evaporate
        }
        // Dried up or run off the edge: what it carried stays where it was.
        if sediment > 0 { f.Heights[lastJ * w + lastI] += sediment }
    }
}

// heightAndGradient is the height at a point between points (in point
// units) and its slope along X and Z, bilinearly.
func heightAndGradient(_ f: Field, _ px: float32, _ pz: float32) -> (h: float32, gx: float32, gz: float32) {
    let i = int(px), j = int(pz)
    let u = px - float32(i), v = pz - float32(j)
    let w = f.Width
    let a = f.Heights[j * w + i], b = f.Heights[j * w + i + 1]
    let c = f.Heights[(j + 1) * w + i], e = f.Heights[(j + 1) * w + i + 1]
    let gx = (b - a) * (1 - v) + (e - c) * v
    let gz = (c - a) * (1 - u) + (e - b) * u
    let h = a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + e * u * v
    return (h: h, gx: gx, gz: gz)
}
