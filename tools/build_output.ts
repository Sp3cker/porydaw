// Reduces CMake/Ninja output to what an agent can act on: the failing step,
// its errors, and warnings located in project sources. The full log keeps the rest.
import { isAbsolute, relative, resolve } from "node:path";

export interface BuildSummary {
  /** Descriptions of the Ninja steps that failed. */
  readonly failedSteps: string[];
  readonly errors: string[];
  /** Warnings located in project-owned sources only. */
  readonly warnings: string[];
  /** Ninja steps that ran; zero when the build was already up to date. */
  readonly steps: number;
}

export interface OutputRoots {
  /** Repository root; also the root for CMake's relative paths. */
  readonly repo: string;
  /** Build tree Ninja runs in; the root for compilers' relative paths. */
  readonly build: string;
}

interface Step {
  readonly description: string;
  readonly lines: string[];
  failed: boolean;
}

interface Diagnostic {
  readonly path?: string;
  readonly severity: "error" | "warning";
  readonly text: string;
}

// Terminal color and OSC 8 hyperlink sequences wrap Swift diagnostics.
// deno-lint-ignore no-control-regex
const ESCAPE = /\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]/g;
const GROUP_TAG = /\s*\[#[\w-]+\]\s*$/;
const STEP = /^\[\d+\/\d+\] (.*)$/;
const LOCATED = /^(.+?):(\d+)(?::(\d+))?: (fatal error|error|warning): (.*)$/;
const MSVC =
  /^(.+?)\((\d+)(?:,(\d+))?\)\s*: (fatal error|error|warning) ([A-Z]+\d+): (.*)$/;
const TOOL = /^(Error|Warning): (?:(.+?):(\d+):(?:(\d+):)? )?(.*)$/;
const UNLOCATED =
  /^(?:<unknown>:0: )?(?:[\w.+-]+: )?(fatal error|error|warning): (.*)$/;
const DRIVER_FAILURE = /command failed|failed with exit code|subcommand failed/;
const LINKER = [
  /^Undefined symbols for architecture /,
  /^\s+"[^"]+", referenced from:$/,
  /^ld: /,
  /^duplicate symbol /,
  /undefined reference to /,
  /multiple definition of /,
];
const CMAKE_HEADER =
  /^CMake (Error|Warning)( \(dev\))?(?: at (.+?):(\d+) \((\w+)\))?:\s*(.*)$/;
const CMAKE_BODY_LINES = 8;

function located(
  path: string,
  line: string,
  column: string | undefined,
  severity: string,
  message: string,
): Diagnostic {
  return {
    path,
    severity: severity === "warning" ? "warning" : "error",
    text: `${line}${column ? `:${column}` : ""}: ${severity}: ${
      message.replace(GROUP_TAG, "")
    }`,
  };
}

function parseDiagnostic(line: string): Diagnostic | undefined {
  const msvc = MSVC.exec(line);
  if (msvc) {
    const [, path, row, column, severity, code, message] = msvc;
    return located(path, row, column, severity, `${code}: ${message}`);
  }
  const clang = LOCATED.exec(line);
  if (clang) {
    const [, path, row, column, severity, message] = clang;
    return located(path, row, column, severity, message);
  }
  const tool = TOOL.exec(line);
  if (tool) {
    const [, severity, path, row, column, message] = tool;
    const level = severity.toLowerCase();
    return path
      ? located(path, row, column, level, message)
      : { severity: level === "warning" ? "warning" : "error", text: line };
  }
  const bare = UNLOCATED.exec(line);
  if (bare) {
    return {
      severity: bare[1] === "warning" ? "warning" : "error",
      text: line.replace(GROUP_TAG, ""),
    };
  }
  return undefined;
}

function repoPath(roots: OutputRoots, base: string, path: string): string {
  const absolute = isAbsolute(path) ? path : resolve(base, path);
  const inside = relative(roots.repo, absolute);
  return inside.startsWith("..") || isAbsolute(inside) ? absolute : inside;
}

function projectOwned(path: string): boolean {
  if (isAbsolute(path)) return false;
  const segments = path.split(/[\\/]/);
  return !segments[0].startsWith("build") && segments[0] !== "external" &&
    segments[0] !== ".cache" && !segments.includes("_deps");
}

function render(roots: OutputRoots, base: string, diagnostic: Diagnostic) {
  if (!diagnostic.path) return { text: diagnostic.text, owned: false };
  // Swift reports macro expansions and buffers as `macro expansion @X` or `<name>`.
  if (/^<|\s@/.test(diagnostic.path)) {
    return { text: `${diagnostic.path}:${diagnostic.text}`, owned: false };
  }
  const path = repoPath(roots, base, diagnostic.path);
  return { text: `${path}:${diagnostic.text}`, owned: projectOwned(path) };
}

function splitSteps(lines: string[]): { steps: Step[]; ran: number } {
  const steps: Step[] = [{ description: "", lines: [], failed: false }];
  let ran = 0;
  let skipCommand = false;
  for (const line of lines) {
    const step = STEP.exec(line);
    if (step) {
      ran++;
      steps.push({ description: step[1], lines: [], failed: false });
      continue;
    }
    const current = steps[steps.length - 1];
    if (line.startsWith("FAILED: ")) {
      current.failed = true;
      skipCommand = true;
      continue;
    }
    if (skipCommand) {
      skipCommand = false;
      continue;
    }
    if (line.startsWith("ninja: ")) continue;
    current.lines.push(line);
  }
  return { steps, ran };
}

function cmakeMessages(
  lines: string[],
  roots: OutputRoots,
): { errors: string[]; warnings: string[] } {
  const errors: string[] = [];
  const warnings: string[] = [];
  for (let index = 0; index < lines.length; index++) {
    const header = CMAKE_HEADER.exec(lines[index]);
    if (!header) continue;
    const [, kind, dev, path, row, command, inline] = header;
    const body: string[] = inline ? [inline] : [];
    while (
      index + 1 < lines.length &&
      (lines[index + 1] === "" || /^\s/.test(lines[index + 1]))
    ) {
      const text = lines[++index].trim();
      if (text) body.push(text);
    }
    const where = path ? repoPath(roots, roots.repo, path) : undefined;
    const message = [
      `CMake ${kind}${where ? ` at ${where}:${row} (${command})` : ""}:`,
      ...body.slice(0, CMAKE_BODY_LINES).map((text) => `  ${text}`),
    ].join("\n");
    if (kind === "Error") errors.push(message);
    else if (!dev && (where === undefined || projectOwned(where))) {
      warnings.push(message);
    }
  }
  return { errors, warnings };
}

function failureLines(step: Step, roots: OutputRoots, tail: boolean): string[] {
  const errors: string[] = [];
  const driverFailures: string[] = [];
  for (const line of step.lines) {
    if (LINKER.some((pattern) => pattern.test(line))) {
      errors.push(line.trim());
      continue;
    }
    const diagnostic = parseDiagnostic(line);
    if (diagnostic?.severity !== "error") continue;
    const { text } = render(roots, roots.build, diagnostic);
    (DRIVER_FAILURE.test(text) ? driverFailures : errors).push(text);
  }
  if (errors.length > 0) return errors;
  if (driverFailures.length > 0 || !tail) return driverFailures;
  // Custom commands (rcc, qmlcachegen, moc) report in free form: keep their tail.
  return step.lines.map((line) => line.trimEnd()).filter(Boolean).slice(-15);
}

export function summarizeBuild(
  output: string,
  roots: OutputRoots,
): BuildSummary {
  const lines = output.replace(ESCAPE, "").split(/\r?\n/);
  const { steps, ran } = splitSteps(lines);
  const cmake = cmakeMessages(lines, roots);
  const failed = steps.filter((step) => step.failed);
  const errors = [
    ...cmake.errors,
    ...failed.flatMap((step) =>
      failureLines(step, roots, cmake.errors.length === 0)
    ),
  ];
  const warnings = [...cmake.warnings];
  for (const line of lines) {
    const diagnostic = parseDiagnostic(line);
    if (diagnostic?.severity !== "warning") continue;
    const rendered = render(roots, roots.build, diagnostic);
    if (rendered.owned) warnings.push(rendered.text);
  }
  return {
    failedSteps: failed.map((step) => step.description || "configure"),
    errors: [...new Set(errors)],
    warnings: [...new Set(warnings)],
    steps: ran,
  };
}
