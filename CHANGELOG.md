# Changelog

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
