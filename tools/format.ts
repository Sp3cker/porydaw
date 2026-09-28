// Formats Swift with the toolchain's swift-format (config: .swift-format) and
// TypeScript with deno fmt. Swift is formatted only on lines changed since the
// base, so untouched code keeps its style; files named explicitly are whole.
import { extname } from "node:path";
import { buildDirectory } from "./local_build_environment.ts";
import { selectedSwiftCompiler, swiftDriver } from "./swift_toolchain.ts";

export interface FormatRequest {
  readonly check: boolean;
  /** Changes are measured from merge-base(base, HEAD) to the working tree. */
  readonly base: string;
  readonly files: string[];
}

type LineRanges = [number, number][] | "whole";

const decoder = new TextDecoder();
const HUNK = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/;

async function git(args: string[]): Promise<string> {
  const result = await new Deno.Command("git", {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(
      `git ${args[0]} failed: ${decoder.decode(result.stderr).trim()}`,
    );
  }
  return decoder.decode(result.stdout);
}

async function changedSwift(base: string): Promise<Map<string, LineRanges>> {
  const since = base === "HEAD"
    ? "HEAD"
    : (await git(["merge-base", base, "HEAD"])).trim();
  const diff = await git([
    "diff",
    "--unified=0",
    "--no-color",
    "--no-ext-diff",
    "--diff-filter=AMR",
    since,
    "--",
    "*.swift",
  ]);
  const changed = new Map<string, LineRanges>();
  let file: [number, number][] | undefined;
  for (const line of diff.split("\n")) {
    if (line.startsWith("+++ ")) {
      file = [];
      changed.set(line.slice("+++ b/".length), file);
      continue;
    }
    const hunk = HUNK.exec(line);
    if (!hunk || !file) continue;
    const start = Number(hunk[1]);
    const count = hunk[2] === undefined ? 1 : Number(hunk[2]);
    if (count > 0) file.push([start, start + count - 1]);
  }
  const untracked = await git([
    "ls-files",
    "--others",
    "--exclude-standard",
    "--",
    "*.swift",
  ]);
  for (const path of untracked.split("\n").filter(Boolean)) {
    changed.set(path, "whole");
  }
  for (const [path, ranges] of changed) {
    if (ranges !== "whole" && ranges.length === 0) changed.delete(path);
  }
  return changed;
}

async function swiftFormat(
  swift: string,
  path: string,
  ranges: LineRanges,
  inPlace: boolean,
): Promise<string> {
  const args = [
    "format",
    ...(inPlace ? ["-i"] : []),
    ...(ranges === "whole"
      ? []
      : ranges.flatMap(([start, end]) => ["--lines", `${start}:${end}`])),
    path,
  ];
  let result;
  try {
    result = await new Deno.Command(swift, {
      args,
      stdout: "piped",
      stderr: "piped",
    }).output();
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(
        `${swift} not found: install the Swift toolchain; swift-format ships with it`,
      );
    }
    throw error;
  }
  if (!result.success) {
    throw new Error(`${path}: ${decoder.decode(result.stderr).trim()}`);
  }
  return decoder.decode(result.stdout);
}

async function denoFmt(check: boolean, files: string[]): Promise<boolean> {
  const result = await new Deno.Command("deno", {
    args: ["fmt", "--quiet", ...(check ? ["--check"] : []), ...files],
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  return result.success;
}

// Returns the process exit code. Prints nothing when there is nothing to act on.
export async function formatSources(request: FormatRequest): Promise<number> {
  const unsupported = request.files.filter((file) =>
    extname(file) !== ".swift" && extname(file) !== ".ts"
  );
  if (unsupported.length > 0) {
    console.error(
      `format: only .swift and .ts files are formatted: ${
        unsupported.join(", ")
      }`,
    );
    return 2;
  }
  const typescript = request.files.filter((file) => extname(file) === ".ts");
  if (
    (request.files.length === 0 || typescript.length > 0) &&
    !(await denoFmt(request.check, typescript))
  ) return 1;

  const swiftFiles = request.files.filter((file) => extname(file) === ".swift");
  const targets = request.files.length > 0
    ? new Map<string, LineRanges>(swiftFiles.map((file) => [file, "whole"]))
    : await changedSwift(request.base);
  if (targets.size === 0) return 0;

  const swift = swiftDriver(
    await selectedSwiftCompiler(buildDirectory("debug")),
  );
  const unformatted: string[] = [];
  for (const [path, ranges] of targets) {
    const before = await Deno.readTextFile(path);
    if (request.check) {
      if (await swiftFormat(swift, path, ranges, false) !== before) {
        unformatted.push(path);
      }
      continue;
    }
    await swiftFormat(swift, path, ranges, true);
    if (await Deno.readTextFile(path) !== before) unformatted.push(path);
  }
  if (unformatted.length === 0) return 0;
  if (!request.check) {
    console.log(`format: reformatted ${unformatted.join(", ")}`);
    return 0;
  }
  const base = request.base === "HEAD" ? "" : ` --base ${request.base}`;
  console.error(
    `format: changed Swift lines need formatting; run deno task format${base}:`,
  );
  for (const path of unformatted) console.error(`  ${path}`);
  return 1;
}
