// One-shot converter from line-numbered S headers to stable Anchor lines.
import {
  enclosingFunction,
  findFunctionBodies,
  formatAnchor,
  functionName,
  literalLines,
  resolveAnchor,
} from "./proof_anchor.ts";
import type { Anchor } from "./proof_anchor.ts";

const CHECKS = "src/checks";
const USAGE =
  "usage: deno run --allow-read=src/checks --allow-write=src/checks tools/proof_migrate.ts [--dry-run]";

const sHeader = /^(S\d+)\s*\|\s*(.+)\s*\|\s*(.+?)\s*$/;
const anchorLine = /^Anchor:/;
const siteHeader = /^(A\d+\s*\|\s*.+|Original\s+\d+)\s*$/;
const trailer =
  /^(?:Swift assertion predicates|Remaining original source|Shared helpers|Remaining source|Swift predicates|Tally)\s*(?:\(|:|$)/;
const shaLine = /^(?:Additional )?Swift SHA-256:.*$/;
const tallyLine = /^\s*Tally:/;
const location =
  /^(?:.*?\s+::\s+)?(src\/\S+?)(?::(\d+)(?:-\d+)?)?(?:\s+::\s+.*)?$/;
const funcTrailer = /\s+::\s*(\S+?)(?::(\d+)(?:-\d+)?)?\s*$/;
const loosePath = /(src\/[^\s:]+)(?::(\d+)(?:-\d+)?)?/;
const looseFunc = /::\s*(\S+?)(?::(\d+)(?:-\d+)?)?(?:\s|$)/;
const swiftMessage = /(?:message|what):\s*"((?:[^"\\\n]|\\.)*)"/;
const quoted = /"((?:[^"\\\n]|\\.)*)"/g;

interface Totals {
  files: number;
  message: number;
  numbered: number;
  function: number;
  deleted: number;
  sha: number;
  tally: number;
}

interface Failure {
  path: string;
  id: string;
  reason: string;
}

type Migration =
  | {
    ok: true;
    field: string;
    anchor: Anchor;
    kind: "message" | "function" | "deleted";
    numbered: boolean;
  }
  | { ok: false; reason: string };

function statementAt(sourceLines: string[], start: number): string {
  const gathered: string[] = [];
  let depth = 0;
  let opened = false;
  let inString = false;
  let complete = false;
  for (
    let i = start - 1;
    i < sourceLines.length && i < start + 11 && !complete;
    i++
  ) {
    const line = sourceLines[i] ?? "";
    gathered.push(line);
    for (let j = 0; j < line.length && !complete; j++) {
      const ch = line[j];
      if (inString) {
        if (ch === "\\") j++;
        else if (ch === '"') inString = false;
      } else if (ch === '"') {
        inString = true;
      } else if (ch === "/" && line[j + 1] === "/") {
        break;
      } else if (ch === "(") {
        depth++;
        opened = true;
      } else if (ch === ")") {
        depth--;
        if (!opened || depth <= 0) complete = true;
      }
    }
    if (gathered.length === 1 && !opened) complete = true;
  }
  return gathered.join("\n");
}

function sourceLiteral(text: string, isQml: boolean): string | undefined {
  if (isQml) {
    const found = [...text.matchAll(quoted)];
    return found.length ? found[found.length - 1][1] || undefined : undefined;
  }
  return text.match(swiftMessage)?.[1] || undefined;
}

function stripHashProse(line: string): string {
  return line
    .replaceAll(" Source hashes pin the tree inspected here.", "")
    .replaceAll("; source hashes pin the tree inspected here", "")
    .replaceAll(" source hashes pin the tree inspected here.", "")
    .replace(/([\w./+-]+\.(?:swift|qml)):\d+(?:-\d+)?/g, "$1");
}

function rescueHeader(
  field: string,
  last: string,
): { locPath: string; name: string; start: number | undefined } | undefined {
  const combined = `${field} ${last}`;
  const pathHit = combined.match(loosePath);
  const funcHit = combined.match(looseFunc);
  if (!pathHit || !funcHit) return undefined;
  const line = funcHit[2] ?? pathHit[2];
  return {
    locPath: pathHit[1],
    name: funcHit[1],
    start: line === undefined ? undefined : Number(line),
  };
}

function migrateUnlined(
  source: string,
  field: string,
  locPath: string,
  bodyText: string,
): Migration {
  if (!findFunctionBodies(source, functionName(field)).length) {
    return {
      ok: false,
      reason: `function ${functionName(field) || field} not found`,
    };
  }
  const literal = sourceLiteral(bodyText, locPath.endsWith(".qml"));
  if (literal !== undefined) {
    let total = 0;
    for (const body of findFunctionBodies(source, functionName(field))) {
      total += literalLines(source, body, literal).length;
    }
    if (total === 1) {
      const candidate: Anchor = { kind: "message", literal };
      if (resolveAnchor(source, field, candidate).ok) {
        return {
          ok: true,
          field,
          anchor: candidate,
          kind: "message",
          numbered: false,
        };
      }
    }
  }
  const fallback = resolveAnchor(source, field, { kind: "function" });
  if (fallback.ok) {
    return {
      ok: true,
      field,
      anchor: { kind: "function" },
      kind: "function",
      numbered: false,
    };
  }
  return {
    ok: false,
    reason: literal === undefined
      ? `no message literal; ${fallback.reason}`
      : `message unconfirmed; ${fallback.reason}`,
  };
}

function migrateEntry(
  source: string | undefined,
  field: string,
  start: number | undefined,
  locPath: string,
  bodyText: string,
): Migration {
  if (source === undefined) {
    return {
      ok: true,
      field,
      anchor: { kind: "deleted" },
      kind: "deleted",
      numbered: false,
    };
  }
  if (start === undefined) {
    return migrateUnlined(source, field, locPath, bodyText);
  }
  let current = field;
  let bodies = findFunctionBodies(source, functionName(current));
  if (!bodies.length) {
    const enclosing = enclosingFunction(source, start);
    if (!enclosing) {
      return { ok: false, reason: `no enclosing function at line ${start}` };
    }
    current = enclosing.name;
    bodies = findFunctionBodies(source, functionName(current));
  }
  const isQml = locPath.endsWith(".qml");
  let literal = sourceLiteral(statementAt(source.split("\n"), start), isQml);
  if (literal === undefined) literal = sourceLiteral(bodyText, isQml);
  if (literal !== undefined) {
    const ordered = [
      ...bodies.filter((b) => b.startLine <= start && start <= b.endLine),
      ...bodies.filter((b) => b.startLine > start || start > b.endLine),
    ];
    for (const body of ordered) {
      const lines = literalLines(source, body, literal);
      if (!lines.length) continue;
      let occurrence: number | undefined;
      if (lines.length > 1) {
        let best = 0;
        for (let i = 1; i < lines.length; i++) {
          if (Math.abs(lines[i] - start) < Math.abs(lines[best] - start)) {
            best = i;
          }
        }
        occurrence = best + 1;
      }
      const candidate: Anchor = occurrence === undefined
        ? { kind: "message", literal }
        : { kind: "message", literal, occurrence };
      if (resolveAnchor(source, current, candidate).ok) {
        return {
          ok: true,
          field: current,
          anchor: candidate,
          kind: "message",
          numbered: occurrence !== undefined,
        };
      }
    }
  }
  const fallback = resolveAnchor(source, current, { kind: "function" });
  if (fallback.ok) {
    return {
      ok: true,
      field: current,
      anchor: { kind: "function" },
      kind: "function",
      numbered: false,
    };
  }
  return {
    ok: false,
    reason: literal === undefined
      ? `no message literal; ${fallback.reason}`
      : `message unconfirmed; ${fallback.reason}`,
  };
}

const sources = new Map<string, string | undefined>();

async function sourceText(path: string): Promise<string | undefined> {
  if (!sources.has(path)) {
    let text: string | undefined;
    try {
      text = await Deno.readTextFile(path);
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    sources.set(path, text);
  }
  return sources.get(path);
}

async function migrateFile(
  path: string,
  dryRun: boolean,
  totals: Totals,
  failures: Failure[],
): Promise<void> {
  const text = await Deno.readTextFile(path);
  const newline = text.includes("\r\n") ? "\r\n" : "\n";
  const lines = text.split(/\r?\n/);
  const kept: string[] = [];
  let changed = false;
  let i = 0;
  while (i < lines.length) {
    const header = lines[i].match(sHeader);
    if (!header) {
      const line = lines[i];
      if (shaLine.test(line)) {
        totals.sha++;
        changed = true;
      } else if (tallyLine.test(line)) {
        totals.tally++;
        changed = true;
      } else {
        const stripped = stripHashProse(line);
        if (stripped !== line) changed = true;
        kept.push(stripped);
      }
      i++;
      continue;
    }
    const id = header[1];
    const field = header[2].trim();
    const last = header[3].trim();
    let end = i + 1;
    while (
      end < lines.length &&
      !sHeader.test(lines[end]) &&
      !siteHeader.test(lines[end]) &&
      !trailer.test(lines[end])
    ) end++;
    const body = lines.slice(i + 1, end);
    if (body.some((line) => anchorLine.test(line))) {
      kept.push(...lines.slice(i, end));
      i = end;
      continue;
    }
    const loc = last.match(location);
    let locPath: string | undefined = loc?.[1];
    let start: number | undefined = loc?.[2] === undefined
      ? undefined
      : Number(loc?.[2]);
    let name = field;
    if (locPath === undefined) {
      const rescued = rescueHeader(field, last);
      if (!rescued) {
        failures.push({ path, id, reason: "header has no counterpart path" });
        kept.push(...lines.slice(i, end));
        i = end;
        continue;
      }
      locPath = rescued.locPath;
      name = rescued.name;
      start = rescued.start;
    } else if (start === undefined) {
      const named = last.match(funcTrailer);
      if (named) {
        name = named[1];
        if (named[2] !== undefined) start = Number(named[2]);
      }
    }
    let source: string | undefined;
    try {
      source = await sourceText(locPath);
    } catch {
      failures.push({ path, id, reason: `cannot read ${locPath}` });
      kept.push(...lines.slice(i, end));
      i = end;
      continue;
    }
    const migration = migrateEntry(
      source,
      name,
      start,
      locPath,
      body.join("\n"),
    );
    if (!migration.ok) {
      failures.push({ path, id, reason: migration.reason });
      kept.push(...lines.slice(i, end));
    } else {
      kept.push(`${id} | ${migration.field} | ${locPath}`);
      kept.push(formatAnchor(migration.anchor));
      kept.push(...body);
      if (migration.kind === "message") {
        totals.message++;
        if (migration.numbered) totals.numbered++;
      } else if (migration.kind === "function") totals.function++;
      else totals.deleted++;
      changed = true;
    }
    i = end;
  }
  if (!changed) return;
  totals.files++;
  if (!dryRun) await Deno.writeTextFile(path, kept.join(newline));
}

async function collectProofs(): Promise<string[]> {
  const paths: string[] = [];
  async function walk(dir: string): Promise<void> {
    for await (const entry of Deno.readDir(dir)) {
      const path = `${dir}/${entry.name}`;
      if (entry.isDirectory) await walk(path);
      else if (entry.isFile && /^proof\..+\.txt$/.test(entry.name)) {
        paths.push(path);
      }
    }
  }
  await walk(CHECKS);
  paths.sort();
  return paths;
}

async function main(args: string[]): Promise<void> {
  if (args.some((arg) => arg !== "--dry-run")) {
    console.error(USAGE);
    Deno.exit(2);
  }
  const dryRun = args.includes("--dry-run");
  const totals: Totals = {
    files: 0,
    message: 0,
    numbered: 0,
    function: 0,
    deleted: 0,
    sha: 0,
    tally: 0,
  };
  const failures: Failure[] = [];
  for (const path of await collectProofs()) {
    await migrateFile(path, dryRun, totals, failures);
  }
  if (dryRun) console.log("dry run: no files written");
  console.log(`files changed: ${totals.files}`);
  console.log(
    `message anchors: ${totals.message} (with #n: ${totals.numbered})`,
  );
  console.log(`function anchors: ${totals.function}`);
  console.log(`deleted anchors: ${totals.deleted}`);
  console.log(`failures: ${failures.length}`);
  for (const failure of failures) {
    console.log(`  ${failure.path} ${failure.id}: ${failure.reason}`);
  }
  console.log(`removed SHA lines: ${totals.sha}`);
  console.log(`removed Tally lines: ${totals.tally}`);
}

if (import.meta.main) await main(Deno.args);
