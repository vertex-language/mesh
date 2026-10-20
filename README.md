# mesh

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![license: MIT](https://img.shields.io/badge/license-MIT-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](LICENSE)

Triangle meshes as plain data: positions, normals and texture coordinates
per vertex, indices three to a triangle. It builds the simple shapes
models are made of, transforms and joins them, and knows nothing about a
GPU: a renderer turns a `Mesh` into whatever vertex layout it draws.
Pure Vertex, so a cooker, a server or a test can build meshes too.

Conventions are `math/geom`'s: right-handed, Y up, triangles wound
counter-clockwise seen from the side their normal points to, V = 0 at the
top of the image.

---

## Packages

### `mesh`

| Name | What it is |
| :--- | :--- |
| `Mesh` | `Positions`, `Normals`, `UVs`, `Colors` (linear RGBA, optional), `Indices`; `Append` (offsets the other mesh's indices), `Transformed(by:)` (normals by the inverse transpose, kept unit), `Bounds`, `Triangles`, `Tangents` (per vertex, with the bitangent's sign, for normal maps). |
| `Rect` | A region of a texture, `U0 V0 U1 V1`; `Rect.Tile(column, row, of: n)` for a cell of an n × n atlas. |
| `BoxUV` | Which `Rect` each of a box's six faces is painted from, laid so the region's top-left is the face's top-left seen from outside. |
| `Quad`, `Box` | A quad from four corners; a box from a `geom.AABB`, 24 vertices and 12 triangles with flat normals. |
| `Sweep` | A tube along a path: a ring of `sides` vertices round each point at its radius (0 for a tip), turned along without twisting, UVs mapped into an atlas region, the start optionally capped. Trunks, branches, staffs, ropes, pipes. |

### `mesh/height`

Heightfields: ground as a grid of heights, the way open-world engines
keep outdoor terrain.

| Name | What it is |
| :--- | :--- |
| `Field` | `Width` × `Depth` points `Spacing` m apart from `Origin`; `At`, `Set`, `Point`, `Sample(x, z)` (bilinear), `Normal`, `NormalAt`, `Slope`, `Range`, `Bounds`, `Raycast`. |
| `Recipe` | Ground as JSON (`Encode`, `DecodeRecipe`): size, spacing, seed, base, noise `Layer`s, erosion, smoothing. A `Layer` is simplex noise summed as `fbm`, `ridged` or `billow`, with an amplitude, a wavelength, octaves, and domain warp (the noise bent by another noise, so it looks grown, not generated). |
| `Generate` | A recipe's ground: layers (rows shared over threads), then `Rain`, then `Slump`, then `Blur`. 513² points with erosion in about 1.3 s. |
| `Rain` | Hydraulic erosion: raindrops run downhill with inertia, carrying soil from where they speed up to where they slow; what a drop still carries when it dries up stays where it ended. |
| `Slump` | Thermal erosion: slopes steeper than the talus settle toward it. |
| `Chunk` | A tile of the field as a `Mesh`: every `step`th point, normals from the whole field (no creases between tiles), world-space UVs, an optional skirt hiding cracks next to coarser tiles. |

---

## Example

```vertex
import "math/geom"
import "mesh"

// A blocky head: an 8-pixel cube painted from a 64 × 64 skin.
let px: float32 = 1.8 / 32
let head = mesh.Box(geom.AABB(center: geom.Vec3(0, 4 * px, 0), size: geom.Vec3(splat: 8 * px)),
                    uv: mesh.BoxUV(all: mesh.Rect(8 / 64, 8 / 64, 16 / 64, 16 / 64)))
let tilted = head.Transformed(by: geom.RotationY(0.3))
```

---

## Testing

```bash
vsc run check    # box shape, winding and normals, bounds, face UV layout, Append, transforms; mesh/height: sampling, normals, raycasts, recipes and JSON, erosion, tiles
```

---

## License

[MIT](LICENSE)
