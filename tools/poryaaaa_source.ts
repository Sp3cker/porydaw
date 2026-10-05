import { dirname, isAbsolute, join, resolve } from "node:path";

const decoder = new TextDecoder();
const packageRelativePath = join(
  "external",
  "poryaaaa",
  "packages",
  "poryaaaa",
);
const packageSentinel = join("plugin", "porydaw", "CMakeLists.txt");

export type PoryaaaaConfiguration = {
  cmakeArgument: string;
  cacheMatches: boolean;
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

async function gitOutput(cwd: string, args: string[]): Promise<string> {
  const result = await new Deno.Command("git", {
    cwd,
    args: ["--no-optional-locks", ...args],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    const detail = decoder.decode(result.stderr).trim();
    throw new Error(detail || `git ${args.join(" ")} failed`);
  }
  return decoder.decode(result.stdout).trim();
}

async function recordedSubmoduleCommit(sourceRoot: string): Promise<string> {
  const entry = await gitOutput(sourceRoot, [
    "ls-files",
    "--stage",
    "--",
    "external/poryaaaa",
  ]);
  const match = /^160000 ([0-9a-f]+) /.exec(entry);
  if (!match) {
    throw new Error("external/poryaaaa is not recorded as a submodule");
  }
  return match[1];
}

async function mainWorktreeRoot(sourceRoot: string): Promise<string> {
  const commonDir = await gitOutput(sourceRoot, [
    "rev-parse",
    "--path-format=absolute",
    "--git-common-dir",
  ]);
  const absoluteCommonDir = isAbsolute(commonDir)
    ? commonDir
    : resolve(sourceRoot, commonDir);
  return dirname(absoluteCommonDir);
}

async function validateDependencyCheckout(
  repository: string,
  expectedCommit: string,
  description: string,
  allowTrackedChanges = false,
): Promise<void> {
  const actualCommit = await gitOutput(repository, ["rev-parse", "HEAD"]);
  if (actualCommit !== expectedCommit) {
    throw new Error(
      `${description} poryaaaa revision mismatch: worktree records ${expectedCommit}, checkout has ${actualCommit}`,
    );
  }
  const status = await gitOutput(repository, [
    "status",
    "--porcelain=v1",
    "--untracked-files=all",
  ]);
  const disallowedChanges = allowTrackedChanges
    ? status.split("\n").filter((line) => line.startsWith("?? ")).join("\n")
    : status;
  if (disallowedChanges) {
    throw new Error(
      `${description} poryaaaa checkout is dirty:\n${disallowedChanges}`,
    );
  }
}

async function resolvePoryaaaaPackage(sourceRoot: string): Promise<string> {
  const mainRoot = await Deno.realPath(await mainWorktreeRoot(sourceRoot));
  const worktreeRoot = await Deno.realPath(sourceRoot);
  let dependencyRoot = mainRoot;
  if (worktreeRoot !== mainRoot) {
    const localRepository = join(worktreeRoot, "external", "poryaaaa");
    const localCheckout = await Deno.lstat(localRepository).catch((error) => {
      if (error instanceof Deno.errors.NotFound) return undefined;
      throw error;
    });
    if (localCheckout !== undefined) {
      if (
        !localCheckout.isDirectory ||
        await Deno.realPath(localRepository) !== localRepository
      ) {
        dependencyRoot = worktreeRoot;
      } else {
        // A real empty directory is an uninitialized gitlink, not a checkout.
        for await (const _entry of Deno.readDir(localRepository)) {
          dependencyRoot = worktreeRoot;
          break;
        }
      }
    }
  }
  const local = dependencyRoot !== mainRoot;
  const description = local ? "worktree-local" : "canonical";
  const repository = join(dependencyRoot, "external", "poryaaaa");
  const packageDirectory = join(dependencyRoot, packageRelativePath);
  try {
    const expectedCommit = await recordedSubmoduleCommit(dependencyRoot);
    if (!(await exists(join(packageDirectory, packageSentinel)))) {
      throw new Error(`package sentinel is missing in ${packageDirectory}`);
    }
    if (
      await Deno.realPath(repository) !== repository ||
      await Deno.realPath(packageDirectory) !== packageDirectory
    ) {
      throw new Error(`${description} package must not use a symlink target`);
    }
    const repositoryRoot = await gitOutput(repository, [
      "rev-parse",
      "--show-toplevel",
    ]);
    if (resolve(repositoryRoot) !== repository) {
      throw new Error(`${repository} is not a dependency checkout`);
    }
    await validateDependencyCheckout(
      repository,
      expectedCommit,
      description,
      local,
    );
    return packageDirectory;
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    const context = local
      ? `Invalid worktree-local poryaaaa checkout ${repository}`
      : `Canonical poryaaaa sync required in main checkout ${mainRoot}`;
    throw new Error(`${context}: ${detail}`, { cause: error });
  }
}

async function cachedPoryaaaaPackage(
  sourceRoot: string,
  buildDirectory: string,
): Promise<string | undefined> {
  try {
    const cache = await Deno.readTextFile(
      join(sourceRoot, buildDirectory, "CMakeCache.txt"),
    );
    const prefix = "PORYAAAA_DIR:PATH=";
    const entry = cache.split("\n").find((line) => line.startsWith(prefix));
    return entry?.slice(prefix.length);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

export async function poryaaaaConfiguration(
  buildDirectory: string,
  sourceRoot = Deno.cwd(),
): Promise<PoryaaaaConfiguration> {
  const packageDirectory = await resolvePoryaaaaPackage(sourceRoot);
  const cachedPackage = await cachedPoryaaaaPackage(sourceRoot, buildDirectory);
  return {
    cmakeArgument: `-DPORYAAAA_DIR=${packageDirectory}`,
    cacheMatches: cachedPackage !== undefined &&
      resolve(cachedPackage) === resolve(packageDirectory),
  };
}
