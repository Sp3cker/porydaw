// Summarize one trace: filter, aggregate, render text or JSON.
// Self weight = leaf-frame weight; inclusive = every distinct (binary, symbol)
// in the stack gets the sample weight once (recursion-safe via per-sample set).
import { basename } from "node:path";
import { findRun, inferSchema, loadToc } from "./toc.ts";
import type { RunInfo, SchemaName } from "./toc.ts";
import { exportRows, profileSamples, signpostEvents } from "./tables.ts";
import type { ProfileSample, SignpostEvent } from "./tables.ts";

export interface SummarizeOptions {
  schema?: SchemaName;
  run: number;
  intervalFlag?: [number, number];
  binary?: string;
  thread?: string;
  top: number;
  json: boolean;
}

export interface IntervalUse {
  start: number | null;
  end: number | null;
  source: "flag" | "sidecar" | "whole-run";
}

/** Sidecar lookup: <trace>.json, then <trace without .trace>.json.
 *  Accepts {startEpoch,endEpoch} or {start,end} in epoch seconds. */
export async function readSidecar(
  trace: string,
): Promise<[number, number] | null> {
  const candidates = [`${trace}.json`];
  if (trace.endsWith(".trace")) {
    candidates.push(trace.slice(0, -".trace".length) + ".json");
  }
  let firstError: string | undefined;
  for (const path of candidates) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(await Deno.readTextFile(path));
    } catch {
      continue;
    }
    if (typeof parsed !== "object" || parsed === null) {
      firstError ??= `bad sidecar ${path}: want {startEpoch,endEpoch} numbers`;
      continue;
    }
    // Sidecar JSON: shape-checked field by field below, never trusted blindly.
    const record = parsed as Record<string, unknown>;
    const start = record["startEpoch"] ?? record["start"];
    const end = record["endEpoch"] ?? record["end"];
    if (typeof start !== "number" || typeof end !== "number") {
      firstError ??= `bad sidecar ${path}: want {startEpoch,endEpoch} numbers`;
      continue;
    }
    if (!(start < end)) {
      firstError ??= `bad sidecar ${path} (start must precede end)`;
      continue;
    }
    return [start, end];
  }
  if (firstError !== undefined) throw new Error(firstError);
  return null;
}

export async function resolveInterval(
  trace: string,
  flag: [number, number] | undefined,
): Promise<IntervalUse> {
  if (flag) return { start: flag[0], end: flag[1], source: "flag" };
  const sidecar = await readSidecar(trace);
  if (sidecar) return { start: sidecar[0], end: sidecar[1], source: "sidecar" };
  return { start: null, end: null, source: "whole-run" };
}

export function threadKept(
  sample: ProfileSample,
  query: string | undefined,
): boolean {
  if (!query) return true;
  if (query.toLowerCase() === "main") return sample.mainThread;
  return sample.thread.toLowerCase().includes(query.toLowerCase());
}

function inInterval(epoch: number, interval: IntervalUse): boolean {
  if (interval.start === null || interval.end === null) return true;
  return epoch >= interval.start && epoch <= interval.end;
}

export interface SymbolStat {
  sym: string;
  binary: string;
  self: number;
  incl: number;
  samples: number;
}

export interface ProfileSummary {
  kind: "profile";
  trace: string;
  run: RunInfo;
  schema: SchemaName;
  unit: string;
  interval: IntervalUse;
  sampleCount: number;
  total: number;
  processes: { name: string; weight: number; pct: number }[];
  threads: { name: string; weight: number; pct: number; main: boolean }[];
  binaries: { name: string; self: number; pct: number }[];
  symbols: SymbolStat[];
  symbolScope: string | null;
}

export function aggregateProfile(
  trace: string,
  run: RunInfo,
  schema: SchemaName,
  samples: ProfileSample[],
  interval: IntervalUse,
  options: SummarizeOptions,
): ProfileSummary {
  const kept = samples.filter((sample) =>
    threadKept(sample, options.thread) &&
    inInterval(run.startEpoch + sample.tNs / 1e9, interval)
  );
  const total = kept.reduce((sum, sample) => sum + sample.weight, 0);
  const byProc = new Map<string, number>();
  const byThread = new Map<string, { weight: number; main: boolean }>();
  const byBinary = new Map<string, number>();
  const bySymbol = new Map<string, SymbolStat>();
  for (const sample of kept) {
    byProc.set(sample.proc, (byProc.get(sample.proc) ?? 0) + sample.weight);
    const thread = byThread.get(sample.thread) ??
      { weight: 0, main: sample.mainThread };
    thread.weight += sample.weight;
    byThread.set(sample.thread, thread);
    const leaf = sample.stack[0];
    if (leaf) {
      byBinary.set(
        leaf.binary,
        (byBinary.get(leaf.binary) ?? 0) + sample.weight,
      );
    }
    const seen = new Set<string>();
    for (let depth = 0; depth < sample.stack.length; depth++) {
      const frame = sample.stack[depth];
      const key = `${frame.binary}\u0000${frame.sym}`;
      if (seen.has(key)) continue;
      seen.add(key);
      let stat = bySymbol.get(key);
      if (!stat) {
        stat = {
          sym: frame.sym,
          binary: frame.binary,
          self: 0,
          incl: 0,
          samples: 0,
        };
        bySymbol.set(key, stat);
      }
      stat.incl += sample.weight;
      if (depth === 0) {
        stat.self += sample.weight;
        stat.samples += 1;
      }
    }
  }
  const pct = (weight: number) => total > 0 ? (weight / total) * 100 : 0;
  const symbols = [...bySymbol.values()]
    .filter((stat) => !options.binary || stat.binary === options.binary)
    .sort((a, b) => b.self - a.self);
  return {
    kind: "profile",
    trace,
    run,
    schema,
    unit: schema === "cpu-profile" ? "cycle-weight" : "weight",
    interval,
    sampleCount: kept.length,
    total,
    processes: [...byProc.entries()]
      .map(([name, weight]) => ({ name, weight, pct: pct(weight) }))
      .sort((a, b) => b.weight - a.weight),
    threads: [...byThread.entries()]
      .map(([name, entry]) => ({
        name,
        weight: entry.weight,
        pct: pct(entry.weight),
        main: entry.main,
      }))
      .sort((a, b) => b.weight - a.weight),
    binaries: [...byBinary.entries()]
      .map(([name, self]) => ({ name, self, pct: pct(self) }))
      .sort((a, b) => b.self - a.self),
    symbols,
    symbolScope: options.binary ?? null,
  };
}

export interface SignpostStat {
  subsystem: string;
  category: string;
  name: string;
  count: number;
  totalMs: number;
  minMs: number;
  medianMs: number;
  maxMs: number;
}

export interface SignpostSummary {
  kind: "signpost";
  trace: string;
  run: RunInfo;
  schema: SchemaName;
  interval: IntervalUse;
  groups: SignpostStat[];
  unpairedBegins: number;
  unpairedEnds: number;
  events: number;
}

function median(sorted: number[]): number {
  if (sorted.length === 0) return 0;
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

export function aggregateSignposts(
  trace: string,
  run: RunInfo,
  events: SignpostEvent[],
  interval: IntervalUse,
): SignpostSummary {
  const epoch = (tNs: number) => run.startEpoch + tNs / 1e9;
  // Pairing always runs over every event; the interval then keeps completed
  // intervals whose begin falls inside, plus in-interval unpaired/Event rows.
  const open = new Map<string, number[]>();
  const durations = new Map<string, { begin: number; ms: number }[]>();
  const unpairedEndEpochs: number[] = [];
  for (const event of [...events].sort((a, b) => a.tNs - b.tNs)) {
    const pairKey = JSON.stringify([
      event.subsystem,
      event.category,
      event.name,
      event.ident,
    ]);
    if (event.type === "Begin") {
      const stack = open.get(pairKey) ?? [];
      stack.push(event.tNs);
      open.set(pairKey, stack);
    } else if (event.type === "End") {
      const begin = open.get(pairKey)?.pop();
      if (begin === undefined) {
        unpairedEndEpochs.push(epoch(event.tNs));
      } else {
        const groupKey = JSON.stringify([
          event.subsystem,
          event.category,
          event.name,
        ]);
        const list = durations.get(groupKey) ?? [];
        list.push({ begin: epoch(begin), ms: (event.tNs - begin) / 1e6 });
        durations.set(groupKey, list);
      }
    }
  }
  const unpairedBeginEpochs: number[] = [];
  for (const stack of open.values()) {
    for (const begin of stack) unpairedBeginEpochs.push(epoch(begin));
  }
  const groups: SignpostStat[] = [...durations.entries()].map(([key, all]) => {
    const [subsystem, category, name] = JSON.parse(key) as [
      string,
      string,
      string,
    ];
    const ms = all
      .filter((entry) => inInterval(entry.begin, interval))
      .map((entry) => entry.ms)
      .sort((a, b) => a - b);
    return {
      subsystem,
      category,
      name,
      count: ms.length,
      totalMs: ms.reduce((sum, value) => sum + value, 0),
      minMs: ms.length ? ms[0] : 0,
      medianMs: median(ms),
      maxMs: ms.length ? ms[ms.length - 1] : 0,
    };
  }).filter((group) => group.count > 0)
    .sort((a, b) => b.totalMs - a.totalMs);
  return {
    kind: "signpost",
    trace,
    run,
    schema: "os-signpost",
    interval,
    groups,
    unpairedBegins:
      unpairedBeginEpochs.filter((t) => inInterval(t, interval)).length,
    unpairedEnds:
      unpairedEndEpochs.filter((t) => inInterval(t, interval)).length,
    events:
      events.filter((event) =>
        event.type !== "Begin" && event.type !== "End" &&
        inInterval(epoch(event.tNs), interval)
      ).length,
  };
}

export type Summary = ProfileSummary | SignpostSummary;

/** Load TOC + rows and aggregate for one trace under the given options. */
export async function loadSummary(
  trace: string,
  options: SummarizeOptions,
): Promise<Summary> {
  const runs = await loadToc(trace);
  const run = findRun(runs, options.run);
  const schema = options.schema ?? inferSchema(run);
  const interval = await resolveInterval(trace, options.intervalFlag);
  const rows = await exportRows(trace, options.run, schema);
  if (schema === "os-signpost") {
    return aggregateSignposts(trace, run, signpostEvents(rows), interval);
  }
  return aggregateProfile(
    trace,
    run,
    schema,
    profileSamples(rows),
    interval,
    options,
  );
}

export function parseIntervalFlag(value: string): [number, number] {
  const parts = value.split(",").map(Number);
  if (parts.length !== 2 || parts.some((n) => !Number.isFinite(n))) {
    throw new Error(`bad --interval ${value} (want <startEpoch>,<endEpoch>)`);
  }
  if (!(parts[0] < parts[1])) {
    throw new Error(`bad --interval ${value} (start must precede end)`);
  }
  return [parts[0], parts[1]];
}

function intervalLabel(interval: IntervalUse): string {
  if (interval.start === null || interval.end === null) return "whole run";
  return `${interval.start},${interval.end} (${interval.source})`;
}

function headerLines(summary: Summary): string[] {
  const run = summary.run;
  const duration = Number.isFinite(run.durationSec)
    ? `  duration: ${run.durationSec.toFixed(3)} s`
    : "";
  return [
    `trace: ${summary.trace}`,
    `run: ${run.number}  template: ${run.template}${duration}`,
    `interval: ${intervalLabel(summary.interval)}`,
  ];
}

function weightCell(weight: number, unit: string): string {
  if (unit === "weight") return `${(weight / 1e6).toFixed(2)} ms`;
  return String(Math.round(weight));
}

/** Compact human summary; never raw XML. */
export function renderText(summary: Summary, top: number): string[] {
  const lines = headerLines(summary);
  if (summary.kind === "profile") {
    lines.push(`unit: ${summary.unit}  samples: ${summary.sampleCount}`);
    lines.push("process:");
    for (const proc of summary.processes) {
      lines.push(
        `  ${proc.name} ${weightCell(proc.weight, summary.unit)} (${
          proc.pct.toFixed(1)
        }%)`,
      );
    }
    lines.push("thread:");
    for (const thread of summary.threads.slice(0, top)) {
      const main = thread.main ? " [main]" : "";
      lines.push(
        `  ${thread.name}${main} ${weightCell(thread.weight, summary.unit)} (${
          thread.pct.toFixed(1)
        }%)`,
      );
    }
    lines.push(`binary self (top ${top}):`);
    for (const binary of summary.binaries.slice(0, top)) {
      lines.push(
        `  ${binary.name} ${weightCell(binary.self, summary.unit)} (${
          binary.pct.toFixed(1)
        }%)`,
      );
    }
    const scope = summary.symbolScope
      ? ` in binary "${summary.symbolScope}"`
      : "";
    lines.push(`symbol self/incl${scope} (top ${top}):`);
    lines.push(
      `  ${"self".padStart(12)} ${"incl".padStart(12)} ${
        "samples".padStart(7)
      }  symbol`,
    );
    for (const sym of summary.symbols.slice(0, top)) {
      lines.push(
        `  ${weightCell(sym.self, summary.unit).padStart(12)} ` +
          `${weightCell(sym.incl, summary.unit).padStart(12)} ` +
          `${String(sym.samples).padStart(7)}  ${sym.sym} [${sym.binary}]`,
      );
    }
  } else {
    lines.push(`signpost intervals (unit: ms):`);
    lines.push(
      `  ${"count".padStart(5)} ${"total".padStart(10)} ${"min".padStart(8)} ${
        "median".padStart(8)
      } ${"max".padStart(8)}  subsystem / category / name`,
    );
    for (const group of summary.groups.slice(0, top)) {
      lines.push(
        `  ${String(group.count).padStart(5)} ` +
          `${group.totalMs.toFixed(2).padStart(10)} ` +
          `${group.minMs.toFixed(2).padStart(8)} ` +
          `${group.medianMs.toFixed(2).padStart(8)} ` +
          `${group.maxMs.toFixed(2).padStart(8)}  ` +
          `${group.subsystem} / ${group.category} / ${group.name}`,
      );
    }
    if (summary.groups.length === 0) lines.push("  (no completed intervals)");
    lines.push(
      `unpaired begins: ${summary.unpairedBegins}  unpaired ends: ${summary.unpairedEnds}  events: ${summary.events}`,
    );
  }
  return lines;
}

export function summaryJson(summary: Summary): unknown {
  return {
    trace: summary.trace,
    run: summary.run.number,
    template: summary.run.template,
    durationSec: summary.run.durationSec,
    interval: summary.interval.start === null ? null : {
      start: summary.interval.start,
      end: summary.interval.end,
      source: summary.interval.source,
    },
    ...(summary.kind === "profile"
      ? {
        schema: summary.schema,
        unit: summary.unit,
        samples: summary.sampleCount,
        total: summary.total,
        processes: summary.processes,
        threads: summary.threads,
        binaries: summary.binaries,
        symbols: summary.symbols,
        symbolScope: summary.symbolScope,
      }
      : {
        schema: summary.schema,
        groups: summary.groups,
        unpairedBegins: summary.unpairedBegins,
        unpairedEnds: summary.unpairedEnds,
        events: summary.events,
      }),
  };
}

export function shortTrace(trace: string): string {
  return basename(trace);
}
