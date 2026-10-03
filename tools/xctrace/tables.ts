// Row extraction for the three supported schemas. Every export goes through
// id/ref resolution (see xml.ts) so backtraces, frames, binaries, threads,
// processes, weights and timestamps arrive as plain trees.
import {
  child,
  childList,
  collectIds,
  deref,
  fmt,
  isObj,
  num,
  parseXml,
  runCapture,
  text,
} from "./xml.ts";
import type { SchemaName } from "./toc.ts";

export interface Frame {
  sym: string;
  binary: string;
}

export interface ProfileSample {
  /** Nanoseconds since run start, as exported. */
  tNs: number;
  thread: string;
  mainThread: boolean;
  proc: string;
  weight: number;
  /** Leaf first. */
  stack: Frame[];
}

export type SignpostType = "Begin" | "End" | "Event" | string;

export interface SignpostEvent {
  tNs: number;
  type: SignpostType;
  subsystem: string;
  category: string;
  name: string;
  ident: string;
}
/** Export one table (all matching nodes merged: os-signpost repeats per
 *  category) and return its resolved rows. */
export async function exportRows(
  trace: string,
  run: number,
  schema: SchemaName,
): Promise<unknown[]> {
  const xml = await runCapture("xcrun", [
    "xctrace",
    "export",
    "--input",
    trace,
    "--xpath",
    `/trace-toc/run[@number="${run}"]/data/table[@schema="${schema}"]`,
  ]);
  const doc = parseXml(xml);
  const result = child(doc, "trace-query-result");
  const nodes = childList(result, "node");
  if (nodes.length === 0) {
    throw new Error(`missing table: no ${schema} table in run ${run}`);
  }
  const rows: unknown[] = [];
  for (const node of nodes) rows.push(...childList(node, "row"));
  return rows.map((row) => deref(row, collectIds(doc)));
}

function displayName(fmtValue: string, fallback: string): string {
  const cut = fmtValue.indexOf(" (0x");
  if (cut > 0) return fmtValue.slice(0, cut);
  return fmtValue || fallback;
}

function threadFields(thread: unknown): { name: string; main: boolean } {
  const name = displayName(
    fmt(thread),
    `tid ${text(child(thread, "tid")) || "?"}`,
  );
  return { name, main: name.toLowerCase() === "main thread" };
}

function procName(process: unknown): string {
  const name = displayName(fmt(process), "");
  // fmt is "name (pid)"; the bare name keys cross-trace aggregation.
  const bare = name.replace(/ \([0-9]+\)$/, "");
  if (bare) return bare;
  return text(child(process, "pid")) || "?";
}
function backtraceFrames(tagged: unknown): Frame[] {
  const frames = childList(child(tagged, "backtrace"), "frame");
  return frames.map((frame) => {
    if (!isObj(frame)) return { sym: "?", binary: "?" };
    const rawName = frame["@_name"];
    const sym = typeof rawName === "string" && rawName
      ? rawName
      : fmt(frame) || "?";
    const binary = child(frame, "binary");
    const binaryName = isObj(binary) && typeof binary["@_name"] === "string" &&
        binary["@_name"]
      ? binary["@_name"]
      : "?";
    return { sym, binary: binaryName };
  });
}

/** Typed samples from cpu-profile (cycle-weight) or time-profile (weight) rows. */
export function profileSamples(rows: unknown[]): ProfileSample[] {
  return rows.map((row) => {
    const time = num(child(row, "sample-time"));
    const thread = child(row, "thread");
    const { name, main } = threadFields(thread);
    const weightNode = child(row, "cycle-weight") ?? child(row, "weight");
    return {
      tNs: time,
      thread: name,
      mainThread: main,
      proc: procName(child(row, "process")),
      weight: num(weightNode),
      stack: backtraceFrames(child(row, "tagged-backtrace")),
    };
  }).filter((sample) =>
    Number.isFinite(sample.tNs) && Number.isFinite(sample.weight)
  );
}

export function signpostEvents(rows: unknown[]): SignpostEvent[] {
  return rows.map((row) => ({
    tNs: num(child(row, "event-time")),
    type: text(child(row, "event-type")) || "?",
    subsystem: text(child(row, "subsystem")),
    category: text(child(row, "category")),
    name: text(child(row, "signpost-name")),
    ident: text(child(row, "os-signpost-identifier")),
  })).filter((event) => Number.isFinite(event.tNs));
}
