export type Anchor =
  | { kind: "message"; literal: string; occurrence?: number }
  | { kind: "function" }
  | { kind: "deleted" };

export interface PredicateHeader {
  id: string;
  functionField: string;
  path: string;
}

export interface FunctionBody {
  name: string;
  startLine: number;
  endLine: number;
}

export type Resolution = { ok: true; line: number } | {
  ok: false;
  reason: string;
};

const predicateHeaderPattern = /^(S\d+) \| (.+) \| (src\/\S+)$/;
const anchorMessagePattern =
  /^Anchor: message "((?:[^"\\\r\n]|\\.)*)"(?: #(\d+))?$/;
const identifierTokenPattern = /[A-Za-z_$][A-Za-z0-9_$]*/;
const backtickedNamePattern = /^[A-Za-z_][A-Za-z0-9_]*$/;

export function parsePredicateHeader(
  line: string,
): PredicateHeader | undefined {
  const match = predicateHeaderPattern.exec(line);
  if (match === null) return undefined;
  return { id: match[1], functionField: match[2], path: match[3] };
}

export function parseAnchorLine(line: string): Anchor | undefined {
  if (line === "Anchor: function") return { kind: "function" };
  if (line === "Anchor: deleted") return { kind: "deleted" };
  const match = anchorMessagePattern.exec(line);
  if (match === null) return undefined;
  if (match[2] === undefined) return { kind: "message", literal: match[1] };
  return { kind: "message", literal: match[1], occurrence: Number(match[2]) };
}

export function formatAnchor(anchor: Anchor): string {
  if (anchor.kind === "function") return "Anchor: function";
  if (anchor.kind === "deleted") return "Anchor: deleted";
  if (anchor.occurrence === undefined) {
    return `Anchor: message "${anchor.literal}"`;
  }
  return `Anchor: message "${anchor.literal}" #${anchor.occurrence}`;
}

export function functionName(functionField: string): string {
  const scopeIndex = functionField.lastIndexOf("::");
  const tail = scopeIndex < 0
    ? functionField
    : functionField.slice(scopeIndex + 2);
  const stripped = tail.replace(/\s*\(.*\)\s*$/, "");
  return identifierTokenPattern.exec(stripped)?.[0] ?? "";
}

interface BraceState {
  count: number;
}

function skipLineEnd(source: string, i: number): number {
  const newline = source.indexOf("\n", i);
  return newline < 0 ? source.length : newline;
}

function skipNestedComment(source: string, i: number): number {
  let depth = 1;
  let j = i;
  while (j < source.length) {
    if (source[j] === "/" && source[j + 1] === "*") {
      depth++;
      j += 2;
    } else if (source[j] === "*" && source[j + 1] === "/") {
      depth--;
      j += 2;
      if (depth === 0) return j;
    } else {
      j++;
    }
  }
  return source.length;
}

function skipParenCode(
  source: string,
  openParen: number,
  brace: BraceState,
): number {
  let parens = 1;
  let k = openParen + 1;
  while (k < source.length) {
    const skipped = skipElement(source, k, brace);
    if (skipped >= 0) {
      k = skipped;
      continue;
    }
    const c = source[k];
    if (c === "(") parens++;
    else if (c === ")") {
      parens--;
      if (parens === 0) return k + 1;
    } else if (c === "{") brace.count++;
    else if (c === "}") brace.count--;
    k++;
  }
  return source.length;
}

function skipDoubleQuoted(
  source: string,
  i: number,
  brace: BraceState,
): number {
  let j = i + 1;
  while (j < source.length) {
    const c = source[j];
    if (c === "\\") {
      if (source[j + 1] === "(") j = skipParenCode(source, j + 1, brace);
      else j += 2;
      continue;
    }
    if (c === '"') return j + 1;
    if (c === "\n") return j;
    j++;
  }
  return source.length;
}

function skipSingleQuoted(source: string, i: number): number {
  let j = i + 1;
  while (j < source.length) {
    const c = source[j];
    if (c === "\\") {
      j += 2;
      continue;
    }
    if (c === "'") return j + 1;
    if (c === "\n") return j;
    j++;
  }
  return source.length;
}

function skipTemplateExpression(
  source: string,
  j: number,
  brace: BraceState,
): number {
  let depth = 1;
  let k = j;
  while (k < source.length) {
    const skipped = skipElement(source, k, brace);
    if (skipped >= 0) {
      k = skipped;
      continue;
    }
    if (source[k] === "{") depth++;
    else if (source[k] === "}") {
      depth--;
      if (depth === 0) return k + 1;
    }
    k++;
  }
  return source.length;
}

function skipTemplate(source: string, i: number, brace: BraceState): number {
  let j = i + 1;
  while (j < source.length) {
    const c = source[j];
    if (c === "\\") {
      j += 2;
      continue;
    }
    if (c === "`") return j + 1;
    if (c === "$" && source[j + 1] === "{") {
      j = skipTemplateExpression(source, j + 2, brace);
      continue;
    }
    j++;
  }
  return source.length;
}

function skipTripleQuoted(
  source: string,
  i: number,
  brace: BraceState,
): number {
  let j = i + 3;
  while (j < source.length) {
    if (source[j] === "\\") {
      if (source[j + 1] === "(") j = skipParenCode(source, j + 1, brace);
      else j += 2;
      continue;
    }
    if (source.startsWith('"""', j)) return j + 3;
    j++;
  }
  return source.length;
}

function skipRawString(source: string, i: number, brace: BraceState): number {
  let j = i;
  while (source[j] === "#") j++;
  if (j === i) return -1;
  const hashes = source.slice(i, j);
  const triple = source.startsWith('"""', j);
  let closer: string;
  if (triple) {
    closer = `"""${hashes}`;
    j += 3;
  } else if (source[j] === '"') {
    closer = `"${hashes}`;
    j += 1;
  } else {
    return -1;
  }
  while (j < source.length) {
    if (
      source[j] === "\\" && source.startsWith(hashes, j + 1) &&
      source[j + 1 + hashes.length] === "("
    ) {
      j = skipParenCode(source, j + 1 + hashes.length, brace);
      continue;
    }
    if (source.startsWith(closer, j)) return j + closer.length;
    j++;
  }
  return source.length;
}

function skipElement(source: string, j: number, brace: BraceState): number {
  const c = source[j];
  if (c === "/" && source[j + 1] === "/") return skipLineEnd(source, j + 2);
  if (c === "/" && source[j + 1] === "*") {
    return skipNestedComment(source, j + 2);
  }
  if (c === "#") return skipRawString(source, j, brace);
  if (c === '"' && source.startsWith('"""', j)) {
    return skipTripleQuoted(source, j, brace);
  }
  if (c === '"') return skipDoubleQuoted(source, j, brace);
  if (c === "'") return skipSingleQuoted(source, j);
  if (c === "`") return skipTemplate(source, j, brace);
  return -1;
}

function isIdentStart(code: number): boolean {
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) ||
    code === 95 ||
    code === 36;
}

function isIdentCharCode(code: number): boolean {
  return isIdentStart(code) || (code >= 48 && code <= 57);
}

function isIdentChar(value: string | undefined): boolean {
  if (value === undefined || value === "") return false;
  return isIdentCharCode(value.charCodeAt(0));
}

function readIdentifier(
  source: string,
  j: number,
): { name: string; next: number } | undefined {
  if (source[j] === "`") {
    const end = source.indexOf("`", j + 1);
    if (end < 0) return undefined;
    const raw = source.slice(j + 1, end);
    if (!backtickedNamePattern.test(raw)) return undefined;
    return { name: raw, next: end + 1 };
  }
  const code = source.charCodeAt(j);
  if (Number.isNaN(code) || !isIdentStart(code)) return undefined;
  let k = j + 1;
  while (k < source.length && isIdentCharCode(source.charCodeAt(k))) k++;
  return { name: source.slice(j, k), next: k };
}

function skipWsAndComments(source: string, j: number): number {
  let k = j;
  while (k < source.length) {
    const c = source[k];
    if (
      c === " " || c === "\t" || c === "\n" || c === "\r" || c === "\f" ||
      c === "\v"
    ) {
      k++;
    } else if (c === "/" && source[k + 1] === "/") {
      k = skipLineEnd(source, k + 2);
    } else if (c === "/" && source[k + 1] === "*") {
      k = skipNestedComment(source, k + 2);
    } else {
      return k;
    }
  }
  return k;
}

function isKeywordAt(source: string, j: number, keyword: string): boolean {
  if (!source.startsWith(keyword, j)) return false;
  if (isIdentChar(source[j - 1]) || isIdentChar(source[j + keyword.length])) {
    return false;
  }
  return true;
}

interface FuncHit {
  name: string;
  keywordIndex: number;
  searchFrom: number;
  nextIndex: number;
}

function matchFuncAt(source: string, j: number): FuncHit | undefined {
  if (isKeywordAt(source, j, "function")) {
    let k = skipWsAndComments(source, j + 8);
    if (source[k] === "*") k = skipWsAndComments(source, k + 1);
    const id = readIdentifier(source, k);
    if (id === undefined) return undefined;
    if (source[skipWsAndComments(source, id.next)] !== "(") return undefined;
    return {
      name: id.name,
      keywordIndex: j,
      searchFrom: id.next,
      nextIndex: id.next,
    };
  }
  if (isKeywordAt(source, j, "func")) {
    const k = skipWsAndComments(source, j + 4);
    const id = readIdentifier(source, k);
    if (id === undefined) return undefined;
    return {
      name: id.name,
      keywordIndex: j,
      searchFrom: id.next,
      nextIndex: id.next,
    };
  }
  return undefined;
}

const declIntroducers: Record<string, true> = {
  if: true,
  guard: true,
  while: true,
  for: true,
  case: true,
  catch: true,
  else: true,
  return: true,
  in: true,
  where: true,
};

function precededByDeclIntroducer(source: string, j: number): boolean {
  let k = j - 1;
  while (k >= 0) {
    const c = source[k];
    if (
      c === " " || c === "\t" || c === "\n" || c === "\r" || c === "\f" ||
      c === "\v"
    ) {
      k--;
    } else {
      break;
    }
  }
  if (k < 0) return false;
  if (!isIdentCharCode(source.charCodeAt(k))) return false;
  const end = k + 1;
  while (k >= 0 && isIdentCharCode(source.charCodeAt(k))) k--;
  return declIntroducers[source.slice(k + 1, end)] === true;
}

function scanDeclEquals(source: string, from: number): number {
  const brace: BraceState = { count: 0 };
  let parens = 0;
  let brackets = 0;
  let braces = 0;
  let j = from;
  while (j < source.length) {
    const skipped = skipElement(source, j, brace);
    if (skipped >= 0) {
      j = skipped;
      continue;
    }
    const c = source[j];
    if (c === "(") parens++;
    else if (c === ")") {
      if (parens > 0) parens--;
    } else if (c === "[") brackets++;
    else if (c === "]") {
      if (brackets > 0) brackets--;
    } else if (c === "{") {
      if (parens === 0 && brackets === 0 && braces === 0) return -1;
      braces++;
    } else if (c === "}") {
      if (braces > 0) braces--;
      else return -1;
    } else if (c === ";" && parens === 0 && brackets === 0 && braces === 0) {
      return -1;
    } else if (c === "=" && parens === 0 && brackets === 0 && braces === 0) {
      const prev = source[j - 1];
      const next = source[j + 1];
      if (
        prev === "=" || prev === "<" || prev === ">" || next === "=" ||
        next === ">"
      ) return -1;
      return j;
    }
    j++;
  }
  return -1;
}

interface DeclHit {
  name: string;
  keywordIndex: number;
  nextIndex: number;
  openIndex: number;
}

function matchStoredPropertyAt(
  source: string,
  j: number,
): DeclHit | undefined {
  if (!isKeywordAt(source, j, "let") && !isKeywordAt(source, j, "var")) {
    return undefined;
  }
  if (precededByDeclIntroducer(source, j)) return undefined;
  const id = readIdentifier(source, skipWsAndComments(source, j + 3));
  if (id === undefined) return undefined;
  let m = skipWsAndComments(source, id.next);
  if (source[m] === ":") {
    m = scanDeclEquals(source, m + 1);
    if (m < 0) return undefined;
  }
  if (source[m] !== "=") return undefined;
  const prev = source[m - 1];
  const next = source[m + 1];
  if (
    prev === "=" || prev === "!" || prev === "<" || prev === ">" ||
    next === "=" || next === ">"
  ) return undefined;
  const o = skipWsAndComments(source, m + 1);
  const open = source[o];
  if (open !== "[" && open !== "(" && open !== "{") return undefined;
  return { name: id.name, keywordIndex: j, nextIndex: id.next, openIndex: o };
}

function scanBracketClose(source: string, openIndex: number): number {
  const open = source[openIndex];
  const close = open === "[" ? "]" : open === "(" ? ")" : "}";
  const brace: BraceState = { count: 0 };
  let depth = 1;
  let j = openIndex + 1;
  while (j < source.length) {
    const skipped = skipElement(source, j, brace);
    if (skipped >= 0) {
      j = skipped;
      continue;
    }
    if (source[j] === open) depth++;
    else if (source[j] === close) {
      depth--;
      if (depth === 0) return j;
    }
    j++;
  }
  return -1;
}

function findBodyOpen(source: string, from: number): number {
  const brace: BraceState = { count: 0 };
  let parens = 0;
  let brackets = 0;
  let j = from;
  while (j < source.length) {
    const skipped = skipElement(source, j, brace);
    if (skipped >= 0) {
      j = skipped;
      continue;
    }
    const c = source[j];
    if (c === "(") parens++;
    else if (c === ")") {
      if (parens > 0) parens--;
    } else if (c === "[") brackets++;
    else if (c === "]") {
      if (brackets > 0) brackets--;
    } else if (parens === 0 && brackets === 0) {
      if (c === "{") return j;
      if (c === ";" || c === "}") return -1;
      if (
        isKeywordAt(source, j, "func") || isKeywordAt(source, j, "function")
      ) return -1;
    }
    j++;
  }
  return -1;
}

function scanBodyClose(source: string, openIndex: number): number {
  const brace: BraceState = { count: 0 };
  let j = openIndex;
  while (j < source.length) {
    const skipped = skipElement(source, j, brace);
    if (skipped >= 0) {
      j = skipped;
      continue;
    }
    if (source[j] === "{") brace.count++;
    else if (source[j] === "}") {
      brace.count--;
      if (brace.count === 0) return j;
    }
    j++;
  }
  return -1;
}

function lineStarts(source: string): number[] {
  const starts = [0];
  for (let i = 0; i < source.length; i++) {
    if (source[i] === "\n") starts.push(i + 1);
  }
  return starts;
}

function lineOf(starts: number[], index: number): number {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= index) lo = mid;
    else hi = mid - 1;
  }
  return lo + 1;
}

function collectBodies(
  source: string,
  wanted: string | undefined,
): FunctionBody[] {
  const bodies: FunctionBody[] = [];
  const starts = lineStarts(source);
  const brace: BraceState = { count: 0 };
  let j = 0;
  while (j < source.length) {
    const skipped = skipElement(source, j, brace);
    if (skipped >= 0) {
      j = skipped;
      continue;
    }
    const hit = matchFuncAt(source, j);
    if (hit !== undefined) {
      if (wanted === undefined || hit.name === wanted) {
        const open = findBodyOpen(source, hit.searchFrom);
        if (open >= 0) {
          const close = scanBodyClose(source, open);
          bodies.push({
            name: hit.name,
            startLine: lineOf(starts, hit.keywordIndex),
            endLine: lineOf(starts, close >= 0 ? close : source.length - 1),
          });
        }
      }
      j = hit.nextIndex;
      continue;
    }
    const decl = matchStoredPropertyAt(source, j);
    if (decl !== undefined) {
      if (wanted === undefined || decl.name === wanted) {
        const close = scanBracketClose(source, decl.openIndex);
        bodies.push({
          name: decl.name,
          startLine: lineOf(starts, decl.keywordIndex),
          endLine: lineOf(starts, close >= 0 ? close : source.length - 1),
        });
      }
      j = decl.nextIndex;
      continue;
    }
    j++;
  }
  return bodies;
}

export function findFunctionBodies(
  source: string,
  name: string,
): FunctionBody[] {
  if (name === "") return [];
  return collectBodies(source, name);
}

export function enclosingFunction(
  source: string,
  line: number,
): FunctionBody | undefined {
  let best: FunctionBody | undefined = undefined;
  let bestSpan = 0;
  for (const body of collectBodies(source, undefined)) {
    if (line < body.startLine || line > body.endLine) continue;
    const span = body.endLine - body.startLine;
    if (
      best === undefined || span < bestSpan ||
      (span === bestSpan && body.startLine > best.startLine)
    ) {
      best = body;
      bestSpan = span;
    }
  }
  return best;
}

export function literalLines(
  source: string,
  body: FunctionBody,
  literal: string,
): number[] {
  const targets = [`"${literal}"`, `'${literal}'`];
  const lines = source.split("\n");
  const hits: Array<{ line: number; index: number }> = [];
  const first = Math.max(body.startLine, 1);
  const last = Math.min(body.endLine, lines.length);
  for (let line = first; line <= last; line++) {
    const text = lines[line - 1];
    for (const target of targets) {
      let from = 0;
      while (from <= text.length - target.length) {
        const found = text.indexOf(target, from);
        if (found < 0) break;
        hits.push({ line, index: found });
        from = found + target.length;
      }
    }
  }
  hits.sort((a, b) => a.line - b.line || a.index - b.index);
  return hits.map((hit) => hit.line);
}

export function resolveAnchor(
  source: string | undefined,
  functionField: string,
  anchor: Anchor,
): Resolution {
  if (anchor.kind === "deleted") return { ok: false, reason: "deleted" };
  if (source === undefined) return { ok: false, reason: "file missing" };
  const name = functionName(functionField);
  const bodies = findFunctionBodies(source, name);
  if (bodies.length === 0) {
    return { ok: false, reason: `function ${name} not found` };
  }
  if (anchor.kind === "function") {
    return { ok: true, line: bodies[0].startLine };
  }
  const matches: number[] = [];
  for (const body of bodies) {
    matches.push(...literalLines(source, body, anchor.literal));
  }
  if (matches.length === 0) return { ok: false, reason: "literal not found" };
  if (anchor.occurrence === undefined) {
    if (matches.length > 1) {
      return {
        ok: false,
        reason: `literal ambiguous (${matches.length} matches); add #n`,
      };
    }
    return { ok: true, line: matches[0] };
  }
  if (
    !Number.isInteger(anchor.occurrence) || anchor.occurrence < 1 ||
    anchor.occurrence > matches.length
  ) {
    return {
      ok: false,
      reason:
        `occurrence #${anchor.occurrence} out of range (${matches.length} matches)`,
    };
  }
  return { ok: true, line: matches[anchor.occurrence - 1] };
}

function escapeRegExpText(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function literalPattern(literal: string): RegExp {
  let out = "";
  let i = 0;
  while (i < literal.length) {
    const c = literal[i];
    if (c === "\\" && i + 1 < literal.length) {
      const e = literal[i + 1];
      if (e === "n") {
        out += "\n";
        i += 2;
        continue;
      }
      if (e === "t") {
        out += "\t";
        i += 2;
        continue;
      }
      if (e === '"' || e === "\\") {
        out += escapeRegExpText(e);
        i += 2;
        continue;
      }
      if (e === "(") {
        let depth = 1;
        let k = i + 2;
        while (k < literal.length && depth > 0) {
          if (literal[k] === "(") depth++;
          else if (literal[k] === ")") depth--;
          k++;
        }
        out += ".*?";
        i = k;
        continue;
      }
      out += escapeRegExpText(c + e);
      i += 2;
      continue;
    }
    out += escapeRegExpText(c);
    i++;
  }
  return new RegExp(`^${out}$`);
}
