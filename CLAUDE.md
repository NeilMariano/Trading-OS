# Trading-OS — Claude Code Instructions

## What This Project Is
Trading-OS is a modular team operating system. Its first module is `trading` (US index futures: NQ, ES, YM, RTY). The runtime is **n8n Cloud** + **Supabase Cloud** + **OpenRouter** + **Discord**. This repo is an artifact store and sync tool — nothing here runs in production.

## Your Role
You BUILD artifacts only. You are never part of the runtime. Anything you produce here — workflow JSON, schema SQL, prompt markdown, function JS — is deployed to n8n Cloud / Supabase Cloud via the sync scripts, not executed from this repo.

## Standing Rules

### Target: n8n Cloud (not self-hosted)
- Code nodes are **vanilla JS only** — no npm imports, no `require`, no external packages. n8n Cloud Code nodes run in a sandbox with no module resolution.
- Secrets are n8n **Credentials**, referenced by name only: `supabase_service`, `openrouter`, `discord_bot`. Never hardcode a secret value in workflow JSON or function JS.
- Non-secret config (model IDs, channel IDs, base URLs) uses n8n **Variables**, accessed as `$vars.*` inside nodes. Never hardcode these either — they change between test and real environments.

### Workflow JSON is source of truth
- `modules/*/workflows/*.json` and `shared/workflows/*.json` are the canonical definitions. The n8n Cloud instance is a deployment target, not the source of truth.
- Sync with `scripts/push.js` (repo → n8n Cloud) and `scripts/pull.js` (n8n Cloud → repo), both using the n8n public API.
- Never hand-edit a workflow in the n8n Cloud UI and consider it done — pull it back into the repo immediately after.

### Function-node JS
- Authored in `modules/*/functions/*.js`, one file per Code node.
- `push.js` inlines each file into the matching Code node by name: node `name` must equal the filename minus `.js`. Keep node names and filenames in sync.

### Every workflow must include
1. A manual or webhook trigger, even if the workflow is normally cron-triggered — so it can always be run on demand for testing.
2. A standard `is_test` IF router: test branch → `#os-lab` Discord channel + DB rows flagged `is_test = true`; real branch → real channels + real rows.
3. An error output wired to the global error handler workflow.

### Prompts
- Runtime LLM prompts live in `modules/*/prompts/*.md` and are fetched at runtime (e.g. via an HTTP Request node or Supabase storage read) — never hardcoded into a node's parameters.

### Schema conventions
- `snake_case` everywhere.
- Every table carries `trader_id`.
- Timestamps are `timestamptz`, stored in UTC.
- Prices: `numeric(12,2)`.
- R (risk multiple): `numeric(6,2)`.
- `session` enum: `asia | london | ny_am | ny_pm`.
- Trade rows carry `source`, `external_ref`, and `is_test`.

## File Structure
```
modules/trading/    trading module: schema, workflows, prompts, functions, docs
shared/              cross-module schema and workflow patterns (e.g. skeleton, error handler)
openclaw/            OpenClaw config and skills — OpenClaw talks ONLY to n8n webhooks
scripts/             push.js / pull.js — sync repo <-> n8n Cloud
docs/                architecture.md, playbook.md, decisions/ (ADRs)
```

## Build Rules
1. Do not invent workflows, schema, or prompts beyond what's asked — build exactly what is specified.
2. Never add npm dependencies to a Code node's logic — it will fail on n8n Cloud.
3. Never put a secret value in a workflow JSON file — reference the Credential by name.
4. When adding a new experiment, start from `shared/workflows/_skeleton.json` (see `docs/playbook.md`).
5. Flag any conflict with the rules above before proceeding — don't silently resolve it.
