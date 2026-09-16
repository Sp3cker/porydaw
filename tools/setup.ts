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
import { poryaaaaConfiguration } from "./poryaaaa_source.ts";
import { SetupProgress } from "./setup_reporter.ts";

const root = Deno.cwd();
const buildDirectory = "build";
const cacheDirectory = setupCacheDirectory(root);
const virtualEnvironment = setupVirtualEnvironment(root);
const toolsetMarker = setupToolsetMarker(root);
const toolsetVersion = `aqtinstall=${aqtInstall}\nclang-format=22\n`;
const decoder = new TextDecoder();

type Options = {
  dryRun: boolean;
};

type Python = {
  executable: string;
  prefixArgs: string[];
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
  installTools: () => Promise<void>;
};

function usage(message?: string): never {
  if (message) console.error(`setup: ${message}`);
  console.error(`usage: deno task setup [--dry-run]
  --dry-run  print the selected platform setup without changing the machine
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

async function commandAvailable(
  executable: string,
  args = ["--version"],
): Promise<boolean> {
  try {
    return (await new Deno.Command(executable, {
      args,
      stdout: "null",
      stderr: "null",
    }).output()).success;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function capture(executable: string, args: string[]): Promise<string> {
  try {
    const result = await new Deno.Command(executable, {
      args,
      cwd: root,
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!result.success) {
      const detail = decoder.decode(result.stderr).trim();
      throw new Error(detail || `${executable} ${args.join(" ")} failed`);
    }
    return decoder.decode(result.stdout).trim();
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(`${executable} is not installed`);
    }
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
        installTools: installMacosTools,
      };
    case "linux":
      return {
        label: qt.host === "linux_arm64" ? "Linux arm64" : "Linux x86_64",
        qt,
        launchCommand: "./build/porydaw",
        installTools: installLinuxTools,
      };
    case "windows":
      return {
        label: "Windows x86_64",
        qt,
        launchCommand: ".\\build\\Release\\porydaw.exe",
        installTools: installWindowsTools,
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

async function installMacosTools(): Promise<void> {
  if (!(await commandAvailable("brew"))) {
    throw new Error("Homebrew is required on macOS: https://brew.sh/");
  }
  if (!(await commandAvailable("xcode-select", ["-p"]))) {
    await run(
      "requesting Xcode Command Line Tools",
      "xcode-select",
      ["--install"],
    );
    throw new Error(
      "finish the Xcode Command Line Tools installation, then rerun setup",
    );
  }
  await run(
    "installing macOS build tools",
    "brew",
    ["install", "cmake", "ninja", "python"],
  );
}

async function installLinuxTools(): Promise<void> {
  if (await commandAvailable("apt-get")) {
    await run("refreshing APT metadata", "sudo", ["apt-get", "update"]);
    await run("installing Debian/Ubuntu build tools", "sudo", [
      "apt-get",
      "install",
      "-y",
      "--no-install-recommends",
      "build-essential",
      "cmake",
      "ninja-build",
      "python3",
      "python3-venv",
    ]);
    return;
  }
  if (await commandAvailable("pacman")) {
    await run("installing Arch build tools", "sudo", [
      "pacman",
      "-S",
      "--needed",
      "base-devel",
      "cmake",
      "ninja",
      "python",
    ]);
    return;
  }
  if (await commandAvailable("dnf")) {
    await run("installing Fedora build tools", "sudo", [
      "dnf",
      "install",
      "-y",
      "gcc-c++",
      "cmake",
      "ninja-build",
      "python3",
      "python3-pip",
    ]);
    return;
  }
  throw new Error(
    "unsupported Linux package manager; supported: apt-get, pacman, dnf",
  );
}

async function installWindowsTools(): Promise<void> {
  if (!(await commandAvailable("winget"))) {
    throw new Error(
      "WinGet is required on Windows; install App Installer and rerun setup",
    );
  }
  const agreements = [
    "--accept-source-agreements",
    "--accept-package-agreements",
  ];
  await run("installing CMake", "winget", [
    "install",
    "--exact",
    "--id",
    "Kitware.CMake",
    ...agreements,
  ]);
  await run("installing Python", "winget", [
    "install",
    "--exact",
    "--id",
    "Python.Python.3.12",
    ...agreements,
  ]);
  await run("installing Visual Studio Build Tools", "winget", [
    "install",
    "--exact",
    "--id",
    "Microsoft.VisualStudio.2022.BuildTools",
    "--override",
    "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended",
    ...agreements,
  ]);
}

async function firstPython(candidates: Python[]): Promise<Python | undefined> {
  for (const candidate of candidates) {
    if (
      await commandAvailable(candidate.executable, [
        ...candidate.prefixArgs,
        "--version",
      ])
    ) {
      return candidate;
    }
  }
  return undefined;
}

async function windowsPython(): Promise<Python | undefined> {
  const localAppData = Deno.env.get("LOCALAPPDATA");
  if (!localAppData) return undefined;
  const installations = join(localAppData, "Programs", "Python");
  let entries: Deno.DirEntry[] = [];
  try {
    for await (const entry of Deno.readDir(installations)) entries.push(entry);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  entries = entries.filter((entry) => entry.isDirectory).sort((left, right) =>
    right.name.localeCompare(left.name, undefined, { numeric: true })
  );
  for (const entry of entries) {
    const executable = join(installations, entry.name, "python.exe");
    if (await exists(executable)) return { executable, prefixArgs: [] };
  }
  return undefined;
}

async function resolvePython(): Promise<Python> {
  const direct = await firstPython(
    Deno.build.os === "windows"
      ? [
        { executable: "python", prefixArgs: [] },
        { executable: "py", prefixArgs: ["-3"] },
      ]
      : [{ executable: "python3", prefixArgs: [] }],
  );
  if (direct) return direct;
  if (Deno.build.os === "windows") {
    const discovered = await windowsPython();
    if (discovered) return discovered;
  }
  throw new Error(
    "Python was installed but is not available; restart the terminal and rerun setup",
  );
}

async function ensureToolset(): Promise<Toolset> {
  await Deno.mkdir(cacheDirectory, { recursive: true });
  const python = await resolvePython();
  const environmentPython = setupVirtualEnvironmentPython(root);
  const environmentExists = await exists(environmentPython);
  if (!environmentExists) {
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
  }
  let currentMarker = "";
  try {
    currentMarker = await Deno.readTextFile(toolsetMarker);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const toolsCurrent = currentMarker === toolsetVersion;
  if (!toolsCurrent) {
    await run("installing Qt and formatter setup tools", environmentPython, [
      "-m",
      "pip",
      "install",
      "--disable-pip-version-check",
      "--upgrade",
      aqtInstall,
      "clang-format==22.*",
    ]);
    await Deno.writeTextFile(toolsetMarker, toolsetVersion);
  }
  return {
    environmentPython,
    reused: environmentExists && toolsCurrent,
  };
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

async function cmakeExecutable(): Promise<string> {
  const candidates = ["cmake"];
  if (Deno.build.os === "windows") {
    const programFiles = Deno.env.get("ProgramFiles");
    if (programFiles) {
      candidates.push(join(programFiles, "CMake", "bin", "cmake.exe"));
    }
  }
  for (const candidate of candidates) {
    if (await commandAvailable(candidate)) return candidate;
  }
  throw new Error(
    "CMake was installed but is not available; restart the terminal and rerun setup",
  );
}

async function requireCmake24(cmake: string): Promise<void> {
  const version = await capture(cmake, ["--version"]);
  const match = /cmake version (\d+)\.(\d+)/.exec(version);
  if (!match) {
    throw new Error(`could not determine the CMake version: ${version}`);
  }
  const major = Number(match[1]);
  const minor = Number(match[2]);
  if (major < 3 || (major === 3 && minor < 24)) {
    throw new Error(`CMake 3.24 or newer is required; found ${match[0]}`);
  }
}

async function configurePorydaw(qtPrefix: string): Promise<string> {
  const cmake = await cmakeExecutable();
  await requireCmake24(cmake);
  const poryaaaa = await poryaaaaConfiguration(buildDirectory, root);
  const configureArgs = await cmakeConfigureArgs({
    buildDirectory,
    poryaaaaArgument: poryaaaa.cmakeArgument,
    qtPrefix,
    buildChecks: true,
  });
  await run("configuring Porydaw", cmake, configureArgs);
  return cmake;
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
    progress.printDryRun(target.label);
  } else {
    await progress.run("submodule", () =>
      run("initializing poryaaaa", "git", [
        "submodule",
        "update",
        "--init",
        "--recursive",
      ]));
    await progress.run("native-tools", () => target.installTools());
    const toolset = await progress.run(
      "python-tools",
      ensureToolset,
      ({ reused }) => reused ? "reused .cache/setup-venv" : "done",
    );
    const qt = await progress.run(
      "qt",
      () => ensureQt(toolset.environmentPython, target),
      ({ reused }) => reused ? "reused .cache/setup/qt" : "downloaded",
    );
    const cmake = await progress.run(
      "configure",
      () => configurePorydaw(qt.prefix),
    );
    await progress.run("build", () => buildPorydaw(cmake));
    progress.complete(target.launchCommand);
  }
} catch (error) {
  progress.fail(error);
  Deno.exit(1);
}
