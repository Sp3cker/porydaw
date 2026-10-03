import { dirname, isAbsolute, join, resolve } from "node:path";

const decoder = new TextDecoder();
const taskNamePattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

type CreateRequest = {
  name: string;
  baseBranch: string;
};

function usage(message?: string): never {
  if (message) console.error(`worktree: ${message}`);
  console.error(
    "usage: deno task worktree:create -- <name> [--base <branch>]",
  );
  Deno.exit(2);
}

function parseRequest(rawArgs: string[]): CreateRequest {
  const args = rawArgs.filter((argument) => argument !== "--");
  if (args.shift() !== "create") usage("expected create");

  let name: string | undefined;
  let baseBranch = "fork-main";
  for (let index = 0; index < args.length; ++index) {
    const argument = args[index];
    if (argument === "--base") {
      const value = args[++index];
      if (!value || value.startsWith("-")) {
        usage("--base requires a branch");
      }
      baseBranch = value;
      continue;
    }
    if (argument.startsWith("-")) usage(`unknown option ${argument}`);
    if (name) usage(`unexpected argument ${argument}`);
    name = argument;
  }

  if (!name) usage("worktree name is required");
  if (!taskNamePattern.test(name)) {
    usage("name must be lowercase kebab-case");
  }
  return { name, baseBranch };
}

async function run(
  cwd: string,
  executable: string,
  args: string[],
  inheritOutput = false,
): Promise<Deno.CommandOutput> {
  return await new Deno.Command(executable, {
    cwd,
    args,
    stdin: "null",
    stdout: inheritOutput ? "inherit" : "piped",
    stderr: inheritOutput ? "inherit" : "piped",
  }).output();
}

async function gitOutput(cwd: string, args: string[]): Promise<string> {
  const result = await run(cwd, "git", args);
  if (!result.success) {
    const detail = decoder.decode(result.stderr).trim();
    throw new Error(detail || `git ${args.join(" ")} failed`);
  }
  return decoder.decode(result.stdout).trim();
}

async function gitSucceeds(cwd: string, args: string[]): Promise<boolean> {
  return (await run(cwd, "git", args)).success;
}

async function requireSuccess(
  cwd: string,
  executable: string,
  args: string[],
): Promise<void> {
  const result = await run(cwd, executable, args, true);
  if (!result.success) {
    throw new Error(
      `${executable} ${args.join(" ")} failed with ${result.code}`,
    );
  }
}

async function mainWorktreeRoot(cwd: string): Promise<string> {
  const commonDir = await gitOutput(cwd, [
    "rev-parse",
    "--path-format=absolute",
    "--git-common-dir",
  ]);
  return dirname(isAbsolute(commonDir) ? commonDir : resolve(cwd, commonDir));
}

async function mainIndexSubmoduleCommit(mainRoot: string): Promise<string> {
  const entry = await gitOutput(mainRoot, [
    "ls-files",
    "--stage",
    "--",
    "external/poryaaaa",
  ]);
  const match = /^160000 ([0-9a-f]+) 0\texternal\/poryaaaa$/.exec(entry);
  if (!match) {
    throw new Error(
      "external/poryaaaa is missing or unmerged; run deno task poryaaaa:sync in swift-qml-grid",
    );
  }
  return match[1];
}

async function validateSharedSubmodule(
  repository: string,
  expectedCommit: string,
): Promise<void> {
  const actualCommit = await gitOutput(repository, ["rev-parse", "HEAD"]);
  if (actualCommit !== expectedCommit) {
    throw new Error(
      `canonical poryaaaa checkout has ${actualCommit}, but the main index records ${expectedCommit}; run deno task poryaaaa:sync in swift-qml-grid`,
    );
  }
  const status = await gitOutput(repository, [
    "status",
    "--porcelain=v1",
    "--untracked-files=all",
  ]);
  if (status) throw new Error(`shared poryaaaa checkout is dirty:\n${status}`);
}

async function prepareSharedSubmodule(mainRoot: string): Promise<string> {
  const mainCommit = await mainIndexSubmoduleCommit(mainRoot);
  const repository = join(mainRoot, "external", "poryaaaa");
  let initialized = true;
  try {
    await Deno.lstat(join(repository, ".git"));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    initialized = false;
  }
  if (initialized) {
    await validateSharedSubmodule(repository, mainCommit);
    return repository;
  }

  try {
    for await (const _entry of Deno.readDir(repository)) {
      throw new Error(
        `shared poryaaaa path ${repository} is not initialized and is not empty`,
      );
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  await requireSuccess(mainRoot, "git", [
    "-c",
    "submodule.external/poryaaaa.url=https://github.com/Sp3cker/poryaaaa-monorepo.git",
    "submodule",
    "update",
    "--init",
    "--recursive",
    "external/poryaaaa",
  ]);
  await validateSharedSubmodule(repository, mainCommit);
  return repository;
}

export async function createWorktree(
  mainRoot: string,
  request: CreateRequest,
): Promise<void> {
  if (
    !(await gitSucceeds(mainRoot, [
      "check-ref-format",
      "--branch",
      request.baseBranch,
    ]))
  ) {
    throw new Error(`invalid base branch ${request.baseBranch}`);
  }
  if (
    !(await gitSucceeds(mainRoot, [
      "show-ref",
      "--verify",
      "--quiet",
      `refs/heads/${request.baseBranch}`,
    ]))
  ) {
    throw new Error(`local branch ${request.baseBranch} does not exist`);
  }

  const baseRef = `refs/heads/${request.baseBranch}`;

  const branch = `feature/${request.name}`;
  const path = join(mainRoot, ".worktrees", request.name);
  if (
    await gitSucceeds(mainRoot, [
      "show-ref",
      "--verify",
      "--quiet",
      `refs/heads/${branch}`,
    ])
  ) {
    throw new Error(`branch ${branch} already exists`);
  }
  try {
    await Deno.lstat(path);
    throw new Error(`path ${path} already exists`);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const sharedSubmodule = await prepareSharedSubmodule(mainRoot);
  const canonicalCommit = await mainIndexSubmoduleCommit(mainRoot);
  await requireSuccess(mainRoot, "git", [
    "-c",
    "submodule.recurse=false",
    "worktree",
    "add",
    "-b",
    branch,
    path,
    baseRef,
  ]);
  await requireSuccess(path, "git", [
    "update-index",
    "--cacheinfo",
    `160000,${canonicalCommit},external/poryaaaa`,
  ]);
  console.log(
    `worktree: adopted canonical poryaaaa ${canonicalCommit} in new index`,
  );
  console.log(`worktree: created ${path}`);
  console.log(`worktree: branch ${branch} from ${request.baseBranch}`);
  console.log(`worktree: builds use shared submodule ${sharedSubmodule}`);
}

if (import.meta.main) {
  try {
    const request = parseRequest(Deno.args);
    const mainRoot = await mainWorktreeRoot(Deno.cwd());
    await createWorktree(mainRoot, request);
  } catch (error) {
    console.error(
      `worktree: ${error instanceof Error ? error.message : String(error)}`,
    );
    Deno.exit(1);
  }
}
