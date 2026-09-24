// Edit one selected proof section without regenerating or inferring correspondence.
import {
  parseAnchorLine,
  parsePredicateHeader,
  resolveAnchor,
} from "./proof_anchor.ts";
import { counts, loadProof, parseProof } from "./proof_reader.ts";
import type { Entry, Proof, Site } from "./proof_reader.ts";

const HELP =
  `usage: deno task proof:edit <source-or-proof-path> <A###|S###|Original N|header> --before <exact text> --after <replacement> [--apply]
  Preview an exact, unique replacement within one proof entry. --apply writes it.
  A disposition change must also change that site's Mapping or Mapping/reason line.
  An S edit must keep exactly one Anchor: line that resolves to its cited source.
  Closed rows (MATCHED, RETIRED-*, NATIVE-*) stay compact: --apply rejects edits
  that add Source context or Original expression lines back to them, and S edits
  that add body lines beyond header plus Anchor. Stripped C++ is recoverable via
  \`git show <Reference revision>:<Original path>\` from the ledger preamble.
  The command preserves entry IDs and validates proof structure, but cannot prove
  source freshness, execution, or correspondence. Inspect the source first.

Example: deno task proof:edit clipboard/clipcheck_merge.cpp A036 --before 'native view editCursorTick' --after 'native view cursor position'`;

function section(
  proof: Proof,
  id: string,
): { start: number; end: number; site?: Site } {
  if (id.toLowerCase() === "header") {
    return { start: 0, end: proof.preamble.length };
  }
  const entry: Entry | undefined = [...proof.sites, ...proof.predicates].find(
    (item) => item.id.toUpperCase() === id.toUpperCase(),
  );
  if (!entry) throw new Error(`${id}: entry not found in ${proof.path}`);
  const start = entry.line - 1;
  return {
    start,
    end: entry.endIndex,
    site: proof.sites.find((item) => item.id === entry.id),
  };
}

function assertPreserved(
  oldProof: Proof,
  nextProof: Proof,
  oldSite?: Site,
): void {
  if (nextProof.errors.length) {
    throw new Error(`invalid proof: ${nextProof.errors.join("; ")}`);
  }
  const oldIds = [
    ...oldProof.sites.map((site) => site.id),
    ...oldProof.predicates.map((predicate) => predicate.id),
  ];
  const nextIds = [
    ...nextProof.sites.map((site) => site.id),
    ...nextProof.predicates.map((predicate) => predicate.id),
  ];
  if (oldIds.join("\0") !== nextIds.join("\0")) {
    throw new Error(
      "entry IDs changed; assertion/predicate inventory must be preserved",
    );
  }
  if (oldSite) {
    const nextSite = nextProof.sites.find((site) => site.id === oldSite.id)!;
    if (nextSite.status !== oldSite.status) {
      const beforeMapping = oldSite.text.match(
        /^(?:Mapping|Mapping\/reason):.*$/m,
      )?.[0];
      const afterMapping = nextSite.text.match(
        /^(?:Mapping|Mapping\/reason):.*$/m,
      )?.[0];
      if (!afterMapping || beforeMapping === afterMapping) {
        throw new Error(
          "a disposition change requires an updated Mapping or Mapping/reason line in the same edit",
        );
      }
    }
  }
}

function assertCompact(before: string, after: string, status?: string): void {
  if (status !== undefined) {
    if (
      status !== "MATCHED" && !status.startsWith("RETIRED-") &&
      !status.startsWith("NATIVE")
    ) return;
    for (
      const marker of [
        "Source context since previous assertion:",
        "Original expression:",
      ]
    ) {
      if (!before.includes(marker) && after.includes(marker)) {
        throw new Error(
          `closed ${status} rows stay compact: ${marker} belongs in git history, not the ledger`,
        );
      }
    }
    return;
  }
  const bulk = (text: string): number =>
    text.split("\n").slice(1).filter((line) =>
      line.trim() && !line.trim().startsWith("Anchor:")
    ).length;
  if (bulk(after) > bulk(before)) {
    throw new Error(
      "S entries stay compact: header plus one Anchor: line only, no added body lines",
    );
  }
}

async function assertAnchorResolves(changed: string): Promise<void> {
  const changedLines = changed.split("\n");
  const header = parsePredicateHeader(changedLines[0].trim());
  if (!header) {
    throw new Error(
      "edited S entry header must be `S### | function | src/path` without a line suffix",
    );
  }
  const anchors = changedLines.filter((line) =>
    line.trim().startsWith("Anchor:")
  );
  if (anchors.length !== 1) {
    throw new Error(
      `edited S entry must keep exactly one Anchor: line, found ${anchors.length}`,
    );
  }
  const anchor = parseAnchorLine(anchors[0].trim());
  if (!anchor) {
    throw new Error(
      `edited S entry has an unparseable Anchor: line: ${anchors[0].trim()}`,
    );
  }
  let source: string | undefined;
  try {
    source = await Deno.readTextFile(header.path);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    source = undefined;
  }
  if (anchor.kind === "deleted") {
    if (source !== undefined) {
      throw new Error(
        "a deleted anchor is allowed only when the cited file is missing",
      );
    }
    return;
  }
  const resolution = resolveAnchor(source, header.functionField, anchor);
  if (!resolution.ok) {
    throw new Error(
      `edited S entry anchor does not resolve: ${resolution.reason}`,
    );
  }
}

async function replace(
  proof: Proof,
  id: string,
  before: string,
  after: string,
  apply: boolean,
): Promise<void> {
  before = before.replace(/\r\n/g, "\n");
  after = after.replace(/\r\n/g, "\n");
  if (
    !before || before === after || before.length > 2000 ||
    after.length > 2000 ||
    before.includes("\r") || after.includes("\r")
  ) {
    throw new Error(
      "provide distinct exact text (at most 2000 characters each; use LF for line breaks)",
    );
  }
  const source = await Deno.readTextFile(proof.path);
  const current = parseProof(proof.path, source);
  if (current.errors.length) {
    throw new Error(`invalid existing proof: ${current.errors.join("; ")}`);
  }
  const { start, end, site } = section(current, id);
  const newline = source.includes("\r\n") ? "\r\n" : "\n";
  const lines = source.split(/\r?\n/);
  const text = lines.slice(start, end).join("\n");
  const occurrences = text.split(before).length - 1;
  if (occurrences !== 1) {
    throw new Error(
      `${id}: expected one exact match in this entry, found ${occurrences}; use 'deno task proof show ${proof.original} ${id} --full'`,
    );
  }
  const changed = text.replace(before, after);
  const isPredicate = current.predicates.some((predicate) =>
    predicate.id.toUpperCase() === id.toUpperCase()
  );
  if (isPredicate) {
    await assertAnchorResolves(changed);
  }
  const result = [
    ...lines.slice(0, start),
    ...changed.split("\n"),
    ...lines.slice(end),
  ].join(newline);
  const updated = parseProof(proof.path, result);
  assertPreserved(current, updated, site);
  if (apply && (site !== undefined || isPredicate)) {
    assertCompact(
      text,
      changed,
      updated.sites.find((entry) => site !== undefined && entry.id === site.id)
        ?.status,
    );
  }
  console.log(
    `${proof.path}:${start + 1} ${id} ${
      apply ? "applying" : "preview (not written)"
    }`,
  );
  console.log(`- ${JSON.stringify(before)}\n+ ${JSON.stringify(after)}`);
  if (!apply) {
    console.log(
      `Counts before: ${counts(current.sites)}\nCounts proposed: ${
        counts(updated.sites)
      }`,
    );
    if (site) {
      console.log(
        `${site.id}: ${site.status} → ${
          updated.sites.find((entry) => entry.id === site.id)!.status
        }`,
      );
    }
    console.log(
      "Rerun with --apply to write; verify actual source and execution separately.",
    );
    return;
  }
  const directory = proof.path.slice(0, proof.path.lastIndexOf("/"));
  const temporary = await Deno.makeTempFile({
    dir: directory,
    prefix: ".proof-edit-",
  });
  let renamed = false;
  try {
    await Deno.writeTextFile(temporary, result);
    const metadata = await Deno.stat(proof.path);
    if (metadata.mode !== null) {
      await Deno.chmod(temporary, metadata.mode & 0o777);
    }
    if (await Deno.readTextFile(proof.path) !== source) {
      throw new Error(
        "proof changed while preparing the edit; nothing written",
      );
    }
    await Deno.rename(temporary, proof.path);
    renamed = true;
  } finally {
    if (!renamed) {
      try {
        await Deno.remove(temporary);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) {
          console.error(`failed to clean temporary proof: ${error}`);
        }
      }
    }
  }
  const persisted = await Deno.readTextFile(proof.path);
  if (persisted !== result) {
    throw new Error("written proof differs from the requested edit");
  }
  const confirmed = parseProof(proof.path, persisted);
  assertPreserved(current, confirmed, site);
  console.log(`Read-back verified: ${proof.path}:${start + 1} ${id}`);
  console.log(
    `Counts before: ${counts(current.sites)}\nCounts after:  ${
      counts(confirmed.sites)
    }`,
  );
  if (site) {
    console.log(
      `${site.id}: ${site.status} → ${
        confirmed.sites.find((entry) => entry.id === site.id)!.status
      }`,
    );
  }
  console.log(
    "Structure checked; source freshness, execution, and parity not verified.",
  );
}

async function main(args: string[]): Promise<void> {
  if (!args.length || args.includes("--help")) {
    console.log(HELP);
    return;
  }
  const positionals: string[] = [];
  let before: string | undefined;
  let after: string | undefined;
  let apply = false;
  for (let i = 0; i < args.length; ++i) {
    if (args[i] === "--before" || args[i] === "--after") {
      const value = args[++i];
      if (value === undefined) {
        throw new Error("--before and --after require values");
      }
      if (args[i - 1] === "--before") {
        if (before !== undefined) throw new Error("duplicate --before");
        before = value;
      } else {
        if (after !== undefined) throw new Error("duplicate --after");
        after = value;
      }
    } else if (args[i] === "--apply") {
      if (apply) throw new Error("duplicate --apply");
      apply = true;
    } else if (args[i].startsWith("--")) {
      throw new Error(`unknown option ${args[i]}`);
    } else positionals.push(args[i]);
  }
  if (positionals.length !== 2 || before === undefined || after === undefined) {
    throw new Error(
      `expected proof, entry ID, --before and --after; use deno task proof:edit --help`,
    );
  }
  await replace(
    await loadProof(positionals[0]),
    positionals[1],
    before,
    after,
    apply,
  );
}

if (import.meta.main) {
  try {
    await main(Deno.args);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    Deno.exitCode = 1;
  }
}
