# Why import-books is shaped this way

The phases are ordered by what a mistake costs to undo. A field is a one-line fix next week; a
filename, a folder or a variant link is a move, a rename or a relink, and a deleted file is gone.
Every rule below follows from that.

## Research before the plan

Phase 2 (identify) runs before phase 3 writes a single target name. The naming rules (catalogue
code, publisher spelling, printing qualifier, year) all depend on facts phase 2 gathers, so a plan
written first would be rewritten after. A name that ships wrong is not an edit: it is a rename on
the server and a broken link for anyone who knew the old path.

## One network phase

Only phase 2 contacts external sources, and it caches what it fetched in the run dir. Every other
phase reads the source folder, the server and the run dir, so a failed run restarts from a known
point instead of re-fetching. Network calls fail quietly (a page moved, a rate limit, a bot wall),
and confining them to one phase keeps those failures in one place where the agent is paying
attention to them.

## Duplicates, then paths, then metadata

Metadata written before duplicate detection is written twice, once per copy. Metadata written
before a rename can be lost with it (`isbn`, `language` and `product_code` live only in the
database). So the survey hashes for twins and the plan fixes every name before phase 8 writes a
field.

## The plan is the contract

`plan.json` holds every judgement; the scripts hold none. The agent decides, the user approves, the
scripts execute without re-deciding. That split is what makes the execute phases re-runnable: each
script keeps an append-only receipt in the run dir and skips rows already done, so an interrupted
upload or a proxy error mid-index is resumed, not repaired by hand.

## Reconcile before writing

An import over a populated shelf must not overwrite what a person curated. `check_shelf.sh` diffs
every row the shelf already holds against the plan and stamps the plan; `apply.py` refuses an
unstamped plan, because an unstamped plan looks exactly like a first import and would be written in
full. Only a field the shelf lacks is written freely. A field both sides hold and disagree on
(`differs`) is written only after the user approved it by name, since the shelf's value may be a
decision the plan cannot know about. `duplicates link` moves an already-filed child rather than
refusing, so variant links get the same gate.

## Scripts refuse, they do not warn

An unmet precondition is exit 2 and nothing written. A warning is a line an agent can read past; a
refusal is a stop it has to resolve. Refusing a duplicate target or an open question costs a minute;
a partial write the agent failed to notice costs a cleanup.

## Walkthrough ordered by cost to reverse

The hard stop leads with `permanent`, `rename` and `relink` decisions, not with what looks most
interesting. Exclusions are listed one per row with evidence because an exclusion is the one
decision that silently loses content: a summary count hides the file that should have been kept.
"Conforms" is said out loud because silence reads as "not checked".

## OCR is a branch, not a phase

Whether text layers are added by the server (`ocr: server`) or by the user's own tool
(`ocr: handover`) changes when OCR happens, not what the shelf ends up with. Server OCR runs after
indexing, queued in one batch so nothing local has to stay awake for it; a handover runs before
upload so the shelf receives the finished files. Both start from the same per-page survey, because
a file-level text share hides image-only pages inside otherwise digital books.

## A version floor, not workarounds

The skill names a minimum CLI and server version instead of carrying workarounds for old bugs. A
workaround outlives the bug it was written for; a floor does not.
