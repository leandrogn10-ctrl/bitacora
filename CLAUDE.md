# Bitácora — project notes for Claude

Single-file PWA: a personal, literary, **single-user** media logbook (films / TV / games / books /
albums). The entire app is **`index.html`** — HTML + CSS + vanilla JS, **no build, no dependencies**.
`sw.js` is the service worker. `bitacora.html` is a legacy duplicate; **`index.html` is canonical**
(the code-push + GitHub Pages target). No social graph — per-entry **AI takes** are the recommendation
layer.

## Identity (don't drift from this)
- Theme **"Cabaret Clásico"**: wine ground (`--bg:#160810`), **gold** accent (`--accent:#f0b24a`,
  `--gold:#f5c860`), **magenta neon** (`--accent2:#ff3d8a`, `--accent-soft:#ff5d96`) — all CSS vars on
  `:root`/`[data-theme]`.
- Type: **Instrument Serif** (titles/prose) + **JetBrains Mono** (labels/metadata/data). Never
  Inter/Roboto/system.
- Guardrails: no AI-slop, content over chrome, **no emoji-as-icons**, **no chart libraries** (hand-rolled
  CSS/SVG), rationed accent, verified contrast, motion gated behind `prefers-reduced-motion`.

## Data model — the load-bearing part (FEAT-02 event model)
`state = { collections[], items[], settings{}, tagGroups[], tagAssignments{}, tagOrder{}, lastModified }`,
persisted to `localStorage['bitacora.v2']`.

- **item** = a *title/work*: `{ id, title, collectionId, year|null, creator|null, tags[], config,
  createdAt, updatedAt, events[], …PROJECTED fields }`
- **event** ∈ `item.events[]` = an *encounter*: `{ id, date, kind, rating, status, notes, claudeNote,
  publicReview, claudeReplies[] }`
- **Projection (critical):** the flat fields `rating/status/completedAt/notes/claudeNote/publicReview/
  claudeReplies` on the item are a *denormalized mirror of the latest event*, kept current by
  **`projectItem(item)`**. Every render path, the gist sync, and the LeandroOS `newtab.js` integration
  read these flat fields → `events[]` is purely additive. `migrate()` back-fills one event per legacy
  item (idempotent). **All writes go through the latest event then `projectItem()`** (entry submit,
  `respondOnLog`, clear-takes, share-go, quota-prune). `year`/`creator` are title-level.
- Helpers: `kindFor(collectionId)` → watch/read/play/listen/log · `latestEvent(item)` · `projectItem(item)`.

## Views / filters
`view = { collection, status, search, sort, tags[], minRating, creator, decade, mode, obsUnit }`.
- `mode`: **'shelf'** (grid, default) · **'diary'** (cosmic timeline) · **'observatory'** (stats). Tabs
  atop the main column; hotkeys `s`/`d`/`o`; ⌘K commands.
- **`renderItems()` is the mode dispatcher** → `renderShelf()` / `renderDiary()` / `renderObservatory()`.
  Every existing caller becomes mode-aware through it.
- Filtering: `getFilteredItems()` (shelf), `getDiaryEvents()` (diary). Shared helpers:
  `isViewDefault()`, `resetView()`, `anyFilterActive()`, `filterChipsHtml()`. Active filters render as
  removable chips. Diary excludes `queued` (backlog lives on the Shelf).

## Command palette (⌘K) — FEAT-01
`paletteActions()` builds actions (items, commands, collections, tags, **creators**, **decades**).
`cmdkCompute()` = fuzzy subsequence + **frecency** (own `localStorage['bitacora_palette_frecency']`, no
sync churn). Fallbacks `Log "…"` / `Ask Claude "…"`. `›` = command mode. `+` = combo filters
(`resolveFilterTerm`). `⌘⏎` on an item = **re-log** (rewatch). Hotkeys: `⌘K`, `/`, `n`, `?`, `s`/`d`/`o`,
`Esc` (cascade; Esc-Esc → default), `Tab` (→ default while browsing).

## Observatory (stats) — FEAT-03
`renderObservatory()`: fingerprint · gold-ramped ratings histogram · by-medium (collection-colored) ·
top tags · **by decade** · **top creators** · encounters-over-time · **Rewatch Lab** (glow-ups/fades).
`by titles ↔ by encounters` toggle. Bars are **click-to-filter** (drill into Shelf). Clean CSS bars, no
chart lib. ("Ask the Observatory" — aggregates→Claude paragraph — is the one designed-but-unbuilt piece.)

## Claude integration
`callClaude({system, userMessage, maxTokens, model})` — `model` overrides `state.settings.claude.model`.
`respondOnLog` (takes on save), `buildClaudeSystem/Message`. `fetchYearCreator` runs on **Sonnet**
(`ENRICH_MODEL = 'claude-sonnet-4-6'`) with an "abstain-don't-guess" prompt; `autoEnrich` (on new log) +
`enrichLibrary` (backfill: ⌘K "Enrich library" / Settings button). Direct browser API call; key lives in
settings, **never logged or exported**.

## Persistence / sync / security
- `save()` → `persistState()` with a `QuotaExceededError` guard (prunes oldest event takes).
- Sync = GitHub Gist; **`cleanStateForSync()` / `cleanStateForExport()` strip secrets** (PAT / API key /
  gist id). Never re-introduce secrets into exports.
- Code-push (Settings) pushes `index.html` + `sw.js` to GitHub Pages.
- **Bump `sw.js` `CACHE_NAME` on every shipped change** (currently `bitacora-v4`) — or phones serve a
  stale cached app.

## Verifying changes (this is how the build sessions worked — keep doing it)
1. **Syntax:** extract the main `<script>` block and `node --check` it (it's the *2nd* `<script>`).
2. **Run it:** serve on a **FRESH localhost port every time** (`python3 -m http.server <newport>`).
   ⚠️ A reused port can carry a **stale service worker** that serves a cached old app — a new port = a
   clean origin. (This bit us once: a different cached app showed up.)
3. **Seed:** write `localStorage['bitacora.v2']` directly, then `location.reload()`.
4. **Drive:** browser automation (claude-in-chrome). The injected JS world can't see the page's
   `let`/function globals (only DOM + localStorage) — drive via DOM events. **⌘K is swallowed by Chrome
   in automation** → dispatch a synthetic `keydown {key:'k', metaKey:true}` to test the palette.
5. Check the console for errors; screenshot for visuals.

## Workflow the user likes
- **Vision → decide → build → verify → commit.** For each FEAT: write a detailed, *code-grounded*
  vision; use `AskUserQuestion` for the pivotal forks; then build, verify in-browser, commit.
- Pair-programmer tone; challenge weak ideas; flag tradeoffs; don't oversell. Spanish/spanglish when he
  writes Spanish.
- **One feature per commit**, verified in-browser. Trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Branch off `main` for features.
- Hardware: **MacBook Pro M2 Pro / 16 GB** (room for SVG/CSS-anim/moderate WebGL; avoid runaway
  per-frame JS / huge DOM).

## Status — 2026-06-30
- **Shipped & merged to `main` AND pushed to `origin/main`** (origin now current through FEAT-05):
  FEAT-01 (palette + rating/tag/creator/decade filters + `?` cheatsheet + Esc/Tab reset),
  FEAT-02 (event model A/B/C + cosmic Diary "La Línea Sagrada"),
  FEAT-03 (Observatory + year/creator capture + Rewatch Lab),
  FEAT-09 (tag token-field + fuzzy typeahead + `≈ canonical` reuse hint; Settings dupe-scan +
  multi-select merge; one `applyTagMerge()` behind rename/cluster/multi-merge),
  FEAT-14 (description **voice system**: additive `noteSource` `''`/`me`/`claude`/`friend:Name`;
  three-lane rendering — Claude=mono+dotted dusty rail+✦, friend=serif quote+"— Name", you/legacy=serif —
  on cards/Diary/history; takes restyled to the machine voice; **serif reserved for the user's words**;
  takes stay auto-on-save),
  FEAT-05 (**Mood & Pace as AI-assigned tags** — no manual UI; AI researches the work and tags it.
  Both are plain **tags** in seeded groups via `settings.taxonomySeeded`: **Mood** `plum` = curated 12;
  **Pace** `sage` = slow/medium/fast. `fetchYearCreator` → **`fetchMeta`** returns
  `{year, creator, mood[], pace}` in ONE Sonnet call; `applyMeta` fills blanks only; `needsMeta` gates
  `autoEnrich` + `enrichLibrary`; `✦ fill` adds reviewable chips. Observatory **"By pace"** panel reads
  pace tags ordinal slow→med→fast, `data-tag` drill. `buildClaudeMessage` emits `- Mood:` / `- Pace:`.
  No scalar `pace` field / `view.pace` / manual controls. SW `bitacora-v8`).
- **Shipped, on branch `feat/status-paused` (NOT merged):** **FEAT-04** — **`paused` status** (one
  addition, not the audit's 5). The real gap: started-but-set-aside (TV/games you stepped away from)
  forced a lie — `active` (untrue) or `dropped` (too final, poisons drop-rate). Added `'paused'` to
  `STATUSES` (between active/done), the sidebar nav + `count-paused`, the entry `<select>`,
  `STATUS_LABELS`, `.cmdk-dot.st-paused` + `.status-paused` pill (cool slate `#6f7e8c`/`#9fb0bd` — reads
  "frozen" against the warm palette), `statusBoost` (1, between active's 2 and queued's 0.5). Paused
  shows in the Diary (it's a real encounter, not backlog) and is NOT counted as a drop or a completion
  (no `completedAt`); the queued→done auto-flip leaves it alone. The audit's "exclusive status / multi
  tags" half was already true (status is a scalar, tags an array); POL-31's `done`/`finished` drift is a
  cross-surface LeandroOS concern, not fixable from inside `index.html` → out of scope. Verified
  in-browser (sidebar count, slate pill, filter, select). SW now `bitacora-v9`.
- **Shipped, on branch `feat/roulette` (stacked on `feat/status-paused`, NOT merged):** **FEAT-06** —
  **Backlog Roulette** (the now-playing spotlight half was already shipped). Principle: *"spin the room
  you're standing in"* — the pool IS the current filtered Shelf (`roulettePool()` = `getFilteredItems()`,
  narrowed to the live backlog `queued/active/paused` only when `isViewDefault()`, never done/dropped).
  So filtering to In-Progress = "what do I continue?", to a `june` tag = "what to watch in June" (months
  are just tags — no planner built), to Queued = "what's next".
  **REDESIGNED per Leandro (the inline 'Up Next' card felt disruptive & meek):** trigger is now a
  **filter-bar launcher** `#roul-launch` (`❉ Spin · N`) sitting beside Filter-by-tag — it **wears the
  live pool count** (`renderRouletteBtn()` in the `renderItems` dispatcher), ticks as you filter, hides
  when pool<2 or in Observatory. Now-Playing reclaimed full width (the `#live-deck` wrapper is gone).
  The act is a **full-screen Cabaret** — a `<dialog id="roul-modal">` (native focus-trap + `::backdrop`
  wine vignette/blur) with a gold spotlight cone and **chasing/pulsing bulb marquees** (`buildBulbs()`).
  **SIX acts deal at random each spin** (`ROUL_ACTS = [actMarquee, actTablero, actCroupier,
  actSearchlight, actCifrado, actTelon]`, `rnd(ROUL_ACTS)` in `openRoulette`) — all riffle to the SAME
  lit landing (`reelLand`): **Marquee** (vertical slot-reel → lit band), **Tablero** (split-flap board,
  per-cell `flapClack`), **Croupier** (3D card-deal, `c3shuffle` then the chosen `.c3-inner` flips),
  **Searchlight** (a spotlight hops the dim cast, quadratic decel, rests on the winner), **Cifrado**
  (glyph-scramble resolves left→right), **Telón** (velvet curtain parts). `prefers-reduced-motion` →
  `actInstant` (skips the performance). Timer bookkeeping (`roulWait`/`roulLoop`/`roulClearTimers`) +
  a `reelLand` `!stage.open` guard so a mid-act dismiss can't strand or double-fire; transition acts
  (marquee/croupier/telón) have a **backstop `roulWait`** in case `transitionend` is missed (was: Telón
  stranded because `transform` won't transition from `none` — fixed with an explicit base `translateX(0)`
  + backstop). On land: winner glows gold, result fades in with `medium · year · creator · status`, up to
  3 **mood pills**, **adaptive CTA** — queued→**Start it** (flips event→active via `latestEvent`+
  `projectItem`+`save`), active/paused→**Continue** (now **goes home**: `resetView()`+shelf+scroll-top,
  where the item sits in Now-Playing — was `openEntryModal`). *Spin again* re-rolls; Esc/backdrop/dismiss
  close (wired first in the Esc cascade so it doesn't also reset the view). NO ⌘K command (per Leandro).
  Verified in-browser (launcher + live count, all six acts render+land, random dispatch hits all 6,
  Telón fix, both CTAs, Continue→home, Start-it persists, Esc closes w/o view-reset, <2 & Observatory
  hide). SW now `bitacora-v12`.
- **Enrich sweep — ✅ DONE / moot (verified 2026-06-28).** The real 46-item library (deployed origin
  `leandrogn10-ctrl.github.io/bitacora`) is already 100% enriched: **0** items missing `year`/`creator`,
  no blanks. `enrichLibrary()` filters to the missing-set, which is empty → no-op. It filled
  incrementally via `autoEnrich` on each log. NOTE: synced devices start keyless (`cleanStateForSync`
  strips the API key), so re-paste the key in Settings if you want `autoEnrich` on *new* logs there.
- **Backlog = source of truth:** `~/Downloads/leandro-os/prototype/BITACORA-AUDIT.md` (§0 status banner,
  §2 features).
- **Shipped (not yet committed): FEAT-16** — **medium-specific genre tags**, AI-assigned like
  FEAT-05's Mood/Pace (one more field in `fetchMeta`'s JSON contract, filled on log/enrich,
  reviewable via ✦ fill), built around a **two-tier taxonomy**: `GENRE_TAXONOMY` (film/TV/books,
  12 umbrellas → 58 leaves), `MUSIC_TAXONOMY` (12 → 44), `GAME_TAXONOMY` (17 → 37) — objects shaped
  `{ umbrella: [specific subgenres] }`. The model always prefers the most specific leaf; the bare
  umbrella name is itself a valid, directly-assignable tag, used only when none of its leaves fit
  but the umbrella clearly does — so an item never ends up with zero genre signal, and nothing
  outside the closed taxonomy can ever become a tag (enforced in `parseMeta`'s filter, not just by
  prompt instruction). Umbrella count is small and hand-curated (Observatory rollup bars stay
  clean); leaf count is the axis meant to grow. `genreTaxonomyFor(collectionId)` picks by `kindFor`
  (watch/read → Genre, listen → Music, play → Game, `log` kind → none). `taxonomyVocab`/
  `taxonomyPromptStr`/`taxonomyParentMap` derive the flat vocab, the grouped prompt listing, and the
  leaf→umbrella map from each taxonomy object — `GENRE_PARENT` merges all three (safe: no leaf name
  repeats across taxonomies, verified programmatically), `GENRE_SUBSUMED_PAIRS` and
  `GENRE_UMBRELLA_NAMES` are both derived from it (no more hand-maintained pair list).
  No tag string repeats across Genre/Music/Game/Mood/Pace — `tagAssignments` is a single global map
  keyed by tag text, so a shared string (the original "adventure"/"horror" collision between Genre
  and Game) would render with whichever group seeded first, regardless of the item's actual medium.
  `migrate()`: group creation (`ensureTagGroup`) is one-time per group (`genreSeeded` flag, so a
  group the user deletes stays deleted), but vocab→group assignment now runs unconditionally every
  load (only fills blanks, only into a group that still exists) — new leaves added to a taxonomy
  later just get colored on next load, no more one-off `...V2Seeded`-style flags needed each time
  the vocab grows. One-time `genreDedupDone` pass drops a bare umbrella tag wherever its own leaf
  is also present on the same item (backfills anything a prior enrich run double-tagged before this
  taxonomy existed). Game was briefly seeded `ochre` (near-identical to Music's `gold`) —
  self-fixes on load.
  **Curation loop (the actual point of "umbrella-as-fallback" over "leave it blank")**: when
  `applyMeta` lands a tag that's a bare umbrella name, `logGenreGap(it, umbrella)` pushes
  `{itemId, title, umbrella, medium, at}` onto `state.genreGaps` (deduped per item+umbrella, capped
  at 200) — reviewed in Settings under "Genre gaps (N)", each row with **open** (closes Settings,
  opens that entry so you can hand-pick a leaf) and **dismiss** (this one genuinely has no better
  fit). Never auto-creates a tag — promoting a recurring gap into a real leaf is a deliberate code
  edit to the taxonomy, done by us, not the model. Separately, `it.genreAbstained` is set when
  `fetchMeta` returned a real (non-null) response but genre came back `[]` — distinguishes "tried,
  found nothing" from "never asked yet" so `needsMeta` stops re-querying that item forever on every
  future "Enrich library" pass (mood/pace/year/creator have the same theoretical gap, not fixed here
  — out of scope, genre's taxonomy is narrow enough per medium that empty comes up far more often).
  Verified in-browser end to end: taxonomy extracted from the live file and collision-checked
  (`node`, zero collisions across 195 strings) and coverage-checked (every pre-FEAT-16 vocab word
  still valid, either as a leaf or promoted to an umbrella name); seeding survives an
  already-migrated library; a new leaf ("time travel") colors correctly on next load without a new
  flag; a Genre-umbrella leaf-pair not in the old hand-written list ("documentary"+"true crime")
  dedupes correctly, proving the auto-derivation; Game-medium umbrella ("shooter") renders `ash`,
  Genre-medium umbrella ("action") renders `terracotta`; Settings gap list renders a seeded gap and
  dismiss removes it and shows the empty state. Not yet tested against the live Claude API (no key
  in this session) — the JSON contract shape mirrors mood's proven pattern. SW `bitacora-v16`.
  **Observatory "By genre" rollup + drill-down** (same session): three panels —
  **By genre** (watch/read, `GENRE_TAXONOMY`), **By genre (music)**, **By genre (games)** — each
  conditionally rendered only when the library has items of that medium-group at all (skipped
  entirely otherwise; shows the `run ✦ enrich` hint if items exist but none are tagged yet, same as
  By pace). Rolls up every genre tag on a title to its umbrella via `GENRE_PARENT` regardless of
  whether it landed on a specific leaf or the bare umbrella fallback, ranks descending, top 8 (same
  cap as Top tags/creators/actors). New `view.genreUmbrella` filter dimension (single-value, alongside
  creator/actor/decade — NOT part of the `view.tags` AND-array, since a drill-down needs OR across an
  umbrella's leaves): `hasGenreUmbrella(it, umbrella)` matches the bare umbrella tag OR any leaf under
  it. Wired through `isViewDefault`/`resetView`/`anyFilterActive`/`filterChipsHtml` (chip: `◈ sci-fi`
  with its own clear button) and both `getFilteredItems` and `getDiaryEvents`, plus the new
  `[data-genre-umbrella]` click case in the Observatory delegated handler (same click-to-filter
  pattern as `data-decade`/`data-creator`/`data-actor`) and the cmdk `+` combo-filter reset line.
  Verified in-browser: hit the exact documented stale-SW gotcha mid-session (had to unregister +
  clear caches to see the new code — a good reminder that gotcha is real, not just a warning);
  confirmed `kindFor` matches on the collection ID string itself, not `.name` — real IDs always
  carry the keyword (defaults `films`/`tv`/`games`/`books`; custom collections slugify the name into
  the ID, e.g. "Albums" → `albums-xk2`) so this isn't a gap, just something to remember when hand-
  seeding test data with placeholder IDs. All three panels render with correct rollups; clicking a
  bar filters the Shelf to exactly the matching item(s) (leaf-tag member of the umbrella, not just
  the bare umbrella string); the same filter carries into Diary mode; clear button restores the full
  list. `preview_click` intermittently missed freshly-re-rendered bar elements in this session —
  dispatching a real `click` MouseEvent via `preview_eval` worked every time; not a code bug.
  **`it.paceAbstained`** added, mirroring `genreAbstained` exactly: `pace: null` is a legitimate
  answer (explicitly "not applicable, e.g. an album" per the prompt spec, not just "unsure"), so
  without tracking that a real attempt happened, `needsMeta` re-asked forever on every future
  "Enrich library" pass — confirmed against the real exported library that this was actively
  happening on 15 albums. Verified with a standalone Node harness (sliced the real functions out of
  `index.html`, no page-global-access workaround needed since it's pure data logic): `needsMeta`
  true → `applyMeta` with `pace: null` → `paceAbstained` set, `needsMeta` false, second `applyMeta`
  call is a no-op. **Prompt caching evaluated and skipped**: `fetchMeta`'s system prompt (identical
  across every call for a given medium — real savings during a library-wide enrich run) comes out
  to ~650-730 estimated tokens per medium (chars/4 heuristic), under Anthropic's 1024-token minimum
  for Sonnet cache blocks — wiring `cache_control` on it wouldn't actually cache anything at the
  current prompt size, so skipped rather than ship dead complexity.
  **Real-library-audit fixes, all shipped**: (1) one-time `genreColorFixDone` forces the 5
  canonical groups (Mood/Pace/Genre/Music/Game) to their intended colors regardless of a
  pre-existing group the user made before this session's auto-seeding existed (which
  `ensureTagGroup`'s find-by-name correctly never touched, but that meant a legacy color could
  collide) — then bumps any OTHER group still colliding with one of those 5 colors to the first
  free `TAG_COLORS` slot. Caught a real bug in this fix while testing: the bump step originally did
  `usedColors.delete(oldColor)` before reassigning, which let a SECOND colliding group get
  reassigned back to a color a canonical group still legitimately owns — fixed by only ever adding
  to the used-set, never deleting. (2) force-reassigns (not fill-blanks) every taxonomy word to
  its correct group — fixed `adventure` rendering Genre/sage instead of Game/ash on real game
  entries, and 7 Music words (`bedroom pop`, `dream pop`, `indie pop`, `indie rock`, `r&b`, `pop`,
  `experimental`) stuck on Genre or a legacy "Music Genre" group. (3) the `genreDedupDone` one-time
  flag was missing two live double-tags (`r&b`+`soul` on El Madrileño, `simulation`+`life
  simulation` on Spiritfarer) because both were created by enrich activity *after* the flag had
  already fired once — dedup now runs unconditionally every load (idempotent, costs nothing when
  there's nothing to fix). (4) added `poetry` (leafless) to `GENRE_TAXONOMY` and `latin`
  (reggaeton/flamenco/bolero/salsa/bachata/latin pop) to `MUSIC_TAXONOMY` — collision-checked
  (0 across 203 strings). Verified all four together in-browser against a reconstruction of the
  exact real-library state (pre-existing legacy groups/colors, the two live double-tags): dedup
  now ALSO catches `latin`+`flamenco` on El Madrileño as a bonus, since `flamenco` became one of
  `latin`'s own leaves — nothing in the fix was written for that case specifically, it just fell
  out of the general derivation. Final state has all 7 groups (5 canonical + 2 legacy) on distinct
  colors, confirmed programmatically.
  **Follow-up round, same session**: the live "Filter by tag" dropdown on the real deployed app
  (confirming fix (1)+(2) above had already reached production — `adventure`/`pop`/`r&b` were
  correctly under Game/Music) surfaced 3 more legacy custom tags stuck under Genre: `art pop`,
  `indie folk`, `lo-fi` — pre-taxonomy free-form tags, not caught by the earlier fix since they
  weren't in the taxonomy yet. Added as leaves: `art pop` under Music's `pop`, `indie folk` under
  `folk`, `lo-fi` under `rock` (flagged as a genuine judgment call — lo-fi is more a production
  aesthetic than a genre, cuts across pop/hip-hop/rock, but its one live use is on an indie-rock
  album). This exposed a real mechanism bug: fix (2) above (`genreAssignmentFixDone`) was a
  single one-time boolean, already spent on the real library — adding new taxonomy words after
  that point meant they'd NEVER get force-corrected, the same class of problem the fill-blanks
  loop already solved once. Fixed properly this time instead of bolting on another one-off flag:
  replaced the boolean with `settings.genreForceFixedWords`, a list of words already force-fixed.
  Any taxonomy word — present now or added at any future point — gets force-corrected exactly
  once, automatically, the first time `migrate()` sees it; no new flag to remember to add when the
  taxonomy grows again (and it will). `classic` (on *Is This It*) deliberately NOT touched —
  it's not taxonomy vocab, almost certainly shorthand for the already-existing `classic rock` leaf;
  correct fix is a manual tag-manager merge, not new taxonomy, left for the user to do. Verified
  in-browser against a reconstruction of the real post-fix-(1)/(2) state (stale
  `genreAssignmentFixDone: true`, no `genreForceFixedWords` yet, the 3 new words still on Genre):
  all 3 correctly land on Music after one load, `classic` correctly untouched.
- **Open:** merge `feat/roulette` (brings FEAT-04 + FEAT-06, stacked) → `main` + push ·
  FEAT-07 heatmap · FEAT-08 auto-ingestion · FEAT-10 Releer · FEAT-11 in-app graph · FEAT-12 Wrapped ·
  "Ask the Observatory".
