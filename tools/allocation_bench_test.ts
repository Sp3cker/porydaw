import {
  type Options,
  parseJsonl,
  parseOptions,
  summarize,
  validateCapture,
} from "./allocation_bench.ts";

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function rejects(action: () => unknown, expected: string): void {
  try {
    action();
  } catch (error) {
    if (error instanceof Error && error.message.includes(expected)) return;
    throw new Error(`Expected '${expected}', received ${error}`);
  }
  throw new Error(`Expected failure containing '${expected}'`);
}

const OPTIONS: Options = {
  scenario: "automation-commit",
  mode: "allocations",
  warmup: 2,
  iterations: 4,
  runs: 1,
};

function capture(
  mode: Options["mode"] = "allocations",
  label = "automation-commit.release-commit",
): Record<string, unknown>[] {
  return [
    {
      pda: "hook",
      mode,
      hookinstalled: mode === "allocations",
      runtimevalidated: true,
      previouslogger: false,
      reason: "ok",
    },
    {
      pda: mode === "allocations" ? "phase" : "cpu",
      label,
      operations: 4,
      threadid: 123,
      hookinstalled: mode === "allocations",
      runtimevalidated: true,
      valid: true,
      reason: "ok",
      capturedsegments: 4,
      cpu_ns: 400,
      cpuvalid: true,
      cpu_instrumented: true,
      ...(mode === "allocations"
        ? {
          allocations: 8,
          allocatedbytes: 128,
          frees: 4,
          reallocations: 2,
          reallocinplace: 1,
          failedallocations: 0,
          failedreallocations: 0,
        }
        : {}),
    },
  ];
}

Deno.test("CLI accepts defaults and independent CPU options", () => {
  equal(parseOptions(["--scenario", "note-draw"]), {
    scenario: "note-draw",
    mode: "allocations",
    warmup: 64,
    iterations: 1000,
    runs: 3,
  });
  equal(
    parseOptions([
      "--scenario=window-resize",
      "--mode=cpu",
      "--warmup=0",
      "--iterations",
      "4",
      "--runs",
      "1",
    ]),
    {
      scenario: "window-resize",
      mode: "cpu",
      warmup: 0,
      iterations: 4,
      runs: 1,
    },
  );
  equal(parseOptions(["--help"]), null);
});

Deno.test("CLI rejects unsupported scenarios and malformed counts", () => {
  const failures: [string[], string][] = [
    [[], "--scenario is required"],
    [["--scenario", "audition"], "--scenario requires"],
    [["--scenario"], "requires a value"],
    [["--mode=heap"], "--mode requires"],
    [["--unknown"], "unknown argument"],
    [["--help", "--unknown"], "unknown argument"],
    [["--help=true"], "unknown argument"],
    [["--output="], "requires a value"],
    [
      ["--scenario=note-draw", "--scenario=window-resize"],
      "duplicate argument",
    ],
  ];
  for (const flag of ["--warmup", "--iterations", "--runs"]) {
    for (
      const value of [
        "-1",
        "1.5",
        "NaN",
        "Infinity",
        "1e3",
        "9007199254740992",
        " ",
      ]
    ) {
      failures.push([
        ["--scenario=note-draw", `${flag}=${value}`],
        "safe integer",
      ]);
    }
    if (flag !== "--warmup") {
      failures.push([
        ["--scenario=note-draw", `${flag}=0`],
        "positive safe integer",
      ]);
    }
  }
  for (const [args, error] of failures) {
    rejects(() => parseOptions(args), error);
  }
});

Deno.test("JSONL rejects missing, malformed, and non-object captures", () => {
  const records = capture();
  const jsonl = records.map((record) => JSON.stringify(record)).join("\r\n");
  equal(parseJsonl(`\n${jsonl}\n\n`), records);
  rejects(() => parseJsonl(" \n\r\n"), "missing capture records");
  rejects(() => parseJsonl(`${jsonl}\n{broken`), "line 3: invalid JSON");
  for (const value of [null, [], 0, "noise"]) {
    rejects(() => validateCapture([value], OPTIONS), "expected a JSON object");
  }
});

Deno.test("Allocation reports fail closed on corrupt captures", () => {
  const failures: [number, string, unknown, string][] = [
    [0, "mode", "cpu", "hook calibration"],
    [0, "hookinstalled", false, "hook calibration"],
    [0, "runtimevalidated", false, "hook calibration"],
    [0, "reason", "unsupported", "hook calibration"],
    [0, "previouslogger", null, "hook calibration"],
    [1, "pda", "cpu", "unexpected capture record"],
    [1, "label", "note-draw.stroke", "mismatched phase label"],
    [1, "operations", 0, "operations must be a positive"],
    [1, "operations", 3, "do not match requested iterations"],
    [1, "capturedsegments", 3, "do not match requested iterations"],
    [1, "capturedsegments", null, "capturedsegments must be a positive"],
    [1, "threadid", 0, "threadid must be a positive"],
    [1, "valid", false, "invalid phase"],
    [1, "runtimevalidated", false, "invalid phase"],
    [1, "reason", "overflow", "invalid phase"],
    [1, "hookinstalled", false, "unexpected hookinstalled"],
    [1, "cpuvalid", false, "invalid or unmarked"],
    [1, "cpu_instrumented", false, "invalid or unmarked"],
    [1, "cpu_ns", null, "cpu_ns must be a nonnegative"],
    [1, "allocatedbytes", Number.MAX_SAFE_INTEGER + 1, "safe integer"],
  ];
  for (
    const key of [
      "allocations",
      "allocatedbytes",
      "frees",
      "reallocations",
      "reallocinplace",
      "failedallocations",
      "failedreallocations",
    ]
  ) {
    for (const value of [null, undefined, -1, 1.5, "0"]) {
      failures.push([1, key, value, `${key} must be a nonnegative`]);
    }
  }
  for (const [index, key, value, error] of failures) {
    const records = capture();
    records[index][key] = value;
    rejects(() => summarize([records], OPTIONS), error);
  }
  const records = capture();
  rejects(
    () => summarize([records.slice(1)], OPTIONS),
    "missing hook calibration",
  );
  rejects(() => summarize([[records[0]]], OPTIONS), "missing phase");
  rejects(
    () => summarize([[...records, records[0]]], OPTIONS),
    "duplicate hook",
  );
  rejects(
    () => summarize([[...records, records[1]]], OPTIONS),
    "duplicate phase",
  );
  rejects(() => summarize([], OPTIONS), "expected 1 complete captures");
});

Deno.test("CPU-only rejects heap hooks and invalid samples", () => {
  const options: Options = { ...OPTIONS, mode: "cpu" };
  const failures: [number, string, unknown, string][] = [
    [0, "hookinstalled", true, "hook calibration"],
    [0, "previouslogger", true, "hook calibration"],
    [0, "runtimevalidated", false, "hook calibration"],
    [1, "hookinstalled", true, "unexpected hookinstalled"],
    [1, "valid", false, "invalid phase"],
    [1, "cpuvalid", false, "invalid or unmarked"],
    [1, "cpu_ns", null, "cpu_ns must be a nonnegative"],
    [1, "capturedsegments", null, "capturedsegments must be a positive"],
    [1, "allocations", 0, "must not claim heap counters"],
    [1, "allocatedbytes", null, "must not claim heap counters"],
  ];
  for (const [index, key, value, error] of failures) {
    const records = capture("cpu");
    records[index][key] = value;
    rejects(() => summarize([records], options), error);
  }
  const report = summarize([capture("cpu")], options);
  equal(report.phases[0].cpu_ns.per_operation, {
    median: 100,
    min: 100,
    max: 100,
  });
  equal("heap" in report.phases[0], false);
});

Deno.test("Aggregation preserves per-phase totals and per-op rates", () => {
  const low = capture();
  const high = capture();
  high[1].cpu_ns = 800;
  high[1].allocations = 16;
  high[1].allocatedbytes = 256;
  high[1].frees = 8;
  high[1].threadid = 456;
  high[0].previouslogger = true;
  const report = summarize([high, low], { ...OPTIONS, runs: 2 });
  const phase = report.phases[0];
  equal(phase.label, "automation-commit.release-commit");
  equal(phase.threadids, [456, 123]);
  equal(phase.cpu_ns.total, { median: 600, min: 400, max: 800 });
  equal(phase.cpu_ns.per_operation, { median: 150, min: 100, max: 200 });
  equal(phase.heap?.allocations.total, { median: 12, min: 8, max: 16 });
  equal(phase.heap?.allocations.per_operation, { median: 3, min: 2, max: 4 });
  equal(phase.heap?.allocatedbytes.per_operation, {
    median: 48,
    min: 32,
    max: 64,
  });
  equal(phase.heap?.frees.per_operation, { median: 1.5, min: 1, max: 2 });
  equal(report.warnings.length, 1);
  equal(
    summarize([low, high, low], { ...OPTIONS, runs: 3 })
      .phases[0].cpu_ns.total.median,
    400,
  );
  low[1].allocations = 0;
  equal(summarize([low], OPTIONS).phases[0].heap?.allocations.total.median, 0);
});

Deno.test("Both note phases and window control are required", () => {
  for (
    const [scenario, labels] of [
      ["note-draw", ["note-draw.stroke", "note-draw.release-commit"]],
      [
        "window-resize",
        ["window-resize.geometry-event-turn", "window-resize.empty-event-turn"],
      ],
    ] as const
  ) {
    const options: Options = { ...OPTIONS, scenario };
    const records = capture("allocations", labels[0]);
    records.push(capture("allocations", labels[1])[1]);
    const report = summarize([records], options);
    equal(report.phases.map((phase) => phase.label), labels);
    // Empty controls remain separate; the runner never subtracts their values.
    equal(report.phases.map((phase) => phase.cpu_ns.total.median), [400, 400]);
    rejects(
      () => summarize([records.slice(0, 2)], options),
      `missing phase ${labels[1]}`,
    );
    records[2].threadid = 999;
    rejects(() => summarize([records], options), "single GUI-thread scope");
  }
});
