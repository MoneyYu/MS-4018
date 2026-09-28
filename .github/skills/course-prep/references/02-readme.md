# Phase 2 — Attendee-facing README

The `README.md` is the **attendee-facing** course reference page. It uses **HackMD-style** syntax
(the user publishes it on HackMD), which is *not* plain GitHub Markdown. Preserve these constructs:

- **YAML front-matter** (`image`, `tags`, Google Analytics `GA` id).
- **Admonition blocks**: `:::success`, `:::info`, `:::warning` … `:::`.
- An optional **mind map**: a ```` ```markmap ```` fenced block.

## Hard rule: attendee-only

Keep **trainer-private** content out of the README — no demo-environment details, no model-choice
rationale, no Terraform, no internal notes. Those live in `docs/` (Phase 6 and
`docs/demo-environment.md`). If you find such a section in an old README, **move** it to `docs/`.

## Required sections (adapt to the course)

1. **Front-matter + title + one-paragraph intro** — what the course teaches, in plain language.
2. **`## Course`** — `:::success` with the per-instance metadata: **Date** (`YYYYMMDD`),
   **Course ID** (the numeric ESI delivery id). `:::info` with the **Course Survey** link.
3. **`## Course Materials`** — the Microsoft Learn learning-path links (EN / `zh-cn` / `zh-tw`) and
   the Learn course page.
4. **`## Infos`** — LxP portal (`esi.microsoft.com`) and ESI support links.
5. **`## Lab`**
   - **Skillable**: ESI Labs link + `:::success` **Training key** + `:::info` redeem-once / valid
     6 months note.
   - **Instruction**: the lab exercise links (grouped per lab repo if there are several), plus each
     `main.zip`. Add a `:::warning` if labs aren't localized.
6. **`## Links`** — curated official references grouped in the course's teaching order. First
   inspect the **original/source course README** and preserve its module-reference layout, heading
   rhythm, and standalone-link formatting while replacing the old subject matter with the current
   course. Reconcile its headings with the current official module order; when the current course
   has explicit Learning Paths, Learning Path headings may group those modules without changing
   the source layout's link presentation. Do not invent a service/resource taxonomy. Every link
   must directly support that module's official objectives.
7. **`## Videos`** — curated, **module-grouped** *official-only* videos. See **Videos** below.
8. **`## Mind Map`** — a ```` ```markmap ```` overview representing the course outline in the
   structural style used by `MoneyYu/AI-901`. See **Mind map** below.
9. **`## Exam & Credential`** — official exam, certification, and study-guide links when the
   course maps to a credential. Use the standalone-link formatting contract below.
10. **`## Contact`** — course-owner contact details, following the sibling-repo convention.

## Per-instance metadata to refresh every delivery

`Date`, `Course ID`, `Course Survey`, and the **Skillable Training key**. These change per class —
update them and nothing else when only re-running the same course.

## Quality bar

- **Verify every external link *semantically*, not just HTTP 200** (see "Organizing & verifying
  links"). Drop or fix dead links, and links that 200 but redirect to a generic hub/browse page.
- Prefer canonical `learn.microsoft.com/...` URLs over blog/marketing pages. End-user (business
  user) how-to pages on `support.microsoft.com` are also authoritative.
- Keep wording concise and attendee-appropriate; technical depth goes in `docs/teaching-guide.md`.
- The Links section is a reference index, not a concept summary. Put explanations and comparison
  tables in `docs/teaching-guide.md`; the markmap carries the concise curriculum concepts.

## Organizing & verifying links

**Group by module, not by service.** The `## Links` section mirrors the course's authoritative
module list. If the course publishes explicit Learning Paths, use a `### LPx - <path name>` heading
and `#### Mxx - <module name>` beneath it; otherwise use `### Mxx - <module name>`. Do **not** add
a generic `Foundations`, service, or resource category unless it is an official part of the course
outline. Inside each module, lead with the Microsoft Learn **module** page, then only supporting
concept/how-to pages that map directly to that module's objectives.

**Source and relevance contract**
- Official sources only: Microsoft Learn/product documentation, official Microsoft/GitHub
  documentation, or an official Microsoft-maintained repository required by the module.
- Prefer the exact product/concept/how-to page over a generic product hub.
- Do not add blogs, Q&A, community posts, third-party tutorials, pricing pages, or links included
  merely because they mention the same product.
- A supporting link belongs under exactly the module that teaches it. Do not use a related topic
  as filler in a neighboring module.

**Exact Markdown layout for standalone reference links**

```markdown
### LP1 - <learning path>
#### M01 - <module name>
[Microsoft Learn Module](https://learn.microsoft.com/...)

[Directly relevant official reference](https://learn.microsoft.com/...)

[Another directly relevant official reference](https://learn.microsoft.com/...)

#### M02 - <module name>
[Microsoft Learn Module](https://learn.microsoft.com/...)
```

- The first link is on the line immediately after its heading: **no blank line after a heading**.
- Put exactly one blank line between standalone links.
- Do **not** use bullet points or numbered lists for standalone links.
- Do not add prose summaries between links.
- These spacing rules also apply to other standalone-link groups such as Course Materials, Infos,
  and Exam/Credential. They do not prohibit bullets inside the markmap or the Contact section.

**Verify semantically — a 200 is not enough.** For every candidate URL, confirm:
1. **Final URL after redirects** — keep the canonical destination in the README.
2. **Page title / H1 matches the topic** — a live page can still be the *wrong* page.
3. **Locale** — a localized link must actually serve that locale, not silently fall back to EN.

Known-good redirects you should keep (the *final* URL): `aka.ms/...` short links; GitHub
`archive/refs/heads/main.zip` → `codeload.github.com`; the learn.microsoft.com
`/copilot/microsoft-365/...` → `/microsoft-365/copilot/...` move. **Drop** any link that 200s but
redirects to a generic hub (e.g. `.../training/browse/`) — that page no longer exists.

**Build one shared ledger.** Collect all candidate links + videos into a single list (label | url)
and run the checker so `## Links`, `## Videos`, the mind map, and `docs/teaching-guide.md` all cite
the *same* verified URLs. Re-run before every delivery — Microsoft rename/retire pages often.

> **Tool:** [`scripts/link_check.py`](../scripts/link_check.py) takes a `label | url` file and
> prints status + final URL + `<title>` for pages, and LIVE/OFFICIAL + channel + title for videos.
> Run it from the course venv: `python .github/skills/course-prep/scripts/link_check.py urls.txt`.

## Videos

The `## Videos` section is **module-grouped and official-only**. Use one `### Mxx - <module name>`
table per module. Add a `### Foundations` group only when Foundations is explicitly part of the
official course outline or the user requests it. Use a 3-column table:
`| No. | Name | Link |` with `youtu.be/<id>` links.

**Sourcing priority (best first):**
1. The course's **own official video series/playlist** if one exists (search `aka.ms/<COURSE>onYouTube`
   and the Microsoft Learn channel for a per-module episode series) — the single strongest source.
2. Videos **embedded in the course slide deck** (extract via the deck's hyperlink/media relationships
   — see [01-research.md](01-research.md)). These are the ones the course author chose.
3. Additional **official** per-module explainers/demos to fill gaps.

**Hard rules:**
- **Official Microsoft channels ONLY.** Verify each via YouTube oEmbed (see the tool): confirm
  `author_name` is a Microsoft-owned channel (e.g. *Microsoft*, *Microsoft 365*, *Microsoft Learn*,
  *Microsoft Mechanics*, *Microsoft Developer/365 Developer*, *Microsoft Community Learning*, regional
  *Microsoft APAC/ANZ*). **Reject third-party creators** even when the content looks good, and reject
  anything you cannot confirm the channel of (oEmbed 403 = embedding disabled → verify by hand or drop).
- **Liveness:** oEmbed 404 = unavailable → drop. Re-verify the whole set every delivery.
- **Relevance over completeness.** Keep a video only if it is (a) on-topic for that module, or
  (b) genuinely **foundational/important** context. **Drop off-topic, dated, or redundant clips**
  (e.g. generic app-Copilot demos on an *agents* course) and **do not pad** a module with weak videos.
  Dated product branding in a title (e.g. an old product name) is a signal to look for a newer official
  replacement.
- **No non-module catch-all sections.** Fold "customer stories" etc. into the relevant module only if
  they specifically demonstrate that module's topic; otherwise omit.

## Mind map

Add a `## Mind Map` near the end, followed by `## Exam & Credential` and `## Contact`, like
`MoneyYu/AI-901`. It is a single ```` ```markmap ```` fenced block (HackMD renders it).

**Structure**
- **Root `#`** = the course title.
- **`##` nodes** = each `Mxx - <module name>` in official course order. Add another node only when
  it is explicitly part of the official course outline.
- **`###` nodes** = two or three curriculum subtopics from that module's official objectives.
- **Bullet nodes** = concise core concepts, comparisons, named capabilities, or process steps under
  the matching curriculum subtopic.

**Content contract** — the map is a compact visualization of the **course outline**, not a copy of
the Links section and not a general architecture diagram:
- Derive branches from official module objectives, slide agendas, and knowledge-check themes.
- Capture the core concepts and the course's important comparisons in learner-facing language.
- Attach selected verified links inline on the concept they explain, as AI-901 does; do not create
  separate link-list branches or paste every reference.
- Keep trainer implementation choices, Terraform, demo paths, local/Azure setup notes, credentials,
  delivery metadata, lab logistics, and model-selection rationale out of the map.
- Do not add `Foundations`, `Labs`, exam metadata, or resource categories by habit. Include them
  only if the user or the official course outline explicitly requires them.

**Leave out**: per-instance metadata, Skillable/ESI logistics, marketing taglines, and any link not
already verified in the ledger. Don't dump every link — just the spine.

**Shape to aim for** (illustrative — adapt node names to the actual course):

```
## Mxx - <module name>
### <sub-theme>
- Core concept, embedded as [concept](https://learn.microsoft.com/...)
- **<Option A>** vs **<Option B>**: one-line distinction
- Named item 1 / Named item 2 / Named item 3
```

- Keep it dense-but-scannable; prefer two or three `###` curriculum subtopics and 4–7 total bullets
  per module over exhaustive detail.
- Verify the fence is balanced (one ```` ```markmap ```` open, one ```` ``` ```` close) and that every
  embedded link is in the verified ledger.

## README validation contract

Before accepting the README:

```powershell
$lines = Get-Content .\README.md
$sectionNames = @('Course Materials', 'Infos', 'Links', 'Exam & Credential')
$documentHeadings = @()
$inFence = $false
for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
    if ($lines[$lineIndex] -match '^```') {
        $inFence = -not $inFence
        continue
    }
    if (-not $inFence -and $lines[$lineIndex] -match '^## ') {
        $documentHeadings += [pscustomobject]@{
            Line       = $lines[$lineIndex]
            LineNumber = $lineIndex + 1
        }
    }
}

$requiredOrder = @(
    'Course Materials',
    'Infos',
    'Lab',
    'Links',
    'Mind Map',
    'Exam & Credential',
    'Contact'
)
$positions = @{}

foreach ($heading in $requiredOrder) {
    $positions[$heading] = ($documentHeadings |
        Where-Object Line -eq "## $heading" |
        Select-Object -First 1).LineNumber
    if (-not $positions[$heading]) {
        throw "Missing required section: $heading"
    }
}

for ($i = 1; $i -lt $requiredOrder.Count; $i++) {
    if ($positions[$requiredOrder[$i]] -le $positions[$requiredOrder[$i - 1]]) {
        throw "Required sections are out of order: $($requiredOrder[$i - 1]) before $($requiredOrder[$i])"
    }
}

$afterMindMap = @($documentHeadings |
    Where-Object LineNumber -gt $positions['Mind Map'] |
    ForEach-Object Line)
if (($afterMindMap -join '|') -ne '## Exam & Credential|## Contact') {
    throw 'Only ## Exam & Credential and ## Contact may follow ## Mind Map.'
}

foreach ($sectionName in $sectionNames) {
    $start = $positions[$sectionName]
    $end = ($documentHeadings |
        Where-Object LineNumber -gt $start |
        Select-Object -First 1).LineNumber
    if (-not $end) {
        $end = $lines.Count + 1
    }
    $section = $lines[($start - 1)..($end - 2)]

    for ($i = 0; $i -lt $section.Count; $i++) {
        if ($section[$i] -match '^#{2,4} ' -and $section[$i + 1] -eq '') {
            throw "Blank line after heading: $($section[$i])"
        }
        if ($section[$i] -match '^([-*+]|\d+[.)])\s+\[') {
            throw "Standalone link uses a list marker: $($section[$i])"
        }
        if ($section[$i] -match '^\[') {
            $next = $i + 1
            while ($next -lt $section.Count -and $section[$next] -eq '') {
                $next++
            }
            if ($next -lt $section.Count -and $section[$next] -match '^\[' -and $next -ne $i + 2) {
                throw "Links must have exactly one blank line between them: $($section[$i])"
            }
        }
    }
}

$raw = $lines -join "`n"
$map = [regex]::Match($raw, '(?s)```markmap\s+(.*?)```').Groups[1].Value
$expectedModules = <official module count>
if ([regex]::Matches($map, '(?m)^## M\d{2}\s+-').Count -ne $expectedModules) {
    throw 'Mind map module count does not match the official course.'
}
```

Replace `<official module count>` with the researched course value before running the check. Also
verify every README URL is present in the shared ledger, run `scripts/link_check.py`, and perform a
focused semantic review for module placement and curriculum coverage.
