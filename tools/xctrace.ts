// deno task xctrace — record Instruments traces and summarize them locally.
// Thin wrapper over `xcrun xctrace record` plus offline summarize/compare
// over `xcrun xctrace export` XML. No Python, no ad-hoc app timing.
import {
  compareJson,
  type CompareOptions,
  compareStructured,
  renderCompareLines,
} from "./xctrace/compare.ts";
import {
  loadSummary,
  parseIntervalFlag,
  renderText,
  type SummarizeOptions,
  summaryJson,
} from "./xctrace/summarize.ts";
import { parseSchemaName } from "./xctrace/toc.ts";
import { firstLine } from "./xctrace/xml.ts";

const HELP = `usage: deno task xctrace <command> [options]

record: thin wrapper over \`xcrun xctrace record --no-prompt\`.
  deno task xctrace record --template <name> (--attach <pid> | --launch <app> [-- args]) --output <file.trace> [--time-limit <sec>]
  Prints the trace path and attached PID; exits when xctrace exits
  (Ctrl-C stops the recording: SIGINT reaches xctrace directly).
  --attach echoes the given PID; --launch reports unknown since xctrace
  never prints the launched target's PID.

summarize: offline summary of one trace via \`xcrun xctrace export\`.
  deno task xctrace summarize <file.trace> [--schema cpu-profile|time-profile|os-signpost]
      [--run 1] [--interval <startEpoch>,<endEpoch>] [--binary <name>]
      [--thread main|<name>] [--top 20] [--json]
  Default schema is inferred from the trace TOC (cpu-profile wins over
  time-profile wins over os-signpost: CPU Profiler traces also carry
  PointsOfInterest signpost tables). --interval filters samples (profile) or
  completed intervals by begin (signpost). Beside-trace sidecars
  (<file>.trace.json or <file>.json with {startEpoch,endEpoch} or
  {start,end}) supply per-trace intervals; --interval overrides them.
  Weight unit is cycle-weight for cpu-profile, weight (shown in ms) for
  time-profile. Never prints raw XML.

compare: pair before/after traces in order.
  deno task xctrace compare <before.trace>... --against <after.trace>... [same filters] [--metric <symbol-or-binary-or-thread>]
  Prints per-pair reduction and median reduction for the process total, main
  thread, --binary self, and any --metric (raw per-run values included).
  Each trace uses its own interval (flag overrides sidecar); the interval
  source (sidecar/flag/whole-run) is printed per trace.
  Value flags must agree on both sides of --against. --json emits
  {pairs: [{before: {trace, interval, source}, after, metrics:
  {processTotal: {before, after, reductionPct}, mainThread, binarySelf?,
  metric?}}], medians, dropped} built from the same values as the text.
`;

const RECORD_HELP =
  `usage: deno task xctrace record --template <name> (--attach <pid> | --launch <app-or-exe> [-- args]) --output <file.trace> [--time-limit <sec>]
`;
const SUMMARIZE_HELP =
  `usage: deno task xctrace summarize <file.trace> [--schema cpu-profile|time-profile|os-signpost] [--run 1] [--interval <startEpoch>,<endEpoch>] [--binary <name>] [--thread main|<name>] [--top 20] [--json]
`;
const COMPARE_HELP =
  `usage: deno task xctrace compare <before.trace>... --against <after.trace>... [--schema ...] [--run 1] [--interval <s,e>] [--binary <name>] [--thread main|<name>] [--top 20] [--json] [--metric <symbol-or-binary-or-thread>]
  Value flags must agree on both sides of --against. --json emits
  {pairs: [{before: {trace, interval, source}, after, metrics:
  {processTotal: {before, after, reductionPct}, mainThread, binarySelf?,
  metric?}}], medians, dropped} built from the same values as the text.
`;

function fail(message: string): never {
  console.error(`xctrace: ${firstLine(message)}`);
  Deno.exit(1);
}

/** Split bare positionals from flags; known value-flags consume one token. */
function splitArgs(
  args: string[],
  valueFlags: Record<string, true>,
): { positionals: string[]; flags: string[] } {
  const positionals: string[] = [];
  const flags: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--") {
      positionals.push(...args.slice(i + 1));
      break;
    }
    if (valueFlags[arg]) {
      const value = args[i + 1];
      if (value === undefined) fail(`${arg} requires a value`);
      flags.push(arg, value);
      i++;
    } else if (arg.startsWith("--")) {
      flags.push(arg);
    } else {
      positionals.push(arg);
    }
  }
  return { positionals, flags };
}

const VALUE_FLAGS: Record<string, true> = {
  "--template": true,
  "--attach": true,
  "--launch": true,
  "--output": true,
  "--time-limit": true,
  "--schema": true,
  "--run": true,
  "--interval": true,
  "--binary": true,
  "--thread": true,
  "--top": true,
  "--metric": true,
};

function flagValue(flags: string[], flag: string): string | undefined {
  const index = flags.indexOf(flag);
  if (index === -1) return undefined;
  const value = flags[index + 1];
  if (value === undefined || value.startsWith("--")) {
    fail(`${flag} requires a value`);
  }
  return value;
}

function hasFlag(flags: string[], flag: string): boolean {
  return flags.includes(flag);
}

function parseWholeFlag(
  value: string | undefined,
  flag: string,
  fallback: number,
): number {
  if (value === undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    fail(`bad ${flag} ${value}`);
  }
  return parsed;
}

/** Shared summarize/compare filters. Unknown flags are errors, not guesses. */
function parseFilters(
  flags: string[],
  extra: Record<string, true>,
): SummarizeOptions {
  const allowed: Record<string, true> = {
    "--schema": true,
    "--run": true,
    "--interval": true,
    "--binary": true,
    "--thread": true,
    "--top": true,
    "--json": true,
    ...extra,
  };
  for (const flag of flags) {
    if (flag.startsWith("--") && !allowed[flag]) {
      fail(`unknown argument ${flag}`);
    }
  }
  const schemaText = flagValue(flags, "--schema");
  const intervalText = flagValue(flags, "--interval");
  let intervalFlag: [number, number] | undefined;
  if (intervalText !== undefined) {
    try {
      intervalFlag = parseIntervalFlag(intervalText);
    } catch (error) {
      fail(firstLine(error));
    }
  }
  return {
    schema: schemaText === undefined ? undefined : parseSchemaName(schemaText),
    run: parseWholeFlag(flagValue(flags, "--run"), "--run", 1),
    top: parseWholeFlag(flagValue(flags, "--top"), "--top", 20),
    intervalFlag,
    binary: flagValue(flags, "--binary"),
    thread: flagValue(flags, "--thread"),
    json: hasFlag(flags, "--json"),
  };
}

async function runRecord(args: string[]): Promise<void> {
  if (args.includes("--help")) {
    console.log(RECORD_HELP);
    return;
  }
  // Everything after a bare -- belongs to the launch target.
  const sep = args.indexOf("--");
  let head = sep === -1 ? args : args.slice(0, sep);
  const tail = sep === -1 ? [] : args.slice(sep + 1);
  // `--launch -- app`: the app lives in the tail.
  let launchFromTail = false;
  if (head[head.length - 1] === "--launch") {
    head = head.slice(0, -1);
    launchFromTail = true;
  }
  const { positionals, flags } = splitArgs(head, VALUE_FLAGS);
  if (positionals.length > 0) fail(`unknown argument ${positionals[0]}`);
  const template = flagValue(flags, "--template");
  const attach = flagValue(flags, "--attach");
  const output = flagValue(flags, "--output");
  const timeLimit = flagValue(flags, "--time-limit");
  if (!template) fail("record requires --template <name>");
  if (!output) fail("record requires --output <file.trace>");
  const launchIndex = flags.indexOf("--launch");
  if (!attach && launchIndex === -1 && !launchFromTail) {
    fail("record requires --attach <pid> or --launch <app-or-exe>");
  }
  if (attach && (launchIndex !== -1 || launchFromTail)) {
    fail("--attach and --launch are exclusive");
  }
  const allowed: Record<string, true> = {
    "--launch": true,
    "--template": true,
    "--attach": true,
    "--output": true,
    "--time-limit": true,
  };
  for (const flag of flags) {
    if (flag.startsWith("--") && !allowed[flag]) {
      fail(`unknown argument ${flag}`);
    }
  }
  const xctraceArgs = [
    "xctrace",
    "record",
    "--no-prompt",
    "--template",
    template,
  ];
  if (timeLimit) {
    xctraceArgs.push(
      "--time-limit",
      /^\d+(\.\d+)?$/.test(timeLimit) ? `${timeLimit}s` : timeLimit,
    );
  }
  xctraceArgs.push("--output", output);
  if (attach) {
    xctraceArgs.push("--attach", attach);
  } else {
    const app = launchFromTail ? tail[0] : flags[launchIndex + 1];
    const appArgs = launchFromTail ? tail.slice(1) : tail;
    if (!app || app.startsWith("--")) {
      fail("--launch requires an app or executable");
    }
    xctraceArgs.push("--launch", "--", app, ...appArgs);
  }
  const child = new Deno.Command("xcrun", {
    args: xctraceArgs,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "piped",
  }).spawn();
  // Tee stderr so the user sees xctrace progress; scan it for the target pid.
  const reader = child.stderr.getReader();
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let announcedPid: string | null = attach ?? null;
  let pending = "";
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      const chunk = decoder.decode(value, { stream: true });
      await Deno.stderr.write(encoder.encode(chunk));
      pending += chunk;
      const match = pending.match(
        /(?:pid[^\d]*|attaching to:[^(]*\()(\d+)\)?/i,
      );
      if (match) announcedPid = match[1];
    }
  } catch {
    // A torn-down pipe here just means the child is gone; status below rules.
  } finally {
    reader.releaseLock();
  }
  const status = await child.status;
  if (!status.success) Deno.exit(status.code);
  console.log(`trace: ${output}`);
  console.log(`pid: ${announcedPid ?? "unknown"}`);
}

async function runSummarize(args: string[]): Promise<void> {
  if (args.includes("--help")) {
    console.log(SUMMARIZE_HELP);
    return;
  }
  const { positionals, flags } = splitArgs(args, VALUE_FLAGS);
  if (positionals.length !== 1) {
    fail("summarize requires exactly one <file.trace>");
  }
  const options = parseFilters(flags, {});
  const summary = await loadSummary(positionals[0], options).catch((
    error: unknown,
  ) => fail(firstLine(error)));
  if (options.json) {
    console.log(JSON.stringify(summaryJson(summary), null, 2));
  } else {
    for (const line of renderText(summary, options.top)) console.log(line);
  }
}

async function runCompare(args: string[]): Promise<void> {
  if (args.includes("--help")) {
    console.log(COMPARE_HELP);
    return;
  }
  const against = args.indexOf("--against");
  if (against === -1) fail("compare requires --against <after.trace>...");
  const beforeSplit = splitArgs(args.slice(0, against), VALUE_FLAGS);
  const afterSplit = splitArgs(args.slice(against + 1), VALUE_FLAGS);
  for (const flag of Object.keys(VALUE_FLAGS)) {
    const beforeValue = flagValue(beforeSplit.flags, flag);
    const afterValue = flagValue(afterSplit.flags, flag);
    if (
      beforeValue !== undefined && afterValue !== undefined &&
      beforeValue !== afterValue
    ) {
      fail(`conflicting ${flag} on both sides of --against`);
    }
  }
  const flags = [...beforeSplit.flags, ...afterSplit.flags];
  const metric = flagValue(flags, "--metric");
  const options = parseFilters(flags, { "--metric": true }) as CompareOptions;
  if (metric !== undefined) options.metric = metric;
  const result = await compareStructured(
    beforeSplit.positionals,
    afterSplit.positionals,
    options,
  )
    .catch((error: unknown) => fail(firstLine(error)));
  if (options.json) {
    console.log(JSON.stringify(compareJson(result), null, 2));
  } else {
    for (const line of renderCompareLines(result, options)) console.log(line);
  }
}

const [command, ...rest] = Deno.args;
try {
  if (command === undefined || command === "--help") {
    console.log(HELP);
  } else if (command === "record") {
    await runRecord(rest);
  } else if (command === "summarize") {
    await runSummarize(rest);
  } else if (command === "compare") {
    await runCompare(rest);
  } else {
    fail(`unknown command ${command}`);
  }
} catch (error) {
  fail(firstLine(error));
}
