// Checks-only, calibrated GUI-thread measurements; never injects into the app.
import { join, resolve } from "node:path";

const HELP = `usage: deno task bench:allocations [options]
  --scenario <name>   note-draw|automation-commit|window-resize (required)
  --mode <mode>       allocations|cpu (default allocations)
  --warmup <count>    unmeasured operations per phase (default 64, >= 0)
  --iterations <n>    measured operations per phase (default 1000, > 0)
  --runs <count>      sequential fresh check processes (default 3, > 0)
  --output <path>     also write the structured JSON report to this path
  --help              show this help without building

Darwin only. Builds a private profiling dylib once with clang, then uses the
normal Debug Deno check runner and fixture staging. No app automation/injection.
Inherited MallocStackLogging variants are removed. Raw captures and failure
stdout/stderr are retained in the report before temporary files are removed.
Allocation-mode CPU is heap-hook-distorted, NOT independent CPU performance.
Use --mode cpu for independent CPU-only sampling without heap-counter claims;
both modes still include capture/clock overhead, and are not whole-process or
render-thread measurements. Window resizing includes one bounded queued GUI
turn and a separate identical empty-turn control; no control is subtracted.

Adding an arbitrary scenario driver: implement the checks-only AllocationProbe
and AllocationBenchmarkOptions interface. Keep setup/validation/reset outside
begin/pause; warm the same operation and discard warmup counters. Use one
measured segment per operation and scenario-prefixed labels.
Capture an identical empty control for unavoidable event-loop driver overhead.
Register its exact phases/scope and check task here explicitly; this runner
currently supports only the three names above. Run independent CPU mode too.
Example: deno task bench:allocations --scenario note-draw --mode cpu --runs 3`;

type Scenario = "note-draw" | "automation-commit" | "window-resize";
type Mode = "allocations" | "cpu";
export interface Options {
  scenario: Scenario;
  mode: Mode;
  warmup: number;
  iterations: number;
  runs: number;
  output?: string;
}

const SCENARIOS: Record<Scenario, { labels: string[]; scope: string }> = {
  "note-draw": {
    labels: ["note-draw.stroke", "note-draw.release-commit"],
    scope: "GUI-thread synchronous Swift/presenter; queued QML/render excluded",
  },
  "automation-commit": {
    labels: ["automation-commit.release-commit"],
    scope:
      "GUI-thread synchronous automation release and SongDocument commit/publication; queued QML/render excluded",
  },
  "window-resize": {
    labels: [
      "window-resize.geometry-event-turn",
      "window-resize.empty-event-turn",
    ],
    scope:
      "GUI-thread real window geometry and one bounded queued Qt turn; render thread and physical window dragging excluded",
  },
};

export function parseOptions(args: string[]): Options | null {
  let scenario: Scenario | undefined;
  let mode: Mode = "allocations";
  let warmup = 64;
  let iterations = 1000;
  let runs = 3;
  let output: string | undefined;
  let help = false;
  const seen = new Set<string>();
  for (let i = 0; i < args.length; i++) {
    const separator = args[i].indexOf("=");
    const flag = separator < 0 ? args[i] : args[i].slice(0, separator);
    if (flag === "--help" && separator < 0) {
      help = true;
      continue;
    }
    if (
      ![
        "--scenario",
        "--mode",
        "--warmup",
        "--iterations",
        "--runs",
        "--output",
      ].includes(flag)
    ) {
      throw new Error(`unknown argument ${args[i]}`);
    }
    if (seen.has(flag)) throw new Error(`duplicate argument ${flag}`);
    seen.add(flag);
    const value = separator < 0 ? args[++i] : args[i].slice(separator + 1);
    if (!value || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }
    if (flag === "--scenario") {
      if (
        value !== "note-draw" && value !== "automation-commit" &&
        value !== "window-resize"
      ) {
        throw new Error(
          "--scenario requires note-draw, automation-commit, or window-resize",
        );
      }
      scenario = value;
    } else if (flag === "--mode") {
      if (value !== "allocations" && value !== "cpu") {
        throw new Error("--mode requires allocations or cpu");
      }
      mode = value;
    } else if (flag === "--output") output = resolve(value);
    else {
      const count = Number(value);
      const minimum = flag === "--warmup" ? 0 : 1;
      if (
        !/^\d+$/.test(value) || !Number.isSafeInteger(count) || count < minimum
      ) {
        throw new Error(
          `${flag} requires a ${
            minimum === 0 ? "nonnegative" : "positive"
          } safe integer`,
        );
      }
      if (flag === "--warmup") warmup = count;
      else if (flag === "--iterations") iterations = count;
      else runs = count;
    }
  }
  if (help) return null;
  if (!scenario) throw new Error("--scenario is required");
  return { scenario, mode, warmup, iterations, runs, output };
}

type JsonRecord = Record<string, unknown>;
const HEAP_COUNTERS = [
  "allocations",
  "allocatedbytes",
  "frees",
  "reallocations",
  "reallocinplace",
  "failedallocations",
  "failedreallocations",
] as const;
type HeapCounter = typeof HEAP_COUNTERS[number];
interface Phase {
  label: string;
  operations: number;
  threadid: number;
  capturedsegments: number;
  cpu_ns: number;
  heap?: Record<HeapCounter, number>;
}
interface Capture {
  phases: Phase[];
  previouslogger: boolean;
}

interface Distribution {
  median: number;
  min: number;
  max: number;
}
interface MetricSummary {
  total: Distribution;
  per_operation: Distribution;
}
export interface Summary {
  warnings: string[];
  phases: {
    label: string;
    operations: Distribution;
    capturedsegments: Distribution;
    threadids: number[];
    cpu_ns: MetricSummary;
    heap?: Record<string, MetricSummary>;
  }[];
}

function object(value: unknown, context: string): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${context}: expected a JSON object`);
  }
  return value as JsonRecord;
}

function integer(record: JsonRecord, key: string, minimum = 0): number {
  const value = record[key];
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value < minimum
  ) {
    throw new Error(
      `${record.label ?? record.pda}: ${key} must be a ${
        minimum ? "positive" : "nonnegative"
      } safe integer, not ${value}`,
    );
  }
  return value;
}

export function parseJsonl(text: string): unknown[] {
  const records: unknown[] = [];
  for (const [index, line] of text.split(/\r?\n/).entries()) {
    if (!line.trim()) continue;
    try {
      records.push(JSON.parse(line));
    } catch (error) {
      throw new Error(`capture line ${index + 1}: invalid JSON: ${error}`);
    }
  }
  if (records.length === 0) throw new Error("missing capture records");
  return records;
}

export function validateCapture(records: unknown[], options: Options): Capture {
  const expected = SCENARIOS[options.scenario].labels;
  const phases: Phase[] = [];
  let hook: JsonRecord | undefined;
  for (const value of records) {
    const record = object(value, "capture record");
    if (record.pda === "hook") {
      if (hook) throw new Error("duplicate hook calibration record");
      hook = record;
      continue;
    }
    if (record.pda !== (options.mode === "allocations" ? "phase" : "cpu")) {
      throw new Error(
        `unexpected capture record ${record.pda} in ${options.mode} mode`,
      );
    }
    if (typeof record.label !== "string" || !expected.includes(record.label)) {
      throw new Error(
        `mismatched phase label ${record.label} for ${options.scenario}`,
      );
    }
    if (phases.some((phase) => phase.label === record.label)) {
      throw new Error(`duplicate phase ${record.label}`);
    }
    if (
      record.valid !== true || record.reason !== "ok" ||
      record.runtimevalidated !== true
    ) {
      throw new Error(`invalid phase ${record.label}: ${record.reason}`);
    }
    if (record.hookinstalled !== (options.mode === "allocations")) {
      throw new Error(
        `${record.label}: unexpected hookinstalled=${record.hookinstalled}`,
      );
    }
    if (record.cpuvalid !== true || record.cpu_instrumented !== true) {
      throw new Error(
        `${record.label}: invalid or unmarked instrumented CPU timing`,
      );
    }
    const phase: Phase = {
      label: record.label,
      operations: integer(record, "operations", 1),
      threadid: integer(record, "threadid", 1),
      capturedsegments: integer(record, "capturedsegments", 1),
      cpu_ns: integer(record, "cpu_ns"),
    };
    if (
      phase.operations !== options.iterations ||
      phase.capturedsegments !== options.iterations
    ) {
      throw new Error(
        `${record.label}: operations/segments do not match requested iterations ${options.iterations}`,
      );
    }
    if (options.mode === "allocations") {
      phase.heap = Object.fromEntries(
        HEAP_COUNTERS.map((key) => [key, integer(record, key)]),
      ) as Record<HeapCounter, number>;
    } else if (HEAP_COUNTERS.some((key) => key in record)) {
      throw new Error(
        `${record.label}: CPU-only capture must not claim heap counters`,
      );
    }
    phases.push(phase);
  }
  if (!hook) throw new Error("missing hook calibration record");
  if (
    hook.mode !== options.mode ||
    hook.hookinstalled !== (options.mode === "allocations") ||
    hook.runtimevalidated !== true || hook.reason !== "ok" ||
    typeof hook.previouslogger !== "boolean" ||
    (options.mode === "cpu" && hook.previouslogger !== false)
  ) {
    throw new Error(
      `invalid ${options.mode} hook calibration: ${JSON.stringify(hook)}`,
    );
  }
  for (const label of expected) {
    if (!phases.some((phase) => phase.label === label)) {
      throw new Error(`missing phase ${label}`);
    }
  }
  if (new Set(phases.map((phase) => phase.threadid)).size !== 1) {
    throw new Error(
      "phase thread IDs disagree with the single GUI-thread scope",
    );
  }
  return { phases, previouslogger: hook.previouslogger };
}

function distribution(values: number[]): Distribution {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return {
    median: sorted.length % 2
      ? sorted[middle]
      : sorted[middle - 1] / 2 + sorted[middle] / 2,
    min: sorted[0],
    max: sorted[sorted.length - 1],
  };
}

export function summarize(captures: unknown[][], options: Options): Summary {
  if (captures.length !== options.runs) {
    throw new Error(
      `expected ${options.runs} complete captures, got ${captures.length}`,
    );
  }
  const validated = captures.map((records) =>
    validateCapture(records, options)
  );
  return {
    warnings: validated.some((capture) => capture.previouslogger)
      ? [
        "A previous malloc logger was chained; its observer effects remain in these instrumented measurements.",
      ]
      : [],
    phases: SCENARIOS[options.scenario].labels.map((label) => {
      const samples = validated.flatMap((capture) =>
        capture.phases.filter((phase) => phase.label === label)
      );
      let heap: Record<string, MetricSummary> | undefined;
      if (options.mode === "allocations") {
        heap = {};
        for (const key of HEAP_COUNTERS) {
          const values = samples.map((sample) => {
            if (!sample.heap) {
              throw new Error(`missing heap capture for ${label}`);
            }
            return sample.heap[key];
          });
          heap[key] = {
            total: distribution(values),
            per_operation: distribution(
              values.map((value, index) => value / samples[index].operations),
            ),
          };
        }
      }
      return {
        label,
        operations: distribution(samples.map((sample) => sample.operations)),
        capturedsegments: distribution(
          samples.map((sample) => sample.capturedsegments),
        ),
        threadids: samples.map((sample) => sample.threadid),
        cpu_ns: {
          total: distribution(samples.map((sample) => sample.cpu_ns)),
          per_operation: distribution(
            samples.map((sample) => sample.cpu_ns / sample.operations),
          ),
        },
        ...(heap ? { heap } : {}),
      };
    }),
  };
}

// clearEnv ensures removed keys are not silently re-inherited by Deno.Command.
function cleanEnvironment(): Record<string, string> {
  const environment = Deno.env.toObject();
  for (const key of Object.keys(environment)) {
    if (
      /^MallocStackLogging/i.test(key) || [
        "PORYDAW_ALLOCATION_DYLIB",
        "PORYDAW_PROFILE_OUTPUT",
        "PORYDAW_ALLOCATION_SCENARIO",
        "PORYDAW_ALLOCATION_WARMUP",
        "PORYDAW_ALLOCATION_ITERATIONS",
        "PORYDAW_ROLL_QML_SUITE",
      ].includes(key)
    ) delete environment[key];
  }
  return environment;
}

interface CommandResult {
  command: string[];
  code: number;
  stdout: string;
  stderr: string;
}
async function execute(
  command: string[],
  root: string,
  env: Record<string, string>,
): Promise<CommandResult> {
  const result = await new Deno.Command(command[0], {
    args: command.slice(1),
    cwd: root,
    clearEnv: true,
    env,
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  }).output();
  const decoder = new TextDecoder();
  return {
    command,
    code: result.code,
    stdout: decoder.decode(result.stdout),
    stderr: decoder.decode(result.stderr),
  };
}

interface RunResult {
  run: number;
  process?: CommandResult;
  raw_jsonl?: string;
  records?: unknown[];
  error?: string;
}
function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function main(): Promise<number> {
  const options = parseOptions(Deno.args);
  if (!options) {
    console.log(HELP);
    return 0;
  }
  if (Deno.build.os !== "darwin") {
    throw new Error("allocation benchmarks require Darwin");
  }
  const root = await Deno.realPath(new URL("..", import.meta.url));
  const environment = cleanEnvironment();
  const temporary = await Deno.makeTempDir({
    prefix: "porydaw-allocation-bench-",
  });
  const runs: RunResult[] = [];
  let build: CommandResult | undefined;
  let error: string | undefined;
  let summary: Summary | undefined;
  try {
    const library = join(temporary, "allocation_probe.dylib");
    build = await execute(
      [
        "clang",
        "-dynamiclib",
        "-std=c11",
        "-O2",
        "-Wall",
        "-Wextra",
        "-Werror",
        `-DPDA_CPU_ONLY=${options.mode === "cpu" ? 1 : 0}`,
        join(root, "src/app/allocation_probe.c"),
        "-o",
        library,
      ],
      root,
      environment,
    );
    if (build.code !== 0) {
      throw new Error(
        `profiling dylib compilation failed (exit ${build.code})`,
      );
    }
    for (let run = 1; run <= options.runs; run++) {
      const capture = join(temporary, `capture-${run}.jsonl`);
      const result: RunResult = { run };
      runs.push(result);
      try {
        const window = options.scenario === "window-resize";
        result.process = await execute(
          [
            Deno.execPath(),
            "task",
            window ? "checks:qml-roll" : "checks",
            "--filter",
            window ? "swiftroll-window" : "swiftcore-projectsession",
          ],
          root,
          {
            ...environment,
            PORYDAW_ALLOCATION_DYLIB: library,
            PORYDAW_PROFILE_OUTPUT: capture,
            PORYDAW_ALLOCATION_SCENARIO: options.scenario,
            PORYDAW_ALLOCATION_WARMUP: String(options.warmup),
            PORYDAW_ALLOCATION_ITERATIONS: String(options.iterations),
            ...(window
              ? { PORYDAW_ROLL_QML_SUITE: "tst_AllocationWindowResize.qml" }
              : {}),
          },
        );
        let captureError: unknown;
        try {
          result.raw_jsonl = await Deno.readTextFile(capture);
          result.records = parseJsonl(result.raw_jsonl);
        } catch (failure) {
          captureError = failure;
        }
        if (result.process.code !== 0) {
          throw new Error(
            `scenario check failed (exit ${result.process.code})${
              captureError ? `; capture: ${message(captureError)}` : ""
            }`,
          );
        }
        if (captureError) throw captureError;
        if (!result.records) throw new Error("missing capture records");
        validateCapture(result.records, options);
      } catch (failure) {
        result.error = message(failure);
        throw failure;
      }
    }
    summary = summarize(runs.map((run) => run.records ?? []), options);
  } catch (failure) {
    error = message(failure);
  } finally {
    // Preserve diagnostics in the emitted report before destroying their files.
    try {
      const report = {
        success: error === undefined,
        scenario: options.scenario,
        mode: options.mode,
        scope: SCENARIOS[options.scenario].scope,
        warmup: options.warmup,
        iterations: options.iterations,
        runs: options.runs,
        config: "Debug",
        instrumented: true,
        heap_hook_instrumented: options.mode === "allocations",
        cpu_measurement: options.mode === "allocations"
          ? "heap-hook-distorted; not independent CPU performance"
          : "independent CPU-only; capture/clock overhead remains",
        empty_control_subtracted: false,
        build,
        samples: runs,
        summary: summary ?? null,
        ...(error ? { error } : {}),
      };
      const json = JSON.stringify(report, null, 2);
      console.log(json);
      if (options.output) await Deno.writeTextFile(options.output, `${json}\n`);
    } finally {
      await Deno.remove(temporary, { recursive: true });
    }
  }
  return error === undefined ? 0 : 1;
}

if (import.meta.main) {
  try {
    Deno.exit(await main());
  } catch (error) {
    console.error(`bench:allocations: ${message(error)}`);
    console.error("Use deno task bench:allocations --help for usage.");
    Deno.exit(2);
  }
}
