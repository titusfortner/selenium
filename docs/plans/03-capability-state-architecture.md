# Plan 03 — Where capability state should live

Status: proposal — decision required
Owner: unassigned
Blocks: Plan 01 items 5 and 6.

## The question

BiDi commands never consult session capabilities, so every command Selenium
migrates to BiDi must enforce the relevant capabilities itself. That requires the
client to hold them. Today Ruby reads them ad hoc. Where should they live, and
should the store cover only the locally-enforced capabilities or all of them?

## Facts the design must accommodate

**Mutable at runtime:** `timeouts` only, via Set Timeouts.

**Create-only:** `pageLoadStrategy`, `strictFileInteractability`,
`unhandledPromptBehavior`, `acceptInsecureCerts`, `proxy`, and the informational
capabilities (`browserName`, `browserVersion`, `platformName`, `userAgent`,
`setWindowRect`).

**A second axis, from BiDi:** `browser.createUserContext` accepts
`acceptInsecureCerts`, `proxy`, and `unhandledPromptBehavior` overrides, and
*get navigable's user prompt handler* resolves through the user context *before*
falling back to the session. Capability lookup stops being a single session-level
read the moment user contexts are exposed.

**No read-back over BiDi.** There is no BiDi equivalent of `GET /timeouts`. In a
BiDi-only session (`session.new`, `flags = {"bidi"}`) `pageLoadStrategy`,
`timeouts`, and `strictFileInteractability` are never stored remotely at all, so
the client is the only possible source of truth.

**Current Ruby state.** `bidi/browsing_context.rb:38` caches
`bridge.capabilities[:page_load_strategy]` at construction, while
`remote/bridge.rb:126-132` round-trips `timeouts` to the classic endpoint on every
access — an endpoint that does not exist in a BiDi-only session.

## Which capabilities need local enforcement, and for which commands

| Capability | Commands affected once migrated | Local mechanism |
| --- | --- | --- |
| `pageLoadStrategy` | `get`, `back`, `forward`, `refresh`, click-induced navigation | map to `wait`; event-based wait where no `wait` exists |
| `timeouts.pageLoad` | same | local timer |
| `timeouts.implicit` | all finders | poll loop; synthesize `NoSuchElementError` |
| `timeouts.script` | `execute_script`, `execute_async_script` | local timer |
| `strictFileInteractability` | `element_send_keys` on file inputs | interactability check before `input.setFiles` |
| `unhandledPromptBehavior` | **every command** — see Plan 02 | event subscription + pending flag |
| `acceptInsecureCerts`, `proxy` | none today; per-user-context once exposed | none / resolution layering |
| `setWindowRect` | window commands | guard only |

## Options

### Option 1 — status quo, ad hoc reads at point of use

**Pros.** No new API. No migration. Nothing to keep in sync.

**Cons.** No single source of truth. Caching bugs recur per call site — this is how
Plan 01's A2 and A4 happened. `bridge.timeouts` is a network round-trip that does
not exist in a BiDi-only session. Every newly migrated command re-invents the
lookup. Per-user-context overrides have nowhere to live.

### Option 2 — client-side store for the locally-enforced subset only

Hold `timeouts`, `pageLoadStrategy`, `strictFileInteractability`, and
`unhandledPromptBehavior`. Leave everything else on `driver.capabilities`.

**Pros.** Small and targeted. The membership rule is teachable: "these are the ones
the client enforces." Low regression risk for informational capabilities. Ships
quickly.

**Cons.** Split brain — two places to look, and contributors must know which. The
boundary is not stable: `acceptInsecureCerts` and `proxy` join the set as soon as
user contexts land, and each addition is a reorganization.

### Option 3 — full client-side capability store

One authoritative object populated from the New Session / `session.new` response,
mutated by Set Timeouts, consulted by every command path.

**Pros.** Single source of truth. Identical shape for classic, hybrid, and
BiDi-only sessions, so migrating commands never changes the mental model. Natural
home for per-user-context overrides later. `get_timeouts` becomes free. Testable
without a browser.

**Cons.** Can diverge from remote-end state — an intermediary node or Grid may
rewrite capabilities, and out-of-band changes are invisible. Needs a deliberate
answer for what `driver.capabilities` returns. More code than Option 2 for the same
near-term benefit.

### Option 4 — a capability domain with per-context layering

Option 3 structured as a resolver layering session → user context → navigable,
mirroring the spec's own resolution order, injected into each BiDi module.

**Pros.** Matches how the spec actually resolves handlers. Scales to
`browser.createUserContext` without rework. One place implements "resolve X for
context Y." Dependency-injectable and unit-testable.

**Cons.** Heaviest option, and it builds the user-context abstraction before user
contexts are exposed. Cross-binding consistency becomes a coordination cost — the
option most likely to drift between languages if not specified up front.

### Option 5 — push it upstream instead

Add the missing parameters to BiDi (`wait` on `traverseHistory`, timeouts on
`navigate` and `script.*`) so the remote end enforces and clients hold nothing.

**Pros.** Correct long-term. Benefits every client. Deletes local emulation rather
than centralizing it.

**Cons.** Slow — spec plus two engines. Does nothing for shipping users. Cannot
cover everything: implicit wait is a client concern by design, and
`unhandledPromptBehavior` needs a semantic decision, not a parameter.

## Recommendation

**Option 3 now, shaped so Option 4 is a later refactor rather than a rewrite, with
Option 5 pursued in parallel for the genuinely-missing parameters.**

Concretely:

- Build a mutable, authoritative `SessionCapabilities` object keyed by session.
- Give it `resolve(name, context: nil)` from day one, ignoring `context:` until
  user contexts land. This is the cheap move that makes Option 4 additive.
- Back `Timeouts#implicit_wait=` and friends with it rather than a round-trip.
- Have `NavigationWaiter` (Plan 01) and the prompt shim (Plan 02) read from it.
- Keep `driver.capabilities` returning the negotiated remote-end response so
  nothing user-facing changes.

Option 2 is a defensible smaller first step, but the boundary it draws will move
within a release or two, so the saving is temporary.

## Decision needed

1. Option 2 or Option 3 as the first increment?
2. Should `driver.capabilities` ever reflect locally-managed values, or always the
   negotiated response?
3. Is the store shape agreed cross-binding before a second language implements it?

## Risks

- Divergence from remote-end state. Mitigate with parity specs asserting identical
  behavior across `Remote::Bridge` and `Remote::BiDiBridge`.
- Cross-binding drift if Ruby lands first and others copy loosely.
