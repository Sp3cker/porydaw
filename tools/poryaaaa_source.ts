import { dirname, isAbsolute, join, resolve } from "node:path";
import { run } from "./lib/exec.ts";

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
  const result = await run("git", ["--no-optional-locks", ...args], { cwd });
  if (!result.success) {
    const detail = result.text("stderr").trim();
    throw new Error(detail || `git ${args.join(" ")} failed`);
  }
  return result.text().trim();
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
  if (status) {
    throw new Error(`${description} poryaaaa checkout is dirty:\n${status}`);
  }
}

async function resolvePoryaaaaPackage(sourceRoot: string): Promise<string> {
  const mainRoot = await Deno.realPath(await mainWorktreeRoot(sourceRoot));
  try {
    const expectedCommit = await recordedSubmoduleCommit(mainRoot);
    const canonicalRepository = join(mainRoot, "external", "poryaaaa");
    const canonicalPackage = join(mainRoot, packageRelativePath);
    if (!(await exists(join(canonicalPackage, packageSentinel)))) {
      throw new Error(`package sentinel is missing in ${canonicalPackage}`);
    }
    if (await Deno.realPath(canonicalPackage) !== canonicalPackage) {
      throw new Error(`canonical package must not use a symlink target`);
    }
    const repositoryRoot = await gitOutput(canonicalRepository, [
      "rev-parse",
      "--show-toplevel",
    ]);
    if (resolve(repositoryRoot) !== canonicalRepository) {
      throw new Error(`${canonicalRepository} is not a dependency checkout`);
    }
    await validateDependencyCheckout(
      canonicalRepository,
      expectedCommit,
      "canonical",
    );
    return canonicalPackage;
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Canonical poryaaaa sync required in main checkout ${mainRoot}: ${detail}`,
      { cause: error },
    );
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
