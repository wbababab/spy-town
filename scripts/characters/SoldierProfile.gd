class_name SoldierProfile extends Resource

## Everything that distinguishes one soldier archetype from another.
##
## The three characters in the concept art share a single mesh factory, a single
## body material and a single skeleton layout. What makes them read as different
## silhouettes is entirely in this resource: proportions, which head assembly to
## build, whether they carry cloth, and where the plumes attach. Adding a fourth
## archetype should mean writing a .tres, not writing geometry code.

enum Head {
	NVG_CLUSTER,   ## Four-lamp night-vision rack on a forehead mount.
	SINGLE_OCULAR, ## One large ranging lens under a draped shroud.
	SKULL_VISOR,   ## Full-face pane with the skull sitting behind it.
}

enum Weapon {
	MARKSMAN, ## Long suppressed precision rifle on a bipod.
	CARBINE,  ## Compact suppressed assault carbine.
	HEAVY,    ## Vented heavy support gun with a side energy cell.
}

enum Stance {
	ADVANCE, ## Walking forward, weapon at the ready.
	KNEEL,   ## Braced on one knee behind the bipod.
	HIPFIRE, ## Squared up, firing from the hip.
}

@export_group("Identity")
@export var profile_id: StringName = &""
@export var display_name: String = ""
@export var callsign: String = ""

@export_group("Build")
## Total height in metres, heel to crown of the helmet.
@export_range(1.4, 2.4, 0.01) var height: float = 1.85
## Shoulder span in metres. Drives how wide the chest and pauldrons read.
@export_range(0.30, 0.80, 0.005) var shoulder_width: float = 0.46
## Multiplier on limb and torso thickness. The heavy sits near 1.3, the
## marksman near 0.85.
@export_range(0.6, 1.8, 0.01) var bulk: float = 1.0
@export var stance: Stance = Stance.ADVANCE

@export_group("Head")
@export var head_style: Head = Head.NVG_CLUSTER
@export var ocular_color: Color = Color(1.0, 1.0, 1.0)
@export var ocular_halo: Color = Color(0.62, 0.76, 1.0)
## Emission multiplier. Must exceed the environment's glow HDR threshold for the
## lamps to bloom at all - below about 1.5 they read as flat white circles.
@export_range(0.0, 24.0, 0.1) var ocular_energy: float = 6.5
@export_range(0.0, 0.12, 0.001) var ocular_radius: float = 0.032

@export_group("Cloth")
@export var has_cloak: bool = false
## Length of the cloak in metres, measured from the shoulders down.
@export_range(0.2, 1.6, 0.01) var cloak_length: float = 1.0
## 0 = clean hem, 1 = heavily torn. Drives the per-strip length jitter.
@export_range(0.0, 1.0, 0.01) var cloak_shred: float = 0.55
@export_range(4, 20, 1) var cloak_strips: int = 11
## Ragged netting over the head and shoulders, for the marksman's ghillie.
@export var has_shroud: bool = false

@export_group("Flames")
## Local-space emitter positions, relative to the character's feet.
@export var flame_points: PackedVector3Array = PackedVector3Array()
@export_range(0.0, 3.0, 0.01) var flame_height: float = 0.9
@export_range(0.0, 2.0, 0.01) var flame_width: float = 0.45
@export_range(0.0, 1.0, 0.01) var flame_opacity: float = 1.0

@export_group("Loadout")
@export var weapon: Weapon = Weapon.CARBINE
@export var has_backpack: bool = false
@export var has_thigh_holster: bool = true
## Number of magazine pouches across the chest rig.
@export_range(0, 5, 1) var chest_pouches: int = 3


## Uniform scale relative to the 1.85 m reference the factory is authored at.
func scale_factor() -> float:
	return height / 1.85
