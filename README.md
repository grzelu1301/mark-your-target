<p align="center"><img src="docs/assets/logo.png" alt="Mark Your Target logo" width="135"></p>

# Mark Your Target

A WoW: Forever add-on by **Goshdev** for when you keep changing the NPC name in the same targeting macro. Type `/myt`, pick a mob, and hit Save. You can keep the same macro on your action bar as you switch targets.

[Project site](https://grzelu1301.github.io/mark-your-target/) · [Download v1.2.1](https://github.com/grzelu1301/mark-your-target/releases/tag/v1.2.1)

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

The add-on code is licensed under [GPLv3](LICENSE.md).

Project icon adapted from [Crosshair by Delapouite](https://game-icons.net/1x1/delapouite/crosshair.html), licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). The artwork was recolored and exported as PNG.
