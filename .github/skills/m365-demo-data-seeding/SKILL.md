---
name: m365-demo-data-seeding
description: >
  Inject realistic demo data into Microsoft 365 tenants for Copilot demos using
  Microsoft Graph PowerShell. Covers: Outlook email threads, Teams channel messages
  (with historical dates via Migration API), calendar events, OneDrive file uploads,
  meeting group chats, user profile configuration (JobTitle/Department by industry),
  and SharePoint sites with document libraries + custom lists + list items.
  USE FOR: seed demo data, inject emails, create Teams messages, upload files to OneDrive,
  prepare M365 Copilot demo, migration API, simulate multi-user conversations,
  populate tenant with sample data, course preparation, AB-730 demo setup,
  pre-build SharePoint sites for SharePoint Agent demos.
  DO NOT USE FOR: production data migration, Exchange migration, tenant-to-tenant migration.
license: MIT
metadata:
  author: tzyu
  version: "4.2.0"
---

# M365 Demo Data Seeding Skill

> Inject realistic demo data into Microsoft 365 tenants for Copilot demos.

> ⛔ **These tenants are shared.** This skill has **no cleanup path**: recovery never deletes.
> Before proposing any recovery, retry or "reset", read
> [Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes) and
> [Engine Status](#engine-status--which-copy-is-safe-to-re-run).

## Quick Start

```powershell
# TEMPLATE (not runnable as written) — replace <project>, <scenario-name>, <industry-key>.
# Run from a scenario folder — NO browser login needed (all App Permissions)
cd <project>\seed-data\scenarios\<scenario-name>
.\run.ps1 [-Industry <industry-key>]
```

> 🧩 **Template vs runnable snippet.** Blocks whose header says **TEMPLATE** carry `<placeholder>`
> tokens and must be filled in before use. Every other PowerShell block in this SKILL is a complete,
> runnable snippet: it parses as written and only needs the variables its own header names.

The `-Industry` parameter selects which JobTitle/Department mapping to apply (defined in each scenario's `user-profiles.json`). If omitted, the scenario's `run.ps1` declares its own default (e.g. `cathay-financial`).

For the actual scenarios currently in this workspace and their `-Industry` defaults, see the [Existing Scenarios](#existing-scenarios) section below.

### MS-4018 Customer Packs (this repository only)

For a Teams/Outlook/Excel course demo, use the local `seed-data/packs/<scenario>/pack.yaml`
and `seed-data/generator/build_scenario.py` instead of copying the unrelated SharePoint-only
MS-4022 runner. Run from the **MS-4018 repository root**:

```powershell
$env:UV_INDEX_URL = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
uv run --no-project .\seed-data\generator\build_scenario.py --pack .\seed-data\packs\ms4018-ford-auto\pack.yaml --date 20260929 --output .\seed-data\scenarios\ms4018-ford-auto-20260929
Set-Location .\seed-data\scenarios\ms4018-ford-auto-20260929
pwsh -File .\run.ps1 -PreflightOnly
# Run .\run.ps1 only after checking the preflight result and the local config.
```

The generator refuses to overwrite an existing dated scenario. Copy `config.json.example`
to the gitignored `config.json` and provide existing app credentials locally; NEVER put
credentials into a pack, issue, commit or log. `-PreflightOnly` connects to Graph and checks
existing enabled tenant users and declared surfaces with **GET only**; it does not upload,
send mail or write tenant data. A full run seeds only the pack's declared phases. No phase
creates a user, and new Customer Packs omit Phase 1 (profile PATCH) entirely. Each role UPN
must correspond to an existing enabled person; the instructor logs in as `adminUpn` only.

**Customer identity belongs in narrative content only** (email body, Teams message,
Excel sheet). Persistent Team names use `<YYYYMMDD>-<courseCode>`; Group/Site names
remain neutral course + purpose + delivery date, not customer + date. Two customers on
the same course and date cannot get different Team names by changing purpose: fail closed
in read-only preflight, do not append a suffix, and use a different delivery date. Keep
dated email subjects distinct. Never
treat a recorded ID, an exact name match or a successful GET as post-run authorization to
repair/rename/delete; see [Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes).

For generator fields, example pack, runtime boundaries and Ford trainer steps, see
[`seed-data/README.md`](../../../seed-data/README.md) and
[`DEMO/20260929-Ford/MS-4018_LiveDemo_Runbook_Ford.md`](../../../DEMO/20260929-Ford/MS-4018_LiveDemo_Runbook_Ford.md).
Chinese narrative and workbook headers for Ford are **Simplified Chinese (`zh-CN`)**;
trainer instructions are Traditional Chinese. Generated Excel sheets use named Tables,
formula columns, deterministic rows (`generate.seed`) and planted anomalies for analysis.
OneDrive receives immutable dated files, not updates in place. Outlook mail timestamps
are execution-time, not historic; Teams migrated channel messages can be historic.

## ⛔ Shared-Tenant Safety — recovery NEVER deletes

One tenant hosts many instructors, courses and months of demos. **Seeding is additive only.**
There is no cleanup mode, no "clean rerun", and no supported delete path in this skill.

### Non-negotiable prohibitions

1. **Never delete a group, team, site, channel, chat, message or file that was selected by
   `displayName`, alias/`mailNickname`, `createdDateTime`, match count, or "the latest N".**
   An exact `displayName` match is **not** ownership proof: the naming convention is
   *date + course code* for Teams (course + purpose + date for Groups/Sites); it is published
   in this skill, and any instructor sharing the
   tenant can reproduce it. Duplicates are precisely the state in which the name has **stopped**
   identifying one resource — that is the moment a name-based delete is most likely to destroy
   somebody else's demo.
2. **A recent `createdDateTime` is not ownership either.** Another instructor may have seeded
   minutes ago. "Only two matched, so the blast radius is bounded" is still someone else's data.
3. **Never purge or permanently delete directory objects** (`/directory/deletedItems/...`) to free
   an alias or `mailNickname`. It is irreversible, tenant-wide, and destroys the evidence needed
   to reconstruct what happened.
4. **Never invent seeder parameters.** The PL-7008 runner takes `-Industry`; generated MS-4018
   runners take `-PreflightOnly`. Legacy MS-4022 takes `-Date`/`-WhatIf` only. There is no
   `-Clean`, `-Reset`, `-Force`, `-Recreate` or `-Purge`; inventing one manufactures a
   destructive interface for a problem the read-only path already solves.
5. **Without a resource ID recorded by the current run you have no ownership evidence — fail
   closed.** Inspect read-only, report the ambiguity, and stop. Do not emit a delete command
   "for the operator to paste", and do not delete "just this once".
6. **No recovery or repair write may take a target discovered by name — and after the run there is
   no repair write left to make.** Delete, rename, `PATCH`, `owners/$ref`, `members/$ref` and any
   other *recovery/repair* write must consume a resource **id** the run produced **inside its own
   process, while it still held it**, or come from an ownership record the tenant owner
   authenticates separately — a mechanism this skill does **not** implement today. A run launched as
   its own process (`pwsh -File .\run.ps1`, CI, a scheduled task, another terminal) leaves nothing
   behind when it exits; and a `$global:Seed*` value that does survive a same-session invocation is
   unauthenticated shell state, not provenance (see prohibition 7). So post-run the supported
   actions are **read-only verification, evidence hand-over and additive re-seeding**. A lookup by
   `displayName`/`mailNickname` that returns **exactly one** match is not ownership evidence either:
   it proves the name is currently unique, not that the resource is yours — another instructor's
   identically named team is exactly one match too. Name lookups stay in read-only diagnosis. **No
   proof of ownership ⇒ no repair write**; report and use a non-destructive fallback.

   > *Scope: this governs manual recovery/repair. The engine's own create/reuse path is a different
   > thing — it runs the GET-only Phase 0.5 preflight, **aborts** on an ambiguous dated name, and
   > then writes against the id it created or verifiably reused inside that same run.*

7. **Nothing on disk — and nothing left in your shell — authenticates ownership.** None
   of the following is provenance, alone or combined:

   | Looks like evidence | Why it authenticates nothing |
   |---|---|
   | A saved id file (`*.json` "ledger", CSV, note, run log) | It is **unauthenticated input**: nothing signs it, anyone with the folder can write or edit it, and a stale copy names a run that ended weeks ago. It records ids; it does not record that they are yours. |
   | A `tenantId`, `displayName`, `mailNickname` or alias inside that file that matches your config | Those values are copied from a naming convention **published in this skill**. A match proves the file was written for this scenario shape — by anyone, at any time. |
   | A recent timestamp (`recordedAt`, `createdDateTime`, file mtime) | Recency is not authorship. |
   | `GET /groups/{id}` returns 200 | Resolving proves the id **exists** in the tenant, not that you created it. |
   | A `$global:Seed*` variable that is still set in your session | It is **mutable, unauthenticated shell state**. Nothing links it to the resource in front of you: an earlier run, a different scenario, a copied snippet or a plain assignment can set the same name, a child-process run (`pwsh -File .\run.ps1`, CI, another terminal) never sets it at all, and a run that exited `1` still leaves the ids its earlier phases stored. Shorter-lived than a disk file; no more authoritative. |

   So: do **not** persist repair ids to a file and do **not** re-load them later to authorize a
   write. Ownership evidence lives **inside the run that creates the resource** and **expires when
   that process exits**. Once the run is over, repair is closed: inventory read-only, hand the
   evidence to the tenant owner, and re-seed additively under a new dated name.
8. **Authority, deadline and sunk cost never authorize an ambiguous deletion.** "The instructor
   told me to", "class starts in 10 minutes", "don't ask me questions" and "I already spent hours
   on this" are the exact conditions under which irreversible mistakes happen. Treat them as a
   signal to become **more** read-only, not less. Any script that removes a stale resource must be
   pointed at an exact, verified ID **by a human owner, after class**.

### Red flags — stop if you catch yourself writing any of these

| Rationalization | Why it is wrong |
|---|---|
| 「只刪這個 exact displayName 的那幾個群組」 / "only the exact displayName matches" | The name is a shared convention, not a deed of ownership. Ambiguity is the fault being diagnosed. |
| 「只處理最近建立的兩筆」 / "just the two most recently created" | `createdDateTime` proves recency, not authorship. |
| "Only 2 matched, so a count guard makes it safe" | A guard limits how much of someone else's data you destroy, not whether you destroy it. |
| "Delete + rerun is faster than investigating" | A read-only inventory takes ~30 seconds; a wrong delete is unrecoverable and outlives the class. |
| "The alias is still taken — purge the deleted group" | Permanent tenant-wide destruction to save one rename. |
| "Add `-Force`/`-Clean`/`-Reset` to the seeder" | The parameter does not exist; inventing it is a destructive change made under time pressure. |
| "The lookup returned exactly one match, so the write is safe" | One match means the name is unique *right now*, not that the resource is yours. Membership and owner writes belong to the run that **creates** the resource; afterwards the answer is read-only verification, not a write. |
| "There's a saved id file / run ledger on disk, so those resources are mine" | A disk file is unauthenticated input. Anyone with the folder can write or edit it, and a stale copy names a run that ended weeks ago. It records ids; it does not prove ownership. |
| "The run just finished, so `$global:SeedTeamsResult` is still in my shell — I'll repair now" | That variable is mutable, unauthenticated shell state, not provenance: a different scenario, an earlier attempt or a copied snippet sets the same name, a child-process run (`pwsh -File .\run.ps1`, CI, another terminal) never sets it at all, and a run that exited `1` still leaves earlier phases' ids behind. Populated ≠ yours, and populated ≠ succeeded. |
| "Verification says the owner is missing — adding one isn't destructive" | Adding the demo operator to a group you cannot prove is yours hands your account somebody else's live demo (or theirs to you), and it is immediately user-visible. A missing owner means **the run is incomplete**: report it and re-seed additively. |
| "The file's `tenantId`/name matches and the id still resolves — that's verified" | The fields are copied from a convention this skill publishes, and a 200 from `GET /groups/{id}` proves the id exists, not that you created it. Neither is a signature. |
| "I'll rename the branded group I found by displayName — renaming isn't destructive" | Relabelling someone else's live demo mid-course is user-visible damage. A `PATCH` is a write, and post-run you have no ownership evidence for it — fix the label in the scenario JSON and let the next run create it right. |
| "The instructor owns the tenant, so consent is implied" | Consent to seed is not consent to delete unidentified resources belonging to other people. |

### The 10-minute runbook (read-only first)

**Step 0 — load the paged read helper. Every collection example in this SKILL uses it.**

```powershell
# Follow @odata.nextLink until a Graph collection is exhausted. GET only — this helper never writes.
# Same contract as Get-SeedGraphCollection in the hardened engine (engine/Seed-GraphRead.ps1):
# a truncated first page would make complete data look missing and trigger a duplicate write.
function Get-GraphPaged {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [int]$MaxPages = 50
    )
    $items = @()
    $next  = $Uri
    $page  = 0
    while ($next) {
        $page++
        if ($page -gt $MaxPages) { throw "Collection '$Uri' exceeded $MaxPages pages; refusing to loop." }
        $response = Invoke-RestMethod -Method GET -Headers $Headers -Uri $next
        $props    = @($response.PSObject.Properties.Name)
        if ($props -contains 'value') { $items += @($response.value) }
        $link = $null
        if ($props -contains '@odata.nextLink') { $link = $response.'@odata.nextLink' }
        if ($link -and $link -eq $next) { throw "Self-referencing @odata.nextLink on '$Uri'; refusing to loop." }
        $next = $link
    }
    # ONE normalization boundary: this function always returns an array, so callers must NOT wrap
    # the result in @(...) again — see PowerShell Implementation Pitfalls.
    return , @($items)
}
```

**Step 1 — read-only inventory. GET only; nothing below this line writes.**

> 🔎 A name lookup is **diagnosis, never authorization**. The ids printed here tell you *what
> exists*; they do not tell you what is *yours*, so they must never be pasted into a write, saved as
> an "ownership record", or re-read later to justify one. Membership and owner writes belong to the
> run that creates a resource, inside its own process; once that run has finished, nothing available
> to you — a saved file, a name hit, or a variable still set in your shell — can authorize one. See
> [Post-Run Verification](#-post-run-verification--admin-must-be-in-every-resource-the-run-created).

```powershell
# READ-ONLY inventory of an ambiguous dated resource. No POST / PATCH / DELETE anywhere here.
# Requires Get-GraphPaged from Step 0 and an app token in $global:AccessToken.
$token      = $global:AccessToken                 # never print, log or paste the token
$authScheme = 'Bearer'
$h          = @{ Authorization = "$authScheme $token" }   # composed from variables only
$name       = 'PL-7008 IT Helpdesk — 2026-08-31'  # the exact declared teamDisplayName

# Build the OData literal FIRST, then escape (see PowerShell pitfalls: no -replace inside a
# static-method argument list).
$literal = $name.Replace("'", "''")
$filter  = [Uri]::EscapeDataString("displayName eq '$literal'")
$uri     = "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,mailNickname,createdDateTime"
$found   = Get-GraphPaged -Headers $h -Uri $uri   # paged; already an array, do not re-wrap

foreach ($g in $found) {
    $owners = Get-GraphPaged -Headers $h -Uri "https://graph.microsoft.com/v1.0/groups/$($g.id)/owners?`$select=userPrincipalName"
    $chans  = Get-GraphPaged -Headers $h -Uri "https://graph.microsoft.com/v1.0/teams/$($g.id)/channels?`$select=id,displayName"
    [pscustomobject]@{
        Id       = $g.id
        Created  = $g.createdDateTime
        Alias    = $g.mailNickname
        Owners   = ($owners.userPrincipalName -join ', ')
        Channels = ($chans.displayName -join ', ')
    }
}
```

**Step 2 — verify content, still read-only.** Run the scenario's Phase 0.5 preflight
(`engine/Invoke-SeedPreflight.ps1`, GET-only) or the readers in `engine/Seed-GraphRead.ps1`. It
reports channel cardinality and normalized message/reply hashes and **throws on ambiguity** —
that abort is the correct outcome, not a bug to work around.

**Step 3 — decide from the table. Every row is non-destructive.**

| Finding | Action |
|---|---|
| Exactly one dated resource, content complete | Nothing to fix. Deliver the class against it; a rerun of the hardened PL-7008 engine is a no-op (see [Engine Status](#engine-status--which-copy-is-safe-to-re-run)). |
| Exactly one, content partial | Let the hardened engine's preflight abort and report. Deliver from the complete surfaces; reconcile after class. |
| **Two or more matches** | **Do not delete anything.** Deliver from the complete surfaces, or seed **additively** under a new unique name (bump the dated suffix in `config.json`, e.g. `… — 2026-08-31b`, plus a matching new site alias) so no existing resource is touched. Record the new IDs. |
| Ownership genuinely unknown | Stop. Hand over the Step 1 evidence table and let the tenant owner decide **after** class. |

**Non-destructive class fallbacks, in order of preference**

1. **Deliver from the surfaces that are already complete.** SharePoint documents, OneDrive files
   and Outlook threads ground Copilot perfectly well without a complete Teams channel.
2. **Additive re-seed under a new dated suffix** (new `teamDisplayName` + new site alias). Costs
   one extra group; destroys nothing; leaves the ambiguity for a human to resolve later.
3. **Demo the Copilot/agent behaviour against a backup scenario site** you own.
4. **Swap the agenda**: teach the lecture segment or another lab first, finish seeding afterwards.
   Losing five minutes of lab order is recoverable; deleting a colleague's tenant data is not.

> 🧾 **Ownership evidence lives inside the run — not on disk, and not in your shell.** The hardened
> PL-7008 `run.ps1` prints a `Resource ledger` block and sets `$global:SeedTeamsResult`,
> `$global:SeedSharePointResults` and `$global:SeedEmailResults` **inside its own process**, for the
> phases that follow. Once it exits (`exit 0`; `exit 1` on a failed phase) those values are either
> gone with the process — the normal case for `pwsh -File .\run.ps1`, CI or a second terminal — or,
> at best, left lying in the shell that launched it as unauthenticated state that nothing signs and
> that a failed run populates just as happily. **Neither case authorizes a write.** The printed
> ledger is a **human report**: hand it to the tenant owner, never re-type an id from it into a
> write, and never save it as an "ownership record", because a saved id list is unauthenticated
> input, indistinguishable from a stale, borrowed or edited copy, and this skill implements no way to
> authenticate one. Run finished ⇒ no repair write: verify read-only and re-seed additively (see
> [Post-Run Verification](#-post-run-verification--admin-must-be-in-every-resource-the-run-created)).

## Engine Status — which copy is safe to re-run

A shared SKILL can describe **different copies of the engine**. Idempotency and fail-fast are
properties of a *patched copy*, not of this document. Always confirm which copy you are running
before promising a safe rerun.

| Engine copy | Status | Safe to re-run? |
|---|---|---|
| `MoneyYu/MS-4018` → `seed-data/engine` + generated `ms4018-ford-auto-20260929` | First live run: five Excel files and one Outlook mail were written; reply lookup failed across mailbox-local `conversationId`s, so Teams never ran. The original scenario is partial. | ❌ Do not rerun the original scenario or delete its evidence |
| `MoneyYu/MS-4018` → `seed-data/engine` + generated `ms4018-ford-auto-workshop-b-20260929` | Separate neutral names and new first-message subjects. Cross-mailbox reply fix passes the offline suite (**472 passed, 0 failed**); live write and idempotency for this scenario have **not** been verified. | ⚠️ Requires read-only preflight, write approval, live verification, and a complete-state preflight before any rerun |
| `MoneyYu/PL-7008` → `seed-data/engine` + scenario `pl7008-it-helpdesk-20260831` | **Hardened and live-verified** (2026-08-31): read-only Phase 0.5 preflight, email/team/channel/message idempotency, exact-name file skip, fail-fast phase wrapper, Graph write responses suppressed, `seed-data/tests/Test-SeedEngine.ps1` offline suite | ✅ Yes — two consecutive runs produced identical tenant state |
| `lettucebo/Work` → `20260507-PL7008-CopilotStudio/seed-data/engine` (legacy) | **Unpatched — unsafe for reruns.** Missing: email idempotency (re-POSTs threads), team/channel/message idempotency (unconditional create → `ChannelNameAlreadyExist` and duplicate content), read-only preflight content verification, fail-fast (a phase can fail and the run still prints success), upload-response suppression and exact-name file skip (re-uploads every file and prints the pre-authenticated download URL) | ❌ No |

**Rules while the legacy copy is unpatched**

- **Do not describe the Work legacy engine as idempotent** anywhere — docs, comments, chat or
  commit messages. Only the PL-7008 copy is fixed and live-verified.
- Only its already-safe phases may be run, and only with deliberate operator review of what each
  phase will write. Never rerun its email or Teams phases against a tenant that already holds
  that scenario's data.
- When the fixes are ported, port the **tests** with them and re-verify on a live run before
  updating this table.
- Calendar (Phase 5) and Meeting Chats (Phase 6) are **unhardened and unused** in the PL-7008
  scenario. They carry none of the idempotency guarantees above; do not enable them without the
  same TDD treatment.

## Execution Flow (phases are per-scenario, not a fixed count)

Each scenario's `run.ps1` declares which phases it runs. **A scenario is not required to run every
phase, and a phase must never be added just to reach a "complete" phase count** — an unused phase
seeds resources nobody verifies.

**MS-4018 generator contract:** Ford selects 0→0.5→2→3→4; the migrated MS-4022
Product Support pack selects 0→0.5→7. A `-PreflightOnly` invocation runs 0→0.5
only, validating existing enabled users and the selected surfaces before any
Graph write or lab download. `run.ps1` must never call `/users` with POST or
`/invitations`; new customer scenarios do not run Phase 1 or create accounts.

| Phase | What | API | Auth | Idempotency key / skip rule |
|---|---|---|---|---|
| 0 | Connect (app token only) | OAuth2 client credentials | App | — |
| **0.5** | **Preflight collision report — read-only** | GET groups / channels / messages / Inbox | App | Aborts before any write on duplicate name, duplicate alias, or partial/extra/ambiguous content |
| 1 | Update user JobTitle/Department | PATCH /users | App | Re-asserts declared tenant-default values (creates nothing) — see the [Phase 1 caution](#-tenant-identity-neutrality--never-customer-brand-persistent-identities): those UPNs are shared personas |
| 2 | Upload files to OneDrive | PUT /drive/root | App | Exact filename already in the target folder → skip |
| 3 | Send email threads | POST /sendMail + /reply | App | Exact declared subjects present in the Inbox thread → skip |
| 4 | Create Teams channels + messages | Migration API | App | Exact team `displayName` + channel name + normalized content hash of every message/reply |
| 5 | Create calendar events | POST /events | App | *(unhardened — opt-in)* |
| 6 | Create meeting group chats + messages | startMigration (beta) + POST messages | App | *(unhardened — opt-in)* |
| 7 | Pre-build SharePoint sites + lists + items *(optional)* | POST /groups, /sites/{id}/lists, /lists/{id}/items | App | Group `mailNickname`, list `displayName`, item `Title`, exact document filename |

**Scope of the skip rules above** — they describe the **hardened `MoneyYu/PL-7008` engine**, and
they are the required contract for any port. They are not a property of this document: the legacy
`lettucebo/Work` copy implements none of them, so no row above may be read as a rerun guarantee for
that copy (see [Engine Status](#engine-status--which-copy-is-safe-to-re-run)).

**Fail-fast contract** — every phase runs inside a wrapper that turns any unexpected error into a
nonzero process exit code and an explicit "PHASE FAILED" banner. A run that printed a success
banner while a phase failed is a bug: **never let a phase log-and-continue**, and never treat
"the script finished" as "the data is correct" — verify the surfaces.

**Fail-closed contract** — only known idempotent conditions are absorbed (`already exists`,
`already completed`, `not in migration`, `404 itemNotFound` for a folder that has not been created
yet). Everything else throws. In particular a `403`/`429`/unreadable response must **never** be
converted into "the resource is absent", because an empty read makes complete data look missing
and triggers a re-write.

**Verify only what the scenario creates.** Post-run verification covers the surfaces the run
actually seeded (for PL-7008: user profiles, OneDrive, email, Teams, SharePoint). Do not assert on
phases the scenario skips by design. Verification is **read-only**: the run — not the operator —
is what puts `adminUpn` into a resource, so a missing owner is a finding to report, never a write
to make afterwards (see
[Post-Run Verification](#-post-run-verification--admin-must-be-in-every-resource-the-run-created)).

## Architecture: Engine + Scenario

```
seed-data/
├── engine/                              ← Reusable logic (do NOT modify per customer)
│   ├── Connect-GraphApp.ps1             # App token via client credentials
│   ├── Seed-Idempotency.ps1             # Pure helpers: content normalization/hashing, skip-vs-create
│   │                                    #   verdicts, known-idempotent error classifiers
│   ├── Seed-GraphRead.ps1               # GET-only paged readers (drive, Inbox, channels, messages)
│   ├── Invoke-SeedPreflight.ps1         # Phase 0.5: read-only collision + content report, aborts before writes
│   ├── Invoke-SeedUserProfiles.ps1      # Update user JobTitle/Department
│   ├── Invoke-UploadFiles.ps1           # OneDrive file upload (supports nested subfolders)
│   ├── Invoke-SeedEmails.ps1            # Outlook email threads
│   ├── Invoke-SeedTeamsChannel.ps1      # Teams Migration API
│   ├── Invoke-SeedCalendar.ps1          # Calendar events (relative dayOffset) — unhardened, opt-in
│   ├── Invoke-SeedMeetingChats.ps1      # Group chats (startMigration API) — unhardened, opt-in
│   └── Invoke-SeedSharePoint.ps1        # Phase 7: M365 Group + Site + Doc Library + Lists + Items (idempotent)
├── tests/
│   └── Test-SeedEngine.ps1              # Offline unit + AST suite (no live Graph calls, no Pester)
├── scenarios/
│   └── <scenario-name>/                 # one folder per course + neutral purpose + delivery date
│       ├── config.json                  # App credentials + role→UPN mapping (GITIGNORED — never committed)
│       ├── config.json.example          # Committed placeholder copy of the shape above
│       ├── user-profiles.json           # Industry profiles (JobTitle/Department mapping)
│       ├── emails.json                  # Email threads
│       ├── teams-messages.json          # Teams channels + messages
│       ├── calendar-events.json         # Events (dayOffset relative)
│       ├── meeting-chats.json           # Group chats
│       ├── files-manifest.json          # OneDrive upload list (supports `subfolder` field)
│       ├── sharepoint-sites.json        # (Phase 7 only) SharePoint sites + lists + items
│       └── run.ps1                      # One-click execution (fail-fast phase wrapper)
```

In **MS-4018 only**, `seed-data/generator/build_scenario.py` consumes `seed-data/packs/*/pack.yaml`
validated against `generator/pack.schema.json` and writes the files required by selected
surfaces. Ford emits `emails.json`, `teams-messages.json`, `files-manifest.json`, five
Excel workbooks, a runner and a placeholder config. The migrated MS-4022 pack emits a
SharePoint-only runner and `sharepoint-sites.json`. The old engine is preserved under
`seed-data/legacy/ms4022-engine/`; the original scenario data is retained, but its
runner refuses live execution because its format is incompatible with the new engine.
Generated scripts are not written into a nonempty destination. The new project-specific
tests live under `seed-data/generator/tests/`.

For an MS-4018 scenario, author a new Customer Pack and generate to a **new neutral dated
destination**. For legacy consumers without this generator, copy an existing scenario and edit
the JSON and runner, keeping its engine's actual supported phases in mind. A name is only an
idempotency key, not ownership proof. Reusing a prior team's name binds you to its existing
tenant state and must not authorize a write by itself.

> 🧪 **TDD is mandatory for engine changes.** Extend `tests/Test-SeedEngine.ps1` first, capture the
> RED run, implement, capture GREEN, and re-run the whole suite before any live run. The suite is
> offline: it exercises the pure helpers and asserts source-level properties via AST (e.g. that no
> Graph write call site can reach stdout).

## Prerequisites

### 1. Azure AD App Registration

Entra admin center → App registrations → New → "M365-DemoSeeder"

**Application Permissions** (Grant admin consent) — **all from Microsoft Graph, NOT SharePoint API**:

| Permission | Used For |
|---|---|
| `Mail.Send` | Send emails as any user |
| `Mail.ReadWrite` | Read mailboxes for reply chain |
| `User.Read.All` | Resolve UPNs to user IDs |
| `User.ReadWrite.All` | Update user JobTitle/Department |
| `Group.ReadWrite.All` | Create Teams (groups) + M365 Groups (Phase 7) |
| `TeamMember.ReadWrite.All` | Add members to teams (incl. the `roles ["owner"]` POST) and read team membership for the reuse ownership proof |
| `Channel.Create` | Create channels |
| `Teamwork.Migrate.All` | Migration API (historical dates) |
| `Calendars.ReadWrite` | Create calendar events |
| `Files.ReadWrite.All` | Upload to OneDrive + SharePoint document library |
| `Chat.Create` | Create group chats |
| `Chat.ReadWrite.All` | Read chats for message injection |
| `OnlineMeetings.ReadWrite.All` | Online meeting management |
| **`Sites.FullControl.All`** 🆕 | **Phase 7: create SharePoint List / columns / items (REQUIRED)** |
| `Sites.Manage.All` 🆕 | Phase 7 backup |
| `Sites.ReadWrite.All` 🆕 | Phase 7 backup |

> ⚠️ **CRITICAL: Microsoft Graph vs SharePoint API confusion**
>
> In Azure Portal → API permissions, there are **two separate API surfaces** that both have `Sites.*` permissions:
> - **Microsoft Graph** API ID `00000003-0000-0000-c000-000000000000` → **THIS is what we use**
> - **SharePoint** (REST) API ID `00000003-0000-0ff1-ce00-000000000000` → **NOT what we use**
>
> Granting `Sites.*` under "SharePoint" alone will NOT make Phase 7 work — the token roles claim will be empty for Graph endpoints. **Always grant under "Microsoft Graph"**.
>
> Verify the actual roles in your token:
> ```powershell
> # Set $tid / $cid / $cs first from the scenario's config.json (tenantId / clientId / clientSecret).
> # $cs and $tk are live credentials: never echo, log or paste them.
> $tk = (Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tid/oauth2/v2.0/token" -Body @{client_id=$cid;client_secret=$cs;scope='https://graph.microsoft.com/.default';grant_type='client_credentials'}).access_token
> $payload = $tk.Split('.')[1]; $padded = $payload + ('=' * ((4 - $payload.Length % 4) % 4))
> ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($padded.Replace('-','+').Replace('_','/'))) | ConvertFrom-Json).roles | Sort-Object
> ```

**Grant all 16 at once** using delegated admin (idempotent script):
```powershell
# TEMPLATE (not runnable as written) — replace <CLIENT_ID> with your app registration's client id.
Connect-MgGraph -Scopes "Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Directory.ReadWrite.All"
$appSp = Get-MgServicePrincipal -All -Filter "appId eq '<CLIENT_ID>'"
$graphSp = Get-MgServicePrincipal -All -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$perms = @(
    "Mail.Send","Mail.ReadWrite","User.Read.All","User.ReadWrite.All",
    "Group.ReadWrite.All","TeamMember.ReadWrite.All","Channel.Create","Teamwork.Migrate.All",
    "Calendars.ReadWrite","Files.ReadWrite.All","Chat.Create","Chat.ReadWrite.All",
    "OnlineMeetings.ReadWrite.All",
    "Sites.FullControl.All","Sites.Manage.All","Sites.ReadWrite.All"   # Phase 7 required
)
foreach ($p in $perms) {
    $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $p -and $_.AllowedMemberTypes -contains "Application" }
    if ($role) {
        # -All pages the assignment collection; without it a later page hides an existing grant.
        $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id -All |
                    Where-Object { $_.AppRoleId -eq $role.Id -and $_.ResourceId -eq $graphSp.Id }
        if (-not $existing) {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id -PrincipalId $appSp.Id -ResourceId $graphSp.Id -AppRoleId $role.Id
        }
    }
}
```

### 2. Auth Model — All App Permissions (No Browser Login)

All phases use **Application Permissions only**. No delegated login or browser popup needed.

| Operation | Auth Type | Permission |
|---|---|---|
| Send email as UserA | **App** | `Mail.Send` |
| Teams Migration API | **App** | `Teamwork.Migrate.All` |
| Update user profile | **App** | `User.ReadWrite.All` |
| Meeting group chats | **App** | `Teamwork.Migrate.All` (startMigration beta API) |
| Create group chats | **App** | `Chat.Create` |
| Calendar events | **App** | `Calendars.ReadWrite` |

## Industry User Profiles (`-Industry` parameter)

The seeder uses a **conglomerate-with-multiple-business-units** model: each industry profile defines a JobTitle/Department mapping for a specific group of tenant accounts. Pre-existing accounts in the demo tenant are kept; only `JobTitle` and `Department` are overwritten.

### Industry profile pattern

`user-profiles.json` per scenario defines one or more industry profiles:

```jsonc
{
  "industries": {
    "<industry-key>": {
      "name": "事業處中文名",
      "profiles": {
        "<RoleName>": {
          "upn": "user@<tenant>.com",
          "jobTitle": "...",
          "department": "事業處 / 部門"
        }
      }
    }
  }
}
```

### When adding a NEW industry key

You MUST update **two `[ValidateSet(...)]` declarations** otherwise Phase 1 fails with `Cannot validate argument on parameter 'Industry'`:

1. `seed-data/engine/Invoke-SeedUserProfiles.ps1` — `[ValidateSet(...)]` on `-Industry`
2. `seed-data/scenarios/<scenario>/run.ps1` — `[ValidateSet(...)]` on `-Industry`

### Demo Account convention

Each scenario's `config.json` declares two reserved UPNs:
- `demoUserUpn` — the primary "main character" of the demo (e.g. PM); files upload here, team co-owner
- `adminUpn` — the **single demo operator account** used by the instructor at runtime

The engine auto-elevates `adminUpn` to **team owner** (not just member), CCs every email, attends every calendar event, joins every meeting chat, and owns every Phase 7 SharePoint site. **Do NOT assign `adminUpn` to any business role** — it is the observer.

> 📚 **Tenant-specific directory** (account list, role mappings, scenario-by-scenario assignments) lives in repo `docs/` rather than this SKILL. See for example [`docs/tenants/moneyyu-tenant-directory.md`](../../../docs/tenants/moneyyu-tenant-directory.md) for the `moneyyu.com` demo tenant layout.

### 🚫 Tenant Identity Neutrality — NEVER customer-brand persistent identities

The tenant's **identity layer** (user profile `jobTitle`/`department`, Group `displayName`/`mailNickname`, Site `displayName`/alias) must stay **customer-neutral and reusable**. Only narrative content (email bodies, calendar locations, file contents, list items) may carry the customer storyline.

**Rules**

| Surface | ✅ Generic / Dated | ❌ Customer-branded |
|---|---|---|
| User `jobTitle` | `數位轉型專案經理` | `國泰人壽 商品企劃協理` |
| User `department` | `金融事業處 / 數位金融部` | `國泰金控 / 數位金融處` |
| Team `displayName` | `20260515-MS-4019` | `國泰集團 — MS-4019 Demo` |
| SharePoint site alias | `ms4019-compliance-20260515` | `cathay-compliance` |
| SharePoint site `displayName` | `MS-4019 — 法遵與風險 — 2026-05-15` | `國泰金控 — 法令遵循處` |

**Conventions**

- Use **date + course code** (`YYYYMMDD-<courseCode>`) for Teams. For Groups/Sites, keep the existing neutral course + purpose + date convention. A second Team for the same course/date needs a different delivery date; a different purpose does not change its name.
- Use **tenant-default generic department names** for `user-profiles.json` profiles. They typically already exist in the tenant directory (e.g. moneyyu: `金融事業處 / 法令遵循部`). **The seeder's Phase 1 should be a no-op** that re-asserts those defaults — never a customer-specific override.
- Email signatures, calendar locations, list items, and document contents **may** reference the customer (`國泰金控總部 18F`, signature `Christie Cline / 國泰人壽`). This is storytelling, not identity.

**Why this matters**

- One tenant hosts **many demos across months / customers**. Yesterday's "國泰金控 法令遵循處" labels leak into today's banking demo via Outlook GAL, Teams profile cards, Copilot Researcher results, and SharePoint home.
- Resetting `jobTitle`/`department` after each demo is fragile (easy to forget). **Don't override in the first place.**
- Group/Site `displayName` is the user-visible label across SharePoint home / Teams sidebar. Date-stamped names sort naturally and let multiple instructors share one tenant without collision.

**If a previous run left customer-branded labels**, the *user* `jobTitle`/`department` values can be
re-asserted by Phase 1, which PATCHes exactly the UPNs the scenario declares — its own identity
contract.

> ⚠️ **Phase 1 caution — those UPNs are shared personas.** The scenario JSON names real tenant
> accounts that other instructors and other courses reuse, so a Phase 1 run rewrites *their* profile
> cards too. Run it **only** to re-assert the documented tenant-neutral defaults for those accounts.
> Never use it to push a customer-branded title, and never let it overwrite a colleague's active
> branded demo: read the current `jobTitle`/`department` first, and if they belong to a demo that is
> still running, that is someone else's live data. **If you are unsure, skip Phase 1** — it is a
> neutrality guarantee for the accounts this scenario declares, not a tenant cleanup tool. A demo
> that keeps yesterday's titles for one more day is recoverable; a live demo relabelled mid-course
> is not.

**Group and Site labels are different**, because no file declares which group id is yours, and once
the run that created it has finished nothing available to you authenticates one. Rename such a
resource **only** from an ownership record the tenant owner authenticates separately — which this
skill does not implement.

**So in practice: do not rename the existing group or site at all.** Never search
`displayName`/`mailNickname` for a branded label and PATCH whatever comes back, and never restore
the id from a saved file or from a `$global:Seed*` variable still sitting in your shell: a name hit
is diagnosis, and both a file and a leftover variable are unauthenticated input, so either path can
relabel another instructor's live demo. Leave the old resource untouched, report it to the tenant
owner, fix the label in the scenario JSON, and create the next demo **additively under a new dated,
customer-neutral name** so the next run creates it correctly. **Deleting is never a repair — and
after the run, neither is renaming** — see
[Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes).

### Where the exact identities live (not in this SKILL)

This skill is generic and is copied into several repos. **Never hard-code one tenant's people,
UPNs, job titles or departments here.** Each consuming repo owns its own identity contract:

| Artifact | Owns | Rule |
|---|---|---|
| `scenarios/<name>/user-profiles.json` | **Canonical** UPN → `jobTitle` / `department` tuples | Single source of truth; the seeder writes exactly these values |
| Repo instructions (e.g. `.github/copilot-instructions.md`) | The same tuples, repeated verbatim | So a future agent editing docs cannot invent or drift a title; list the operator/`adminUpn` **explicitly as excluded** — the demo operator is never assigned a business role |
| This SKILL | The *pattern* only | Generic, customer-neutral naming rules and conventions |

Repeating the tuples in repo instructions is deliberate redundancy: the JSON stays canonical, and
the instructions stop drift at authoring time. Whenever the two disagree, the scenario JSON wins
and the instructions must be corrected to match it.

## API Reference & Verified Limitations

### Idempotency & state verification (the contract every hardened phase follows)

Idempotency is **read-then-decide**, never "POST and hope". A script that unconditionally POSTs is
not idempotent no matter what its header comment claims — check the code, not the docstring.

- **Decide from observed state**: read the target surface first, compare it to the declared set,
  then create only what is missing. The three verdicts are `Create` / `Skip` / `Abort`.
- **Compare content by normalized hash**, not by object identity or timestamp: strip HTML/markup
  noise, collapse whitespace, normalize Unicode, then SHA-256. This is what makes "the same message"
  recognizable across runs.
- **Page every collection read** (`@odata.nextLink`) and cap the page count. A truncated first page
  makes a complete team or thread look partial and triggers a duplicate write. The engine's reader
  is `Get-SeedGraphCollection` (`engine/Seed-GraphRead.ps1`); ad-hoc scripts use the `Get-GraphPaged`
  helper in [Shared-Tenant Safety Step 0](#-shared-tenant-safety--recovery-never-deletes). A single
  unpaged `Invoke-RestMethod` on a collection is a bug even in a throwaway verification snippet.
- **Absorb only known idempotent conditions** (`already exists`, `already completed`,
  `not in migration`, `already been finalized`, `404 itemNotFound` for a not-yet-created folder).
  Everything else throws.
- **Never turn an error into "absent"**: `403`, `429` and unparseable responses must throw. An
  empty result invented from a failed read causes the engine to re-create data that already exists.
- **Ambiguity aborts.** More than one resource matching the declared name/alias, or content that is
  partial, duplicated or has extra items, stops the run *before* any write — it never triggers
  automatic cleanup.
- **Error text**: pass the full PowerShell `ErrorRecord` (`$_`), not `$_.Exception.Message`. Graph
  puts the actionable code and message in `ErrorDetails.Message`; combine
  `ErrorDetails.Message` + `Exception.Message` + `InnerException.Message` so classifiers and logs
  see the whole payload. Classifying on a truncated message silently mislabels errors.

### Email Threading
- `receivedDateTime` is **read-only** — emails show execution date
- Use `Send` → locate the first message in the admin Inbox by **exact subject** → use its
  `internetMessageId` to locate the same message in the next sender's Inbox → reply using that
  sender's mailbox-local `id`. After every reply, find exactly one **new** message in the admin
  Inbox conversation and use its `internetMessageId` for the following sender.
- **Never use an admin-local `conversationId` to search another mailbox.** The first Ford live
  message had different `conversationId`s in the admin and recipient Inboxes but the same
  `internetMessageId`; waiting longer did not help. Subject lookup is only for the initial mail,
  not for cross-mailbox replies.
- Poll within a bounded 60-second budget; only post-send Inbox GET errors 429/503/504 or
  explicit timeouts can be retried, honoring `Retry-After`. 4xx authorization errors,
  ambiguous messages and missing stable IDs abort. Never retry a mail POST or repair a
  partially sent thread.
- All recipients must be **within tenant** (external = "Message Blocked")
- **State model (idempotency)**: snapshot the **Inbox only**, paged, then match the declared
  subjects **exactly and in memory** against that snapshot. Do not push the match into an OData
  `$filter`/`$search`: Exchange degrades or rejects those combinations (see `InefficientFilter`
  below), and the seeded subjects are CJK strings that must compare as exact literals. Then:
  - 0 of the declared messages present → send the thread
  - exactly the declared set present → **skip** (re-sending would duplicate a thread whose
    timestamps cannot be corrected afterwards)
  - partial or more than declared → **abort** and report
- **Deleted Items and Sent Items do not count.** The unscoped `/users/{upn}/messages` collection
  includes them, so a thread the operator deleted would still look "complete" and be skipped, and a
  Sent copy would make a missing Inbox thread look present.

### Teams Migration API
- Team creation in migration mode **cannot include members** — add after completeMigration
- **Must complete ALL channels (including General)** before completing team
- `createdDateTime` is writable — messages show historical dates ✅
- Supports `mentions` array: `"mentions": ["RoleName"]` in JSON + `<at id="N">DisplayName</at>` in bodyHtml
- Order: Create team → Create channels → Post messages → Complete channels (all) → Complete team → Add members
- `adminUpn` is added as **owner** (not member) alongside `demoUserUpn`

**Preflight before any write (Phase 0.5)** — the Teams state check runs *before* Phase 1, so a run
that would abort at Phase 4 never PATCHes a profile or uploads a file first:

- Exactly **one** group may match the declared `teamDisplayName`; two or more → abort (never
  "pick the newest", never delete — see [Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes)).
- Channel **cardinality is exact**: the declared channels plus `General`, nothing else.
- Content is compared as **paged top-level messages** plus **replies fetched separately per
  message** (replies are not included in the top-level collection), matched by normalized content
  hash. Report `missingTop / missingReplies / extraTop / extraReplies`.
- Complete → the Teams phase skips messages. **Partial, extra, missing or ambiguous → abort.**
  There is deliberately **no automatic resume**: after `completeMigration` the Migration API cannot
  reliably accept historical messages, so an automatic "repair" produces duplicates with wrong
  timestamps. A human resolves an incomplete dated team.

**`completeMigration` must be idempotent at both levels.** A run that posted messages but died
before completing leaves the team in migration mode — where membership cannot be added — so every
path (including a reused, already-complete team) re-posts both `POST /teams/{id}/channels/{cid}/completeMigration`
and `POST /teams/{id}/completeMigration`. Graph answers an already-finished migration with several
wordings, all of which mean success:

- `... has already been completed` (documented)
- `... is not in migration [mode]` (documented)
- `... has already been finalized` (observed live, 2026-08-31)

Match all three, treat them as success, and **throw on anything else**.

**Reading channel messages needs a different permission than writing them.** Migration writes work
with `Teamwork.Migrate.All`, but `GET /v1.0/teams/{id}/channels/{cid}/messages` requires
`ChannelMessage.Read.All` / `ChannelMessage.Read.Group`, which is **not** in the permission set
above. Options: consent to the read permission, or fall back to the identical **beta** collection
— but only for the exact "missing channel-message read permission" 403. Any other 403 (or any
other error) must throw; a blanket `catch { $beta }` hides real authorization problems. Beta
carries no compatibility guarantee, so record the fallback in the run log.

### Calendar Events
- Use `dayOffset` for relative dates — events always within 1 week of execution
- Past and future dates both work ✅
- `isOnlineMeeting: true` + `onlineMeetingProvider: "teamsForBusiness"` for Teams meetings

### Meeting Chats (startMigration API)
- Uses **beta `startMigration` API** — NO delegated login required
- Flow: Create normal chat → `POST /beta/chats/{id}/startMigration` → inject messages with `from.user` → `POST /beta/chats/{id}/completeMigration`
- Each message shows the **actual sender's avatar and display name** ✅
- Supports `mentions` array (same format as Teams channels: `<at id="N">DisplayName</at>`)
- After migration: remove + re-add members with `visibleHistoryStartDateTime` to ensure message visibility
- Fallback: if `startMigration` fails, sends messages with `[SenderName (Title)]` prefix (all show as app)
- `dayOffset` + `startTime` control message timestamps (relative to execution date)

### OneDrive
- Admin may have multiple Drives — use `/drive/root:` (default)
- URL-encode Chinese filenames
- Files ≤4MB: simple upload; >4MB: upload session with 4MB chunks
- **Subfolder support** — `Invoke-UploadFiles.ps1` accepts both `"localName": "S1/file.docx"` (path embedded) and `"localName": "file.docx", "subfolder": "S1_xxx"` (flat local + grouped on OneDrive). Subfolders are auto-created (idempotent via children endpoint).
- Path encoding: split by `/`, EscapeDataString each segment, rejoin with `/` (preserve separator while encoding Chinese / spaces)

#### File upload idempotency & safety (applies to OneDrive *and* the Phase 7 document library)

- **Never print a Graph write response.** The upload `PUT` returns a DriveItem carrying a
  **pre-authenticated download URL** (a capability URL with an embedded token that downloads the
  file with no sign-in). Left on the pipeline it lands in the run log and in any pasted evidence.
  Pipe every write to `Out-Null` (or assign it), and keep a test that fails when a new write call
  site can reach stdout. If a log already contains one, redact the whole property and treat the URL
  as burned.
- **Snapshot the target folder first, then skip files whose exact name is already stored.** A `PUT`
  of identical bytes is *not* a no-op: the drive stores a new version and re-serializes Office
  containers, so file sizes drift between runs and the "nothing changed" proof disappears. Upload
  only the missing files — a requirement for any hardened copy, not a description of whatever
  engine you happen to be running (the legacy `lettucebo/Work` copy re-uploads every declared file).
- **404 / `itemNotFound` means "absent"** — that is the only error an emptiness check may absorb
  (the folder simply is not created yet). **`403`, `429`, and any unreadable response must throw**;
  an error silently converted to "empty folder" re-uploads every declared file.
- **A filename is not content equality.** Same-name-skip is correct for **immutable dated demo
  assets** (that is what these scenarios ship) and is the wrong rule for content that changes: if an
  operator edited a file in place, re-uploading would destroy their edit, so preserve it and require
  a deliberate human decision instead. Never work around a name clash with a case-only variant
  (`Policy.docx` vs `policy.docx`) — the drive treats it as one name and the demo shows the wrong
  file.

### SharePoint Sites (Phase 7)

**Workflow** — as implemented in the **hardened `MoneyYu/PL-7008` engine**, where every step is
read-then-decide, so re-running *that copy* is a no-op. This is the required contract for a port,
not a claim about any other copy: on the legacy `lettucebo/Work` engine do **not** re-run Phase 7
blind — abort and seed under a new dated alias instead (see
[Engine Status](#engine-status--which-copy-is-safe-to-re-run)).
```
For each site config:
  1. GET /groups?$filter=mailNickname eq '...'  → reuse if exists
  2. POST /groups (groupTypes=[Unified], owners@odata.bind=[admin])
     … ⚠️ Owner is REQUIRED — App-only POST without owner = anonymous group, SharePoint site never provisions
  3. Poll /groups/{id}/sites/root every 5s for up to 180s  → wait for site provisioning
  4. PUT /sites/{siteId}/drive/root:/{filename}:/content for each document
  5. POST /sites/{siteId}/lists with columns schema  → create custom list
  6. POST /sites/{siteId}/lists/{listId}/items for each item  → idempotent on Title field
```

**Idempotency keys**:
- `mailNickname` — unique per group, used to detect existing site (do NOT change after first run)
- List `displayName` — used to find existing list before creating
- Item `Title` field — used to skip duplicate items on re-run
- Document **exact filename** — an already-stored document is skipped, never re-uploaded

> ⚠️ **`Title` created via Graph may be unindexed.** A brand-new list (and sometimes a list whose
> items were all created through Graph) does not answer
> `GET /lists/{id}/items?$filter=fields/Title eq '...'` usefully — it returns `400`, or `200` with
> an empty page although the item exists. Relying on that filter (or on the
> `Prefer: HonorNonIndexedQueriesWarningMayFailRandomly` header, whose name is a promise it keeps)
> makes the engine re-add every item on each run. **Page the list once, snapshot the `Title` values,
> and match in memory.** Same lesson, same fix as the CJK email subjects.

**Person/User columns**: avoid them — they require `lookupId` resolution which is fragile in App context. **Use Text columns storing displayName** instead (e.g., the user's display name as plain text). Visually identical in SharePoint UI, much simpler to seed.

**Column types supported in `sharepoint-sites.json`**:
- `Text`, `Note` (multiline), `Number`, `DateTime`, `Choice` (with `choices` array)
- See `ConvertTo-ColumnSchema` in `Invoke-SeedSharePoint.ps1` for full mapping

**Site provisioning timing**:
- Group creation is fast (~1s)
- SharePoint site provisioning often takes **30-120 seconds** — poll loop must allow at least 180s with 5s interval
- After site exists, list creation is immediate (no extra wait)

### Phase 7 「Lived-in」 Patterns (optional post-provision enrichment)

Default Phase 7 produces functional but **template-looking** sites. To make them feel actively used (so demos don't look like "yesterday from template"), run an enrichment script after Phase 7. Example: [`20260515-Cathy/seed-data/scripts/enrich-sites.ps1`](../../../20260515-Cathy/seed-data/scripts/enrich-sites.ps1) + [`site-enrichment.json`](../../../20260515-Cathy/seed-data/scripts/site-enrichment.json).

| Enrichment | Graph endpoint | Notes |
|---|---|---|
| **Site description** | `PATCH /sites/{id}` body `{ "description": "..." }` | Sets the tagline under site title. Write it as if a real team owns the site (cadence, purpose, owners). |
| **Site logo** | `PUT /groups/{groupId}/photo/$value` (image/png) | **Use group endpoint, NOT `/sites/{id}/siteLogo`** — siteLogo returns `400 Bad Request` on group-backed sites. Group photo automatically surfaces as the SP site icon. |
| **News posts** | `POST /sites/{id}/pages` with `@odata.type = #microsoft.graph.sitePage`, `promotionKind = "newsPost"`, `pageLayout = "article"`, then `POST /pages/{pid}/microsoft.graph.sitePage/publish` | 3-4 posts per site is sufficient. Use `textWebPart` only (other web part types via Graph have limited stable schema). Reference real items from your seeded lists/files to make content cohesive. |
| **Extra page (e.g., "本月重點")** | Same as news posts but **omit** `promotionKind` | Appears under Pages but not in News feed. Useful as a curated dashboard linking lists + docs. |

**Idempotency requirement**: an enrichment script **must** page `/sites/{id}/pages` and skip when a page `name` already exists. Page `name` (file name like `weekly-20260514.aspx`) is the unique key.

> 🔒 **Enrichment writes belong to the run.** Take `{id}`/`{groupId}` from the Phase 7 results the
> **same process** produced — invoke the enrichment from `run.ps1` as a phase, so it consumes ids
> that run just resolved. A standalone enrichment started after the run has no ownership evidence at
> all: those ids left with the process, or at best linger in a shell as unauthenticated state. Do not
> reconstruct them from a `displayName`/alias search, from a saved file, or from a leftover
> `$global:Seed*` variable. Enrich a site inside the run that creates it, or seed the next demo
> additively under a new dated alias — see
> [Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes), prohibitions 6–7.

**Logo generation tip**: simple text-on-colored-square PNGs (`Pillow` ImageDraw, 96×96) using Chinese-capable font like `msjh.ttc` — see `generate_logos.py` for a minimal example.

**Limitations**:
- **Theme color via Graph: not stably supported.** Logo + description is enough for visual differentiation between sites.
- **Cannot backdate page `createdDateTime`** — all news posts show today's date when published. Acceptable since the storyline lives in the title (e.g., `【週報 5/14】`).
- **List item `Modified` date cannot be backdated via Graph** — to redistribute item dates, use PnP PowerShell with delegated auth + `SystemUpdate` flag, or add new items rather than trying to backdate existing ones.

### ⚠️ SharePoint Agent grounding: Custom Lists are NOT indexed

**Critical for any demo built around the in-site SharePoint Agent (`+ Add an agent` button on a SharePoint site)**: this agent's underlying retrieval pipeline (Microsoft 365 Copilot Retrieval API) **only indexes documents and pages**, NOT Custom Lists.

**Evidence (all from Microsoft Learn)**:

1. **[SharePoint tool with the agent API — Limitations](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/sharepoint#parameters)**:
   > "For semantic and hybrid retrieval, the Microsoft 365 Copilot Retrieval API supports `.doc`, `.docx`, `.pptx`, `.pdf`, `.aspx`, and `.one` file types."
2. **[SharePoint Embedded agent — Scoping](https://learn.microsoft.com/sharepoint/dev/embedded/development/declarative-agent/spe-da-adv#advanced-topics)** lists data source types as `File | Folder | DocumentLibrary | Site | WorkingSet | Meeting` — no `List`.
3. **[Add knowledge sources to a declarative agent](https://learn.microsoft.com/microsoft-365/copilot/extensibility/build-declarative-agents-add-knowledge#add-a-sharepoint-site-to-the-agent)** `items_by_url` supports site / document library / folder / file URLs — no list URLs.
4. **List support is Copilot Studio-only** (different agent surface): [Add SharePoint lists as a knowledge source](https://learn.microsoft.com/microsoft-copilot-studio/knowledge-add-sharepoint#add-sharepoint-lists-as-a-knowledge-source) — Public preview / GA **May 2026** ([release plan](https://learn.microsoft.com/power-platform/release-plan/2026wave1/microsoft-copilot-studio/add-sharepoint-lists-as-knowledge-source)).

**Practical consequence for seed data**:

| Phase 7 produces | Used by in-site SharePoint Agent? | Used by Copilot Studio agent? |
|---|---|---|
| Document library files (`.docx`, `.xlsx`, `.pptx`, `.pdf`) | ✅ Indexed and citable | ✅ Indexed and citable |
| Site Pages (`.aspx`, e.g., enrichment news posts) | ✅ Indexed and citable | ✅ Indexed and citable |
| Custom Lists + List items | ❌ **NOT indexed — never appears in citations** | ✅ Supported via `Add knowledge → SharePoint → Browse items` |

**Demo design rules**:
- **For in-site SharePoint Agent demos**: do NOT design questions / Custom Instructions that require Agent to retrieve list rows. Put any data the Agent must cite into **documents** (`.xlsx` works well for tabular content; `.docx` for narrative).
- **Lists may still be seeded** to make the site look like a real working workspace, but treat them as **visual decoration**, not Agent knowledge.
- **If your demo's pedagogy requires lists** (e.g., demonstrating structured-data grounding), pivot to **Copilot Studio agent** at `copilotstudio.microsoft.com`. Note: requires user-identity auth, not app-only.
- **Don't render list data into `.aspx` pages as a workaround** — appears fake to users who can see the real Lists in the same site. Just put the data into proper documents and reference those.

## Common Errors & Solutions

| Error | Cause | Solution |
|---|---|---|
| MS-4018 `config.json` appears in `git status` | Copied seed-data without its `.gitignore` rules | Add `seed-data/scenarios/*/config.json`, `*/source/`, `*/Products.zip` and `*/sharepoint-runtime.json` excludes; verify with `git check-ignore -v` **before** staging. Never print or commit credentials. |
| New Customer Pack role cannot be resolved | UPN absent or disabled, or pack guesses a new person | Stop at Phase 0.5; reconcile roles against the tenant's existing enabled users by GET. **Never create a user** to make a demo pass. |
| Same-date second customer collides with Ford Team or mail subjects | Team names are fixed to `YYYYMMDD-<courseCode>`; the first mail subject might also be reused | Choose a different delivery date for a second Team of the same course and unique first mail subjects; run read-only preflight. Changing purpose only changes the OneDrive folder, not the Team. Never rename or delete an existing Team. |
| Workbook has fewer facts than Teams/Outlook narrative | Pack source and generated data diverged | Validate the source pack's numeric invariants and regenerated workbook before seeding; never overwrite an already-seeded filename. |
| Archived MS-4022 runner refuses live execution | Legacy scenario format is incompatible with the new engine; old runner no longer seeds | Use the generated dated `ms4022-productsupport-20260929/run.ps1 -PreflightOnly` after reviewing its local config. Do not bypass the archived runner's guard. |
| MS-4022 document path repeats `source\Products` | Runtime `sourceFilename` was calculated relative to the scenario root instead of `filesSourceDir` | Generate filenames relative to `$source` so Phase 7 can join them to `filesSourceDir` exactly once; check all nine files before any write. |
| First Ford email appears in admin Inbox but not admin Sent Items | Supply (Alex) sent it; admin was CC, not sender. The first live run stopped before the reply | Verify the exact subject in admin Inbox or the actual sender's Sent Items. One visible message does not mean the five threads or Teams completed; never rerun the partial original scenario. |
| Email send succeeds but reply target lookup times out | `conversationId` differs between sender and recipient mailboxes even for the same delivered message | Compare `internetMessageId` by read-only GET, then use the recipient's mailbox-local `id` for `/reply`; only a reviewed new scenario with new first subjects can be seeded. Do not delete or resend the original mail. |
| Post-send Inbox GET returns 503 or 429 | Transient Graph failure while waiting for mail delivery | Retry only GET within the bounded polling budget (honor `Retry-After`); non-transient 403 aborts. Do not reissue `sendMail` or `/reply` after an uncertain response. |
| Existing OneDrive demo folder lacks a matching local `onedrive-receipt.json` and remote `.ms4018-seed-proof.json` | The generated scenario did not prove ownership and exact file revisions | Stop before writing; do not adopt, overwrite, or repair the folder. Generate a new neutral dated scenario and retain its receipt for verified reruns. |
| Ford preflight rejects Graph app token permissions or mismatched admin role | The token lacks a selected phase's effective app role, belongs to another tenant/client, or `adminUpn`, `roles.Admin.upn`, and `demoUserUpn` differ | Stop before writes; use the approved tenant app and existing Admin role mapping. Do not create users or infer permission from app registration settings alone. |
| `Message Blocked` | External email domain | Use tenant-internal UPNs only |
| `InefficientFilter` | OData $filter + $orderby on Exchange | Use $top + manual filtering |
| `Members cannot be specified for migration` | Team creation with members in migration mode | Remove members array, add after completeMigration |
| `General channel must be finalized before team` | completeMigration order wrong | Complete ALL channels (including General) first |
| `Threadtype [chat] is not allowed to be imported` | Using `chatCreationMode=migration` on chat creation | Use `startMigration` beta API on existing chat instead |
| `403 Forbidden` on user update | Missing `User.ReadWrite.All` | Grant via AppRoleAssignment |
| `Multiple drives returned` | Admin has multiple OneDrive drives | Use `/drive/root:` endpoint |
| `Throttled (429)` | API rate limit | `Start-Sleep` between calls |
| Browser login hidden behind windows | VS Code Terminal | Run in **external PowerShell** |
| `InvalidChannelName` 400 on Teams channel | Channel name contains forbidden chars (e.g., `+`, `#`, `%`, `&`) | Replace with safe substitute (e.g., `+` → `、`); do NOT URL-encode the name itself |
| `403 Forbidden` on `POST /sites/.../lists` | Granted `Sites.*` under "SharePoint" API instead of "Microsoft Graph" | See Permissions section — grant `Sites.FullControl.All` under **Microsoft Graph**, NOT SharePoint API |
| `400 Bad Request` (or `200` with an empty page) on `GET /sites/.../lists/.../items?$filter=fields/Title eq '...'` | Graph-created `Title` values may not be indexed | Do **not** depend on the filter (or on `Prefer: HonorNonIndexedQueriesWarningMayFailRandomly`). Page the list once, snapshot `Title` values, match in memory — otherwise every re-run re-adds every item |
| `Cannot validate argument on parameter 'Industry'` | Engine `[ValidateSet(...)]` doesn't include the new industry name | Add new industry to `Invoke-SeedUserProfiles.ps1`'s ValidateSet AND `run.ps1`'s ValidateSet |
| `Site provisioning timeout for group` | SharePoint provisioning slow (>180s) | Wait ~5 min and re-run **the hardened PL-7008 engine**, whose Phase 7 reuses the existing group instead of creating a second one. On the legacy `lettucebo/Work` copy, do not re-run blind: abort and seed under a new dated alias |
| `Cannot create group ... without at least one owner` | App-only `POST /groups` without `owners@odata.bind` | Always include admin as owner; otherwise group goes anonymous + site never provisions |
| `Creation time is in the future.` 400 on Migration API | A `createdDateTime` in `teams-messages.json` / `meeting-chats.json` is later than execution time (e.g. message dated `2026-05-08` while running on `2026-05-06`) | Audit all date strings in JSON before run — `Select-String -Path *.json -Pattern '\d{4}-\d{2}-\d{2}'` then compare to today. Shift to past dates. **Specifically watch for messages dated for the same day** — they may be future relative to execution clock-time. |
| `ChannelNameAlreadyExist` (or `NameAlreadyExists` on the group/alias) | Phase 4 ran before; the team and some channels already exist. On the hardened PL-7008 engine this is prevented by Phase 0.5; on an unpatched copy it surfaces mid-run | **Never delete anything to clear it.** Run the read-only preflight and confirm the existing channel's content. On the **hardened PL-7008 engine** the preflight lets the run skip the matching channel; on the legacy `lettucebo/Work/20260507-PL7008-CopilotStudio` copy there is no skip path — **abort the run** and re-seed additively under a **new dated name**. If ownership is ambiguous (more than one match), abort and use a **new dated name** in both cases — see [Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes) |
| Two or more groups share the declared `displayName` / alias | Repeated failed attempts, or another instructor seeding in the same shared tenant | Abort. Inspect read-only, report ids/owners/createdDateTime, deliver the class additively under a new dated name, and let the tenant owner reconcile afterwards with an exact ID |
| Run printed a success banner although a phase failed | Phase invoked without the fail-fast wrapper (error logged and swallowed) | Wrap every phase; on failure print the failing phase name and `exit 1`. Never claim success from "the script finished" |
| `403 Forbidden` on `GET /teams/{id}/channels/{cid}/messages` while migration writes succeed | Reads need `ChannelMessage.Read.All` / `.Group`; `Teamwork.Migrate.All` does not grant them | Consent to the read permission, or fall back to the identical **beta** collection **only** for this exact missing-read-permission 403; every other error throws |
| `completeMigration` returns "already completed" / "not in migration" / "already been finalized" | Migration finished in an earlier run | Treat all three as success and continue; anything else throws. Both channel level and team level must be re-posted, or membership can never be added |
| File sizes drift by a few bytes between two "identical" runs | Every run re-`PUT`s the same file; the drive versions it and re-serializes Office containers | Snapshot the folder and skip files already stored under the exact name |
| A pre-authenticated download URL appears in a run log | A Graph write response was left on the pipeline | `Out-Null` every write, redact the existing log, and treat the URL as compromised |
| `AADSTS7000215: Invalid client secret provided` | The app secret expired or was rotated | Obtain a current secret for the **same** `tenantId`/`clientId`, assert both match before substituting, and never print or commit the value |
| `404` / `itemNotFound` while checking whether a folder holds a file | The folder does not exist yet | The **only** error that may be read as "empty". `403`/`429`/unparseable must throw |
| Regex date-replace produces malformed timestamps like `2026-05-06T0514:00:00` | Naive `-replace '2026-05-08T', '2026-05-06T05'` concatenates `05` with the existing `14:00:00` portion, producing invalid `T0514:00:00` | Use anchored regex `[regex]::Replace($content, '2026-05-08T(\d{2}):(\d{2}):(\d{2})', '2026-05-05T$1:$2:$3')` — capture the time portion explicitly and rebuild |

## PowerShell Implementation Pitfalls

Bugs that cost real debugging time in this engine. All of them look correct while being wrong.

| Pitfall | What actually happens | Do this instead |
|---|---|---|
| **Bulk regex edit whose replacement contains `$`** | A replacement string holding `$_`, `$1` or `$(...)` is expanded by the regex engine (and by PowerShell before it), which can rewrite or blank out an entire file | Prefer exact-context edits over file-wide `-replace`. If a regex edit is unavoidable, use a single-quoted replacement, run it on a copy, and **read the diff before staging** |
| **`$x = if (…) { @('owner') } else { @() }`** | The assignment collapses to a scalar (or `$null`), so a Graph `String collection` property is serialized as a string or dropped, and the request fails or silently loses members | Build typed arrays directly: `[string[]]$x = @()` then `$x += 'owner'`, and assert `$x -is [array]` before sending |
| **`return , @($items)` *and* `@(Get-Thing)` at the call site** | Two normalization boundaries produce a nested array: `$r[0]` is the real array, `$r.Count` is `1` | Pick **one** boundary. Either the function guarantees an array (`, @(...)`) and callers use it as-is, or callers wrap. Cover it with a test that asserts `.Count` for 0, 1 and N items |
| **`[Uri]::EscapeDataString($x -replace 'a','b')`** | PowerShell parses this as a **two-argument** method call (`EscapeDataString($x, ...)`) and fails with "cannot find an overload" | Compute the replacement first: `$tmp = $x -replace 'a','b'; [Uri]::EscapeDataString($tmp)` — or parenthesize it fully. Add a test asserting the static method is called with exactly one argument |
| **`$script:`-scoped state in a probe/helper** | `$script:` binds to the file that is *executing*, so a function dot-sourced into another script writes into that host's scope; a second probe then sees the first probe's leftovers | Give test probes state they explicitly own, initialize it at entry and clean it up at exit; never share a `$script:` variable across dot-sourced files |
| **Redaction anchored to line starts** | ANSI colour escapes (from `Write-Host` output captured to a file) sit in front of the text, so `^Authorization:` never matches and the secret survives | Strip or tolerate ANSI (`\x1b\[[0-9;]*m`) before matching, and finish with a **recursive post-redaction scan** of the whole evidence folder that fails on any remaining pattern |

## Secrets, Config & Test Hygiene

- **Only `config.json.example` is committed.** The real `seed-data/scenarios/*/config.json` stays
  git-ignored. Verify the *tracked* state, not the disk: `.gitignore` **never untracks a file that
  is already tracked** — always confirm with `git ls-files -- <path>` (empty output = untracked).
- **Tests should assert the real config is untracked/ignored, not that it is missing from disk.**
  The operator needs that file locally; a test demanding its absence fails on every working machine
  and teaches people to delete their credentials.
- A private repository may deliberately track a config with secrets if its owner explicitly accepts
  that. **That is the owner's call, not a default** — do not rewrite history or rotate keys on
  someone else's repo, and do not copy that pattern into a repo that has not opted in.
- **Client secrets expire.** When a run fails with an invalid-secret error and you are authorized to
  substitute one, assert that the replacement's `tenantId` **and** `clientId` match the briefed
  config before using it, and never log, echo or commit the value.
- **Sanitize before folding lessons back.** Raw error text and run logs carry bearer tokens,
  `Authorization` values, client secrets, pre-authenticated download URLs and private object IDs.
  Replace them with placeholders (`<TOKEN>`, `<GROUP_ID>`, `[REDACTED]`) and keep only the parts
  that carry the lesson: error code, message shape, and the decision it drove. Tenant id and app
  client id are identifiers rather than secrets, but treat any capability URL as a credential.
- Keep the redaction helpers **outside** the folder they scan — a script has to name the strings
  that must not appear in the evidence.

## Course Integration & Documentation Lessons

Lessons from shipping this seed data as part of a course, not just as a script:

- **Product terminology drifts after slides ship.** Verify every product/feature name against the
  page the Learn URL finally redirects to, and use that page's current title (this course had to
  rename its runtime concepts to *standard harness* vs *GitHub Copilot harness* after the deck was
  authored). Correct the spoken names in the trainer notes rather than trusting the slide text.
- **A search summary never proves a video is Microsoft-owned.** Confirm each referenced video via
  the YouTube oEmbed check (LIVE + OFFICIAL channel) before linking it. **Prefer shipping no video
  over an unverified one** — third-party content that looks right is still a support liability, and
  links that were live in a previous delivery must be re-verified before each new one.
- **Durable docs must not present ignored working files as shipped artifacts.** `.venv/`, run logs
  and SDD/working ledgers under `.superpowers/` are local-only. A fresh clone has none of them, so
  documentation must tell the reader how to *create* what they need (create the virtualenv, generate
  a current link ledger from the committed docs) instead of referencing a private file path.
- **Maintain one authoritative module → lab map.** When a lab appears in more than one place (an
  optional or repeated lab), it keeps its owning module everywhere it is listed. Duplicated,
  divergent maps in README/teaching guide/instructions are how a lab silently changes owner.
- **Fold every seeding lesson back into this SKILL** (and keep the copies in sync) so the next
  course does not re-learn it at a tenant's expense.

## Git & GitHub Delivery Pitfalls

Publishing the course artifacts is part of the delivery, and it fails in ways that look like
permission problems but are not. Every row below is either **fail-closed** (the push aborted and the
remote was left untouched) or **read-side only** (the write had already succeeded and only the
verification call was wrong). In none of them is the correct response to weaken a safety setting,
retry with force, or re-do the write.

| Symptom | Cause | Safe fix | Verify |
|---|---|---|---|
| A non-interactive `git push` aborts with `fatal: Cannot prompt because user interactivity has been disabled`, `Git credentials for <remote> not found` (often next to a Git LFS locking-API warning), and the remote ref is unchanged | The only configured `credential.helper` is an interactive GUI manager. A Git LFS `pre-push` hook resolves credentials in its **own child process**, so an earlier `fetch` that succeeded on a cached credential proves nothing about push | Supply an already-authorized non-interactive helper **on the command line only** (snippet below). Do **not** persist it in any config scope, and do **not** set `lfs.<url>.locksverify=false` — git suggests it, but it permanently disables a safety check and supplies no credential | Remote head equals the pushed commit, and `git -C <repo> config --local --get-all credential.helper` still prints nothing |
| `GET /repos/{owner}/{repo}/issues/{number}/comments/{comment_id}` returns `404 Not Found` immediately after the comment was created successfully | Wrong endpoint, not a failed write. `/issues/{number}/comments` is the **list/create** collection; appending an id to it does not address a comment | Read a single comment from the repository-scoped collection: `/repos/{owner}/{repo}/issues/comments/{comment_id}` | Re-read returns the expected body; cross-check with the list endpoint or the `html_url` returned by the create call |
| A ref-qualified Contents read (`GET /repos/{owner}/{repo}/contents/{path}?ref={sha-or-branch}`) returns `404 Not Found` for a file that was just pushed, while the same path without `?ref=` returns it and the qualified call succeeds on a later retry | **First rule out the verb** (next row): only a call proven to be a real GET — `gh api -X GET …` or a plain query-string request — can be read this way. For a confirmed GET it is an **observed failure mode; root cause not proven** — a read-side symptom of a second system, not evidence about the push, because `git ls-remote` already showed the branch head advanced | Ask git, not the REST API, whether the push landed: `git ls-remote <remote> refs/heads/<branch>`, then compare file content through fetched git refs (`git fetch` with an explicit refspec + `git rev-parse refs/remotes/<remote>/<branch>:<path>`, `git cat-file`), checking the exit status of every step. Retry the Contents API only when you need byte-level readback evidence | The failing call is confirmed `-X GET`, the remote branch head equals the pushed commit, and the remote-tracking blob hash equals the local blob hash |
| A `gh api` **read** that supplies fields, e.g. `gh api <read-endpoint> -f ref=main`, returns a generic `404` although the endpoint and ref are correct | `-f`/`-F` make `gh api` default to **POST**, so a read path is routed as a write. The 404 is a method error, not a missing object | Set the verb explicitly whenever a read carries parameters: `gh api -X GET <read-endpoint> -f ref=main` (or move the parameters into the query string) | The identical call with `-X GET` returns the resource — a 404 that disappears when only the verb changes was never about the resource |

**Authenticated push through a command-local helper.** The two `-c` values below apply to one
command: the empty first helper clears any inherited interactive helper, the second delegates to the
already-signed-in CLI, and both propagate to the `git-lfs` child process. Nothing is persisted.

> This is a **mechanical fix for a push the repository owner already authorized** — it is not
> permission to push. If you are not sure the push was requested for that exact repo and branch,
> stop and ask instead of running it.

```powershell
# TEMPLATE (not runnable as written) — replace <repo> and <branch>.
# Explicit refspec, never --force / --force-with-lease, never a bare `git push`.
git -C <repo> `
  -c "credential.helper=" `
  -c "credential.helper=!gh auth git-credential" `
  push origin HEAD:<branch>
```

Verify afterwards that the push landed and that no credential configuration survived it:

```powershell
# Read-only push verification. $repo = working copy path; $remote = the remote you pushed to
# (`origin` in the push command above); $branch = the branch you pushed to.
$localSha = (git -C $repo rev-parse HEAD).Trim()
$lsRemote = (git -C $repo ls-remote --exit-code $remote "refs/heads/$branch" | Out-String)
if ($LASTEXITCODE -ne 0) { throw "ls-remote could not read ${remote}/${branch} (exit $LASTEXITCODE) - delivery is unverified, not proven failed." }
$remoteSha = ($lsRemote -split '\s+')[0]
if ($localSha -ne $remoteSha) { throw "Push did not land: local $localSha, remote '$remoteSha'." }
git -C $repo config --local --get-all credential.helper   # expect: no output
```

**Did the push land? Ask git, not the Contents API.** `git ls-remote <remote> refs/heads/<branch>`
reads the remote's refs directly and is the authoritative branch-delivery check. A REST read is a
second system with its own routing and caching: a ref-qualified Contents call (`?ref=<sha-or-branch>`)
has been **observed** returning 404 for a path immediately after a successful push — while the
unqualified read of the same path worked and the qualified read succeeded when retried later. That
explanation is the **last** one to reach for: first prove the failing call was a real GET (see
"Confirm the verb" below). Even then the root cause was never proven, so treat it as an observed
failure mode, not a guaranteed consistency model, and never as proof that the push failed. Prove
file-level delivery from fetched git refs — checking the exit status of every step, so a fetch that
fails can never be answered from a stale remote-tracking ref — and reach for the Contents API only
when you specifically need the bytes as the API will serve them:

```powershell
# File-level delivery check. Writes nothing to the remote; the only local change is the
# remote-tracking ref refs/remotes/$remote/$branch. $repo = working copy path, $remote = the remote
# you pushed to, $branch = the branch you pushed to, $path = repo-relative file path.
# Every step is checked, so a failed fetch throws instead of answering from a stale ref.
$remoteRef = "refs/remotes/$remote/$branch"

$lsRemote = (git -C $repo ls-remote --exit-code $remote "refs/heads/$branch" | Out-String)
if ($LASTEXITCODE -ne 0) { throw "ls-remote could not read ${remote}/${branch} (exit $LASTEXITCODE) - delivery is unverified." }
$remoteHead = ($lsRemote -split '\s+')[0]

# Explicit refspec: refreshes exactly this branch's remote-tracking ref, nothing else.
git -C $repo fetch --quiet $remote "refs/heads/${branch}:$remoteRef"
if ($LASTEXITCODE -ne 0) { throw "fetch of ${remote}/${branch} failed (exit $LASTEXITCODE) - refusing to compare the possibly stale $remoteRef." }

$fetchedHead = (git -C $repo rev-parse --verify --quiet "$remoteRef" | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $fetchedHead) { throw "$remoteRef does not exist after a reportedly successful fetch - delivery is unverified." }
if ($fetchedHead -ne $remoteHead) { throw "$remoteRef is stale: it points at $fetchedHead but ${remote}/${branch} is at $remoteHead." }

$localBlob = (git -C $repo rev-parse --verify --quiet "HEAD:$path" | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $localBlob) { throw "'$path' does not exist in local HEAD - check the repo-relative path and that the change was committed; nothing was compared." }

$remoteBlob = (git -C $repo rev-parse --verify --quiet "${remoteRef}:$path" | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $remoteBlob) { throw "'$path' does not exist in ${remote}/${branch} at $fetchedHead - the file was not delivered (do not re-push blindly: confirm the path and the commit first)." }

if ($localBlob -ne $remoteBlob) { throw "File not delivered: local $localBlob, ${remote}/${branch} $remoteBlob." }
```

**Confirm the verb before you blame the lag mode.** A ref-qualified Contents 404 only counts as the
observed behaviour above once you have confirmed the failing request was a real GET — an explicit
`gh api -X GET ...` (or a plain query-string GET). If the call passed fields with `-f`/`-F` and no
`-X GET`, `gh api` sent a **POST**, the generic route 404 is that method bug, and retrying the same
call — or re-pushing because of it — only repeats it. Re-issue it as a GET first; the two look
different once you read the body, because a genuine Contents 404 answers for the contents route
while the method error answers generically for a route that does not accept POST.

**`gh api -f` silently switches the verb.** Supplying fields with `-f`/`-F` makes `gh api` default
to `POST`, so a read endpoint is routed as a write and answers with a generic `404` that reads like
a missing resource. Name the method on every read that carries parameters:

```text
gh api -X GET repos/{owner}/{repo}/contents/{path} -f ref=main   # read — correct
gh api repos/{owner}/{repo}/contents/{path} -f ref=main          # POSTs — generic 404
```

**Issue comments — three endpoints, three jobs.** A 404 on read-back is a URL bug until proven
otherwise; confirm the comment through the list endpoint or its `html_url`
before concluding the write failed.

```text
POST /repos/{owner}/{repo}/issues/{number}/comments      # create a comment on issue {number}
GET  /repos/{owner}/{repo}/issues/{number}/comments      # LIST that issue's comments
GET  /repos/{owner}/{repo}/issues/comments/{comment_id}  # read ONE comment (no issue number)
```

- **Never re-post after an unverified read.** Re-running a create because the read-back 404'd is how
  an issue collects duplicate comments; check the list endpoint first.
- **A read-side 404 is never a reason to re-push.** Check the verb first, then confirm the branch
  head with `git ls-remote` and the file through fetched refs before touching the remote again;
  re-pushing or re-committing to "fix" a failed read delivers nothing and leaves empty or duplicated
  history behind.
- **Keep the diagnosis read-only.** `gh auth status`, `git config --get-all`, `git lfs status` and
  `git ls-remote` answer "who am I, what is configured, what would move" without changing anything.
- **Same sanitization rule as the tenant work.** Push output, `gh api` responses and auth diagnostics
  can carry tokens and private ids — redact before pasting them into an issue, log or report.

## SKILL Location

This skill lives **inside the repositories that use it**. This MS-4018
copy is intentionally project-specific; other repository copies may differ:

```
MoneyYu/PL-7008/.github/skills/m365-demo-data-seeding/SKILL.md
lettucebo/Work/.github/skills/m365-demo-data-seeding/SKILL.md
MoneyYu/MS-4018/.github/skills/m365-demo-data-seeding/SKILL.md
```

**Scope exception**: the Ford Customer Pack changes apply only to MS-4018
per the course owner's decision. Do not overwrite the PL-7008 or Work copy
with this project-specific documentation. When intentionally porting a general
fix to another repository, review that copy's engine and tests first; identical
skill text alone does not make different engines behave alike.

> Note that byte-identical **documentation** does not imply identical **engines**: the Work repo's
> legacy seed engine is still unpatched. See [Engine Status](#engine-status--which-copy-is-safe-to-re-run).

## JSON Schema Reference

### MS-4018 Customer Pack (`seed-data/packs/<scenario>/pack.yaml`)

The actual schema is [`seed-data/generator/pack.schema.json`](../../../seed-data/generator/pack.schema.json).
The pack carries `slug`, `customer` (`name`, `industry`, `locale`),
`course` (`code`, neutral `purpose`), `tenantDomain`, `roles` (existing
`upn`/`displayName` only), and **only the needed** `teams`, `emails`,
`workbooks`, `sharepoint`. Teams messages specify `dayOffset` + `time`;
the generator writes dated `createdDateTime`. Email `send` then `reply`
authors must have received the previous mail and must CC `Admin`.
The first subject contains the delivery date and is distinct across
threads. `workbooks` specify `filename` and `sheets` with `table`,
`headers`, `rows` (or seeded `generate`), optional `formulas` and
`chart`. No user-creation or tenant-profile field exists. See
[`seed-data/packs/ms4018-ford-auto/pack.yaml`](../../../seed-data/packs/ms4018-ford-auto/pack.yaml)
for a complete Simplified Chinese example.

### config.json
```json
{
  "tenantId": "...", "clientId": "...", "clientSecret": "...",
  "teamDisplayName": "Team Name",
  "demoUserUpn": "AdeleV@tenant.com",
  "adminUpn": "admin@tenant.com",
  "roles": {
    "RoleName": { "upn": "user@tenant.com", "displayName": "Display Name", "title": "Job Title" }
  },
  "filesSourceDir": "relative/path", "timezone": "Asia/Taipei"
}
```

### calendar-events.json (relative dates)
```json
{
  "events": [{
    "subject": "Meeting", "dayOffset": -3,
    "startTime": "10:00", "endTime": "11:30",
    "timeZone": "Asia/Taipei", "isOnlineMeeting": true,
    "organizerRole": "RoleName", "attendeeRoles": ["RoleName", "Admin"]
  }]
}
```

### meeting-chats.json (with mentions + multi-user avatars)
```json
{
  "meetingChats": [{
    "topic": "Meeting Chat Title",
    "dayOffset": -3,
    "startTime": "10:00",
    "memberRoles": ["RoleName", "Admin"],
    "messages": [
      { "fromRole": "RoleName", "bodyHtml": "<p><at id=\"0\">Display Name</at> hello</p>", "mentions": ["OtherRole"] },
      { "fromRole": "OtherRole", "bodyHtml": "<p>Reply without mention</p>", "mentions": [] }
    ]
  }]
}
```

### teams-messages.json (with mentions + replies)
```json
{
  "channels": [{
    "channelName": "Channel Name",
    "channelDescription": "Description",
    "messages": [{
      "order": 1,
      "fromRole": "RoleName",
      "createdDateTime": "2026-03-16T09:00:00+08:00",
      "bodyHtml": "<p><at id=\"0\">Display Name</at> hello</p>",
      "mentions": ["OtherRole"],
      "replies": [
        { "fromRole": "OtherRole", "createdDateTime": "...", "bodyHtml": "...", "mentions": ["RoleName"] }
      ]
    }]
  }]
}
```

> ⚠️ Channel name **cannot contain** `+`, `#`, `%`, `&`, `\`, `/`, `:`, `<`, `>`, `?`, `|`, `"`. Use Chinese punctuation like `、` as safe substitute.

### files-manifest.json (OneDrive upload, supports subfolders)
```json
{
  "targetFolder": "TopLevelFolderName",
  "uploadToRole": "RoleName",
  "files": [
    { "localName": "file.docx", "subfolder": "GroupA", "description": "..." },
    { "localName": "GroupB/nested/file.docx", "description": "path embedded — also works" }
  ]
}
```

### sharepoint-sites.json (Phase 7 — optional)
```json
{
  "sites": [{
    "alias": "team-compliance",
    "displayName": "Compliance Team Site",
    "description": "...",
    "owners": ["Admin"],
    "members": ["Compliance", "Risk", "CDO"],
    "documents": [
      { "sourceFilename": "compliance-doc.docx" }
    ],
    "lists": [{
      "displayName": "Regulation Tracker",
      "columns": [
        { "name": "Title",       "displayName": "Reg ID",       "type": "Text" },
        { "name": "PublishDate", "displayName": "Published",    "type": "DateTime" },
        { "name": "ImpactLevel", "displayName": "Impact",       "type": "Choice", "choices": ["High","Medium","Low"] },
        { "name": "Owner",       "displayName": "Owner",        "type": "Text" }
      ],
      "items": [
        { "Title": "R-2026-001", "PublishDate": "2026-04-22", "ImpactLevel": "High", "Owner": "Display Name" }
      ]
    }]
  }]
}
```

## Existing Scenarios

The skill defines an architecture, not specific scenarios. Each repo using this skill maintains its own scenarios under `seed-data/scenarios/`. As of this writing:

**`MoneyYu/MS-4018`** (local Customer Pack generator + ported engine):

- `seed-data/packs/ms4018-ford-auto/pack.yaml` → `scenarios/ms4018-ford-auto-20260929`:
  5 Simplified Chinese Teams channels, 5 Outlook threads, 5 Excel workbooks uploaded
  to admin OneDrive. Uses **existing manufacturing personas**; no user creation
  and no profile PATCH. Read-only preflight first.
- `seed-data/packs/ms4022-productsupport/pack.yaml` → dated SharePoint-only
  scenario: `Products` library + `Support Cases` list; preserves original
  `scenarios/ms4022-productsupport` unmodified. MS-4022 is not seeded live
  as part of the Ford delivery.

**`MoneyYu/PL-7008`** (hardened engine):

- `seed-data/scenarios/pl7008-it-helpdesk-20260831` — PL-7008 delivery 2026-08-31, IT Helpdesk RAG backend (`-Industry technology`). Runs Phases 0, 0.5, 1, 2, 3, 4 and 7; Phases 5 and 6 are skipped by design.
  **Live-verified 2026-08-31**: one corrective `run.ps1` added the single missing IT Tickets item `TKT-100011` (1 added / 10 skipped), and the 196-leaf snapshots taken before and after it differ only in the IT Tickets leaves and in the verifier's own assertion-failure count; the **two runs after it** both exited `0` and produced **no new resources, no duplicates, no list items, no messages and no files**, each followed by a read-only verification of **72/72 checks**, and a 196-leaf snapshot comparison of those two verifications showed **0 differences** (every resource, message, item id/title and file id and size identical). Those reruns are idempotent, not silent: Phase 1 still sends a user-profile `PATCH` per role account and Phase 4 still re-issues `completeMigration` plus one `POST` per team member — each call re-asserts state that already exists, which is why the first and second snapshots match. The offline suite `seed-data/tests/Test-SeedEngine.ps1` passes **418/418**. No phase created, replaced or deleted any other resource — every other phase reused or skipped.

**`lettucebo/Work`** (legacy engine — see [Engine Status](#engine-status--which-copy-is-safe-to-re-run) before running any of these):

> ⚠️ **These scenarios have no rerun guarantee.** For
> `20260507-PL7008-CopilotStudio` in particular, a second run against a tenant that already holds
> its data duplicates threads and messages and fails on the existing channel/alias. If its
> resources already exist, **abort and seed under a new dated scenario name** (new
> `teamDisplayName` + new site alias). **Never delete the existing resources to "clean" the rerun**
> — see [Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes).

- `AB730-Inventec/seed-data/scenarios/inventec-ab730` — manufacturing demo
- `MS4018-Tmnewa/seed-data/scenarios/tokiomarine-ms4018` — insurance demo
- `20260515-Cathy/seed-data/scenarios/cathay-ms4019` — financial holdings demo (with Phase 7 SharePoint pre-build)
- `20260507-PL7008-CopilotStudio/seed-data/scenarios/pl7008-it-helpdesk` — PL-7008 Copilot Studio Lab 場景 A (IT Helpdesk, 🟢 簡單)
- `20260507-PL7008-CopilotStudio/seed-data/scenarios/pl7008-hr-travel` — PL-7008 Copilot Studio Lab 場景 B (HR 差旅, 🟡 中等, 含 Excel Online table)
- `20260507-PL7008-CopilotStudio/seed-data/scenarios/pl7008-customer-service` — PL-7008 Copilot Studio Lab 場景 C (客服中心, 🔴 複雜, 4 lists × 2 channels)

> **PL-7008 專案另有場景 D（旅遊助理 Skillable 友善）** 不需 seed-data — 學員直接下載檔案 + 用 HTTP 公開 API。詳見 [20260507-PL7008-CopilotStudio/scenarios/D-旅遊助理-Skillable/](../../../20260507-PL7008-CopilotStudio/scenarios/D-旅遊助理-Skillable/)。

For account assignments, role mappings, and tenant-specific layouts, see the per-tenant directory in `docs/tenants/` (e.g. [`docs/tenants/moneyyu-tenant-directory.md`](../../../docs/tenants/moneyyu-tenant-directory.md)).

## 🔐 Demo Account Ironclad Rule

All demo operations (login, file open, agent invocation, SharePoint browse, etc.) **MUST use the single account designated as `adminUpn` in the scenario's `config.json`** — that account is the "observer + demo operator". The instructor running the demo holds only that one password.

Never instruct users to log in as a business role account (e.g. the PM, the Risk officer) — those accounts are seed data sources, not real login identities.

The engine treats the admin account specially:
- Email: every thread CCs admin
- Calendar: admin is an attendee on every event
- Teams: admin is team owner (not just member)
- Chat: admin is in every meeting group chat
- OneDrive: seed uploads happen on `demoUserUpn`'s drive, but admin sees the files via Teams/Files share or by browsing the drive
- SharePoint sites (Phase 7): admin is the site owner

**Demo step-by-step prompts must use admin's perspective**:
- ❌ Wrong: 「我是 [角色名]...」 — this would require logging in as that role account
- ✅ Right: 「我（admin）正在協助 [角色名] 準備...」 — admin stays logged in, role names appear only inside prompts as narrative context

### ⚠️ Post-Run Verification — admin MUST be in every resource the run created

The engine puts admin into a resource **while it creates it**. When a resource already existed (a
previous run with a different `demoUserUpn`/`adminUpn`, or a teammate's earlier seeding), retro-fit
is not guaranteed: the hardened PL-7008 Teams phase re-asserts the declared member list against the
team id it resolved, but the Phase 7 reuse branch returns the existing group untouched, and the
legacy `lettucebo/Work` copy guarantees nothing at all. After every `run.ps1`, verify admin in
**every surface this scenario actually creates** — read the scenario's `run.ps1` phase list and
verify exactly those. There is no fixed number of surfaces: a scenario that skips Calendar and
Meeting Chats has nothing to verify there, and **never add a phase just to make a verification list
look complete**.

**Verification is read-only. There is no post-run repair write in this skill.** Putting `adminUpn`
into a resource is the **seeder's** job and it happens *during* the run, in the process that created
the resource — `Invoke-SeedTeamsChannel.ps1` asserts the declared owner/member list against the team
id it just resolved, and Phase 7 passes `owners@odata.bind` in the group it creates. Afterwards
there is nothing left that can authorize a manual repair:

- **A run usually leaves nothing behind at all.** Launched as its own process — `pwsh -File
  .\run.ps1`, a scheduled task, CI, a second terminal, a wrapper script — it takes every
  `$global:Seed*` value with it when it exits (`exit 0`, or `exit 1` on a failed phase). A recovery
  path that only exists when the run happened to be typed into the prompt you are still sitting at
  is not a path.
- **When those variables *are* still set, they prove nothing.** A global is **mutable,
  unauthenticated shell state**: an earlier run, a different scenario, a copied snippet, an aborted
  attempt or a plain assignment can leave one behind, and the value carries no signature and no link
  to the resource in front of you. It is a disk ledger with a shorter lifetime, and
  [prohibition 7](#-shared-tenant-safety--recovery-never-deletes) rejects it for the same reason.
- **A populated variable is not even proof the phase succeeded.** `run.ps1` exits `1` the moment a
  phase fails, and the ids earlier phases had already stored stay exactly where they were.

So: **never write from those variables, and never rely on them.** The `Resource ledger` block
`run.ps1` prints is a **human-readable report** — put it in your notes or hand it to the tenant
owner. Re-typing an id out of it into a write re-creates the disk-ledger loophole by hand.

```powershell
# READ-ONLY POST-RUN VERIFICATION. This block issues no Graph write at all: no POST/PATCH/PUT to a
# resource, no /$ref, no DELETE. It answers one question — "is adminUpn present in the resources
# this scenario declares?" — and prints evidence you can hand over. It cannot repair by design.
# Requires Get-GraphPaged (Shared-Tenant Safety, Step 0). Run it from the scenario folder in ANY
# shell, at any time: it needs nothing from the seeding process, because nothing survives it.
# $tok and the header below hold a live credential: never echo them, never paste them into a log,
# an issue or a chat message.
if (-not (Get-Command Get-GraphPaged -ErrorAction SilentlyContinue)) {
    throw "Load Get-GraphPaged first (Shared-Tenant Safety, Step 0) — every collection read must page."
}

$c = Get-Content config.json -Raw | ConvertFrom-Json
$tok = (Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($c.tenantId)/oauth2/v2.0/token" -Body @{client_id=$c.clientId;client_secret=$c.clientSecret;scope='https://graph.microsoft.com/.default';grant_type='client_credentials'}).access_token
$authScheme = 'Bearer'
$h = @{ Authorization = "$authScheme $tok" }   # composed from variables only
# adminUpn identifies the PRINCIPAL being looked for — a unique identifier declared in config.json.
$adminId = (Invoke-RestMethod -Headers $h -Uri "https://graph.microsoft.com/v1.0/users/$($c.adminUpn)").id

# The declared names below are DIAGNOSIS keys, never write targets: they report what exists in the
# tenant, not what is yours. Nothing downstream of this loop may become a write.
$targets = @([pscustomobject]@{ Surface = 'Teams team'; Property = 'displayName'; Value = $c.teamDisplayName })
if (Test-Path .\sharepoint-sites.json) {
    foreach ($alias in @((Get-Content sharepoint-sites.json -Raw | ConvertFrom-Json).sites.alias)) {
        $targets += [pscustomobject]@{ Surface = 'Phase 7 site'; Property = 'mailNickname'; Value = $alias }
    }
}

$report = @()
foreach ($t in $targets) {
    # Build the OData literal FIRST, then escape (see PowerShell pitfalls).
    $literal = "$($t.Value)".Replace("'", "''")
    $filter  = [Uri]::EscapeDataString("$($t.Property) eq '$literal'")
    $groups  = Get-GraphPaged -Headers $h -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,mailNickname,createdDateTime"
    if ($groups.Count -eq 0) {
        $report += [pscustomobject]@{ Surface = $t.Surface; Declared = $t.Value; Id = '(not found)'; Created = ''; AdminOwner = $false; AdminMember = $false }
        continue
    }
    foreach ($g in $groups) {
        $owners  = Get-GraphPaged -Headers $h -Uri "https://graph.microsoft.com/v1.0/groups/$($g.id)/owners?`$select=id"
        $members = Get-GraphPaged -Headers $h -Uri "https://graph.microsoft.com/v1.0/groups/$($g.id)/members?`$select=id"
        $report += [pscustomobject]@{
            Surface     = $t.Surface
            Declared    = $t.Value
            Id          = $g.id
            Created     = $g.createdDateTime
            AdminOwner  = ($owners.id  -contains $adminId)
            AdminMember = ($members.id -contains $adminId)
        }
    }
}

# Two rows sharing one Declared value = ambiguous tenant state. Report it; never resolve it by writing.
$report | Format-Table -AutoSize
```

**If admin is missing, the run is incomplete — that is a finding, not a task.** Work through this
list in order; every step is read-only or additive:

1. **Classify the run incomplete** and say so in the handover. A hardened phase that finished
   without admin in a resource it created is a **seeder defect**: fix the phase so it asserts
   membership in-process against the id it just created, and cover it with the offline engine tests.
   A manual write papers over the defect and leaves the next run just as broken.
2. **Collect read-only evidence** — the table printed above plus the Step 1 inventory
   ([Shared-Tenant Safety](#-shared-tenant-safety--recovery-never-deletes)): declared key, every
   matching id, `createdDateTime`, current owners. Ambiguity (two rows for one declared name) is
   itself the finding.
3. **Then choose exactly one of two paths:**
   - **(a) Hand it to the tenant owner.** Ownership is decided from a record the tenant owner
     authenticates *outside this skill* (a directory/ITSM record, an access review, an audit-log
     trace of who created the id). That record is what authorizes anything they choose to do; your
     evidence table is an input to it, not a substitute for it.
   - **(b) Seed a new dated scenario resource.** Bump the dated suffix in `config.json` plus a
     matching new site alias and run the hardened seeder. It **creates** the group, so admin is in
     the owner/member list from the first second — which is the only mechanism this skill has for
     putting admin into a resource. Nothing existing is touched.
4. **Never** close the gap with a write of your own — not from a saved id file, not from a
   `displayName`/`mailNickname` hit, and not from a `$global:Seed*` variable that happens to still be
   set in your shell (mutable, unauthenticated state; see prohibition 7). Adding the demo operator to
   a group you cannot prove is yours hands your account somebody else's live demo, or hands them
   yours.

> ⚠️ **A re-run is not a repair path either.** The seeder resolves an existing team by its declared
> `displayName` and reuses a single match, so re-running it to retro-fit membership into a resource
> you cannot prove is yours is a name-authorized write with extra steps. Re-run the seeder to
> **finish seeding a resource it creates**, never to adopt one it finds.

Verify only the rows whose phase this scenario actually runs. Every "if missing" outcome is
read-only or additive — none of them writes to an existing group:

| Surface | How admin gets in **during the run** | Read-only verification | If admin is missing |
|---|---|---|---|
| Email | `cc` includes admin in `emails.json` | Page the admin **Inbox** and match the exact subject in memory | Content gap, not an ownership gap: re-run Phase 3 of the **hardened PL-7008 engine**, which pages the Inbox and skips a thread already present. A partial thread is a human decision — never hand-POST into one |
| Calendar *(only if Phase 5 runs)* | `attendees` includes admin | Page `calendarView` for admin | Classify the run incomplete and report. Phase 5 is unhardened, so re-create the event **only** after a read-only check shows it absent; otherwise deliver from a new dated scenario |
| Teams team | the run asserts the declared owner/member list against the team id it resolved | `GET /groups/{teamId}/owners` (paged) includes admin — `{teamId}` from the read-only verification above, reported not written | **Incomplete run.** Read-only evidence → tenant owner's authenticated ownership record, **or** a new dated scenario resource whose creation puts admin in from the start. No manual owner/member write, and no re-run aimed at adopting the existing team |
| Group chats *(only if Phase 6 runs)* | admin in `participants` per chat | Page `GET /users/{admin}/chats` for the topic | Classify the run incomplete and report. Phase 6 is unhardened; re-create the chat **only** after a read-only check shows it absent |
| OneDrive | `uploadToRole: "admin"` in `files-manifest.json` | `GET /users/{admin}/drive/root:/{targetFolder}` (page the children) | Content gap: re-run Phase 2 of the **hardened PL-7008 engine** — it uploads only the missing files into the declared UPN's drive. The legacy `lettucebo/Work` copy re-uploads everything, so do not use it as a repair path. If the folder holds content you did not seed, stop and use a new dated folder |
| Phase 7 sites | admin is in `owners@odata.bind` of the group the run **creates** | `GET /groups/{siteGroupId}/owners` (paged) — `{siteGroupId}` from the read-only verification above | **Incomplete run.** Read-only evidence → tenant owner's authenticated ownership record, **or** a new dated site alias. A reused site is never retro-fitted, by the engine or by hand |

> 💡 **Why this happens**: an engine copy that unconditionally `POST /teams` even when a same-named
> team exists can bind to the existing (older) team, which keeps its original owner/member list. The
> hardened PL-7008 engine aborts on an ambiguous dated name and asserts the declared owner/member
> list in-process against the id it resolved, so a *complete* run leaves admin in place. Phase 7 is
> the known gap: its reuse branch returns the existing group untouched, so a site the run did not
> create keeps whatever owners it had — which is exactly why a missing site owner is answered with a
> **new dated alias** (whose creation sets `owners@odata.bind`), never with a post-run owner write.
> Either way the post-run posture is the same: **verify read-only, classify, hand over or re-seed
> additively** — never remove a member, never delete a resource, never write to a group found by
> name, and never restore a write target from a file or a leftover shell variable.

## Demo File Generation

Each scenario has Python scripts to generate demo Excel/Word files. **Use `uv`** — never
`pip install` into a global interpreter:

In MS-4018, use the checked-in Customer Pack generator (`uv run --no-project
.\seed-data\generator\build_scenario.py --pack <pack.yaml> --date YYYYMMDD
--output <new-scenario-directory>`); it declares dependencies with PEP 723.
Pass `UV_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple/` in the
local command environment. The generator rejects nonempty output; Excel files
are immutable per dated scenario. Validate formulas, dimensions, calculated
facts, CJK labels and workbook readability before any upload.

```powershell
# One-time, per repo: create the environment and install the two generators' dependencies.
# On workstations/local containers, resolve packages through the internal index.
uv venv
uv pip install --index-url https://packagefeedproxy.microsoft.io/pypi/simple/ openpyxl python-docx

# Generate Excel files (理賠數據、費率精算、KPI 等)
uv run python create_excel_files.py

# Generate Word files (會議逐字稿、提案報告、範本等)
uv run python create_word_files.py
```

> Hosted runners / Codespaces / cloud agents use the public PyPI default instead — drop
> `--index-url`. Never set the index globally; pass it per command or in the project config.

Word files may include **red Copilot placeholder blocks** (`[此章節請使用 Copilot 草擬]`) for live demo use.

Generated demo assets are **immutable dated artifacts**: regenerate them locally and re-run the
**hardened PL-7008 seeder** (which uploads only the missing filenames) rather than editing a file
that is already stored in the tenant. The legacy `lettucebo/Work` engine re-uploads every declared
file, so never use it as a "refresh" path.
