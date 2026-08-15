# Low-poly soldier characters

Three soldier archetypes — bodies, weapons and the vantablack / black-flame /
ocular / skull-visor shading — built to run on weak hardware.

Everything is generated in code at load time. There are no model files, no
textures and no imported assets anywhere in this system: a character is a
`.tres` profile plus a script, and the mesh is welded together by `SurfaceTool`
when the node enters the tree. That is not a stunt — it is what makes the three
archetypes share one skeleton layout, one body material and one set of
proportions, so a fourth soldier costs a resource file rather than a modelling
session.

This is a self-contained subsystem. It does not touch the existing sewer game.

## Try it

```
godot --path . scenes/dev/CharacterForge.tscn
```

Controls: `A`/`D` orbit, `W`/`S` zoom, `R` auto-orbit, `1`/`2`/`3` quality
preset, `Space` muzzle flash, `Tab` cycle the framed character. The HUD reports
live triangle counts.

`--capture <file.png>` renders a few frames, writes a screenshot and quits, so
the scene doubles as a visual regression check. `--focus <0-2>` and
`--quality <0-2>` narrow what it captures.

## The three archetypes

| | Wraith | Spectre | Reaper |
|---|---|---|---|
| Role | Marksman | Vanguard | Heavy |
| Head | Single ranging optic under a ghillie shroud | Four-lamp night rack | Skull behind an armoured pane |
| Weapon | Suppressed precision rifle on a bipod | Suppressed carbine | Vented support gun |
| Stance | Kneeling, braced | Advancing | Squared, hip-fired |
| Triangles | 1304 | 1274 | 1178 |

About 3,750 triangles for the whole squad, weapons included. For scale, a single
Quake 3 player model was roughly 700.

## How the geometry is built

`LowPoly.gd` is a thin builder over `SurfaceTool` offering tapered boxes,
faceted tubes, bevelled plates and lens discs. Every face carries its own
vertices and its own hard normal, which is what produces the faceted read and
means there are no smoothing groups to maintain.

Three decisions carry most of the weight:

**Vertex colour is material data, not tint.** `COLOR.r` is an armour-plate mask,
`COLOR.g` a cloth mask, `COLOR.b` dust wear. The body shader reads those to give
plate, cloak and webbing different responses from one material with no texture
fetch. This is the reason a whole character is one draw call rather than four.

**Skinning is rigid.** Every vertex binds to exactly one bone at weight 1.0.
On a mesh this coarse there are not enough vertices across a joint for a smooth
weight gradient to read, and rigid binding keeps the limbs crisply faceted when
animated — which is the look we want anyway. Bind poses come from
`create_skin_from_rest_transforms()` because the geometry is authored in model
space at rest.

**Stances are poses, not geometry.** The rest pose is neutral (arms hanging,
legs straight) and each stance is a table of bone rotations in `SoldierRig`.
The kneeling angles are solved against the reference skeleton rather than
eyeballed. The weapon is aimed by cancelling the hand bone's accumulated
rotation, so you can change an arm pose freely and the muzzle still points
forward.

Cloth — the cloak and the ghillie shroud — is built as independent vertical
ribbons. The gaps *between* ribbons are the tatters, so a shredded silhouette
costs nothing extra. Ribbons overlap at the shoulder and separate lower down; a
cloak shredded all the way to the collar reads as a grass skirt.

## The shaders

### Vantablack (`shaders/vantablack.gdshader`)

The reference material absorbs ~99.965% of incident light. Rendered literally
that is a hole in the frame: no form, no readable silhouette against a dark
level, and no way to tell which way a character is facing. The shader keeps the
look of total absorption while restoring the three cues that survive on a real
ultra-black surface:

1. **Grazing-angle scatter** — a very tight Fresnel (`edge_power` 8) that only
   opens up within a few degrees of the silhouette. Light-independent on
   purpose: it stands in for environment bounce, so the figure never fully
   vanishes.
2. **A backlight kicker** — a per-light rim that peaks when the light sits
   *behind* the subject, keyed off `dot(LIGHT, VIEW)` going negative.
3. **Material breaks** — hard armour edges catch a sliver where cloth does not,
   driven by the vertex-colour masks. Cloth gets roughly a third of the plate's
   rim response; without that split the cloak tatters read as chrome.

`absorption` is the master dial: 1.0 is true vantablack and silhouette-only,
lower trades the effect for gameplay readability. It ships at 0.94.

**The lighting rig matters more than the shader.** A vantablack character lit
conventionally — bright key from behind the camera — is a silhouette-shaped
hole, because the key has nothing to reflect off. These characters read only
when light comes from behind them. `CharacterForge` is deliberately backwards
from a three-point setup: cool backlight as the key, hard rim kickers at the
rear quarters, and a frontal fill so weak it only just keeps the chest from
disappearing. That fill is the single most sensitive value in the scene; raise
it and the vantablack stops reading almost immediately.

### Silhouette edge (`shaders/silhouette_edge.gdshader`)

An inverted-hull pass chained onto the body material. Two departures from the
stock version: it expands in **clip** space so the edge holds a fixed pixel
width at any range — distance is exactly when a vantablack figure dissolves into
the fog — and it defaults to a **light** colour. A dark outline on a dark
character in a dark corridor separates nothing.

### Black flames (`shaders/black_flame.gdshader`)

Fire is normally additive, and you cannot add darkness. What the concept art
shows is not burning light but burning *soot*: a plume that absorbs the fog
behind it and warps it with heat. So this renders as an absorber:

- the background is sampled, darkened by plume density and written back;
- the sample is displaced along the plume's own noise gradient, giving the heat
  shimmer that lets a black plume read against a black character;
- the thin dissolving edge lifts toward grey, where real soot catches ambient
  light.

That ash edge is load-bearing. Against a lit backdrop the plume works by
absorption, but over a night sky an absorber has nothing to subtract from, and
without a visible soot rim the effect disappears entirely. If your levels are
very dark, `ash_width` is the knob.

Noise is a 128px seamless `FastNoiseLite` texture generated once and shared by
every plume in the level. Per-plume variation comes from an `instance uniform
float phase`, so all plumes share one material and still burn out of step.

### Oculars (`shaders/ocular.gdshader`, `ocular_flare.gdshader`)

The bloom does not come from the shader. It comes from writing colour above the
`WorldEnvironment` glow HDR threshold and letting the existing glow pass spread
it, which costs nothing per lamp. This is why `energy` sits well above 1.0 — at
1.0 the lenses are flat white circles with no halo. The lens shader is opaque
and unshaded: no blending, no sorting, no lighting.

The additive flare card behind the lamps supplies the anamorphic streak that
post-process glow cannot, and it is one quad with no texture fetch. Depth
*testing* stays on — a flare that draws through walls is a wallhack, not a
lighting effect.

### Skull behind glass (`shaders/skull_visor.gdshader`)

Two problems, solved separately.

**Depth.** The skull has to sit *inside* the helmet. Modelling an actual skull
behind an actual pane means a second transparent surface, sorting between them,
and a few hundred triangles on something seen through dark glass. Instead the
interior is rendered by parallax offset: the visor's UV is displaced along the
tangent-space view vector, so as the camera orbits, the skull slides against the
frame exactly as real geometry at that depth would. One surface, no sorting, and
the illusion holds until the camera is nearly edge-on — by which point the
Fresnel term has already turned the glass opaque.

**The skull itself** is a signed distance field, not a texture. No atlas, no
import step, no mip shimmer on a small screen element, and it stays crisp when a
player walks right up to it. It also makes the face uniform-driven: socket tilt,
jaw width and tooth count are parameters, so several archetypes can share one
material and still read as different skulls.

The pane is **curved**, not flat. A flat pane has one normal, so its Fresnel is
constant across the whole surface and the glass reads as a sticker; curvature is
what makes the edges flare while the centre stays clear. The pane also sits
*proud* of the helmet shell — tucked inside it, the visor is occluded by the
very helmet it belongs to.

The glass stays lit rather than unshaded, so it catches the same rim lights as
the armour. Unshaded glass is the classic tell that a visor is a decal.

## Performance

Per character, three surfaces for the body/lenses/visor plus two for the weapon,
and that number does not grow with the number of pouches, plates or lamps —
anything sharing a material is welded into one surface. On top of that sit one
flare card and one draw per flame plume, and those are the parts that get culled
first.

`SoldierRig` stages the falloff so the most expensive thing goes first:

| Distance | Dropped |
|---|---|
| > 9 m | Plumes stop sampling the screen and depth buffers |
| > 14 m | Flare card |
| > 18 m | Plumes entirely |

The `LOW` preset additionally drops character shadows, the flare and the ocular
light. Ocular lights use Godot's engine-side `distance_fade`, so they cost
nothing to maintain per frame. There is one light for the whole four-lamp
cluster, not one per lamp.

**Renderer note.** The plumes' soft-edge path reads the depth buffer using the
Forward+ convention. The Compatibility renderer does not share it — there the
recipe reads a near-zero scene depth and erases the plume rather than softening
it. `SoldierRig` checks `RenderingServer.get_current_rendering_method()` and
enables the feature only where it works, and the uniform defaults to off so a
plume never silently vanishes on an unsupported backend.

## Adding a fourth archetype

Write a `.tres` against `SoldierProfile` — proportions, head style, cloth,
flame emitter positions, loadout — and point a `SoldierRig` at it. Add geometry
code only for a genuinely new head assembly or weapon; everything else is
already parameterised.

## Files

```
shaders/vantablack.gdshader        body and armour
shaders/silhouette_edge.gdshader   constant-width outline pass
shaders/black_flame.gdshader       absorbing/refracting plumes
shaders/ocular.gdshader            emissive lenses
shaders/ocular_flare.gdshader      additive flare card
shaders/skull_visor.gdshader       parallax interior + SDF skull + glass

scripts/characters/LowPoly.gd              flat-shaded primitive builder
scripts/characters/SoldierProfile.gd       per-archetype resource
scripts/characters/SoldierMeshFactory.gd   skeleton, body, heads, cloth
scripts/characters/WeaponMeshFactory.gd    the three weapons
scripts/characters/SoldierMaterials.gd     material construction and caching
scripts/characters/SoldierRig.gd           runtime assembly, stances, LOD

resources/soldiers/*.tres          the three archetypes
scenes/dev/CharacterForge.tscn     turntable preview and capture harness
```
