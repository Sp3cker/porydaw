// Read-only index over checked-in proof.*.txt files. The proofs remain authoritative.
import {
  functionName,
  literalPattern,
  parseAnchorLine,
  parsePredicateHeader,
  resolveAnchor,
} from "./proof_anchor.ts";
import type { Anchor, PredicateHeader } from "./proof_anchor.ts";
const CHECKS = "src/checks";
const HELP = `usage: deno task proof <command> [options]
  list [--area <path>] [--status <label>] [--no-swift]
      List proofs, their original C++ paths, and disposition counts.
  show <source-or-proof-path> [A###|S###|Original N|header] [--status <label>] [--full]
      Show a bounded index, one entry (long source context abbreviated), or safety metadata.
      --full prints all source context for a single entry.
      Showing an S entry also prints its live resolved source location.
  sites <source-or-proof-path> [--status <label>] [--offset <number>]
  sites --area <path> [--status <label>] [--offset <number>]
      Page through site IDs, dispositions, mapping reasons, and original expressions.
  search <literal> [--area <path>] [--status <label>] [--no-swift]
      Search C++ sites, Swift predicates, and proof preambles. With --status,
      search only C++ sites of that disposition.
  check [--executed [dir]]
      Check proof structure and resolve every anchor against its source file.
      With --executed, also classify each anchor against the JSON evidence in
      dir (default build/proof-evidence) written by the verify lanes.

An S entry names its predicate without a line number and carries one Anchor: line:
  S012 | drawerAutomationHitGeometry | src/checks/automation/automationcanvaslayout.swift
  Anchor: message "the requested automation height never falls under the minimum"
  Anchor: message "shared literal" #2
      Selects the nth occurrence of a repeated message literal in the function.
  Anchor: function
      Only the enclosing function is anchored.
  Anchor: deleted
      The cited file no longer exists; the entry is historical.

To preview or apply an exact edit to one proof entry: deno task proof:edit --help

Paths are relative to src/checks; an unambiguous C++ basename also works.
Examples:
  deno task proof list --area clipboard --status GAP
  deno task proof show clipboard/clipcheck_merge.cpp A035
  deno task proof show clipboard/clipcheck_merge.cpp S004
  deno task proof sites clipboard/clipcheck_merge.cpp --status PARTIAL
  deno task proof sites --area automation/domain --status PARTIAL --offset 20
  deno task proof show automation/automationmenus.cpp header
  deno task proof search "report.expect" --area clipboard
  deno task proof check --executed`;

interface Entry {
  id: string;
  label: string;
  line: number;
  // Exclusive zero-based boundary in the original file's line array.
  endIndex: number;
  text: string;
}

interface Site extends Entry {
  status: string;
}

interface Predicate extends Entry {
  header: PredicateHeader | undefined;
  anchor: Anchor | undefined;
}

interface Proof {
  path: string;
  original: string;
  revision: string;
  hash: string;
  swift: string[];
  preamble: string[];
  sites: Site[];
  predicates: Predicate[];
  errors: string[];
}

// These labels occur in the existing corpus. A new classification needs an explicit review.
const DISPOSITIONS: Record<string, true> = {
  GAP: true,
  MATCHED: true,
  PARTIAL: true,
  NATIVE: true,
  "NATIVE-SETUP": true,
  "RETIRED-BACKEND-MECHANISM": true,
  "RETIRED-ROLE-PROTOCOL": true,
  "RETIRED-REPRESENTATION": true,
  "DEFERRED-KEYBOARD": true,
};
const siteHeader = /^(A\d+\s*\|\s*.+|Original\s+\d+)\s*$/;
const predicateHeader = /^(S\d+)\s*\|\s*.+$/;
const trailer =
  /^(?:Swift assertion predicates|Remaining original source|Shared helpers|Remaining source|Swift predicates)\s*(?:\(|:|$)/;
const safetyLine =
  /^(?:Deleted in:|Note:|Scope:|Covered native implementation:|Verification:|Command:|Result:|Execution boundary:|Original C\+\+ file |(?:No|Zero) assertion sites[.:]|The deleted .+ contains zero assertion sites:)/i;
const zeroSiteDeclaration = /^(?:No|Zero) assertion sites(?:[.:]|$)/i;

function field(text: string, label: string): string | undefined {
  return text.match(new RegExp(`^${label}:\\s*(.+)$`, "m"))?.[1];
}

function parseProof(path: string, text: string): Proof {
  const lines = text.split(/\r?\n/);
  const original = field(text, "Original") ?? "";
  const revision = field(text, "Reference revision") ?? "";
  const hash = field(text, "Original SHA-256") ?? "";
  const swift = [
    ...text.matchAll(/^(?:Additional )?Swift counterpart:\s*(.+)$/gm),
  ]
    .map((match) => match[1]);
  const proof: Proof = {
    path,
    original,
    revision,
    hash,
    swift,
    preamble: [],
    sites: [],
    predicates: [],
    errors: [],
  };
  for (
    const [name, value] of [["Original", original], [
      "Reference revision",
      revision,
    ], ["Original SHA-256", hash]] as const
  ) {
    if (!value) proof.errors.push(`missing ${name}`);
  }
  if (hash && !/^[0-9a-f]{64}$/i.test(hash)) {
    proof.errors.push("invalid Original SHA-256");
  }
  if (!swift.length) proof.errors.push("missing Swift counterpart header");
  if (!/^Assertion correspondence: /m.test(text)) {
    proof.errors.push("missing correspondence header");
  }

  const siteLines: number[] = [];
  const predicateLines: number[] = [];
  for (let i = 0; i < lines.length; ++i) {
    if (siteHeader.test(lines[i])) siteLines.push(i);
    if (predicateHeader.test(lines[i])) predicateLines.push(i);
  }
  const firstEntry = Math.min(
    siteLines[0] ?? lines.length,
    predicateLines[0] ?? lines.length,
  );
  proof.preamble = lines.slice(0, firstEntry);
  const declaredZeroSites = proof.preamble.some((line) =>
    zeroSiteDeclaration.test(line)
  );
  if (!siteLines.length && !declaredZeroSites) {
    proof.errors.push(
      "no assertion entries or explicit zero-site inventory declaration",
    );
  }
  if (siteLines.length && declaredZeroSites) {
    proof.errors.push("zero-site declaration contradicts assertion entries");
  }
  const starts = [...siteLines, ...predicateLines].sort((a, b) => a - b);
  const ends = new Map<number, number>();
  for (let index = 0; index < starts.length; ++index) {
    const start = starts[index];
    let end = starts[index + 1] ?? lines.length;
    for (let i = start + 1; i < end; ++i) {
      if (trailer.test(lines[i])) {
        end = i;
        break;
      }
    }
    ends.set(start, end);
  }
  if (
    predicateLines.length && siteLines.some((line) => line > predicateLines[0])
  ) {
    proof.errors.push("assertion site follows a Swift predicate");
  }
  let malformedSiteDisposition = false;
  const seen = new Set<string>();
  for (let index = 0; index < siteLines.length; ++index) {
    const start = siteLines[index];
    const end = ends.get(start)!;
    const block = lines.slice(start, end);
    const label = lines[start].trim();
    const id = label.match(/^A\d+/)?.[0] ??
      label.match(/^Original\s+\d+/)?.[0] ?? label;
    const dispositions = block.flatMap((line) =>
      line.match(/^Disposition:\s*(\S+)/)?.[1] ?? []
    );
    if (seen.has(id)) proof.errors.push(`duplicate ${id} at line ${start + 1}`);
    seen.add(id);
    if (dispositions.length !== 1) {
      malformedSiteDisposition = true;
      proof.errors.push(
        `${id} at line ${
          start + 1
        }: expected one disposition, found ${dispositions.length}`,
      );
    }
    const status = dispositions[0] ?? "UNCLASSIFIED";
    if (dispositions.length === 1 && !Object.hasOwn(DISPOSITIONS, status)) {
      proof.errors.push(
        `${id} at line ${start + 1}: unknown disposition ${status}`,
      );
    }
    proof.sites.push({
      id,
      label,
      status,
      line: start + 1,
      endIndex: end,
      text: block.join("\n").trimEnd(),
    });
  }
  const actualDispositions =
    lines.filter((line) => /^Disposition:\s*\S+/.test(line)).length;
  if (actualDispositions !== siteLines.length && !malformedSiteDisposition) {
    proof.errors.push(
      `${actualDispositions} dispositions for ${siteLines.length} site headers`,
    );
  }
  for (let i = 0; i < lines.length; ++i) {
    if (lines[i].startsWith("Tally:")) {
      proof.errors.push(`obsolete Tally: line at line ${i + 1}`);
    } else if (/^(?:Additional )?Swift SHA-256:/.test(lines[i])) {
      proof.errors.push(`obsolete Swift SHA-256 line at line ${i + 1}`);
    }
  }
  for (let index = 0; index < predicateLines.length; ++index) {
    const start = predicateLines[index];
    const end = ends.get(start)!;
    const label = lines[start].trim();
    const id = label.match(/^S\d+/)![0];
    if (seen.has(id)) proof.errors.push(`duplicate ${id} at line ${start + 1}`);
    seen.add(id);
    const block = lines.slice(start, end);
    const header = parsePredicateHeader(label);
    let anchor: Anchor | undefined;
    if (!header) {
      proof.errors.push(
        `${id} at line ${start + 1}: invalid predicate header`,
      );
    } else if (/:\d+$/.test(header.path)) {
      proof.errors.push(
        `${id} at line ${start + 1}: old line-numbered predicate header`,
      );
    }
    const anchors = block.filter((line) => line.startsWith("Anchor:"));
    if (anchors.length !== 1) {
      proof.errors.push(
        `${id} at line ${
          start + 1
        }: expected one Anchor: line, found ${anchors.length}`,
      );
    } else {
      const parsed = parseAnchorLine(anchors[0]);
      if (!parsed) {
        proof.errors.push(
          `${id} at line ${start + 1}: invalid Anchor: line`,
        );
      } else anchor = parsed;
    }
    proof.predicates.push({
      id,
      label,
      line: start + 1,
      endIndex: end,
      text: block.join("\n").trimEnd(),
      header,
      anchor,
    });
  }
  return proof;
}

async function loadProofs(area?: string): Promise<Proof[]> {
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
  const scope = area?.replace(/^src\/checks\//, "").replace(/\/$/, "");
  if (
    scope &&
    scope.split("/").some((part) => !part || part === "." || part === "..")
  ) {
    throw new Error(`invalid proof area ${area}`);
  }
  try {
    await walk(scope ? `${CHECKS}/${scope}` : CHECKS);
  } catch (error) {
    if (!scope || !(error instanceof Deno.errors.NotFound)) throw error;
    return [];
  }
  paths.sort();
  return await Promise.all(
    paths.map(async (path) => parseProof(path, await Deno.readTextFile(path))),
  );
}

interface Options {
  positionals: string[];
  area?: string;
  status?: string;
  noSwift: boolean;
  full: boolean;
  offset?: number;
  executed?: string;
}

function options(args: string[]): Options {
  const parsed: Options = { positionals: [], noSwift: false, full: false };
  for (let i = 0; i < args.length; ++i) {
    const arg = args[i];
    if (arg === "--no-swift") parsed.noSwift = true;
    else if (arg === "--full") parsed.full = true;
    else if (arg === "--executed") {
      const value = args[i + 1];
      if (value !== undefined && !value.startsWith("--")) {
        parsed.executed = value;
        ++i;
      } else parsed.executed = "build/proof-evidence";
    } else if (arg === "--offset") {
      const value = args[++i];
      if (
        value === undefined || !/^(?:0|[1-9]\d*)$/.test(value) ||
        !Number.isSafeInteger(Number(value))
      ) {
        throw new Error("--offset requires a nonnegative safe integer");
      }
      parsed.offset = Number(value);
    } else if (arg === "--area" || arg === "--status") {
      const value = args[++i];
      if (!value || value.startsWith("--")) {
        throw new Error(`${arg} needs a value`);
      }
      if (arg === "--area") {
        parsed.area = value.replace(/^src\/checks\//, "").replace(/\/$/, "");
      } else parsed.status = value.toUpperCase();
    } else if (arg.startsWith("--")) throw new Error(`unknown option ${arg}`);
    else parsed.positionals.push(arg);
  }
  if (parsed.status && !Object.hasOwn(DISPOSITIONS, parsed.status)) {
    throw new Error(
      `unknown disposition ${parsed.status}; use one of ${
        Object.keys(DISPOSITIONS).join(", ")
      }`,
    );
  }
  return parsed;
}

function matchingProofs(
  proofs: Proof[],
  area?: string,
  status?: string,
  noSwift = false,
): Proof[] {
  return proofs.filter((proof) => {
    const path = proof.path.slice(CHECKS.length + 1);
    return (!area || path === area || path.startsWith(`${area}/`)) &&
      (!status || proof.sites.some((site) => site.status === status)) &&
      (!noSwift || proof.swift.every((name) => /^(?:none|n\/a)/i.test(name)));
  });
}

function dispositionCounts(sites: readonly Site[]): Map<string, number> {
  const tally = new Map<string, number>();
  for (const site of sites) {
    tally.set(site.status, (tally.get(site.status) ?? 0) + 1);
  }
  return tally;
}

function counts(sites: readonly Site[]): string {
  const tally = dispositionCounts(sites);
  const core = ["MATCHED", "PARTIAL", "GAP", "NATIVE"];
  const labels = [
    ...core,
    ...[...tally.keys()].filter((status) => !core.includes(status)).sort(),
  ];
  return labels.map((status) => `${status} ${tally.get(status) ?? 0}`).join(
    ", ",
  );
}

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

function mappingIds(site: Site): string[] {
  const mapping = site.text.split("\n").filter((line) =>
    /^(?:Mapping|Mapping\/reason):/.test(line)
  ).join("\n");
  return citedPredicateIds(mapping);
}

function resolveProof(proofs: Proof[], requested: string): Proof {
  const name = requested.replace(/^src\/checks\//, "");
  const matches = proofs.filter((proof) =>
    proof.original.replace(/^src\/checks\//, "") === name ||
    proof.path.slice(CHECKS.length + 1) === name ||
    proof.original.endsWith(`/${name}`)
  );
  if (matches.length === 1) return matches[0];
  const candidates = matches.length
    ? matches
    : proofs.filter((proof) =>
      proof.original.includes(name) || proof.path.includes(name)
    );
  const suggestions = candidates.slice(0, 5).map((proof) => proof.original)
    .join(", ");
  throw new Error(
    `${requested}: ${matches.length ? "ambiguous proof" : "proof not found"}${
      suggestions ? `; try ${suggestions}` : ""
    }`,
  );
}

async function loadProof(requested: string): Promise<Proof> {
  const name = requested.replace(/^src\/checks\//, "");
  const separator = name.lastIndexOf("/");
  if (separator > 0) {
    const scoped = await loadProofs(name.slice(0, separator));
    try {
      return resolveProof(scoped, requested);
    } catch {
      // A historical original may live beside a differently named proof.
    }
  }
  return resolveProof(await loadProofs(), requested);
}

async function readSource(
  cache: Map<string, string | undefined>,
  path: string,
): Promise<string | undefined> {
  if (!cache.has(path)) {
    try {
      cache.set(path, await Deno.readTextFile(path));
    } catch {
      cache.set(path, undefined);
    }
  }
  return cache.get(path);
}

interface EvidencePass {
  cppId: string;
  row: string;
}

interface EvidenceFile {
  passes: EvidencePass[];
  functions: string[];
}

async function loadEvidence(dir: string): Promise<EvidenceFile[]> {
  const paths: string[] = [];
  try {
    for await (const entry of Deno.readDir(dir)) {
      if (entry.isFile && entry.name.endsWith(".json")) {
        paths.push(`${dir}/${entry.name}`);
      }
    }
  } catch {
    throw new Error(
      `no proof evidence in ${dir}; run the verify lanes first`,
    );
  }
  if (!paths.length) {
    throw new Error(
      `no proof evidence in ${dir}; run the verify lanes first`,
    );
  }
  paths.sort();
  const files: EvidenceFile[] = [];
  for (const path of paths) {
    const data = JSON.parse(await Deno.readTextFile(path)) as {
      passes?: { cppId?: unknown; row?: unknown }[];
      functions?: unknown[];
    };
    files.push({
      passes: (data.passes ?? []).filter((pass) =>
        typeof pass.cppId === "string" && typeof pass.row === "string"
      ) as EvidencePass[],
      functions: (data.functions ?? []).filter((name) =>
        typeof name === "string"
      ) as string[],
    });
  }
  return files;
}

type AnchorVerdict = "executed" | "not executed" | "unverifiable";

function classifyPredicates(
  proofs: readonly Proof[],
  evidence: readonly EvidenceFile[],
): Map<string, AnchorVerdict> {
  const rows = evidence.flatMap((file) => file.passes.map((pass) => pass.row));
  const functions = new Set(
    evidence.flatMap((file) => file.functions).map((name) =>
      name.split("::").at(-1)!
    ),
  );
  const verdicts = new Map<string, AnchorVerdict>();
  for (const proof of proofs) {
    for (const predicate of proof.predicates) {
      const header = predicate.header;
      const anchor = predicate.anchor;
      if (!header || !anchor || anchor.kind === "deleted") continue;
      const key = `${proof.path} ${predicate.id}`;
      if (header.path.endsWith(".qml")) {
        const name = functionName(header.functionField);
        verdicts.set(
          key,
          !name.startsWith("test_")
            ? "unverifiable"
            : functions.has(name)
            ? "executed"
            : "not executed",
        );
      } else if (anchor.kind === "message") {
        const pattern = new RegExp(
          literalPattern(anchor.literal).source.replace(/\$$/, ""),
        );
        verdicts.set(
          key,
          rows.some((row) => pattern.test(row)) ? "executed" : "not executed",
        );
      } else {
        verdicts.set(key, "unverifiable");
      }
    }
  }
  return verdicts;
}

export { counts, loadProof, loadProofs, parseProof, resolveProof };
export type { Entry, Predicate, Proof, Site };

function printSafety(proof: Proof, full = false): void {
  const lines = proof.preamble.flatMap((text, index) =>
    safetyLine.test(text) ? [{ line: index + 1, text }] : []
  );
  const priority = (text: string): number =>
    /^(?:Scope:|Deleted in:|Original C\+\+ file |Covered native implementation:)/i
        .test(text)
      ? 0
      : /^(?:Execution boundary:|Result:|Verification:\s*\S)/i.test(text)
      ? 1
      : 2;
  const chosen = full
    ? lines
    : [...lines].sort((a, b) =>
      priority(a.text) - priority(b.text) || a.line - b.line
    ).slice(0, 3);
  for (const { line, text } of chosen) {
    console.log(`${proof.path}:${line} ${text}`);
  }
  if (!full && lines.length > chosen.length) {
    console.log(
      `… ${
        lines.length - chosen.length
      } more safety lines; use 'show ${proof.original} header'`,
    );
  }
}

async function show(
  proofs: Proof[],
  requested: string,
  entryId?: string,
  status?: string,
  full = false,
): Promise<void> {
  const proof = resolveProof(proofs, requested);
  const sites = status
    ? proof.sites.filter((site) => site.status === status)
    : proof.sites;
  if (!entryId || entryId.toLowerCase() === "header") {
    console.log(
      `${proof.path} → ${proof.original}\nreference ${proof.revision}; file totals: ${
        counts(proof.sites)
      }`,
    );
    console.log(
      `Swift: ${
        proof.swift.join(", ")
      }; Swift predicates indexed: ${proof.predicates.length}`,
    );
    if (entryId) {
      printSafety(proof, true);
      return;
    }
    printSafety(proof);
  }
  if (entryId) {
    console.log(
      `${proof.path} → ${proof.original}; reference ${proof.revision}`,
    );
    for (const [index, line] of proof.preamble.entries()) {
      if (/^(?:Scope:|Deleted in:)/i.test(line)) {
        console.log(`${proof.path}:${index + 1} ${line}`);
      }
    }
    const entry = [...proof.sites, ...proof.predicates].find((item) =>
      item.id.toUpperCase() === entryId.toUpperCase()
    );
    if (!entry) {
      const ids = [...proof.sites, ...proof.predicates].filter((item) =>
        item.id.toUpperCase().startsWith(entryId[0].toUpperCase())
      ).map((item) => item.id);
      throw new Error(
        `${entryId}: entry not found${
          ids.length
            ? `; available ${ids.slice(0, 8).join(", ")}${
              ids.length > 8 ? ", …" : ""
            }`
            : ""
        }`,
      );
    }
    const selectedSite = proof.sites.find((site) => site.id === entry.id);
    if (status && selectedSite && selectedSite.status !== status) {
      console.log(
        `${entry.id} is ${selectedSite.status}, not ${status}; showing requested entry`,
      );
    }
    const lines = entry.text.split("\n");
    const contextStart = lines.findIndex((line) =>
      /^Source context since previous assertion:/.test(line)
    );
    if (!full && contextStart !== -1 && lines.length > 80) {
      const expression = lines.findIndex((line, index) =>
        index > contextStart && /^Original expression:/.test(line)
      );
      const endStart = expression >= 0 && lines.length - expression <= 30
        ? expression
        : Math.max(contextStart, lines.length - 30);
      console.log(
        `\n${proof.path}:${entry.line}\n${
          lines.slice(0, contextStart).join("\n")
        }`,
      );
      let previous = contextStart;
      const windows = expression >= 0 && expression < endStart
        ? [[expression, Math.min(expression + 4, endStart)], [
          endStart,
          lines.length,
        ]]
        : [[endStart, lines.length]];
      for (const [from, to] of windows) {
        console.log(
          `… ${
            from - previous
          } source-context lines omitted; use --full\n${proof.path}:${
            entry.line + from
          }\n${lines.slice(from, to).join("\n")}`,
        );
        previous = to;
      }
    } else console.log(`\n${proof.path}:${entry.line}\n${entry.text}`);
    const predicate = proof.predicates.find((item) => item.id === entry.id);
    if (predicate) {
      if (!predicate.header || !predicate.anchor) {
        console.log("resolution failed: entry has structure errors");
      } else if (predicate.anchor.kind === "deleted") {
        console.log(
          `historical entry; ${predicate.header.path} no longer exists`,
        );
      } else {
        let source: string | undefined;
        try {
          source = await Deno.readTextFile(predicate.header.path);
        } catch {
          source = undefined;
        }
        const resolution = resolveAnchor(
          source,
          predicate.header.functionField,
          predicate.anchor,
        );
        if (resolution.ok) {
          console.log(`resolved: ${predicate.header.path}:${resolution.line}`);
        } else console.log(`resolution failed: ${resolution.reason}`);
      }
    }
    return;
  }
  if (status) {
    console.log(
      `Displaying ${status}: ${sites.length} of ${proof.sites.length} C++ sites`,
    );
  }
  for (const site of sites.slice(0, 20)) {
    const reason =
      site.text.match(/^(?:Mapping\/reason|Mapping|Swift):\s*(.+)$/m)?.[1] ??
        "";
    console.log(
      `${site.id.padEnd(12)} ${
        site.status.padEnd(30)
      } ${proof.path}:${site.line}  ${reason}`,
    );
  }
  if (sites.length > 20) {
    console.log(
      `… ${sites.length - 20} more; narrow with --status or an entry ID`,
    );
  }
}

function clippedExcerpt(value: string): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized.length > 260 ? `${normalized.slice(0, 260)}…` : normalized;
}

function sites(
  proofs: Proof[],
  requested?: string,
  area?: string,
  status?: string,
  offset = 0,
): void {
  const selected = requested
    ? [resolveProof(proofs, requested)]
    : matchingProofs(proofs, area);
  let total = 0;
  for (const proof of selected) {
    for (const site of proof.sites) {
      if (status && site.status !== status) continue;
      if (total++ < offset || total > offset + 20) continue;
      const lines = site.text.split("\n");
      const reason =
        site.text.match(/^(?:Mapping\/reason|Mapping|Swift):\s*(.*)$/m)?.[1] ??
          "(no labeled mapping)";
      const expression = lines.findIndex((line) =>
        line.startsWith("Original expression:")
      );
      const mapping = expression >= 0
        ? -1
        : lines.findIndex((line) =>
          /^(?:Mapping\/reason|Mapping|Swift):/.test(line)
        );
      const expressionStart = expression >= 0
        ? expression + 1
        : mapping >= 0
        ? mapping + 1
        : -1;
      let snippetStart = expressionStart;
      while (
        snippetStart >= 0 && snippetStart < lines.length &&
        !lines[snippetStart].trim()
      ) ++snippetStart;
      const expressionLines: string[] = [];
      for (
        let i = snippetStart;
        i >= 0 && i < lines.length && expressionLines.length < 3;
        ++i
      ) {
        if (!lines[i].trim()) break;
        expressionLines.push(lines[i]);
      }
      const excerpt = expressionLines.join(" ");
      console.log(`${proof.path}:${site.line} ${site.id} ${site.status}`);
      const unprovedAt = reason.toLowerCase().indexOf("unproved:");
      const summary = unprovedAt < 0
        ? reason
        : reason.slice(0, unprovedAt).replace(/;\s*$/, "");
      console.log(`  why: ${clippedExcerpt(summary)}`);
      if (unprovedAt >= 0) {
        console.log(
          `  unproved: ${
            clippedExcerpt(reason.slice(unprovedAt + "unproved:".length))
          }`,
        );
      }
      if (excerpt) {
        console.log(
          `  expr ${proof.path}:${site.line + snippetStart}: ${
            clippedExcerpt(excerpt)
          }`,
        );
      } else {
        console.log(
          `  expr: (not indexed; use 'show ${proof.path} ${site.id} --full')`,
        );
      }
    }
  }
  console.log(
    `Displaying ${
      Math.max(0, Math.min(20, total - offset))
    } of ${total} C++ sites${status ? ` (${status})` : ""}`,
  );
  if (total > offset + 20) console.log(`Next page: --offset ${offset + 20}`);
}

function search(
  proofs: Proof[],
  literal: string,
  area?: string,
  status?: string,
  noSwift = false,
): void {
  const needle = literal.toLowerCase();
  let hits = 0;
  function emit(
    proof: Proof,
    id: string,
    kind: string,
    line: number,
    text: string,
  ): void {
    ++hits;
    if (hits > 30) return;
    const snippet = text.trim();
    console.log(
      `${proof.path}:${line} ${id} ${kind}  ${
        snippet.length > 220 ? `${snippet.slice(0, 220)}…` : snippet
      }`,
    );
  }
  for (const proof of matchingProofs(proofs, area, status, noSwift)) {
    if (!status) {
      for (const [index, line] of proof.preamble.entries()) {
        if (line.toLowerCase().includes(needle)) {
          emit(proof, "header", "META", index + 1, line);
        }
      }
    }
    for (const site of proof.sites) {
      if (status && site.status !== status) continue;
      const lines = site.text.split("\n");
      const index = lines.findIndex((line) =>
        line.toLowerCase().includes(needle)
      );
      if (index !== -1) {
        emit(proof, site.id, site.status, site.line + index, lines[index]);
      }
    }
    if (!status) {
      for (const predicate of proof.predicates) {
        const lines = predicate.text.split("\n");
        const index = lines.findIndex((line) =>
          line.toLowerCase().includes(needle)
        );
        if (index !== -1) {
          emit(
            proof,
            predicate.id,
            "SWIFT",
            predicate.line + index,
            lines[index],
          );
        }
      }
    }
  }
  if (hits > 30) {
    console.log(`… ${hits - 30} more; narrow with --area or --status`);
  }
  console.log(`${hits} matching entries`);
}

async function main(args: string[]): Promise<void> {
  const [command, ...rest] = args;
  if (!command || command === "--help" || command === "help") {
    console.log(HELP);
    return;
  }
  if (!["list", "show", "sites", "search", "check"].includes(command)) {
    throw new Error(`unknown command ${command}`);
  }
  const { positionals, area, status, noSwift, full, offset, executed } =
    options(
      rest,
    );
  let invalid = false;
  switch (command) {
    case "check":
      invalid = !!(positionals.length || area || status || noSwift || full ||
        offset !== undefined);
      break;
    case "list":
      invalid = !!(positionals.length || full || offset !== undefined ||
        executed !== undefined);
      break;
    case "show":
      invalid = positionals.length < 1 || positionals.length > 2 ||
        !!area || noSwift || offset !== undefined || executed !== undefined ||
        (full && positionals.length !== 2);
      break;
    case "sites":
      invalid = positionals.length > 1 ||
        (positionals.length === 1) === (area !== undefined) ||
        noSwift || full || executed !== undefined;
      break;
    case "search":
      invalid = positionals.length !== 1 || full || offset !== undefined ||
        executed !== undefined;
      break;
  }
  if (invalid) {
    throw new Error(
      `invalid arguments for ${command}; use deno task proof --help`,
    );
  }
  const proofs =
    command === "show" || (command === "sites" && positionals.length)
      ? [await loadProof(positionals[0])]
      : await loadProofs(area);
  if (command === "check") {
    const errors = proofs.flatMap((proof) =>
      proof.errors.map((error) => `${proof.path}: ${error}`)
    );
    const cache = new Map<string, string | undefined>();
    let anchors = 0;
    let deleted = 0;
    for (const proof of proofs) {
      const byId = new Map(proof.predicates.map((predicate) => [
        predicate.id,
        predicate,
      ]));
      for (const predicate of proof.predicates) {
        if (!predicate.header || !predicate.anchor) continue;
        if (predicate.anchor.kind === "deleted") {
          ++deleted;
          continue;
        }
        const source = await readSource(cache, predicate.header.path);
        const resolution = resolveAnchor(
          source,
          predicate.header.functionField,
          predicate.anchor,
        );
        if (resolution.ok) ++anchors;
        else errors.push(`${proof.path} ${predicate.id}: ${resolution.reason}`);
      }
      for (const site of proof.sites) {
        if (site.status !== "MATCHED" && site.status !== "PARTIAL") continue;
        for (const cited of mappingIds(site)) {
          if (byId.get(cited)?.anchor?.kind === "deleted") {
            errors.push(
              `${proof.path} ${site.id}: cites deleted predicate ${cited}`,
            );
          }
        }
      }
    }
    if (errors.length) {
      throw new Error(
        `${errors.join("\n")}\n${errors.length} proof check error(s)`,
      );
    }
    const sites = proofs.reduce((sum, proof) => sum + proof.sites.length, 0);
    console.log(
      `${proofs.length} proof files; ${sites} indexed C++ sites; ${anchors} anchors resolved (${deleted} historical)`,
    );
    if (executed !== undefined) {
      const evidence = await loadEvidence(executed);
      const verdicts = classifyPredicates(proofs, evidence);
      let ran = 0;
      let missing = 0;
      let unverifiable = 0;
      for (const verdict of verdicts.values()) {
        if (verdict === "executed") ++ran;
        else if (verdict === "not executed") ++missing;
        else ++unverifiable;
      }
      console.log(
        `execution evidence from ${executed}: executed ${ran}; not executed ${missing}; unverifiable ${unverifiable}`,
      );
      for (const proof of proofs) {
        for (const predicate of proof.predicates) {
          const key = `${proof.path} ${predicate.id}`;
          if (verdicts.get(key) === "not executed") {
            console.log(`${key}: not executed`);
          }
        }
      }
      const uncovered: string[] = [];
      for (const proof of proofs) {
        for (const site of proof.sites) {
          if (site.status !== "MATCHED") continue;
          const cited = mappingIds(site).filter((id) =>
            verdicts.has(`${proof.path} ${id}`)
          );
          if (
            cited.length &&
            cited.every((id) =>
              verdicts.get(`${proof.path} ${id}`) !== "executed"
            ) &&
            cited.some((id) =>
              verdicts.get(`${proof.path} ${id}`) === "not executed"
            )
          ) {
            uncovered.push(
              `${proof.path} ${site.id}: no executed predicate among ${
                cited.join(", ")
              }`,
            );
          }
        }
      }
      if (uncovered.length) {
        throw new Error(
          `${
            uncovered.join("\n")
          }\n${uncovered.length} MATCHED site(s) without executed predicates`,
        );
      }
    }
  } else if (command === "show") {
    await show(proofs, positionals[0], positionals[1], status, full);
  } else if (command === "sites") {
    sites(proofs, positionals[0], area, status, offset);
  } else if (command === "list") {
    const selected = matchingProofs(proofs, area, status, noSwift);
    for (const proof of selected.slice(0, 30)) {
      console.log(
        `${proof.path} → ${proof.original}  ${counts(proof.sites)}  Swift: ${
          proof.swift.join(", ")
        }`,
      );
    }
    if (selected.length > 30) {
      console.log(
        `… ${
          selected.length - 30
        } more; narrow with --area, --status, or --no-swift`,
      );
    }
    console.log(`${selected.length} / ${proofs.length} proof files`);
  } else search(proofs, positionals[0], area, status, noSwift);
}

if (import.meta.main) {
  try {
    await main(Deno.args);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    Deno.exitCode = 1;
  }
}
