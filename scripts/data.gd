class_name Data
extends RefCounted
## Game data. Like Age of Empires, every race builds from one shared template of units
## (`UNITS`), buildings (`BUILDINGS`) and technologies (`TECHS`); like StarCraft, each race
## (`RACES`) gives them its own names and looks, leaves some out, and has a passive bonus and
## one unique technology. `MAPS` are the four map templates.

const CELL := 2.0                   # metres per path grid cell
const MAP_CELLS := 80               # the map is MAP_CELLS x MAP_CELLS cells
const MAX_PLAYERS := 4
const START_GOLD := 300
const START_AETHER := 150
const MAX_SUPPLY := 120

const TEAM_COLORS := [Color(0.86, 0.16, 0.14), Color(0.16, 0.42, 0.95), Color(0.95, 0.78, 0.12), Color(0.18, 0.78, 0.45)]
const TEAM_NAMES := ["Red", "Blue", "Gold", "Green"]

# --- shared unit template ---------------------------------------------------------------
# hp, atk, cd (seconds between attacks), range (metres beyond both radii), arm (melee armour),
# parm (pierce armour), speed (m/s), sight, cost, supply, time (seconds to train), tier,
# from (building), dmg (melee/pierce/magic/siege), cls (classes for bonus damage),
# bonus (extra damage against a class), air (can hit flyers), radius, splash (metres)
const UNIT_ORDER := ["worker", "infantry", "spear", "archer", "cavalry", "siege", "flyer", "caster", "champion"]
const UNITS := {
	"worker": {"role": "Worker", "hp": 40, "atk": 3, "cd": 1.5, "range": 0.3, "arm": 0, "parm": 0, "speed": 4.0, "sight": 9.0,
		"cost": {"g": 50}, "supply": 1, "time": 12.0, "tier": 1, "from": "hall", "dmg": "melee", "cls": ["worker"], "radius": 0.45,
		"desc": "Gathers gold and aether, builds and repairs."},
	"infantry": {"role": "Infantry", "hp": 65, "atk": 8, "cd": 1.2, "range": 0.3, "arm": 1, "parm": 1, "speed": 3.7, "sight": 10.0,
		"cost": {"g": 55, "a": 15}, "supply": 1, "time": 16.0, "tier": 1, "from": "barracks", "dmg": "melee", "cls": ["infantry"],
		"bonus": {"building": 3, "spear": 3}, "radius": 0.5, "desc": "Sturdy melee soldier. Beats spearmen."},
	"spear": {"role": "Spearman", "hp": 50, "atk": 5, "cd": 1.3, "range": 0.6, "arm": 0, "parm": 0, "speed": 3.7, "sight": 10.0,
		"cost": {"g": 35, "a": 20}, "supply": 1, "time": 14.0, "tier": 1, "from": "barracks", "dmg": "melee", "cls": ["infantry", "spear"],
		"bonus": {"mounted": 14, "champion": 6}, "radius": 0.5, "desc": "Cheap pikes. Shreds cavalry and champions."},
	"archer": {"role": "Archer", "hp": 35, "atk": 5, "cd": 1.6, "range": 7.0, "arm": 0, "parm": 0, "speed": 3.6, "sight": 11.0,
		"cost": {"g": 30, "a": 40}, "supply": 1, "time": 15.0, "tier": 1, "from": "barracks", "dmg": "pierce", "cls": ["ranged"],
		"bonus": {"infantry": 2, "air": 2}, "air": true, "radius": 0.45, "desc": "Fires from range, hits flyers. Weak against cavalry."},
	"cavalry": {"role": "Cavalry", "hp": 120, "atk": 9, "cd": 1.4, "range": 0.4, "arm": 2, "parm": 2, "speed": 6.2, "sight": 11.0,
		"cost": {"g": 80, "a": 45}, "supply": 2, "time": 22.0, "tier": 2, "from": "stable", "dmg": "melee", "cls": ["mounted"],
		"bonus": {"ranged": 7, "siege": 10}, "radius": 0.75, "desc": "Fast riders. Run down archers and siege; fear spears."},
	"siege": {"role": "Siege engine", "hp": 150, "atk": 18, "cd": 4.0, "range": 9.0, "arm": 1, "parm": 6, "speed": 2.6, "sight": 11.0,
		"cost": {"g": 130, "a": 120}, "supply": 3, "time": 30.0, "tier": 2, "from": "workshop", "dmg": "siege", "cls": ["siege"],
		"bonus": {"building": 70, "siege": 15}, "radius": 0.9, "splash": 1.8, "minrange": 2.5, "desc": "Long-range engine that wrecks buildings. Helpless up close."},
	"flyer": {"role": "Flyer", "hp": 85, "atk": 7, "cd": 1.4, "range": 4.0, "arm": 1, "parm": 0, "speed": 5.4, "sight": 13.0,
		"cost": {"g": 70, "a": 90}, "supply": 2, "time": 24.0, "tier": 2, "from": "sanctum", "dmg": "pierce", "cls": ["air"],
		"bonus": {"siege": 10, "air": 3}, "air": true, "fly": true, "radius": 0.7, "desc": "Flies over everything. Only archers, flyers, casters and towers can hit it."},
	"caster": {"role": "Caster", "hp": 50, "atk": 6, "cd": 1.8, "range": 6.0, "arm": 0, "parm": 1, "speed": 3.6, "sight": 11.0,
		"cost": {"g": 40, "a": 100}, "supply": 2, "time": 24.0, "tier": 2, "from": "sanctum", "dmg": "magic", "cls": ["ranged"],
		"air": true, "heal": 5.0, "radius": 0.45, "desc": "Heals nearby allies; its bolts ignore armour."},
	"champion": {"role": "Champion", "hp": 420, "atk": 24, "cd": 1.6, "range": 0.5, "arm": 4, "parm": 4, "speed": 3.9, "sight": 11.0,
		"cost": {"g": 220, "a": 200}, "supply": 4, "time": 40.0, "tier": 3, "from": "sanctum", "dmg": "melee", "cls": ["champion"],
		"bonus": {"building": 18}, "radius": 1.0, "splash": 1.4, "desc": "A towering elite. Cleaves groups and buildings; spears are its bane."},
}
const MELEE_ROLES := ["worker", "infantry", "spear", "cavalry", "champion"]
const RANGED_ROLES := ["archer", "flyer", "caster", "siege"]

# --- shared building template ----------------------------------------------------------
# size (cells), hp, cost, time, tier, trains, supply (adds), drop (gold/aether drop-off),
# atk/range/cd for buildings that shoot
const BUILD_ORDER := ["hall", "house", "depot", "barracks", "forge", "tower", "stable", "workshop", "sanctum"]
const BUILDINGS := {
	"hall": {"role": "Town hall", "size": 4, "hp": 2400, "arm": 3, "parm": 8, "cost": {"g": 350, "a": 100}, "time": 80.0, "tier": 1,
		"trains": ["worker"], "supply": 10, "drop": true, "atk": 5, "range": 8.0, "cd": 2.0, "sight": 14.0,
		"desc": "Trains workers, takes in resources and advances your age."},
	"house": {"role": "House", "size": 2, "hp": 500, "arm": 1, "parm": 6, "cost": {"g": 60}, "time": 18.0, "tier": 1, "supply": 8, "sight": 6.0,
		"desc": "Supports 8 more supply."},
	"depot": {"role": "Depot", "size": 2, "hp": 600, "arm": 1, "parm": 6, "cost": {"g": 40, "a": 60}, "time": 22.0, "tier": 1, "drop": true, "sight": 7.0,
		"desc": "Workers drop gold and aether here. Build it next to far deposits."},
	"barracks": {"role": "Barracks", "size": 3, "hp": 1200, "arm": 2, "parm": 7, "cost": {"g": 150}, "time": 40.0, "tier": 1,
		"trains": ["infantry", "spear", "archer"], "sight": 8.0, "desc": "Trains infantry, spearmen and archers."},
	"forge": {"role": "Forge", "size": 3, "hp": 1000, "arm": 2, "parm": 7, "cost": {"g": 120, "a": 40}, "time": 35.0, "tier": 1, "sight": 8.0,
		"desc": "Researches attack and armour upgrades."},
	"tower": {"role": "Tower", "size": 2, "hp": 900, "arm": 3, "parm": 9, "cost": {"g": 100, "a": 60}, "time": 35.0, "tier": 1,
		"atk": 8, "range": 9.0, "cd": 1.6, "sight": 12.0, "air": true, "desc": "Shoots at anything in range, flyers included."},
	"stable": {"role": "Stable", "size": 3, "hp": 1200, "arm": 2, "parm": 7, "cost": {"g": 160, "a": 50}, "time": 40.0, "tier": 2,
		"trains": ["cavalry"], "sight": 8.0, "desc": "Trains cavalry."},
	"workshop": {"role": "Workshop", "size": 3, "hp": 1200, "arm": 2, "parm": 7, "cost": {"g": 180, "a": 80}, "time": 45.0, "tier": 2,
		"trains": ["siege"], "sight": 8.0, "desc": "Builds siege engines."},
	"sanctum": {"role": "Sanctum", "size": 3, "hp": 1300, "arm": 2, "parm": 7, "cost": {"g": 160, "a": 140}, "time": 45.0, "tier": 2,
		"trains": ["flyer", "caster", "champion"], "sight": 9.0, "desc": "Trains flyers, casters and, in the third age, champions."},
}
## Workers can put these up, in this order on the build menu.
const BUILD_MENU := ["house", "depot", "barracks", "forge", "tower", "stable", "workshop", "sanctum", "hall"]

# --- shared technology template --------------------------------------------------------
# at (building), tier (age needed), cost, time, fx (effects, applied by Sim._stats):
#   {"roles": [...], "stat": "atk"/"hp%"/"arm"/"parm"/"range"/"speed%"/"gather_g%"/"gather_a%"/"carry"/"bhp%"/"train%"}
const TECH_ORDER := ["tier2", "tier3", "gold1", "gold2", "aether1", "aether2", "carry", "worker_armor",
	"melee1", "melee2", "melee3", "ranged1", "ranged2", "ranged3", "armor1", "armor2", "armor3",
	"elite_infantry", "elite_spear", "elite_archer", "elite_cavalry", "elite_siege", "elite_flyer", "elite_caster",
	"tower_range", "tower_fortify", "unique"]
## Template names of the technologies (each race calls them something of its own).
const TECH_TEMPLATE := {"tier2": "Second age", "tier3": "Third age", "gold1": "Gold mining 1", "gold2": "Gold mining 2",
	"aether1": "Aether harvest 1", "aether2": "Aether harvest 2", "carry": "Bigger loads", "worker_armor": "Worker armour",
	"melee1": "Melee attack 1", "melee2": "Melee attack 2", "melee3": "Melee attack 3", "ranged1": "Ranged attack 1",
	"ranged2": "Ranged attack 2", "ranged3": "Ranged attack 3", "armor1": "Armour 1", "armor2": "Armour 2", "armor3": "Armour 3",
	"elite_infantry": "Elite infantry", "elite_spear": "Elite spears", "elite_archer": "Elite archers", "elite_cavalry": "Elite cavalry",
	"elite_siege": "Elite siege", "elite_flyer": "Elite flyers", "elite_caster": "Elite casters", "tower_range": "Tower range",
	"tower_fortify": "Fortified towers", "unique": "Unique technology"}
const ELITE_FX := [{"stat": "hp%", "add": 30}, {"stat": "atk", "add": 2}, {"stat": "arm", "add": 1}, {"stat": "parm", "add": 1}]
const TECHS := {
	"tier2": {"at": "hall", "tier": 1, "cost": {"g": 400, "a": 250}, "time": 45.0, "age": 2, "desc": "Advance to the second age: cavalry, siege, flyers, casters and stronger upgrades."},
	"tier3": {"at": "hall", "tier": 2, "cost": {"g": 700, "a": 500}, "time": 60.0, "age": 3, "desc": "Advance to the third age: champions, elite troops and the best upgrades."},
	"gold1": {"at": "hall", "tier": 1, "cost": {"g": 80, "a": 60}, "time": 25.0, "fx": [{"roles": ["worker"], "stat": "gather_g%", "add": 20}], "desc": "Workers mine gold 20% faster."},
	"gold2": {"at": "hall", "tier": 2, "cost": {"g": 180, "a": 140}, "time": 35.0, "fx": [{"roles": ["worker"], "stat": "gather_g%", "add": 20}], "desc": "Workers mine gold another 20% faster."},
	"aether1": {"at": "hall", "tier": 1, "cost": {"g": 100, "a": 40}, "time": 25.0, "fx": [{"roles": ["worker"], "stat": "gather_a%", "add": 20}], "desc": "Workers draw aether 20% faster."},
	"aether2": {"at": "hall", "tier": 2, "cost": {"g": 200, "a": 120}, "time": 35.0, "fx": [{"roles": ["worker"], "stat": "gather_a%", "add": 20}], "desc": "Workers draw aether another 20% faster."},
	"carry": {"at": "hall", "tier": 2, "cost": {"g": 150, "a": 100}, "time": 30.0, "fx": [{"roles": ["worker"], "stat": "carry", "add": 5}], "desc": "Workers carry 5 more per trip."},
	"worker_armor": {"at": "hall", "tier": 1, "cost": {"g": 60, "a": 60}, "time": 25.0, "fx": [{"roles": ["worker"], "stat": "hp%", "add": 50}, {"roles": ["worker"], "stat": "arm", "add": 1}, {"roles": ["worker"], "stat": "parm", "add": 2}], "desc": "Workers get 50% more life and armour."},
	"melee1": {"at": "forge", "tier": 1, "cost": {"g": 100, "a": 50}, "time": 30.0, "fx": [{"roles": ["infantry", "spear", "cavalry", "champion"], "stat": "atk", "add": 1}], "desc": "Melee troops +1 attack."},
	"melee2": {"at": "forge", "tier": 2, "cost": {"g": 200, "a": 120}, "time": 40.0, "need": "melee1", "fx": [{"roles": ["infantry", "spear", "cavalry", "champion"], "stat": "atk", "add": 1}], "desc": "Melee troops +1 attack."},
	"melee3": {"at": "forge", "tier": 3, "cost": {"g": 300, "a": 220}, "time": 50.0, "need": "melee2", "fx": [{"roles": ["infantry", "spear", "cavalry", "champion"], "stat": "atk", "add": 2}], "desc": "Melee troops +2 attack."},
	"ranged1": {"at": "forge", "tier": 1, "cost": {"g": 80, "a": 80}, "time": 30.0, "fx": [{"roles": ["archer", "flyer", "caster", "tower", "hall"], "stat": "atk", "add": 1}, {"roles": ["archer", "flyer", "tower"], "stat": "range", "add": 0.5}], "desc": "Archers, flyers, casters and towers +1 attack and a little more range."},
	"ranged2": {"at": "forge", "tier": 2, "cost": {"g": 160, "a": 160}, "time": 40.0, "need": "ranged1", "fx": [{"roles": ["archer", "flyer", "caster", "tower", "hall"], "stat": "atk", "add": 1}, {"roles": ["archer", "flyer", "tower"], "stat": "range", "add": 0.5}], "desc": "Ranged attackers +1 attack and more range."},
	"ranged3": {"at": "forge", "tier": 3, "cost": {"g": 250, "a": 250}, "time": 50.0, "need": "ranged2", "fx": [{"roles": ["archer", "flyer", "caster", "tower", "hall"], "stat": "atk", "add": 2}], "desc": "Ranged attackers +2 attack."},
	"armor1": {"at": "forge", "tier": 1, "cost": {"g": 120, "a": 40}, "time": 30.0, "fx": [{"roles": ["infantry", "spear", "archer", "cavalry", "flyer", "caster", "champion", "siege"], "stat": "arm", "add": 1}, {"roles": ["infantry", "spear", "archer", "cavalry", "flyer", "caster", "champion", "siege"], "stat": "parm", "add": 1}], "desc": "All troops +1 armour."},
	"armor2": {"at": "forge", "tier": 2, "cost": {"g": 220, "a": 100}, "time": 40.0, "need": "armor1", "fx": [{"roles": ["infantry", "spear", "archer", "cavalry", "flyer", "caster", "champion", "siege"], "stat": "arm", "add": 1}, {"roles": ["infantry", "spear", "archer", "cavalry", "flyer", "caster", "champion", "siege"], "stat": "parm", "add": 1}], "desc": "All troops +1 armour."},
	"armor3": {"at": "forge", "tier": 3, "cost": {"g": 320, "a": 200}, "time": 50.0, "need": "armor2", "fx": [{"roles": ["infantry", "spear", "archer", "cavalry", "flyer", "caster", "champion", "siege"], "stat": "arm", "add": 2}, {"roles": ["infantry", "spear", "archer", "cavalry", "flyer", "caster", "champion", "siege"], "stat": "parm", "add": 2}], "desc": "All troops +2 armour."},
	"elite_infantry": {"at": "barracks", "tier": 2, "cost": {"g": 150, "a": 100}, "time": 40.0, "elite": "infantry", "desc": "Infantry become elite: +30% life, +2 attack, +1 armour."},
	"elite_spear": {"at": "barracks", "tier": 2, "cost": {"g": 120, "a": 100}, "time": 40.0, "elite": "spear", "desc": "Spearmen become elite: +30% life, +2 attack, +1 armour."},
	"elite_archer": {"at": "barracks", "tier": 2, "cost": {"g": 140, "a": 140}, "time": 40.0, "elite": "archer", "desc": "Archers become elite: +30% life, +2 attack, +1 armour."},
	"elite_cavalry": {"at": "stable", "tier": 3, "cost": {"g": 250, "a": 180}, "time": 50.0, "elite": "cavalry", "desc": "Cavalry become elite: +30% life, +2 attack, +1 armour."},
	"elite_siege": {"at": "workshop", "tier": 3, "cost": {"g": 250, "a": 250}, "time": 50.0, "elite": "siege", "desc": "Siege engines become elite: +30% life, +2 attack, +1 armour."},
	"elite_flyer": {"at": "sanctum", "tier": 3, "cost": {"g": 250, "a": 250}, "time": 50.0, "elite": "flyer", "desc": "Flyers become elite: +30% life, +2 attack, +1 armour."},
	"elite_caster": {"at": "sanctum", "tier": 3, "cost": {"g": 200, "a": 300}, "time": 50.0, "elite": "caster", "fx": [{"roles": ["caster"], "stat": "heal", "add": 3}], "desc": "Casters become elite: +30% life, +2 attack, stronger healing."},
	"tower_range": {"at": "forge", "tier": 2, "cost": {"g": 120, "a": 80}, "time": 30.0, "fx": [{"roles": ["tower", "hall"], "stat": "range", "add": 2.0}], "desc": "Towers and town halls shoot 2 m further."},
	"tower_fortify": {"at": "forge", "tier": 3, "cost": {"g": 200, "a": 150}, "time": 40.0, "fx": [{"roles": ["tower"], "stat": "atk", "add": 5}, {"roles": ["tower"], "stat": "bhp%", "add": 50}], "desc": "Towers +5 attack and +50% life."},
	"unique": {"at": "hall", "tier": 3, "cost": {"g": 500, "a": 400}, "time": 60.0, "desc": "The race's own technology."},
}

# --- races -------------------------------------------------------------------------------
# missing: template entries the race does not get. mods: changes to the template per role.
# unique_fx: what the "unique" technology does. bonus: passive bonus (applied by Sim).
const RACE_ORDER := ["phyrexia", "dominaria", "ravnica", "avishkar"]
const RACES := {
	"phyrexia": {
		"name": "Phyrexia", "motto": "All will be one.",
		"blurb": "Porcelain and sinew. Compleated warriors that knit their wounds closed.",
		"bonus_text": "All troops regenerate their wounds slowly.",
		"bonus": {"regen": 0.4},
		"colors": {"main": Color(0.92, 0.9, 0.86), "dark": Color(0.12, 0.1, 0.11), "trim": Color(0.6, 0.06, 0.08), "glow": Color(0.3, 0.95, 0.55), "metal": Color(0.55, 0.55, 0.58)},
		"missing": ["caster", "elite_caster", "armor3", "aether2"],
		"mods": {"infantry": {"hp": 5}, "cavalry": {"speed": 0.3}},
		"ages": ["First Sphere", "Second Sphere", "Third Sphere"],
		"unique_fx": [{"roles": ["infantry", "spear", "cavalry", "champion"], "stat": "atk", "add": 2}, {"roles": ["*"], "stat": "regen", "add": 0.8}],
		"units": {
			"worker": "Vat Drone", "infantry": "Compleated Legionary", "spear": "Impaler Husk", "archer": "Oil Spitter",
			"cavalry": "Ravager Hound", "siege": "Gorger Engine", "flyer": "Porcelain Drake", "champion": "Praetor's Chosen"},
		"buildings": {
			"hall": "Furnace Core", "house": "Incubation Vat", "depot": "Ichor Sump", "barracks": "Compleation Pit", "forge": "Flesh Forge",
			"tower": "Spine Tower", "stable": "Hound Kennels", "workshop": "Engine Foundry", "sanctum": "Oil Cathedral"},
		"techs": {
			"tier2": "Second Sphere", "tier3": "Third Sphere", "gold1": "Rending Claws", "gold2": "Ore Gullets", "aether1": "Aether Siphons",
			"carry": "Distended Sacs", "worker_armor": "Plated Drones", "melee1": "Serrated Blades", "melee2": "Bone Saws", "melee3": "Flensing Edges",
			"ranged1": "Caustic Glands", "ranged2": "Pressurized Oil", "ranged3": "Acid Spines", "armor1": "Porcelain Plating", "armor2": "Carapace Grafts",
			"elite_infantry": "Full Compleation", "elite_spear": "Barbed Impalers", "elite_archer": "Bloated Spitters", "elite_cavalry": "Alpha Hounds",
			"elite_siege": "Gorger Overdrive", "elite_flyer": "Wyrm Grafts", "tower_range": "Spinal Reach", "tower_fortify": "Calcified Spines",
			"unique": "Glistening Oil"},
		"unique_text": "Melee troops +2 attack, and every unit regenerates three times as fast.",
	},
	"dominaria": {
		"name": "Dominaria", "motto": "For Benalia and the Coalition.",
		"blurb": "Knights, pikes and longbows behind stout stone walls.",
		"bonus_text": "Infantry, spearmen and champions have 15% more life. Towers shoot 1 m further.",
		"bonus": {"hp%": {"infantry": 15, "spear": 15, "champion": 15}, "range": {"tower": 1.0}},
		"colors": {"main": Color(0.86, 0.84, 0.78), "dark": Color(0.25, 0.22, 0.2), "trim": Color(0.2, 0.32, 0.7), "glow": Color(1.0, 0.85, 0.45), "metal": Color(0.72, 0.72, 0.75)},
		"missing": ["siege", "elite_siege", "elite_flyer", "ranged3"],
		"mods": {"archer": {"range": 0.5}},
		"ages": ["Hamlet Age", "Town Age", "Kingdom Age"],
		"unique_fx": [{"roles": ["*b"], "stat": "bhp%", "add": 50}, {"roles": ["tower", "hall"], "stat": "atk", "add": 3}],
		"units": {
			"worker": "Peasant", "infantry": "Benalish Footman", "spear": "Pikeman", "archer": "Longbowman",
			"cavalry": "Benalish Knight", "flyer": "Pegasus Rider", "caster": "Tolarian Mage", "champion": "Angel of the Host"},
		"buildings": {
			"hall": "Keep", "house": "Cottage", "depot": "Storehouse", "barracks": "Barracks", "forge": "Smithy",
			"tower": "Watchtower", "stable": "Stables", "sanctum": "Tolarian Academy"},
		"techs": {
			"tier2": "Town Age", "tier3": "Kingdom Age", "gold1": "Pickaxes", "gold2": "Deep Shafts", "aether1": "Mana Lenses", "aether2": "Leyline Maps",
			"carry": "Handcarts", "worker_armor": "Militia Drills", "melee1": "Tempered Steel", "melee2": "Folded Blades", "melee3": "Thran Alloy",
			"ranged1": "Fletching", "ranged2": "Bodkin Points", "armor1": "Mail Coats", "armor2": "Plate Armour", "armor3": "Thran Plate",
			"elite_infantry": "Benalish Veterans", "elite_spear": "Halberds", "elite_archer": "Yew Longbows", "elite_cavalry": "Order of the Sun",
			"elite_caster": "Archmages", "tower_range": "Arrow Slits", "tower_fortify": "Stone Battlements", "unique": "Thran Masonry"},
		"unique_text": "Every building gets 50% more life; towers and keeps +3 attack.",
	},
	"ravnica": {
		"name": "Ravnica", "motto": "The city never sleeps.",
		"blurb": "A city-plane of guilds: crossbows, sky knights, spark cannons and mages.",
		"bonus_text": "Technologies cost 20% less.",
		"bonus": {"tech_cost%": -20},
		"colors": {"main": Color(0.72, 0.68, 0.62), "dark": Color(0.18, 0.14, 0.2), "trim": Color(0.45, 0.2, 0.6), "glow": Color(0.55, 0.75, 1.0), "metal": Color(0.75, 0.55, 0.3)},
		"missing": ["cavalry", "elite_cavalry", "melee3", "tower_fortify"],
		"mods": {"flyer": {"hp": 15}, "caster": {"heal": 1.0}},
		"ages": ["Founding Charter", "Guild Charter", "Grand Charter"],
		"unique_fx": [{"roles": ["*"], "stat": "train%", "add": 35}],
		"units": {
			"worker": "Guild Laborer", "infantry": "Legion Trooper", "spear": "Precinct Halberdier", "archer": "Rooftop Crossbowman",
			"siege": "Spark Cannon", "flyer": "Skyknight", "caster": "Guild Mage", "champion": "Guardian Golem"},
		"buildings": {
			"hall": "Guildhall", "house": "Tenement", "depot": "Counting House", "barracks": "Legion Precinct", "forge": "Armory",
			"tower": "Bell Tower", "workshop": "Spark Foundry", "sanctum": "Guild Spire"},
		"techs": {
			"tier2": "Guild Charter", "tier3": "Grand Charter", "gold1": "Union Picks", "gold2": "Tunnel Contracts", "aether1": "Mana Conduits",
			"aether2": "Ley Taxation", "carry": "Courier Carts", "worker_armor": "Union Badges", "melee1": "Forged Halberds", "melee2": "Precinct Steel",
			"ranged1": "Repeating Crossbows", "ranged2": "Spark Bolts", "ranged3": "Storm Quarrels", "armor1": "Leather Coats", "armor2": "Lamellar Plate",
			"armor3": "Guild Wards", "elite_infantry": "Legion Veterans", "elite_spear": "Precinct Wardens", "elite_archer": "Rooftop Marksmen",
			"elite_siege": "Overcharged Coils", "elite_flyer": "Sky Marshals", "elite_caster": "Guild Masters", "tower_range": "Belfry Lookouts",
			"unique": "Guild Accord"},
		"unique_text": "Every building trains units 35% faster.",
	},
	"avishkar": {
		"name": "Avishkar", "motto": "Invent, race, win.",
		"blurb": "Brass, filigree and aether: racing cycles, thopters and cannons.",
		"bonus_text": "Workers draw aether 20% faster and cost 40 gold.",
		"bonus": {"gather_a%": 20, "worker_cost": 40},
		"colors": {"main": Color(0.82, 0.62, 0.3), "dark": Color(0.2, 0.16, 0.12), "trim": Color(0.1, 0.62, 0.66), "glow": Color(0.35, 0.95, 1.0), "metal": Color(0.85, 0.66, 0.35)},
		"missing": ["infantry", "elite_infantry", "elite_spear", "worker_armor"],
		"mods": {"cavalry": {"speed": 0.6, "hp": -10}, "siege": {"range": 1.0}},
		"ages": ["Spark Era", "Invention Era", "Grand Prix Era"],
		"unique_fx": [{"roles": ["cavalry", "flyer"], "stat": "speed%", "add": 25}, {"roles": ["cavalry", "flyer"], "stat": "atk", "add": 2}],
		"units": {
			"worker": "Servo", "spear": "Brass Lancer", "archer": "Aether Rifleman", "cavalry": "Aethercycle Rider",
			"siege": "Aether Cannon", "flyer": "Thopter", "caster": "Inventor", "champion": "Gearsmith Colossus"},
		"buildings": {
			"hall": "Consulate", "house": "Dwelling", "depot": "Aether Depot", "barracks": "Guard Post", "forge": "Gearworks",
			"tower": "Aether Spire", "stable": "Racing Garage", "workshop": "Cannon Works", "sanctum": "Inventors' Fair"},
		"techs": {
			"tier2": "Invention Era", "tier3": "Grand Prix Era", "gold1": "Brass Drills", "gold2": "Ore Refinery", "aether1": "Aether Condensers",
			"aether2": "Pressure Tanks", "carry": "Cargo Servos", "melee1": "Filigree Blades", "melee2": "Tempered Brass", "melee3": "Arc Edges",
			"ranged1": "Rifled Barrels", "ranged2": "Aether Rounds", "ranged3": "Coil Rifles", "armor1": "Brass Plating", "armor2": "Filigree Shields",
			"armor3": "Aether Barrier", "elite_archer": "Sharpshooters", "elite_cavalry": "Racing Champions", "elite_siege": "Twin Barrels",
			"elite_flyer": "Ornithopter Wings", "elite_caster": "Master Inventors", "tower_range": "Focus Lenses", "tower_fortify": "Aether Shielding",
			"unique": "Aether Overdrive"},
		"unique_text": "Cavalry and flyers move 25% faster and get +2 attack.",
	},
}

# --- resources -------------------------------------------------------------------------
const RESOURCES := {
	"gold": {"name": "Gold vein", "amount": 1400, "rate": 1.25},    # per second of gathering
	"aether": {"name": "Aether crystal", "amount": 800, "rate": 1.0},
}
const CARRY := 10

# --- maps --------------------------------------------------------------------------------
# Each template is laid out by MapGen from a seed, so the same template plays a little
# differently every match. biome picks the ground colours, props and sky.
const MAPS := [
	{"id": "meadows", "name": "Benalish Meadows", "plane": "Dominaria", "shape": "open",
		"desc": "Open farmland with copses and ponds. Room to manoeuvre and many ways in.",
		"ground": Color(0.36, 0.5, 0.22), "ground2": Color(0.5, 0.56, 0.26), "dirt": Color(0.48, 0.38, 0.24), "rock": Color(0.5, 0.48, 0.44),
		"water": Color(0.18, 0.38, 0.5), "sky_top": Color(0.32, 0.5, 0.82), "sky_horizon": Color(0.8, 0.85, 0.9), "sun": Color(1.0, 0.95, 0.85), "fog": Color(0.75, 0.82, 0.9),
		"tree": "oak"},
	{"id": "canals", "name": "Ravnican Canals", "plane": "Ravnica", "shape": "river",
		"desc": "Four districts split by canals. Bridges are the only ways across, so hold them.",
		"ground": Color(0.42, 0.4, 0.38), "ground2": Color(0.5, 0.47, 0.42), "dirt": Color(0.36, 0.32, 0.3), "rock": Color(0.35, 0.32, 0.36),
		"water": Color(0.14, 0.26, 0.32), "sky_top": Color(0.25, 0.24, 0.36), "sky_horizon": Color(0.7, 0.62, 0.6), "sun": Color(1.0, 0.86, 0.7), "fog": Color(0.55, 0.5, 0.55),
		"tree": "ruin"},
	{"id": "canyon", "name": "Ghirapur Canyon", "plane": "Avishkar", "shape": "canyon",
		"desc": "Each base sits on its own plateau with two ramps down to a wide canyon floor.",
		"ground": Color(0.66, 0.46, 0.28), "ground2": Color(0.74, 0.56, 0.34), "dirt": Color(0.56, 0.38, 0.24), "rock": Color(0.6, 0.38, 0.26),
		"water": Color(0.2, 0.55, 0.6), "sky_top": Color(0.2, 0.45, 0.75), "sky_horizon": Color(0.95, 0.8, 0.6), "sun": Color(1.0, 0.9, 0.75), "fog": Color(0.9, 0.78, 0.62),
		"tree": "pipe"},
	{"id": "mirrex", "name": "Mirrex Expanse", "plane": "New Phyrexia", "shape": "ring",
		"desc": "Metal thickets wall in every base. The rich centre is worth fighting over.",
		"ground": Color(0.26, 0.25, 0.27), "ground2": Color(0.34, 0.3, 0.3), "dirt": Color(0.3, 0.2, 0.2), "rock": Color(0.4, 0.4, 0.44),
		"water": Color(0.06, 0.06, 0.06), "sky_top": Color(0.12, 0.08, 0.1), "sky_horizon": Color(0.6, 0.3, 0.25), "sun": Color(1.0, 0.8, 0.75), "fog": Color(0.4, 0.25, 0.25),
		"tree": "spire"},
]

const AI_LEVELS := ["Easy", "Normal", "Hard"]


# --- lookups ----------------------------------------------------------------------------

static func has_unit(race: String, role: String) -> bool:
	return role not in RACES[race].missing


static func has_tech(race: String, tech: String) -> bool:
	if tech in RACES[race].missing:
		return false
	var t: Dictionary = TECHS[tech]
	if t.has("elite") and not has_unit(race, t.elite):
		return false
	return has_building(race, t.at)


## A building exists for a race when it trains something or researches something for it.
static func has_building(race: String, role: String) -> bool:
	if role in ["hall", "house", "depot", "tower", "forge"]:
		return true
	for u in BUILDINGS[role].get("trains", []):
		if has_unit(race, u):
			return true
	return false


static func unit_name(race: String, role: String) -> String:
	return RACES[race].units.get(role, UNITS[role].role)


static func building_name(race: String, role: String) -> String:
	return RACES[race].buildings.get(role, BUILDINGS[role].role)


static func tech_name(race: String, tech: String) -> String:
	return RACES[race].techs.get(tech, tech.capitalize())


static func age_name(race: String, tier: int) -> String:
	return RACES[race].ages[clampi(tier - 1, 0, 2)]


static func cost_text(c: Dictionary) -> String:
	var parts := []
	if c.get("g", 0) > 0:
		parts.append("%d gold" % c.g)
	if c.get("a", 0) > 0:
		parts.append("%d aether" % c.a)
	return ", ".join(parts) if parts else "free"
