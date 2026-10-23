# Qst Script API - Advanced Examples

This guide shows real-world patterns for writing qst scripts. It is a companion to the authoritative protocol reference:

- [qst Script API](https://github.com/GitanElyon/qst/blob/main/API.md)

The scripts referenced below are the bundled ones in this repository. Open them alongside this guide to see the patterns in context.

## Single-result mode

Instead of a list of rows, a script can return a single result with `qst! single <query>|<result>`. The calculator uses this to replace the input line with the answer:

```bash
#!/usr/bin/env bash
query="${1:-}"
result="$(evaluate "$query")"

if [[ -z "$query" ]]; then
    echo "qst! single |"
elif [[ -z "$result" ]]; then
    echo "qst! single $query|Error"
else
    echo "qst! single $query|$result"
fi
```

See `calculator.sh` for the full version, including error handling when no calculation backend is installed.

## Action chaining

Actions are evaluated left to right, so a row can do several things at once. The todo script chains `Execute,ResetPrompt` so an item is acted on and the prompt returns to `todo ` for the next entry:

```bash
#!/usr/bin/env bash
echo "qst! title  Todo @meta:fuzzy=true"
echo "qst! action Execute,ResetPrompt"
echo "qst! item  Buy milk|todo a Buy milk|Execute,ResetPrompt"
echo "qst! item  Ship it|todo c Ship it|Execute,ResetPrompt"
```

Note the `@meta:fuzzy=true` on the title: it makes the whole response filterable with fuzzy matching instead of exact substring matching. For short lists of items, this is often what you want.

## Nonselectable and centered rows

Use `@meta:nonselectable=true` for rows that are purely decorative, and `@meta:center=true` to center them. The clock uses both to render a large glyph clock and separators:

```bash
#!/usr/bin/env bash
echo "qst! item  $(date '+%a, %d %b %Y')|$(date '+%a, %d %b %Y')|None @meta:nonselectable=true @meta:center=true"
echo "qst! item  ───────────────────────|───────────────────────|None @meta:nonselectable=true @meta:center=true"
```

Help rows are a common use of `nonselectable` without `center`, so they render like normal items but cannot be activated:

```bash
#!/usr/bin/env bash
echo "qst! title  Todo Help "
echo "qst! action None"
echo "qst! item  todo a <item>      add a new item|todo a <item>|None @meta:nonselectable=true"
echo "qst! item  todo h             show this help|todo h|None @meta:nonselectable=true"
```

See `clock.sh` and `todo.sh` for the full layouts.

## Styled labels

Rows, titles, and messages can be styled with `@meta:fg` and `@meta:bg`, plus the text modifiers `@meta:bold`, `@meta:dim`, `@meta:italic`, `@meta:underline`, `@meta:strikethrough`, and `@meta:reversed`. Colors accept `#rrggbb`, `#rrggbbaa`, or names like `red`. Styling applies to the visible label only, so centered content stays centered and styled labels keep their look while selected. Use `@meta:fill=<color>` to set a background across the whole row instead; a label `bg` overrides it on the label. A status script can map each row's color to its severity:

```bash
#!/usr/bin/env bash
echo "qst! title  Service Health @meta:bold=true"
echo "qst! action CopyToClipboard,ExitApp"

echo "qst! item  api      * up|api @meta:fg=green"
echo "qst! item  worker   * degraded|worker @meta:fg=yellow @meta:bold=true"
echo "qst! item  cache    * down|cache @meta:fg=red @meta:bold=true @meta:reversed=true"
echo "qst! item  legacy   * retiring|legacy @meta:dim=true @meta:strikethrough=true"
echo "qst! item  maintenance tonight|maintenance @meta:fill=#332200 @meta:fg=#ffcc00 @meta:nonselectable=true"
```

Colors and modifiers combine freely, and `@meta:fg`/`@meta:bg` work anywhere a label is shown.

## Copy to clipboard and exit

A single row action can combine copy and exit so one `Enter` does the whole job. The emoji browser uses `CopyToClipboard,ExitApp` as its default action:

```bash
#!/usr/bin/env bash
echo "qst! title Emoji"
echo "qst! action CopyToClipboard,ExitApp"
echo "qst! item  😀 grinning face|😀"
echo "qst! item  ❤️ red heart|❤️"
```

## Storing data with directives

Scripts can persist data with `qst! write`, `qst! read`, and `qst! delete` against `~/.config/qst/storage/<script-name>/`. Files are created on first write. A minimal bookmark store:

```bash
#!/usr/bin/env bash
query="${1:-}"

if [[ "$query" == b* ]]; then
    echo "qst! write bookmarks|pback|${query#b }"
    echo "qst! message Bookmark saved"
fi

echo "qst! read bookmarks"
```

This reads every stored line back as a row. Per-line actions on the stored data use the read/write action variants (`fpeek`, `bpeek`, `pfront`, `rmfront`, `purge`, ...) documented in the protocol reference.

## Logging

Scripts can write timestamped entries to their own log under `~/.local/state/qst/` with `qst! log`:

```bash
#!/usr/bin/env bash
echo "qst! log Script started with query: '${1:-}'"
```

