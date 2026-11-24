<p align="center"><img src="docs/assets/logo.png" alt="Mark Your Target logo" width="135"></p>

# Mark Your Target

A World of Warcraft: Forever add-on by **Goshdev** for building a reusable NPC targeting macro. Type part of an NPC name, pick the mob you want, and save it straight to WoW’s Macros window.

[Project site](https://grzelu1301.github.io/mark-your-target/) · [Download v1.2.0](https://github.com/grzelu1301/mark-your-target/releases/tag/v1.2.0)

## Use it in game

1. Open the editor with `/myt` or click its skull icon in MinimapButtonButton.
2. Type an NPC name or choose a suggestion. For example, `Bat` finds **Vampiric Duskbat**. Search checks your current zone first and checks all zones if there are no local matches. **All zones** searches the full catalog immediately.
3. Press **Save** out of combat. The add-on creates or updates **Mark Your Target** with the Hunter’s Mark icon and selects it in WoW’s Macros window. Drag it onto an action bar to use it.

The macro clears your old target, looks for the name you picked, clears a dead match, then tries to skull-mark and ping a living target using WoW’s macro commands.

## Install

Unzip the release into `World of Warcraft/_forever_/Interface/AddOns/` so that `MarkYourTarget/MarkYourTarget.toc` is directly inside `AddOns`. Restart WoW after a first install. The add-on targets **WoW: Forever 1.60.1**. MinimapButtonButton is optional.

## Screenshots

| Pick an NPC | Save to WoW’s Macros window | Search across all zones |
| --- | --- | --- |
| ![The editor with Vampiric Duskbat selected](docs/assets/choose-target.png) | ![WoW’s Macros window displaying Mark Your Target](docs/assets/macro-window.png) | ![The editor showing results for Cat with All zones enabled](docs/assets/search-all-zones.png) |

## NPC data

The add-on ships with 9,810 distinct English NPC names. Zone coverage varies, and you can always enter a name manually. See the [data credits and licenses](DATA-CREDITS.md).
