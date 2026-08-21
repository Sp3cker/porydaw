// Run every porydaw check harness with only its declared fixture files.
// Point this at an ASAN build (-DPORYDAW_ASAN=ON) to turn silent memory bugs
// into aborts with stack traces.
//
// usage: deno task checks <porydaw-checks-binary> [--all|--no-windowing-checks] [--reporter=quiet|verbose] [--filter=<name>]
//
// env: PORYDAW_SAMPLE_CORPUS  optional built project for samplecheck's corpus
//      ASAN_OPTIONS defaults to detect_leaks=0

import { dirname, join } from "node:path";
import { createReporter } from "./checks_reporter.ts";
import type { Reporter } from "./checks_reporter.ts";
import { wallEstimate } from "./checks_walls.ts";

type ScratchKind = "existing-directory" | "must-not-exist-path" | "unused";
type FixtureRootKind = "decomp-project" | "songs-mk-project" | "none";
type Windowing = "offscreen" | "window-system";
interface CheckManifestEntry {
  readonly name: string;
  readonly argv: readonly string[];
  readonly binary: "application" | "checks";
  readonly windowing: Windowing;

  readonly environment?: Readonly<Record<string, string>>;
  readonly optionalArgumentEnvironment?: Readonly<Record<string, string>>;
  readonly exclusive?: boolean;
  readonly scratchKind: ScratchKind;
  readonly fixtureRootKind: FixtureRootKind;
  readonly fixtureFiles: readonly string[];
}
const CHECK_TIMEOUT_MS = 90_000;
const TERMINATE_GRACE_MS = 5_000;
// Benchmark 2026-08-21 (M4, 10 cores): unified LPT pool of 6 beat 5/7/8 —
// 7+ slows CPU-saturating checks via contention, 5 underuses the machine.
const MAX_PARALLEL_CHECKS = Math.max(
  1,
  Math.min(6, navigator.hardwareConcurrency),
);
function parsePool(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 64) usage();
  return parsed;
}
const decoder = new TextDecoder();

function usage(): never {
  console.error(
    "usage: deno task checks <porydaw-checks-binary> [--all|--no-windowing-checks] [--reporter=quiet|verbose] [--filter=<name>] [--pool=<n>]",
  );
  console.error("  --all (default): all checks");
  console.error(
    "  --no-windowing-checks: skip checks that require a window system",
  );
  console.error("  --reporter=quiet|verbose (default: quiet)");
  console.error(
    "  --filter=<name>: only run harnesses whose name contains <name> (repeatable, substring)",
  );
  console.error("  --verbose: alias for --reporter=verbose");
  console.error(
    "  --pool=<n>: worker count for the unified LPT pool (default: MAX_PARALLEL_CHECKS)",
  );
  Deno.exit(2);
}

async function requiredFile(path: string, description: string): Promise<void> {
  let stat: Deno.FileInfo;
  try {
    stat = await Deno.stat(path);
  } catch {
    throw new Error(`run_checks: missing ${description}: ${path}`);
  }
  if (!stat.isFile) {
    throw new Error(`run_checks: ${description} is not a file: ${path}`);
  }
}

async function resolveRequiredFile(
  path: string,
  description: string,
): Promise<string> {
  try {
    await requiredFile(path, description);
    return await Deno.realPath(path);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(2);
  }
}

async function findMid2Agb(buildRoot: string): Promise<string> {
  for (const name of ["mid2agb", "mid2agb.exe"]) {
    const candidate = join(buildRoot, name);
    try {
      if ((await Deno.stat(candidate)).isFile) {
        return candidate;
      }
    } catch {
      // Try the next platform name.
    }
  }
  console.error(
    `run_checks: missing in-tree mid2agb beside the build: ${buildRoot}`,
  );
  Deno.exit(2);
}

async function findApplication(buildRoot: string): Promise<string> {
  const candidates = [
    join(buildRoot, "porydaw"),
    join(buildRoot, "porydaw.exe"),
    join(buildRoot, "porydaw.app", "Contents", "MacOS", "porydaw"),
  ];
  for (const candidate of candidates) {
    try {
      if ((await Deno.stat(candidate)).isFile) {
        return await Deno.realPath(candidate);
      }
    } catch {
      // Try the next platform path.
    }
  }
  console.error(
    `run_checks: missing production porydaw binary beside the build: ${buildRoot}`,
  );
  Deno.exit(2);
}

async function loadManifest(
  checksBinary: string,
): Promise<readonly CheckManifestEntry[]> {
  const result = await new Deno.Command(checksBinary, {
    args: ["--manifest"],
    env: { QT_QPA_PLATFORM: "offscreen" },
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    console.error("run_checks: porydaw_checks --manifest failed");
    console.error(decoder.decode(result.stderr));
    Deno.exit(2);
  }
  let document: unknown;
  try {
    document = JSON.parse(decoder.decode(result.stdout));
  } catch (error) {
    console.error(
      `run_checks: invalid check manifest JSON: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    Deno.exit(2);
  }
  if (
    typeof document !== "object" || document === null ||
    !("checks" in document) || !Array.isArray(document.checks)
  ) {
    console.error("run_checks: unsupported check manifest");
    Deno.exit(2);
  }
  const checks = document.checks as readonly CheckManifestEntry[];
  if (
    checks.some(
      (check) =>
        check.windowing !== "offscreen" &&
        check.windowing !== "window-system",
    )
  ) {
    console.error("run_checks: manifest has an unsupported windowing mode");
    Deno.exit(2);
  }
  return checks;
}

function fixtureRoot(
  kind: FixtureRootKind,
  decompFixture: string,
  songsMkFixture: string,
): string | undefined {
  switch (kind) {
    case "decomp-project":
      return decompFixture;
    case "songs-mk-project":
      return songsMkFixture;
    case "none":
      return undefined;
  }
}

async function stageFixtureFiles(
  check: CheckManifestEntry,
  sourceRoot: string | undefined,
  scratch: string,
): Promise<void> {
  if (check.fixtureFiles.length === 0) {
    return;
  }
  if (sourceRoot === undefined) {
    throw new Error(
      `${check.name} declares fixture files without a fixture root`,
    );
  }

  for (const relativePath of check.fixtureFiles) {
    const source = join(sourceRoot, relativePath);
    const destination = join(scratch, relativePath);
    await requiredFile(source, `${check.name} fixture file`);
    await Deno.mkdir(dirname(destination), { recursive: true });
    await Deno.copyFile(source, destination);
  }
}

function expandArguments(
  check: CheckManifestEntry,
  scratch: string,
  mid2agb: string,
): string[] {
  const result: string[] = [];
  for (const argument of check.argv) {
    if (argument === "{scratch}") {
      result.push(scratch);
      continue;
    }
    if (argument === "{mid2agb}") {
      result.push(mid2agb);
      continue;
    }
    const optionalEnvironment = check.optionalArgumentEnvironment?.[argument];
    if (optionalEnvironment !== undefined) {
      const value = Deno.env.get(optionalEnvironment);
      if (value) {
        result.push(value);
      }
      continue;
    }
    result.push(argument);
  }
  return result;
}

function platformFor(check: CheckManifestEntry): string {
  if (check.windowing === "offscreen") {
    return "offscreen";
  }

  switch (Deno.build.os) {
    case "darwin":
      return "cocoa";
    case "windows":
      return "windows";
    case "linux":
      if (!Deno.env.get("DISPLAY")) {
        throw new Error(
          `${check.name} requires a window system, but DISPLAY is unset`,
        );
      }
      return "xcb";
    default:
      throw new Error(
        `${check.name} requires a window system unsupported on ${Deno.build.os}`,
      );
  }
}

function executionEnvironment(
  check: CheckManifestEntry,
): Readonly<Record<string, string>> {
  const environment = check.environment ?? {};
  if (environment.QT_QPA_PLATFORM !== undefined) {
    throw new Error(
      `${check.name} sets QT_QPA_PLATFORM; declare its windowing mode instead`,
    );
  }
  return { ...environment, QT_QPA_PLATFORM: platformFor(check) };
}

interface CheckResult {
  readonly code: number;
  readonly output: string;
  readonly signal: string | null;
  readonly timedOut: boolean;
  readonly durationMs: number;
}

async function runProcess(
  binary: string,
  args: string[],
  environment: Readonly<Record<string, string>>,
): Promise<CheckResult> {
  const startedAt = performance.now();
  const profileFile = Deno.env.get("LLVM_PROFILE_FILE");
  const child = new Deno.Command(binary, {
    args,
    env: {
      ASAN_OPTIONS: Deno.env.get("ASAN_OPTIONS") ?? "detect_leaks=0",
      ...(profileFile ? { LLVM_PROFILE_FILE: profileFile } : {}),
      ...environment,
    },
    stdout: "piped",
    stderr: "piped",
  }).spawn();

  let timedOut = false;
  let forceTimer: ReturnType<typeof setTimeout> | undefined;
  const timeoutTimer = setTimeout(() => {
    timedOut = true;
    try {
      child.kill("SIGTERM");
      forceTimer = setTimeout(() => {
        try {
          child.kill("SIGKILL");
        } catch {
          // The process exited during the grace period.
        }
      }, TERMINATE_GRACE_MS);
    } catch {
      // The process exited as the timer fired.
    }
  }, CHECK_TIMEOUT_MS);

  const result = await child.output();
  clearTimeout(timeoutTimer);
  if (forceTimer !== undefined) {
    clearTimeout(forceTimer);
  }
  const output = `${decoder.decode(result.stdout)}${
    decoder.decode(result.stderr)
  }`;
  return {
    code: result.code,
    output,
    signal: result.signal,
    timedOut,
    durationMs: performance.now() - startedAt,
  };
}

function lastNonemptyLine(output: string): string | undefined {
  return output.trimEnd().split(/\r?\n/).findLast((line) => line.length > 0);
}

if (Deno.args.length < 1) {
  usage();
}
let selection: string = "--all";
let reporterMode: "quiet" | "verbose" = "quiet";
const filters: string[] = [];
let unifiedPoolSize = MAX_PARALLEL_CHECKS;
for (let i = 1; i < Deno.args.length; i++) {
  const arg = Deno.args[i];
  if (arg === "--all" || arg === "--no-windowing-checks") {
    selection = arg;
  } else if (arg === "--verbose") {
    reporterMode = "verbose";
  } else if (arg.startsWith("--pool=")) {
    unifiedPoolSize = parsePool(arg.slice("--pool=".length));
  } else if (arg.startsWith("--reporter=")) {
    const value = arg.slice("--reporter=".length);
    if (value === "quiet" || value === "verbose") {
      reporterMode = value;
    } else {
      usage();
    }
  } else if (arg === "--reporter") {
    const value = Deno.args[++i];
    if (value === "quiet" || value === "verbose") {
      reporterMode = value;
    } else {
      usage();
    }
  } else if (arg.startsWith("--filter=")) {
    const value = arg.slice("--filter=".length);
    if (value.length === 0) usage();
    filters.push(value);
  } else if (arg === "--filter") {
    const value = Deno.args[++i];
    if (!value) usage();
    filters.push(value);
  } else {
    usage();
  }
}

const repoRoot = await Deno.realPath(new URL("..", import.meta.url));
const checksBinary = await resolveRequiredFile(
  Deno.args[0],
  "porydaw checks binary",
);
const checkManifest = await loadManifest(checksBinary);
const buildRoot = await Deno.realPath(dirname(checksBinary));
const applicationBinary = await findApplication(buildRoot);
const mid2agb = await findMid2Agb(buildRoot);
const decompFixture = join(
  repoRoot,
  "src",
  "checks",
  "fixtures",
  "decompproject",
);
const songsMkFixture = join(
  repoRoot,
  "src",
  "checks",
  "fixtures",
  "songsmkproject",
);
const tempRoot = await Deno.makeTempDir({ prefix: "porydaw-checks-" });
const failures: string[] = [];
const suiteStartedAt = performance.now();
// deno-lint-ignore prefer-const
let reporter!: Reporter;
async function runCheck(check: CheckManifestEntry): Promise<void> {
  if (reporter.onCheckStart) reporter.onCheckStart(check.name);
  const scratch = join(tempRoot, check.name);
  let result: CheckResult;
  try {
    if (check.scratchKind === "existing-directory") {
      await Deno.mkdir(scratch, { recursive: true });
    }
    await stageFixtureFiles(
      check,
      fixtureRoot(check.fixtureRootKind, decompFixture, songsMkFixture),
      scratch,
    );
    const binary = check.binary === "application"
      ? applicationBinary
      : checksBinary;
    result = await runProcess(
      binary,
      expandArguments(check, scratch, mid2agb),
      executionEnvironment(check),
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    result = {
      code: 1,
      output: message,
      signal: null,
      timedOut: false,
      durationMs: 0,
    };
  }
  if (result.code !== 0 || result.signal !== null || result.timedOut) {
    failures.push(check.name);
    reporter.onCheckFail(check.name, result);
    return;
  }
  const detail = lastNonemptyLine(result.output);
  reporter.onCheckPass(check.name, result.durationMs, detail);
}

async function runParallel(
  checks: readonly CheckManifestEntry[],
  poolSize: number,
): Promise<void> {
  if (checks.length === 0) return;
  // Each worker claims its next index before awaiting, so Deno's single
  // JavaScript event loop cannot assign one check to two workers.
  let nextCheck = 0;
  const workerCount = Math.min(poolSize, checks.length);
  await Promise.all(
    Array.from({ length: workerCount }, async () => {
      while (nextCheck < checks.length) {
        const check = checks[nextCheck++];
        await runCheck(check);
      }
    }),
  );
}

async function runScheduled(
  checks: readonly CheckManifestEntry[],
): Promise<void> {
  // Exclusive harnesses share global state (host audio device, QSettings) and
  // must run alone. Running them from manifest position drains every in-flight
  // batch once per exclusive; one serial tail drains at most once.
  const exclusiveChecks = checks.filter((check) => check.exclusive);
  // LPT: heaviest walls first minimizes makespan.
  const batched = checks
    .filter((check) => !check.exclusive)
    .sort((a, b) => wallEstimate(b.name) - wallEstimate(a.name));
  await runParallel(batched, unifiedPoolSize);
  for (const check of exclusiveChecks) {
    await runCheck(check);
  }
}

const skipWindowSystem = selection === "--no-windowing-checks";
let runnableChecks = checkManifest.filter(
  (check) => !skipWindowSystem || check.windowing !== "window-system",
);
if (filters.length > 0) {
  runnableChecks = runnableChecks.filter((check) =>
    filters.some((filter) => check.name.includes(filter))
  );
  if (runnableChecks.length === 0) {
    console.error(
      `run_checks: no harness matches filter: ${filters.join(", ")}`,
    );
    Deno.exit(2);
  }
}
reporter = createReporter(reporterMode, runnableChecks.length);
try {
  // Window-system checks schedule like any other: the unified pool already
  // overlaps them with offscreen work, and a separate lane would push peak
  // concurrency to pool+1.
  await runScheduled(runnableChecks);
} finally {
  await Deno.remove(tempRoot, { recursive: true });
}

reporter.onSummary(
  failures,
  performance.now() - suiteStartedAt,
  checkManifest.length,
  runnableChecks.length,
);
if (failures.length > 0) {
  Deno.exit(1);
}
