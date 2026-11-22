## The human progress of the Run: YearEntries sorted by `from_year`, one run of
## rows per District (`district_id`). Each Year uses the last entry of that
## District that has started (see entry_for()).
class_name YearTable
extends Resource

const FALLBACK_DISTRICT := "slums"

@export var entries: Array[YearEntry] = []   # sorted by from_year


## The last entry of `district_id` with from_year <= year. Without one, the
## slums' entry for that Year; before any entry has started, the District's
## (else the slums') earliest entry; null when the table is empty.
func entry_for(year: int, district_id := FALLBACK_DISTRICT) -> YearEntry:
	var e := _latest(year, district_id)
	if e == null and district_id != FALLBACK_DISTRICT:
		e = _latest(year, FALLBACK_DISTRICT)
	if e == null:
		e = _earliest(district_id)
	if e == null:
		e = _earliest(FALLBACK_DISTRICT)
	if e == null:
		e = _earliest("")
	return e


func _latest(year: int, district_id: String) -> YearEntry:
	var best: YearEntry = null
	for e: YearEntry in entries:
		if e == null or e.district_id != district_id:
			continue
		if e.from_year <= year and (best == null or e.from_year >= best.from_year):
			best = e
	return best


## Earliest entry of `district_id` ("" = any District).
func _earliest(district_id: String) -> YearEntry:
	var best: YearEntry = null
	for e: YearEntry in entries:
		if e == null or (district_id != "" and e.district_id != district_id):
			continue
		if best == null or e.from_year < best.from_year:
			best = e
	return best
