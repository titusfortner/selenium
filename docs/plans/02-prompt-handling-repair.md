# Plan 02 — Restore `unhandledPromptBehavior` notify semantics, and take it upstream

Status: proposal
Owner: unassigned
Depends on: nothing. Ships independently of Plans 01 and 03.

## Context

A session created over classic HTTP with `webSocketUrl: true` keeps every classic
capability — `flags` is `{"http"}` during capability processing, and `"bidi"` is
appended afterward by the `webSocketUrl` new session algorithm, too late to gate
anything. Verified: the returned capabilities differ by exactly one key.

`unhandledPromptBehavior` is the sole exception, and it degrades the moment BiDi is
*enabled*, not when any particular command migrates — the handling happens in the
browser at prompt-display time. Measured with **no capability set at all**, so the
spec default applies, and with navigation forced over the classic endpoint:

```
ws=false  echoed="dismiss and notify"  UnexpectedAlertOpenError — notify fired
ws=true   echoed="dismiss and notify"  <no error>              — notify LOST
```

The remote end returns `"dismiss and notify"` either way and implements the
dismiss half only.

### Why this happens

BiDi handles prompts **eagerly**. The *WebDriver BiDi user prompt opened* steps are
a remote end event trigger: they run when the dialog appears, resolve the handler,
and return it, so the browser applies accept/dismiss immediately. Only `"ignore"`
maps to `"none"`.

Classic handles prompts **lazily**. *Handle any user prompts* runs at the start of
each command and begins "If the current browsing context is not blocked by a dialog
return success", reaching its `unexpected alert open` step only if a dialog was
still standing.

In a hybrid session the dialog is gone before the next classic command arrives, so
the notify step is never evaluated. Confirmed by matrix: `accept and notify` and
`dismiss and notify` both lose the error with `ws=true`; `ignore` and plain
`accept` are identical in both.

## B1 — Ship the client-side shim

Recoverable locally. The spec emits `browsingContext.userPromptOpened` *before*
applying the handler, and the payload carries what is needed:

```
echoed unhandledPromptBehavior: "dismiss and notify"
  click #a -> event: {"handler"=>"dismiss", "message"=>"from alert",   "type"=>"alert"}
  next command       -> no error from remote end
  click #c -> event: {"handler"=>"dismiss", "message"=>"from confirm", "type"=>"confirm"}
  next command       -> no error from remote end
```

`message` is exactly what `UnexpectedAlertOpenError`'s alert text needs.

### Implementation

1. Subscribe to `browsingContext.userPromptOpened` when the BiDi session opens.
2. Resolve whether `notify` applies for the prompt's `type`, from the negotiated
   `unhandledPromptBehavior` (default `"dismiss and notify"`), following classic's
   *get the prompt handler* fallback order: exact type → `default` →
   `beforeUnload` special case → `fallbackDefault` → `dismiss` with notify true.
3. Record a pending notification keyed by context, carrying the event's `message`.
4. In `Remote::BiDiBridge`, before dispatching any command, consume a pending
   notification and raise `Error::UnexpectedAlertOpenError` with that text.

### Edge cases requiring specs

- `ignore` — the prompt genuinely stays open and the remote end already raises.
  Do not double-raise.
- explicit `accept` / `dismiss` without notify — must not raise.
- `beforeUnload` — classic falls back to `accept` with notify false.
- `file` — BiDi-only prompt type, no classic analogue.
- prompts opened in a context other than the current one.
- string form (`"dismiss and notify"`) vs map form of the capability.

## B2 — Read the upstream threads (do this first; currently blocked)

Gates B3. Could not be read from the environment where this was investigated:
GitHub issue pages do not render for the fetcher, `gh` is not installed, and
attaching `GoogleChromeLabs/chromium-bidi` for API access is refused by a
cross-tier restriction. Needs a session started with that repo as its initial
source, or the threads pasted in.

To review:

| Thread | State | Note |
| --- | --- | --- |
| `GoogleChromeLabs/chromium-bidi` #3873 *Incorrect UnhandledPromptBehavior* | closed | filed by titusfortner, Oct 2025 |
| `GoogleChromeLabs/chromium-bidi` #2556 *Alerts are automatically closing* | closed | filed by Christian Bromann (WebdriverIO), Sept 2024 — independent cross-client confirmation |
| `GoogleChromeLabs/chromium-bidi` PR #2351 | merged | referenced as the origin of the behavior |
| second closed chromium-bidi issue | closed | identifier not captured |
| `SeleniumHQ/selenium` #14450 | open | the user-facing symptom |

For each: was the closing rationale *spec-conformance* (fix belongs at W3C) or
*intended behavior* (worth reopening with the capability-echo evidence)?

That WebdriverIO hit this a year earlier and was also closed is the strongest
argument that the venue is wrong rather than the report.

## B3 — Upstream recommendations

Draft after B2. Current position, subject to what the threads say.

### `w3c/webdriver-bidi` — the substantive one

The notify bit is discarded at a single step. *Get navigable's user prompt handler*
ends:

```
1. Let |handler configuration| be [=get the prompt handler=] with |type|.
1. Return |handler configuration|'s [=prompt handler configuration/handler=].
```

`get the prompt handler` returns a full prompt handler configuration — `handler`
**and** `notify`. The BiDi wrapper returns only `.handler`. That discard is where
the information is lost.

Two candidate fixes:

**Carry notify through.** Keep the full configuration; set a session-level
pending-notification flag when `notify` is true; amend classic's *handle any user
prompts* step 1 to return `unexpected alert open` when the flag is set even though
no dialog is currently blocking. Hybrid sessions then behave like classic ones;
pure-BiDi sessions are unaffected.

**Split the capability name.** `unhandledPromptBehavior` describes what to do with
a prompt *still open when a command arrives* — that is what makes the name accurate
and what makes `notify` coherent. BiDi's handler fires at display time
unconditionally, so nothing is ever "unhandled"; it is an automatic-prompt policy.
The same key selecting between two different models is the backwards-compatibility
break. Give the eager model its own key and leave `unhandledPromptBehavior` with
its classic meaning. Note that `session.UserPromptHandlerType` is only
`"accept" / "dismiss" / "ignore"` — BiDi's type system cannot express notify at
all, which is evidence the two models were never reconciled.

Supporting either: the spec emits `userPromptOpened` *before* applying the handler,
so deferring the handling costs BiDi consumers nothing — they still get the event.
Eager handling is not load-bearing for observability.

### `w3c/webdriver`

State explicitly what a hybrid (`http` + `bidi`) session owes classic prompt
semantics. The current text leaves it to inference.

### WPT

Assert that the returned `unhandledPromptBehavior` matches observed behavior, run
with and without `webSocketUrl`. The strongest framing is not "BiDi picked
different defaults" but "the session advertises a capability value it does not
implement."

### `chromium-bidi`

Likely no change until the spec resolves. The narrow ask that stands on its own:
stop echoing `"dismiss and notify"` while implementing only the dismiss half.

## B4 — Adjacent spec gaps worth filing at the same time

Each is a "must be managed locally" that need not be:

- `browsingContext.traverseHistory` has no `wait` parameter — forces every client
  to reimplement readiness waiting for back/forward (see Plan 01, A1).
- `script.evaluate` / `script.callFunction` have no timeout parameter (open `TODO`
  in the spec text).
- `browsingContext.navigate` has no timeout parameter.
- `input.setFiles` performs no interactability check, so `strictFileInteractability`
  has no BiDi expression.

## Risks

- Restoring notify changes behavior for anyone who adapted to its absence. It
  restores documented behavior and matches the advertised capability, but it
  belongs in release notes.
- Upstream may reject the argument again. B1 does not depend on that outcome.

## Open questions

- Which was the second closed chromium-bidi issue, and what were both closing
  rationales?
- Does Firefox/geckodriver show the same notify loss? Not testable where this was
  measured — Chrome only.
- Does requesting `webSocketUrl: true` but never connecting the socket also lose
  notify? Ruby connects eagerly at session creation, so this was not isolated.

## Reproduction

Measured on Chromium 141.0.7390.37 with matching ChromeDriver 141, headless,
Ruby 3.3.6, bindings at 4.31.0.nightly.
