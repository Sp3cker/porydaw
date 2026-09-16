import type { NativeBuildDependency } from "./native_build_tools.ts";

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

async function run(
  description: string,
  executable: string,
  args: string[],
): Promise<void> {
  try {
    const result = await new Deno.Command(executable, {
      args,
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

async function installMacosTools(
  missing: readonly NativeBuildDependency[],
): Promise<void> {
  if (missing.includes("compiler")) {
    await run(
      "requesting Xcode Command Line Tools",
      "xcode-select",
      ["--install"],
    );
    throw new Error(
      "finish the Xcode Command Line Tools installation, then rerun setup",
    );
  }
  const formulas = [
    ...(missing.includes("cmake") ? ["cmake"] : []),
    ...(missing.includes("ninja") ? ["ninja"] : []),
    ...(missing.some((dependency) =>
        dependency === "python" || dependency === "python-pip" ||
        dependency === "python-venv"
      )
      ? ["python"]
      : []),
  ];
  if (formulas.length === 0) return;
  if (!(await commandAvailable("brew"))) {
    throw new Error("Homebrew is required on macOS: https://brew.sh/");
  }
  await run("installing missing macOS build tools", "brew", [
    "install",
    ...formulas,
  ]);
}

function packageNames(
  missing: readonly NativeBuildDependency[],
  names: Record<NativeBuildDependency, readonly string[]>,
): string[] {
  return [...new Set(missing.flatMap((dependency) => names[dependency]))];
}

async function installLinuxTools(
  missing: readonly NativeBuildDependency[],
): Promise<void> {
  if (await commandAvailable("apt-get")) {
    const packages = packageNames(missing, {
      compiler: ["build-essential"],
      cmake: ["cmake"],
      ninja: ["ninja-build"],
      python: ["python3", "python3-venv"],
      "python-pip": ["python3-pip"],
      "python-venv": ["python3-venv"],
    });
    await run("refreshing APT metadata", "sudo", ["apt-get", "update"]);
    await run("installing missing Debian/Ubuntu build tools", "sudo", [
      "apt-get",
      "install",
      "-y",
      "--no-install-recommends",
      ...packages,
    ]);
    return;
  }
  if (await commandAvailable("pacman")) {
    const packages = packageNames(missing, {
      compiler: ["base-devel"],
      cmake: ["cmake"],
      ninja: ["ninja"],
      python: ["python"],
      "python-pip": ["python"],
      "python-venv": ["python"],
    });
    await run("installing missing Arch build tools", "sudo", [
      "pacman",
      "-S",
      "--needed",
      ...packages,
    ]);
    return;
  }
  if (await commandAvailable("dnf")) {
    const packages = packageNames(missing, {
      compiler: ["gcc-c++"],
      cmake: ["cmake"],
      ninja: ["ninja-build"],
      python: ["python3", "python3-pip"],
      "python-pip": ["python3-pip"],
      "python-venv": ["python3"],
    });
    await run("installing missing Fedora build tools", "sudo", [
      "dnf",
      "install",
      "-y",
      ...packages,
    ]);
    return;
  }
  throw new Error(
    "unsupported Linux package manager; supported: apt-get, pacman, dnf",
  );
}

async function installWindowsTools(
  missing: readonly NativeBuildDependency[],
): Promise<void> {
  if (!(await commandAvailable("winget"))) {
    throw new Error(
      "WinGet is required on Windows; install App Installer and rerun setup",
    );
  }
  const agreements = [
    "--accept-source-agreements",
    "--accept-package-agreements",
  ];
  if (missing.includes("cmake")) {
    await run("installing missing CMake", "winget", [
      "install",
      "--exact",
      "--id",
      "Kitware.CMake",
      ...agreements,
    ]);
  }
  if (
    missing.some((dependency) =>
      dependency === "python" || dependency === "python-pip" ||
      dependency === "python-venv"
    )
  ) {
    await run("installing missing Python", "winget", [
      "install",
      "--exact",
      "--id",
      "Python.Python.3.12",
      ...agreements,
    ]);
  }
  if (missing.includes("ninja")) {
    await run("installing missing Ninja", "winget", [
      "install",
      "--exact",
      "--id",
      "Ninja-build.Ninja",
      ...agreements,
    ]);
  }
  if (missing.includes("compiler")) {
    await run("installing missing Visual Studio Build Tools", "winget", [
      "install",
      "--exact",
      "--id",
      "Microsoft.VisualStudio.2022.BuildTools",
      "--override",
      "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended",
      ...agreements,
    ]);
  }
}

export async function installMissingNativeBuildTools(
  missing: readonly NativeBuildDependency[],
): Promise<void> {
  switch (Deno.build.os) {
    case "darwin":
      await installMacosTools(missing);
      return;
    case "linux":
      await installLinuxTools(missing);
      return;
    case "windows":
      await installWindowsTools(missing);
      return;
    default:
      throw new Error(`unsupported platform ${Deno.build.os}`);
  }
}
