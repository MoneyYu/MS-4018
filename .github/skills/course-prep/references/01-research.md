# Phase 1 — Research & verify the course

**Goal:** establish the *current, authoritative* identity of the course — title, modules, labs,
localization, and credential — before touching any files. Do not trust the existing README; courses
are frequently renamed and re-versioned.

## Inputs to ask for / gather

- **Course ID** (e.g. `AI-3008`, `AZ-104`) and the Microsoft Learn course/path links.
- **The PPT / slide deck** (often a `PPT/` folder the user points at). Speaker notes are gold for
  Phase 6 demo talking points. Extract the text; do not keep the deck in the attendee repo.
- **Sibling course repos** the user already prepared — reference these for expected structure and
  the Terraform pattern (e.g. `MoneyYu/AI-3016`, `AI-3003`, `AI-102`, `AZ-104`).

## Tools

- **Microsoft Learn MCP** (`microsoft_docs_search`, `microsoft_docs_fetch`) — primary, authoritative.
- **`web_search`** — for "does X exist / latest status", but always confirm against Learn (web
  summaries can be AI-synthesized or cite dead URLs).
- **GitHub MCP / `gh`** — to read sibling repos and the course's lab repos.
- For PPT text extraction prefer a Python venv with `python-pptx` (per user preference), or any
  available extractor.

## Steps

1. **Confirm the current course identity.** Fetch `learn.microsoft.com/training/courses/<course-id>`
   and the linked **learning path**. Record the *current* title and the full ordered **module
   list**. ⚠️ Compare against the existing README — if they disagree, the README is stale and the
   course was re-versioned (flag this prominently to the user).
2. **Map modules → labs.** Find the lab repo(s) under `github.com/MicrosoftLearning/mslearn-*`.
   A course may span **multiple** lab repos (AI-3008 uses *mslearn-ai-vision* for modules 1–4 and
   *mslearn-ai-information-extraction* for 5–8). Capture each exercise's published URL
   (`…github.io/<repo>/Instructions/Exercises/<n>-….html`) and the `main.zip` download.
3. **Check localization.** Note whether the learning path and the lab repos have `zh-cn` / `zh-tw`
   versions. Often the path is localized but the **labs are English-only** — state this in the
   README (`:::warning`).
4. **Check for a skill-based credential.** Look in the **Applied Skills** catalog. Many courses only
   offer an **Achievement Code** (course-completion badge), *not* an Applied Skills credential.
   Verify against Learn; don't assume one exists.
5. **Study the closest sibling repo.** Read its `README.md` + `TERRAFORM/{MAIN,MOD,OUTPUT}.tf` to
   inherit naming, region, provider versions, and the data-plane pattern. Diff, don't reinvent.
6. **List the services & models the course demos** (from modules + slides). Feed this into Phase 4
   (model lifecycle check) and Phase 3 (what resources the Terraform must create).
7. **Decide the region.** Pick a region where *all* required services **and** the chosen models are
   available (and ideally GA). This is a deliberate decision — record the reason. (AI-3008 → `eastus2`
   for Content Understanding GA + Foundry + the selected models.)

## Output of this phase

A short written brief: confirmed course title, ordered module list, lab repo URLs, localization
status, credential status, target region (+ reason), and a list of **open uncertainties** to raise
with the user (e.g. model-vs-slides tension, region/quota risks). Say explicitly when you don't know
something.
