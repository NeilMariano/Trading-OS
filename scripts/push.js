import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnv, getApiConfig, n8nRequest, findWorkflowByName } from "./lib.js";

const rootDir = join(dirname(fileURLToPath(import.meta.url)), "..");
loadEnv(rootDir);

function findWorkflowFiles(root) {
  const dirs = [
    join(root, "shared", "workflows"),
    ...listModuleDirs(root).map((mod) => join(root, "modules", mod, "workflows")),
  ];

  const files = [];
  for (const dir of dirs) {
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir)) {
      if (entry.endsWith(".json") && !entry.startsWith("_")) {
        files.push(join(dir, entry));
      }
    }
  }
  return files;
}

function listModuleDirs(root) {
  const modulesDir = join(root, "modules");
  if (!existsSync(modulesDir)) return [];
  return readdirSync(modulesDir).filter((entry) =>
    statSync(join(modulesDir, entry)).isDirectory()
  );
}

function findFunctionFiles(root) {
  // Map of node name -> absolute path to its .js source
  const map = new Map();
  const dirs = [
    join(root, "shared", "functions"),
    ...listModuleDirs(root).map((mod) => join(root, "modules", mod, "functions")),
  ];

  for (const dir of dirs) {
    if (!existsSync(dir)) continue;
    for (const entry of readdirSync(dir)) {
      if (entry.endsWith(".js")) {
        map.set(basename(entry, ".js"), join(dir, entry));
      }
    }
  }
  return map;
}

function inlineFunctions(workflow, functionMap) {
  let inlined = 0;
  for (const node of workflow.nodes ?? []) {
    if (node.type !== "n8n-nodes-base.code") continue;
    const srcPath = functionMap.get(node.name);
    if (!srcPath) continue;

    const code = readFileSync(srcPath, "utf8");
    node.parameters = node.parameters ?? {};
    node.parameters.jsCode = code;
    inlined++;
  }
  return inlined;
}

async function pushWorkflow(config, filePath, functionMap) {
  const name = basename(filePath, ".json");
  const workflow = JSON.parse(readFileSync(filePath, "utf8"));

  const inlined = inlineFunctions(workflow, functionMap);

  const existing = await findWorkflowByName(config, workflow.name ?? name);

  // n8n rejects unknown/read-only fields on write.
  const payload = {
    name: workflow.name ?? name,
    nodes: workflow.nodes,
    connections: workflow.connections,
    settings: workflow.settings ?? {},
  };

  if (existing) {
    await n8nRequest(config, `/workflows/${existing.id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    console.log(`updated: ${name} (${inlined} function node(s) inlined)`);
  } else {
    await n8nRequest(config, "/workflows", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    console.log(`created: ${name} (${inlined} function node(s) inlined)`);
  }
}

async function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error("Usage: node scripts/push.js <workflow-name> | --all");
    process.exit(1);
  }

  const config = getApiConfig();
  const functionMap = findFunctionFiles(rootDir);
  const allFiles = findWorkflowFiles(rootDir);

  const targets =
    arg === "--all"
      ? allFiles
      : allFiles.filter((f) => basename(f, ".json") === arg);

  if (targets.length === 0) {
    console.error(`No workflow file found matching "${arg}"`);
    process.exit(1);
  }

  for (const filePath of targets) {
    await pushWorkflow(config, filePath, functionMap);
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
