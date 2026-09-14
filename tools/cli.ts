// Singular CLI for porydaw build/verify/format lanes.
// Builds print only summaries and diagnostics; verify uses a quiet reporter with a live name line.
// Usage:
// deno task build:app [--release] -> build porydaw only
// deno task build:checks [--release] -> build porydaw + porydaw_checks + mid2agb
// deno task verify [--verbose] [--filter <name>] [-- <run_checks args>]
// deno task format [--check] [files...]

import { join } from "node:path";
import { poryaaaaConfiguration } from "./poryaaaa_source.ts";
import { unsupportedSources, unsupportedSourcesError } from "./format.ts";
import { parseCheckOptions, VERIFY_HELP } from "./checks_options.ts";

const decoder = new TextDecoder();
const BUILD_DIR = "build";

type Subcommand = "build:app" | "build:checks" | "verify" | "format";

function help(command?: Subcommand): string {
  switch (command) {
    case "verify":
      return VERIFY_HELP;
    case "build:app":
    case "build:checks":
      return `usage: deno task ${command} [--release] [--help]
  ${
        command === "build:app"
          ? "build the application"
          : "build the application, checks, and mid2agb"
      }
  --release       configure and build Release
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
  verify        build and run checks
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

async function ensureConfigured(release: boolean): Promise<void> {
  const poryaaaa = await poryaaaaConfiguration(BUILD_DIR);
  const ninjaFile = join(BUILD_DIR, "build.ninja");
  const makefile = join(BUILD_DIR, "Makefile");
  const hasBuildSystem = (await exists(ninjaFile)) || (await exists(makefile));
  if (!release && hasBuildSystem && poryaaaa.cacheMatches) return;
  const result = await new Deno.Command("cmake", {
    args: [
      "-S",
      ".",
      "-B",
      BUILD_DIR,
      "-DCMAKE_BUILD_TYPE=Release",
      poryaaaa.cmakeArgument,
    ],
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
): Promise<void> {
  const started = performance.now();
  await ensureConfigured(release);
  const nproc = String(navigator.hardwareConcurrency);
  const args = ["--build", BUILD_DIR, "-j", nproc];
  if (release) args.push("--config", "Release");
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

async function runVerify(rawArgs: string[]): Promise<void> {
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
        usage("verify", "--filter requires a value");
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

  const binary = join(BUILD_DIR, "porydaw_checks");
  const reporterArgs = verbose ? ["--reporter=verbose"] : [];
  const args = [...reporterArgs, ...filters, ...passthrough];
  if (qtPayload !== undefined) args.push("--qt", ...qtPayload);
  let options;
  try {
    options = parseCheckOptions(args);
  } catch (error) {
    usage("verify", error instanceof Error ? error.message : String(error));
  }
  if (options.help) showHelp("verify");
  await runBuild(["porydaw", "porydaw_checks", "mid2agb"]);
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
const normalized = sub as Subcommand;
switch (normalized) {
  case "build:app":
    await runBuild(["porydaw"], buildRelease(rest, "build:app"));
    break;
  case "build:checks":
    await runBuild(
      ["porydaw", "porydaw_checks", "mid2agb"],
      buildRelease(rest, "build:checks"),
    );
    break;
  case "verify":
    await runVerify(rest);
    break;
  case "format":
    await runFormat(rest);
    break;
  default:
    usage(undefined, `unknown command ${sub}`);
}
