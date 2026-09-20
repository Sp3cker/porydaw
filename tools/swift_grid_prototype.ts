// Isolated build/run lane for the Swift/QtBridge piano-grid prototype.
// Builds only src/ui/songview/quick/swift-grid-prototype into
// build-swift-grid/ — never the production porydaw targets.
//
// usage: deno task prototype:swift-grid [
//     --build-only|--smoke|--widget-smoke|--widget-preview]
//   (default)         configure, build, then launch the app
//   --build-only      configure and build only
//   --smoke           configure, build, then run the native gesture smoke
//                     (PORYDAW_SWIFT_GRID_SMOKE=1); expects SWIFT_GRID_SMOKE PASS
//   --widget-smoke    configure, build, then run the native widget-interop
//                     smoke (PORYDAW_SWIFT_WIDGET_SMOKE=1); expects
//                     SWIFT_GRID_WIDGET_SMOKE PASS
//   --widget-preview  configure, build, then run the same widget automation
//                     with the app left open (PORYDAW_SWIFT_WIDGET_PREVIEW=1)

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

function cleanEnvironment(): Record<string, string> {
  const source = Deno.env.toObject();
  const result: Record<string, string> = {};
  const names = new Map<string, string>();
  for (const [name, value] of Object.entries(source)) {
    const folded = name.toLowerCase();
    const existing = names.get(folded);
    if (existing && name !== "PATH") continue;
    if (existing) delete result[existing];
    names.set(folded, name);
    result[name] = value;
  }
  return result;
}

async function swiftCompiler(): Promise<string | undefined> {
  if (Deno.build.os !== "windows") return undefined;
  const localAppData = Deno.env.get("LOCALAPPDATA");
  if (!localAppData) return undefined;
  const toolchains = join(localAppData, "Programs", "Swift", "Toolchains");
  const candidates: string[] = [];
  try {
    for await (const entry of Deno.readDir(toolchains)) {
      if (!entry.isDirectory) continue;
      const compiler = join(toolchains, entry.name, "usr", "bin", "swiftc.exe");
      if (await exists(compiler)) candidates.push(compiler);
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  return candidates.sort().at(-1);
}

async function swiftSdk(): Promise<string | undefined> {
  if (Deno.build.os !== "windows") return undefined;
  const localAppData = Deno.env.get("LOCALAPPDATA");
  if (!localAppData) return undefined;
  const platforms = join(localAppData, "Programs", "Swift", "Platforms");
  const candidates: string[] = [];
  try {
    for await (const entry of Deno.readDir(platforms)) {
      if (!entry.isDirectory) continue;
      const sdk = join(
        platforms,
        entry.name,
        "Windows.platform",
        "Developer",
        "SDKs",
        "Windows.sdk",
      );
      if (await exists(join(sdk, "SDKSettings.plist"))) candidates.push(sdk);
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  return candidates.sort().at(-1);
}

async function swiftRuntimeBin(): Promise<string | undefined> {
  if (Deno.build.os !== "windows") return undefined;
  const localAppData = Deno.env.get("LOCALAPPDATA");
  if (!localAppData) return undefined;
  const runtimes = join(localAppData, "Programs", "Swift", "Runtimes");
  const candidates: string[] = [];
  try {
    for await (const entry of Deno.readDir(runtimes)) {
      if (!entry.isDirectory) continue;
      const bin = join(runtimes, entry.name, "usr", "bin");
      if (await exists(join(bin, "swiftCore.dll"))) candidates.push(bin);
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  return candidates.sort().at(-1);
}

async function ninjaExecutable(): Promise<string | undefined> {
  if (Deno.build.os !== "windows") return undefined;
  const localAppData = Deno.env.get("LOCALAPPDATA");
  if (!localAppData) return undefined;
  const packages = join(localAppData, "Microsoft", "WinGet", "Packages");
  try {
    for await (const entry of Deno.readDir(packages)) {
      if (!entry.isDirectory || !entry.name.startsWith("Ninja-build.Ninja_")) {
        continue;
      }
      const executable = join(packages, entry.name, "ninja.exe");
      if (await exists(executable)) return executable;
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  return undefined;
}

async function buildEnvironment(
  swiftc: string | undefined,
  swiftRuntime: string | undefined,
): Promise<Record<string, string>> {
  const base = cleanEnvironment();
  if (Deno.build.os !== "windows") return base;

  const programFilesX86 = Object.entries(base).find(([name]) =>
    name.toLowerCase() === "programfiles(x86)"
  )?.[1];
  if (!programFilesX86) throw new Error("ProgramFiles(x86) is unavailable");
  const vswhere = join(
    programFilesX86,
    "Microsoft Visual Studio",
    "Installer",
    "vswhere.exe",
  );
  const installation = await new Deno.Command(vswhere, {
    args: [
      "-latest",
      "-products",
      "*",
      "-requires",
      "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
      "-property",
      "installationPath",
    ],
    env: base,
    clearEnv: true,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const installationPath = decoder.decode(installation.stdout).trim();
  if (!installation.success || !installationPath) {
    throw new Error("Visual Studio 2022 C++ tools are unavailable");
  }

  const developerCommand = join(
    installationPath,
    "Common7",
    "Tools",
    "Launch-VsDevShell.ps1",
  );
  const escapedDeveloperCommand = developerCommand.replaceAll("'", "''");
  const environmentScript =
    `& '${escapedDeveloperCommand}' -Arch amd64 -HostArch amd64 ` +
    "-SkipAutomaticLocation; $values = @{}; " +
    "[Environment]::GetEnvironmentVariables().GetEnumerator() | " +
    "ForEach-Object { $values[$_.Key] = $_.Value }; " +
    "$values | ConvertTo-Json -Compress";
  const result = await new Deno.Command("powershell.exe", {
    args: [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      environmentScript,
    ],
    env: base,
    clearEnv: true,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(
      decoder.decode(result.stderr).trim() ||
        "Visual Studio developer environment failed",
    );
  }

  const outputLines = decoder.decode(result.stdout).trim().split(/\r?\n/);
  const environmentLine = outputLines.findLast((line) => line.startsWith("{"));
  if (!environmentLine) {
    throw new Error(
      "Visual Studio developer environment produced no variables",
    );
  }
  const environment = JSON.parse(environmentLine) as Record<string, string>;
  const pathName =
    Object.keys(environment).find((name) => name.toLowerCase() === "path") ??
      "PATH";
  const swiftPaths = [swiftc ? dirname(swiftc) : undefined, swiftRuntime]
    .filter((path): path is string => path !== undefined);
  if (swiftPaths.length > 0) {
    environment[pathName] = `${swiftPaths.join(";")};${
      environment[pathName] ?? ""
    }`;
  }
  return environment;
}

function usage(): string {
  return `usage: deno task prototype:swift-grid [
    --build-only|--smoke|--widget-smoke|--widget-preview]
  build and launch the Swift/QtBridge piano-grid prototype
  --build-only      configure and build without launching
  --smoke           build, then run the native gesture smoke check
  --widget-smoke    build, then run the native widget-interop smoke check
  --widget-preview  build, then run the widget-interop preview (stays open)`;
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

async function sameFile(source: string, destination: string): Promise<boolean> {
  try {
    const [sourceInfo, destinationInfo] = await Promise.all([
      Deno.stat(source),
      Deno.stat(destination),
    ]);
    return sourceInfo.size === destinationInfo.size &&
      (destinationInfo.mtime?.getTime() ?? 0) >=
        (sourceInfo.mtime?.getTime() ?? 0);
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

async function poryaaaaDir(): Promise<string | undefined> {
  const candidates = [
    join(Deno.cwd(), "external", "poryaaaa", "packages", "poryaaaa"),
    join(
      (await mainWorktreeRoot()) ?? "",
      "external",
      "poryaaaa",
      "packages",
      "poryaaaa",
    ),
  ];
  for (const candidate of candidates) {
    if (await exists(join(candidate, "plugin", "porydaw", "CMakeLists.txt"))) {
      return candidate;
    }
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
async function configure(
  environment: Record<string, string>,
  swiftc: string | undefined,
  swiftSdkRoot: string | undefined,
  ninja: string | undefined,
): Promise<void> {
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
    ...(ninja ? [`-DCMAKE_MAKE_PROGRAM=${ninja}`] : []),
    ...(Deno.build.os === "windows"
      ? [
        "-DCMAKE_C_COMPILER=cl.exe",
        "-DCMAKE_CXX_COMPILER=cl.exe",
        ...(swiftc ? [`-DCMAKE_Swift_COMPILER=${swiftc}`] : []),
        ...(swiftSdkRoot ? [`-DCMAKE_Swift_FLAGS=-sdk ${swiftSdkRoot}`] : []),
      ]
      : []),
    ...(qtPrefix ? [`-DCMAKE_PREFIX_PATH=${qtPrefix}`] : []),
    // The worktree ships without the poryaaaa submodule checkout; resolve it
    // from the main checkout so the audio session can link the engine.
    ...(await poryaaaaDir().then((dir) =>
      dir ? [`-DPORYAAAA_DIR=${dir}`] : []
    )),
  ];
  // Streamed so a long first-time configure (QtBridge fetch) shows progress
  // instead of looking stuck.
  const result = await new Deno.Command("cmake", {
    args,
    env: environment,
    clearEnv: Deno.build.os === "windows",
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) {
    console.error(
      "prototype:swift-grid: configure failed " +
        "(needs cmake, ninja, Swift 6.4+, and Qt 6.10+ on PATH or a local install)",
    );
    Deno.exit(result.code || 1);
  }
}

async function build(
  environment: Record<string, string>,
  swiftc: string | undefined,
  swiftSdkRoot: string | undefined,
  ninja: string | undefined,
): Promise<void> {
  await configure(environment, swiftc, swiftSdkRoot, ninja);
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
    env: environment,
    clearEnv: Deno.build.os === "windows",
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!result.success) {
    console.error("prototype:swift-grid: build failed");
    Deno.exit(result.code || 1);
  }
}

async function deployWindowsRuntime(
  environment: Record<string, string>,
  qtPrefix: string | undefined,
  swiftRuntime: string | undefined,
): Promise<void> {
  if (Deno.build.os !== "windows") return;
  if (!qtPrefix) throw new Error("local Qt runtime is unavailable");
  if (!swiftRuntime) throw new Error("Swift runtime is unavailable");

  const qtCoreSource = join(qtPrefix, "bin", "Qt6Core.dll");
  const qtCoreDestination = join(BUILD_DIR, "Qt6Core.dll");
  const windowsPlugin = join(BUILD_DIR, "platforms", "qwindows.dll");
  if (
    !(await sameFile(qtCoreSource, qtCoreDestination)) ||
    !(await exists(windowsPlugin))
  ) {
    console.log("prototype:swift-grid: deploy Qt runtime");
    const result = await new Deno.Command(
      join(qtPrefix, "bin", "windeployqt.exe"),
      {
        args: [
          "--release",
          "--no-translations",
          "--qmldir",
          SOURCE_DIR,
          executablePath(),
        ],
        env: environment,
        clearEnv: true,
        stdout: "inherit",
        stderr: "inherit",
      },
    ).output();
    if (!result.success) throw new Error("windeployqt failed");
  }

  for await (const entry of Deno.readDir(swiftRuntime)) {
    if (!entry.isFile || !entry.name.toLowerCase().endsWith(".dll")) continue;
    const source = join(swiftRuntime, entry.name);
    const destination = join(BUILD_DIR, entry.name);
    if (!(await sameFile(source, destination))) {
      await Deno.copyFile(source, destination);
    }
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
    clearEnv: Deno.build.os === "windows",
    stdout: "inherit",
    stderr: "inherit",
    stdin: "inherit",
  }).spawn();
  return (await child.status).code;
}

// Runs the app under a bounded smoke environment, captures its output, and
// requires the exact pass marker before reporting success.
async function runBoundedSmoke(
  environment: Record<string, string>,
  variable: string,
  marker: string,
  label: string,
): Promise<void> {
  const binary = executablePath();
  if (!(await exists(binary))) {
    console.error(`prototype:swift-grid: missing binary ${binary}`);
    Deno.exit(1);
  }
  console.log(`prototype:swift-grid: ${label}`);
  const child = new Deno.Command(binary, {
    env: {
      ...environment,
      [variable]: "1",
      PORYDAW_AUDIO_BACKEND: "null",
    },
    clearEnv: Deno.build.os === "windows",
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
  if (!result.success || !combined.includes(marker)) {
    console.error(`prototype:swift-grid: ${label} failed`);
    Deno.exit(1);
  }
  console.log(`prototype:swift-grid: ${label} ok`);
}

async function runSmoke(environment: Record<string, string>): Promise<void> {
  await runBoundedSmoke(
    environment,
    "PORYDAW_SWIFT_GRID_SMOKE",
    "SWIFT_GRID_SMOKE PASS",
    "smoke",
  );
}

async function runWidgetSmoke(
  environment: Record<string, string>,
): Promise<void> {
  await runBoundedSmoke(
    environment,
    "PORYDAW_SWIFT_WIDGET_SMOKE",
    "SWIFT_GRID_WIDGET_SMOKE PASS",
    "widget smoke",
  );
}

// The preview runs the same widget automation but keeps the app open with the
// outcomes visible, so output and input stay attached to the terminal.
function runWidgetPreview(environment: Record<string, string>): Promise<void> {
  console.log("prototype:swift-grid: widget preview");
  return runApp({
    ...environment,
    PORYDAW_SWIFT_WIDGET_PREVIEW: "1",
    PORYDAW_AUDIO_BACKEND: "null",
  }).then((code) => Deno.exit(code));
}

const MODE_FLAGS = [
  "--build-only",
  "--smoke",
  "--widget-smoke",
  "--widget-preview",
];

const args = Deno.args;
if (args.includes("--help") || args.includes("-h")) {
  console.log(usage());
  Deno.exit(0);
}
const modes = MODE_FLAGS.filter((flag) => args.includes(flag));
const unknown = args.filter((arg) => !MODE_FLAGS.includes(arg));
const mode = modes.at(0);
// The modes are mutually exclusive; repeating the same flag is harmless.
const conflicting = modes.some((flag) => flag !== mode);
if (unknown.length > 0 || conflicting) {
  console.error(usage());
  Deno.exit(2);
}

const swiftc = await swiftCompiler();
const swiftSdkRoot = await swiftSdk();
const swiftRuntime = await swiftRuntimeBin();
const ninja = await ninjaExecutable();
const environment = await buildEnvironment(swiftc, swiftRuntime);
const qtPrefix = await resolveQtPrefix();
if (Deno.build.os === "windows") {
  if (qtPrefix) {
    const pathName = Object.keys(environment).find((name) =>
      name.toLowerCase() === "path"
    ) ?? "PATH";
    environment[pathName] = `${join(qtPrefix, "bin")};${
      environment[pathName] ?? ""
    }`;
  }
}
await build(environment, swiftc, swiftSdkRoot, ninja);
await deployWindowsRuntime(environment, qtPrefix, swiftRuntime);
if (mode === "--build-only") {
  console.log("prototype:swift-grid: build ok");
} else if (mode === "--smoke") {
  await runSmoke(environment);
} else if (mode === "--widget-smoke") {
  await runWidgetSmoke(environment);
} else if (mode === "--widget-preview") {
  await runWidgetPreview(environment);
} else {
  console.log("prototype:swift-grid: launch");
  Deno.exit(await runApp(environment));
}
