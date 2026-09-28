# Pre-Merge PR / Issue Update Gate

Operational reference for updating a Pull Request (and its linked issue) **before any merge**.

> **Policy authority vs. this file.** The canonical policy and trigger list live in
> `.github/instructions/general.instructions.md` ("🚦 合併前強制 Gate") and the
> `git-worktree` skill (Workflow 4.5 / 5). **This file is the operational command reference** — it documents
> *which `gh` commands to run* to satisfy the gate. If anything here ever conflicts with those two sources,
> treat them as authoritative.

## ⛔ STOP — when this gate applies

Before you run **or enable any form of merge**, you must first complete this gate and **emit the confirmation
block** (see below). Do not merge until every item is verified.

This covers **all merge entry points**:

- `gh pr merge` (including `--merge` / `--delete-branch`)
- `gh pr merge --auto` or otherwise enabling auto-merge
- merge queue
- the GitHub Web UI "Merge pull request" button
- release PR merges
- **Natural-language triggers**: "ship it", "land it", "LGTM, merge", "approved, merge",
  "merge when green", "done", "ready to merge", "合併吧", etc.

## Core principle: body vs. comment

> **The PR body describes *what was implemented* (overwrite-update); comments append *what was verified*
> (test / code review results), append-only.**

| Information type | How to write it | Examples |
|------------------|-----------------|----------|
| **Implementation description** (body, overwrite-update) | **Edit the body** — update only when the implementation actually changed; otherwise preserve the existing body | Change summary, affected modules, design decisions, `Closes #N` |
| **Verification / process artifacts** (comment, append) | **Add a comment** — append whenever an artifact exists; only-add, never overwrite | **Test status & results, code review results**, browser-testing results, etc. |

## Mandatory scope

| Item | Rule |
|------|------|
| **PR body (implementation description, overwrite-update)** | **Always required.** Put the change summary, affected modules, design decisions, and `Closes #N` here. **Only update when the implementation itself was added/changed**; otherwise keep the original body. **Never put test status/results or code review results in the body.** |
| **Comment (verification artifacts, append)** | **Always append verification/process artifacts as comments**: test status & results, code review results, browser-testing results, etc. Append whenever an artifact exists; write `N/A` only when there is genuinely nothing to append. **Do not create noise comments.** |
| **Linked issue** | **Only when a linked issue exists.** Otherwise `N/A`. |
| **Closing keyword** | If the PR resolves an issue, put `Closes #N` / `Fixes #N` **in the PR body** (not in the issue). |

### Linked-issue detection

Check in order; the first match wins:

1. An issue explicitly named by the user.
2. An issue number in the branch name or PR title/body.
3. An existing `Closes` / `Fixes` reference already in the PR body.
4. `gh pr view <pr-number> --json closingIssuesReferences`.

If none match → treat as **no linked issue** (write `N/A` in the confirmation block).

## Body-safe: never blind-overwrite

`gh pr edit --body` and the issue `PATCH body=` operation **replace the entire body**. Therefore always:

1. **Read** the existing body first.
2. **Preserve** the existing content.
3. **Update or append only inside a controlled section** (e.g. `## Change Summary`) that holds **only the
   implementation description**.

Never blind-overwrite an existing PR template, issue description, requirements, or screenshots.
**Do not put test / code review results in the body — append them as comments instead.**

## Command examples

```bash
# 1. Read existing content first (preserve, then update — never overwrite)
gh pr view <pr-number> --json body,url,closingIssuesReferences

# 2. Edit the PR body (preserved body + updated/appended change-summary section; body contains Closes #N)
gh pr edit <pr-number> --body "<preserved body + change-summary section>"

# 3. Append test / code review results as a comment
#    (a PR is also an issue, so it shares the issues/.../comments endpoint)
gh api repos/{owner}/{repo}/issues/<pr-number>/comments -X POST -f body="<test / code review results>"

# 4. When a linked issue exists: read -> preserve -> update body / append comment
gh issue view <issue-number> --json body,url
gh api repos/{owner}/{repo}/issues/<issue-number> -X PATCH -f body="<preserved + updated>"
gh api repos/{owner}/{repo}/issues/<issue-number>/comments -X POST -f body="<comment>"
```

> See the rest of this skill (`SKILL.md`, [templates.md](templates.md)) for general issue/PR write conventions.

## Forcing function — emit this block before merging

After the updates are done and **before running the merge command**, emit the following block and verify each
line item:

```text
Pre-Merge Gate confirmation
- PR body updated/preserved (implementation): ✅ <PR URL>
- Closing keyword:        Closes #N / N/A
- Verification comment (test / code review results): ✅ <URL> / N/A
- Linked issue updated:   ✅ #N / N/A (with reason)
- Verified with:          gh pr view ... / (if needed) gh issue view ...
```

- **Merge is a separate action**: do **not** chain the PR/Issue update and the merge in the same shell command
  (update and verify first, then run the merge on its own).
- **If any item cannot be verified → STOP, do not merge.**

## Exception

If the PR has already been merged by a human on GitHub (state `MERGED`), there is no need to retroactively run
this gate — proceed directly to cleanup.
