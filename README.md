<p align="center">
  <img src="assets/awesome-qst.svg" alt="qst Logo" width="577">
</p>


This repository hosts the curated script catalog for [qst](https://github.com/gitanelyon/qst), a terminal-first Linux application launcher built with Rust and Ratatui.

## What is here

- `scripts/`: scripts used by Qst, including shell, Python, Perl, and other supported script types.
- `misc/`: scripts used for Qst's development, including logo generation, and catalog management.
- `API.md`: protocol reference for `qst!` directives, actions, metadata, and row formatting.
- `DOCS.md`: installation instructions, alias configuration, and script authoring guidance.

Scripts may declare a metadata header with `qst! meta name,version,author,description`. Qst recognizes the same header at runtime, and `help.sh` and `loader.sh` surface those fields in their own views.

## Installing Scripts

> Note: Its recomended to install a script manager like `loader.sh` to make managing scripts easier.

Manual installation:

```bash
mkdir -p ~/.config/qst/scripts
cp -r scripts/* ~/.config/qst/scripts/
chmod +x ~/.config/qst/scripts/*
```

Through Qst:
```bash
qst --install <script>
```

Through `loader.sh`:
```
loader i <script>
```

## Included scripts

A full updated list of scripts, authors, versions and descriptions can be found in [catalog.tsv](catalog.tsv)

Some commonly used scripts include:
- `bluetooth.sh` - Bluetooth device discovery and management.
- `calculator.sh` - Expression evaluation for quick calculations.
- `clipboard.sh` - Clipboard history browser and writer.
- `emoji.sh` - Emoji browser for fast lookup and copying.
- `loader.sh` - Script installation and management helper.
- `media.sh` - Control currently playing media via playerctl (MPRIS).
- `runner.sh` - Shell command launcher.
- `symbols.sh` - Nerd Font symbol browser for fast copying.
- `todo.sh` - Simple task list manager.
- `weather.sh` - Current weather and three-day forecast for your area.


## Aliases

Optional aliases can be defined in `~/.config/qst/alias.toml`.

If you use extension-based keys (`.sh`, `.pl`, etc.), quote them in TOML:

```toml
[scripts]
"volume.sh" = "v!"
battery = ":"
"clipboard.sh" = "+"
"symbols.pl" = "sym!"

[apps]
# You can also set app aliases!
"btop++" = "alacritty -e btop"
```

Unquoted dotted keys also work, but they are interpreted as TOML dotted paths.

Full protocol reference: [qst Script API](https://github.com/GitanElyon/qst/blob/main/API.md). For advanced authoring examples, see [API.md](API.md).
