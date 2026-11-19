# Delirium Heating

Build 42 mod for the Delirium server. Requires **Delirium Economy** (and through it Delirium Shops).

District heating for a world without grid power: one boiler house heats a whole neighbourhood.

- **Water intake** (2x2 cells, next to a river or a lake): pumps water into the pipes. Every working intake whose water reaches a boiler house adds 200 l a game hour to its tank. Needs electricity.
- **Boiler house** (2x3 cells): burns fuel and heats the water. It does not burn without water in its tank (1000 l; a burning boiler loses 10 l an hour plus 0.5 per radiator). Anyone lights it or puts it out and loads fuel from its window: logs, firewood, planks, branches, charcoal, coke, a propane tank (drained, the empty tank stays) or petrol (poured out of its container). The water warms up by a degree a game minute and cools down slowly when the fire is out.
- **Pipes** lie on the ground and do not block the way. They join their neighbours by themselves. There are two kinds that never join each other: the **heating pipe** (bare steel) carries the hot water from a boiler house to the heat units, the **cold water pipe** (painted blue) carries the intake's water to the boiler houses and the water units.
- **Pipes in the air**, to cross a road: above the ground a pipe needs no floor. Lay it from the ground with the cursor lifted a level (**R**), or stand on an upper floor and drag the run out into the air. A pipe joins the pipe right above or below it, and the lower one shows a riser, so a run goes up, over and down again. A pipe one level up is taken apart from the ground below it.
- **Pump stations**: the water travels 60 cells of pipe from an intake and 40 from a boiler house; a pump station on the way sends it 80 cells further. A pump needs electricity (a generator in range); without it it is just a pipe. It is turned along the pipe it stands on, east-west or north-south.
- **Heat unit**: stands at a wall of a house (any of the four edges of its cell) on the end of a pipe. When hot water reaches it, every radiator within 10 cells of it works (three floors up and down; the radius is the sandbox option `InletRadius`) - no pipes inside the house.
- **Water unit**: the heat unit's twin for cold water. Stands at a wall of a house on a pipe the intake's water reaches. It keeps a tank (200 l) that the intake's water fills at the intake's rate, and every 10 game minutes tops up the sinks, toilets, baths and showers within 10 cells of it (three floors up and down) - nothing has to be plumbed. Clean water by default; sandbox `TapClean` off gives the river's water as it is, to be boiled. A fixture plumbed to a barrel upstairs is left to its barrel; while the mains water is still on, nothing needs it.
- **Radiators** stand in the rooms, at any of the four walls. A working one warms the air around it the way a vanilla fireplace does (an `IsoHeatSource`): walls and closed doors stop the heat. They start to warm at 30 degrees of water and give full heat at 80.
- **Where things join.** A pipe joins the pipes of its own kind around it on all four sides, up and down too. A **pump station** carries its own length of pipe and joins only at its two ends, either kind: it is put into a line, turned along it; a pump turned across a line cuts it, and a pump between a cold and a heating pipe passes no water from one to the other. A **boiler house** has two outlets on the corner cell by its tank: the blue one takes the cold water pipe, the other gives the hot water to the heating pipe (front to the south: cold from the south, hot to the east; front to the east: cold from the east, hot to the north). A **water intake** takes a cold water pipe at the blue pipe end coming out of the south face of its pad, on its south-east cell. A heat unit stands on a heating pipe, a water unit on a cold water pipe. A pipe lying against any other cell of them joins nothing, neither on the picture nor for the water.
- **Pipe support**: a steel lattice post one level high, to stand on the ground under a pipe laid a level up. Only for the look - a pipe hangs without it too - and it does not block the way.
- Fuel: an idle boiler burns 1 unit a game hour, plus 0.05 for every radiator it feeds; a log is 6 units, the furnace holds 500.

## Building

A part is put down with a **placement cursor**: right-click the part in the inventory - **Place**, or right-click the ground - **Heating** - the part (an admin finds every part there without carrying it).

- The part is drawn on the ground under the mouse, a boiler house and a water intake with their whole footprint. Red means it cannot go there; a click on a red one says why.
- **R** turns it, and so does holding the button and dragging: a radiator and a heat unit to any of the four walls of the cell, a pump along either pipe, a boiler house with its front to the south or to the east.
- Left click places, right click cancels. The cursor stays for pipes, supports and radiators.
- **Pipes**: a click lays one, holding the button and dragging lays a run from the pressed cell to the mouse (along x, then along y; up to 200 cells; cells already taken are passed over, the pipes are drawn joined the way they will lie). *Heating - Remove pipes* is the same cursor taking a run off. A pipe has nothing to turn, so **R** lifts its cursor a level instead: the cell under the mouse is marked, the pipe is drawn above it and goes there, laid from below; R again brings it back. A run that ends where nobody can stand (in the air, over water) is laid from its start.

Who builds:

- **Players** craft the parts (crafting tab *Heating*, welding) and need a **pipe wrench** on them. Placing takes the part and a little time; taking a thing apart gives the part back. Nothing can be built or taken apart in somebody else's safehouse. Sandbox `PlayersBuild` turns this off.
- **Radiators** are anybody's to put in and take out. **Everything else** - pipes, heat units, pump stations, water intakes, boiler houses - is built and taken apart only by the head and staff of an organization with the **Heat supply** activity. An admin ticks it in the organization window of Delirium Economy, the same way as *Road repair* of Delirium Roads. Other players see those parts greyed out in the menu with the reason. Lighting a boiler and loading fuel stay open to everyone.
- **Admins** build for free and at once, and can fill a boiler with fuel or water.

## Windows

Right-click a thing of the heating and pick its name: its window opens (the menu line itself shows the short state in a tooltip). The window is kept up to date by the server and closes when you walk away.

- **Boiler house**: the state of the furnace, bars for fuel, water and water temperature (with marks at 30 and 80 degrees), whether a water intake is connected, radiators fed, fuel and water used per hour and how long the fuel lasts. *Light the furnace / Put it out*. The fuel you carry is listed by kind with what it is worth and a **Load** button each, plus **Load everything**. Admins also get *fill with fuel* and *fill with water*.
- **Water intake**: working or without power, how many boiler houses its water reaches, its output and reach.
- **Pump station**: working or without power, how far it sends the water, whether the boiler's and the intake's water get to it.
- **Heat unit**: whether hot water reaches it and how hot it is, its radius, radiators in the radius.
- **Water unit**: whether the intake's water reaches it, a tank bar, clean or river water, its radius, the plumbing in the radius and how many of those take water.
- **Radiator**: a heat bar, the water temperature, the air temperature at it, how far the heat spreads.
- **Pipe**: whether the boiler's and the intake's water get here and how many cells further they would go.
- Every window has *Take apart* (greyed out with the reason for those who may not).

The objects cannot be picked up or broken with a sledgehammer.

| Recipe | Skill | Ingredients (plus a welding mask) |
|---|---|---|
| 3 heating pipes | Welding 2 | 1 sheet metal, 1 torch use |
| 3 cold water pipes | Welding 2 | 1 sheet metal, 1 torch use |
| Pipe support | Welding 2 | 4 metal bars, 1 torch use |
| Radiator | Welding 2 | 4 small sheet metal, 2 metal pipes, 2 torch uses |
| Heat unit | Welding 3 | 2 sheet metal, 4 metal pipes, 6 nuts and bolts, 3 torch uses |
| Water unit | Welding 3 | 2 sheet metal, 4 metal pipes, 6 nuts and bolts, a rubber hose, 3 torch uses |
| Pump station | Welding 4, Electrical 3 | 2 sheet metal, 2 metal pipes, 2 metal bars, engine parts, 4 electric wire, 10 scrap electronics, 10 screws, 4 torch uses |
| Water intake kit | Welding 5, Electrical 4 | 6 sheet metal, 6 metal pipes, 4 metal bars, 2 engine parts, 2 rubber hoses, 6 electric wire, 15 scrap electronics, 20 screws, 8 torch uses |
| Boiler house kit | Welding 7 | 20 sheet metal, 10 metal pipes, 10 metal bars, 60 clay bricks, 20 nuts and bolts, 10 torch uses |

## Sandbox options (page DelHeat)

| Option | Default | Meaning |
|---|---|---|
| `PlayersBuild` | true | players build with crafted parts (radiators anyone, the rest a heat supply organization); off - admins only |
| `FuelCapacity` | 500 | fuel units a boiler house holds; one unit is one game hour of an idle boiler |
| `BurnPerHour` | 1 | units a lit boiler burns each game hour |
| `BurnPerRadiator` | 0.05 | extra units per hour for every radiator fed |
| `HeatUpPerMinute` | 1 | water heats up, degrees per game minute |
| `CoolDownPerMinute` | 0.25 | water cools down, degrees per game minute |
| `WaterCapacity` | 1000 | litres in a boiler's tank |
| `WaterPerHour` | 10 | litres a burning boiler loses each game hour |
| `WaterPerRadiator` | 0.5 | extra litres per hour for every radiator fed |
| `IntakeRate` | 200 | litres a working intake adds to a boiler each game hour |
| `IntakeReach` | 60 | cells of pipe the water travels from an intake |
| `BoilerReach` | 40 | cells of pipe the hot water travels from a boiler house |
| `PumpReach` | 80 | cells a working pump sends it further |
| `PumpNeedsPower` | true | pumps and intakes work only on a powered square |
| `InletRadius` | 10 | cells around a heat unit in which radiators work |
| `TapClean` | true | water units give clean water; off - the river's water as it is |
| `TapRadius` | 10 | cells around a water unit in which the plumbing is topped up |
| `TapCapacity` | 200 | litres in a water unit's tank |
| `RadiatorTemp` | 35 | air temperature at a radiator at full heat (a fireplace is 35) |
| `RadiatorRadius` | 6 | cells at which the heat fades to nothing |
| `PetrolPerLitre` | 2 | units per litre of petrol, 0 to refuse petrol |
| `FuelTable` | `Base.Log:6; Base.Firewood:2; Base.Plank:2; ...; Base.PropaneTank:80` | item:units pairs |

Tiles: pack `delheat` (43 sprites), `tiledef=delheat 1919`. Art is modelled from primitives and rendered with the PZ camera: `art/render_heat.py` (Blender) -> `art/cut_heat.py` (frames, item icons, `art/tiles.json`) -> `tools/TilePack/build-tilepack.ps1`. Translations are written by `art/make_translations.py`.
