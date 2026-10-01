# Changelog

## 2.3.4
- **Breakable walls.** The tool key, the Switch Tool prompt and auto tool take out the pickaxe for the breakable walls (castle, DK, DR and vault walls, and the Fuzan wall), as they do for rocks.

## 2.3.3
- **Dead plants.** Facing a farm plot whose plant has died, the tool key, the Switch Tool prompt and auto tool take out the spade to dig it out. The plot's stage is read from the game (`PlotStage`); with Debug on, the log says so if it cannot be read.
- **Every diggable spot.** Buried treasure is now found through the game's own diggable class, which covers every kind of buried chest, buried journal pages and quest dig spots, not only the blueprints listed in 2.3.2.
- **Dug-up spots no longer ask for the spade.** A spot whose digging is complete stops counting.

## 2.3.2
- **Kebbit burrows and buried treasure.** The tool key, the Switch Tool prompt and auto tool now take out the spade for kebbit burrows and buried treasure: buried chests, buried journal pages and the buried coffin.
- **Toolbag keys default to Alt+1-0.** Ctrl is dodge and Shift is sprint. Existing configs keep their setting.
- **Fixed: changing `SlotKeys` in RSE-ModMenu did nothing until a restart.** The keys were bound once, for the modifier set at start. Now 1-0 is bound with Alt, Shift and Ctrl, and the setting picks which one works, so a change applies at once. The toolbag row's key cap, the window's hint and the dock tooltip follow it.

## 2.3.1
- **Toolbag row:** the tool in your hand now gets a thin bronze outline inside its slot, like the action bar's selected slot, instead of an orange frame.
- **Fewer hitches while moving.** The tool key, the equip prompt and auto tool keep a list of nearby rocks, trees, vines and fishing spots. It is now rebuilt when you have moved far enough that something within reach could be missing from it (about 24 m, 10 m for fishing), or after 45 s, and only one kind per tick. It was every 8 m or 20 s, all kinds at once.
- **Crash safety:** that list, the players' controllers on a server and the item types changed by bag first are kept as object paths and looked up when used. A rock that was destroyed or unloaded can no longer be touched after it is gone.
- The dock icon works out the tools you carry while the inventory is open, and otherwise at most every 5 s (it scanned the inventory every second).
- The Switch Tool prompt is rebuilt at most every 10 s if the game removes it, and looks for the game's key-hint widget every 60 s after 3 misses.
- Smaller savings: native classes are looked up once per world, property checks no longer build a name each time, the chest-label typing check runs only after a key press, and debug text is built only with Debug on. `hud-dump.txt` is written to a temporary file first.

## 2.3.0
- **Toolbag row.** The 10 toolbag slots are shown on the HUD, each with its tool's icon, its number and a durability bar like the action bar's (red when low). A faded SHIFT key cap (your `SlotKeys` modifier) sits at the left, so the keys that take each tool out are always in view. The tool in your hand gets an orange frame. The slots use the game's embroidered item slot frame. It is display only, and hidden while a menu is open or while toolbag storage is off.
  - `QuickRowPosition`: **Above health**, **Below health**, or **Above action bar**. Above the action bar, only slots 1-8 show, to line up with it. The in-world 1-8 bar is the inventory panel's own quick access bar, which stays on screen when the inventory closes, so the row is placed on that panel's canvas and follows it.
  - `QuickRowOffset` moves the row up (+) or down (-), -300 to 300.
  - `QuickRow` turns it off. All three apply at once from RSE-ModMenu.
- **Cuttable vines.** The tool key, the equip prompt and auto tool now also work on vines and choppable blockers: the thorny vines across entrances, the vines over wells and pools, and the Imaru dragon vines. Also anything else whose class has "Vine" or "Choppable" in its name, but never the Wild Jade Vine enemy or any other creature. They take out the axe; `VineTool` picks another tool if the game wants one.
- With Debug on, `hud-dump.txt` (in the mod folder) records where the game's health bars and action bar sit, for placing the row.
- Found while testing: the first build of the row rebuilt itself about 3 times a second. It stacked copies whose newest, still empty copy hid the icons, and it made the game hitch. The row now keeps its widget by path, removes every copy it made before a rebuild, and rebuilds only when its position setting changes, or at most every 10 seconds if its widget is really gone.

## 2.2.6
- **The equip prompt looks like the game's own prompts.** It now reads "Switch Tool [X]", drawn like "Harvest [E]" or the inventory's "Sort [V]": a plain label and a boxed key, with no frame. It reuses the game's input legend widget, whose class is taken from one the game already has. The widget's own key icon only draws keys the game has a binding for, so the mod hides it and draws its own key cap in its place. That cap is a 30 by 30 square with the letter centred, matched to the game's key caps. It uses the game's key-cap art when available, and a light outlined box otherwise. Longer key names such as F10 get a wider box.
- Until a legend widget exists (for example before the inventory is first opened), or if it cannot be used, the prompt falls back to the framed panel from 2.2.5 with the same "Switch Tool [X]" words.

## 2.2.5
- **Equip prompt text no longer cut off.** The smaller font in 2.2.4 did not help. The panel's content area sits inside the frame art's padding and is shorter than a line of text. The text now sits over the whole panel, centred. The old placement is the fallback.
- **No stray sparks around the prompt.** The game's panel plays ember and flourish effects meant for large windows. The prompt now hides them. With Debug on, the panel's widgets are logged once, so a missed effect can be named.

## 2.2.4
- **Fixed a crash risk from stale cached game objects after the game unloaded them.** The same bug crashed RSE-Transmog. The toolbag window kept item icons, fonts, the game button class and the inventory slots used for its slot art between uses. The tool list kept item data objects. The game can unload those, and the next use would then touch freed memory. The mod now keeps only names and paths, and looks each object up again when it needs it. The icon cache is also cleared on every map load.
- **Equip prompt text fits its frame.** The "[X] Equip ..." prompt used text too large for its panel, which cut off the bottom of the letters. The text is now smaller (14 instead of 18) and centred in the panel.

## 2.2.3
- The toolbag slots now look like the inventory's empty slots: a slightly darker square over the window's own grain, with no framed slot art. The game's empty slots draw no texture of their own; every slot brush is empty, as `transmog_slotart` showed.

## 2.2.2
- **Slots match the inventory's empty slots.** The toolbag and bag squares now copy what an empty inventory slot draws (plain dark with a faint grain) instead of the item slot frame. If no empty inventory slot is found (full bag), they fall back to the frame, then to flat dark.
- **Quieter log.** With `Debug = false` (the default), the log only shows the version line, errors and warnings. Setup details (toolbag tab, keys bound, move function, co-op handshake, bag first, slot art) and move status lines need `Debug = true`. Debug can be switched in game with RSE-ModMenu and applies at once.
- The cached inventory slot used for the slot art is dropped on every map load.

## 2.2.1
- **Game-style slots.** The toolbag and bag squares now use the inventory's own slot art, copied from a live inventory slot, instead of flat grey boxes with a light outline. Hover and the equipped slot still show the tan fill and gold outline, and the slot numbers stay in the corners. The game's hover sparkle is not reproduced. If the slot art cannot be found, the squares stay flat dark.
- **Same spacing as RSE-Transmog.** Both windows now share the same padding, row gaps, cell gaps and title/Close row.
