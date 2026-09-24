// Singular CLI for porydaw build/verify/format lanes.
// Builds print only summaries and diagnostics; verify uses a quiet reporter with a live name line.
// Usage:
// deno task build:app [--release] -> Debug porydaw; --release opts into Release
// deno task build:checks [--release] -> Debug porydaw + checks + mid2agb
// deno task build:render [--release] -> Debug porydaw_render_cli; --release opts into Release
// deno task verify [--verbose] [--filter <name>] [-- <run_checks args>]
// deno task verify:qml [verify options] -> build editor_qml_tests + mid2agb, run that lane
// deno task verify:qml-roll [verify options] -> build roll_qml_tests + mid2agb, run that lane
// deno task verify:shell [verify options] -> build shell_qml_tests + mid2agb, run that lane
// deno task format [--check] [files...]

import { join } from "node:path";
import {
  cmakeConfigureArgs,
  localQtPrefix,
} from "./local_build_environment.ts";
import { poryaaaaConfiguration } from "./poryaaaa_source.ts";
import { unsupportedSources, unsupportedSourcesError } from "./format.ts";
import {
  type CheckOptions,
  parseCheckOptions,
  VERIFY_HELP,
} from "./checks_options.ts";

const decoder = new TextDecoder();
const BUILD_DIR = "build";

type Subcommand =
  | "build:app"
  | "build:checks"
  | "build:render"
  | "verify"
  | "verify:qml"
  | "verify:qml-roll"
  | "verify:shell"
  | "verify:bridge"
  | "format";

function help(command?: Subcommand): string {
  switch (command) {
    case "verify":
      return VERIFY_HELP;
    case "verify:qml":
      // Same runner options; only the build targets and harness binary differ.
      return VERIFY_HELP.replaceAll("deno task verify", "deno task verify:qml");
    case "verify:qml-roll":
      return VERIFY_HELP.replaceAll(
        "deno task verify",
        "deno task verify:qml-roll",
      );
    case "verify:shell":
      return VERIFY_HELP.replaceAll(
        "deno task verify",
        "deno task verify:shell",
      );
    case "verify:bridge":
      return `usage: deno task verify:bridge [--update-baseline] [--help]
  check Swift/QML QtBridge surface against the shrink-only baseline
  --update-baseline  replace the baseline with current findings
  --help             show this help without checking

Examples:
  deno task verify:bridge
  deno task verify:bridge --update-baseline`;
    case "build:app":
    case "build:checks":
    case "build:render":
      return `usage: deno task ${command} [--release] [--help]
  ${
        command === "build:app"
          ? "build the application"
          : command === "build:render"
          ? "build the Swift-backed offline renderer"
          : "build the application, checks, and mid2agb"
      }
  --release       configure and build Release; default is Debug
  --verbose, -v   accepted; successful builds remain concise
  --help          show this help without building

Examples:
  deno task ${command}
  deno task ${command} --release`;
    case "format":
      return `usage: deno task format [--check] [files...] [--help]
  default: format supported TypeScript and C/C++ sources
  --check  report formatting differences without editing
  --help   show this help without running formatters

Examples:
  deno task format --check
  deno task format tools/cli.ts`;
    default:
      return `usage: deno task <command> [options]
  build:app     build the application
  build:checks  build the application, checks, and mid2agb
  build:render  build the Swift-backed offline renderer
  verify        build and run checks
  verify:qml    build and run the QML drawer lane
  verify:qml-roll  build and run the QML roll window lane
  verify:shell  build and run the production QML shell lane
  verify:bridge  check the Swift/QML QtBridge surface
  format        format sources (or --check)
help: deno task <command> --help`;
  }
}

function usage(command?: Subcommand, message?: string): never {
  if (message) console.error(`error: ${message}`);
  console.error(help(command));
  Deno.exit(2);
}

function showHelp(command?: Subcommand): never {
  console.log(help(command));
  Deno.exit(0);
}

function isVerbose(args: string[]): boolean {
  return args.includes("--verbose") || args.includes("-v");
}

function buildRelease(args: string[], command: Subcommand): boolean {
  const unknown = args.find((arg) =>
    arg !== "--release" && arg !== "--verbose" && arg !== "-v" &&
    arg !== "--help"
  );
  if (unknown) usage(command, `unknown argument ${unknown}`);
  if (args.includes("--help")) showHelp(command);
  return args.includes("--release");
}

function printCapturedOutput(output: string): void {
  if (output.trim()) console.error(output.trimEnd());
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function hasBuildSystem(): Promise<boolean> {
  const ninjaFile = join(BUILD_DIR, "build.ninja");
  const makefile = join(BUILD_DIR, "Makefile");
  if ((await exists(ninjaFile)) || (await exists(makefile))) return true;
  try {
    for await (const entry of Deno.readDir(BUILD_DIR)) {
      if (entry.isFile && entry.name.endsWith(".sln")) return true;
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
  return false;
}

async function usesMultiConfigBuild(): Promise<boolean> {
  try {
    const cache = await Deno.readTextFile(join(BUILD_DIR, "CMakeCache.txt"));
    return /^CMAKE_CONFIGURATION_TYPES:[^=]*=.+$/m.test(cache);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function cachedBuildType(): Promise<string | undefined> {
  try {
    const cache = await Deno.readTextFile(join(BUILD_DIR, "CMakeCache.txt"));
    return /^CMAKE_BUILD_TYPE:STRING=(.*)$/m.exec(cache)?.[1];
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

async function cachedBuildChecks(): Promise<boolean | undefined> {
  try {
    const cache = await Deno.readTextFile(join(BUILD_DIR, "CMakeCache.txt"));
    const value = /^PORYDAW_BUILD_CHECKS:BOOL=(.*)$/m.exec(cache)?.[1];
    if (value === "ON") return true;
    if (value === "OFF") return false;
    return undefined;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

async function ensureConfigured(
  release: boolean,
  buildChecks: boolean,
): Promise<void> {
  const poryaaaa = await poryaaaaConfiguration(BUILD_DIR);
  const buildType = release ? "Release" : "Debug";
  const multiConfig = await usesMultiConfigBuild();
  const typeMatches = multiConfig ||
    (await cachedBuildType()) === buildType;
  const checksMatch = (await cachedBuildChecks()) === buildChecks;
  if (
    (await hasBuildSystem()) && poryaaaa.cacheMatches && typeMatches &&
    checksMatch
  ) return;
  const localQt = await localQtPrefix();
  const result = await new Deno.Command("cmake", {
    args: await cmakeConfigureArgs({
      buildDirectory: BUILD_DIR,
      poryaaaaArgument: poryaaaa.cmakeArgument,
      qtPrefix: localQt,
      buildType,
      buildChecks,
    }),
    stdout: "piped",
    stderr: "piped",
  }).output();
  const out = decoder.decode(result.stdout);
  const err = decoder.decode(result.stderr);
  if (!result.success) {
    printCapturedOutput(out + err);
    console.error("build: configure failed");
    Deno.exit(result.code || 1);
  }
  printCapturedOutput(err);
}

async function runBuild(
  targets: string[],
  release = false,
  buildChecks = true,
): Promise<void> {
  const started = performance.now();
  await ensureConfigured(release, buildChecks);
  const nproc = String(navigator.hardwareConcurrency);
  const args = ["--build", BUILD_DIR, "-j", nproc];
  if (release || (await usesMultiConfigBuild())) {
    args.push("--config", "Release");
  }
  if (targets.length > 0) {
    args.push("--target", ...targets);
  }
  const child = new Deno.Command("cmake", {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const result = await child;
  const out = decoder.decode(result.stdout);
  const err = decoder.decode(result.stderr);
  const combined = out + err;
  if (!result.success) {
    printCapturedOutput(combined);
    console.error(`build: failed (${targets.join(", ") || "all"})`);
    Deno.exit(result.code || 1);
  }
  if (/\b(?:warning(?:\s+[A-Z]+\d+)?:|CMake Warning\b)/i.test(combined)) {
    printCapturedOutput(combined);
  }
  const ms = performance.now() - started;
  const sec = (ms / 1000).toFixed(2);
  // Filter progress noise: only show summary, not per-target [%] lines
  console.log(`build: ok (${sec}s)`);
}
// One verify lane = the build targets it needs plus the harness it runs through
// tools/run_checks.ts. Options, filters and the --qt payload are identical.
interface VerifyLane {
  readonly command:
    | "verify"
    | "verify:qml"
    | "verify:qml-roll"
    | "verify:shell";
  /** Harness executable name inside the build directory. */
  readonly binary: string;
  buildTargets(options: CheckOptions): string[];
}

// The application binary is only needed by the production-startup windowed rows.
function verifyBuildTargets(options: CheckOptions): string[] {
  const productionStartupSelected = options.filters.length === 0
    ? !options.exclusions.includes("production-startup")
    : options.filters.some((filter) => "production-startup".includes(filter)) &&
      !options.exclusions.includes("production-startup");
  return [
    ...(productionStartupSelected ? ["porydaw"] : []),
    "porydaw_checks",
    "mid2agb",
  ];
}

const VERIFY_LANES: Record<
  "verify" | "verify:qml" | "verify:qml-roll" | "verify:shell",
  VerifyLane
> = {
  "verify": {
    command: "verify",
    binary: "porydaw_checks",
    buildTargets: verifyBuildTargets,
  },
  // The QML lane is its own executable and manifest, not a porydaw_checks
  // catalog row; run_checks.ts still needs mid2agb beside the build.
  "verify:qml": {
    command: "verify:qml",
    binary: "editor_qml_tests",
    buildTargets: () => ["editor_qml_tests", "mid2agb"],
  },
  // The roll window lane is its own executable and manifest too; it mounts the
  // production SwiftRollOverlay against a real ApplicationSession.
  "verify:qml-roll": {
    command: "verify:qml-roll",
    binary: "roll_qml_tests",
    buildTargets: () => ["roll_qml_tests", "mid2agb"],
  },
  "verify:shell": {
    command: "verify:shell",
    binary: "shell_qml_tests",
    buildTargets: () => ["shell_qml_tests", "mid2agb"],
  },
};

async function runBridge(args: string[]): Promise<void> {
  if (args.includes("--help")) showHelp("verify:bridge");
  const unknown = args.find((arg) => arg !== "--update-baseline");
  if (unknown) usage("verify:bridge", `unknown argument ${unknown}`);
  const result = await new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read=src,CMakeLists.txt,cmake/QtBridge.cmake,tools",
      ...(args.includes("--update-baseline") ? ["--allow-write=tools"] : []),
      "tools/qtbridge_surface.ts",
      ...args,
    ],
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) Deno.exit(result.code);
}

async function runVerify(
  rawArgs: string[],
  lane: VerifyLane,
): Promise<void> {
  // Terminal --qt: everything after it is the Qt test payload. It is never
  // parsed as a runner option — not by the loop below and not by the
  // no-build/verbose pre-scans. run_checks.ts parses the marker identically.
  const qtIndex = rawArgs.indexOf("--qt");
  const runnerArgs = qtIndex === -1 ? rawArgs : rawArgs.slice(0, qtIndex);
  const qtPayload = qtIndex === -1 ? undefined : rawArgs.slice(qtIndex + 1);
  const verbose = isVerbose(runnerArgs);
  const filters: string[] = [];
  const passthrough: string[] = [];
  for (let i = 0; i < runnerArgs.length; i++) {
    const arg = runnerArgs[i];
    if (arg === "--verbose" || arg === "-v") {
      continue;
    } else if (arg.startsWith("--filter=")) {
      filters.push(arg);
    } else if (arg === "--filter") {
      const next = runnerArgs[++i];
      if (!next || next.startsWith("-")) {
        usage(lane.command, "--filter requires a value");
      }
      filters.push(`--filter=${next}`);
    } else if (arg === "--all" || arg === "--no-windowing-checks") {
      passthrough.push(arg);
    } else if (arg === "--") {
      passthrough.push(...runnerArgs.slice(i + 1));
      break;
    } else if (arg.startsWith("-")) {
      passthrough.push(arg);
    } else {
      passthrough.push(arg);
    }
  }

  const reporterArgs = verbose ? ["--reporter=verbose"] : [];
  const args = [...reporterArgs, ...filters, ...passthrough];
  if (qtPayload !== undefined) args.push("--qt", ...qtPayload);
  let options;
  try {
    options = parseCheckOptions(args);
  } catch (error) {
    usage(lane.command, error instanceof Error ? error.message : String(error));
  }
  if (options.help) showHelp(lane.command);
  await runBridge([]);
  await runBuild(lane.buildTargets(options), false, true);
  const executable = Deno.build.os === "windows"
    ? `${lane.binary}.exe`
    : lane.binary;
  const binary = join(
    BUILD_DIR,
    ...((Deno.build.os === "windows" && await usesMultiConfigBuild())
      ? ["Release"]
      : []),
    executable,
  );
  const cmd = new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read",
      "--allow-write",
      "--allow-run",
      "--allow-env=ASAN_OPTIONS,DISPLAY,LLVM_PROFILE_FILE,PORYDAW_SAMPLE_CORPUS",
      "tools/run_checks.ts",
      binary,
      ...args,
    ],
    stdout: "inherit",
    stderr: "inherit",
    stdin: "null",
  });
  const status = await cmd.output();
  Deno.exit(status.code);
}

async function runFormat(rawArgs: string[]): Promise<void> {
  const unknown = rawArgs.find((arg) =>
    arg.startsWith("-") && arg !== "--check" && arg !== "--help"
  );
  if (unknown) usage("format", `unknown argument ${unknown}`);
  if (rawArgs.includes("--help")) showHelp("format");
  const check = rawArgs.includes("--check");

  const files = rawArgs.filter((a) => a !== "--check");

  // Reject unsupported explicit files up front: a mixed list such as
  // `deno task format a.ts b.qml` must fail before deno fmt touches the
  // TypeScript half. tools/format.ts re-applies the same rule when invoked
  // directly.
  const bad = unsupportedSources(files.filter((f) => !f.endsWith(".ts")));
  if (bad.length > 0) {
    console.error(`format: ${unsupportedSourcesError(bad)}`);
    Deno.exit(2);
  }

  const tsFiles = files.filter((f) => f.endsWith(".ts"));
  if (files.length === 0) {
    const denoFmtArgs = check ? ["fmt", "--check"] : ["fmt"];
    const denoResult = await new Deno.Command("deno", {
      args: denoFmtArgs,
      stdout: "inherit",
      stderr: "inherit",
    }).output();
    if (!denoResult.success) Deno.exit(denoResult.code);
  } else if (tsFiles.length > 0) {
    const denoFmtArgs = check
      ? ["fmt", "--check", ...tsFiles]
      : ["fmt", ...tsFiles];
    const denoResult = await new Deno.Command("deno", {
      args: denoFmtArgs,
      stdout: "inherit",
      stderr: "inherit",
    }).output();
    if (!denoResult.success) Deno.exit(denoResult.code);
  }

  const formatArgs = [
    ...(check ? ["--check"] : []),
    ...files.filter((f) => !f.endsWith(".ts") || files.length === 0),
  ];
  const clangFiles = formatArgs.filter((a) => a !== "--check");
  if (files.length > 0 && clangFiles.length === 0) {
    if (!check) {
      console.log(`format: formatted ${tsFiles.length} TypeScript files`);
    } else {console.log(
        `format: all ${tsFiles.length} TypeScript files formatted`,
      );}
    return;
  }

  // Delegate to tools/format.ts for C++ handling (explicit files support)
  const args = [
    "run",
    "--allow-read",
    "--allow-run",
    "--allow-env=CLANG_FORMAT",
    "tools/format.ts",
    ...formatArgs,
  ];
  const result = await new Deno.Command("deno", {
    args,
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  Deno.exit(result.code);
}

const raw = Deno.args.slice(0);
if (raw.length === 0) usage();
if (raw[0] === "--help") showHelp();
let sub = raw[0];
const rest = raw.slice(1);
// Normalize hyphen vs colon: build-app -> build:app
if (sub === "build-app") sub = "build:app";
if (sub === "build-checks" || sub === "build:check") sub = "build:checks";
if (sub === "build-render") sub = "build:render";
if (sub === "verify-qml") sub = "verify:qml";
if (sub === "verify-qml-roll" || sub === "verify:qmlroll") {
  sub = "verify:qml-roll";
}
if (sub === "verify-shell") sub = "verify:shell";
const normalized = sub as Subcommand;
switch (normalized) {
  case "build:app":
    await runBuild(["porydaw"], buildRelease(rest, "build:app"), false);
    break;
  case "build:render":
    await runBuild(
      ["porydaw_render_cli"],
      buildRelease(rest, "build:render"),
      false,
    );
    break;
  case "build:checks":
    await runBuild(
      ["porydaw", "porydaw_checks", "mid2agb"],
      buildRelease(rest, "build:checks"),
      true,
    );
    break;
  case "verify":
    await runVerify(rest, VERIFY_LANES.verify);
    break;
  case "verify:bridge":
    await runBridge(rest);
    break;
  case "verify:qml":
    await runVerify(rest, VERIFY_LANES["verify:qml"]);
    break;
  case "verify:qml-roll":
    await runVerify(rest, VERIFY_LANES["verify:qml-roll"]);
  case "verify:shell":
    await runVerify(rest, VERIFY_LANES["verify:shell"]);
    break;
  case "format":
    await runFormat(rest);
    break;
  default:
    usage(undefined, `unknown command ${sub}`);
}
