## Stats of one townsfolk weapon. A WeaponComponent reads these: it starts an
## attack when a rat is within `reach`, telegraphs it for `windup` seconds,
## then strikes and waits `cooldown` before the next one. `kind` picks how it
## strikes:
##   stomp / club: hits every rat within `radius` of the strike point;
##   broom: sweeps an `arc_deg` arc of `radius` in front of the wielder, killing
##          Pups and shoving everything else `knockback` u away;
##   torch: throws a fire patch of `radius` at the rat that burns `burn_time` s
##          and hits any rat standing in it for more than `burn_delay` s.
class_name WeaponDef
extends Resource

@export var id := &""
@export var kind := &"stomp"       # stomp | broom | torch | club
@export var windup := 0.6          # s from the telegraph to the impact
@export var radius := 1.1          # u around the strike point (broom: arc radius)
@export var cooldown := 2.5        # s after an impact
@export var reach := 1.4           # u from the wielder to a rat to start an attack
@export var kills_pups_only := false
@export var arc_deg := 100.0       # broom: width of the sweep
@export var knockback := 3.0       # broom: shove distance for Adults and the Lead Rat
@export var burn_time := 3.0       # torch: s the fire patch burns
@export var burn_delay := 0.25     # torch: s a rat must stand in the fire to be hit
