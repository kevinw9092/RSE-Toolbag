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
The toolbag is 10 extra slots added to the end of your character's last inventory tab. Adding them at the end keeps every existing slot where it was, so **no items move on an existing character** and no emptying is needed before the first start. The slots are saved with your character like any other slot.

- **Before removing the mod**, click **Take all out**. Without the mod, the game no longer sees those 10 slots, and tools left in them can be lost.
- **Co-op:** the host decides the inventory layout. The host and every guest need the mod.
- The mod only adds the slots when the last tab has a vanilla size (24 or 72, or that plus 10). If another inventory-size mod changed it, the toolbag stays off and the log says why. Don't use RSE-Toolbag with Expanded Inventory or other inventory-size mods.

## Settings (`config.txt`, or Esc > MODS)
| Setting | Default | Meaning |
|---|---|---|
| `SlotKeys` | `SHIFT` | modifier for 1-0: `SHIFT`, `CTRL`, `ALT` or `NONE`. Restart after a change |
| `ToolKey` | `X` | tool key, `none` turns it off. Restart after a change |
| `EquipPrompt` | `true` | show the equip hint |
| `ToolReach` | `3.0` | how close a rock or tree must be, in meters (1.5 to 6) |
| `UseCompost` | `true` | compost bucket for watered farm plots |
| `AutoTool` | `true` | the right tool comes out when you hit with the wrong one |
| `AutoToolFromWeapon` | `true` | auto tool also from melee weapons, only right in front of you |
| `BagFirst` | `false` | pickups go to the bag instead of empty hotbar slots |
| `Debug` | `false` | extra log lines |

## Things to check on first run
These couldn't be checked without the game running. Run `toolbag_status` in the UE4SS console and look at `UE4SS.log`:
1. **Which tab is last.** The log line `last tab (type N) ...` names it. If the game refuses a tool there, the window says "The game did not accept ...". The game filters which items each tab accepts. That result decides whether the toolbag needs a different home.
2. **Move function.** The log shows `move function ...(...)` with the parameters the game expects. If it says "not usable", send the log.
3. **Shift+1.** Check that the game's own hotbar key 1 doesn't also fire when you press Shift+1. If it does, set `SlotKeys = CTRL` or `ALT`.
4. **X key.** Check that X isn't already bound in the game.

## Credits
Based on **Expanded Inventory** by notto0606 (MIT). The auto tool, tool key and bag-first code come from it. The inventory-size feature was replaced by the toolbag. See `LICENSE`.
