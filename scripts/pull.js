import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnv, getApiConfig, n8nRequest, stableStringify } from "./lib.js";

const rootDir = join(dirname(fileURLToPath(import.meta.url)), "..");
loadEnv(rootDir);

// Fields n8n adds/mutates server-side that would otherwise cause noisy diffs.
const VOLATILE_KEYS = ["versionId", "createdAt", "updatedAt", "tags", "pinData", "meta"];

function listModuleDirs(root) {
  const modulesDir = join(root, "modules");
  if (!existsSync(modulesDir)) return [];
  return readdirSync(modulesDir).filter((entry) =>
    statSync(join(modulesDir, entry)).isDirectory()
  );
}

function findExistingWorkflowPath(root, name) {
  const dirs = [
    join(root, "shared", "workflows"),
    ...listModuleDirs(root).map((mod) => join(root, "modules", mod, "workflows")),
  ];
  for (const dir of dirs) {
    const candidate = join(dir, `${name}.json`);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

function findFunctionDir(root, nodeName) {
  const dirs = [
    join(root, "shared", "functions"),
    ...listModuleDirs(root).map((mod) => join(root, "modules", mod, "functions")),
  ];
  for (const dir of dirs) {
    if (existsSync(join(dir, `${nodeName}.js`))) return dir;
  }
  return null;
}

function extractFunctions(root, workflow) {
  let extracted = 0;
  for (const node of workflow.nodes ?? []) {
    if (node.type !== "n8n-nodes-base.code") continue;
    const code = node.parameters?.jsCode;
    if (typeof code !== "string") continue;

    const dir = findFunctionDir(root, node.name);
    if (!dir) continue; // no local function file established yet for this node

    writeFileSync(join(dir, `${node.name}.js`), code);
    extracted++;
  }
  return extracted;
}

function cleanWorkflow(workflow) {
  const clean = { ...workflow };
  for (const key of VOLATILE_KEYS) delete clean[key];
  return clean;
}

async function pullWorkflow(config, summary) {
  const full = await n8nRequest(config, `/workflows/${summary.id}`);
  const clean = cleanWorkflow(full);

  const extracted = extractFunctions(rootDir, clean);

  let targetPath = findExistingWorkflowPath(rootDir, full.name);
  let note = "";
  if (!targetPath) {
    targetPath = join(rootDir, "shared", "workflows", `${full.name}.json`);
    note = " (new — wrote to shared/workflows/, move into a module if appropriate)";
  }

  writeFileSync(targetPath, stableStringify(clean));
  console.log(`pulled: ${full.name} -> ${targetPath} (${extracted} function file(s) updated)${note}`);
}

async function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error("Usage: node scripts/pull.js <workflow-name> | --all");
    process.exit(1);
  }

  const config = getApiConfig();
  const result = await n8nRequest(config, "/workflows");
  const workflows = result.data ?? result;

  const targets = arg === "--all" ? workflows : workflows.filter((wf) => wf.name === arg);

  if (targets.length === 0) {
    console.error(`No workflow found on n8n matching "${arg}"`);
    process.exit(1);
  }

  for (const summary of targets) {
    await pullWorkflow(config, summary);
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
