# Spec: Fix desktop from-segments finalization skipping conversation enrichment

## Problem Statement

Desktop recordings uploaded through the `/v1/conversations/from-segments` ingestion path can be persisted as completed conversations while expected server-side enrichment is absent. User-visible symptoms reported in upstream [BasedHardware/omi#19705](https://github.com/BasedHardware/omi/issues/19705) include an empty overview/summary, missing action items/events, and placeholder-like categorization. This breaks the core capture → understand → remember loop: a recording can appear finished while the useful post-processing never ran.

## Evidence and Current Understanding

- Upstream report: [BasedHardware/omi#19705](https://github.com/BasedHardware/omi/issues/19705).
- Related proposed fix: [BasedHardware/omi#19788](https://github.com/BasedHardware/omi/pull/19788). That newer upstream code uses a ProcessingTrigger.CLIENT_FINALIZE abstraction; that abstraction does not exist in this fork and must not be copied into it as a one-off import.
- Before this change, the from-segments route passed neither force_process nor a trigger, while the established explicit desktop create/finalize path passes force_process=True to process_conversation. The local regression test reproduced the missing call intent before the fix.
- With the rollout flag off, that mismatch allows should_defer_desktop_processing to persist a deferred placeholder for a free-tier desktop transcript instead of enriching the already-finalized upload. The fork-local equivalent is to request force_process=True for desktop from-segments uploads, matching the sibling route.
- This only bypasses the legacy capture-time deferral. The coordinator's trial-paywall early return remains authoritative, and the rollout-on FREE_TIER_LOCAL_PROCESSING policy still sends identified-basic desktop accounts to the minimum/projection path even when force_process=True.
- With FREE_TIER_LOCAL_PROCESSING off, force_process=True also makes the existing BASIC_PLAN_GATE_EAGER_EXTRACTION_ENABLED guard reachable. That guard is default-off; if enabled, its identified-basic deny still persists the deterministic minimum. The existing coordinator tests cover this gate, so the PR must not claim that force_process bypasses it.
- Upstream PR test counts are not evidence for this fork. The initial red reproduction failed because the route omitted force_process. The route test was then promoted to the public HTTP seam and now verifies desktop uses force_process while phone uploads do not. Four isolated focused files pass 278 tests across from-segments idempotency, the free-tier entrypoint matrix, policy, and coordinator branch coverage. The trial-paywall guard verifies force_process does not bypass the paywall.
- The code and issue must be rechecked at implementation time in case the fork has diverged or the bug has already been fixed.

The fork-local behavior is now demonstrated: the test failed before the route change, and the regression plus coordinator policy matrix pass after the change. The upstream ProcessingTrigger design is not imported; this fork uses its existing force_process contract.

## Solution

Make the from-segments finalization path express the correct processing intent so a completed desktop upload follows the same explicit-finalization semantics as the established sibling client path. Preserve idempotency and admission/lifecycle guarantees. Keep subscription, rollout, and free-tier policy gates authoritative: choosing the right trigger must not silently bypass access policy or accidentally impose eager paid processing on accounts that are intentionally assigned a minimum/deferred path.

**Product-impact note for review:** With the rollout flag off, this makes free-tier desktop from-segments uploads enrich at upload rather than waiting for first-open, matching the sibling explicit-finalize paths. The trial paywall and rollout-on `FREE_TIER_LOCAL_PROCESSING` entitlement policy remain authoritative. Confirm this upload-time spend parity before merging; it is deliberately called out rather than treated as an incidental side effect.

## User Stories

1. As a desktop user, when I finish and upload a transcript, I want the resulting conversation to be enriched when my account and current policy permit enrichment, rather than marked completed with empty placeholder fields.
2. As a user, I want the final conversation status to mean that the intended finalization pathway has been applied—not merely that transcript data has been stored.
3. As a user whose subscription or rollout policy does not permit full enrichment, I want the existing policy behavior to remain intact; the fix must not circumvent a trial paywall, free-tier policy decision, or an intentional defer/minimum-projection path.
4. As a client that retries finalization, I want the existing idempotency contract to continue preventing duplicate or conflicting conversations and processing.
5. As a maintainer, I want a behavioral regression test that fails against the broken behavior and passes with the fix, exercising production behavior through the existing deterministic seam rather than only asserting source text.
6. As a maintainer, I want focused test commands and their actual outcomes recorded in the PR so a reviewer can distinguish a validated fix from an unverified code change.
7. As a contributor working in this fork, I want the change scoped to the finalization contract and related regression coverage, so implementation does not expand into transcription, diarization, or an architecture rewrite.

## Implementation Decisions

- Verify the current fork’s route, processing coordinator API, and relevant tests immediately before changing code. Do not assume the newer ProcessingTrigger abstraction in upstream PR #19788 exists in this fork.
- Use the existing from-segments endpoint/coordinator boundary as the primary test seam. Prefer the smallest deterministic behavioral test that proves the request’s processing intent and the persisted/user-visible result for an account eligible for enrichment.
- Add/extend policy-matrix coverage for an account or rollout state that must retain the minimum/deferred behavior. The corrected finalization signal must not weaken downstream eligibility checks.
- Preserve the route’s idempotency and processing-admission behavior. Avoid changing persistence ordering or adding a parallel finalization path unless a test demonstrates it is necessary.
- Inspect sibling client-finalization paths and use their established contract rather than inventing new trigger semantics.
- Keep diarization, segment splitting, transcript quality, and historical-record repair out of this fix. These may be real adjacent symptoms, but the evidence currently identifies a likely finalization-trigger mismatch, not a proven common root cause.
- Conversation hydration/rendering is a separate concern. Test that the persisted enrichment is available from the backend contract where feasible, but do not rewrite client hydration as part of this ticket.
- Do not weaken, remove, or relabel a failing test merely to make the suite pass. If the regression test fails for an unrelated environment/pre-existing issue, document it precisely.

## Testing Decisions

Run the narrowest relevant existing tests first, then the backend runner/lane required by the repository guidance. At minimum:
1. From-segments regression coverage: prove the desktop route passes force_process=True and verify its coordinator effect through the entrypoint matrix for eligible and policy-ineligible account states.
2. Idempotency tests: retries do not create duplicate conversations or double-finalize.
3. Free-tier/rollout entrypoint matrix: policy-ineligible cases remain on the intended minimum/deferred behavior and do not bypass paywall/eligibility.
4. Relevant coordinator, free-tier policy, trial-paywall, and lifecycle tests.
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
