---
name: course-prep
description: 'End-to-end playbook for preparing (備課) a Microsoft training-course reference repo (AI-xxxx, AZ-xxx, etc.). Use when the user wants to prepare/refresh a course, update the course README, build the demo/backup Terraform stack for a course, validate course models, write a trainer teaching guide (備課指南), or set up the course repo (issue + commits + copilot-instructions). Triggers on requests like "準備課程", "備課", "prepare AI-xxxx", "update the course README", "build the demo Terraform for this course", "幫我備課", "prepare course materials", or "research this course".'
---

# Prepare a Microsoft Training Course (Reference Repo)

A repeatable workflow for turning a Microsoft course (ESI/MCT instructor-led course such as
**AI-3008**, **AI-3016**, **AZ-104**, …) into a complete reference repo: an attendee-facing
README, a demo-ready **backup** Terraform stack, trainer-only docs, and a clean Git/GitHub trail.

This skill generalizes the exact operation used to prepare **AI-3008** ("Extract insights from
visual data on Azure"). Follow it for any other course.

## When to use

- "準備 / 備課 / prepare course materials for AI-xxxx"
- "Update / refresh the course README"
- "Build (or test) the demo Terraform / backup environment for this course"
- "Check the course's models aren't retired"
- "Write a teaching guide / 備課指南"
- "Set up the course repo (issue, commits, copilot-instructions)"

## What you produce (target repo structure)

```
<COURSE>/
├─ README.md                     # Attendee-facing course reference (HackMD style). NO trainer-private info.
├─ .gitattributes                # Mark binary asset types so * text=auto can't corrupt them
├─ .gitignore                    # Ignore .terraform/, *.tfstate, .terraform.lock.hcl, local helpers
├─ .github/
│  ├─ copilot-instructions.md    # Repo-specific conventions (produced by /init)
│  └─ skills/                    # git-commit, github-issues, course-prep, …
├─ TERRAFORM/                    # Trainer-private demo "backup" stack (full resources + data plane)
│  ├─ MAIN.tf                    # providers + variables + locals + resource groups
│  ├─ MOD.tf                     # all resources + data-plane wiring
│  ├─ OUTPUT.tf                  # endpoints / names
│  ├─ README.md                  # how to deploy/destroy + data-plane explanation
│  ├─ scripts/*.ps1              # data-plane automation (PowerShell 7 + az, AAD)
│  └─ sample-data/               # realistic fictional demo assets (binaries only)
└─ docs/                         # Trainer-only docs (NOT attendee-facing)
   ├─ demo-environment.md        # the demo stack + model choices
   └─ teaching-guide.md          # 備課指南 (teaching prep)
```

> Reference the user's sibling course repos for the canonical shape:
> `MoneyYu/AI-3016`, `AI-3003`, `AI-102`, `AZ-104`. They share this layout — diff against the
> closest one rather than inventing structure.

## Workflow (8 phases)

Work top-to-bottom; load the matching reference file only when you reach that phase. Track
progress with a todo list and (for multi-step phases) a `plan.md`.

| # | Phase | Reference |
|---|-------|-----------|
| 0 | **Plan & track** — restate scope, create todos / `plan.md`, confirm the target GitHub repo | — |
| 1 | **Research & verify the course** — confirm the *current* course identity, modules, labs, credential | [references/01-research.md](references/01-research.md) |
| 2 | **Attendee README** — HackMD reference page: module-grouped Links, official-only Videos, and a markmap near the end before Exam/Credential and Contact; verify every link & video | [references/02-readme.md](references/02-readme.md) |
| 3 | **Demo backup Terraform** — full stack to a completed (resources + data-plane) state | [references/03-terraform.md](references/03-terraform.md) |
| 4 | **Model selection** — validate against the retirement schedule; latest GA | [references/04-models.md](references/04-models.md) |
| 5 | **Validate & end-to-end test** — fmt/validate, AST parse, real apply + destroy | [references/05-validation.md](references/05-validation.md) |
| 6 | **Trainer teaching guide (備課指南)** — `docs/teaching-guide.md` | [references/06-teaching-guide.md](references/06-teaching-guide.md) |
| 7 | **Git & GitHub** — issue (body=scope/comments=progress), commits, /init | [references/07-git-workflow.md](references/07-git-workflow.md) |

Phases 2–4 are usually iterated together (README ↔ models ↔ Terraform). Phases 5–7 close out.

## Golden rules (apply in every phase)

1. **Verify the course identity first — courses get renamed/re-versioned.** The existing README
   may describe an *old* version of the course. Confirm the current title + modules against
   Microsoft Learn before changing anything. (AI-3008 flipped from "Azure AI Language" to
   "Extract insights from visual data".)
2. **Attendee README vs trainer-only `docs/`.** The README is for attendees — keep demo
   environment details, model choices, Terraform, and Skillable internals out of it; put them in
   `docs/`. Keep the per-instance metadata (Date, Course ID, survey, Skillable key) current.
3. **Models must not be retired or near-retirement.** Always check the Foundry model
   retirement schedule with *today's* date; prefer the latest GA. Re-check before each delivery.
4. **The tenant is Entra ID (AAD) only — no account/access keys.** Storage, Cognitive/AI
   Services, and AI Search all enforce key-less auth + managed identity + RBAC.
5. **The Terraform is a *backup* for a live from-scratch demo** — it must reach a *completed*
   state (resources **and** data plane), so the demo shows real results immediately.
6. **Verify every external link *semantically* before adding it** — check status **and** final URL
   (after redirects) **and** page title/locale, not just HTTP 200; drop links that 200 but redirect
   to a generic hub/browse page. README references must be official, directly relevant to the
   matching course module, and use the exact standalone-link layout in
   [references/02-readme.md](references/02-readme.md). The mind map visualizes the official course
   outline in the `MoneyYu/AI-901` style; it is not a generic concept map or link directory.
   **Videos: official Microsoft channels ONLY**, confirmed LIVE via
   YouTube oEmbed, grouped by module, no third-party and no padding. Reuse
   [`scripts/link_check.py`](scripts/link_check.py) and re-verify before every delivery. Details:
   [references/02-readme.md](references/02-readme.md).
7. **Python work uses a virtual environment (venv).** Commit only generated binary assets, not
   the generator; mark binary types in `.gitattributes`.
8. **Decide, don't stall — but say when you don't know.** Make reasonable assumptions and state
   them; surface genuine uncertainties (region/quota/credential/model tension) to the user rather
   than guessing silently.

## Reusing this skill in other course repos

The user's course repos are independent (each has its own `.github/skills/`). To use this skill
when preparing a *different* course, copy `.github/skills/course-prep/` into that repo (or keep a
template repo that all course repos are seeded from). The content here is course-agnostic; AI-3008
is only the worked example.
