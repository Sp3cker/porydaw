import {
  deepStrictEqual,
  match,
  ok,
  strictEqual,
  throws,
} from "node:assert/strict";
import {
  type Options,
  parseJsonl,
  parseOptions,
  summarize,
  validateCapture,
} from "./allocation_bench.ts";

const OPTIONS: Options = {
  scenario: "automation-commit",
  mode: "allocations",
  warmup: 2,
  iterations: 4,
  runs: 1,
};

type WireRecord = Record<string, unknown>;

// Explicit wire examples stay independent of the consumer's schema tables.
function allocationCapture(
  label = "automation-commit.release-commit",
): [WireRecord, WireRecord] {
  return [
    {
      pda: "hook",
      mode: "allocations",
      hookinstalled: true,
      runtimevalidated: true,
      previouslogger: false,
      reason: "ok",
    },
    {
      pda: "phase",
      label,
      operations: 4,
      threadid: 123,
      hookinstalled: true,
      runtimevalidated: true,
      valid: true,
      reason: "ok",
      capturedsegments: 4,
      cpu_ns: 400,
      cpuvalid: true,
      cpu_instrumented: true,
      allocations: 8,
      allocatedbytes: 128,
      frees: 4,
      reallocations: 2,
      reallocinplace: 1,
      failedallocations: 0,
      failedreallocations: 0,
    },
  ];
}

function cpuCapture(): [WireRecord, WireRecord] {
  return [
    {
      pda: "hook",
      mode: "cpu",
      hookinstalled: false,
      runtimevalidated: true,
      previouslogger: false,
      reason: "ok",
    },
    {
      pda: "cpu",
      label: "automation-commit.release-commit",
      operations: 4,
      threadid: 123,
      hookinstalled: false,
      runtimevalidated: true,
      valid: true,
      reason: "ok",
      capturedsegments: 4,
      cpu_ns: 400,
      cpuvalid: true,
      cpu_instrumented: true,
    },
  ];
}

Deno.test("CLI accepts explicit CPU counts and help without a scenario", () => {
  const options = parseOptions([
    "--scenario=window-resize",
    "--mode=cpu",
    "--warmup=0",
    "--iterations",
    "4",
    "--runs",
    "1",
  ]);
  ok(options);
  strictEqual(options.scenario, "window-resize");
  strictEqual(options.mode, "cpu");
  strictEqual(options.warmup, 0);
  strictEqual(options.iterations, 4);
  strictEqual(options.runs, 1);
  strictEqual(parseOptions(["--help"]), null);
  strictEqual(parseOptions(["--help", "--scenario=note-draw"]), null);
  strictEqual(parseOptions(["--scenario=note-draw", "--help"]), null);
});

Deno.test("CLI rejects malformed flags even when help is requested", () => {
  const failures: [string[], RegExp][] = [
    [[], /--scenario is required/],
    [["--scenario", "audition"], /--scenario requires/],
    [["--scenario=__proto__"], /--scenario requires/],
    [["--scenario=constructor"], /--scenario requires/],
    [["--scenario=toString"], /--scenario requires/],
    [["--scenario"], /requires a value/],
    [["--scenario", "--mode=cpu"], /requires a value/],
    [["--mode=heap"], /--mode requires/],
    [["--unknown"], /unknown argument/],
    [["--help", "--unknown"], /unknown argument/],
    [["--unknown", "--help"], /unknown argument/],
    [["--help", "--iterations=0"], /positive safe integer/],
    [["--help=true"], /unknown argument/],
    [["--output="], /requires a value/],
    [
      ["--scenario=note-draw", "--scenario", "window-resize"],
      /duplicate argument/,
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
        /safe integer/,
      ]);
    }
    if (flag !== "--warmup") {
      failures.push([
        ["--scenario=note-draw", `${flag}=0`],
        /positive safe integer/,
      ]);
    }
  }
  for (const [args, error] of failures) {
    throws(() => parseOptions(args), error);
  }
});

Deno.test("JSONL handles blank lines but rejects missing or malformed data", () => {
  const records = allocationCapture();
  const jsonl = records.map((record) => JSON.stringify(record)).join("\r\n");
  deepStrictEqual(parseJsonl(`\n${jsonl}\n\n`), records);
  throws(() => parseJsonl(" \n\r\n"), /missing capture records/);
  throws(() => parseJsonl(`${jsonl}\n{broken`), /line 3: invalid JSON/);
  for (const value of [null, [], 0, "noise"]) {
    throws(
      () => validateCapture(parseJsonl(JSON.stringify(value)), OPTIONS),
      /expected a JSON object/,
    );
  }
});

Deno.test("Allocation validation fails closed on corrupt measurements", () => {
  const failures: [number, string, unknown, RegExp][] = [
    [0, "mode", "cpu", /hook calibration/],
    [0, "hookinstalled", false, /hook calibration/],
    [0, "runtimevalidated", false, /hook calibration/],
    [0, "reason", "unsupported", /hook calibration/],
    [0, "previouslogger", null, /hook calibration/],
    [1, "pda", "cpu", /unexpected capture record/],
    [1, "label", "note-draw.stroke", /mismatched phase label/],
    [1, "operations", 0, /operations must be a positive/],
    [1, "operations", 3, /do not match requested iterations/],
    [1, "capturedsegments", 3, /do not match requested iterations/],
    [1, "capturedsegments", null, /capturedsegments must be a positive/],
    [1, "threadid", 0, /threadid must be a positive/],
    [1, "valid", false, /invalid phase/],
    [1, "runtimevalidated", false, /invalid phase/],
    [1, "reason", "overflow", /invalid phase/],
    [1, "hookinstalled", false, /unexpected hookinstalled/],
    [1, "cpuvalid", false, /invalid or unmarked/],
    [1, "cpu_instrumented", false, /invalid or unmarked/],
    [1, "cpu_ns", null, /cpu_ns must be a nonnegative/],
    [1, "allocations", null, /allocations must be a nonnegative/],
    [1, "allocatedbytes", Number.MAX_SAFE_INTEGER + 1, /safe integer/],
    [1, "frees", undefined, /frees must be a nonnegative/],
    [1, "reallocations", -1, /reallocations must be a nonnegative/],
    [1, "reallocinplace", 1.5, /reallocinplace must be a nonnegative/],
    [1, "failedallocations", "0", /failedallocations must be a nonnegative/],
    [
      1,
      "failedreallocations",
      null,
      /failedreallocations must be a nonnegative/,
    ],
  ];
  for (const [index, key, value, error] of failures) {
    const records = allocationCapture();
    records[index][key] = value;
    throws(() => validateCapture(records, OPTIONS), error);
  }
  const records = allocationCapture();
  throws(
    () => validateCapture(records.slice(1), OPTIONS),
    /missing hook calibration/,
  );
  throws(() => validateCapture([records[0]], OPTIONS), /missing phase/);
  throws(
    () => validateCapture([...records, records[0]], OPTIONS),
    /duplicate hook/,
  );
  throws(
    () => validateCapture([...records, records[1]], OPTIONS),
    /duplicate phase/,
  );
});

Deno.test("CPU-only validation rejects hooks, heap claims and invalid timing", () => {
  const options: Options = { ...OPTIONS, mode: "cpu" };
  const failures: [number, string, unknown, RegExp][] = [
    [0, "hookinstalled", true, /hook calibration/],
    [0, "previouslogger", true, /hook calibration/],
    [0, "runtimevalidated", false, /hook calibration/],
    [1, "hookinstalled", true, /unexpected hookinstalled/],
    [1, "valid", false, /invalid phase/],
    [1, "cpuvalid", false, /invalid or unmarked/],
    [1, "cpu_ns", null, /cpu_ns must be a nonnegative/],
    [1, "cpu_ns", Number.MAX_SAFE_INTEGER + 1, /safe integer/],
    [1, "capturedsegments", null, /capturedsegments must be a positive/],
    [1, "allocations", 0, /must not claim heap counters/],
    [1, "allocatedbytes", null, /must not claim heap counters/],
  ];
  for (const [index, key, value, error] of failures) {
    const records = cpuCapture();
    records[index][key] = value;
    throws(() => validateCapture(records, options), error);
  }
  const captures = [1000, 80, 360].map((cpu_ns) => {
    const records = cpuCapture();
    records[1].cpu_ns = cpu_ns;
    return validateCapture(records, options);
  });
  const phase = summarize(captures, { ...options, runs: 3 }).phases[0];
  deepStrictEqual(phase.cpu_ns.total, { median: 360, min: 80, max: 1000 });
  deepStrictEqual(phase.cpu_ns.per_operation, {
    median: 90,
    min: 20,
    max: 250,
  });
});

Deno.test("Aggregation computes even and odd medians, extrema and per-op rates", () => {
  const captures = [
    { cpu_ns: 1000, allocations: 20, allocatedbytes: 320, frees: 8 },
    { cpu_ns: 80, allocations: 2, allocatedbytes: 32, frees: 0 },
    { cpu_ns: 360, allocations: 6, allocatedbytes: 96, frees: 4 },
    { cpu_ns: 120, allocations: 4, allocatedbytes: 64, frees: 2 },
  ].map((metrics, index) => {
    const records = allocationCapture();
    Object.assign(records[1], metrics, { threadid: 123 + index });
    records[0].previouslogger = index === 0;
    return validateCapture(records, OPTIONS);
  });
  const report = summarize(captures, { ...OPTIONS, runs: 4 });
  const phase = report.phases[0];
  deepStrictEqual(phase.cpu_ns.total, { median: 240, min: 80, max: 1000 });
  deepStrictEqual(phase.cpu_ns.per_operation, {
    median: 60,
    min: 20,
    max: 250,
  });
  deepStrictEqual(phase.heap?.allocations.total, {
    median: 5,
    min: 2,
    max: 20,
  });
  deepStrictEqual(phase.heap?.allocations.per_operation, {
    median: 1.25,
    min: 0.5,
    max: 5,
  });
  deepStrictEqual(phase.heap?.allocatedbytes.total, {
    median: 80,
    min: 32,
    max: 320,
  });
  deepStrictEqual(phase.heap?.allocatedbytes.per_operation, {
    median: 20,
    min: 8,
    max: 80,
  });
  deepStrictEqual(phase.heap?.frees.per_operation, {
    median: 0.75,
    min: 0,
    max: 2,
  });
  match(report.warnings.join("\n"), /previous malloc logger.*observer effects/);
  deepStrictEqual(
    summarize(captures.slice(0, 3), { ...OPTIONS, runs: 3 })
      .phases[0].cpu_ns.total,
    { median: 360, min: 80, max: 1000 },
  );
  throws(
    () => summarize(captures.slice(0, 3), { ...OPTIONS, runs: 4 }),
    /expected 4 complete captures/,
  );
});

Deno.test("Valid zero measurements are not confused with invalid captures", () => {
  const records = allocationCapture();
  Object.assign(records[1], {
    cpu_ns: 0,
    allocations: 0,
    allocatedbytes: 0,
    frees: 0,
    reallocations: 0,
    reallocinplace: 0,
    failedallocations: 0,
    failedreallocations: 0,
  });
  const report = summarize([validateCapture(records, OPTIONS)], OPTIONS);
  deepStrictEqual(report.phases[0].cpu_ns.total, { median: 0, min: 0, max: 0 });
  deepStrictEqual(report.phases[0].heap?.allocations.per_operation, {
    median: 0,
    min: 0,
    max: 0,
  });
  deepStrictEqual(report.warnings, []);
  records[1].valid = false;
  throws(() => validateCapture(records, OPTIONS), /invalid phase/);
});

Deno.test("Window control stays separate and unsubtracted across process samples", () => {
  const options: Options = { ...OPTIONS, scenario: "window-resize", runs: 2 };
  const first = allocationCapture("window-resize.geometry-event-turn");
  Object.assign(first[1], { cpu_ns: 800, allocations: 40 });
  const firstControl = allocationCapture("window-resize.empty-event-turn")[1];
  Object.assign(firstControl, { cpu_ns: 1200, allocations: 60 });

  throws(() => validateCapture(first, options), /missing phase/);
  throws(
    () =>
      validateCapture([...first, { ...firstControl, threadid: 999 }], options),
    /single GUI-thread scope/,
  );

  const second = allocationCapture("window-resize.empty-event-turn");
  Object.assign(second[1], { cpu_ns: 400, allocations: 20, threadid: 456 });
  const secondGeometry =
    allocationCapture("window-resize.geometry-event-turn")[1];
  Object.assign(secondGeometry, {
    cpu_ns: 1600,
    allocations: 80,
    threadid: 456,
  });
  const report = summarize([
    validateCapture([...first, firstControl], options),
    validateCapture([...second, secondGeometry], options),
  ], options);
  const geometry = report.phases.find((phase) =>
    phase.label === "window-resize.geometry-event-turn"
  );
  const control = report.phases.find((phase) =>
    phase.label === "window-resize.empty-event-turn"
  );
  ok(geometry);
  ok(control);
  deepStrictEqual(geometry.cpu_ns.total, { median: 1200, min: 800, max: 1600 });
  deepStrictEqual(control.cpu_ns.total, { median: 800, min: 400, max: 1200 });
  deepStrictEqual(geometry.heap?.allocations.per_operation, {
    median: 15,
    min: 10,
    max: 20,
  });
  deepStrictEqual(control.heap?.allocations.per_operation, {
    median: 10,
    min: 5,
    max: 15,
  });
});
