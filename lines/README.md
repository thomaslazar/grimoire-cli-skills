# Line references

A line reference is one Markdown file per game line: what `import-books` needs to identify that
line's products. None ship with the skills. Keep yours in a folder of your own and name it in
`grimoire-skills.json`:

```json
{"lines": "lines"}
```

The skill reads `<lines>/<line>.md` for the line it imports (for example `lines/starfall-rpg.md`).
Without one it proposes a lookup source and asks before using it.

## What a line reference holds

- **Lookup sources**, in the order to try them: the line's catalogue or wiki, the publisher's shop,
  storefronts, archives. Per source: how to query it (URL shape, export or API), which fields it
  carries, and which it gets wrong.
- **Catalogue-code rules**: the code families (`ES` for supplements, `EA` for adventures …), where the
  authoritative numbering lives (a series index page, not a product page), padding, and known
  renumberings or gaps.
- **Field precedence** where it differs from the skill's default: for example "the shop's year is the
  listing date, use the imprint", or "the cover prints the stock number top right".
- **Traps**: collisions (one code on two products), components that match their parent product,
  spellings the catalogue uses that filenames do not, edition boundaries.
- **Folder decisions** already made for the line: which system a product family goes to, series
  folders, settings that are lines of their own.

Keep it to facts measured on real lookups, each with an example. Write a firm negative down too
("no per-issue listing anywhere"), so the next import does not repeat the search.
