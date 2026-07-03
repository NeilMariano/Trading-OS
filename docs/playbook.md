# Playbook

## The experiment loop

```
edit --> push --> test in #os-lab via /webhook-test --> commit --> activate
```

1. **Edit** — change workflow JSON, function JS, prompt markdown, or schema SQL in the repo.
2. **Push** — `npm run push -- <workflow-name>` (or `npm run push -- --all`) to sync the workflow to n8n Cloud. This inlines any matching `modules/*/functions/*.js` files into their Code nodes.
3. **Test in `#os-lab`** — trigger the workflow's test webhook URL (`/webhook-test/...` in n8n) with `is_test: true` in the payload. Confirm output lands in `#os-lab` and any DB rows are flagged `is_test = true`.
4. **Commit** — once the workflow behaves correctly, commit the JSON/JS/SQL/prompt changes to git.
5. **Activate** — flip the workflow to active in n8n Cloud (or re-run push once satisfied) so it responds to real webhook calls, and confirm real-channel/real-row behavior with a deliberate `is_test: false` run before relying on it.

## Starting a new experiment from the skeleton

1. Copy `shared/workflows/_skeleton.json` to `modules/<module>/workflows/<name>.json`.
2. Rename the workflow (`name` field) and the `Webhook` node's `path` to something unique.
3. Replace the `Work` node's placeholder code with real logic, or swap it for whatever nodes the experiment needs — keep it between `Config` and `Is Test?` if it needs to run regardless of test/real, or move it after `Is Test?` if the two branches should diverge.
4. Wire `settings.errorWorkflow` to the actual global error handler workflow's ID once one exists.
5. If the work involves a Code node, put its logic in `modules/<module>/functions/<Node Name>.js` — `push.js` inlines it automatically by matching node name to filename.
6. If the work involves an LLM prompt, put it in `modules/<module>/prompts/<name>.md` and fetch it at runtime (never hardcode it in the node).
7. Run through the experiment loop above.

## `is_test` convention

- `is_test: true` — output goes to `#os-lab`, and any Supabase rows written are flagged `is_test = true`. Use this for all development and testing.
- `is_test: false` — output goes to real channels, and DB rows are real. Only use once a workflow is verified working.
- Every workflow's `Is Test?` IF node should read `is_test` from the incoming payload (set in the `Config` node), defaulting to `true` if not provided, so an accidental omission fails safe into the test path.
