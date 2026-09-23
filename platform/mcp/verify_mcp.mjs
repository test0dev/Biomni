#!/usr/bin/env node
/**
 * External-client style MCP verification for biomni-arm.
 * Spawns the full-tool stdio server, lists tools, then calls design_knockout_sgrna
 * against the shared data lake (real-path simulation for Mastra / other hosts).
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { homedir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");
const LAKE =
  process.env.BIOMNI_DATA_LAKE_PATH || path.join(homedir(), "biomni-data-lake");
const CONDA_SH =
  process.env.CONDA_SH || path.join(homedir(), "miniconda3/etc/profile.d/conda.sh");
/** When set, print every tool name from listTools (default: summary + required tools only). */
const LIST_ALL_TOOLS = process.env.MCP_LIST_ALL_TOOLS === "1";

const serverCmd = [
  `source "${CONDA_SH}"`,
  "conda activate biomni_e1",
  `source "${REPO_ROOT}/platform/setup_path.sh"`,
  `cd "${REPO_ROOT}"`,
  `export BIOMNI_DATA_LAKE_PATH="${LAKE}"`,
  "python tutorials/examples/expose_biomni_server/run_mcp_server.py",
].join(" && ");

function hr(title) {
  const line = "=".repeat(72);
  console.log(`\n${line}`);
  if (title) console.log(`  ${title}`);
  console.log(line);
}

function sub(title) {
  console.log(`\n--- ${title} ---`);
}

function dump(label, value) {
  console.log(`${label}:`);
  if (typeof value === "string") {
    console.log(value);
    return;
  }
  console.log(JSON.stringify(value, null, 2));
}

function parseToolPayload(result) {
  const text = result?.content?.[0]?.text;
  if (typeof text !== "string") {
    throw new Error(`Unexpected MCP content: ${JSON.stringify(result)}`);
  }
  try {
    return JSON.parse(text);
  } catch {
    return { result: text };
  }
}

function summarizeTools(tools) {
  return tools.map((t) => ({
    name: t.name,
    description: (t.description || "").slice(0, 120),
    required: t.inputSchema?.required ?? [],
    properties: Object.keys(t.inputSchema?.properties ?? {}),
  }));
}

async function main() {
  hr("Biomni MCP verify (stdio client)");
  dump("config", {
    lake: LAKE,
    repo: REPO_ROOT,
    list_all_tools: LIST_ALL_TOOLS,
    server_cmd: serverCmd,
  });

  sub("spawn server");
  console.log("transport: StdioClientTransport");
  console.log(`command: bash -lc <server_cmd>`);

  const transport = new StdioClientTransport({
    command: "bash",
    args: ["-lc", serverCmd],
    stderr: "inherit",
  });

  const client = new Client({ name: "biomni-arm-mcp-verify", version: "1.0.0" });
  await client.connect(transport);
  console.log("connected: yes");

  try {
    // ---------- tools/list ----------
    hr("1) tools/list");
    const listRequest = {};
    dump("request", {
      method: "tools/list",
      params: listRequest,
      options: { timeout: 120_000 },
    });

    const listed = await client.listTools(listRequest, { timeout: 120_000 });
    const tools = listed.tools || [];
    const names = new Set(tools.map((t) => t.name));

    dump("response.summary", {
      tool_count: tools.length,
      has_nextCursor: Boolean(listed.nextCursor),
      nextCursor: listed.nextCursor ?? null,
    });

    if (LIST_ALL_TOOLS) {
      sub("response.tools (all names)");
      for (const [i, t] of tools.entries()) {
        console.log(`${String(i + 1).padStart(3, " ")}. ${t.name}`);
      }
    } else {
      sub("response.tools (first 10, set MCP_LIST_ALL_TOOLS=1 for full list)");
      dump("sample", summarizeTools(tools.slice(0, 10)));
    }

    const requiredNames = ["design_knockout_sgrna", "query_uniprot"];
    sub("required tools (full schema)");
    for (const required of requiredNames) {
      if (!names.has(required)) {
        throw new Error(`Missing required tool: ${required}`);
      }
      const tool = tools.find((t) => t.name === required);
      dump(required, {
        name: tool.name,
        description: tool.description,
        inputSchema: tool.inputSchema,
      });
    }

    if (tools.length < 200) {
      throw new Error(`Expected ~224 tools, got ${tools.length}`);
    }
    console.log(`\nok: listTools returned ${tools.length} tools; required tools present`);

    // ---------- tools/call ----------
    hr("2) tools/call  design_knockout_sgrna");
    const callParams = {
      name: "design_knockout_sgrna",
      arguments: {
        gene_name: "TP53",
        data_lake_path: LAKE,
        species: "human",
        num_guides: 1,
      },
    };
    dump("request", {
      method: "tools/call",
      params: callParams,
      options: { timeout: 300_000 },
    });

    const call = await client.callTool(callParams, undefined, { timeout: 300_000 });

    sub("response (raw MCP CallToolResult)");
    dump("raw", {
      isError: call.isError ?? false,
      content: call.content,
      structuredContent: call.structuredContent ?? null,
      _meta: call._meta ?? null,
    });

    const payload = parseToolPayload(call);
    sub("response.content[0].text (parsed JSON)");
    dump("payload", payload);

    if (payload && typeof payload === "object" && "error" in payload && payload.error) {
      throw new Error(`Tool returned error: ${payload.error}`);
    }

    const blob = JSON.stringify(payload).toLowerCase();
    if (!blob.includes("tp53") && !blob.includes("sgrna") && !blob.includes("guide")) {
      throw new Error(
        `Unexpected tool payload (no guide markers): ${JSON.stringify(payload).slice(0, 500)}`,
      );
    }

    console.log("\nok: design_knockout_sgrna read lake and returned guides");
    hr("PASS");
  } finally {
    await client.close().catch(() => {});
  }
}

main().catch((err) => {
  hr("FAIL");
  console.error(err);
  process.exit(1);
});
