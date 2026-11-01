# Remember Party Lane Preference

A small UI mod for Valve's **Deadlock** that remembers your party **lane preference** (*Balanced* / *With Party*),
so you don't have to switch it back every time you open the party popup.

## Features

- **"Remember my choice" checkbox** in the party popup, under the *Lane preference* dropdown.
  While it's checked, the popup re-selects your remembered choice every time it opens
  (the game itself always resets it to *Balanced*).
- **Lane preference indicator** under the party avatars on the main menu, showing *With Party* or *Balanced*.
  Hover for a tooltip, click to open the party popup.
- **Remembered across game restarts.** Defaults to *With Party* with the checkbox on.
- Uses the game's own text (all languages), icons and checkbox style. No new art.

## Install

1. Download `remember_party_lane_preference.vpk` from the [latest release](../../releases/latest).
2. Add it in **Deadlock Mod Manager** (or another mod manager) and enable it.
3. Restart Deadlock.

Client-side UI change only: it doesn't touch gameplay or game memory. Its only network use is loading its
small storage page from GitHub Pages (see below).

## How saving works

Deadlock's UI scripts have no storage of their own. Like other Deadlock mods (e.g. HP Colors v2, Roster Tools),
this mod loads a tiny page, [`docs/index.html`](docs/index.html), in a hidden in-game browser panel, and the page
keeps your two settings in its `localStorage` (Steam's browser profile, on your PC).

- The page is served by GitHub Pages from this repo:
  `https://passionaterain.github.io/deadlock-remember-party-lane-preference-mod/`
- It stores only `remember` (true/false) and `choice` (Balanced / With Party).
- Its Content-Security-Policy blocks all network access: it can't send anything anywhere.
- Offline? The mod falls back to the defaults for that session and leaves your saved settings untouched.

## Limitations

- The game only receives your choice when the party popup is opened at least once in a session.
- The indicator shows what the mod applied, not a value read from Valve's servers.
- Game updates can break UI mods. If the party popup changes, this mod needs a rebuild.

## Build from source

Requirements: Windows, [Counter-Strike 2 Workshop Tools](https://developer.valvesoftware.com/wiki/Counter-Strike_2_Workshop_Tools)
(for Valve's `resourcecompiler.exe`), and optionally [Source 2 Viewer](https://github.com/ValveResourceFormat/ValveResourceFormat/releases)
to decompile game files.

```powershell
.\tools\build.ps1 -Src src\mod -Name remember_party_lane_preference
```

Output: `build\remember_party_lane_preference.vpk`. Packing uses the included `tools\vpkpack.ps1`
(CS2 doesn't ship `vpk.exe`). Implementation notes are in [`NOTES.md`](NOTES.md).

Source layout:

| Path | What |
|---|---|
| `src/mod/panorama/layout/popups/popup_join_or_create_party.xml` | Party popup + "Remember my choice" checkbox |
| `src/mod/panorama/layout/citadel_party.xml` | Party bar + indicator + hidden storage panel |
| `src/mod/panorama/scripts/rplp_popup.js` | Re-applies the remembered choice when the popup opens |
| `src/mod/panorama/scripts/rplp_bar.js` | Indicator and saving/loading |
| `docs/index.html` | Storage page (GitHub Pages) |
| `tools/` | VPK reader, packer and build script |

## AI disclosure

I built this mod in collaboration with **Claude Opus 5.5** (Anthropic), an AI coding assistant, which helped
with research, reverse-engineering the game's UI files, and writing the code and docs.

I don't support or use generative AI for art, images, music, voice or other creative work.
This mod contains no AI-generated assets: every icon, text and style in it is Deadlock's own.

## Credits

- [Source 2 Viewer / ValveResourceFormat](https://github.com/ValveResourceFormat/ValveResourceFormat) for decompiling game files.
- The hidden-page storage technique used by [HP Colors v2](https://github.com/Hantu-Raya/hpv2-store) and
  [Roster Tools](https://github.com/piotrpanawas/deadlock-roster-tools-bridge).

Not affiliated with or endorsed by Valve. Deadlock is a trademark of Valve Corporation.

## License

[MIT](LICENSE) © 2026 PassionateRain
