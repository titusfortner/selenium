# Plan 01 — Repair the Ruby bindings' BiDi navigation path

Status: proposal
Owner: unassigned
Depends on: Plan 03 (capability state) for items 5 and 6; can begin without it.

## Context

`Remote::BiDiBridge` is selected at `rb/lib/selenium/webdriver/common/driver.rb:323`
whenever the New Session response contains `webSocketUrl`. It overrides `get`,
`go_back`, `go_forward`, and `refresh` to use BiDi commands. Those four commands
are migrated; the capability plumbing behind them is not complete.

This matters because BiDi commands never consult session capabilities. Classic
remote-end steps do. Measured in a single hybrid session on Chromium 141 /
ChromeDriver 141 with `timeouts: {implicit: 3000, pageLoad: 1000, script: 1000}`:

| Command | Elapsed | Result |
| --- | --- | --- |
| classic Navigate To | 1.02s | `TimeoutError` — pageLoad honored |
| `browsingContext.navigate` | 3.11s | success — pageLoad ignored |

## Defects

### A1 — `traverse_history` sends no readiness wait

`rb/lib/selenium/webdriver/bidi/browsing_context.rb:58-61` sends
`browsingContext.traverseHistory` with only `context` and `delta`. The BiDi
command has no `wait` parameter at all, so `navigate.back` / `navigate.forward`
cannot honor `pageLoadStrategy`. `navigate` (`:49`) and `reload` (`:70`) do pass
`wait`.

Net effect: `pageLoadStrategy` is honored on two of four navigation entry points
in the same session.

### A2 — readiness silently downgrades to `none` when the capability is absent

`browsing_context.rb:38-39`:

```ruby
page_load_strategy = bridge.capabilities[:page_load_strategy]
@readiness = READINESS_STATE[page_load_strategy]
```

A missing or unrecognized value yields `nil`. `BiDi#send_cmd` calls `.compact`,
so `wait` is dropped from the payload. Per `browsingContext.navigate`'s remote end
steps the wait condition then defaults to `"committed"` — and an explicit
`"none"` maps to `"committed"` too. So an absent capability silently produces
`none` semantics where the session default is `normal`.

### A3 — no page load timeout on any BiDi navigation

Nothing bounds `browsingContext.navigate`, `.reload`, or `.traverseHistory`. The
measurement above shows a 1s `pageLoad` timeout ignored for 3.11s.

### A4 — readiness is cached at construction

`@readiness` is resolved once in `initialize`. Correct today only because
`pageLoadStrategy` is create-only. It establishes the wrong pattern for
`timeouts`, which are mutable at runtime via Set Timeouts.

### A5 — `@bridge.window_handle` round-trips on every call

Each BiDi navigation method calls back into a classic endpoint to resolve the
context (existing `TODO` at `browsing_context.rb:34`). Latency, and it means the
"BiDi path" is not actually BiDi-only.

## Tasks

1. **Add `BiDi::NavigationWaiter`.** Subscribe to `browsingContext.navigationStarted`,
   `domContentLoaded`, `load`, `navigationFailed`, and `navigationAborted`. Expose
   `wait_for(context, readiness, timeout:)` resolving at the requested readiness
   level and raising `Error::TimeoutError` on expiry.
2. **Use it for `traverse_history`.** Subscribe before sending, wait after. This is
   the only way to honor `pageLoadStrategy` for back/forward until the spec grows a
   `wait` parameter (filed under Plan 02, item B4).
3. **Default readiness to `'complete'`** when the capability is missing, rather than
   omitting `wait`.
4. **Bound `navigate` and `reload`** with the `pageLoad` timeout, raising
   `Error::TimeoutError` to match classic.
5. **Resolve readiness and timeouts at call time** from the capability store
   (Plan 03), not at construction.
6. **Cache the current context** on the bridge to remove the per-call
   `window_handle` round-trip.

## Ordering constraint

`element_click` still goes over the classic endpoint, so click-induced navigation
is currently correct. The moment `actions` / `element_click` migrate to
`input.performActions`, that path has neither a readiness wait nor a page load
timeout. `NavigationWaiter` must land **before** that migration, not after.

## Tests

- Unit: `NavigationWaiter` against a stubbed event stream.
- Integration: extend `rb/spec/integration/selenium/webdriver/bidi/browsing_context_spec.rb`
  and `rb/spec/integration/selenium/webdriver/navigation_spec.rb` with a
  deliberately slow fixture. Assert `navigate.to`, `.back`, `.forward`, and
  `.refresh` all block per `pageLoadStrategy` and all raise `TimeoutError` per
  `pageLoad` — with and without `web_socket_url`.
- Regression guard: a parity spec running identical assertions against
  `Remote::Bridge` and `Remote::BiDiBridge` for the same capability set.

## Risks

- Local emulation drifting from remote-end semantics. Mitigated by the parity spec.
- Event-based waiting is inherently racier than a blocking remote-end command;
  subscribe before dispatching, never after.

## Reproduction

Measured on Chromium 141.0.7390.37 with matching ChromeDriver 141, headless,
Ruby 3.3.6, bindings at 4.31.0.nightly.
