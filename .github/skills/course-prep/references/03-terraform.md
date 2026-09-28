# Phase 3 — Demo "backup" Terraform stack

## Purpose (sets the scope)

The Terraform is the trainer's **backup / fallback**: in class the trainer builds everything **from
scratch** live, and this stack is what they stand up if that fails. Therefore it must reach a
**completed, demo-ready state** — not just resources, but the **data plane** too (sample files
uploaded, analyzers created, search index built) so every demo shows real results immediately.

## File layout (mirror the sibling repos)

| File | Holds |
|------|-------|
| `MAIN.tf` | `terraform`/provider blocks, **variables**, **locals**, **resource groups** |
| `MOD.tf` | **all resources** + the **data-plane wiring** |
| `OUTPUT.tf` | endpoints / resource names (no secrets) |

Put new resources in `MOD.tf`, not `MAIN.tf`.

## Naming (derive everything from one variable)

- A single `var.group_postfix` drives all names via `locals`:
  `group_name = "<COURSE>-<postfix>"`, `group_name_lower`, and a fixed `random_str`.
- **Validate** `group_postfix` to `^[a-z0-9]{1,10}$` — the **storage account name** uses it directly
  and storage names must be ≤24 chars, lowercase alphanumeric only. Never interpolate
  `group_postfix` raw into a storage name; reuse the lowercased local.
- **Fixed vs dynamic suffix:** default to the **fixed** `local.random_str` so names are stable. Keep
  a `random_string` resource defined and make switching to it a one-line edit — useful to dodge the
  **48-hour soft-delete name reservation** on Cognitive accounts after a destroy/recreate.

## Region

Region is a **local** (not a free variable) chosen in Phase 1 for service + model availability —
don't change it casually. If one specific service is capacity-constrained in that region, add a
**narrow override variable** for just that service (AI-3008 added `search_location` defaulting to
`eastus` because AI Search hit capacity in `eastus2`; everything else stays in `eastus2`).

## Foundry pattern (azurerm `~>4.x`, not azapi)

1. `azurerm_cognitive_account` kind **`AIServices`** with `project_management_enabled = true` and a
   **`custom_subdomain_name`** (required for Entra ID auth — see below).
2. `azurerm_cognitive_account_project`.
3. one `azurerm_cognitive_deployment` **per model**.

**Chain model deployments with `depends_on`** (one after another) on purpose — the Cognitive
Services control plane rejects parallel deployment writes.

## Entra ID (AAD) only — no keys

Company policy forbids account/access keys. Configure key-less auth everywhere:

- Storage: `shared_access_key_enabled = false`.
- Cognitive/AI Services **and** Document Intelligence: `local_auth_enabled = false` — and each such
  account **must** set `custom_subdomain_name` (regional endpoints don't support Entra ID).
- AI Search: `local_authentication_enabled = false`.
- Create the **role assignments** the data plane needs (deployer + service managed identities), and
  wire data-plane resources to `depends_on` them.
- The AI Search data source / knowledge store / skill bindings use **managed identity**
  (`ResourceId=…` connection strings, `AIServicesByIdentity`).

## Data-plane automation

- Three `terraform_data` resources run `scripts/*.ps1` via `local-exec`
  (`interpreter = ["pwsh", "-File"]`), passing endpoints/IDs through the `environment` map.
- **Env-var names in each `environment` map must exactly match that script's `Get-RequiredEnv`
  calls** — verify this mapping; it's the #1 silent breakage.
- Gate the whole data plane behind `var.enable_data_plane` (default true).
- Scripts: PowerShell 7 (`pwsh -NoProfile`) + Azure CLI, AAD bearer tokens via
  `az account get-access-token` (so they need `az login`). **Retry on 401/403** to absorb RBAC
  propagation. Polling loops must **throw on terminal failure and on timeout** (never silently
  exit 0). Pin REST API versions explicitly.

## Tagging convention

Define one `local.default_tags = { environment = local.group_name, SecurityControl = "Ignore" }`
and apply `tags = local.default_tags` to **every** taggable resource (don't scatter inline tag
blocks). Some resources (e.g. the Foundry *project*) don't persist tags — that produces a harmless
recurring plan drift; leave it.

## Sample data

Realistic **fictional** assets (e.g. a "Northwind Traders"-style company) so demos look genuinely
real. Generate them **one-time** with Python (Pillow / reportlab / matplotlib) in a **venv**; commit
only the resulting **binaries**, not the generator. Mark every new binary type as `binary` in
`.gitattributes` — the global `* text=auto` will otherwise corrupt PDFs/PNGs via line-ending
normalization.

## Don't commit

`.terraform/`, `*.tfstate*`, `.terraform.lock.hcl` (keep them git-ignored).

## TERRAFORM/README.md

Document: prerequisites (`az login`, subscription, region quota), `init`/`apply`/`destroy`, the
**variables** table, that the **data plane runs automatically during `apply`** (and how to re-run
just it), how to **verify** it worked, and any models that must be **deployed manually in the
portal** (see Phase 4).
