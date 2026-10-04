import { isAbsolute, relative, resolve } from "node:path";

const BASELINE = "tools/qml_aot_baseline.json";
export const QML_AOT_HELP =
  `usage: deno task checks:qml-aot [--release] [--verbose] [--update-baseline [--allow-growth]] [--help]
  build the application, then ratchet production QML AOT compilation
  --release          use build/release (default: build/debug)
  --verbose          group compiler rejections and list dependency-only revision reads
  --update-baseline  record current numbers, refusing growth by default
  --allow-growth     allow baseline growth (requires --update-baseline)
  --help             show this help without building

Baseline writes require deno task qml-aot:baseline (allows growth).`;

type Baseline = {
  rejected: number;
  total: number;
  files: Record<string, number>;
  propertyVarCount: number;
  revisionDependencyReads: number;
  pragmaAllowlist: string[];
};
type FileStats = { total: number; rejected: number };
type Entry = { codegenResult: number; message?: string };
type Stats = {
  modules: { moduleFiles: { filePath: string; entries: Entry[] }[] }[];
};

async function files(directory: string): Promise<string[]> {
  const result: string[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const path = `${directory}/${entry.name}`;
    if (entry.isDirectory) result.push(...await files(path));
    else if (entry.isFile) result.push(path);
  }
  return result.sort();
}

// Keep quoted imports visible, but exclude comments from structural counts.
function withoutComments(text: string): string {
  return text.replace(
    /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\/\/[^\n]*|\/\*[\s\S]*?\*\//g,
    (part) =>
      part.startsWith("//") || part.startsWith("/*")
        ? part.replace(/[^\n]/g, " ")
        : part,
  );
}

function revisionDependencyLines(code: string): number[] {
  const identifier = "[A-Za-z_$][\\w$]*";
  const revision = `(?:${identifier})?(?:Revision|revision)`;
  const member = `(?:${identifier}\\s*\\.\\s*)*${revision}`;
  const revisionToken = new RegExp(`(?<![\\w$])${revision}(?![\\w$])`);
  const bareRead = new RegExp(`^\\s*${member}\\s*;?\\s*$`);
  const commaRead = new RegExp(`\\(\\s*${member}\\s*,`);
  const sites = new Set<number>();
  const lines = code.split("\n");
  let offset = 0;
  for (const [index, line] of lines.entries()) {
    if (bareRead.test(line) || commaRead.test(line)) sites.add(index + 1);
    for (
      const declaration of line.matchAll(
        /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*([^;\n]+)/g,
      )
    ) {
      if (!revisionToken.test(declaration[2])) continue;
      const name = declaration[1].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const later = code.slice(
        offset + declaration.index + declaration[0].length,
      );
      if (!new RegExp(`(?<![\\w$])${name}(?![\\w$])`).test(later)) {
        sites.add(index + 1);
      }
    }
    offset += line.length + 1;
  }
  return [...sites].sort((a, b) => a - b);
}

function readBaseline(text: string): Baseline {
  const value = JSON.parse(text);
  const count = (n: unknown): n is number =>
    typeof n === "number" && Number.isSafeInteger(n) && n >= 0;
  if (
    !value || !count(value.rejected) || !count(value.total) ||
    !count(value.propertyVarCount) || !count(value.revisionDependencyReads) ||
    !value.files ||
    typeof value.files !== "object" || Array.isArray(value.files) ||
    !Object.values(value.files).every(count) ||
    !Array.isArray(value.pragmaAllowlist) ||
    !value.pragmaAllowlist.every((path: unknown) => typeof path === "string")
  ) {
    throw new Error(
      `Invalid ${BASELINE}: expected nonnegative counts and a pragma allowlist`,
    );
  }
  return value;
}

async function main(): Promise<void> {
  const allowed: Record<string, true> = {
    "--release": true,
    "--verbose": true,
    "--update-baseline": true,
    "--allow-growth": true,
    "--help": true,
  };
  if (
    Deno.args.some((arg) => !Object.hasOwn(allowed, arg)) ||
    (Deno.args.includes("--allow-growth") &&
      !Deno.args.includes("--update-baseline"))
  ) {
    console.error(QML_AOT_HELP);
    Deno.exit(2);
  }
  if (Deno.args.includes("--help")) {
    console.log(QML_AOT_HELP);
    return;
  }
  const config = Deno.args.includes("--release") ? "release" : "debug";
  const directory = `build/${config}/.rcc/qmlcache`;
  const statsPaths: string[] = [];
  try {
    for await (const entry of Deno.readDir(directory)) {
      if (entry.isFile && entry.name.endsWith(".aotstats")) {
        statsPaths.push(`${directory}/${entry.name}`);
      }
    }
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  if (!statsPaths.length) {
    throw new Error(
      `Missing or empty AOT statistics in ${directory}; build the application with AOT statistics enabled`,
    );
  }
  const root = resolve(".");
  const ui = resolve("src/ui");
  const perFile = new Map<string, FileStats>();
  const messages = new Map<string, number>();
  for (const path of statsPaths.sort()) {
    const stats: Stats = JSON.parse(await Deno.readTextFile(path));
    for (const module of stats.modules) {
      for (const file of module.moduleFiles) {
        const absolute = resolve(root, file.filePath);
        const underUi = relative(ui, absolute);
        if (
          underUi === ".." || underUi.startsWith("../") ||
          underUi.startsWith("..\\") || isAbsolute(underUi)
        ) continue;
        const name = relative(root, absolute).replaceAll("\\", "/");
        if (perFile.has(name)) {
          throw new Error(`Duplicate AOT statistics for ${name}`);
        }
        const counts = { total: file.entries.length, rejected: 0 };
        for (const entry of file.entries) {
          if (!Number.isInteger(entry.codegenResult)) {
            throw new Error(`Invalid codegenResult in ${path}`);
          }
          if (entry.codegenResult !== 0) {
            counts.rejected++;
            const message = entry.message || "(no rejection message)";
            messages.set(message, (messages.get(message) ?? 0) + 1);
          }
        }
        perFile.set(name, counts);
      }
    }
  }
  const current: Baseline = {
    rejected: 0,
    total: 0,
    files: {},
    propertyVarCount: 0,
    revisionDependencyReads: 0,
    pragmaAllowlist: [],
  };
  for (
    const [name, counts] of [...perFile].sort(([a], [b]) => a.localeCompare(b))
  ) {
    current.total += counts.total;
    current.rejected += counts.rejected;
    current.files[name] = counts.rejected;
  }
  if (!current.total) {
    throw new Error(`No production QML entries found in ${directory}`);
  }
  const banned: string[] = [];
  const revisionSites: string[] = [];
  for (const path of await files("src/ui")) {
    if (path.endsWith(".js")) banned.push(`JavaScript file: ${path}`);
    if (!path.endsWith(".qml")) continue;
    const code = withoutComments(await Deno.readTextFile(path));
    const structure = code.replace(
      /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`/g,
      (part) => part.replace(/[^\n]/g, " "),
    );
    current.propertyVarCount +=
      [...structure.matchAll(/\bproperty\s+var\s+[A-Za-z_$][\w$]*/g)].length;
    for (const line of revisionDependencyLines(structure)) {
      revisionSites.push(`${path}:${line}`);
    }
    if (!/^\s*pragma\s+ComponentBehavior\s*:\s*Bound\b/m.test(structure)) {
      current.pragmaAllowlist.push(path);
    }
    if (/^\s*import\s+["'][^"'\n]*\.js["']/m.test(code)) {
      banned.push(`JavaScript import: ${path}`);
    }
  }
  current.pragmaAllowlist.sort();
  current.revisionDependencyReads = revisionSites.length;
  const compiled = current.total - current.rejected;
  console.log(
    `QML AOT: ${compiled}/${current.total} compiled (${
      (100 * compiled / current.total).toFixed(1)
    }%); ${current.rejected} rejected`,
  );
  for (
    const [path, counts] of [...perFile].sort(([a, x], [b, y]) =>
      y.rejected - x.rejected || a.localeCompare(b)
    )
  ) {
    console.log(
      `${path}: ${
        counts.total - counts.rejected
      }/${counts.total} compiled; ${counts.rejected} rejected`,
    );
  }
  if (Deno.args.includes("--verbose")) {
    for (
      const [message, count] of [...messages].sort(([a, x], [b, y]) =>
        y - x || a.localeCompare(b)
      )
    ) {
      console.log(`${count} × ${message}`);
    }
    for (const site of revisionSites) {
      console.log(`${site}: dependency-only revision read`);
    }
  }
  let baseline: Baseline;
  try {
    baseline = readBaseline(await Deno.readTextFile(BASELINE));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    throw new Error(
      `Missing ${BASELINE}; generate it with deno task qml-aot:baseline`,
    );
  }
  const growth: string[] = [];
  if (current.rejected > baseline.rejected) {
    growth.push(`Global rejected: ${current.rejected} > ${baseline.rejected}`);
  }
  for (const [path, rejected] of Object.entries(current.files)) {
    const limit = baseline.files[path] ?? 0;
    if (rejected > limit) {
      growth.push(`${path}: rejected ${rejected} > ${limit}`);
    }
  }
  if (current.propertyVarCount > baseline.propertyVarCount) {
    growth.push(
      `property var: ${current.propertyVarCount} > ${baseline.propertyVarCount}`,
    );
  }
  if (current.revisionDependencyReads > baseline.revisionDependencyReads) {
    growth.push(
      `Dependency-only revision reads: ${current.revisionDependencyReads} > ${baseline.revisionDependencyReads}`,
    );
  }
  const allowlist = new Set(baseline.pragmaAllowlist);
  for (const path of current.pragmaAllowlist) {
    if (!allowlist.has(path)) {
      growth.push(`${path}: missing pragma ComponentBehavior: Bound`);
    }
  }
  const update = Deno.args.includes("--update-baseline");
  if (
    banned.length ||
    (growth.length && !(update && Deno.args.includes("--allow-growth")))
  ) {
    for (const failure of [...banned, ...growth]) console.error(failure);
    if (update) {
      console.error(
        `Refusing to update ${BASELINE}; growth requires --allow-growth, JavaScript is always forbidden`,
      );
    }
    Deno.exit(1);
  }
  if (update) {
    await Deno.writeTextFile(BASELINE, JSON.stringify(current, null, 2) + "\n");
    console.log(`Updated ${BASELINE}`);
  }
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
