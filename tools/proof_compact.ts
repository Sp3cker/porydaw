// Bulk compactor for closed proof-ledger rows. Dry run by default; --apply writes.
//
// Closed rows (MATCHED, RETIRED-*, NATIVE*) keep only their header, Disposition,
// and one mapping line; S rows keep only header + Anchor. Open rows
// (GAP/PARTIAL/DEFERRED-*), preambles' required fields, and trailer regions stay
// intact. Stripped C++ is recoverable via `git show <Reference revision>:<Original path>`
// (SHA-verified per file before rewriting).
import { parseProof } from "./proof_reader.ts";
import type { Predicate, Proof, Site } from "./proof_reader.ts";

const CHECKS = "src/checks";
const HELP = `usage: deno task proof:compact [--apply]
  Dry run compacts every proof ledger in memory and prints per-file and total
  before/after bytes. --apply writes the compacted ledgers via temp+rename.
  Files whose pinned original fails the SHA preflight, files with no A/S
  entries, and files that fail a self-check are skipped (self-check failures
  abort the run without writing anything).`;

const CLOSED = (status: string): boolean =>
  status === "MATCHED" || status.startsWith("RETIRED-") ||
  status.startsWith("NATIVE");

// Copies of proof_reader.ts parsing shapes (reader itself is unchanged).
const safetyLine =
  /^(?:Deleted in:|Note:|Scope:|Covered native implementation:|Verification:|Command:|Result:|Execution boundary:|Original C\+\+ file |(?:No|Zero) assertion sites[.:]|The deleted .+ contains zero assertion sites:)/i;
const fieldLine = /^([A-Z][A-Za-z0-9 .\/()+,*'">_-]*):/;
const continuationLine = /^\s|^[a-z0-9(]/;
const mappingLabel = /^(?:Mapping|Mapping\/reason):/;
const anchorLabel = /^Anchor:/;

function citedPredicateIds(text: string): string[] {
  const ids = new Set<string>();
  for (const match of text.matchAll(/S(\d+)-S(\d+)/g)) {
    const low = Number(match[1]);
    const high = Number(match[2]);
    const width = Math.max(match[1].length, match[2].length);
    for (let n = Math.min(low, high); n <= Math.max(low, high); ++n) {
      ids.add(`S${String(n).padStart(width, "0")}`);
    }
  }
  for (const match of text.matchAll(/S\d+/g)) ids.add(match[0]);
  return [...ids];
}

function citedSiteIds(site: Site): string[] {
  const citations = site.text.split("\n").filter((line) =>
    mappingLabel.test(line)
  ).join("\n");
  return citedPredicateIds(citations);
}

function compactPreamble(preamble: string[]): string[] {
  const kept = new Array<boolean>(preamble.length).fill(false);
  for (let i = 0; i < preamble.length; ++i) {
    const line = preamble[i];
    if (!line.trim()) {
      kept[i] = true;
    } else if (safetyLine.test(line)) {
      kept[i] = true;
    } else {
      const field = line.match(fieldLine);
      if (field && field[1].length <= 32) {
        kept[i] = true;
      } else if (
        i > 0 && kept[i - 1] && preamble[i - 1].trim() &&
        continuationLine.test(line)
      ) {
        kept[i] = true;
      }
    }
  }
  return preamble.filter((_, i) => kept[i]);
}

function compactSite(block: string[]): string[] {
  const disposition = block.find((line) => /^Disposition:\s*\S+/.test(line))!;
  const status = disposition.match(/^Disposition:\s*(\S+)/)![1];
  if (!CLOSED(status)) return block;
  // Closed rows keep only the S-id pin cited by their Mapping lines: every
  // other line of the block is source context, original expression, or
  // mapping prose, all opaque to the tools and recoverable from history.
  // Swift: lines stay out so `proof check` keeps seeing exactly the Mapping
  // citations it validated before (it never read Swift: lines).
  const ids = citedPredicateIds(
    block.filter((line) => mappingLabel.test(line)).join("\n"),
  );
  if (!ids.length) return [block[0], disposition];
  const label = status === "MATCHED" ? "Mapping:" : "Mapping/reason:";
  return [block[0], disposition, `${label} ${ids.join(", ")}`];
}
function compactPredicate(block: string[]): string[] {
  return [block[0], block.find((line) => anchorLabel.test(line))!];
}

function trimBlank(lines: string[]): string[] {
  let start = 0;
  let end = lines.length;
  while (start < end && !lines[start].trim()) ++start;
  while (end > start && !lines[end - 1].trim()) --end;
  return lines.slice(start, end);
}
export function compactText(proof: Proof, lines: string[]): string {
  const entries = [...proof.sites, ...proof.predicates].sort((a, b) =>
    a.line - b.line
  );
  const segments: string[][] = [trimBlank(compactPreamble(proof.preamble))];
  for (let i = 0; i < entries.length; ++i) {
    const entry = entries[i];
    const block = lines.slice(entry.line - 1, entry.endIndex);
    const compacted = "status" in entry
      ? compactSite(block)
      : compactPredicate(block);
    segments.push(trimBlank(compacted.length ? compacted : block));
    const nextStart = entries[i + 1]?.line ?? lines.length + 1;
    const gap = trimBlank(lines.slice(entry.endIndex, nextStart - 1));
    if (gap.length) segments.push(gap);
  }
  return segments.filter((s) => s.length).map((s) => s.join("\n")).join(
    "\n\n",
  ) +
    "\n";
}

function sameSet(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const set = new Set(a);
  return b.every((id) => set.has(id));
}

function selfCheck(path: string, before: Proof, afterText: string): string[] {
  const failures: string[] = [];
  const after = parseProof(path, afterText);
  if (after.errors.length) {
    return [`parse errors: ${after.errors.join("; ")}`];
  }
  const seq = (p: Proof) => p.sites.map((s) => `${s.id} ${s.status}`);
  if (seq(before).join("\0") !== seq(after).join("\0")) {
    failures.push("site id/disposition sequence changed");
  }
  const ids = (p: Proof) => p.predicates.map((p) => p.id);
  if (ids(before).join("\0") !== ids(after).join("\0")) {
    failures.push("predicate id sequence changed");
  }
  for (const site of before.sites) {
    if (!CLOSED(site.status)) continue;
    const next = after.sites.find((s) => s.id === site.id)!;
    if (!sameSet(citedSiteIds(site), citedSiteIds(next))) {
      failures.push(`${site.id}: closed-row S-citations changed`);
    }
  }
  for (const predicate of before.predicates) {
    const next = after.predicates.find((p) => p.id === predicate.id)!;
    const headerOf = (p: Predicate) => p.text.split("\n")[0];
    const anchorOf = (p: Predicate) =>
      p.text.split("\n").find((line) => anchorLabel.test(line));
    if (headerOf(predicate) !== headerOf(next)) {
      failures.push(`${predicate.id}: S header changed`);
    }
    if (anchorOf(predicate) !== anchorOf(next)) {
      failures.push(`${predicate.id}: Anchor line changed`);
    }
  }
  return failures;
}

async function git(args: string[], root: string): Promise<string> {
  const process = new Deno.Command("git", {
    args,
    cwd: root,
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await process.output();
  if (code !== 0) {
    throw new Error(
      `git ${args.join(" ")} failed: ${
        new TextDecoder().decode(stderr).trim()
      }`,
    );
  }
  return new TextDecoder().decode(stdout);
}
async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(data));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function repoRoot(): Promise<string> {
  try {
    return (await git(["rev-parse", "--show-toplevel"], Deno.cwd())).trim();
  } catch {
    return Deno.cwd();
  }
}

async function preflight(
  root: string,
  proof: Proof,
): Promise<string | undefined> {
  const original = proof.original.split(/\s+/)[0];
  if (!original || !proof.revision || !proof.hash) {
    return "unverifiable Original/Reference/SHA field";
  }
  let blob: Uint8Array;
  try {
    const process = new Deno.Command("git", {
      args: ["--no-pager", "show", `${proof.revision}:${original}`],
      cwd: root,
      stdout: "piped",
      stderr: "piped",
    });
    const { code, stdout } = await process.output();
    if (code !== 0) return "pinned original not recoverable via git show";
    blob = stdout;
  } catch {
    return "pinned original not recoverable via git show";
  }
  if ((await sha256Hex(blob)) !== proof.hash.toLowerCase()) {
    return "Original SHA-256 mismatch";
  }
  return undefined;
}

interface Outcome {
  path: string;
  before: number;
  after: number;
  status: string;
  text?: string;
}

async function main(args: string[]): Promise<void> {
  if (args.includes("--help")) {
    console.log(HELP);
    return;
  }
  const apply = args.includes("--apply");
  for (const arg of args) {
    if (arg !== "--apply") throw new Error(`unknown option ${arg}`);
  }
  const root = await repoRoot();
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
  const outcomes: Outcome[] = [];
  let failed = false;
  for (const path of paths) {
    const source = await Deno.readTextFile(path);
    const proof = parseProof(path, source);
    if (proof.errors.length) {
      console.error(`${path}: INVALID (${proof.errors.join("; ")})`);
      failed = true;
      continue;
    }
    if (!proof.sites.length && !proof.predicates.length) {
      outcomes.push({
        path,
        before: source.length,
        after: source.length,
        status: "skipped (no A/S entries)",
      });
      continue;
    }
    const blocked = await preflight(root, proof);
    if (blocked) {
      outcomes.push({
        path,
        before: source.length,
        after: source.length,
        status: `skipped (${blocked})`,
      });
      continue;
    }
    const compacted = compactText(proof, source.split(/\r?\n/));
    const failures = selfCheck(path, proof, compacted);
    if (failures.length) {
      console.error(`${path}: SELF-CHECK FAILED (${failures.join("; ")})`);
      failed = true;
      continue;
    }
    outcomes.push({
      path,
      before: source.length,
      after: compacted.length,
      status: compacted === source ? "unchanged" : "compacted",
      text: compacted === source ? undefined : compacted,
    });
  }
  let totalBefore = 0;
  let totalAfter = 0;
  let rewritten = 0;
  for (const outcome of outcomes) {
    totalBefore += outcome.before;
    totalAfter += outcome.after;
    if (outcome.text !== undefined) ++rewritten;
    const pct = outcome.before
      ? ((100 * (outcome.before - outcome.after)) / outcome.before).toFixed(1)
      : "0.0";
    console.log(
      `${outcome.path}: ${outcome.before} → ${outcome.after} B (-${pct}%) ${outcome.status}`,
    );
  }
  const totalPct = totalBefore
    ? ((100 * (totalBefore - totalAfter)) / totalBefore).toFixed(1)
    : "0.0";
  console.log(
    `${paths.length} proof files; ${rewritten} rewritten; ` +
      `${totalBefore} → ${totalAfter} B (-${totalPct}%)${
        apply ? "" : " (dry run)"
      }`,
  );
  if (failed) {
    throw new Error("self-check failures; nothing written");
  }
  if (apply) {
    for (const outcome of outcomes) {
      if (outcome.text === undefined) continue;
      const source = await Deno.readTextFile(outcome.path);
      const directory = outcome.path.slice(
        0,
        outcome.path.lastIndexOf("/"),
      );
      const temporary = await Deno.makeTempFile({
        dir: directory,
        prefix: ".proof-compact-",
      });
      let renamed = false;
      try {
        await Deno.writeTextFile(temporary, outcome.text);
        const metadata = await Deno.stat(outcome.path);
        if (metadata.mode !== null) {
          await Deno.chmod(temporary, metadata.mode & 0o777);
        }
        if ((await Deno.readTextFile(outcome.path)) !== source) {
          throw new Error(`${outcome.path} changed during compaction`);
        }
        await Deno.rename(temporary, outcome.path);
        renamed = true;
      } finally {
        if (!renamed) await Deno.remove(temporary).catch(() => {});
      }
    }
    console.log(`wrote ${rewritten} files`);
  }
}

if (import.meta.main) {
  try {
    await main(Deno.args);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    Deno.exitCode = 1;
  }
}
