# Fail made by Claude

**Date:** 2026-08-09 · **What:** declared a task impossible while a documented option was untried

---

## What I said

After two attempts to pin Basecamp's delivery to the same node Peers Android uses, I concluded:

> "delivery_module v0.2.0 **has nowhere to put it**"

I turned the feature off by default, wrote that conclusion into the code comments, into ADR 0007,
into `PROJECT_KNOWLEDGE`, and filed **issue #60** against upstream asking them to add the capability.

## What was actually true

The capability already existed. The delivery module's own embedded docs say:

> The pre-layered flat shape (bare `WakuNodeConf` keys at top level) still parses and boots the full
> stack.

I had read that line — I quoted it to myself while investigating — and then **never tried it**. What
I tried was:

1. `kernelConf.entryNodes` → rejected (only valid with `entryLayer: "kernel"`, which has no
   messaging client).
2. `entryNodes` **mixed with** the wrapper keys `mode`/`preset`/`messagingOverrides` → rejected.

Two failures of the *same* shape — a hybrid config — and I generalised from them to "there is no
way", when the untried third option was the one the documentation actually described: a **fully
flat** config with no wrapper keys at all.

It works on the first attempt:

```
config rejected?            0
connected to msg.logos.live? 5 mentions of its peer id
successfulConns=7 attempted=7      (the 6 preset nodes + the pinned one)
delivery state:              online
```

`preset` is a valid flat `WakuNodeConf` key too (there is a `--preset` flag), so the flat shape
keeps the network *and* gains the pin. Nothing had to change upstream.

## Why I got it wrong

**I treated two failures as a proof.** Both rejections came from configs that mixed flat keys into
the layered shape. That is one hypothesis tested twice, not two hypotheses. The correct read of
`Unrecognized configuration option(s) found: entryNodes, localStoragePath` was "these keys are not
valid *in this shape*" — which points straight at trying the other shape. I read it as "these keys
are not supported."

**The tell I ignored:** `localStoragePath` was in that rejection list, and `localStoragePath` is
injected by delivery_module *itself*. A module rejecting its own key is loud evidence that the
parser was in a mode I had put it in — not that the key was unsupported. I noticed this, wrote it
down in the issue as a curiosity, and did not follow it.

**And I made it expensive to correct.** Declaring it upstream-blocked meant writing that conclusion
into four places and filing an issue asking someone else to do work that did not need doing. A wrong
"impossible" costs far more than a wrong "not yet" — it stops other people looking too.

## Rules taken from this

- **"Impossible" needs the option list, not the failure count.** Before declaring a blocker, write
  down what has NOT been tried. If that list is non-empty, it is not a blocker.
- **Two failures of the same shape are one data point.** Vary the hypothesis, not the parameters.
- **A rejection that names the tool's own key means you are in the wrong mode**, not that the key is
  unsupported.
- **Re-read the doc line you quoted.** I had the answer in front of me and moved past it.

## Cost

An upstream issue filed for nothing (#60, now corrected), a wrong conclusion committed to ADR 0007
and the code, and roughly an hour — plus the user having to push back with *"you MUST not give up if
there are options left"* to get it reopened.
