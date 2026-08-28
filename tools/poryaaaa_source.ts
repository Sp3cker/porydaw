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
    args,
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
  const expectedCommit = await recordedSubmoduleCommit(sourceRoot);
  const localRepository = join(sourceRoot, "external", "poryaaaa");
  const localPackage = join(sourceRoot, packageRelativePath);
  if (await exists(join(localPackage, packageSentinel))) {
    await validateDependencyCheckout(localRepository, expectedCommit, "local");
    return localPackage;
  }

  const mainRoot = await mainWorktreeRoot(sourceRoot);
  const sharedRepository = join(mainRoot, "external", "poryaaaa");
  const sharedPackage = join(mainRoot, packageRelativePath);
  if (!(await exists(join(sharedPackage, packageSentinel)))) {
    throw new Error(
      `poryaaaa is unavailable: initialize external/poryaaaa in the main checkout ${mainRoot}`,
    );
  }
  await validateDependencyCheckout(sharedRepository, expectedCommit, "shared");
  return sharedPackage;
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
