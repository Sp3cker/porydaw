// Run every porydaw check harness with only its declared fixture files.
// Point this at an ASAN build (-DPORYDAW_ASAN=ON) to turn silent memory bugs
// into aborts with stack traces.
//
// usage: deno task checks <porydaw-binary>
//
// env: PORYDAW_SAMPLE_CORPUS  optional built project for samplecheck's corpus
//      PORYDAW_SMF_STRESS    nonempty: run bounded SMF automation stress checks
//      ASAN_OPTIONS defaults to detect_leaks=0

import { dirname, join } from "node:path";

import {
  CHECK_MANIFEST,
  type CheckManifestEntry,
  type FixtureRootKind,
  OPTIONAL_ARG_ENV,
} from "./check_manifest.ts";

const CHECK_TIMEOUT_MS = 90_000;
const TERMINATE_GRACE_MS = 5_000;
const decoder = new TextDecoder();

function usage(): never {
  console.error("usage: deno task checks <porydaw-binary>");
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
    const optionalEnvironment = OPTIONAL_ARG_ENV[argument];
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

interface CheckResult {
  readonly code: number;
  readonly output: string;
  readonly timedOut: boolean;
  readonly durationMs: number;
}

async function runProcess(
  binary: string,
  args: string[],
): Promise<CheckResult> {
  const startedAt = performance.now();
  const child = new Deno.Command(binary, {
    args,
    env: {
      ASAN_OPTIONS: Deno.env.get("ASAN_OPTIONS") ?? "detect_leaks=0",
      QT_QPA_PLATFORM: "offscreen",
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
    timedOut,
    durationMs: performance.now() - startedAt,
  };
}

function lastNonemptyLine(output: string): string | undefined {
  return output.trimEnd().split(/\r?\n/).findLast((line) => line.length > 0);
}

function printFailure(name: string, result: CheckResult): void {
  const reason = result.timedOut
    ? `exceeded ${CHECK_TIMEOUT_MS / 1000}s`
    : `exit ${result.code}`;
  console.log(
    `FAIL: ${name} (${reason}, ${(result.durationMs / 1000).toFixed(2)}s)`,
  );
  const lines = result.output.trimEnd().split(/\r?\n/);
  console.log(lines.slice(-40).join("\n"));
}

if (Deno.args.length !== 1) {
  usage();
}

const repoRoot = await Deno.realPath(new URL("..", import.meta.url));
const binary = await resolveRequiredFile(Deno.args[0], "porydaw binary");

const appMarker = `${join(".app", "Contents", "MacOS")}`;
const buildRoot = binary.includes(appMarker)
  ? await Deno.realPath(join(dirname(binary), "..", "..", ".."))
  : await Deno.realPath(dirname(binary));
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

try {
  for (const check of CHECK_MANIFEST) {
    if (check.envGate !== undefined && !Deno.env.get(check.envGate)) {
      continue;
    }

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
      result = await runProcess(
        binary,
        expandArguments(check, scratch, mid2agb),
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      result = { code: 1, output: message, timedOut: false, durationMs: 0 };
    }

    if (result.code !== 0 || result.timedOut) {
      failures.push(check.name);
      printFailure(check.name, result);
    } else {
      const detail = lastNonemptyLine(result.output);
      const duration = `${(result.durationMs / 1000).toFixed(2)}s`;
      console.log(
        detail
          ? `ok: ${check.name} (${duration}) — ${detail}`
          : `ok: ${check.name} (${duration})`,
      );
    }
  }
} finally {
  await Deno.remove(tempRoot, { recursive: true });
}

console.log();
if (failures.length > 0) {
  console.log(`run_checks: FAIL (${failures.length}): ${failures.join(" ")}`);
  Deno.exit(1);
}
console.log(
  `run_checks: PASS (all harnesses in ${
    ((performance.now() - suiteStartedAt) / 1000).toFixed(2)
  }s)`,
);
