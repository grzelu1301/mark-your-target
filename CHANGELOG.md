# Changelog

## 1.5.0

- Open `/myt`, choose or type a name, and use **Add to list**. Click suggestions to add more names, or use **Remove** to adjust the list. **Save list** updates the existing macro and opens WoW’s Macros window.
- Use the action-bar macro to find the first living match in list order, skull-mark it, and ping it when pings are enabled. The number of names that fit depends on WoW’s 255-byte macro limit.
- Save at least two names and assign **Cycle Targets** in **/myt → Keybindings**. Each press tries the next exact name and uses a different raid marker for each list entry. Press again if the current name is missing or out of range.
- **Quick Target** is separate. Type `/mytgt Ghostmaw`, then press its key or click the button. The Keybindings panel shows what each shortcut does and whether it has a target or list ready.

Fully restart WoW after updating so it loads the bindings. Built for WoW: Forever 1.60.1.

## 1.4.0

- Type `/mytgt Ghostmaw` to prepare a target out of combat. Click **Quick Target** or use its optional keybind to target, skull-mark, and ping without using a macro slot.
- Select an NPC or player and use `/mytgt [@target]` for Quick Target or `/myt [@target]` to update the saved macro. Forever player surnames are included.
- When pings are disabled, the picker and chat point you to **Options → Ping System → Enable Pings**.
- The crosshair minimap icon now has WoW’s circular gold border and follows the Classic minimap as it resizes. MinimapButtonButton can still collect it.

## 1.3.0

- Type `/myt <name>` to update the macro directly from chat.
- Keep exact and out-of-zone matches accessible when there are local suggestions.
- Rebuild the NPC catalog from Forever spawn records and player observations. Ghostmaw now appears as a Riverglades match.

## 1.2.1

- Explicitly license the add-on code under GPLv3 and include the license notice in the install ZIP. In-game behavior stays the same.

## 1.2.0

- Match NPC names by exact name, prefix, word start, or any matching substring.
- Automatically show all-zone suggestions when the current zone has no match.
- Create or update the macro with the Hunter’s Mark icon and open WoW’s Macros window with it selected.
- Include an offline English NPC catalog, the `/myt` command, and a button that MinimapButtonButton can collect.
