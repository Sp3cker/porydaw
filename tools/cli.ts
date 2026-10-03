// Singular CLI for porydaw build/checks/format lanes. Output is limited to what
// needs acting on; builds keep their complete output in build/<config>/build.log.
// Usage:
// deno task build:app [--release]     -> porydaw in build/debug (or build/release)
// deno task build:checks [--release]  -> porydaw + checks + mid2agb
// deno task build:render [--release]  -> porydaw_render_cli
// deno task checks [--filter <name>] [...]  -> build, then run porydaw_checks
// deno task checks:qml | checks:qml-roll | checks:shell [checks options]
// deno task checks:bridge             -> QtBridge surface guard
// deno task format [--check] [--base <ref>] [files...]

import { join } from "node:path";
import type { BuildConfig } from "./local_build_environment.ts";
import { runBuild, usesMultiConfigBuild } from "./build.ts";
import { formatSources } from "./format.ts";
import {
  type CheckOptions,
  CHECKS_HELP,
  parseCheckOptions,
} from "./checks_options.ts";

type Lane = "checks" | "checks:qml" | "checks:qml-roll" | "checks:shell";

type Subcommand =
  | "build:app"
  | "build:checks"
  | "build:render"
  | Lane
  | "checks:bridge"
  | "format";

function help(command?: Subcommand): string {
  switch (command) {
    case "checks":
      return CHECKS_HELP;
    case "checks:qml":
    case "checks:qml-roll":
    case "checks:shell":
      // Same runner options; only the build targets and harness binary differ.
      return CHECKS_HELP.replaceAll("deno task checks", `deno task ${command}`);
    case "checks:bridge":
      return `usage: deno task checks:bridge [--help]
  check Swift/QML QtBridge surface against the baseline (read-only)

  deno task bridge:baseline regenerates the baseline, allowing growth`;
    case "build:app":
    case "build:checks":
    case "build:render":
      return `usage: deno task ${command} [--release | --asan] [--help]
  ${
        command === "build:app"
          ? "build the application"
          : command === "build:render"
          ? "build the Swift-backed offline renderer"
          : "build the application, checks, and mid2agb"
      }
  --release  configure and build Release in build/release; default is Debug
             in build/debug
  --asan     configure and build Debug with AddressSanitizer in build/asan
  --help     show this help without building

A failed build prints its errors and the path of the complete log
(build/<config>/build.log). Read that log; rebuilding adds no detail.`;
    case "format":
      return `usage: deno task format [--check] [--base <ref>] [--whole] [files...] [--help]
  default: Swift lines changed since --base, and TypeScript under tools/
  --check       report unformatted code without editing
  --base <ref>  measure Swift changes from merge-base(<ref>, HEAD) to the
                working tree; default HEAD (uncommitted changes only)
  files         restrict to these .swift/.ts files (still changed lines only)
  --whole       reflow the named files entirely (requires files)
  --help        show this help without running formatters

Examples:
  deno task format
  deno task format --check --base origin/fork-main
  deno task format --whole src/swift/core/Xcmd.swift`;
    default:
      return `usage: deno task <command> [options]
  build            this help (deno task build, not a real build)
  build:app        build the application
  build:checks     build the application, checks, and mid2agb
  build:render     build the Swift-backed offline renderer
  bench:startup    benchmark existing Release app spawn to first frame
  checks           build and run checks
  checks:qml       build and run the QML drawer lane
  checks:qml-roll  build and run the QML roll window lane
  checks:shell     build and run the production QML shell lane
  checks:bridge    check the Swift/QML QtBridge surface
  bridge:baseline  regenerate the QtBridge surface baseline
  format           format changed Swift and TypeScript (or --check)
  proof            read proof-ledger status
  proof:edit       edit proof ledgers
  proof:compact    compact proof ledgers
  setup            provision a fresh checkout
  lsp:swift        regenerate the Swift compile database
  worktree:create  create a linked worktree
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

function buildConfig(args: string[], command: Subcommand): BuildConfig {
  const unknown = args.find((arg) =>
    arg !== "--release" && arg !== "--asan" && arg !== "--help"
  );
  if (unknown) usage(command, `unknown argument ${unknown}`);
  if (args.includes("--help")) showHelp(command);
  if (args.includes("--release") && args.includes("--asan")) {
    usage(command, "--release and --asan are mutually exclusive");
  }
  if (args.includes("--asan")) return "asan";
  return args.includes("--release") ? "release" : "debug";
}

// One lane = the build targets it needs plus the harness it runs through
// tools/run_checks.ts. Options, filters and the --qt payload are identical.
interface CheckLane {
  /** Harness executable name inside the build directory. */
  readonly binary: string;
  buildTargets(options: CheckOptions): string[];
}

const LANES: Record<Lane, CheckLane> = {
  "checks": {
    binary: "porydaw_checks",
    // The application binary is only needed by the production-startup rows.
    buildTargets: (options) => {
      const productionStartupSelected = options.filters.length === 0
        ? !options.exclusions.includes("production-startup")
        : options.filters.some((filter) =>
          "production-startup".includes(filter)
        ) &&
          !options.exclusions.includes("production-startup");
      return [
        ...(productionStartupSelected ? ["porydaw"] : []),
        "porydaw_checks",
        "mid2agb",
      ];
    },
  },
  // The QML lanes are their own executables and manifests, not porydaw_checks
  // catalog rows; run_checks.ts still needs mid2agb beside the build.
  "checks:qml": {
    binary: "editor_qml_tests",
    buildTargets: () => ["editor_qml_tests", "mid2agb"],
  },
  // Mounts the production SwiftRollOverlay against a real ApplicationSession.
  "checks:qml-roll": {
    binary: "roll_qml_tests",
    buildTargets: () => ["roll_qml_tests", "mid2agb"],
  },
  "checks:shell": {
    binary: "shell_qml_tests",
    buildTargets: () => ["shell_qml_tests", "mid2agb"],
  },
};

// Inside a checks lane the guard only speaks when it fails.
async function runBridge(args: string[], quiet = false): Promise<void> {
  if (args.includes("--help")) showHelp("checks:bridge");
  const unknown = args.find((arg) =>
    arg !== "--update-baseline" && arg !== "--allow-growth"
  );
  if (unknown) usage("checks:bridge", `unknown argument ${unknown}`);
  if (args.includes("--allow-growth") && !args.includes("--update-baseline")) {
    usage("checks:bridge", "--allow-growth requires --update-baseline");
  }
  const update = args.includes("--update-baseline");
  if (
    update &&
    (await Deno.permissions.query({ name: "write", path: "tools" })).state !==
      "granted"
  ) {
    usage("checks:bridge", "baseline writes require deno task bridge:baseline");
  }
  const result = await new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read=src,CMakeLists.txt,cmake/QtBridge.cmake,tools",
      ...(update ? ["--allow-write=tools"] : []),
      "tools/qtbridge_surface.ts",
      ...args,
    ],
    stdout: quiet ? "piped" : "inherit",
    stderr: quiet ? "piped" : "inherit",
  }).output();
  if (result.success) return;
  if (quiet) {
    const decoder = new TextDecoder();
    console.error(
      (decoder.decode(result.stdout) + decoder.decode(result.stderr)).trimEnd(),
    );
  }
  Deno.exit(result.code);
}

async function runChecks(rawArgs: string[], command: Lane): Promise<void> {
  const lane = LANES[command];
  // Terminal --qt: everything after it is the Qt test payload and is never
  // parsed as a runner option. run_checks.ts parses the marker identically.
  const qtIndex = rawArgs.indexOf("--qt");
  const runnerArgs = qtIndex === -1 ? rawArgs : rawArgs.slice(0, qtIndex);
  const qtPayload = qtIndex === -1 ? undefined : rawArgs.slice(qtIndex + 1);
  const filters: string[] = [];
  const passthrough: string[] = [];
  let verbose = false;
  for (let i = 0; i < runnerArgs.length; i++) {
    const arg = runnerArgs[i];
    if (arg === "--verbose" || arg === "-v") {
      verbose = true;
    } else if (arg.startsWith("--filter=")) {
      filters.push(arg);
    } else if (arg === "--filter") {
      const next = runnerArgs[++i];
      if (!next || next.startsWith("-")) {
        usage(command, "--filter requires a value");
      }
      filters.push(`--filter=${next}`);
    } else if (arg === "--") {
      passthrough.push(...runnerArgs.slice(i + 1));
      break;
    } else {
      passthrough.push(arg);
    }
  }

  const args = [
    ...(verbose ? ["--reporter=verbose"] : []),
    ...filters,
    ...passthrough,
  ];
  if (qtPayload !== undefined) args.push("--qt", ...qtPayload);
  let options;
  try {
    options = parseCheckOptions(args);
  } catch (error) {
    usage(command, error instanceof Error ? error.message : String(error));
  }
  if (options.help) showHelp(command);
  await runBridge([], true);
  const directory = await runBuild(
    lane.buildTargets(options),
    Deno.build.os === "windows" ? "release" : "debug",
    true,
  );
  const executable = Deno.build.os === "windows"
    ? `${lane.binary}.exe`
    : lane.binary;
  const binary = join(
    directory,
    ...((Deno.build.os === "windows" && await usesMultiConfigBuild(directory))
      ? ["Release"]
      : []),
    executable,
  );
  const status = await new Deno.Command("deno", {
    args: [
      "run",
      "--allow-read",
      "--allow-write",
      "--allow-run",
      "--allow-env=ASAN_OPTIONS,DISPLAY,PORYDAW_SAMPLE_CORPUS,PORYDAW_CHECK_HOST",
      "tools/run_checks.ts",
      binary,
      ...args,
    ],
    stdout: "inherit",
    stderr: "inherit",
    stdin: "null",
  }).output();
  Deno.exit(status.code);
}

async function runFormat(args: string[]): Promise<void> {
  if (args.includes("--help")) showHelp("format");
  let check = false;
  let whole = false;
  let base = "HEAD";
  const files: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--check") check = true;
    else if (arg === "--whole") whole = true;
    else if (arg.startsWith("--base=")) base = arg.slice("--base=".length);
    else if (arg === "--base") {
      const next = args[++i];
      if (!next || next.startsWith("-")) {
        usage("format", "--base requires a ref");
      }
      base = next;
    } else if (arg.startsWith("-")) usage("format", `unknown argument ${arg}`);
    else files.push(arg);
  }
  if (!base) usage("format", "--base requires a ref");
  if (whole && files.length === 0) usage("format", "--whole requires files");
  try {
    Deno.exit(await formatSources({ check, base, files, whole }));
  } catch (error) {
    console.error(`format: ${error instanceof Error ? error.message : error}`);
    Deno.exit(2);
  }
}

const [command, ...rest] = Deno.args;
if (command === undefined) usage();
if (command === "--help") showHelp();
// The deno.json `build` alias exists so a bare `deno task build` prints this
// task list instead of Deno's raw task dump.
if (command === "build") usage();

switch (command) {
  case "build:app":
    await runBuild(["porydaw"], buildConfig(rest, command));
    break;
  case "build:render":
    await runBuild(["porydaw_render_cli"], buildConfig(rest, command));
    break;
  case "build:checks":
    await runBuild(
      ["porydaw", "porydaw_checks", "mid2agb"],
      buildConfig(rest, command),
      true,
    );
    break;
  case "checks":
  case "checks:qml":
  case "checks:qml-roll":
  case "checks:shell":
    await runChecks(rest, command);
    break;
  case "checks:bridge":
    await runBridge(rest);
    break;
  case "format":
    await runFormat(rest);
    break;
  default:
    usage(undefined, `unknown command ${command}`);
}
