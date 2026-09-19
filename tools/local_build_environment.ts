import { join } from "node:path";

export const qtVersion = "6.11";
// Qt 6.11's Windows repository layout needs this post-3.3 aqtinstall revision.
export const aqtInstall =
  "git+https://github.com/miurahr/aqtinstall.git@076e1659807d0b362a3ed684d54c2e9c775eb9c7";

export type QtInstallation = {
  host: string;
  architecture: string;
};

type CmakeConfigureOptions = {
  buildDirectory: string;
  poryaaaaArgument: string;
  qtPrefix?: string;
  buildChecks?: boolean;
};

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

export function currentQtInstallation(): QtInstallation {
  switch (Deno.build.os) {
    case "darwin":
      return { host: "mac", architecture: "clang_64" };
    case "linux":
      if (Deno.build.arch === "x86_64") {
        return { host: "linux", architecture: "gcc_64" };
      }
      if (Deno.build.arch === "aarch64") {
        return { host: "linux_arm64", architecture: "linux_gcc_arm64" };
      }
      throw new Error(`unsupported Linux architecture ${Deno.build.arch}`);
    case "windows":
      if (Deno.build.arch !== "x86_64") {
        throw new Error(`unsupported Windows architecture ${Deno.build.arch}`);
      }
      return { host: "windows", architecture: "win64_msvc2022_64" };
    default:
      throw new Error(`unsupported platform ${Deno.build.os}`);
  }
}

export function setupCacheDirectory(root = Deno.cwd()): string {
  return join(root, ".cache", "setup");
}

export function setupVirtualEnvironment(root = Deno.cwd()): string {
  return join(root, ".cache", "setup-venv");
}

export function setupToolsetMarker(root = Deno.cwd()): string {
  return join(setupVirtualEnvironment(root), ".porydaw-toolset-version");
}

export function setupVirtualEnvironmentPython(root = Deno.cwd()): string {
  return Deno.build.os === "windows"
    ? join(setupVirtualEnvironment(root), "Scripts", "python.exe")
    : join(setupVirtualEnvironment(root), "bin", "python");
}

export function setupClangFormat(root = Deno.cwd()): string {
  return Deno.build.os === "windows"
    ? join(setupVirtualEnvironment(root), "Scripts", "clang-format.exe")
    : join(setupVirtualEnvironment(root), "bin", "clang-format");
}

export function qtInstallationDirectory(
  root: string,
  installation: QtInstallation,
): string {
  return join(
    setupCacheDirectory(root),
    "qt",
    `${installation.host}-${installation.architecture}`,
  );
}

function isRequestedQtVersion(version: string): boolean {
  return version === qtVersion || version.startsWith(`${qtVersion}.`);
}

function qtConfig(prefix: string): string {
  return join(prefix, "lib", "cmake", "Qt6", "Qt6Config.cmake");
}

export async function localQtPrefix(
  root = Deno.cwd(),
  installation = currentQtInstallation(),
): Promise<string | undefined> {
  const directory = qtInstallationDirectory(root, installation);
  // aqt's Windows architecture name includes a win64_ prefix, but the
  // extracted kit directory does not.
  const kitDirectory = installation.host === "windows"
    ? "msvc2022_64"
    : installation.architecture;
  try {
    for await (const version of Deno.readDir(directory)) {
      if (!version.isDirectory || !isRequestedQtVersion(version.name)) continue;
      const prefix = join(directory, version.name, kitDirectory);
      if (await exists(qtConfig(prefix))) return prefix;
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  return undefined;
}

// Bind the Swift compiler to the swiftly-managed toolchain named by
// .swift-version when one is installed. CMake's Apple Swift discovery goes
// through `xcrun --find swiftc`, which ignores PATH, so the swiftly shim
// never wins without an explicit -D. Returns nothing on platforms or
// checkouts without swiftly so other hosts are unaffected.
export async function swiftToolchainArgument(
  root = Deno.cwd(),
): Promise<string | undefined> {
  if (Deno.build.os !== "darwin") return undefined;
  let version: string;
  try {
    version = (await Deno.readTextFile(join(root, ".swift-version"))).trim();
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
  if (!version) return undefined;
  const home = Deno.env.get("HOME");
  if (!home) return undefined;
  let inUse: string | undefined;
  try {
    const config = JSON.parse(
      await Deno.readTextFile(join(home, ".swiftly", "config.json")),
    );
    inUse = typeof config?.inUse === "string" ? config.inUse : undefined;
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  if (inUse !== undefined && inUse !== version) {
    throw new Error(
      `swiftly in-use toolchain ${inUse} does not match pinned .swift-version ${version}; run: swiftly use ${version}`,
    );
  }
  const compiler = join(home, ".swiftly", "bin", "swiftc");
  if (!(await exists(compiler))) return undefined;
  return `-DCMAKE_Swift_COMPILER=${compiler}`;
}

function defaultGeneratorArguments(): string[] {
  return currentQtInstallation().host === "windows"
    ? ["-G", "Visual Studio 17 2022", "-A", "x64"]
    : ["-G", "Ninja"];
}

export async function cmakeBuildUsesNinja(
  buildDirectory: string,
): Promise<boolean> {
  const cache = join(buildDirectory, "CMakeCache.txt");
  if (!(await exists(cache))) {
    return currentQtInstallation().host !== "windows";
  }
  const content = await Deno.readTextFile(cache);
  const generator = /^CMAKE_GENERATOR:INTERNAL=(.+)$/m.exec(content)?.[1];
  return generator?.startsWith("Ninja") ?? false;
}

export async function cmakeConfigureArgs({
  buildDirectory,
  poryaaaaArgument,
  qtPrefix,
  buildChecks,
}: CmakeConfigureOptions): Promise<string[]> {
  const generatorArguments =
    await exists(join(buildDirectory, "CMakeCache.txt"))
      ? []
      : defaultGeneratorArguments();
  const swiftToolchain = await swiftToolchainArgument();
  return [
    "-S",
    ".",
    "-B",
    buildDirectory,
    ...generatorArguments,
    "-DCMAKE_BUILD_TYPE=Release",
    ...(buildChecks === undefined
      ? []
      : [`-DPORYDAW_BUILD_CHECKS=${buildChecks ? "ON" : "OFF"}`]),
    ...(qtPrefix ? [`-DCMAKE_PREFIX_PATH=${qtPrefix}`] : []),
    ...(swiftToolchain ? [swiftToolchain] : []),
    poryaaaaArgument,
  ];
}
