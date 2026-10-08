import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { runBuild } from "./build.ts";
import { compilerArguments } from "./swift_toolchain.ts";

const HELP = `usage: deno task bench:swift-compile [options]
  --module <name>  restrict to a Swift module (repeatable)
  --file <path>    run only this file's frontend job (repeatable)
  --no-build       use existing dependencies; caller must keep them current
  --order <mode>   both (default) or normal; both reverses source order
  --repeat <n>     measurements per source order (default 1)
  --output <dir>   new report directory (default build/swift-timings/<timestamp>)
  --top <n>        displayed functions/files/expressions (default 10)
  --help           show help without building

Debug type-checking only, not optimization, code generation, or linking.
File sums exclude generated bodies; generated timings have a separate report.
First run prepares the app; later filtered runs build only selected modules.
File mode retains all module inputs but executes only selected primary jobs.
Results depend on lazy imports and source order; never add expression to body times.
`;

export interface Options {
  modules: string[];
  files: string[];
  build: boolean;
  order: "normal" | "both";
  repeat: number;
  top: number;
  output?: string;
}

export function parseOptions(args: string[]): Options {
  const options: Options = {
    modules: [],
    files: [],
    build: true,
    order: "both",
    repeat: 1,
    top: 10,
  };
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (flag === "--no-build") {
      options.build = false;
      continue;
    }
    if (
      !["--module", "--file", "--order", "--repeat", "--output", "--top"]
        .includes(flag)
    ) {
      throw new Error(`unknown option ${flag}`);
    }
    const value = args[++i];
    if (!value || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }
    if (flag === "--module") options.modules.push(value);
    if (flag === "--file") options.files.push(value);
    if (flag === "--output") options.output = value;
    if (flag === "--order") {
      if (value !== "normal" && value !== "both") {
        throw new Error("--order must be normal or both");
      }
      options.order = value;
    }
    if (flag === "--repeat" || flag === "--top") {
      const count = Number(value);
      if (!Number.isSafeInteger(count) || count < 1) {
        throw new Error(`${flag} must be a positive integer`);
      }
      options[flag === "--repeat" ? "repeat" : "top"] = count;
    }
  }
  return options;
}

interface CompilationEntry {
  directory: string;
  file: string;
  command?: string;
  arguments?: string[];
}

export interface ModuleJob {
  module: string;
  cwd: string;
  command: string[];
  sources: string[];
}

export function discoverModules(
  entries: CompilationEntry[],
  root: string,
): ModuleJob[] {
  const modules = new Map<string, ModuleJob>();
  const prefix = resolve(root, "src/swift") + "/";
  for (const entry of entries) {
    const file = resolve(entry.directory, entry.file);
    if (!file.startsWith(prefix) || !file.endsWith(".swift")) continue;
    const command = entry.arguments ?? compilerArguments(entry.command ?? "");
    const index = command.indexOf("-module-name");
    if (index < 0 || !command[index + 1]) continue;
    const module = command[index + 1];
    const sources = command.filter((arg) => arg.endsWith(".swift")).map((arg) =>
      resolve(entry.directory, arg)
    );
    if (!sources.includes(file)) {
      throw new Error(
        `unusable compiler command for ${file}; regenerate the Swift database`,
      );
    }
    if (sources.some((source) => !source.startsWith(resolve(root) + "/"))) {
      throw new Error(`${module} has Swift inputs outside this worktree`);
    }
    modules.set(module, { module, cwd: entry.directory, command, sources });
  }
  if (!modules.size) {
    throw new Error(
      "no first-party Swift commands; regenerate the Swift database",
    );
  }
  return [...modules.values()].sort((a, b) => a.module.localeCompare(b.module));
}

export function selectModules(
  jobs: ModuleJob[],
  options: Options,
  root: string,
): ModuleJob[] {
  for (const name of options.modules) {
    if (!jobs.some((job) => job.module === name)) {
      throw new Error(`unknown Swift module ${name}`);
    }
  }
  const files = options.files.map((file) => resolve(root, file));
  for (const file of files) {
    if (!jobs.some((job) => job.sources.includes(file))) {
      throw new Error(`file is not a Swift input in this worktree: ${file}`);
    }
  }
  const selected = jobs.filter((job) =>
    (!options.modules.length || options.modules.includes(job.module)) &&
    (!files.length || files.some((file) => job.sources.includes(file)))
  );
  for (const file of files) {
    if (!selected.some((job) => job.sources.includes(file))) {
      throw new Error(`file excluded by --module: ${file}`);
    }
  }
  if (!selected.length) throw new Error("no modules selected");
  return selected;
}

export function timingCommand(
  job: ModuleJob,
  reverse: boolean,
  fileMode: boolean,
): string[] {
  const values: Record<string, true> = {
    "-output-file-map": true,
    "-emit-module-path": true,
    "-emit-module-doc-path": true,
    "-emit-module-source-info-path": true,
    "-emit-objc-header-path": true,
    "-emit-dependencies-path": true,
    "-serialize-diagnostics-path": true,
    "-index-store-path": true,
    "-num-threads": true,
    "-j": true,
    "-o": true,
  };
  const flags: Record<string, true> = {
    "-c": true,
    "-emit-module": true,
    "-incremental": true,
    "-enable-batch-mode": true,
    "-disable-batch-mode": true,
    "-static": true,
    "-index-ignore-system-modules": true,
  };
  const command: string[] = [];
  for (let i = 0; i < job.command.length; i++) {
    const arg = job.command[i];
    if (arg === "-Xcc" || arg === "-Xfrontend" || arg === "-Xlinker") {
      if (job.command[i + 1] === undefined) {
        throw new Error(`missing forwarded argument for ${arg}`);
      }
      command.push(arg, job.command[++i]);
    } else if (Object.hasOwn(values, arg)) {
      if (job.command[i + 1] === undefined) {
        throw new Error(`missing compiler value for ${arg}`);
      }
      i++;
    } else if (!Object.hasOwn(flags, arg)) command.push(arg);
  }
  if (reverse) {
    const positions = command.flatMap((arg, i) =>
      arg.endsWith(".swift") ? [i] : []
    );
    const sources = positions.map((i) => command[i]).reverse();
    positions.forEach((position, i) => command[position] = sources[i]);
  }
  command.push(
    "-typecheck",
    "-Xfrontend",
    "-debug-time-function-bodies",
    "-Xfrontend",
    "-debug-time-expression-type-checking",
  );
  if (fileMode) command.push("-disable-batch-mode", "-driver-print-jobs");
  else command.push("-enable-batch-mode", "-driver-batch-count", "1");
  return command;
}

export function selectedFrontendJobs(
  output: string,
  files: string[],
  cwd: string,
): string[][] {
  const commands = output.split(/\r?\n/).filter((line) =>
    line.includes(" -frontend ")
  ).map((line) => compilerArguments(line));
  const result = files.map((file) => {
    const matches = commands.filter((command) =>
      command.some((arg, i) =>
        arg === "-primary-file" && resolve(cwd, command[i + 1] ?? "") === file
      )
    );
    if (matches.length !== 1 || !matches[0].includes("-typecheck")) {
      throw new Error(
        `expected one type-checking frontend job for ${file}, found ${matches.length}`,
      );
    }
    return matches[0];
  });
  return result;
}

export interface Timing {
  ms: number;
  location: string;
  symbol?: string;
  generated: boolean;
}

export function parseTimings(text: string, root?: string): Timing[] {
  const timings: Timing[] = [];
  for (const line of text.split(/\r?\n/)) {
    const match = /^(\d+(?:\.\d+)?)ms\s+(.+)$/.exec(line);
    if (!match) continue;
    const [location, ...symbol] = match[2].split("\t");
    if (location === "<invalid loc>") continue;
    timings.push({
      ms: Number(match[1]),
      location,
      ...(symbol.length ? { symbol: symbol.join("\t") } : {}),
      generated: location.startsWith("@__swiftmacro_") ||
        (root !== undefined &&
          location.startsWith(resolve(root, "build") + "/")),
    });
  }
  return timings;
}

interface Measurement {
  module: string;
  order: string;
  iteration: number;
  wallMs: number;
  exit: number;
  log: string;
  commands: string[][];
  timings: Timing[];
}

export function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

interface Ranked {
  module: string;
  location: string;
  symbol: string;
  generated: boolean;
  normalMs: number | null;
  reversedMs: number | null;
}

export function rankTimings(
  measurements: Measurement[],
  bodies: boolean,
): Ranked[] {
  const rows = new Map<
    string,
    { row: Ranked; values: Map<string, number[]> }
  >();
  for (const measurement of measurements) {
    if (measurement.exit) continue;
    const perRun = new Map<string, { timing: Timing; ms: number }>();
    for (const timing of measurement.timings) {
      if ((timing.symbol !== undefined) !== bodies) continue;
      const key = JSON.stringify([
        measurement.module,
        timing.location,
        timing.symbol ?? "",
      ]);
      const existing = perRun.get(key);
      const ms = existing
        ? (bodies ? existing.ms + timing.ms : Math.max(existing.ms, timing.ms))
        : timing.ms;
      perRun.set(key, { timing, ms });
    }
    for (const [key, { timing, ms }] of perRun) {
      let entry = rows.get(key);
      if (!entry) {
        entry = {
          row: {
            module: measurement.module,
            location: timing.location,
            symbol: timing.symbol ?? "",
            generated: timing.generated,
            normalMs: null,
            reversedMs: null,
          },
          values: new Map(),
        };
        rows.set(key, entry);
      }
      const values = entry.values.get(measurement.order) ?? [];
      values.push(ms);
      entry.values.set(measurement.order, values);
    }
  }
  return [...rows.values()].map(({ row, values }) => ({
    ...row,
    normalMs: values.has("normal") ? median(values.get("normal")!) : null,
    reversedMs: values.has("reversed") ? median(values.get("reversed")!) : null,
  })).sort((a, b) => lower(b) - lower(a));
}

function lower(
  row: { normalMs: number | null; reversedMs: number | null },
): number {
  return Math.min(
    ...[row.normalMs, row.reversedMs].filter((value): value is number =>
      value !== null
    ),
  );
}

function fileRankings(bodies: Ranked[], root: string) {
  const files = new Map<
    string,
    {
      module: string;
      file: string;
      normalMs: number;
      reversedMs: number | null;
    }
  >();
  for (const body of bodies) {
    if (body.generated) continue;
    const path = body.location.replace(/:\d+:\d+$/, "");
    if (!isAbsolute(path) || relative(root, path).startsWith("..")) continue;
    const key = JSON.stringify([body.module, path]);
    const row = files.get(key) ??
      {
        module: body.module,
        file: relative(root, path),
        normalMs: 0,
        reversedMs: null,
      };
    row.normalMs += body.normalMs ?? 0;
    if (body.reversedMs !== null) {
      row.reversedMs = (row.reversedMs ?? 0) + body.reversedMs;
    }
    files.set(key, row);
  }
  return [...files.values()].sort((a, b) => lower(b) - lower(a));
}

function csv(rows: object[], fields: string[]): string {
  const cell = (value: unknown) =>
    `"${String(value ?? "").replaceAll('"', '""')}"`;
  return [
    fields.join(","),
    ...rows.map((row) =>
      fields.map((field) => cell((row as Record<string, unknown>)[field])).join(
        ",",
      )
    ),
  ].join("\n") + "\n";
}

async function execute(command: string[], cwd: string) {
  const result = await new Deno.Command(command[0], {
    args: command.slice(1),
    cwd,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const decode = new TextDecoder();
  return {
    code: result.code,
    text: decode.decode(result.stdout) + "\n" + decode.decode(result.stderr),
  };
}

async function refreshDatabase(root: string, directory: string) {
  const refreshed = await execute([
    "python3",
    join(root, "tools/gen_swift_compdb.py"),
    directory,
  ], root);
  if (refreshed.code || refreshed.text.includes("WARNING: no swiftc command")) {
    throw new Error(`Swift database regeneration failed:\n${refreshed.text}`);
  }
}

async function main(args: string[]): Promise<number> {
  if (args.includes("--help")) {
    console.log(HELP);
    return 0;
  }
  const options = parseOptions(args);
  const root = Deno.cwd();
  const directory = resolve(root, "build/debug");
  const database = join(directory, "compile_commands.json");
  let exists = true;
  try {
    await Deno.stat(database);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    exists = false;
  }
  if (!exists) {
    if (!options.build) {
      throw new Error(
        "no Debug compilation database; omit --no-build to prepare dependencies",
      );
    }
    await runBuild(
      options.modules.length && !options.files.length
        ? options.modules
        : ["porydaw"],
      "debug",
    );
  }
  await refreshDatabase(root, directory);
  let jobs = selectModules(
    discoverModules(JSON.parse(await Deno.readTextFile(database)), root),
    options,
    root,
  );
  if (options.build && exists) {
    await runBuild(jobs.map((job) => job.module), "debug");
    await refreshDatabase(root, directory);
    jobs = selectModules(
      discoverModules(JSON.parse(await Deno.readTextFile(database)), root),
      options,
      root,
    );
  }
  const output = resolve(
    root,
    options.output ??
      join(
        "build/swift-timings",
        new Date().toISOString().replaceAll(":", "-"),
      ),
  );
  await Deno.mkdir(dirname(output), { recursive: true });
  await Deno.mkdir(output);
  const files = options.files.map((file) => resolve(root, file));
  const hashes: Record<string, string> = {};
  for (const source of new Set(jobs.flatMap((job) => job.sources))) {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      await Deno.readFile(source),
    );
    hashes[relative(root, source)] = [...new Uint8Array(digest)].map((byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("");
  }
  const compilers: Record<string, string> = {};
  for (const program of new Set(jobs.map((job) => job.command[0]))) {
    const version = await execute([program, "--version"], root);
    if (version.code) {
      throw new Error(`compiler version query failed: ${version.text}`);
    }
    compilers[program] = version.text.trim();
  }
  const measurements: Measurement[] = [];
  for (let iteration = 1; iteration <= options.repeat; iteration++) {
    for (
      const order of options.order === "both"
        ? ["normal", "reversed"]
        : ["normal"]
    ) {
      for (const job of jobs) {
        const command = timingCommand(
          job,
          order === "reversed",
          files.length > 0,
        );
        let commands = [command];
        if (files.length) {
          const printed = await execute(command, job.cwd);
          if (printed.code) {
            throw new Error(`frontend discovery failed: ${printed.text}`);
          }
          commands = selectedFrontendJobs(
            printed.text,
            files.filter((file) => job.sources.includes(file)),
            job.cwd,
          );
        }
        const start = performance.now();
        let text = "";
        let exit = 0;
        for (const invocation of commands) {
          const result = await execute(invocation, job.cwd);
          text += result.text;
          if (result.code) {
            exit = result.code;
            break;
          }
        }
        const wallMs = performance.now() - start;
        const log = `${job.module}.${order}.${iteration}.log`;
        await Deno.writeTextFile(join(output, log), text);
        const timings = parseTimings(text, root);
        if (!exit && !timings.some((timing) => timing.symbol !== undefined)) {
          exit = 1;
        }
        measurements.push({
          module: job.module,
          order,
          iteration,
          wallMs,
          exit,
          log,
          commands,
          timings,
        });
        console.log(
          `${job.module} ${order} #${iteration}: ${
            (wallMs / 1000).toFixed(2)
          }s, ${timings.length} timing rows${
            exit ? ` FAILED (see ${join(output, log)})` : ""
          }`,
        );
      }
    }
  }
  const sourceFilter = (row: Ranked) =>
    !files.length || row.generated ||
    files.some((file) => row.location.startsWith(file + ":"));
  const bodies = rankTimings(measurements, true).filter(sourceFilter);
  const expressions = rankTimings(measurements, false).filter(sourceFilter);
  const authored = bodies.filter((row) => !row.generated);
  const generated = bodies.filter((row) => row.generated);
  const rankedFiles = fileRankings(authored, root);
  const failed = measurements.some((measurement) => measurement.exit !== 0);
  const report = {
    schemaVersion: 1,
    status: failed ? "failed" : "ok",
    metric:
      "Debug function-body type-checking ms; file sums exclude generated bodies. Expressions overlap bodies. Shared/lazy work remains order-sensitive; not total compilation time.",
    root,
    created: new Date().toISOString(),
    options,
    compilers,
    sourceHashes: hashes,
    moduleCommands: jobs,
    measurements,
    functions: authored,
    generated,
    expressions,
    files: rankedFiles,
  };
  await Deno.writeTextFile(
    join(output, "report.json"),
    JSON.stringify(report, null, 2) + "\n",
  );
  const timingFields = [
    "module",
    "location",
    "symbol",
    "generated",
    "normalMs",
    "reversedMs",
  ];
  for (
    const [name, rows, fields] of [
      ["functions", authored, timingFields],
      ["generated", generated, timingFields],
      ["expressions", expressions, timingFields],
      ["files", rankedFiles, ["module", "file", "normalMs", "reversedMs"]],
    ] as const
  ) {
    await Deno.writeTextFile(
      join(output, `${name}.csv`),
      csv(rows, [...fields]),
    );
  }
  const ms = (value: number | null) => value === null ? "—" : value.toFixed(2);
  console.log(
    "\nAuthored functions: normal / reversed ms (ranked by lower measurement)",
  );
  for (const row of authored.slice(0, options.top)) {
    console.log(
      `${ms(row.normalMs)} / ${
        ms(row.reversedMs)
      }  ${row.location}  ${row.symbol}`,
    );
  }
  console.log("\nFiles: summed authored bodies, normal / reversed ms");
  for (const row of rankedFiles.slice(0, options.top)) {
    console.log(`${ms(row.normalMs)} / ${ms(row.reversedMs)}  ${row.file}`);
  }
  console.log("\nExpressions: normal / reversed ms (overlap function timings)");
  for (const row of expressions.slice(0, options.top)) {
    console.log(`${ms(row.normalMs)} / ${ms(row.reversedMs)}  ${row.location}`);
  }
  console.log(
    `\n${generated.length} generated bodies reported separately. Report: ${output}`,
  );
  return failed ? 1 : 0;
}

if (import.meta.main) {
  try {
    Deno.exit(await main(Deno.args));
  } catch (error) {
    console.error(
      `bench:swift-compile: ${error instanceof Error ? error.message : error}`,
    );
    Deno.exit(1);
  }
}
