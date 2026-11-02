package height

import (
    "encoding/json"
    "math"
    "math/geom"
    "math/noise"
    "sync"
)

/// Shape is how a noise layer's octaves are summed.
public enum Shape: Equatable {
    /// Plain fractal noise: rolling ground.
    case fbm
    /// Folded into creases: ridges and crests.
    case ridged
    /// Folded the other way: rounded mounds.
    case billow
}

/// Layer is one noise added to the ground.
public struct Layer {
    public var Kind = Shape.fbm
    /// How tall, meters: the layer adds -Amplitude…+Amplitude (ridged and
    /// billow, 0…Amplitude).
    public var Amplitude: float32 = 10
    /// How wide its features are, meters (the first octave's wavelength).
    public var Wavelength: float32 = 200
    public var Octaves = 4
    /// Each octave's amplitude times this…
    public var Gain: float32 = 0.5
    /// …and its frequency times this.
    public var Lacunarity: float32 = 2
    /// How far, meters, the noise is pushed about by another noise before
    /// it is read (domain warping): 0 for none. It bends straight noise
    /// into shapes that look grown.
    public var Warp: float32 = 0
    /// Added to the recipe's seed, so two layers differ.
    public var Seed: uint32 = 0

    public init() {}
}

/// ThermalErosion is slumping: wherever ground is steeper than Talus (rise over
/// run), Rate of the excess moves downhill each pass.
public struct ThermalErosion {
    public var Passes = 0
    public var Talus: float32 = 0.7
    public var Rate: float32 = 0.25

    public init() {}
}

/// HydraulicErosion is rain: Drops raindrops, each falling at random, running
/// downhill, picking up soil where it speeds up and dropping it where it
/// slows, then drying up. Its fields are those of the usual particle
/// method (Hans Theobald Beyer, 2015).
public struct HydraulicErosion {
    public var Drops = 0
    /// Steps a drop lives.
    public var Lifetime = 40
    /// How much a drop keeps its heading, 0…1, against the slope's pull.
    public var Inertia: float32 = 0.05
    /// How much soil a drop can carry, for its speed, water and slope.
    public var Capacity: float32 = 4
    /// The least slope a drop counts, so slow drops on flats still carry.
    public var MinSlope: float32 = 0.01
    /// How fast a drop picks soil up, and puts it down, 0…1.
    public var Erode: float32 = 0.3
    public var Deposit: float32 = 0.3
    /// How much water a drop loses each step, 0…1.
    public var Evaporate: float32 = 0.02
    public var Gravity: float32 = 4
    /// The radius, in points, a drop wears the ground over.
    public var Radius = 2

    public init() {}
}

/// Recipe is ground: how big, how fine, and how it's made. Small, plain
/// data, saved as JSON (Encode, DecodeRecipe), the way a humanoid recipe
/// is a person.
public struct Recipe {
    public var Name = ""
    /// Meters along X and Z.
    public var Size: float32 = 512
    /// Meters between points.
    public var Spacing: float32 = 1
    public var Seed: uint32 = 1
    /// Every height starts here, meters.
    public var Base: float32 = 0
    public var Layers: [Layer] = []
    public var Thermal = ThermalErosion()
    public var Hydraulic = HydraulicErosion()
    /// Smoothing passes after erosion (each a light blur): 0 for none.
    public var Smooth = 0

    public init() {}

    /// Points along each side.
    public var Points: int { return int(math.Round(Size / Spacing)) + 1 }
}

/// Generate builds a recipe's ground, centered on the origin: noise
/// layers, then hydraulic and thermal erosion, then smoothing.
public func Generate(r: Recipe) -> Field {
    let n = r.Points
    let half = float32(n - 1) * r.Spacing / 2
    var f = Field(width: n, depth: n, spacing: r.Spacing, origin: geom.Vec2(-half, -half), fill: r.Base)
    for l in r.Layers { Add(&f, l, seed: r.Seed) }
    // Rain carves, then slumping settles what it left too steep (the
    // pits and gully walls a drop's brush digs).
    if r.Hydraulic.Drops > 0 { Rain(&f, r.Hydraulic, seed: r.Seed) }
    if r.Thermal.Passes > 0 { Slump(&f, r.Thermal) }
    for _ in 0..<r.Smooth { Blur(&f, amount: 0.5) }
    return f
}

/// Add puts a noise layer onto the ground, rows shared out over
/// `threads` threads.
public func Add(f: inout Field, l: Layer, seed: uint32, threads: int = 8) {
    let w = f.Width, d = f.Depth
    let ox = f.Origin.X, oz = f.Origin.Y, sp = f.Spacing
    let n = max(1, min(threads, d))
    var bands: [band] = []
    var workers: [sync.Thread] = []
    for k in 0..<n {
        let b = band(from: d * k / n, to: d * (k + 1) / n)
        bands.append(b)
        workers.append(sync.Thread.spawn {
            b.values = layerRows(l, seed: seed, width: w, from: b.from, to: b.to, ox: ox, oz: oz, spacing: sp)
        })
    }
    for t in workers { t.join() }
    for b in bands {
        let base = b.from * w
        for k in 0..<b.values.count { f.Heights[base + k] += b.values[k] }
    }
}

// band is rows a thread fills.
final class band {
    let from: int
    let to: int
    var values: [float32] = []

    init(from: int, to: int) {
        self.from = from
        self.to = to
    }
}

// layerRows is a layer's heights for rows from..<to of a field.
func layerRows(l: Layer, seed: uint32, width w: int, from: int, to: int, ox: float32, oz: float32, spacing: float32) -> [float32] {
    let s = noise.Simplex(seed: seed &+ l.Seed &* 7919)
    let wx = noise.Simplex(seed: seed &+ l.Seed &* 7919 &+ 101)
    let wz = noise.Simplex(seed: seed &+ l.Seed &* 7919 &+ 202)
    let freq = 1 / math.Max(l.Wavelength, 0.001)
    // The octaves' amplitudes add to at most this: dividing by it keeps
    // the layer within ±Amplitude whatever the octave count.
    var total: float32 = 0
    var a: float32 = 1
    let octaves = max(1, l.Octaves)
    for _ in 0..<octaves {
        total += a
        a *= l.Gain
    }
    var out = [float32](repeating: 0, count: (to - from) * w)
    for j in from..<to {
        for i in 0..<w {
            var x = ox + float32(i) * spacing
            var z = oz + float32(j) * spacing
            if l.Warp > 0 {
                // Warp at half the layer's frequency, so the bends are wide.
                let u = x * freq * 0.5, v = z * freq * 0.5
                x += wx.At(u, v) * l.Warp
                z += wz.At(u + 31.7, v - 17.3) * l.Warp
            }
            var sum: float32 = 0
            var amp: float32 = 1
            var fr = freq
            for _ in 0..<octaves {
                let v = s.At(x * fr, z * fr)
                switch l.Kind {
                case .fbm: sum += v * amp
                case .ridged: sum += (1 - math.Abs(v)) * (1 - math.Abs(v)) * amp
                case .billow: sum += math.Abs(v) * amp
                }
                amp *= l.Gain
                fr *= l.Lacunarity
            }
            out[(j - from) * w + i] = sum / total * l.Amplitude
        }
    }
    return out
}

/// Blur softens the ground: each point moves `amount` of the way to the
/// average of its four neighbors.
public func Blur(f: inout Field, amount: float32) {
    let old = f.Heights
    let w = f.Width
    for j in 0..<f.Depth {
        for i in 0..<w {
            let l = old[j * w + max(0, i - 1)], r = old[j * w + min(w - 1, i + 1)]
            let d = old[max(0, j - 1) * w + i], u = old[min(f.Depth - 1, j + 1) * w + i]
            let c = old[j * w + i]
            f.Heights[j * w + i] = c + ((l + r + d + u) / 4 - c) * amount
        }
    }
}

// ---- JSON ----

extension Recipe {
    /// Encode writes the recipe as JSON.
    public func Encode() -> string {
        var o = json.Object()
        o["version"] = .number("1")
        o["name"] = .string(Name)
        o["size"] = num(Size)
        o["spacing"] = num(Spacing)
        o["seed"] = .number("\(Seed)")
        o["base"] = num(Base)
        var layers: [json.Value] = []
        for l in Layers {
            var x = json.Object()
            x["shape"] = .string(l.Kind == .ridged ? "ridged" : (l.Kind == .billow ? "billow" : "fbm"))
            x["amplitude"] = num(l.Amplitude)
            x["wavelength"] = num(l.Wavelength)
            x["octaves"] = .number("\(l.Octaves)")
            x["gain"] = num(l.Gain)
            x["lacunarity"] = num(l.Lacunarity)
            x["warp"] = num(l.Warp)
            x["seed"] = .number("\(l.Seed)")
            layers.append(.object(x))
        }
        o["layers"] = .array(layers)
        var t = json.Object()
        t["passes"] = .number("\(Thermal.Passes)")
        t["talus"] = num(Thermal.Talus)
        t["rate"] = num(Thermal.Rate)
        o["thermal"] = .object(t)
        var h = json.Object()
        h["drops"] = .number("\(Hydraulic.Drops)")
        h["lifetime"] = .number("\(Hydraulic.Lifetime)")
        h["inertia"] = num(Hydraulic.Inertia)
        h["capacity"] = num(Hydraulic.Capacity)
        h["minSlope"] = num(Hydraulic.MinSlope)
        h["erode"] = num(Hydraulic.Erode)
        h["deposit"] = num(Hydraulic.Deposit)
        h["evaporate"] = num(Hydraulic.Evaporate)
        h["gravity"] = num(Hydraulic.Gravity)
        h["radius"] = .number("\(Hydraulic.Radius)")
        o["hydraulic"] = .object(h)
        o["smooth"] = .number("\(Smooth)")
        return json.Encode(.object(o), indent: "  ")
    }
}

/// DecodeRecipe reads a recipe written by Encode (or by hand; what's
/// missing keeps its default).
public func DecodeRecipe(text: string) throws -> Recipe {
    let v = try json.Parse(text)
    var r = Recipe()
    r.Name = v["name"]?.String ?? ""
    r.Size = f32(v["size"], r.Size)
    r.Spacing = math.Max(0.05, f32(v["spacing"], r.Spacing))
    r.Seed = uint32(max(0, v["seed"]?.Int ?? int64(r.Seed)))
    r.Base = f32(v["base"], r.Base)
    for x in v["layers"]?.Array ?? [] {
        var l = Layer()
        let s = x["shape"]?.String ?? "fbm"
        l.Kind = s == "ridged" ? .ridged : (s == "billow" ? .billow : .fbm)
        l.Amplitude = f32(x["amplitude"], l.Amplitude)
        l.Wavelength = f32(x["wavelength"], l.Wavelength)
        l.Octaves = int(x["octaves"]?.Int ?? int64(l.Octaves))
        l.Gain = f32(x["gain"], l.Gain)
        l.Lacunarity = f32(x["lacunarity"], l.Lacunarity)
        l.Warp = f32(x["warp"], l.Warp)
        l.Seed = uint32(max(0, x["seed"]?.Int ?? 0))
        r.Layers.append(l)
    }
    if let t = v["thermal"] {
        r.Thermal.Passes = int(t["passes"]?.Int ?? 0)
        r.Thermal.Talus = f32(t["talus"], r.Thermal.Talus)
        r.Thermal.Rate = f32(t["rate"], r.Thermal.Rate)
    }
    if let h = v["hydraulic"] {
        var d = HydraulicErosion()
        d.Drops = int(h["drops"]?.Int ?? 0)
        d.Lifetime = int(h["lifetime"]?.Int ?? int64(d.Lifetime))
        d.Inertia = f32(h["inertia"], d.Inertia)
        d.Capacity = f32(h["capacity"], d.Capacity)
        d.MinSlope = f32(h["minSlope"], d.MinSlope)
        d.Erode = f32(h["erode"], d.Erode)
        d.Deposit = f32(h["deposit"], d.Deposit)
        d.Evaporate = f32(h["evaporate"], d.Evaporate)
        d.Gravity = f32(h["gravity"], d.Gravity)
        d.Radius = int(h["radius"]?.Int ?? int64(d.Radius))
        r.Hydraulic = d
    }
    r.Smooth = int(v["smooth"]?.Int ?? 0)
    return r
}

func f32(v: json.Value?, fallback: float32) -> float32 {
    guard let d = v?.Double else { return fallback }
    return float32(d)
}

func num(x: float32) -> json.Value {
    return .number("\(Double(Int((x * 10000).rounded())) / 10000)")
}
