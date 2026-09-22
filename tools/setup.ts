// Provision a fresh checkout for local Porydaw development.
// Deno itself must be installed before this script can run.

import { join } from "node:path";
import {
  aqtInstall,
  cmakeConfigureArgs,
  currentQtInstallation,
  localQtPrefix,
  type QtInstallation,
  qtInstallationDirectory,
  qtVersion,
  setupCacheDirectory,
  setupToolsetMarker,
  setupVirtualEnvironment,
  setupVirtualEnvironmentPython,
} from "./local_build_environment.ts";
import {
  ensureNativeBuildTools,
  inspectNativeBuildTools,
  type NativeBuildPython,
  nativeBuildToolsDryRunOutcome,
  NativeBuildToolsError,
} from "./native_build_tools.ts";
import { poryaaaaConfiguration } from "./poryaaaa_source.ts";
import { SetupProgress } from "./setup_reporter.ts";

const root = Deno.cwd();
const buildDirectory = "build";
const cacheDirectory = setupCacheDirectory(root);
const virtualEnvironment = setupVirtualEnvironment(root);
const toolsetMarker = setupToolsetMarker(root);

type Options = {
  dryRun: boolean;
};

type Toolset = {
  environmentPython: string;
  reused: boolean;
};

type LocalQt = {
  prefix: string;
  reused: boolean;
};

type Platform = {
  label: string;
  qt: QtInstallation;
  launchCommand: string;
};

function usage(message?: string): never {
  if (message) console.error(`setup: ${message}`);
  console.error(`usage: deno task setup [--dry-run]
  --dry-run  check installed native tools and print setup without provisioning
  --help     show this help`);
  Deno.exit(2);
}

function options(raw: string[]): Options {
  let dryRun = false;
  for (const argument of raw) {
    if (argument === "--") continue;
    if (argument === "--dry-run") {
      dryRun = true;
    } else if (argument === "--help") {
      usage();
    } else {
      usage(`unknown option ${argument}`);
    }
  }
  return { dryRun };
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

async function run(
  description: string,
  executable: string,
  args: string[],
): Promise<void> {
  try {
    const result = await new Deno.Command(executable, {
      args,
      cwd: root,
      stdin: "inherit",
      stdout: "inherit",
      stderr: "inherit",
    }).spawn().status;
    if (!result.success) {
      throw new Error(
        `${executable} ${args.join(" ")} failed (${result.code})`,
      );
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(`${description}: ${executable} is not installed`);
    }
    throw error;
  }
}

function platform(): Platform {
  const qt = currentQtInstallation();
  switch (Deno.build.os) {
    case "darwin":
      return {
        label: "macOS",
        qt,
        launchCommand: "open build/porydaw.app",
      };
    case "linux":
      return {
        label: qt.host === "linux_arm64" ? "Linux arm64" : "Linux x86_64",
        qt,
        launchCommand: "./build/porydaw",
      };
    case "windows":
      return {
        label: "Windows x86_64",
        qt,
        launchCommand: ".\\build\\Release\\porydaw.exe",
      };
    default:
      throw new Error(`unsupported platform ${Deno.build.os}`);
  }
}

async function requireProjectRoot(): Promise<void> {
  if (
    !(await exists(join(root, "CMakeLists.txt"))) ||
    !(await exists(join(root, "deno.json")))
  ) {
    throw new Error("run deno task setup from the Porydaw repository root");
  }
  const major = Number(Deno.version.deno.split(".")[0]);
  if (!Number.isFinite(major) || major < 2) {
    throw new Error(
      `Deno 2 or newer is required; found ${Deno.version.deno}. Install it: https://docs.deno.com/runtime/getting_started/installation/`,
    );
  }
}

async function ensureToolset(python: NativeBuildPython): Promise<Toolset> {
  await Deno.mkdir(cacheDirectory, { recursive: true });
  const environmentPython = setupVirtualEnvironmentPython(root);
  const expectedToolsetVersion =
    `aqtinstall=${aqtInstall}\nclang-format=22\npython=${python.version}\n`;
  const environmentExists = await exists(environmentPython);
  let currentMarker = "";
  try {
    currentMarker = await Deno.readTextFile(toolsetMarker);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const reused = environmentExists && currentMarker === expectedToolsetVersion;
  if (!reused) {
    if (await exists(virtualEnvironment)) {
      await Deno.remove(virtualEnvironment, { recursive: true });
    }
    await run(
      "creating the checkout-local Python environment",
      python.executable,
      [
        ...python.prefixArgs,
        "-m",
        "venv",
        virtualEnvironment,
      ],
    );
    await run("installing Qt and formatter setup tools", environmentPython, [
      "-m",
      "pip",
      "install",
      "--disable-pip-version-check",
      "--upgrade",
      aqtInstall,
      "clang-format==22.*",
    ]);
    await Deno.writeTextFile(toolsetMarker, expectedToolsetVersion);
  }
  return { environmentPython, reused };
}

async function ensureQt(
  environmentPython: string,
  target: Platform,
): Promise<LocalQt> {
  const installation = qtInstallationDirectory(root, target.qt);
  const existingPrefix = await localQtPrefix(root, target.qt);
  if (existingPrefix) return { prefix: existingPrefix, reused: true };
  await run(`downloading Qt ${qtVersion}.x`, environmentPython, [
    "-m",
    "aqt",
    "install-qt",
    "--outputdir",
    installation,
    target.qt.host,
    "desktop",
    qtVersion,
    target.qt.architecture,
  ]);
  const prefix = await localQtPrefix(root, target.qt);
  if (!prefix) {
    throw new Error("Qt installation did not provide Qt6Config.cmake");
  }
  return { prefix, reused: false };
}

async function configurePorydaw(
  cmake: string,
  qtPrefix: string,
): Promise<void> {
  const poryaaaa = await poryaaaaConfiguration(buildDirectory, root);
  const configureArgs = await cmakeConfigureArgs({
    buildDirectory,
    poryaaaaArgument: poryaaaa.cmakeArgument,
    qtPrefix,
    buildChecks: true,
    buildType: "Release",
  });
  await run("configuring Porydaw", cmake, configureArgs);
}

async function buildPorydaw(cmake: string): Promise<void> {
  const buildArguments = ["--build", buildDirectory];
  if (Deno.build.os === "windows") buildArguments.push("--config", "Release");
  buildArguments.push(
    "--target",
    "porydaw",
    "-j",
    String(navigator.hardwareConcurrency),
  );
  await run("building Porydaw", cmake, buildArguments);
}

const progress = new SetupProgress();

try {
  const parsed = options(Deno.args);
  await requireProjectRoot();
  const target = platform();
  if (parsed.dryRun) {
    const nativeTools = await inspectNativeBuildTools(buildDirectory);
    progress.printDryRun(target.label, {
      "native-tools": nativeBuildToolsDryRunOutcome(nativeTools),
    });
    if (nativeTools.incompatibilities.length > 0) {
      throw new NativeBuildToolsError(nativeTools.incompatibilities);
    }
  } else {
    const nativeTools = await progress.run(
      "native-tools",
      () => ensureNativeBuildTools(buildDirectory),
      ({ reused, installed }) =>
        reused
          ? "compatible installed tools"
          : `installed ${installed.join(", ")}`,
    );
    await progress.run("submodule", () =>
      run("initializing poryaaaa", "git", [
        "submodule",
        "update",
        "--init",
        "--recursive",
      ]));
    const toolset = await progress.run(
      "python-tools",
      () => ensureToolset(nativeTools.python),
      ({ reused }) => reused ? "reused .cache/setup-venv" : "done",
    );
    const qt = await progress.run(
      "qt",
      () => ensureQt(toolset.environmentPython, target),
      ({ reused }) => reused ? "reused .cache/setup/qt" : "downloaded",
    );
    await progress.run(
      "configure",
      () => configurePorydaw(nativeTools.cmake, qt.prefix),
    );
    await progress.run("build", () => buildPorydaw(nativeTools.cmake));
    progress.complete(target.launchCommand);
  }
} catch (error) {
  progress.fail(
    error,
    error instanceof NativeBuildToolsError ? "native-tools" : undefined,
  );
  Deno.exit(1);
}
