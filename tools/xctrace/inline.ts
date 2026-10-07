// Out-of-line calls on a profile's hot paths. Instruments records only real
// frames, so a binary frame directly above another binary frame is a call the
// compiler kept out of line. Frameless leaves can hide their caller.
import type { RunInfo } from "./toc.ts";
import {
  headerLines,
  type IntervalUse,
  keptSamples,
  openTrace,
  type SummarizeOptions,
} from "./summarize.ts";

export type CallKind = "call" | "closure" | "copy" | "stub" | "unnamed";

export interface OutOfLineCall {
  caller: string;
  callee: string;
  kind: CallKind;
  /** Weight where the callee is the deepest frame in the binary: its own code
   *  plus everything it calls outside the binary. */
  local: number;
  /** The part of `local` spent outside the binary below the callee. */
  outside: number;
  /** Weight of samples containing the call, once per sample. */
  incl: number;
  /** Distinct caller return addresses: call sites seen. */
  sites: number;
}

export interface InlineReport {
  trace: string;
  run: RunInfo;
  interval: IntervalUse;
  binary: string;
  unit: string;
  sampleCount: number;
  total: number;
  calls: OutOfLineCall[];
}

const COPY_PREFIXES = [
  "outlined ",
  "initializeWithCopy for ",
  "initializeWithTake for ",
  "assignWithCopy for ",
  "assignWithTake for ",
  "destroy for ",
];

function callKind(callee: string): CallKind {
  if (callee.startsWith("DYLD-STUB$$")) return "stub";
  if (callee === "<deduplicated_symbol>") return "unnamed";
  if (COPY_PREFIXES.some((prefix) => callee.startsWith(prefix))) return "copy";
  if (
    callee.includes("closure #") || callee.startsWith("partial apply for ") ||
    callee.includes("thunk for ")
  ) {
    return "closure";
  }
  return "call";
}

export async function loadInlineReport(
  trace: string,
  binary: string,
  options: SummarizeOptions,
): Promise<InlineReport> {
  const opened = await openTrace(trace, options);
  if (opened.schema === "os-signpost") {
    throw new Error("inline needs a cpu-profile or time-profile table");
  }
  const calls = new Map<
    string,
    Omit<OutOfLineCall, "sites"> & { addrs: Set<number> }
  >();
  const callFor = (caller: string, callee: string) => {
    const key = `${caller}\u0000${callee}`;
    let call = calls.get(key);
    if (!call) {
      call = {
        caller,
        callee,
        kind: callKind(callee),
        local: 0,
        outside: 0,
        incl: 0,
        addrs: new Set(),
      };
      calls.set(key, call);
    }
    return call;
  };
  let sampleCount = 0;
  let total = 0;
  for await (const sample of keptSamples(opened, options.thread)) {
    sampleCount++;
    total += sample.weight;
    const stack = sample.stack;
    const deepest = stack.findIndex((frame) => frame.binary === binary);
    // A frame above itself (recursion or a frameless leaf) is no inlining edge.
    let above = deepest + 1;
    while (deepest !== -1 && stack[above]?.sym === stack[deepest].sym) above++;
    if (deepest !== -1 && stack[above]?.binary === binary) {
      const call = callFor(stack[above].sym, stack[deepest].sym);
      call.local += sample.weight;
      if (deepest > 0) call.outside += sample.weight;
    }
    const seen = new Set<string>();
    for (let depth = Math.max(deepest, 0); depth + 1 < stack.length; depth++) {
      const callee = stack[depth];
      const caller = stack[depth + 1];
      if (
        callee.binary !== binary || caller.binary !== binary ||
        caller.sym === callee.sym
      ) continue;
      const call = callFor(caller.sym, callee.sym);
      if (Number.isFinite(caller.addr)) call.addrs.add(caller.addr);
      const key = `${caller.sym}\u0000${callee.sym}`;
      if (seen.has(key)) continue;
      seen.add(key);
      call.incl += sample.weight;
    }
  }
  return {
    trace,
    run: opened.run,
    interval: opened.interval,
    binary,
    unit: opened.schema === "cpu-profile" ? "cycle-weight" : "weight",
    sampleCount,
    total,
    calls: [...calls.values()]
      .map(({ addrs, ...call }) => ({ ...call, sites: addrs.size }))
      .sort((a, b) => b.local - a.local || b.incl - a.incl),
  };
}

export function renderInlineText(report: InlineReport, top: number): string[] {
  const pct = (weight: number) =>
    (report.total > 0 ? (weight / report.total) * 100 : 0).toFixed(2)
      .padStart(6);
  const lines = headerLines(report);
  lines.push(
    `unit: ${report.unit}  samples: ${report.sampleCount}  total: ${
      Math.round(report.total)
    }`,
    `out-of-line calls within "${report.binary}" (top ${top} by local %):`,
    "  local% outside%  incl%  sites  kind     caller -> callee",
  );
  for (const call of report.calls.slice(0, top)) {
    lines.push(
      `  ${pct(call.local)}  ${pct(call.outside)}  ${pct(call.incl)}  ${
        String(call.sites).padStart(5)
      }  ${call.kind.padEnd(7)}  ${call.caller} -> ${call.callee}`,
    );
  }
  return lines;
}
