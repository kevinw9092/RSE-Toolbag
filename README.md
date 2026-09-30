# RSE-Toolbag

*Part of **RSE** (RuneScape Enhanced), a family of UE4SS mods for RuneScape: Dragonwilds.*

A 10-slot toolbag for your tools. Keep your pickaxe, axe, spade, watering can, compost bucket, fishing rod and net out of your bag and hotbar, and take them out with one key.

## Features
- **Toolbag window.** Click the Toolbag icon in the inventory's armour panel (RSE-Dock). It opens beside the inventory in the game's frame art:
  - the 10 toolbag slots
  - the tools in your bag and hotbar: click one to store it
  - click a toolbag slot to take its tool out
  - **Store all tools** and **Take all out** buttons
- **Shift+1 to Shift+0** equips toolbag slot 1 to 10. Set `SlotKeys` to change the modifier.
- **Tool key (X).** Face a rock, tree, farm plot or fishing spot and press X. The best tool for the job comes out, from the toolbag first, then your bag.
- **Equip prompt.** While you face something a tool you carry can work on, a small "[X] Equip Rune pickaxe" hint appears.
- **Auto tool.** Hit a rock, tree or farm plot with the wrong item and the right tool comes out. This is from Expanded Inventory.

## Requirements
- UE4SS for RuneScape: Dragonwilds (a recent experimental build)
- **RSE-Dock** for the window. Without it, the keys and the prompt still work.
- Optional: **RSE-ModMenu** to change settings in game (Esc > MODS)

## How the toolbag is stored
The toolbag is a **hidden fifth inventory tab** of 10 slots, added after the bag, runes, ammo and quest tabs. The inventory screen has no button for it and never draws it. Only the Toolbag window shows those slots. Because it comes after the other tabs, no existing slot number changes, so **no items move** on an existing character.

`ToolbagMode` picks the tab's type:
- `off` (default): no toolbag slots. The tool key, prompt and auto tool still work from your bag.
- `private`: a type of its own that the game never uses. Pickups never go there. **Experimental:** the game might refuse items in it, or drop them when loading.
- `items`: the bag's own type. It accepts every tool, but new pickups may land in it once your main bag is full.

Rules:
- **Before switching back to `off`, or removing the mod**, click **Take all out**. Without the fifth tab, anything in it can be lost.
- **Co-op:** the host decides the inventory layout. The host and every guest need the mod with the same `ToolbagMode`.
- The mod only adds the tab when the four vanilla tabs have vanilla sizes. If another inventory-size mod changed them, the toolbag stays off and the log says why.
- Version 2.0.0 grew the quest tab instead. That crashed the game, because the quest tab's screen holds exactly 72 slots. 2.1.0 never changes an existing tab.

## Settings (`config.txt`, or Esc > MODS)
| Setting | Default | Meaning |
|---|---|---|
| `ToolbagMode` | `off` | toolbag storage: `off`, `private` or `items` (see above). Restart after a change |
| `SlotKeys` | `SHIFT` | modifier for 1-0: `SHIFT`, `CTRL`, `ALT` or `NONE`. Restart after a change |
| `ToolKey` | `X` | tool key, `none` turns it off. Restart after a change |
| `EquipPrompt` | `true` | show the equip hint |
| `ToolReach` | `3.0` | how close a rock or tree must be, in meters (1.5 to 6) |
| `UseCompost` | `true` | compost bucket for watered farm plots |
| `AutoTool` | `true` | the right tool comes out when you hit with the wrong one |
| `AutoToolFromWeapon` | `true` | auto tool also from melee weapons, only right in front of you |
| `BagFirst` | `false` | pickups go to the bag instead of empty hotbar slots |
| `Debug` | `false` | extra log lines |

## Trying the toolbag safely
Test on a **throwaway character**, and back up `%LOCALAPPDATA%\RSDragonwilds\Saved\SaveCharacters` first.

1. **Probe (main menu).** Start the game with `ToolbagMode = off`. On the main menu, open the UE4SS console and run `toolbag_probe`. Read the `probe:` lines in `UE4SS.log`:
   - `APPEND WORKS`: Lua can add the tab. **Quit the game** without loading a character.
   - `APPEND FAILED`: this build can't add a fifth tab. Send the log.
2. **Private type.** Set `ToolbagMode = private`, then start and load the throwaway character.
   1. Open the inventory, switch through all four tabs, and open the Toolbag window. A crash here means the game can't handle a fifth tab.
   2. Store a tool. If the window says "The game did not accept ...", the private type refuses items: go to step 3.
   3. Press Shift+1 to equip it, then put it away.
   4. Save, quit to the main menu, load again, and run `toolbag_status`. The tool must still be listed in the toolbag.
3. **Bag type.** If any part of step 2 fails, set `ToolbagMode = items` and repeat step 2. Also fill your main bag, pick something up, and see whether it lands in the toolbag.

Also check that Shift+1 doesn't fire the game's own hotbar key 1, and that X isn't already bound in the game.

## Credits
Based on **Expanded Inventory** by notto0606 (MIT). The auto tool, tool key and bag-first code come from it. The inventory-size feature was replaced by the toolbag. See `LICENSE`.
