// XML plumbing for xctrace exports: fast-xml-parser DOM plus id/ref resolution.
//
// Discovered xctrace column names (see tables.ts for row shapes):
//   cpu-profile : time/sample-time, thread/thread, process/process, core/core,
//                 thread-state/thread-state, weight/cycle-weight, stack/tagged-backtrace
//   time-profile: same, but weight/weight
//   os-signpost : time/event-time, thread/thread, process/process,
//                 event-type/event-type, scope/string, identifier/os-signpost-identifier,
//                 name/signpost-name, format-string/format-string, backtrace/text-backtrace
//                 (empty cells export as <sentinel/>), subsystem/subsystem,
//                 category/category, message/os-log-metadata, emit-location/return-location
//   toc run info: target/device/process/environment, summary/start-date/end-date/
//                 duration/template-name, processes/process, data/table[@schema]
import { XMLParser } from "fast-xml-parser";

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  textNodeName: "#text",
  // Repeated elements always arrive as arrays so callers never branch.
  isArray: (name) =>
    name === "row" || name === "col" || name === "node" ||
    name === "table" || name === "run" || name === "frame" ||
    name === "item" || name === "process",
  trimValues: true,
  parseTagValue: false,
});

/** Parse an xctrace XML export; throws a one-line Error on malformed input. */
export function parseXml(text: string): Record<string, unknown> {
  try {
    const doc = parser.parse(text, true) as unknown;
    if (typeof doc !== "object" || doc === null) {
      throw new Error("empty XML document");
    }
    return doc as Record<string, unknown>;
  } catch (error) {
    throw new Error(
      `unparsable XML: ${firstLine(error)}`,
    );
  }
}

export function firstLine(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.split("\n")[0];
}

/** Plain-object test for parsed-XML nodes (FXP objects carry @_ attrs). */
export function isObj(node: unknown): node is Record<string, unknown> {
  return typeof node === "object" && node !== null && !Array.isArray(node);
}

/** Collect every element with an id attribute into id -> element. */
export function collectIds(
  root: unknown,
  into: Map<string, unknown> = new Map(),
): Map<string, unknown> {
  if (Array.isArray(root)) {
    for (const item of root) collectIds(item, into);
  } else if (isObj(root)) {
    const id = root["@_id"];
    if (typeof id === "string") into.set(id, root);
    for (const value of Object.values(root)) collectIds(value, into);
  }
  return into;
}

/**
 * Deep-copy a parsed tree with every {@_ref} element replaced by its id
 * target. xctrace reuses backtraces, frames, binaries, threads, processes,
 * weights and timestamps this way; callers work on plain resolved trees.
 */
export function deref(root: unknown, ids: Map<string, unknown>): unknown {
  return derefOne(root, ids, []);
}

function derefOne(
  node: unknown,
  ids: Map<string, unknown>,
  stack: string[],
): unknown {
  if (Array.isArray(node)) {
    return node.map((item) => derefOne(item, ids, stack));
  }
  if (!isObj(node)) return node;
  const ref = node["@_ref"];
  if (typeof ref === "string") {
    if (stack.includes(ref)) return {};
    const target = ids.get(ref);
    if (target === undefined) return {};
    return derefOne(target, ids, [...stack, ref]);
  }
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(node)) {
    if (key === "@_id" || key === "@_ref") continue;
    out[key] = derefOne(value, ids, stack);
  }
  return out;
}

/** Element text: leaf strings, {#text} leaves, or "" for empty/sentinel nodes. */
export function text(node: unknown): string {
  if (typeof node === "string") return node;
  if (!isObj(node)) return "";
  const inner = node["#text"];
  if (typeof inner === "string") return inner;
  if (typeof inner === "number") return String(inner);
  return "";
}

/** Numeric leaf value; NaN when absent/unparsable (callers decide strictness). */
export function num(node: unknown): number {
  const raw = text(node).trim();
  if (!raw) return NaN;
  return Number(raw);
}

/** fmt="..." display string of an element, else "". */
export function fmt(node: unknown): string {
  if (!isObj(node)) return "";
  const value = node["@_fmt"];
  return typeof value === "string" ? value : "";
}

/** First child under key, unwrapping single-element arrays. */
export function child(node: unknown, key: string): unknown {
  if (!isObj(node)) return undefined;
  const value = node[key];
  if (Array.isArray(value)) return value[0];
  return value;
}

/** Child list under key: [] when absent, unwrapping FXP's repeated-tag arrays. */
export function childList(node: unknown, key: string): unknown[] {
  if (!isObj(node)) return [];
  const value = node[key];
  if (value === undefined) return [];
  return Array.isArray(value) ? value : [value];
}

/** Run a command, capturing stdout; throws a one-line Error on failure. */
export async function runCapture(cmd: string, args: string[]): Promise<string> {
  let output;
  try {
    const childProcess = new Deno.Command(cmd, {
      args,
      stdin: "null",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
    output = await childProcess.output();
  } catch (error) {
    throw new Error(`${cmd} failed to start: ${firstLine(error)}`);
  }
  const decoder = new TextDecoder();
  if (!output.success) {
    throw new Error(
      `${cmd} ${args[0] ?? ""} failed: ${
        firstLine(decoder.decode(output.stderr).trim() || `code ${output.code}`)
      }`,
    );
  }
  return decoder.decode(output.stdout);
}
