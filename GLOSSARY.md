# Plaag

A plague incremental: you play a rat colony spreading the Black Death through a medieval city, in short rounds with upgrades in between.

## Language

### Player

**Lead Rat**:
The single rat the player steers directly. The rest of the Colony follows it.
_Avoid_: Player rat, hero, avatar

**Colony**:
All of the player's rats, the Lead Rat included. It starts as the Lead Rat alone and grows from there.
_Avoid_: Swarm, horde, pack

**Adult**:
A full-grown rat. Only Adults fight (Bite), and only Adults produce Pups.
_Avoid_: Grown rat, soldier

**Pup**:
A young rat born when an Adult Feeds. It travels with the Colony but doesn't fight until it Matures.
_Avoid_: Baby rat, small rat, spawn

**Feed**:
A rat eating a corpse. When an Adult Feeds, it produces a Pup; when a Pup Feeds, it Matures sooner.
_Avoid_: Eat, consume

**Mature**:
A Pup becoming an Adult once its maturity time runs out.
_Avoid_: Grow up, level up

**Bite**:
The Colony's automatic attack: a rat bites the nearest person in range, on a cooldown, adding a small chunk of Infection and making it climb faster.
_Avoid_: Attack, hit

### Plague

**Contagion**:
An infected person passing the plague to people near them. Unlocked as an upgrade; not available from the start.
_Avoid_: Chain spread, NPC spread

**Hide**:
The whole Colony slipping into a house with the Lead Rat. Pursuers lose track of it while it Bites the people inside.
_Avoid_: Duck, take cover

**Raid**:
Sending a few Adults into a nearby house, on a cooldown, to infect the people inside while the Lead Rat keeps moving.
_Avoid_: Send rats, infiltrate

### Townsfolk

**Fear**:
How frightened a townsperson is, based on how many rats are near them. It has three bands: Fight (they attack), Uneasy (they keep their distance) and Flee (they run).
_Avoid_: Panic, morale

**Vigilance**:
How alert and organised the town is during a Round. It rises with time in the Round and starts higher in later Years. The higher it is, the more often the strongest townsfolk spawn.
_Avoid_: Alarm, difficulty, threat

**Exterminator**:
A boss who appears once enough of a District is infected and tries to wipe out the plague. Its Infection must reach 100% to unlock the next District.
_Avoid_: Boss, hunter, rat-catcher (as the generic term)

**Infection**:
A person's plague meter, from 0 to 100%. Anyone above 0% is infected; the meter keeps rising on its own over time, and the person dies at 100%. Bites raise the rate at which it climbs.
_Avoid_: Health, HP, Resistance, damage

**Cleanse**:
Lowering a person's Infection. Only Exterminators (the Plague Doctor among them) can Cleanse; ordinary townsfolk never recover.
_Avoid_: Cure, heal

**Hygiene**:
A District-wide trait that makes people there harder to infect.
_Avoid_: Cleanliness

**Guard**:
A townsperson who attacks rats whatever their Fear. Found in richer Districts.
_Avoid_: Soldier, watchman

### Currencies

**Pestilence**:
The common currency, paid once when a person first becomes infected.
_Avoid_: Points, infection currency

**Bones**:
The rarer currency, paid when an infected person dies.
_Avoid_: Souls, death currency

### Structure

**District**:
One area of the city, played one Round at a time. Each District has its own Exterminator, who must be beaten to unlock the next District.
_Avoid_: Level, zone, area

**Scroll Map**:
The parchment map of the city shown between Rounds. Here you pick a District; beaten Districts are inked over, and the houses killed in your best Round are crossed out.
_Avoid_: World map, level select

**Year**:
The city's point in time, shared by every District, which advances by one each time the Lead Rat dies. The Year decides which kinds of townsfolk exist. Each Year, townsfolk are better equipped and cleaner, and the city looks more developed. There is no deadline.
_Avoid_: Era, age, turn

**Carry-over**:
The share of the previous Round's final Colony size that the next Round starts with. It is 0% by default and raised through the Upgrade Tree.
_Avoid_: Persistence, legacy

**Upgrade Tree**:
The branching set of permanent upgrades, drawn on parchment, that you buy between Rounds.
_Avoid_: Skill tree, shop

**Round**:
A 60–120 second stretch of play that ends when the timer runs out or the Lead Rat dies.
_Avoid_: Run, wave, level
