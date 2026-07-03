# Architecture

## Runtime flow

```
Discord --> OpenClaw --> n8n Cloud --> Supabase Cloud / OpenRouter --> Discord
```

- **Discord** is the interface — traders interact via messages/commands in channels.
- **OpenClaw** listens to Discord and talks **only to n8n webhooks**. It never calls Supabase, OpenRouter, or Discord's API directly — every action it takes is routed through an n8n workflow's webhook trigger.
- **n8n Cloud** is the orchestration layer. Workflows receive OpenClaw's webhook calls, run logic (Code nodes, IF routing, data shaping), and call out to Supabase Cloud (via the `supabase_service` credential) and OpenRouter (via the `openrouter` credential) as needed.
- **Supabase Cloud** is the database — trade logs, session data, and other persisted state, following the schema conventions in the root `CLAUDE.md`.
- **OpenRouter** provides LLM access for any AI-assisted steps (e.g. weekly review generation, trade analysis).
- Results flow back out to **Discord** via the `discord_bot` credential, split into test vs. real channels by the `is_test` router present in every workflow.

## Why OpenClaw only talks to n8n

Keeping OpenClaw's only external surface as n8n webhooks means:
- All business logic, schema knowledge, and prompt handling lives in one place (this repo, deployed to n8n).
- Credentials for Supabase/OpenRouter/Discord never need to be duplicated into OpenClaw's config.
- Every action is inherently loggable/replayable as an n8n execution.

## Config vs. secrets

- **Secrets** (API keys, tokens) are n8n Credentials, referenced by name: `supabase_service`, `openrouter`, `discord_bot`. They live in the n8n Cloud UI, not in this repo.
- **Non-secret config** (model IDs, channel IDs, base URLs) are n8n Variables, accessed as `$vars.*` inside nodes, so the same workflow JSON works across test/real environments without code changes.

## This repo's role

This repo holds no runtime code. It is:
- The source of truth for workflow JSON (`modules/*/workflows/`, `shared/workflows/`).
- The source for function-node JS (`modules/*/functions/`) and runtime prompts (`modules/*/prompts/`).
- The source for Supabase schema SQL (`modules/*/schema/`, `shared/schema/`).
- The sync tooling (`scripts/push.js`, `scripts/pull.js`) that moves workflow definitions between here and n8n Cloud.

See `docs/playbook.md` for the day-to-day loop of building and shipping a workflow.
