# Profiles

A profile is a library's shelving rules. The skills read them instead of hard-coding a layout.
Each profile is a folder, `profiles/<name>/`, holding two files. `default` is the shipped one.

## The contract

Skills cite a profile by key and by heading, so every profile must keep both.

**`profile.json`** has every one of these keys:

`category_folders`, `book_variant_kinds`, `map_variant_kinds`, `token_variant_kinds`, `filename_pattern`,
`refused_book_formats`, `licence_placement`, `entry_rule`, `roots`, `armory_category_folders`.

`roots` currently matters only for `armory`: the other collection roots (`books`, `maps`, `tokens`,
`models`, `audio`) are fixed by the server, so their entries are informational.

**`conventions.md`** starts with `# <one-line description>` (setup shows it when offering
profiles) and has these `##` headings, spelled exactly:

Goal, Layout, Filenames, Variants and the entry, Tags, Licence placement,
Maps, tokens, models and audio, Armory, Metadata.

The headings are the citation anchors. A profile may add sections, never rename or drop one.

If you only want to change a few rules, use overrides instead: see [`docs/overrides.md`](../docs/overrides.md).

## Names

A shipped profile name shadows a user folder of the same relative name.

## Contributing a profile

1. Copy `profiles/default` to `profiles/<your-name>`.
2. Change the rules, keeping every key and heading above.
3. Run `python3 -m unittest discover -s lib`; CI runs the same contract test over every folder here.
4. Keep examples neutral (Example Press, Starfall RPG); no private paths or purchase data.
