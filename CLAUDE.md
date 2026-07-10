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
- **Shipped (not yet committed): FEAT-16** — **medium-specific genre tags**, same AI-assigned-tag
  mechanism as FEAT-05's Mood/Pace (one more field in `fetchMeta`'s JSON contract, filled on log/enrich,
  reviewable via ✦ fill). Three new seeded tag groups (`genreSeeded` flag, independent of
  `taxonomySeeded` so existing libraries pick them up on next load): **Genre** `terracotta` (film/TV/book
  shared vocab: drama/comedy/thriller/horror/sci-fi/fantasy/romance/mystery/action/adventure/
  documentary/animation/satire/war/crime/coming-of-age), **Music** `gold` (albums: indie pop/folk/rock/
  hip-hop/electronic/jazz/classical/ambient/metal/pop/punk/soul/country/r&b/experimental), **Game**
  `ochre` (FPS/RPG/platformer/puzzle/strategy/simulation/adventure/roguelike/fighting/sports/racing/
  horror/sandbox/visual novel). `genreVocabFor(collectionId)` picks the applicable list by `kindFor`
  (watch/read → Genre, listen → Music, play → Game; `log` kind gets no genre vocab, no requirement).
  Up to 3 genre tags per item, matched case-insensitively then canonicalized to vocab casing (games'
  vocab is upper-case: FPS/RPG). `needsMeta` only requires genre when `genreVocabFor` is non-empty.
  Verified in-browser (tag groups seed with correct colors/vocab, chip renders `tag-color-terracotta`
  on a film tagged "drama"); not yet tested against the live Claude API (no key in this session) — the
  JSON contract change mirrors mood's proven shape exactly. SW `bitacora-v16`.
- **Open:** merge `feat/roulette` (brings FEAT-04 + FEAT-06, stacked) → `main` + push ·
  FEAT-07 heatmap · FEAT-08 auto-ingestion · FEAT-10 Releer · FEAT-11 in-app graph · FEAT-12 Wrapped ·
  "Ask the Observatory".
