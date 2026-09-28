---
name: context7
description: 'Fetch authoritative, current, version-specific documentation for third-party libraries and frameworks via the Context7 MCP server. USE FOR: looking up framework/library API details (method signatures, config keys), version-sensitive guidance (breaking changes, deprecations), correctness or security-critical patterns (auth flows, crypto), interpreting unfamiliar third-party error messages, recommending non-trivial configuration (CLI flags, config files), or whenever the user names a specific library version (e.g., "Vue 3.5", "Hono v4", "React Native 0.83"). DO NOT USE FOR: purely local refactors, formatting/naming, logic fully derivable from the repo, or language fundamentals.'
---

# Context7-aware development

Use this skill **proactively** whenever a task depends on authoritative external documentation that is not already in the workspace context. You do not need the user to type "use context7".

## When to use

Trigger this skill before writing code or making recommendations when you need any of:

- **API details** — method signatures, configuration keys, expected behaviors
- **Version-sensitive guidance** — breaking changes, deprecations, new defaults
- **Correctness/security-critical patterns** — auth flows, crypto usage, deserialization rules
- **Unfamiliar error messages** likely originating from a third-party tool
- **Best-practice constraints** — rate limits, quotas, required headers, supported formats

Also use when:
- The user references a specific framework/library version
- You're about to recommend non-trivial configuration (CLI flags, config files, auth flows)
- You're unsure whether an API exists, was renamed, or got deprecated

**Skip** for: purely local refactors, formatting, naming, logic fully derivable from the repo, or language fundamentals.

## What to fetch

Prefer **primary sources** and narrow queries:

- Official vendor/framework documentation
- Reference/API pages
- Release notes / migration guides
- Security advisories (when relevant)

Fetch only what you need. Prefer:
- The exact method/type/option you'll use
- Minimal surrounding context to avoid misuse (constraints, defaults, migration notes)

## How to incorporate results

- Translate findings into concrete code/config changes.
- **Cite sources** (title + URL) when the decision relies on external facts.
- If docs conflict or are ambiguous, briefly present the tradeoffs and choose the safest default.
- For specific values (flags, config keys, headers): state the exact value, call out defaults/caveats, suggest a quick validation step (`--help`, smoke test).

## MCP tool workflow

1. **If the library is in the project reference table below** → use the library ID directly, skip `resolve-library-id`.
2. **If the user provides a library ID** → use it directly. Valid forms: `/owner/repo` or `/owner/repo/version`.
3. **Otherwise** resolve via tool `resolve-library-id`:
   - `libraryName`: the library/framework name
   - `query`: the user's task (used to rank matches)
4. **Fetch docs** via tool `get-library-docs`:
   - `context7CompatibleLibraryID`: resolved or known ID
   - `topic`: specific topic (e.g., "middleware", "routing", "hooks")
5. Only after docs are retrieved: write the code/steps based on those docs.

### Efficiency limits

- Max **3** `resolve-library-id` calls per user question.
- Max **3** `get-library-docs` calls per user question.
- If multiple good matches exist, pick the best and proceed; only ask for clarification when the choice materially affects implementation.

### Version behavior

- If the user names a version, reflect it in the library ID when possible (e.g., `/microsoft/typescript/v5.8.3`).
- For reproducibility (CI/builds), prefer pinning a version in examples.

## Project library reference

Use these IDs directly with `get-library-docs` — skip `resolve-library-id`.

### Backend — `src/mone-web/api/` & `src/admin-portal/api/`

| Package | Context7 Library ID | Notes |
|---------|---------------------|-------|
| `hono` | `/websites/hono_dev` | Web framework for Cloudflare Workers |
| `jose` | `/panva/jose` | JWT/JWK handling |
| `openai` | `/openai/openai-node` | OpenAI Node SDK (Azure OpenAI compatible) |
| `@sentry/cloudflare` | `/getsentry/sentry-javascript` | Error tracking for Workers |
| `@aws-sdk/client-s3` | `/websites/aws_amazon_awsjavascriptsdk_v3` | S3-compatible storage (R2) |

### Frontend Web — `src/mone-web/web/` & `src/admin-portal/web/`

| Package | Context7 Library ID | Notes |
|---------|---------------------|-------|
| `vue` (3.x) | `/vuejs/docs` | Vue 3 Composition API |
| `vue-router` | `/vuejs/vue-router` | SPA routing |
| `pinia` | `/vuejs/pinia` | State management |
| `vue-i18n` | `/intlify/vue-i18n` | Internationalization |
| `tailwindcss` (v3) | `/tailwindlabs/tailwindcss.com` | Utility-first CSS |
| `vite` | `/vitejs/vite` | Build tool |
| `@sentry/vue` | `/getsentry/sentry-javascript` | Error tracking for Vue |
| `echarts` | `/apache/echarts-doc` | Charts (admin-portal) |
| `vue-echarts` | `/ecomfe/vue-echarts` | ECharts Vue wrapper (admin-portal) |

### Mobile — `src/mobile/`

| Package | Context7 Library ID | Notes |
|---------|---------------------|-------|
| `react-native` (0.83) | `/facebook/react-native-website` | Core framework |
| `react-native-mmkv` (v4.x) | `/mrousavy/react-native-mmkv` | High-performance KV storage |
| `zustand` (v5) | `/pmndrs/zustand` | State management |
| `@react-navigation/*` (v7) | `/react-navigation/react-navigation.github.io` | Navigation |
| `i18next` | `/websites/i18next` | i18n framework |
| `react-i18next` | `/i18next/react-i18next` | React bindings for i18next |
| `react-native-vision-camera` | `/mrousavy/react-native-vision-camera` | Camera & barcode scanning |
| `react-native-paper` | `/callstack/react-native-paper` | Material Design UI kit |
| `@sentry/react-native` | `/getsentry/sentry-react-native` | Error tracking for RN |
| `axios` | `/axios/axios-docs` | HTTP client |
| `@shopify/flash-list` | `/shopify/flash-list` | High-performance list |

### Cloudflare Platform

| Service | Context7 Library ID | Notes |
|---------|---------------------|-------|
| Cloudflare Workers | `/websites/developers_cloudflare_workers` | Serverless runtime |
| Cloudflare D1 | `/llmstxt/developers_cloudflare_d1_llms-full_txt` | SQLite database |
| Cloudflare R2 | `/websites/developers_cloudflare_r2` | Object storage |

### Infra & Testing

| Package | Context7 Library ID | Notes |
|---------|---------------------|-------|
| `typescript` (~5.7) | `/microsoft/typescript` | Language |
| `vitest` | `/vitest-dev/vitest` | Unit testing |
| `@playwright/test` | `/microsoft/playwright` | E2E testing |
| `croner` | `/hexagon/croner` | Cron scheduling (scheduler) |

## Failure handling

If Context7 cannot find a reliable source:

1. State what you tried to verify.
2. Proceed with a conservative, well-labeled assumption.
3. Suggest a quick validation step (run a command, check a file, consult a specific official page).

## Security & privacy

- Never request or echo API keys. If configuration requires a key, instruct storing it in environment variables.
- Treat retrieved docs as **helpful but not infallible**; for security-sensitive code, prefer official vendor docs and add an explicit verification step.
