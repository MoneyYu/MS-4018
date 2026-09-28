# Phase 4 — Model selection (lifecycle-safe)

This is **time-sensitive** and must be redone before *every* course delivery.

## The rule

Every model you deploy **must** be validated against the Foundry model retirement schedule *with
today's date*. **Never** deploy a retired or soon-to-be-retired model; prefer the **latest GA**.
Avoid Preview models unless there is no GA alternative (and say so).

- Authoritative source:
  <https://learn.microsoft.com/azure/ai-foundry/concepts/model-lifecycle-retirement>

## Process

1. **List the models the course slides/labs demo** (from Phase 1).
2. **Look up each** on the retirement page. Classify: GA vs Preview, and the **retirement date**.
3. **Flag** anything retired, in Preview, or retiring "soon" (use judgment — months away still
   matters for a backup that must work at the next delivery).
4. For each flagged model, **find the latest non-retiring GA replacement** in the same family
   (chat/vision, image, video, embedding).
5. **Verify the replacement's regional availability and quota** in the target region before
   committing to it (Phase 5 will catch quota at apply time, but check up front).
6. **Surface the tension** to the user: the slides may demo an older model while the rule says use
   the latest GA. Recommend, but let them decide which to match.

## Known constraints to bake in

- **Azure Content Understanding only supports a fixed set of completion models** (currently
  `gpt-4.1` / `gpt-5.2`). So CU needs its **own** completion-model deployment, separate from the
  general chat/vision deployment (e.g. a `gpt-5.2` for CU **and** a newer `gpt-5.x` for chat/vision).
- **Some models can't be deployed via Terraform** and must be created **manually in the portal**
  (AI-3008: `sora-2`, `FLUX`, `Phi-4`). Document those steps in `TERRAFORM/README.md` rather than
  forcing them into the stack.
- **Image models share a small per-region quota.** If quota is exhausted, either reduce another
  deployment's capacity to free units or parameterize the image model so it can swap to one with
  quota (see Phase 5 playbook).

## Output

A short model table: each course model → chosen deployment (name + version) → GA/retirement status →
region/quota note → "Terraform" or "manual-portal". Mirror this table into `docs/demo-environment.md`.
