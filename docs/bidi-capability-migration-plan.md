# WebDriver BiDi Capability Migration Plan

Status: proposal
Scope: Ruby bindings first, capability architecture cross-binding, plus upstream (W3C / chromium-bidi) recommendations.

## 0. Why this exists

Classic WebDriver capabilities are enforced by the **remote end**. WebDriver BiDi
commands do not consult them at all. The two facts that drive everything below:

1. **Storage** is decided at session creation. A session created over classic
   HTTP stores all standard capabilities — including when `webSocketUrl: true`
   makes it a hybrid session. A session created with `session.new` sets
   `flags = {"bidi"}` and never stores `pageLoadStrategy`, `timeouts`, or
   `strictFileInteractability`.
2. **Enforcement** is decided per command, by which protocol carries it. Classic
   remote-end steps consult session state. BiDi commands never do.

Measured on Chromium 141.0.7390.37 / ChromeDriver 141, in a *single hybrid
session* with `timeouts: {implicit: 3000, pageLoad: 1000, script: 1000}`:

| Command | Elapsed | Result |
| --- | --- | --- |
| classic Find Element | 3.05s | `NoSuchElementError` — implicit wait honored |
| `browsingContext.locateNodes` | 0.11s | empty result — implicit wait ignored |
| classic Navigate To | 1.02s | `TimeoutError` — pageLoad honored |
| `browsingContext.navigate` | 3.11s | success — pageLoad ignored |
| classic Execute Async Script | 1.01s | `ScriptTimeoutError` — script honored |
| `script.evaluate` | 6.00s+ | still running — script ignored |

Therefore: **any command routed over BiDi needs the client to enforce the
capability itself.** The client must hold the values regardless of session type,
because BiDi has no equivalent of `GET /timeouts` to read them back.

## 1. Workstream A — repair Ruby's navigation path

`Remote::BiDiBridge` overrides `get`, `go_back`, `go_forward`, and `refresh`
(selected at `common/driver.rb:323` whenever `webSocketUrl` is returned). Those
four commands are already migrated; the capability plumbing behind them is not
complete.

### Defects

**A1 — `traverse_history` sends no readiness wait.**
`bidi/browsing_context.rb:58-61` sends `browsingContext.traverseHistory` with only
`context` and `delta`. The BiDi command has no `wait` parameter at all, so
`navigate.back` / `navigate.forward` cannot honor `pageLoadStrategy`. `navigate`
(`:49`) and `reload` (`:70`) do pass `wait`. Net effect: the strategy is honored
on two of four navigation entry points in the same session.

**A2 — readiness silently downgrades to `none` when the capability is absent.**
`bidi/browsing_context.rb:38-39` does
`@readiness = READINESS_STATE[bridge.capabilities[:page_load_strategy]]`.
A missing or unrecognized value yields `nil`, `BiDi#send_cmd` calls `.compact`,
and `wait` is dropped. Per `browsingContext.navigate`'s remote end steps the wait
condition then defaults to `"committed"` — and `"none"` maps to `"committed"` too.
So an absent capability silently produces `none` semantics where the session
default is `normal`.

**A3 — no page load timeout on any BiDi navigation.**
Nothing bounds `browsingContext.navigate` / `.reload` / `.traverseHistory`. The
measurement above shows a 1s `pageLoad` timeout being ignored for 3.11s.

**A4 — readiness is cached at construction.**
`@readiness` is resolved once in `initialize`. Correct today only because
`pageLoadStrategy` is create-only. It establishes the wrong pattern for
`timeouts`, which *are* mutable at runtime.

**A5 — `@bridge.window_handle` round-trips on every call.**
Each BiDi navigation method calls back into a classic endpoint to resolve the
context (existing `TODO` at `bidi/browsing_context.rb:34`). Latency, plus it means
the "BiDi path" is not actually BiDi-only.

### Fixes

1. **Add `BiDi::NavigationWaiter`.** Subscribe to `browsingContext.navigationStarted`,
   `domContentLoaded`, `load`, `navigationFailed`, and `navigationAborted`. Expose
   `wait_for(context, readiness, timeout:)` that resolves at the requested
   readiness level and raises `Error::TimeoutError` on expiry.
2. **Use it for `traverse_history`.** Subscribe before sending the command, wait
   after. This is the only way to honor `pageLoadStrategy` for back/forward until
   the spec grows a `wait` parameter (see Workstream B4).
3. **Default readiness to `'complete'`** when the capability is missing, rather
   than omitting `wait`.
4. **Bound `navigate` and `reload`** with the `pageLoad` timeout, raising
   `Error::TimeoutError` to match classic.
5. **Resolve readiness and timeouts at call time** from the capability store
   (Workstream C), not at construction.
6. **Cache the current context** on the bridge to remove the per-call
   `window_handle` round-trip.

### Not yet broken, but next

`element_click` still goes over the classic endpoint, so click-induced navigation
is currently fine. The moment `actions` / `element_click` migrate to
`input.performActions`, there is no readiness wait and no page load timeout on
that path either. `NavigationWaiter` should land before that migration, not after.

### Tests

- Unit: `NavigationWaiter` against a stubbed event stream.
- Integration: extend `rb/spec/integration/selenium/webdriver/bidi/browsing_context_spec.rb`
  and `navigation_spec.rb` with a deliberately slow fixture, asserting that
  `navigate.to`, `.back`, `.forward`, and `.refresh` all block per strategy and
  all raise `TimeoutError` per `pageLoad`, with and without `web_socket_url`.
- Regression guard: a spec asserting parity between the classic and BiDi bridges
  for the same capability set.

## 2. Workstream B — prompts

### B1. Ship the notify shim

The remote end returns `unhandledPromptBehavior: "dismiss and notify"` in the
capabilities and then does not implement the notify half once BiDi is active.
This is not gated on sending any BiDi command — merely enabling BiDi is enough,
because the handling happens in the browser at prompt-display time.

Recoverable client-side. The spec emits `browsingContext.userPromptOpened`
*before* applying the handler, and the payload carries what is needed:

```
echoed unhandledPromptBehavior: "dismiss and notify"
  click #a -> event: {"handler"=>"dismiss", "message"=>"from alert",   "type"=>"alert"}
  next command       -> no error from remote end
  click #c -> event: {"handler"=>"dismiss", "message"=>"from confirm", "type"=>"confirm"}
  next command       -> no error from remote end
```

Implementation:

1. Subscribe to `browsingContext.userPromptOpened` when the BiDi session opens.
2. Resolve whether `notify` applies for the prompt's `type`, from the negotiated
   `unhandledPromptBehavior` (default `"dismiss and notify"`), following classic's
   *get the prompt handler* fallback order: exact type, `default`, `beforeUnload`
   special case, `fallbackDefault`, then `dismiss`+notify.
3. Record a pending notification keyed by context, carrying the event's `message`.
4. In `BiDiBridge`, before dispatching any command, consume a pending
   notification and raise `Error::UnexpectedAlertOpenError` with that text.

Edge cases to cover in specs:
- `ignore` — the prompt genuinely stays open and the remote end already raises;
  do not double-raise.
- explicit `accept` / `dismiss` without notify — must not raise.
- `beforeUnload` — classic falls back to `accept` with notify false.
- `file` — BiDi-only prompt type, no classic analogue.
- prompts opened in a context other than the current one.

### B2. Read the upstream threads (blocked — do this first)

Not yet done, and it gates B3. The relevant threads could not be read from this
environment: GitHub issue pages do not render for the fetcher, `gh` is not
installed, and attaching `GoogleChromeLabs/chromium-bidi` for API access is
blocked by a cross-tier restriction. Needs either a session started with that
repo as its initial source, or the threads pasted in.

To review:
- `GoogleChromeLabs/chromium-bidi` #3873 *Incorrect UnhandledPromptBehavior* — closed.
- `GoogleChromeLabs/chromium-bidi` #2556 *Alerts are automatically closing* — filed by
  Christian Bromann (WebdriverIO) Sept 2024, closed. Independent confirmation that
  this is a cross-client problem, not Selenium-specific.
- `GoogleChromeLabs/chromium-bidi` PR #2351 — referenced as the origin of the behavior.
- The second closed issue (identifier not captured here).
- `SeleniumHQ/selenium` #14450 — the user-facing symptom, still open.

For each: what was the closing rationale, and does it argue spec-conformance
(in which case the fix belongs at W3C) or intended-behavior (in which case it is
worth reopening with the capability-echo evidence).

### B3. Upstream recommendations

Draft after B2. Current position, subject to what the threads say:

**`w3c/webdriver-bidi` — the substantive one.** The notify bit is discarded at a
single step. *Get navigable's user prompt handler* ends:

```
1. Let |handler configuration| be [=get the prompt handler=] with |type|.
1. Return |handler configuration|'s [=prompt handler configuration/handler=].
```

`get the prompt handler` returns a full prompt handler configuration — `handler`
**and** `notify`. The BiDi wrapper returns only `.handler`. Two candidate fixes:

- *Carry notify through.* Keep the full configuration, set a session-level
  pending-notification flag when `notify` is true, and amend classic's *handle any
  user prompts* step 1 to return `unexpected alert open` when the flag is set even
  though no dialog is currently blocking. Hybrid sessions then behave like classic
  ones; pure-BiDi sessions are unaffected.
- *Split the capability name.* `unhandledPromptBehavior` describes what to do with
  a prompt still open when a command arrives — that is what makes the name accurate
  and what makes `notify` coherent. BiDi's handler fires at display time
  unconditionally, so nothing is ever "unhandled"; it is an automatic-prompt
  policy. Same key, two different models, is the backwards-compatibility break.
  Give the eager model its own key and leave `unhandledPromptBehavior` with its
  classic meaning.

Supporting argument for either: the spec emits `userPromptOpened` *before*
applying the handler, so deferring the handling costs BiDi consumers nothing —
they still get the event. Eager handling is not load-bearing for observability.

**`w3c/webdriver`** — state explicitly what a hybrid (`http` + `bidi`) session owes
classic prompt semantics. The current text leaves it to inference.

**WPT** — assert that the returned `unhandledPromptBehavior` matches observed
behavior, run with and without `webSocketUrl`. The strongest framing of the bug is
not "BiDi picked different defaults" but "the session advertises a capability value
it does not implement."

**`chromium-bidi`** — likely no change until the spec resolves. The narrow ask that
stands on its own: stop echoing `"dismiss and notify"` while implementing only the
dismiss half.

### B4. Adjacent spec gaps worth filing at the same time

- `browsingContext.traverseHistory` has no `wait` parameter — forces every client
  to reimplement readiness waiting for back/forward.
- `script.evaluate` / `script.callFunction` have no timeout parameter (open `TODO`
  in the spec text).
- `browsingContext.navigate` has no timeout parameter.
- `input.setFiles` performs no interactability check, so `strictFileInteractability`
  has no BiDi expression.

Each of these is a "must be managed locally" that need not be, if the spec grows
the parameter.

## 3. Workstream C — where capabilities should live

### Facts the design has to accommodate

- **Mutable at runtime:** `timeouts` only, via Set Timeouts.
- **Create-only:** `pageLoadStrategy`, `strictFileInteractability`,
  `unhandledPromptBehavior`, `acceptInsecureCerts`, `proxy`, and the
  informational ones (`browserName`, `browserVersion`, `platformName`,
  `userAgent`, `setWindowRect`).
- **New dimension from BiDi:** `browser.createUserContext` accepts
  `acceptInsecureCerts`, `proxy`, and `unhandledPromptBehavior` overrides, and
  `get navigable's user prompt handler` resolves through the user context first.
  Capability resolution stops being a single session-level lookup the moment user
  contexts are exposed.
- **No read-back over BiDi.** There is no BiDi equivalent of `GET /timeouts`. In a
  BiDi-only session the client is the only possible source of truth.
- Today Ruby reads capabilities ad hoc: `bridge.capabilities[:page_load_strategy]`
  cached at construction (`bidi/browsing_context.rb:38`), while `bridge.timeouts`
  (`remote/bridge.rb:126-132`) round-trips to the classic endpoint on every access.

### Option 1 — status quo, ad hoc reads at point of use

**Pros.** No new API. No migration. Nothing to keep in sync.

**Cons.** No single source of truth. Caching bugs like A4 recur per call site.
`bridge.timeouts` is a network round-trip that does not exist in a BiDi-only
session. Every newly migrated command re-invents the lookup. Per-user-context
overrides have nowhere to live. This is how A1–A4 happened.

### Option 2 — client-side store for the locally-enforced subset only

Hold `timeouts`, `pageLoadStrategy`, `strictFileInteractability`, and
`unhandledPromptBehavior`; leave everything else on `driver.capabilities`.

**Pros.** Small and targeted. The membership rule is meaningful and teachable:
"these are the ones the client enforces." Low regression risk for the
informational capabilities. Ships quickly.

**Cons.** Split brain — two places to look, and contributors must know which.
The boundary is not stable: `acceptInsecureCerts` and `proxy` join the set as soon
as user contexts land, and each addition is a breaking-ish reorganization.

### Option 3 — full client-side capability store

One authoritative object populated from the New Session / `session.new` response,
mutated by Set Timeouts, consulted by every command path.

**Pros.** Single source of truth. Identical shape for classic, hybrid, and
BiDi-only sessions, so the migration does not change the mental model. Natural
home for per-user-context overrides later. `get_timeouts` becomes free. Testable
without a browser.

**Cons.** Can diverge from remote-end state — an intermediary node or Grid may
rewrite capabilities, and out-of-band changes are invisible. Needs a deliberate
answer for what `driver.capabilities` returns. More code than Option 2 for the
same near-term benefit.

### Option 4 — a capability domain with per-context layering

Option 3, structured as a resolver that layers session → user context → navigable,
mirroring the spec's own resolution order and injected into each BiDi module.

**Pros.** Matches how the spec actually resolves handlers. Scales to
`browser.createUserContext` without rework. One place implements "resolve X for
context Y." Dependency-injectable, so unit-testable.

**Cons.** Heaviest option, and it builds the user-context abstraction before user
contexts are exposed. Cross-binding consistency becomes a coordination cost — this
is the option most likely to drift between languages if not specified up front.

### Option 5 — push it upstream instead

Add the missing parameters to BiDi (`wait` on `traverseHistory`, timeouts on
`navigate` and `script.*`) so the remote end enforces and clients hold nothing.

**Pros.** Correct long-term. Benefits every client. Deletes local emulation rather
than centralizing it.

**Cons.** Slow — spec plus two engines. Does nothing for shipping users. And it
cannot cover everything: implicit wait is a client concern by design, and
`unhandledPromptBehavior` needs a semantic decision, not a parameter.

### Recommendation

**Option 3 now, shaped so Option 4 is a later refactor rather than a rewrite, with
Option 5 pursued in parallel for the genuinely-missing parameters.**

Concretely: build a mutable, authoritative `SessionCapabilities` object keyed by
session; give it a `resolve(name, context: nil)` signature from day one even though
the `context:` argument is ignored until user contexts land; back
`Timeouts#implicit_wait=` and friends with it rather than with a round-trip; and
have `NavigationWaiter` and the prompt shim read from it. Keep `driver.capabilities`
returning the negotiated remote-end response so nothing user-facing changes.

Option 2 is the reasonable fallback if the team wants a smaller first step — but
the boundary it draws will move within a release or two, so the saving is
temporary.

## 4. Sequencing

1. **B1 — prompt shim.** Broken in shipping releases, independent of every other
   change, and it is what users are hitting (`SeleniumHQ/selenium` #14450).
2. **C — capability store.** Needed by A before A can be done correctly.
3. **A — navigation repair.** The half-migrated state is worse than either
   endpoint; `NavigationWaiter` must exist before actions migrate.
4. **B2/B3 — upstream review and filings.** Parallel, gated on obtaining the threads.
5. **B4 — adjacent spec gaps.** File alongside B3 while the context is loaded.

## 5. Risks

- **Local emulation drifts from remote-end semantics.** Mitigate with parity specs
  that run the same assertions against both bridges.
- **Fixing notify changes behavior for anyone who adapted to its absence.** It
  restores documented behavior and matches the advertised capability, but it
  belongs in release notes.
- **Cross-binding divergence.** The capability store shape should be agreed before
  more than one language implements it.
- **Upstream may reject the prompt argument again.** B1 does not depend on that
  outcome; the shim stands either way.

## 6. Open questions

- Which was the second closed chromium-bidi issue, and what were the closing
  rationales on both?
- Does Firefox/geckodriver show the same notify loss? Not testable in the
  environment where this was measured — Chrome only.
- Should `driver.capabilities` ever reflect locally-managed values, or always the
  negotiated response?
- Does requesting `webSocketUrl: true` but never connecting the socket also lose
  notify? Ruby connects eagerly at session creation, so this was not isolated.
