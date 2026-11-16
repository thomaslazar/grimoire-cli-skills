# Overrides

The skills follow a shelving profile (the shipped `default`, or one you point at). You change it for
your library without forking anything, from your library repo (`setup` scaffolds it).

## The layers

Later layers win, in this order:

1. **The profile**: `profiles/<name>/` shipped here, or a folder of your own (`profile.json` +
   `conventions.md`).
2. **Your overrides**: the files in `grimoire/overrides/` (or whatever `overrides` names).

Skills do not hard-code any of it. They run `python3 <skills>/lib/grimoire_skills/config.py`, which
prints JSON with `profile_dir`, `overrides_dir`, `lines_dir`, `ocr`, `cli`, the merged `profile`, and
`rules`: the prose files to read, profile `conventions.md` first, then your `*.md` overrides. Add
`--start DIR` to resolve from another folder. `grimoire-skills.json` is found by walking up from the
current directory.

## Prose overrides (`grimoire/overrides/*.md`)

- Every `*.md` file is read **after** `conventions.md`, in **sorted filename order**.
- By default an override **adds** to the profile. It replaces a profile rule only where it says so,
  naming the profile section heading.
- Nothing parses these files; the agent reads them. Be explicit and give an example.

Example, `grimoire/overrides/tags.md`:

```markdown
# Library tags

Replaces: Tags - companion prefix
Companion material of a French-language book carries `pour:<code>` instead of `for:<code>`.
English rows keep `for:`.

Adds: every book bought as part of a bundle gets the tag `bundle`, in addition to the tags the
profile asks for.
```

The headings you can cite are the profile's `##` sections: Goal, Layout, Filenames, Variants and the
entry, Tags, Licence placement, Maps, tokens, models and audio, Armory, Metadata.

## `grimoire/overrides/profile.json`

Optional. Merged onto the profile's `profile.json` by a plain top-level replace: each key you set wins whole. Lists
**replace**, they do not append, and nested objects (`roots`) are replaced whole, not merged.

```json
{
  "category_folders": ["Core", "Supplements", "Adventures", "Maps"],
  "entry_rule": "newest"
}
```

That leaves exactly four category folders, and every other key as the profile has it.

| key | read by |
|---|---|
| `category_folders`, `armory_category_folders` | `import-books` `check_plan.py` (valid category folder; armory list when the path starts with `roots.armory`) |
| `book_variant_kinds`, `refused_book_formats` | `import-books` `check_plan.py` |
| `map_variant_kinds`, `token_variant_kinds` | `import-maps` `publish_maps.py` (tokens plans use the token list) |
| `roots` | `check_plan.py`, only `roots.armory`; the other roots are fixed by the server |
| `filename_pattern`, `licence_placement`, `entry_rule` | no script; they are stated for the agent and match `conventions.md` |

If you change one of the last three, say so in a prose override too.

## `grimoire-skills.json`

At the root of your library repo. Relative paths resolve against that file's folder.

| key | meaning |
|---|---|
| `profile` | shipped name (default `default`), or a folder path. A shipped name wins over a folder of the same name |
| `overrides` | folder of override files; none if absent |
| `lines` | folder of line references; none if absent |
| `ocr` | `server` (default) or `handover`; anything else is an error |
| `cli` | path to `grimoire-cli` |

CLI resolution, first match wins: `--cli PATH`, `cli` in the config, `grimoire-cli` on `PATH`,
`./bin/grimoire-cli` (resolved against the config root).

## Line references

`grimoire/lines/<line>.md` holds what `import-books` needs to identify one game line (lookup sources,
catalogue codes, traps). Set `"lines": "grimoire/lines"`. See [`lines/README.md`](../lines/README.md).

## A whole other profile instead

Set `profile` to a shipped profile or your own folder. It must meet the contract in
[`profiles/README.md`](../profiles/README.md): every `profile.json` key and every `##` heading, which
skills cite by name. Overrides still apply on top of it.

Choose an **override** when you change a few rules or add some (a tag, a folder list). Choose a
**profile** when the whole layout differs (other folder scheme, filenames, entry rule), so you would
otherwise override most sections.

## Pitfalls

- A list in `overrides/profile.json` replaces the whole list. Repeat the entries you keep.
- Files load in sorted filename order; if two disagree, the later name wins in practice. Prefix
  with numbers (`10-tags.md`) when order matters.
- A replacement without the exact heading name is just an addition.
- Keep secrets out of the repo. Never copy `~/.grimoire-cli/config.json`; log in with
  `grimoire-cli login` in your own terminal.
