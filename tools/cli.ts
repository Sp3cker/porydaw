// Singular CLI for porydaw build/verify/format lanes.
// Builds print only summaries and diagnostics; verify uses a quiet reporter with a live name line.
// Usage:
// deno task build:app [--release] -> build porydaw only
// deno task build:checks [--release] -> build porydaw + porydaw_checks + mid2agb
// deno task verify [--verbose] [--filter <name>] [-- <run_checks args>]
// deno task format [--check] [files...]

import { join } from "node:path";
import { poryaaaaConfiguration } from "./poryaaaa_source.ts";

const decoder = new TextDecoder();
const BUILD_DIR = "build";

type Subcommand = "build:app" | "build:checks" | "verify" | "format";

function usage(): never {
  console.error(`usage:
 deno task build:app [--release]    build porydaw app only
 deno task build:checks [--release] build porydaw + checks + mid2agb
 deno task verify [--verbose] [--filter <name>] [-- <run_checks args>]
 deno task format [--check] [files...]`);
  console.error("");
  console.error(
    "verify forwards --all/--no-windowing-checks/--filter to run_checks.ts",
  );
  console.error(" --verbose  show per-harness ok: lines");
  console.error(" --release  configure and build the Release configuration");
  Deno.exit(2);
}

function isVerbose(args: string[]): boolean {
  return args.includes("--verbose") || args.includes("-v");
}

function buildRelease(args: string[]): boolean {
  // Old agent prompts may still pass build verbosity. Keep them working, but
  // never let those flags expand successful build output.
  if (
    args.some((arg) =>
      arg !== "--release" && arg !== "--verbose" && arg !== "-v"
    )
  ) usage();
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
  if (rawArgs.includes("--no-build")) usage();
  const verbose = isVerbose(rawArgs);
  const filters: string[] = [];
  const passthrough: string[] = [];
  for (let i = 0; i < rawArgs.length; i++) {
    const arg = rawArgs[i];
    if (arg === "--verbose" || arg === "-v") {
      continue;
    } else if (arg.startsWith("--filter=")) {
      filters.push(arg);
    } else if (arg === "--filter") {
      const next = rawArgs[++i];
      if (!next) usage();
      filters.push(`--filter=${next}`);
    } else if (arg === "--all" || arg === "--no-windowing-checks") {
      passthrough.push(arg);
    } else if (arg === "--") {
      passthrough.push(...rawArgs.slice(i + 1));
      break;
    } else if (arg.startsWith("-")) {
      passthrough.push(arg);
    } else {
      passthrough.push(arg);
    }
  }

  await runBuild(["porydaw", "porydaw_checks", "mid2agb"]);

  const binary = join(BUILD_DIR, "porydaw_checks");
  const reporterArgs = verbose ? ["--reporter=verbose"] : [];
  const args = [...reporterArgs, ...filters, ...passthrough];
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
  const check = rawArgs.includes("--check");
  const files = rawArgs.filter((a) => a !== "--check");

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
let sub = raw[0];
const rest = raw.slice(1);
// Normalize hyphen vs colon: build-app -> build:app
if (sub === "build-app") sub = "build:app";
if (sub === "build-checks" || sub === "build:check") sub = "build:checks";
const normalized = sub as Subcommand;
switch (normalized) {
  case "build:app":
    await runBuild(["porydaw"], buildRelease(rest));
    break;
  case "build:checks":
    await runBuild(
      ["porydaw", "porydaw_checks", "mid2agb"],
      buildRelease(rest),
    );
    break;
  case "verify":
    await runVerify(rest);
    break;
  case "format":
    await runFormat(rest);
    break;
  default:
    usage();
}
