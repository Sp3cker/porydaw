// B0 roots are module registration, Swift resource URLs, and transitive component
// references from those roots. Check-fixture paths are metadata, not reachability.
import { skipElement } from "./proof_anchor.ts";

const BASELINE = "tools/qtbridge_surface_baseline.json";
const PIN_FILE = "cmake/QtBridge.cmake";
const SUPPORTED_TYPE_PIN = "407714006dd21107b70db6547ce75e43df0c8a75";
const SUPPORTED_TYPES_AT_407714006dd21107b70db6547ce75e43df0c8a75: Record<
  string,
  true
> = {
  Int: true,
  UInt: true,
  Double: true,
  Float: true,
  String: true,
  Bool: true,
};

type Check =
  | "UNREACHABLE_QML"
  | "UNANNOTATED_MEMBER"
  | "REDUNDANT_TRACKED"
  | "UNTRACKED_CUSTOM_TYPE"
  | "REDUNDANT_IGNORED"
  | "SUGAR_OPTIONAL_RETURN"
  | "SIGNAL_NEVER_OBSERVED"
  | "HANDLER_NEVER_EMITTED";
const CHECKS: Check[] = [
  "UNREACHABLE_QML",
  "UNANNOTATED_MEMBER",
  "REDUNDANT_TRACKED",
  "UNTRACKED_CUSTOM_TYPE",
  "REDUNDANT_IGNORED",
  "SUGAR_OPTIONAL_RETURN",
  "SIGNAL_NEVER_OBSERVED",
  "HANDLER_NEVER_EMITTED",
];

type Finding = { check: Check; path: string; line: number; detail: string };
type Member = {
  name: string;
  type: string;
  tracked: boolean;
  ignored: boolean;
};
type Signal = { name: string; path: string; line: number; emitted: boolean };
type BridgeClass = {
  name: string;
  members: Map<string, Member>;
  signals: Map<string, Signal>;
};
type Source = { path: string; text: string; code: string };

function codeOnly(text: string): string {
  const brace = { count: 0 };
  const characters = text.split("");
  for (let i = 0; i < text.length;) {
    const end = skipElement(text, i, brace);
    if (end > i) {
      for (let j = i; j < end; j++) {
        if (characters[j] !== "\n") characters[j] = " ";
      }
      i = end;
    } else i++;
  }
  return characters.join("");
}

function lineAt(text: string, offset: number): number {
  let line = 1;
  for (let i = 0; i < offset; i++) if (text[i] === "\n") line++;
  return line;
}

async function files(dir: string, suffix: string): Promise<string[]> {
  const result: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    const path = `${dir}/${entry.name}`;
    if (entry.isDirectory) result.push(...await files(path, suffix));
    else if (entry.isFile && path.endsWith(suffix)) result.push(path);
  }
  return result.sort();
}

async function sources(paths: string[]): Promise<Source[]> {
  return await Promise.all(paths.map(async (path) => {
    const text = await Deno.readTextFile(path);
    return { path, text, code: codeOnly(text) };
  }));
}

function supported(type: string): boolean {
  const compact = type.replace(/\s/g, "");
  return SUPPORTED_TYPES_AT_407714006dd21107b70db6547ce75e43df0c8a75[
        compact
      ] === true ||
    compact === "[String]" || compact === "Array<String>" ||
    compact === "[String:QVariantSettable]" ||
    compact === "Dictionary<String,QVariantSettable>" ||
    /^Q(?:List|Table)Model<.+>$/.test(compact);
}

function closingBrace(code: string, open: number): number {
  let depth = 0;
  for (let i = open; i < code.length; i++) {
    if (code[i] === "{") depth++;
    else if (code[i] === "}" && --depth === 0) return i;
  }
  return code.length;
}

function add(
  findings: Finding[],
  check: Check,
  path: string,
  line: number,
  detail: string,
): void {
  findings.push({ check, path, line, detail });
}

function swiftModel(
  swift: Source[],
  findings: Finding[],
): Map<string, BridgeClass> {
  const classes = new Map<string, BridgeClass>();
  for (const file of swift) {
    const classPattern =
      /@QtBridgeable\s+(?:(?:@\w+(?:\([^)]*\))?|public|final|open|internal|private|fileprivate|package|\s)+)?class\s+(\w+)[^{]*\{/g;
    for (const hit of file.code.matchAll(classPattern)) {
      const open = hit.index + hit[0].length - 1;
      const close = closingBrace(file.code, open);
      const bridge: BridgeClass = {
        name: hit[1],
        members: new Map(),
        signals: new Map(),
      };
      classes.set(hit[1], bridge);
      const fragment = file.code.slice(open + 1, close);
      const raw = file.text.slice(open + 1, close);
      const codeLines = fragment.split("\n");
      const rawLines = raw.split("\n");
      let depth = 0;
      let attributes = "";
      let offset = open + 1;
      for (let n = 0; n < codeLines.length; n++) {
        const code = codeLines[n];
        const original = rawLines[n];
        const line = lineAt(file.text, offset);
        if (depth === 0) {
          const attr = code.match(/^\s*((?:@\w+(?:\([^)]*\))?\s*)+)/);
          if (attr) attributes += ` ${attr[1]}`;
          const declaration =
            /\b(var|let)\s+([A-Za-z_]\w*)\s*(?::\s*([^={\n]+))?/.exec(code);
          if (
            declaration &&
            !/\b(?:func|subscript|typealias)\b/.test(
              code.slice(0, declaration.index),
            )
          ) {
            const prefix = `${attributes} ${code.slice(0, declaration.index)}`;
            const name = declaration[2];
            const type = declaration[3]?.trim() ?? "";
            const ignored = /@QtIgnored\b/.test(prefix);
            const tracked = /@QtTracked\b/.test(prefix);
            const privateMember = /\bprivate\b/.test(prefix);
            const staticMember = /\b(?:static|class)\b/.test(prefix);
            const after = code.slice(declaration.index + declaration[0].length);
            const computed = /^\s*\{/.test(after) ||
              (/^\s*$/.test(after) && /^\s*\{/.test(codeLines[n + 1] ?? ""));
            let didSet = /\bdidSet\b/.test(code);
            if (!didSet) {
              let propertyDepth = 0;
              for (let k = n + 1; k < codeLines.length; k++) {
                const candidate = codeLines[k];
                if (
                  propertyDepth === 0 &&
                  /^\s*(?:@|(?:public|private|internal|fileprivate|package|static|class|var|let|func)\b)/
                    .test(candidate)
                ) break;
                if (/\bdidSet\b/.test(candidate)) didSet = true;
                for (const char of candidate) {
                  if (char === "{") propertyDepth++;
                  else if (char === "}") propertyDepth--;
                }
                if (propertyDepth < 0) break;
              }
            }
            if (ignored && (privateMember || staticMember)) {
              add(findings, "REDUNDANT_IGNORED", file.path, line, name);
            }
            if (!privateMember && !staticMember && !computed && !didSet) {
              if (!type && !tracked && !ignored) {
                add(findings, "UNANNOTATED_MEMBER", file.path, line, name);
              } else if (tracked && supported(type)) {
                add(findings, "REDUNDANT_TRACKED", file.path, line, name);
              } else if (!tracked && !ignored && !supported(type)) {
                add(findings, "UNTRACKED_CUSTOM_TYPE", file.path, line, name);
              }
              bridge.members.set(name, { name, type, tracked, ignored });
            }
            attributes = "";
          } else {
            const fn =
              /\bfunc\s+(\w+)\s*\([^)]*\)\s*(?:async\s*)?(?:throws\s*)?(?:->\s*(Optional<)?([A-Za-z_]\w*)(\?)?)?/
                .exec(code);
            if (fn) {
              const prefix = `${attributes} ${code.slice(0, fn.index)}`;
              if (/@QtSignal\b/.test(prefix)) {
                bridge.signals.set(fn[1], {
                  name: fn[1],
                  path: file.path,
                  line,
                  emitted: false,
                });
              }
              if (
                /\bpublic\b/.test(prefix) && fn[2] === undefined &&
                fn[4] === "?"
              ) {
                add(findings, "SUGAR_OPTIONAL_RETURN", file.path, line, fn[1]);
              }
              attributes = "";
            } else if (code.trim() && !/^\s*@/.test(code)) attributes = "";
          }
        }
        for (const char of code) {
          if (char === "{") depth++;
          else if (char === "}") depth--;
        }
        offset += original.length + 1;
      }
    }
  }
  for (const bridge of classes.values()) {
    for (const signal of bridge.signals.values()) {
      const escaped = signal.name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const call = new RegExp(`\\b${escaped}\\s*\\(`, "g");
      const emit = new RegExp(
        `\\bemitSignal\\s*\\(\\s*for:\\s*\\\\(?:\\w+\\.)?${escaped}\\b`,
      );
      signal.emitted = swift.some((file) =>
        emit.test(file.code) || [...file.code.matchAll(call)].some((hit) => {
          if (file.path !== signal.path) return true;
          return lineAt(file.code, hit.index) !== signal.line;
        })
      );
    }
  }
  return classes;
}

function qmlReachability(
  qml: Source[],
  swift: Source[],
  cmake: string,
  findings: Finding[],
): void {
  const ui = qml.filter((file) => file.path.startsWith("src/ui/"));
  const byPath = new Map(ui.map((file) => [file.path, file]));
  const reachable = new Set<string>();
  const module =
    /qt_add_qml_module\(porydaw_app\b[\s\S]*?\bQML_FILES\b([\s\S]*?)\n\s*\)/
      .exec(cmake);
  if (!module) throw new Error("porydaw_app QML_FILES block not found");
  for (const path of module[1].match(/src\/ui\/[^\s)]+\.qml/g) ?? []) {
    reachable.add(path);
  }
  const shell = /set\(shell_qml\s+(src\/ui\/[^\s)]+\.qml)\s*\)/.exec(cmake)
    ?.[1];
  const appName = swift.flatMap((file) =>
    [...file.text.matchAll(/\bqmlFileName\s*=\s*"(\w+)"/g)].map((hit) => hit[1])
  );
  if (
    !shell || !appName.includes(shell.split("/").at(-1)!.replace(/\.qml$/, ""))
  ) {
    console.error(
      `CMakeLists.txt shell_qml (${
        shell ?? "missing"
      }) does not match Swift qmlFileName (${
        appName.join(", ") || "missing"
      }); see docs/plans/qtbridge-surface/spec.md §4`,
    );
    Deno.exit(1);
  }
  reachable.add(shell);
  for (const file of swift) {
    for (
      const hit of file.text.matchAll(
        /QmlEngineAccess\.moduleResourcePrefix\s*\+\s*"([^"\n]+\.qml)"/g,
      )
    ) {
      if (file.code.startsWith("QmlEngineAccess", hit.index)) {
        reachable.add(hit[1].replace(/^\/+/, ""));
      }
    }
  }
  const pending = [...reachable];
  for (let i = 0; i < pending.length; i++) {
    const file = byPath.get(pending[i]);
    if (!file) continue;
    const directory = file.path.slice(0, file.path.lastIndexOf("/"));
    for (const hit of file.code.matchAll(/\b([A-Z][A-Za-z0-9_]*)\s*\{/g)) {
      const name = `${hit[1]}.qml`;
      const local = `${directory}/${name}`;
      const candidates = byPath.has(local)
        ? [local]
        : ui.filter((source) =>
          source.path.endsWith(`/${name}`) && reachable.has(source.path)
        ).map((source) => source.path);
      for (const path of candidates) {
        if (reachable.has(path)) continue;
        reachable.add(path);
        pending.push(path);
      }
    }
    const brace = { count: 0 };
    for (let j = 0; j < file.text.length;) {
      const end = skipElement(file.text, j, brace);
      if (end <= j) {
        j++;
        continue;
      }
      if (file.text[j] === '"') {
        const literal = file.text.slice(j + 1, end - 1);
        if (/^[A-Za-z_][\w/.-]*\.qml$/.test(literal)) {
          const path = literal.startsWith("src/ui/")
            ? literal
            : `${directory}/${literal}`;
          if (byPath.has(path) && !reachable.has(path)) {
            reachable.add(path);
            pending.push(path);
          }
        }
      }
      j = end;
    }
  }
  for (const file of ui) {
    if (!reachable.has(file.path)) {
      add(findings, "UNREACHABLE_QML", file.path, 1, "unregistered");
    }
  }
}

function resolveType(
  chain: string,
  ids: Map<string, string>,
  classes: Map<string, BridgeClass>,
): string | undefined {
  const names = chain.split(".");
  let type: string | undefined;
  let from = 1;
  for (let n = names.length; n > 0; n--) {
    const known = ids.get(names.slice(0, n).join("."));
    if (known) {
      type = known;
      from = n;
      break;
    }
  }
  for (const memberName of names.slice(from)) {
    const member = type
      ? classes.get(type)?.members.get(memberName)
      : undefined;
    if (
      !member || member.ignored || (!member.tracked && !supported(member.type))
    ) {
      return undefined;
    }
    type = /^(?:Optional<)?(\w+)/.exec(member.type)?.[1];
  }
  return type && classes.has(type) ? type : undefined;
}

type QmlElement = { type: string; id?: string; open: number; end: number };

function qmlIds(
  file: Source,
  roots: Set<string>,
  classes: Map<string, BridgeClass>,
  elements: QmlElement[],
  connectionOpen: number,
): Map<string, string> {
  const ids = new Map<string, string>();
  for (const element of elements) {
    if (element.id && roots.has(element.type)) {
      ids.set(element.id, element.type);
    }
  }
  const enclosing = elements.filter((element) =>
    element.open < connectionOpen && connectionOpen < element.end
  );
  for (const hit of file.code.matchAll(/\bproperty\s+(\w+)\s+(\w+)\b/g)) {
    if (!classes.has(hit[1])) continue;
    const owner = elements.findLast((element) =>
      element.open < hit.index && hit.index < element.end
    );
    if (!owner || !enclosing.includes(owner)) continue;
    ids.set(hit[2], hit[1]);
    if (owner.id) ids.set(`${owner.id}.${hit[2]}`, hit[1]);
  }
  return ids;
}

function signalChecks(
  qml: Source[],
  swift: Source[],
  classes: Map<string, BridgeClass>,
  findings: Finding[],
): void {
  const qmlHandlers = new Set<string>();
  const roots = new Set<string>();
  for (const file of swift) {
    for (
      const hit of file.code.matchAll(
        /instantiableTypes\s*:\s*\[[^\]]+\]\s*=\s*\[([^\]]+)\]/g,
      )
    ) {
      for (const type of hit[1].matchAll(/\b(\w+)\.self\b/g)) {
        roots.add(type[1]);
      }
    }
  }
  for (const file of qml) {
    for (
      const hit of file.code.matchAll(
        /\b(?:function\s+on([A-Z]\w*)\s*\(|on([A-Z]\w*)\s*:)/g,
      )
    ) {
      const name = hit[1] ?? hit[2];
      qmlHandlers.add(name[0].toLowerCase() + name.slice(1));
    }
    const elements: QmlElement[] = [...file.code.matchAll(/\b([A-Z]\w*)\s*\{/g)]
      .map((hit) => {
        const open = hit.index + hit[0].length - 1;
        const end = closingBrace(file.code, open);
        const id = /^\s*id\s*:\s*(\w+)/.exec(file.code.slice(open + 1, end))
          ?.[1];
        return { type: hit[1], id, open, end };
      });
    const contexts: Array<{ type?: string; start: number; end: number }> = [];
    for (const hit of file.code.matchAll(/\bConnections\s*\{/g)) {
      const open = hit.index + hit[0].length - 1;
      const end = closingBrace(file.code, open);
      const target =
        /\btarget\s*:\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*(?=\n|$)/m.exec(
          file.code.slice(open, end),
        );
      const ids = qmlIds(file, roots, classes, elements, open);
      const type = target ? resolveType(target[1], ids, classes) : undefined;
      contexts.push({ type, start: open, end });
    }
    for (const hit of file.code.matchAll(/\bfunction\s+on([A-Z]\w*)\s*\(/g)) {
      const context = contexts.find((ctx) =>
        hit.index > ctx.start && hit.index < ctx.end
      );
      if (!context) continue;
      const signalName = hit[1][0].toLowerCase() + hit[1].slice(1);
      if (!context.type) continue;
      const bridge = classes.get(context.type)!;
      const propertyName = signalName.endsWith("Changed")
        ? signalName.slice(0, -"Changed".length)
        : undefined;
      const property = propertyName
        ? bridge.members.get(propertyName)
        : undefined;
      if (
        property && !property.ignored &&
        (property.tracked || supported(property.type))
      ) continue;
      const signal = bridge.signals.get(signalName);
      if (!signal || !signal.emitted) {
        add(
          findings,
          "HANDLER_NEVER_EMITTED",
          file.path,
          lineAt(file.code, hit.index),
          `${context.type}.${signalName}`,
        );
      }
    }
  }
  for (const bridge of classes.values()) {
    for (const signal of bridge.signals.values()) {
      if (qmlHandlers.has(signal.name)) continue;
      const swiftObserved = swift.some((file) =>
        new RegExp(`\\b${signal.name}\\s*\\.\\s*connect\\s*\\(`).test(
          file.code,
        ) ||
        [...file.code.matchAll(
          new RegExp(
            `\\b(\\w+)\\.on${signal.name[0].toUpperCase()}${
              signal.name.slice(1)
            }\\s*=`,
            "g",
          ),
        )].some((hit) =>
          new RegExp(`\\b${hit[1]}\\s*:\\s*${bridge.name}\\b`).test(file.code)
        )
      );
      if (!swiftObserved) {
        add(
          findings,
          "SIGNAL_NEVER_OBSERVED",
          signal.path,
          signal.line,
          `${bridge.name}.${signal.name}`,
        );
      }
    }
  }
}

function format(finding: Finding): string {
  return `${finding.check} ${finding.path}:${finding.line} ${finding.detail}`;
}

function key(finding: Finding): string {
  return `${finding.check} ${finding.path} ${finding.detail}`;
}

function sortFindings(findings: Finding[]): Finding[] {
  return findings.sort((a, b) =>
    a.path.localeCompare(b.path) || a.line - b.line ||
    a.check.localeCompare(b.check) || a.detail.localeCompare(b.detail)
  );
}

async function main(): Promise<void> {
  if (
    Deno.args.some((arg) =>
      arg !== "--update-baseline" && arg !== "--allow-growth"
    ) || (Deno.args.includes("--allow-growth") &&
      !Deno.args.includes("--update-baseline"))
  ) {
    console.error(
      "usage: deno task verify:bridge | deno task bridge:baseline",
    );
    Deno.exit(2);
  }
  const swift = await sources(await files("src/swift", ".swift"));
  const checkSwift = await sources(await files("src/checks", ".swift"));
  const qml = await sources([
    ...await files("src/ui", ".qml"),
    ...await files("src/checks", ".qml"),
  ]);
  const pinSource = await Deno.readTextFile(PIN_FILE);
  const pin = /GIT_TAG\s+([0-9a-f]{40})/.exec(pinSource)?.[1];
  if (!pin) throw new Error(`QtBridge GIT_TAG missing in ${PIN_FILE}`);
  if (pin !== SUPPORTED_TYPE_PIN) {
    console.error(
      `QtBridge pin in ${PIN_FILE} (${pin}) differs from supported-type constant SUPPORTED_TYPE_PIN (${SUPPORTED_TYPE_PIN}); revisit the guard on a QtBridge pin bump (docs/plans/qtbridge-surface/spec.md §4)`,
    );
    Deno.exit(1);
  }
  const findings: Finding[] = [];
  const classes = swiftModel([...swift, ...checkSwift], findings);
  qmlReachability(
    qml,
    swift,
    await Deno.readTextFile("CMakeLists.txt"),
    findings,
  );
  signalChecks(qml, [...swift, ...checkSwift], classes, findings);
  const ordered = sortFindings(findings);
  const keys = [...new Set(ordered.map(key))].sort();
  const counts = new Map<Check, number>();
  for (const finding of ordered) {
    counts.set(finding.check, (counts.get(finding.check) ?? 0) + 1);
  }
  for (const check of CHECKS) {
    console.log(`${check}: ${counts.get(check) ?? 0}`);
  }
  let baseline: { pin: string; findings: string[] };
  try {
    baseline = JSON.parse(await Deno.readTextFile(BASELINE));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    console.error(
      `Missing ${BASELINE}; run deno task bridge:baseline`,
    );
    Deno.exit(1);
  }
  if (baseline.pin !== pin) {
    console.error(
      `QtBridge pin in ${PIN_FILE} (${pin}) differs from recorded pin in ${BASELINE} (${baseline.pin}); check SUPPORTED_TYPE_PIN (${SUPPORTED_TYPE_PIN}) and revisit the guard on a QtBridge pin bump (docs/plans/qtbridge-surface/spec.md §4)`,
    );
    Deno.exit(1);
  }
  if (
    !Array.isArray(baseline.findings) ||
    !baseline.findings.every((entry) => typeof entry === "string")
  ) {
    throw new Error(
      `Invalid ${BASELINE}: findings must be an array of strings`,
    );
  }
  const existing = new Set(baseline.findings);
  const current = new Set(keys);
  const unexpected = keys.filter((entry) => !existing.has(entry));
  const stale = baseline.findings.filter((entry) => !current.has(entry));
  if (Deno.args.includes("--update-baseline")) {
    if (unexpected.length && !Deno.args.includes("--allow-growth")) {
      console.error(`Refusing baseline growth in ${BASELINE}:`);
      for (const entry of unexpected) console.error(entry);
      console.error("Use deno task bridge:baseline to allow growth");
      Deno.exit(1);
    }
    await Deno.writeTextFile(
      BASELINE,
      JSON.stringify({ pin, findings: keys }, null, 2) + "\n",
    );
    console.log(`Updated ${BASELINE}: ${keys.length} findings`);
    return;
  }
  const unexpectedSet = new Set(unexpected);
  for (
    const line of new Set(
      ordered.filter((finding) => unexpectedSet.has(key(finding))).map(format),
    )
  ) console.error(line);
  for (const entry of stale) {
    const match = /^(\w+) (\S+) (.+)$/.exec(entry);
    if (!match) throw new Error(`Invalid baseline finding: ${entry}`);
    console.error(`STALE_BASELINE ${match[2]} ${match[1]} ${match[3]}`);
  }
  if (unexpected.length || stale.length) Deno.exit(1);
  console.log(`Bridge surface: ${keys.length} baselined findings`);
}

if (import.meta.main) await main();
