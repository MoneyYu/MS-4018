# Phase 5 — Validate & end-to-end test

There is **no app build/test suite** in a course repo. The checks that matter are Terraform/script
static checks plus a **real** apply→destroy in Azure.

## Static checks (always, before committing)

```powershell
# Terraform (run from the TERRAFORM/ folder)
terraform fmt -recursive        # format; use -check in CI
terraform init -backend=false   # first time / after provider changes
terraform validate              # must pass

# PowerShell scripts — AST parse (no test runner exists)
Get-ChildItem TERRAFORM/scripts/*.ps1 | ForEach-Object {
  $e=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e)
  if ($e.Count) { "FAIL: $($_.Name)"; $e } else { "OK: $($_.Name)" }
}
```

## End-to-end test (the real proof)

`terraform apply` needs `az login`, a target subscription, and **model quota in the region** — it
**cannot** run in CI. To validate the backup actually works:

1. Use **today's date** as `group_postfix` (e.g. `MMDD` → `0609`). Run `terraform plan` first as a
   dry check (confirm names like `<COURSE>-0609`).
2. `terraform apply` — watch for the data-plane scripts to complete (sample data uploaded, analyzer
   created, search index built with the expected doc count).
3. `terraform destroy` — confirm a clean teardown.
4. On failure, **clean up partial resource groups** before retrying. If retrying, pass a different
   `group_postfix` (or region var) so you build a fresh RG. **Never delete anything unrelated to the
   Terraform deployment.**

## Azure constraint playbook (the ones that actually bite)

| Symptom | Cause | Fix |
|---------|-------|-----|
| Storage `403` "Key based authentication is not permitted" | Azure Policy: shared-key auth disabled | Convert the stack to **AAD-only** (Phase 3): `shared_access_key_enabled=false`, managed identity + RBAC, scripts use `az` tokens. |
| `local_auth_enabled=false` account returns 401 on the data-plane | Missing **`custom_subdomain_name`** (regional endpoints don't support Entra ID) | Add `custom_subdomain_name` to every key-less Cognitive/DocIntel account. |
| Image model `InsufficientQuota` (e.g. "available capacity 0") | **Subscription quota** for that image model is used up | Reduce another deployment's capacity to free units, **or** parameterize the image model and pick one with free quota. (You control this.) |
| AI Search `InsufficientResourcesAvailable: region out of resources` | **Regional capacity** on Microsoft's side (not your quota) | Deploy that service in a nearby region via its override var (e.g. `search_location=eastus`). (You can't fix it; it may be transient.) |
| Cognitive account name "already exists" right after a destroy | **48-hour soft-delete name reservation** | Switch `random_str` to the dynamic `random_string` for a fresh suffix (Phase 3). |

**Quota vs capacity:** *quota* is your subscription's allocation cap (you can free/raise it);
*regional capacity* is Microsoft's datacenter availability for a service+SKU+region (you can't —
change region or retry).

## Then

Run `terraform fmt`/`validate` once more, confirm the scripts still parse, and only then commit.
Record the e2e result (resource count, indexed-doc count) as an issue comment (Phase 7).
