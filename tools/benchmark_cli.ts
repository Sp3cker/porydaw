// Fixed real-CLI workload for agent discovery and usage-error latency.
// One complete warmup excludes initial compilation/cache population. No mocks,
// test execution, network requests, or changes to the production CLI are used.
// Baseline help exits 2; accept 0 or 2 while reporting successful help separately.
const scenarios = [
  { task: "build:app", flag: "--help", help: true, required: "--release" },
  { task: "verify", flag: "--help", help: true, required: "--filter" },
  {
    task: "build:app",
    flag: "--agent-benchmark-invalid",
    help: false,
    required: "build:app",
  },
  {
    task: "verify",
    flag: "--agent-benchmark-invalid",
    help: false,
    required: "--filter",
  },
] as const;
const decoder = new TextDecoder();
const repetitions = 3;

async function exercise(scenario: typeof scenarios[number]) {
  const started = performance.now();
  const child = new Deno.Command(Deno.execPath(), {
    args: ["task", scenario.task, scenario.flag],
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      child.kill("SIGKILL");
    } catch {
      // Child already exited.
    }
  }, 600_000);
  const result = await child.output().finally(() => clearTimeout(timer));
  const elapsedMs = performance.now() - started;
  const output = decoder.decode(result.stdout) + decoder.decode(result.stderr);
  const validCode = scenario.help
    ? result.code === 0 || result.code === 2
    : result.code === 2;
  if (
    timedOut || result.signal !== null || !validCode ||
    !output.includes(scenario.required) ||
    !/usage|help|unknown|invalid|unrecognized/i.test(output) ||
    /run_checks: (PASS|FAIL)|\bverify:.*\bok\b/.test(output)
  ) {
    throw new Error(
      `Invalid diagnostic result: deno task ${scenario.task} ${scenario.flag}\n` +
        `exit=${result.code} signal=${result.signal} timeout=${timedOut}\n${output}`,
    );
  }
  return {
    elapsedMs,
    bytes: result.stdout.byteLength + result.stderr.byteLength,
    helpSuccess: scenario.help && result.code === 0 ? 1 : 0,
    buildSummaries: (output.match(/^build: ok\b/gm) ?? []).length,
  };
}

console.error(
  "benchmark: warming the four diagnostic commands (may build once)",
);
for (const scenario of scenarios) await exercise(scenario);
const walls: number[] = [];
let bytes = 0;
let helpSuccesses = 0;
let buildSummaries = 0;
for (let round = 0; round < repetitions; round++) {
  let wall = 0;
  for (const scenario of scenarios) {
    const result = await exercise(scenario);
    wall += result.elapsedMs;
    bytes += result.bytes;
    helpSuccesses += result.helpSuccess;
    buildSummaries += result.buildSummaries;
  }
  walls.push(wall);
  console.error(`benchmark: round ${round + 1}: ${wall.toFixed(2)}ms`);
}
walls.sort((a, b) => a - b);
console.log(`METRIC diagnostic_round_ms=${walls[1].toFixed(3)}`);
console.log(
  `METRIC output_bytes_per_round=${(bytes / repetitions).toFixed(0)}`,
);
console.log(`METRIC successful_help_per_round=${helpSuccesses / repetitions}`);
console.log(`METRIC build_summaries_per_round=${buildSummaries / repetitions}`);
