// Compare before/after trace pairs: per-pair reduction plus median reduction
// for the process total, main thread, --binary self, and any --metric.
// Each trace uses its own interval (flag overrides that trace's sidecar).
import {
  loadSummary,
  type ProfileSummary,
  type SignpostSummary,
  type SummarizeOptions,
} from "./summarize.ts";

export interface CompareOptions extends SummarizeOptions {
  metric?: string;
}

function reduction(before: number, after: number): number | null {
  if (before === 0) return after === 0 ? 0 : null;
  return ((before - after) / before) * 100;
}

function formatReduction(value: number | null): string {
  if (value === null) return "n/a";
  if (value === 0) return "0.0%";
  return `${value >= 0 ? "-" : "+"}${Math.abs(value).toFixed(1)}%`;
}

function median(values: (number | null)[]): number | null {
  const present = values.filter((v): v is number => v !== null);
  if (present.length === 0) return null;
  const sorted = [...present].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** Resolve --metric against threads, then binaries, then symbols (exact
 *  match first, else first case-insensitive substring hit, labelled). */
function metricWeights(
  summary: ProfileSummary,
  metric: string,
): { label: string; weight: number } | null {
  const query = metric.toLowerCase();
  const thread = summary.threads.find((t) => t.name.toLowerCase() === query) ??
    summary.threads.find((t) => t.name.toLowerCase().includes(query));
  if (thread) {
    return { label: `thread "${thread.name}"`, weight: thread.weight };
  }
  const binary = summary.binaries.find((b) => b.name === metric) ??
    summary.binaries.find((b) => b.name.toLowerCase().includes(query));
  if (binary) return { label: `binary "${binary.name}"`, weight: binary.self };
  const sym = summary.symbols.find((s) => s.sym === metric) ??
    summary.symbols.find((s) => s.sym.toLowerCase().includes(query));
  if (sym) {
    return { label: `symbol "${sym.sym}" [${sym.binary}]`, weight: sym.self };
  }
  return null;
}

function loadForCompare(
  trace: string,
  options: CompareOptions,
): Promise<ProfileSummary | SignpostSummary> {
  // Full symbol maps stay in memory here so --metric can hit outside top N;
  // the --binary scope only selects the binary-self row, never the lookup set.
  return loadSummary(trace, {
    ...options,
    binary: undefined,
    top: Number.MAX_SAFE_INTEGER,
  });
}

function mainThreadWeight(summary: ProfileSummary): number {
  return summary.threads
    .filter((t) => t.main)
    .reduce((sum, t) => sum + t.weight, 0);
}

export interface CompareMetricValue {
  before: number;
  after: number;
  reductionPct: number | null;
}

export interface ComparePairMetrics {
  processTotal: CompareMetricValue;
  mainThread?: CompareMetricValue;
  binarySelf?: CompareMetricValue;
  metric?: CompareMetricValue;
}

export interface ComparePair {
  before: { trace: string; interval: string; source: string };
  after: { trace: string; interval: string; source: string };
  unit: string;
  processLabel: string;
  metricLabel?: string;
  metrics: ComparePairMetrics;
}

export interface CompareResult {
  pairs: ComparePair[];
  medians: Record<string, number | null>;
  dropped: number;
}

/** Row order for the text renderer; maps text keys to structured metrics. */
const MEDIAN_ROWS: { key: string; metric: keyof ComparePairMetrics }[] = [
  { key: "process", metric: "processTotal" },
  { key: "main", metric: "mainThread" },
  { key: "binary", metric: "binarySelf" },
  { key: "metric", metric: "metric" },
];

function endpoint(trace: string, summary: ProfileSummary | SignpostSummary) {
  return {
    trace,
    interval: describeInterval(summary),
    source: summary.interval.source,
  };
}

export async function compareStructured(
  befores: string[],
  afters: string[],
  options: CompareOptions,
): Promise<CompareResult> {
  if (befores.length === 0 || befores.length !== afters.length) {
    throw new Error(
      `compare needs equal before/after counts (got ${befores.length} vs ${afters.length})`,
    );
  }
  const pairs: ComparePair[] = [];
  for (let i = 0; i < befores.length; i++) {
    const before = await loadForCompare(befores[i], options);
    const after = await loadForCompare(afters[i], options);
    if (before.kind !== after.kind) {
      throw new Error(
        `pair ${i + 1}: schema mismatch (${before.schema} vs ${after.schema})`,
      );
    }
    const metrics: ComparePairMetrics = {
      processTotal: { before: 0, after: 0, reductionPct: null },
    };
    let unit = "ms";
    let processLabel = "signpost total";
    let metricLabel: string | undefined;
    if (before.kind === "profile" && after.kind === "profile") {
      unit = before.unit;
      processLabel = "process total";
      const row = (b: number, a: number): CompareMetricValue => ({
        before: b,
        after: a,
        reductionPct: reduction(b, a),
      });
      metrics.processTotal = row(before.total, after.total);
      metrics.mainThread = row(
        mainThreadWeight(before),
        mainThreadWeight(after),
      );
      if (options.binary) {
        const bWeight = (s: ProfileSummary) =>
          s.binaries.find((b) => b.name === options.binary)?.self ?? 0;
        metrics.binarySelf = row(bWeight(before), bWeight(after));
      }
      if (options.metric) {
        const bMetric = metricWeights(before, options.metric);
        const aMetric = metricWeights(after, options.metric);
        metricLabel = bMetric?.label ?? aMetric?.label ??
          `"${options.metric}" (not found)`;
        metrics.metric = row(bMetric?.weight ?? 0, aMetric?.weight ?? 0);
      }
    } else if (before.kind === "signpost" && after.kind === "signpost") {
      const bTotal = Math.round(
        before.groups.reduce((s, g) => s + g.totalMs, 0) * 100,
      ) / 100;
      const aTotal = Math.round(
        after.groups.reduce((s, g) => s + g.totalMs, 0) * 100,
      ) / 100;
      metrics.processTotal = {
        before: bTotal,
        after: aTotal,
        reductionPct: reduction(bTotal, aTotal),
      };
    }
    pairs.push({
      before: endpoint(befores[i], before),
      after: endpoint(afters[i], after),
      unit,
      processLabel,
      metricLabel,
      metrics,
    });
  }
  const medians: Record<string, number | null> = {};
  let dropped = 0;
  for (const row of MEDIAN_ROWS) {
    const values: (number | null)[] = [];
    for (const pair of pairs) {
      const entry = pair.metrics[row.metric];
      if (entry !== undefined) values.push(entry.reductionPct);
    }
    if (values.length === 0) continue;
    dropped += values.filter((v) => v === null).length;
    medians[row.metric] = median(values);
  }
  return { pairs, medians, dropped };
}

/** Text renderer over the same values as the JSON output. */
export function renderCompareLines(
  result: CompareResult,
  options: CompareOptions,
): string[] {
  const lines: string[] = [];
  const staticLabels: Record<keyof ComparePairMetrics, string> = {
    processTotal: "process total",
    mainThread: "main thread",
    binarySelf: options.binary ? `binary "${options.binary}" self` : "binary",
    metric: "metric",
  };
  result.pairs.forEach((pair, i) => {
    lines.push(`pair ${i + 1}: ${pair.before.trace} vs ${pair.after.trace}`);
    lines.push(`  before interval: ${pair.before.interval}`);
    lines.push(`  after interval: ${pair.after.interval}`);
    for (const row of MEDIAN_ROWS) {
      const value = pair.metrics[row.metric];
      if (!value) continue;
      const label = row.metric === "metric" && pair.metricLabel
        ? pair.metricLabel
        : row.metric === "processTotal"
        ? pair.processLabel
        : staticLabels[row.metric];
      lines.push(
        `  ${label}: ${value.before} -> ${value.after} ${pair.unit} (${
          formatReduction(value.reductionPct)
        } reduction)`,
      );
    }
  });
  lines.push(`median reduction over ${result.pairs.length} pair(s):`);
  for (const row of MEDIAN_ROWS) {
    if (!(row.metric in result.medians)) continue;
    const values = result.pairs.map((p) =>
      p.metrics[row.metric]?.reductionPct ?? null
    );
    const droppedCount = values.filter((v) => v === null).length;
    let line = `  ${row.key}: ${
      formatReduction(result.medians[row.metric] ?? null)
    }`;
    if (droppedCount > 0) {
      line += ` (${droppedCount} pair(s) dropped: zero baseline)`;
    }
    lines.push(line);
  }
  return lines;
}

export function compareJson(result: CompareResult): unknown {
  return {
    pairs: result.pairs.map((pair) => ({
      before: { ...pair.before },
      after: { ...pair.after },
      metrics: Object.fromEntries(
        (Object.entries(pair.metrics) as [string, CompareMetricValue][]).map((
          [key, value],
        ) => [key, { ...value }]),
      ),
    })),
    medians: { ...result.medians },
    dropped: result.dropped,
  };
}

export async function compareTraces(
  befores: string[],
  afters: string[],
  options: CompareOptions,
): Promise<string[]> {
  const result = await compareStructured(befores, afters, options);
  return renderCompareLines(result, options);
}

function describeInterval(summary: ProfileSummary | SignpostSummary): string {
  const interval = summary.interval;
  if (interval.start === null || interval.end === null) return "whole run";
  return `${interval.start},${interval.end} (${interval.source})`;
}
