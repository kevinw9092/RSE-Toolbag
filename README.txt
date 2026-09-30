Expanded Inventory 1.3.0 - RuneScape: Dragonwilds
===================================================

1. Main bag up to 152 slots (vanilla 24). The runes and ammo tabs can also grow to 72
   (vanilla 24); the quest tab keeps its vanilla 72. The inventory screen gets extra rows
   and scrolls.
2. Bag first: picked-up items go into your bag instead of filling empty hotbar slots.
3. Auto tool: hit a rock, tree or farm plot with the wrong item and the right tool comes out of
   your bag (pickaxe, axe, spade, watering can or compost bucket). The first hit swaps, the next
   one works. From a melee weapon only for a rock or tree right in front of you, never from a
   bow, crossbow, staff, wand, seeds or potions.
4. Tool key (U): face a rock, tree, farm plot or fishing spot and press U. The best pickaxe,
   axe, spade, watering can, compost bucket, fishing rod or net comes out of your bag, from any
   slot. It only puts the tool in your hand; the gathering is still yours.

REQUIREMENTS
- UE4SS for RuneScape: Dragonwilds (tested with UE4SS 3.0.1)
- Optional: Mod Menu, to change the settings in game (Esc > MODS)

INSTALL
1. Install UE4SS first.
2. Existing character: in game, move everything from the Runes, Ammo and Quest tabs into a
   chest, then quit the game.
3. Extract the "ExpandedInventory" folder into:
   ...\RSDragonwilds\Binaries\Win64\ue4ss\Mods\
4. Start the game and take your runes, ammo and quest items back from the chest.

READ THIS BEFORE USING IT
- New and existing characters both work. The inventory is saved slot by slot, and a bigger bag
  moves where the Runes, Ammo and Quest tabs start. That is why those three tabs must be empty
  (items in a chest) the first time you start with a bigger size, and again before every later
  increase. Items in the main bag stay where they are.
- Back up your saves first:
  %LOCALAPPDATA%\RSDragonwilds\Saved\SaveCharacters
- Never lower a size on a character you play: items in the removed slots are lost.
- Do not remove the mod from a character you played with it. Without the mod the game reads
  the vanilla layout again: items move to the wrong tabs and items in the extra slots can be lost.
- Multiplayer: the host and every guest need the mod with the same sizes. Bag first follows the
  host's setting.
- Updating from 1.x: 1.x used one size for every tab (InventorySlots). Keep your config.txt with
  its "InventorySlots = N" line and do not add BagSlots/TabSlots: nothing changes. To switch to
  the new sizes, empty the Runes, Ammo and Quest tabs into a chest, set BagSlots and TabSlots
  (TabSlots not lower than your old N), then start the game.
- Bag first, auto tool and the tool key do not touch your save and can be turned off at any time.

SETTINGS (config.txt, or Esc > MODS with Mod Menu)
- BagSlots = 152         main bag, 24 to 152 in steps of 8 (restart the game after a change)
- TabSlots = 24          runes and ammo tabs, 24 to 72 in steps of 8 (restart)
- HideScrollBar = true   hides the inventory scroll bar that can stay on screen (restart)
- BagFirst = true        pickups go to the bag first (applies straight away)
- AutoTool = true        the right tool comes out when you hit a rock, tree or farm plot
- AutoToolFromWeapon = true  also swap away from melee weapons (rock or tree right in front)
- ToolKey = U            the tool key, "none" turns it off (restart after a change)
- ToolReach = 3.0        how close a rock or tree must be, in meters, 1.5 to 6
- UseCompost = true      compost bucket for watered farm plots

KNOWN ISSUES
- While scrolling, item icons can briefly stay drawn at their old position. Only visual.
- Not compatible with mods that replace the player inventory or player controller blueprints
  (BP_Components_Inventory, BP_PlayerController), or with other inventory size mods.
- Do not use it together with other mods that do the same thing (a second tool key on the
  same key would take the tool out and put it away again).

Tested on game version 1.0.0.2 (build CL-240163) with UE4SS 3.0.1.
