# Improved Quest Tracker

Sort options for the default quest tracker in **WoW Forever** and **MoP Classic**. It keeps
Blizzard's tracker and only changes the order of your quests, so the tracker still looks and
works as usual, with mouse or controller.

## Features

- **Sort** tracked quests by zone (current zone first), level, level reversed, title or
  distance (WoW Forever).
- **Completed quests** at the top or bottom.
- **Sort menu**: the filter button on the tracker's *Quests* header, the quest right-click
  menu, **R3** while the tracker has controller focus, or a key binding
  (*Key Bindings > AddOns*). Fully usable with a controller: D-pad, A to pick, B to close.
- **Objective sound**: plays a sound when an objective of a tracked quest completes.

On MoP Classic the options are in the tracker header's right-click menu.

## Commands

| | |
|---|---|
| `/iqt` | show the settings and commands |
| `/iqt sort off\|zone\|level\|levelr\|title\|distance` | sort mode |
| `/iqt completed off\|top\|bottom` | where completed quests go |
| `/iqt zonefirst` | toggle current zone first |
| `/iqt sound` | toggle the objective complete sound |
| `/iqt menu` | open the sort menu |
| `/iqt debug` | list tracked quests and whether the tracker shows them |

When the tracker is full, Blizzard only shows the quests that fit; the addon reorders the
tracked list so those are your top-sorted quests. Raise the Objective Tracker height in Edit
Mode to see more.

## Install

- **CurseForge app**: search *Improved Quest Tracker*.
- **Manual**: download `ImprovedQuestTracker-<version>.zip` from
  [Releases](https://github.com/markgravity/ImprovedQuestTracker/releases) and unzip it into
  `World of Warcraft/<flavour>/Interface/AddOns/` so you get `AddOns/ImprovedQuestTracker/`.

## Development

Clone the repo straight into the `AddOns` folder (or symlink it) and `/reload` in game.

- `python3 tools/make_addon_icon.py` regenerates `textures/ic_addon.tga` and
  `tools/addon_logo.png` (needs Pillow).
- `python3 tools/package.py` builds `dist/ImprovedQuestTracker-<version>.zip`.

### Releasing

1. Bump `## Version:` in `ImprovedQuestTracker.toc`.
2. Add a `## <version>` section on top of `CHANGELOG.md`.
3. Commit, then `git tag v<version> && git push origin main v<version>`.

The [release workflow](.github/workflows/release.yml) checks the tag matches the TOC, builds the
zip, creates the GitHub release with the changelog section, and uploads to CurseForge when
`CF_API_KEY` is set. A tag with a suffix (`v0.2.0-beta1`) makes a pre-release / beta. The
repository variable `CF_GAME_VERSION` takes a comma-separated list of CurseForge game versions
(default `1.60.1`, WoW Forever).

## Support

Improved Quest Tracker is free and always will be. If it makes your game better and you'd like
to say thanks, you can buy me a coffee:

- [Ko-fi](https://ko-fi.com/markgravity)
- [PayPal](https://paypal.me/markgravity)

## Credits

Sort options inspired by [Kaliel's Tracker](https://www.curseforge.com/wow/addons/kaliels-tracker)
and the objective sound by my [Kaliel's Tracker mod](https://github.com/markgravity/kaliels-tracker).
No code from them is included.

## License

[MIT](LICENSE)
