import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

export function loadEnv(rootDir) {
  const envPath = join(rootDir, ".env");
  if (!existsSync(envPath)) return;

  const lines = readFileSync(envPath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;

    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

export function getApiConfig() {
  const apiUrl = process.env.N8N_API_URL;
  const apiKey = process.env.N8N_API_KEY;

  if (!apiUrl || !apiKey) {
    throw new Error(
      "Missing N8N_API_URL or N8N_API_KEY. Copy .env.example to .env and fill in your n8n Cloud API details."
    );
  }

  return {
    baseUrl: `${apiUrl.replace(/\/$/, "")}/api/v1`,
    headers: {
      "X-N8N-API-KEY": apiKey,
      "Content-Type": "application/json",
    },
  };
}

export async function n8nRequest(config, path, options = {}) {
  const res = await fetch(`${config.baseUrl}${path}`, {
    ...options,
    headers: { ...config.headers, ...(options.headers ?? {}) },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`n8n API ${options.method ?? "GET"} ${path} failed: ${res.status} ${body}`);
  }

  if (res.status === 204) return null;
  return res.json();
}

export async function findWorkflowByName(config, name) {
  const result = await n8nRequest(config, "/workflows");
  const workflows = result.data ?? result;
  return workflows.find((wf) => wf.name === name) ?? null;
}

// Stable stringify: sorts object keys recursively so git diffs stay clean.
export function stableStringify(value, indent = 2) {
  const sortKeys = (input) => {
    if (Array.isArray(input)) return input.map(sortKeys);
    if (input !== null && typeof input === "object") {
      return Object.keys(input)
        .sort()
        .reduce((acc, key) => {
          acc[key] = sortKeys(input[key]);
          return acc;
        }, {});
    }
    return input;
  };
  return JSON.stringify(sortKeys(value), null, indent) + "\n";
}
