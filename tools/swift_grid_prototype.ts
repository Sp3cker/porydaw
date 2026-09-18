// Isolated build/run lane for the Swift/QtBridge piano-grid prototype.
// Builds only src/ui/songview/quick/swift-grid-prototype into
// build-swift-grid/ — never the production porydaw targets.
//
// usage: deno task prototype:swift-grid [--build-only|--smoke]
//   (default)   configure, build, then launch the app
//   --build-only  configure and build only
//   --smoke       configure, build, then run the native gesture smoke
//                 (PORYDAW_SWIFT_GRID_SMOKE=1); expects SWIFT_GRID_SMOKE PASS

import { dirname, join } from "node:path";
import { localQtPrefix } from "./local_build_environment.ts";

const BUILD_DIR = "build-swift-grid";
const SOURCE_DIR = join(
  "src",
  "ui",
  "songview",
  "quick",
  "swift-grid-prototype",
);
const TARGET = "swift_grid_prototype";
const SMOKE_TIMEOUT_MS = 60_000;

const decoder = new TextDecoder();

function usage(): string {
  return `usage: deno task prototype:swift-grid [--build-only|--smoke]
  build and launch the Swift/QtBridge piano-grid prototype
  --build-only  configure and build without launching
  --smoke       build, then run the native gesture smoke check`;
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

async function mainWorktreeRoot(): Promise<string | undefined> {
  // In a linked worktree the common git dir lives in the main checkout, so
  // its parent is the main worktree root. In the main checkout itself the
  // common dir is just ./.git.
  const result = await new Deno.Command("git", {
    args: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
    stdout: "piped",
    stderr: "null",
  }).output();
  if (!result.success) return undefined;
  const commonDir = decoder.decode(result.stdout).trim();
  return commonDir ? dirname(commonDir) : undefined;
}

async function resolveQtPrefix(): Promise<string | undefined> {
  // Prefer this checkout's local install, then the main worktree's (a
  // worktree shares the main checkout's .cache/setup/qt installation).
  const local = await localQtPrefix();
  if (local) return local;
  const mainRoot = await mainWorktreeRoot();
  if (mainRoot && mainRoot !== Deno.cwd()) {
    return await localQtPrefix(mainRoot);
  }
  return undefined;
}

function executablePath(): string {
  switch (Deno.build.os) {
    case "darwin":
      return join(
        BUILD_DIR,
        `${TARGET}.app`,
        "Contents",
        "MacOS",
        TARGET,
      );
    case "windows":
      return join(BUILD_DIR, `${TARGET}.exe`);
    default:
      return join(BUILD_DIR, TARGET);
  }
}

async function configure(): Promise<void> {
  console.log("prototype:swift-grid: configure");
  const qtPrefix = await resolveQtPrefix();
  const args = [
    "-S",
    SOURCE_DIR,
    "-B",
    BUILD_DIR,
    "-G",
    "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    ...(qtPrefix ? [`-DCMAKE_PREFIX_PATH=${qtPrefix}`] : []),
  ];
  // Streamed so a long first-time configure (QtBridge fetch) shows progress
  // instead of looking stuck.
  const result = await new Deno.Command("cmake", {
    args,
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) {
    console.error(
      "prototype:swift-grid: configure failed " +
        "(needs cmake, ninja, Swift 6.2+, and Qt 6.10+ on PATH or a local install)",
    );
    Deno.exit(result.code || 1);
  }
}

async function build(): Promise<void> {
  await configure();
  console.log("prototype:swift-grid: build");
  const result = await new Deno.Command("cmake", {
    args: [
      "--build",
      BUILD_DIR,
      "-j",
      String(navigator.hardwareConcurrency),
      "--target",
      TARGET,
    ],
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) {
    console.error("prototype:swift-grid: build failed");
    Deno.exit(result.code || 1);
  }
}

async function runApp(env: Record<string, string>): Promise<number> {
  const binary = executablePath();
  if (!(await exists(binary))) {
    console.error(`prototype:swift-grid: missing binary ${binary}`);
    return 1;
  }
  const child = new Deno.Command(binary, {
    env,
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
  }).spawn();
  return (await child.status).code;
}

async function runSmoke(): Promise<void> {
  const binary = executablePath();
  if (!(await exists(binary))) {
    console.error(`prototype:swift-grid: missing binary ${binary}`);
    Deno.exit(1);
  }
  console.log("prototype:swift-grid: smoke");
  const child = new Deno.Command(binary, {
    env: { PORYDAW_SWIFT_GRID_SMOKE: "1" },
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const timeout = setTimeout(() => {
    try {
      child.kill("SIGKILL");
    } catch { /* already exited */ }
  }, SMOKE_TIMEOUT_MS);
  const result = await child.output();
  clearTimeout(timeout);
  const combined = decoder.decode(result.stdout) +
    decoder.decode(result.stderr);
  console.log(combined);
  if (!result.success || !combined.includes("SWIFT_GRID_SMOKE PASS")) {
    console.error("prototype:swift-grid: smoke failed");
    Deno.exit(result.success ? 1 : result.code || 1);
  }
  console.log("prototype:swift-grid: smoke ok");
}

const args = Deno.args;
if (args.includes("--help") || args.includes("-h")) {
  console.log(usage());
  Deno.exit(0);
}
const buildOnly = args.includes("--build-only");
const smoke = args.includes("--smoke");
const unknown = args.filter((a) => a !== "--build-only" && a !== "--smoke");
if (unknown.length > 0 || (buildOnly && smoke)) {
  console.error(usage());
  Deno.exit(2);
}

await build();
if (buildOnly) {
  console.log("prototype:swift-grid: build ok");
} else if (smoke) {
  await runSmoke();
} else {
  console.log("prototype:swift-grid: launch");
  Deno.exit(await runApp({}));
}
