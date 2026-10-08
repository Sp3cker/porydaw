import {
  discoverModules,
  type ModuleJob,
  parseOptions,
  parseTimings,
  rankTimings,
  selectedFrontendJobs,
  selectModules,
  timingCommand,
} from "./swift_compile_bench.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function rejects(action: () => unknown, message: string) {
  try {
    action();
  } catch (error) {
    if (error instanceof Error && error.message.includes(message)) return;
    throw error;
  }
  throw new Error(`expected error containing ${message}`);
}

const root = "/fixture/worktree";
const first = `${root}/src/swift/core/First.swift`;
const second = `${root}/src/swift/core/Second.swift`;
const job: ModuleJob = {
  module: "PorydawCore",
  cwd: `${root}/build/debug`,
  sources: [first, second],
  command: [
    "/toolchain/swiftc",
    "-c",
    "-module-name",
    "PorydawCore",
    "-Onone",
    "-incremental",
    "-output-file-map",
    "outputs.json",
    "-emit-module",
    "-emit-module-path",
    "module.swiftmodule",
    "-index-store-path",
    "indexstore",
    "-Xcc",
    "-j",
    first,
    second,
  ],
};

Deno.test("file selection rejects another worktree and conflicting module filters", () => {
  rejects(
    () =>
      selectModules(
        [job],
        parseOptions(["--file", "/other/src/swift/core/First.swift"]),
        root,
      ),
    "not a Swift input",
  );
  rejects(
    () => selectModules([job], parseOptions(["--module", "Missing"]), root),
    "unknown Swift module",
  );
  const other = {
    ...job,
    module: "Other",
    sources: [`${root}/src/swift/app/Other.swift`],
  };
  rejects(
    () =>
      selectModules(
        [job, other],
        parseOptions(["--module", "Other", "--file", first]),
        root,
      ),
    "excluded by --module",
  );
  equal(
    selectModules([job, other], parseOptions(["--file", first]), root).map((
      value,
    ) => value.module),
    ["PorydawCore"],
  );
});

Deno.test("compilation database rejects foreign source inputs and shell placeholders", () => {
  rejects(
    () =>
      discoverModules(
        [{ directory: job.cwd, file: first, command: ":" }],
        root,
      ),
    "no first-party Swift commands",
  );
  rejects(
    () =>
      discoverModules([{
        directory: job.cwd,
        file: first,
        arguments: [
          "swiftc",
          "-module-name",
          "Mixed",
          first,
          "/other/Foreign.swift",
        ],
      }], root),
    "outside this worktree",
  );
  const modules = discoverModules([{
    directory: job.cwd,
    file: first,
    arguments: job.command,
  }, { directory: job.cwd, file: second, arguments: job.command }], root);
  equal(modules.length, 1);
  equal(modules[0].sources, [first, second]);
  const generated = `${root}/build/debug/BuildVersion.swift`;
  const withGenerated = discoverModules([{
    directory: job.cwd,
    file: first,
    arguments: [...job.command, generated],
  }], root);
  equal(withGenerated[0].sources, [first, second, generated]);
  equal(
    parseTimings(`1ms\t${generated}:1:1\tgetter version`, root)[0].generated,
    true,
  );
});

Deno.test("timing compiler mode cannot write normal build or index outputs", () => {
  const command = timingCommand(job, true, false);
  for (const output of ["outputs.json", "module.swiftmodule", "indexstore"]) {
    if (command.includes(output)) {
      throw new Error(`retained build output ${output}`);
    }
  }
  equal(command.filter((value) => value.endsWith(".swift")), [second, first]);
  const forwarded = command.indexOf("-Xcc");
  equal(command.slice(forwarded, forwarded + 2), ["-Xcc", "-j"]);
  if (!command.includes("-typecheck") || command.includes("-c")) {
    throw new Error("wrong compiler mode");
  }
  rejects(
    () => timingCommand({ ...job, command: ["swiftc", "-o"] }, false, false),
    "missing compiler value",
  );
});

Deno.test("file mode chooses the exact primary input, including quoted paths", () => {
  const quoted = `${root}/src/swift/core/With Space.swift`;
  const output = [
    `/toolchain/swift-frontend -frontend -typecheck -primary-file ${first} "${quoted}"`,
    `/toolchain/swift-frontend -frontend -typecheck ${first} -primary-file "${quoted}"`,
  ].join("\n");
  const selected = selectedFrontendJobs(output, [quoted], job.cwd);
  equal(selected.length, 1);
  equal(selected[0][selected[0].indexOf("-primary-file") + 1], quoted);
  rejects(() => selectedFrontendJobs(output, [second], job.cwd), "found 0");
  rejects(
    () => selectedFrontendJobs(output + "\n" + output, [first], job.cwd),
    "found 2",
  );
});

Deno.test("timing parsing distinguishes expressions, bodies, generated code, and diagnostics", () => {
  const text =
    `warning: unrelated diagnostic\n0.01ms\t<invalid loc>\n12.5ms\t${first}:8:2\n21.5ms\t${first}:7:1\tinstance method Core.first\n3.5ms\t@__swiftmacro_Test.swift:14:20\tstatic method Core.generated\n`;
  const rows = parseTimings(text);
  equal(rows.map((row) => [row.ms, row.symbol ?? null, row.generated]), [
    [12.5, null, false],
    [21.5, "instance method Core.first", false],
    [3.5, "static method Core.generated", true],
  ]);
});

Deno.test("rankings use repeat medians, do not add overlapping expressions, and omit failed runs", () => {
  const measurement = (
    order: string,
    iteration: number,
    exit: number,
    text: string,
  ) => ({
    module: "Core",
    order,
    iteration,
    exit,
    wallMs: 100,
    log: "raw.log",
    commands: [],
    timings: parseTimings(text),
  });
  const body = `${first}:7:1\tinstance method Core.first`;
  const expression = `${first}:8:2`;
  const measurements = [
    measurement(
      "normal",
      1,
      0,
      `10ms\t${body}\n5ms\t${expression}\n3ms\t${expression}`,
    ),
    measurement("normal", 2, 0, `30ms\t${body}\n15ms\t${expression}`),
    measurement("reversed", 1, 0, `7ms\t${body}\n4ms\t${expression}`),
    measurement("normal", 3, 1, `999ms\t${body}`),
  ];
  const bodies = rankTimings(measurements, true);
  equal(bodies.map((row) => [row.normalMs, row.reversedMs]), [[20, 7]]);
  const expressions = rankTimings(measurements, false);
  equal(expressions.map((row) => [row.normalMs, row.reversedMs]), [[10, 4]]);
  equal(rankTimings(measurements.slice(0, 1), true)[0].reversedMs, null);
});

Deno.test("invalid benchmark counts and missing filters fail instead of narrowing silently", () => {
  for (const value of ["0", "-1", "1.5", "NaN"]) {
    rejects(() => parseOptions(["--repeat", value]), "positive integer");
  }
  rejects(() => parseOptions(["--file", "--no-build"]), "requires a value");
  rejects(() => parseOptions(["--order", "random"]), "normal or both");
  rejects(() => parseOptions(["--typo"]), "unknown option");
});
