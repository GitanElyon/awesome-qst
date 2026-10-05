# Contributing to Awesome Qst

Contributions to the `awesome-qst` repo are welcome! This includes new scripts, bug fixes, documentation improvements, and more.

## How to contribute

Either open a pull request with your changes or open an issue to discuss new ideas or problems.

When contributing scripts, please ensure they follow the protocol outlined in the [qst Script API](https://github.com/GitanElyon/qst/blob/main/API.md) and include documentation in `DOCS.md` if necessary.

## Script standards

Every script added to this pack should meet the following baseline standards:

- Be self-contained and focused on one task.
- Start with a metadata line in the format described in the [qst Script API](https://github.com/GitanElyon/qst/blob/main/API.md) so it can be added to `catalog.tsv`.
- Accept the current query payload through script arguments and handle empty input cleanly.
- Support a `h` or `--help` style help path, and a `v` or `--version` path when it makes sense for the script.
- Emit only qst-compatible line-oriented output on stdout; keep stray logging, debugging, and errors off the normal output stream.
- Use `qst!` directives consistently for titles, messages, actions, item overrides, and storage operations.
- Document any non-obvious behavior, required dependencies, or external state in `DOCS.md`.
- Preserve backward compatibility when possible, especially for metadata fields, aliases, and action names.
- Prefer portable shell or interpreter features that work with the supported script styles listed in the [qst Script API](https://github.com/GitanElyon/qst/blob/main/API.md).
- Fail clearly when required dependencies are missing or when the script cannot complete its task.
- For Bash scripts, enable `set -euo pipefail` by default and make any intentional empty or missing-value cases explicit in the code.
- Run `bash -n` on edited shell scripts before opening a pull request.
- Every script update in any capacity should bump the script's version so Qst's registry can pick up on the changes.
- After adding, removing, or updating a script, run `misc/generate_catalog.sh` and add the regenerated `catalog.tsv` in the same commit so Qst's script registry stays updated.

Scripts that manage persistent state should also follow these rules:

- Use the qst storage directives instead of inventing a private storage format when qst already provides the needed behavior.
- Keep stored values stable and predictable so helper scripts and future changes can read them safely.
- Avoid destructive writes unless the user explicitly requested a destructive action.

## Commit standards

Commits that touch scripts should follow the [Conventional Commits](https://www.conventionalcommits.org) format:

```
<type>(<scope>): <short description>
```

Use the script filename as the scope and keep the description in the imperative mood. For example:

```
fix(battery.sh): correct second row of glyph matrix
feat(dict.sh): add quick word definitions
```

A commit body or footer expanding on the change is encouraged but not required. As covered under Script standards, every commit that adds, removes, or updates a script must also include the regenerated `catalog.tsv`.

# Script Architecture

The `awesome-qst` script pack is designed to be modular and extensible. Each script is a separate module that can be easily added, removed, or updated without affecting the overall functionality of the pack. That being said, there are some guidelines to follow when creating new scripts:

Each script should be self-contained and should not rely on other scripts unless absolutely necessary. If a script does depend on another script, it should clearly document this dependency in its documentation.

## Script Requirements

### Metadata

At the top, each script should contain a metadata line that declares the script's name, version, author, and optional description. This metadata is used by `help.sh` and `loader.sh` to display script information.

Example:
```bash
echo "qst! meta My Script, 1.0.0, Your Name, A brief description of what the script does"
```

Scripts can also emit `qst! meta name`, `qst! meta version`, `qst! meta author`, or `qst! meta description` after the header if they need one field for their own UI.

### Distro Compatibility

Scripts should aim to be compatible with a wide range of Linux distributions and environments. Avoid using features or dependencies that are not commonly available unless the script is specifically designed for a niche use case.

This includes things like avoiding relying on a specific package manager, desktop environment, or shell unless the script is explicitly for that context. This also means not embedding another language like python in a bash script.

## Script Protocol

Scripts in `awesome-qst` communicate with the host application (qst) using a line-oriented protocol. Each line of output from a script is parsed by qst to determine how to update the UI, what actions to set, and how to respond to user input.

### Arguments

When a script is invoked, it receives the current query payload as its arguments. The script can use these arguments to generate dynamic output based on user input.

Arguments must be handled by the script itself and are not automatically parsed by qst. This allows for maximum flexibility in how scripts interpret and use the input data.

Unless there is a reason not to, scripts should accept single letter flags for common options (e.g. `h` for help, `v` for version, etc.) and should provide a `h` (`help`) option to display usage information.

# Legal

By contributing to this repository, you agree that your contributions will be licensed under the MIT License. Please ensure that any code you submit is your original work or properly attributed if it includes third-party code.
