# History

## Round 1: the first version
**Request (Petr):** "I want to create now game into my game part of eshop. It will be RTS,
inspired by "age of empires" and "Starcraft". The idea is that there will be like 4 races.
Phyrexians, Dominaria, Ravnica, Avishkar. Couple of basic map templates will be enough (4). Each
race will have its own units and technologies in terms of name and look (like Starcraft) but those
units/tech will be coming from shared template (like AoE). Out of shared template each race will
have only certain unit and technology upgrades available (Much like in AoE). This game will have
multiplier to allow play against either AI or human, or both"

**Decided (defaults, offered to Petr):** the name Planar Wars; a new repository like the other
games; host-run online rooms like Aether Drift, with up to four seats that can each be a person or
an AI player.

**Built:**
- One shared template: 9 troop roles (worker, infantry, spearman, archer, cavalry, siege engine,
  flyer, caster, champion), 9 buildings and 27 technologies (three ages, economy, attack and armour
  levels, elite upgrades, towers, one unique technology per race).
- Four races on that template, each with its own names, models, colours, a bonus, a unique
  technology and a few roles and upgrades it lacks (Phyrexia: no caster; Dominaria: no siege;
  Ravnica: no cavalry; Avishkar: no infantry; plus missing upgrades each).
- Four map templates laid out from a seed: Benalish Meadows (open), Ravnican Canals (river and
  bridges), Ghirapur Canyon (plateaus and ramps), Mirrex Expanse (walled bases, rich centre).
- Gold and aether economy, supply, construction and repair, training queues, rally points,
  research, armour types and counters, splash, healing, towers, fog of war, victory by teams.
- AI players at three levels that build, expand, research and attack in waves.
- Controls in the classic RTS style: box select, groups, command card hotkeys, attack-move,
  minimap, idle worker and alert keys, game speed.
- Title screen with a live AI battle, skirmish setup (map, seats, races, teams), multiplayer rooms
  (WebRTC in the browser), a Codex showing the template table and how to play.
- Tests: an AI-only sim test, a visual smoke test, a two-player online test (desktop and two
  browser tabs). All art and sound are generated in code.
