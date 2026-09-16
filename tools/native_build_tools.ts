import { join } from "node:path";
import { cmakeBuildUsesNinja } from "./local_build_environment.ts";
import { installMissingNativeBuildTools } from "./native_build_tool_installers.ts";

const decoder = new TextDecoder();
const minimumCmake = [3, 24] as const;
const minimumPython = [3, 10] as const;

const cxx20ProbeProject = `cmake_minimum_required(VERSION 3.24)
project(porydaw_cxx20_probe LANGUAGES C CXX)
file(WRITE "\${CMAKE_BINARY_DIR}/cxx20.cpp" "#include <concepts>\\n\\ntemplate <std::integral T> constexpr T twice(T value) { return value + value; }\\n\\nint main() { return twice(21) == 42 ? 0 : 1; }\\n")
try_compile(
  PORYDAW_CXX20
  "\${CMAKE_BINARY_DIR}/cxx20-build"
  SOURCES "\${CMAKE_BINARY_DIR}/cxx20.cpp"
  CMAKE_FLAGS
    "-DCMAKE_CXX_STANDARD=20"
    "-DCMAKE_CXX_STANDARD_REQUIRED=ON"
)
if(NOT PORYDAW_CXX20)
  message(FATAL_ERROR "The selected C++ compiler cannot compile C++20.")
endif()
`;

export type NativeBuildDependency =
  | "compiler"
  | "cmake"
  | "ninja"
  | "python"
  | "python-pip"
  | "python-venv";

export type NativeBuildPython = {
  executable: string;
  prefixArgs: string[];
  version: string;
};

export type NativeBuildToolsCheck = {
  cmake?: string;
  python?: NativeBuildPython;
  missing: NativeBuildDependency[];
  incompatibilities: string[];
};

export type NativeBuildTools = {
  cmake: string;
  python: NativeBuildPython;
  reused: boolean;
  installed: string[];
};

type CommandResult = {
  success: boolean;
  output: string;
};

type Version = readonly [number, number];

type PythonCheck = {
  python?: NativeBuildPython;
  missing?: NativeBuildDependency[];
  incompatibility?: string;
};

type PythonCandidate = Pick<NativeBuildPython, "executable" | "prefixArgs">;

export class NativeBuildToolsError extends Error {
  constructor(incompatibilities: readonly string[]) {
    super(
      [
        "installed native build tools are incompatible:",
        ...incompatibilities.map((incompatibility) => `- ${incompatibility}`),
        "setup does not update installed dependencies. Install compatible versions, then rerun setup.",
      ].join("\n"),
    );
  }
}

function dependencyLabel(dependency: NativeBuildDependency): string {
  switch (dependency) {
    case "compiler":
      return "a C and C++20 compiler";
    case "cmake":
      return "CMake";
    case "ninja":
      return "Ninja";
    case "python":
      return "Python 3.10 or newer";
    case "python-pip":
      return "the Python pip module";
    case "python-venv":
      return "the Python venv module";
  }
}

function versionAtLeast(version: Version, minimum: Version): boolean {
  return version[0] > minimum[0] ||
    (version[0] === minimum[0] && version[1] >= minimum[1]);
}

function versionFrom(output: string): Version | undefined {
  const match = /(\d+)\.(\d+)/.exec(output);
  if (!match) return undefined;
  return [Number(match[1]), Number(match[2])];
}

function firstLine(output: string): string {
  return output.split("\n").find((line) => line.trim())?.trim() ||
    "unrecognized version";
}

function probeFailure(output: string): string {
  return output.trim().split("\n").slice(-8).join("\n").trim() ||
    "CMake could not configure the C++20 probe";
}

async function commandResult(
  executable: string,
  args: string[],
): Promise<CommandResult> {
  try {
    const result = await new Deno.Command(executable, {
      args,
      stdout: "piped",
      stderr: "piped",
    }).output();
    const stdout = decoder.decode(result.stdout).trim();
    const stderr = decoder.decode(result.stderr).trim();
    return { success: result.success, output: stdout || stderr };
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return { success: false, output: "" };
    }
    throw error;
  }
}

async function commandAvailable(
  executable: string,
  args = ["--version"],
): Promise<boolean> {
  return (await commandResult(executable, args)).success;
}

function cmakeCandidates(): string[] {
  const candidates = ["cmake"];
  if (Deno.build.os === "windows") {
    const programFiles = Deno.env.get("ProgramFiles");
    if (programFiles) {
      candidates.push(join(programFiles, "CMake", "bin", "cmake.exe"));
    }
  }
  return candidates;
}

async function compatibleCmake(): Promise<
  { executable?: string; incompatibility?: string }
> {
  const foundVersions: string[] = [];
  for (const executable of cmakeCandidates()) {
    const result = await commandResult(executable, ["--version"]);
    if (!result.success) continue;
    const version = versionFrom(result.output);
    if (!version || !versionAtLeast(version, minimumCmake)) {
      foundVersions.push(firstLine(result.output));
      continue;
    }
    return { executable };
  }
  return foundVersions.length > 0
    ? {
      incompatibility: `CMake 3.24 or newer is required; found ${
        foundVersions.join(", ")
      }`,
    }
    : {};
}

async function windowsPythonCandidates(): Promise<PythonCandidate[]> {
  const localAppData = Deno.env.get("LOCALAPPDATA");
  if (!localAppData) return [];
  const installations = join(localAppData, "Programs", "Python");
  const candidates: PythonCandidate[] = [];
  try {
    for await (const entry of Deno.readDir(installations)) {
      if (!entry.isDirectory) continue;
      candidates.push({
        executable: join(installations, entry.name, "python.exe"),
        prefixArgs: [],
      });
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }
  return candidates.sort((left, right) =>
    right.executable.localeCompare(left.executable, undefined, {
      numeric: true,
    })
  );
}

async function pythonCandidates(): Promise<PythonCandidate[]> {
  const candidates = Deno.build.os === "windows"
    ? [
      { executable: "python", prefixArgs: [] },
      { executable: "py", prefixArgs: ["-3"] },
      ...(await windowsPythonCandidates()),
    ]
    : [
      { executable: "python3.13", prefixArgs: [] },
      { executable: "python3.12", prefixArgs: [] },
      { executable: "python3.11", prefixArgs: [] },
      { executable: "python3.10", prefixArgs: [] },
      { executable: "python3", prefixArgs: [] },
    ];
  const seen = new Set<string>();
  return candidates.filter((candidate) => {
    const key = `${candidate.executable}\0${candidate.prefixArgs.join("\0")}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

type PythonToolingIssue = "pip" | "venv";

async function pythonToolingIssue(
  candidate: PythonCandidate,
): Promise<PythonToolingIssue | undefined> {
  const directory = await Deno.makeTempDir({ prefix: "porydaw-python-" });
  try {
    const created = await commandResult(candidate.executable, [
      ...candidate.prefixArgs,
      "-m",
      "venv",
      directory,
    ]);
    if (!created.success) return "venv";
    const environmentPython = Deno.build.os === "windows"
      ? join(directory, "Scripts", "python.exe")
      : join(directory, "bin", "python");
    return await commandAvailable(environmentPython, ["-m", "pip", "--version"])
      ? undefined
      : "pip";
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

function missingPythonTooling(
  dependencies: NativeBuildDependency[],
  found: string[],
): PythonCheck {
  if (Deno.build.os === "linux") return { missing: dependencies };
  return {
    incompatibility: `${found.join(", ")} is installed without ${
      dependencies.map(dependencyLabel).join(" and ")
    }`,
  };
}

async function compatiblePython(): Promise<PythonCheck> {
  const foundVersions: string[] = [];
  const missingPip: string[] = [];
  const missingVenv: string[] = [];
  for (const candidate of await pythonCandidates()) {
    const result = await commandResult(candidate.executable, [
      ...candidate.prefixArgs,
      "--version",
    ]);
    if (!result.success) continue;
    const version = versionFrom(result.output);
    const found = firstLine(result.output);
    if (!version || !versionAtLeast(version, minimumPython)) {
      foundVersions.push(found);
      continue;
    }
    const toolingIssue = await pythonToolingIssue(candidate);
    if (toolingIssue === "pip") {
      missingPip.push(found);
      continue;
    }
    if (toolingIssue === "venv") {
      missingVenv.push(found);
      continue;
    }
    return {
      python: {
        ...candidate,
        version: `${version[0]}.${version[1]}`,
      },
    };
  }
  if (missingPip.length > 0 || missingVenv.length > 0) {
    return missingPythonTooling(
      [
        ...(missingPip.length > 0 ? ["python-pip" as const] : []),
        ...(missingVenv.length > 0 ? ["python-venv" as const] : []),
      ],
      [...missingPip, ...missingVenv],
    );
  }
  if (foundVersions.length > 0) {
    return {
      incompatibility: `Python 3.10 or newer is required; found ${
        foundVersions.join(", ")
      }`,
    };
  }
  return { missing: ["python"] };
}

async function visualStudioBuildToolsAvailable(): Promise<boolean> {
  const candidates = ["vswhere.exe"];
  const programFiles = Deno.env.get("ProgramFiles(x86)");
  if (programFiles) {
    candidates.push(
      join(
        programFiles,
        "Microsoft Visual Studio",
        "Installer",
        "vswhere.exe",
      ),
    );
  }
  for (const executable of candidates) {
    const result = await commandResult(executable, [
      "-latest",
      "-products",
      "*",
      "-requires",
      "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
      "-property",
      "installationPath",
    ]);
    if (result.success && result.output.trim()) return true;
  }
  return false;
}

async function compilerAvailable(): Promise<boolean> {
  if (Deno.build.os === "windows") {
    return await visualStudioBuildToolsAvailable();
  }
  return await commandAvailable("cc") && await commandAvailable("c++");
}

async function cxx20Probe(cmake: string): Promise<string | undefined> {
  const directory = await Deno.makeTempDir({ prefix: "porydaw-cxx20-" });
  try {
    const source = join(directory, "source");
    await Deno.mkdir(source);
    await Deno.writeTextFile(join(source, "CMakeLists.txt"), cxx20ProbeProject);
    const result = await commandResult(cmake, [
      "-S",
      source,
      "-B",
      join(directory, "build"),
    ]);
    return result.success ? undefined : probeFailure(result.output);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

export async function inspectNativeBuildTools(
  buildDirectory: string,
): Promise<NativeBuildToolsCheck> {
  const missing = new Set<NativeBuildDependency>();
  const incompatibilities: string[] = [];
  const cmake = await compatibleCmake();
  if (cmake.incompatibility) incompatibilities.push(cmake.incompatibility);
  if (!cmake.executable && !cmake.incompatibility) missing.add("cmake");

  const python = await compatiblePython();
  if (python.missing) {
    for (const dependency of python.missing) missing.add(dependency);
  }
  if (python.incompatibility) incompatibilities.push(python.incompatibility);

  if (
    await cmakeBuildUsesNinja(buildDirectory) &&
    !(await commandAvailable("ninja"))
  ) {
    missing.add("ninja");
  }

  const compiler = await compilerAvailable();
  if (!compiler) {
    missing.add("compiler");
  } else if (cmake.executable) {
    const probe = await cxx20Probe(cmake.executable);
    if (probe) {
      incompatibilities.push(
        `the selected C and C++ toolchain cannot compile C++20:\n${probe}`,
      );
    }
  }

  return {
    cmake: cmake.executable,
    python: python.python,
    missing: [...missing],
    incompatibilities,
  };
}

export function nativeBuildToolsDryRunOutcome(
  check: NativeBuildToolsCheck,
): string {
  if (check.incompatibilities.length > 0) {
    return "incompatible installed tools";
  }
  if (check.missing.length > 0) {
    return `would install ${check.missing.map(dependencyLabel).join(", ")}`;
  }
  return "compatible installed tools";
}

function missingDependenciesError(
  missing: readonly NativeBuildDependency[],
): Error {
  return new Error(
    `required native dependencies remain unavailable after installation: ${
      missing.map(dependencyLabel).join(", ")
    }. Restart the terminal, then rerun setup.`,
  );
}

export async function ensureNativeBuildTools(
  buildDirectory: string,
): Promise<NativeBuildTools> {
  const before = await inspectNativeBuildTools(buildDirectory);
  if (before.incompatibilities.length > 0) {
    throw new NativeBuildToolsError(before.incompatibilities);
  }
  if (before.missing.length === 0) {
    if (!before.cmake || !before.python) {
      throw new Error(
        "native tool inspection did not resolve CMake and Python",
      );
    }
    return {
      cmake: before.cmake,
      python: before.python,
      reused: true,
      installed: [],
    };
  }

  await installMissingNativeBuildTools(before.missing);
  const after = await inspectNativeBuildTools(buildDirectory);
  if (after.incompatibilities.length > 0) {
    throw new NativeBuildToolsError(after.incompatibilities);
  }
  if (after.missing.length > 0) {
    throw missingDependenciesError(after.missing);
  }
  if (!after.cmake || !after.python) {
    throw new Error(
      "native tool installation did not resolve CMake and Python",
    );
  }
  return {
    cmake: after.cmake,
    python: after.python,
    reused: false,
    installed: before.missing.map(dependencyLabel),
  };
}
