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

## Status — 2026-06-28
- **Shipped & merged to `main`** (⚠️ **unpushed** — `main` is ahead of `origin/main`):
  FEAT-01 (palette + rating/tag/creator/decade filters + `?` cheatsheet + Esc/Tab reset),
  FEAT-02 (event model A/B/C + cosmic Diary "La Línea Sagrada"),
  FEAT-03 (Observatory + year/creator capture + Rewatch Lab).
- **Shipped, on branch (NOT merged):** FEAT-09 (`feat/tag-chips-merge`) — editor tag token-field +
  fuzzy typeahead + non-blocking `≈ canonical` reuse hint; Settings dupe-scan + multi-select merge; one
  `applyTagMerge()` behind rename/cluster-merge/multi-merge. Verified in-browser. SW bumped v4→v5.
- **Enrich sweep — ✅ DONE / moot (verified 2026-06-28).** The real 46-item library (deployed origin
  `leandrogn10-ctrl.github.io/bitacora`) is already 100% enriched: **0** items missing `year`/`creator`,
  no blanks. `enrichLibrary()` filters to the missing-set, which is empty → no-op. It filled
  incrementally via `autoEnrich` on each log. NOTE: synced devices start keyless (`cleanStateForSync`
  strips the API key), so re-paste the key in Settings if you want `autoEnrich` on *new* logs there.
- **Backlog = source of truth:** `~/Downloads/leandro-os/prototype/BITACORA-AUDIT.md` (§0 status banner,
  §2 features).
- **Open:** push `main`→origin (FEAT-09 branch + this) · FEAT-04 status vocab · FEAT-05 mood tags ·
  FEAT-06 roulette · FEAT-07 heatmap · FEAT-08 auto-ingestion · FEAT-10 Releer · FEAT-11 in-app graph ·
  FEAT-12 Wrapped · FEAT-14 AI-take voice · "Ask the Observatory".
