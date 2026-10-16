# Spec: Fix desktop from-segments finalization skipping conversation enrichment

## Problem Statement

Desktop recordings uploaded through the `/v1/conversations/from-segments` ingestion path can be persisted as completed conversations while expected server-side enrichment is absent. User-visible symptoms reported in upstream [BasedHardware/omi#19705](https://github.com/BasedHardware/omi/issues/19705) include an empty overview/summary, missing action items/events, and placeholder-like categorization. This breaks the core capture → understand → remember loop: a recording can appear finished while the useful post-processing never ran.

## Evidence and Current Understanding

- Upstream report: [BasedHardware/omi#19705](https://github.com/BasedHardware/omi/issues/19705).
- Related proposed fix: [BasedHardware/omi#19788](https://github.com/BasedHardware/omi/pull/19788). Its hypothesis is that the from-segments route omits the `CLIENT_FINALIZE` processing trigger used by other explicit client-finalization paths.
- In the current fork’s `backend/routers/developer.py`, the from-segments path builds processing kwargs for the optional client projection and calls `process_conversation` without explicitly passing a trigger.
- The processing-trigger policy distinguishes a deferred capture-end path from explicit client finalization. The suspected mismatch can therefore take a legacy deferred-processing path and persist the minimal/placeholder conversation instead of running enrichment immediately.
- Existing tests reported on upstream PR #19788 cover from-segments idempotency and the free-tier entrypoint matrix. Those counts/results are upstream-authored claims, not independently verified here; OpenHands must run the relevant tests on this fork and report the real outputs.
- The code and issue must be rechecked at implementation time in case the fork has diverged or the bug has already been fixed.

This is a strong, evidence-backed hypothesis, not yet a demonstrated local reproduction. Confirm it with a regression test before treating the trigger adjustment as proven.

## Solution

Make the from-segments finalization path express the correct processing intent so a completed desktop upload follows the same explicit-finalization semantics as the established sibling client path. Preserve idempotency and admission/lifecycle guarantees. Keep subscription, rollout, and free-tier policy gates authoritative: choosing the right trigger must not silently bypass access policy or accidentally impose eager paid processing on accounts that are intentionally assigned a minimum/deferred path.

## User Stories

1. As a desktop user, when I finish and upload a transcript, I want the resulting conversation to be enriched when my account and current policy permit enrichment, rather than marked completed with empty placeholder fields.
2. As a user, I want the final conversation status to mean that the intended finalization pathway has been applied—not merely that transcript data has been stored.
3. As a user whose subscription or rollout policy does not permit full enrichment, I want the existing policy behavior to remain intact; the fix must not circumvent a trial paywall, free-tier policy decision, or an intentional defer/minimum-projection path.
4. As a client that retries finalization, I want the existing idempotency contract to continue preventing duplicate or conflicting conversations and processing.
5. As a maintainer, I want a behavioral regression test that fails against the broken behavior and passes with the fix, exercising production behavior through the existing deterministic seam rather than only asserting source text.
6. As a maintainer, I want focused test commands and their actual outcomes recorded in the PR so a reviewer can distinguish a validated fix from an unverified code change.
7. As a contributor working in this fork, I want the change to remain scoped to the trigger/finalization contract and closely related regression coverage, so OpenHands does not opportunistically expand it into a transcription, diarization, or architecture rewrite.

## Implementation Decisions

- Verify the current fork’s route, processing coordinator, trigger semantics, and relevant tests immediately before changing code. Do not assume upstream PR #19788 applies unchanged.
- Use the existing from-segments endpoint/coordinator boundary as the primary test seam. Prefer the smallest deterministic behavioral test that proves the request’s processing intent and the persisted/user-visible result for an account eligible for enrichment.
- Add/extend policy-matrix coverage for an account or rollout state that must retain the minimum/deferred behavior. The corrected finalization signal must not weaken downstream eligibility checks.
- Preserve the route’s idempotency and processing-admission behavior. Avoid changing persistence ordering or adding a parallel finalization path unless a test demonstrates it is necessary.
- Inspect sibling client-finalization paths and use their established contract rather than inventing new trigger semantics.
- Keep diarization, segment splitting, transcript quality, and historical-record repair out of this fix. These may be real adjacent symptoms, but the evidence currently identifies a likely finalization-trigger mismatch, not a proven common root cause.
- Conversation hydration/rendering is a separate concern. Test that the persisted enrichment is available from the backend contract where feasible, but do not rewrite client hydration as part of this ticket.
- Do not weaken, remove, or relabel a failing test merely to make the suite pass. If the regression test fails for an unrelated environment/pre-existing issue, document it precisely.

## Testing Decisions

Run the narrowest relevant existing tests first, then the backend runner/lane required by the repository guidance. At minimum:
1. From-segments regression coverage: prove an eligible explicit desktop finalization enters the intended enrichment path and persists the expected enriched result/contract.
2. Idempotency tests: retries do not create duplicate conversations or double-finalize.
3. Free-tier/rollout entrypoint matrix: policy-ineligible cases remain on the intended minimum/deferred behavior and do not bypass paywall/eligibility.
4. Relevant processing-trigger/coordinator tests.
5. Run the documented backend test/check command that is feasible in the environment (consult `backend/AGENTS.md` and root `AGENTS.md`); report exact commands, pass/fail counts, and any environmental skips.
6. If tests pass, run the real user-facing path only if the available offline/dev harness can do so safely. Do not connect to production or process real user recordings for verification.

A passing test must assert behavior at a controllable seam. A source-text check alone does not satisfy the regression requirement.

## Out of Scope

- Fixing speaker diarization, collapsing single-speaker transcripts, splitting segments, or changing transcription models.
- Backfilling/reprocessing historical recordings already stored without enrichment.
- Rewriting macOS/Flutter hydration, sync, rendering, or API schemas.
- Changing subscription plans, trial/paywall rules, free-tier product policy, or rollout defaults.
- Broad refactoring of conversation processing, adding new queues/frameworks, or unrelated cleanups.
- Deploying any change to production or merging it to upstream BasedHardware/omi.

## Further Notes

The product principle in `PRODUCT.md` is “Trust over cleverness”: silent data loss and dual sources of truth are bugs. Treat a completed-but-unenriched conversation as a correctness problem, while carefully distinguishing intentional policy-based minimal processing from accidental deferral.

Useful references:
- User report: https://github.com/BasedHardware/omi/issues/19705
- Existing proposed fix to compare, not copy blindly: https://github.com/BasedHardware/omi/pull/19788
- Current fork route: https://github.com/thesohamdatta/omi/blob/main/backend/routers/developer.py
- Backend contributor/testing guidance: https://github.com/thesohamdatta/omi/blob/main/backend/AGENTS.md
- Product principles: https://github.com/thesohamdatta/omi/blob/main/PRODUCT.md

Implementation should happen on a feature branch in this fork. Do not commit directly to `main`. Open a PR only after the regression test and focused suite are run, and include real verification evidence in the PR description.
