# Phase 7 — Git & GitHub workflow

Close out the prep with a clean, auditable trail. Two existing skills do the heavy lifting — use
them: **`git-commit`** (Conventional Commits) and **`github-issues`** (issue management).

## Tracking issue (body = scope, comments = progress)

House convention: the **issue body holds the scope / things-to-do**; **progress, decisions, and
notes are appended as comments** — never edited back into the body.

- Create/update issues with **`gh api`** (the GitHub MCP server is read-only for writes).
- Prefer the org **issue types** (`Task` / `Bug` / `Feature`) over equivalent labels. Course prep is
  a **Task**.
- Body: a scoped checklist (README rewrite, Terraform stack, data-plane, sample data, validation),
  acceptance criteria, and out-of-scope items.
- Comments (in order, as you progress): research & key findings → e2e deployment result (resource
  count, indexed-doc count) → repo updates / follow-ups → closing commit/push note.

```powershell
# discover org issue types
gh api graphql -f query='{ organization(login: "ORG") { issueTypes(first: 10) { nodes { name } } } }' --jq '.data.organization.issueTypes.nodes[].name'
# create (write the body to a temp file first to avoid shell-escaping issues)
gh api repos/<owner>/<repo>/issues -X POST -f title="Prepare <COURSE> …" -f type="Task" -f body="$(Get-Content body.md -Raw)" --jq '{number, html_url}'
```

## Commits (Conventional Commits + co-author trailer)

- Format: `<type>(<scope>): <description>` + body + footers (`Closes #N`).
- **Always append** the trailer:
  `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
- Group changes into logical commits (README, Terraform, docs) rather than one mega-commit.

## Binary assets — fix `.gitattributes` *before* committing

The global `* text=auto` will **corrupt** PDFs/PNGs/PPTX via line-ending normalization. Mark binary
types explicitly (`*.pdf binary`, `*.png binary`, …) and re-normalize, **then** commit. Verify a
committed PDF still starts with `%PDF-`.

## `.gitignore`

Ignore Terraform noise and local helpers: `.terraform/`, `*.tfstate*`, `.terraform.lock.hcl`, and
any local-only helper files (e.g. a `docker-chat-uis.sh` scratch file) that aren't course
deliverables.

## `/init` → `.github/copilot-instructions.md`

Run `/init` (or write it directly) to capture the **non-obvious, repo-specific** conventions so
future sessions follow them: the validate commands, the `MAIN/MOD/OUTPUT` split and
`group_postfix` naming, the region choice, the Foundry/azurerm pattern, the `depends_on` chaining,
the data-plane wiring, the model-retirement rule + CU constraint, the AAD-only design, the
sample-data/`.gitattributes` rule, the HackMD README conventions, and the attendee-vs-trainer
(`docs/`) split.

## Final cleanup

Remove temp files, confirm the working tree is clean, push, and verify on GitHub (including that
binary blobs are intact). Add the closing comment to the tracking issue.
