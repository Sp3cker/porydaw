// Row extraction for the three supported schemas, streamed from `xctrace
// export`: rows arrive one at a time with id/ref reuse already resolved.
import {
  attr,
  child,
  children,
  exportElements,
  num,
  text,
  type XmlElement,
} from "./xml.ts";
import type { SchemaName } from "./toc.ts";

export interface Frame {
  sym: string;
  binary: string;
  /** Sampled pc (leaf) or return address; NaN when not exported. */
  addr: number;
}

export interface ProfileSample {
  /** Nanoseconds since run start, as exported. */
  tNs: number;
  thread: string;
  mainThread: boolean;
  proc: string;
  weight: number;
  /** Leaf first; shared between samples with the same backtrace. */
  stack: readonly Frame[];
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

/** Stream one table's rows (os-signpost repeats one node per category). */
export async function* exportRows(
  trace: string,
  run: number,
  schema: SchemaName,
): AsyncGenerator<XmlElement> {
  let nodes = 0;
  for await (
    const element of exportElements([
      "xctrace",
      "export",
      "--input",
      trace,
      "--xpath",
      `/trace-toc/run[@number="${run}"]/data/table[@schema="${schema}"]`,
    ], { row: true, node: true })
  ) {
    if (element.name === "node") nodes++;
    else yield element;
  }
  if (nodes === 0) {
    throw new Error(`missing table: no ${schema} table in run ${run}`);
  }
}

function displayName(fmtValue: string, fallback: string): string {
  const cut = fmtValue.indexOf(" (0x");
  if (cut > 0) return fmtValue.slice(0, cut);
  return fmtValue || fallback;
}

function procName(process: XmlElement | undefined): string {
  const name = displayName(attr(process, "fmt"), "");
  // fmt is "name (pid)"; the bare name keys cross-trace aggregation.
  const bare = name.replace(/ \([0-9]+\)$/, "");
  if (bare) return bare;
  return text(child(process, "pid")) || "?";
}

function backtraceFrames(tagged: XmlElement | undefined): Frame[] {
  // cpu-profile puts frames directly under <tagged-backtrace>; others nest <backtrace>.
  const holder = child(tagged, "backtrace") ?? tagged;
  return children(holder, "frame").map((frame) => ({
    sym: attr(frame, "name") || attr(frame, "fmt") || "?",
    binary: attr(child(frame, "binary"), "name") || "?",
    addr: parseInt(attr(frame, "addr"), 16),
  }));
}

/** Typed samples from cpu-profile (cycle-weight) or time-profile (weight) rows. */
export async function* profileSamples(
  rows: AsyncIterable<XmlElement>,
): AsyncGenerator<ProfileSample> {
  // Refs resolve to one shared element, so repeated backtraces convert once.
  const stacks = new WeakMap<XmlElement, Frame[]>();
  for await (const row of rows) {
    const tNs = num(child(row, "sample-time"));
    const weight = num(child(row, "cycle-weight") ?? child(row, "weight"));
    if (!Number.isFinite(tNs) || !Number.isFinite(weight)) continue;
    const thread = child(row, "thread");
    const name = displayName(
      attr(thread, "fmt"),
      `tid ${text(child(thread, "tid")) || "?"}`,
    );
    const tagged = child(row, "tagged-backtrace");
    let stack = tagged && stacks.get(tagged);
    if (!stack) {
      stack = backtraceFrames(tagged);
      if (tagged) stacks.set(tagged, stack);
    }
    yield {
      tNs,
      thread: name,
      mainThread: name.toLowerCase() === "main thread",
      proc: procName(child(row, "process")),
      weight,
      stack,
    };
  }
}

export async function* signpostEvents(
  rows: AsyncIterable<XmlElement>,
): AsyncGenerator<SignpostEvent> {
  for await (const row of rows) {
    const tNs = num(child(row, "event-time"));
    if (!Number.isFinite(tNs)) continue;
    yield {
      tNs,
      type: text(child(row, "event-type")) || "?",
      subsystem: text(child(row, "subsystem")),
      category: text(child(row, "category")),
      name: text(child(row, "signpost-name")),
      ident: text(child(row, "os-signpost-identifier")),
    };
  }
}
