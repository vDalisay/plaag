## One District of the city (M6): its layout, its Exterminator, how many
## people live there and where it sits on the M7 Scroll Map.
## The .tres files keep the Exterminator as a path (exterminator_scene_path)
## while the boss scenes may still be missing; exterminator_packed() loads
## whichever is set.
class_name DistrictDef
extends Resource

@export var id := "slums"
@export var title := "The Slums"
@export var layout_style := "slums"          # slums | merchant
## District id that must be beaten first ("" = open from the start).
@export var requires := ""
@export var exterminator_scene: PackedScene
## Used when exterminator_scene is not set (the scene may not exist yet).
@export var exterminator_scene_path := ""
@export var exterminator_title := "The Rat-catcher"
## Outdoor townsfolk at Round start.
@export var wanderers := 25
## Residents per house: a random count in [x, y], spawned indoors.
@export var residents_per_house := Vector2i(0, 3)
## For the M7 Scroll Map.
@export var map_position := Vector2.ZERO


## The Exterminator scene, or null when neither the scene nor its path exists.
func exterminator_packed() -> PackedScene:
	if exterminator_scene:
		return exterminator_scene
	if not exterminator_scene_path.is_empty() and ResourceLoader.exists(exterminator_scene_path):
		return load(exterminator_scene_path) as PackedScene
	return null
