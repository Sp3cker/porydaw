// Singular CLI for porydaw build/verify/format lanes.
// Quiet by default: build buffers ninja progress, verify uses quiet reporter with live name line.
// Usage:
// deno task build:app -> build porydaw only
// deno task build:checks -> build porydaw + porydaw_checks + mid2agb
// deno task verify [--verbose] [--filter <name>] [--no-build] [-- <run_checks args>]
// deno task format [--check] [files...]

import { join } from "node:path";

const decoder = new TextDecoder();
const BUILD_DIR = "build";

type Subcommand =
  | "build:app"
  | "build:checks"
  | "verify"
  | "format";

function usage(): never {
  console.error(`usage:
 deno task build:app            build porydaw app only
 deno task build:checks         build porydaw + checks + mid2agb
 deno task verify [--verbose] [--filter <name>] [--no-build] [-- <run_checks args>]
 deno task format [--check] [files...]`);
  console.error("");
  console.error(
    "verify forwards --all/--no-windowing-checks/--filter to run_checks.ts",
  );
  console.error(" --verbose  show per-harness ok: lines");
  console.error(" --no-build skip cmake build step");
  Deno.exit(2);
}

function isVerbose(args: string[]): boolean {
  return args.includes("--verbose") || args.includes("-v");
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

async function ensureConfigured(verbose: boolean): Promise<void> {
  const ninjaFile = join(BUILD_DIR, "build.ninja");
  const makefile = join(BUILD_DIR, "Makefile");
  if ((await exists(ninjaFile)) || (await exists(makefile))) return;
  const started = performance.now();
  if (verbose) console.error(`build: configuring...`);
  const result = await new Deno.Command("cmake", {
    args: ["-S", ".", "-B", BUILD_DIR, "-DCMAKE_BUILD_TYPE=Release"],
    stdout: verbose ? "inherit" : "piped",
    stderr: verbose ? "inherit" : "piped",
  }).output();
  if (!result.success) {
    const out = decoder.decode(result.stderr) + decoder.decode(result.stdout);
    if (out.trim()) console.error(out.trimEnd());
    console.error("build: configure failed");
    Deno.exit(result.code || 1);
  }
  const ms = performance.now() - started;
  if (!verbose) console.log(`build: configured (${(ms / 1000).toFixed(2)}s)`);
}

async function runBuild(
  targets: string[],
  verbose: boolean,
): Promise<void> {
  await ensureConfigured(verbose);
  const started = performance.now();
  const nproc = String(navigator.hardwareConcurrency);
  const args = ["--build", BUILD_DIR, "-j", nproc];
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
    // Quiet buffering: spill only on failure
    if (combined.trim()) {
      const lines = combined.trimEnd().split("\n");
      // Keep last 80 lines for context, filter obvious progress noise on failure too
      const tail = lines.slice(-80).join("\n");
      console.error(tail);
    }
    console.error(`build: failed (${targets.join(", ") || "all"})`);
    // Also hint log location
    Deno.exit(result.code || 1);
  }
  const ms = performance.now() - started;
  const sec = (ms / 1000).toFixed(2);
  // Filter progress noise: only show summary, not per-target [%] lines
  console.log(`build: ok (${sec}s)`);
  const artifacts: string[] = [];
  if (targets.includes("porydaw")) {
    artifacts.push(`${BUILD_DIR}/porydaw.app/Contents/MacOS/porydaw`);
  }
  if (targets.includes("porydaw_checks")) {
    artifacts.push(`${BUILD_DIR}/porydaw_checks`);
  }
  if (targets.includes("mid2agb")) {
    artifacts.push(`${BUILD_DIR}/mid2agb`);
  }
  if (artifacts.length === 0 && targets.length === 0) {
    artifacts.push(BUILD_DIR);
  }
  if (artifacts.length > 0) {
    console.log(`  → ${artifacts.join("\n  → ")}`);
  }
  console.log(`Built to ${BUILD_DIR}/`);
}

async function runVerify(rawArgs: string[]): Promise<void> {
  const verbose = isVerbose(rawArgs);
  const noBuild = rawArgs.includes("--no-build");
  const filters: string[] = [];
  const passthrough: string[] = [];
  for (let i = 0; i < rawArgs.length; i++) {
    const arg = rawArgs[i];
    if (arg === "--verbose" || arg === "-v" || arg === "--no-build") {
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

  if (!noBuild) {
    await runBuild(["porydaw_checks", "mid2agb"], verbose);
  }

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
    await runBuild(["porydaw"], isVerbose(rest));
    break;
  case "build:checks":
    await runBuild([
      "porydaw",
      "porydaw_checks",
      "mid2agb",
      "porydaw_loadbench_cli",
    ], isVerbose(rest));
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
