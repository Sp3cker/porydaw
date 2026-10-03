// Measures a fresh Release process through a selected native submitted-frame marker.
import { join, resolve } from "node:path";
import { usesMultiConfigBuild } from "./build.ts";

const HELP = `usage: deno task bench:startup [options]
  --runs <count>       fresh process launches (default 11)
  --until <stage>      first-frame|chrome-frame|workspace-frame|editor-frame (default first-frame)
  --project <path>     project root passed to the app (optional)
  --song <label>       song label passed to the app (optional)
  --budget-ms <ms>     user-set selected-frame ceiling (default 300)
  --timeout-ms <ms>    deadline per launch (default 10000)
  --check             exit 1 if ANY run misses the budget, including run 1
  --help              show this help without launching

Requires an existing Release app: deno task build:app --release
Does not build or use 'open'; only its own spawned processes are terminated.
Measures monotonic process-spawn to receipt of the selected native frame marker.
Each frame marker is QQuickWindow::frameSwapped: a frame queued for presentation,
not physical display scanout. Process creation and dynamic loading are included.
content-ready/workspace-ready record construction, not submitted frames.
chrome-frame follows shell mounting; workspace-frame follows workspace mounting.
Neither guarantees restored-song, editor or audio readiness. editor-frame follows
a visible selected loaded piano-roll document with a positive viewport, a nonzero
display revision and an applied document revision, then a submitted frame.
It does not establish audio readiness or physical display scanout.
Run 1 is reported separately (not guaranteed cold); subsequent runs are warm.
All-run compliance includes run 1. Exit/timeout/launch failures always exit 2.
The budget is a chosen ceiling, not a performance guarantee; 300 is retained
as the compatibility default.
Omitted project/song options retain the app's normal saved-session behavior.
The app is stopped at the selected frame.

Example:
  deno task bench:startup --until editor-frame --project /path/to/project --song mus_title --check`;

type FrameStage =
  | "first-frame"
  | "chrome-frame"
  | "workspace-frame"
  | "editor-frame";

interface Options {
  runs: number;
  until: FrameStage;
  budgetMs: number;
  timeoutMs: number;
  project?: string;
  song?: string;
  check: boolean;
}

type Outcome =
  | { kind: "frame"; ms: number }
  | { kind: "failure"; message: string }
  | { kind: "interrupted"; message: string };

function parseOptions(args: string[]): Options {
  const options: Options = {
    runs: 11,
    until: "first-frame",
    budgetMs: 300,
    timeoutMs: 10000,
    check: false,
  };
  for (let i = 0; i < args.length; i++) {
    const [flag, ...inline] = args[i].split("=");
    if (flag === "--check" && inline.length === 0) {
      options.check = true;
      continue;
    }
    if (
      ![
        "--runs",
        "--until",
        "--budget-ms",
        "--timeout-ms",
        "--project",
        "--song",
      ]
        .includes(flag)
    ) throw new Error(`unknown argument ${args[i]}`);
    const value = inline.length ? inline.join("=") : args[++i];
    if (!value || value.startsWith("--")) {
      throw new Error(`${flag} requires a value`);
    }
    if (flag === "--project") options.project = resolve(value);
    else if (flag === "--song") options.song = value;
    else if (flag === "--until") {
      if (
        value !== "first-frame" && value !== "chrome-frame" &&
        value !== "workspace-frame" && value !== "editor-frame"
      ) {
        throw new Error(
          "--until requires first-frame, chrome-frame, workspace-frame, or editor-frame",
        );
      }
      options.until = value;
    } else {
      const number = Number(value);
      if (!Number.isFinite(number) || number <= 0) {
        throw new Error(`${flag} requires a positive finite number`);
      }
      if (flag === "--runs") {
        if (!Number.isSafeInteger(number)) {
          throw new Error("--runs requires a positive safe integer");
        }
        options.runs = number;
      } else if (flag === "--budget-ms") options.budgetMs = number;
      else {
        if (number > 2147483647) {
          throw new Error("--timeout-ms exceeds the timer limit (2147483647)");
        }
        options.timeoutMs = number;
      }
    }
  }
  return options;
}

function signalChild(child: Deno.ChildProcess, signal: Deno.Signal): void {
  try {
    child.kill(signal);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}

async function stopChild(child: Deno.ChildProcess): Promise<void> {
  signalChild(child, "SIGTERM");
  const force = setTimeout(() => signalChild(child, "SIGKILL"), 500);
  try {
    await child.status;
  } finally {
    clearTimeout(force);
  }
}

async function measure(
  binary: string,
  root: string,
  options: Options,
  run: number,
): Promise<Outcome> {
  const args: string[] = [];
  if (options.project) args.push("--project", options.project);
  if (options.song) args.push("--song", options.song);
  const command = new Deno.Command(binary, {
    args,
    cwd: root,
    env: { PORYDAW_STARTUP_TRACE: "1" },
    stdin: "null",
    stdout: "inherit",
    stderr: "piped",
  });
  const started = performance.now();
  const child = command.spawn();
  const reader = child.stderr.getReader();
  const decoder = new TextDecoder();
  const diagnostics: string[] = [];
  const stages: string[] = [];
  let pending = "";
  let reaped = false;
  const result = Promise.withResolvers<Outcome>();
  const interrupt = () =>
    result.resolve({
      kind: "interrupted",
      message:
        `interrupted before ${options.until} marker; stopped the spawned app`,
    });
  Deno.addSignalListener("SIGINT", interrupt);
  if (Deno.build.os !== "windows") {
    Deno.addSignalListener("SIGTERM", interrupt);
  }
  const deadline = setTimeout(() =>
    result.resolve({
      kind: "failure",
      message:
        `TIMEOUT: no ${options.until} marker within ${options.timeoutMs} ms`,
    }), Math.max(0, options.timeoutMs - (performance.now() - started)));

  function line(text: string): void {
    const marker = text.replace(/\r?\n$/, "");
    if (marker === `PORYDAW_STARTUP_TRACE ${options.until}`) {
      const ms = performance.now() - started;
      result.resolve(
        ms < options.timeoutMs ? { kind: "frame", ms } : {
          kind: "failure",
          message: `TIMEOUT: ${options.until} marker arrived after ${
            ms.toFixed(2)
          } ms`,
        },
      );
    }
    if (marker.startsWith("PORYDAW_STARTUP_TRACE ")) stages.push(marker);
    else diagnostics.push(text);
  }

  const consume = (async () => {
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        pending += decoder.decode(value, { stream: true });
        let newline: number;
        while ((newline = pending.indexOf("\n")) !== -1) {
          line(pending.slice(0, newline + 1));
          pending = pending.slice(newline + 1);
        }
      }
      pending += decoder.decode();
      if (pending) line(pending);
    } catch (error) {
      diagnostics.push(`stderr read failed: ${error}\n`);
      result.resolve({
        kind: "failure",
        message: `stderr read failed before ${options.until} marker: ${error}`,
      });
    }
  })();
  const exited = child.status.then(async (status) => {
    reaped = true;
    await consume;
    result.resolve({
      kind: "failure",
      message: `EXIT before ${options.until} marker: code ${status.code}` +
        (status.signal ? ` (${status.signal})` : ""),
    });
  });

  let outcome: Outcome;
  try {
    outcome = await result.promise;
  } finally {
    clearTimeout(deadline);
    try {
      if (!reaped) await stopChild(child);
    } finally {
      // Drain diagnostics after reap, without hanging on inherited pipe handles.
      const cancel = setTimeout(() => void reader.cancel(), 250);
      try {
        await consume;
        await exited;
      } finally {
        clearTimeout(cancel);
        reader.releaseLock();
        Deno.removeSignalListener("SIGINT", interrupt);
        if (Deno.build.os !== "windows") {
          Deno.removeSignalListener("SIGTERM", interrupt);
        }
      }
    }
  }
  if (diagnostics.length) {
    console.error(`--- run ${run} app stderr ---`);
    const text = diagnostics.join("");
    console.error(text.endsWith("\n") ? text.slice(0, -1) : text);
  }
  if (outcome.kind !== "frame" && stages.length) {
    console.error(`run ${run} trace stages: ${stages.join("; ")}`);
  }
  return outcome;
}

function summary(
  label: string,
  outcomes: Outcome[],
  budget: number,
  stage: FrameStage,
): boolean {
  const samples = outcomes.flatMap((outcome) =>
    outcome.kind === "frame" ? [outcome.ms] : []
  ).sort((a, b) => a - b);
  const missed = samples.filter((ms) => ms >= budget).length;
  const failed = outcomes.length - samples.length;
  const pass = outcomes.length > 0 && missed === 0 && failed === 0;
  if (samples.length) {
    const middle = Math.floor(samples.length / 2);
    const median = samples.length % 2
      ? samples[middle]
      : (samples[middle - 1] + samples[middle]) / 2;
    console.log(
      `${label}: ${samples.length}/${outcomes.length} ${stage} frames; ` +
        `median ${median.toFixed(2)} ms, min ${samples[0].toFixed(2)} ms, ` +
        `max ${samples.at(-1)!.toFixed(2)} ms`,
    );
  } else {console.log(
      `${label}: no ${stage} samples (${outcomes.length} runs)`,
    );}
  console.log(
    `  Budget <${budget} ms: ${pass ? "PASS" : "FAIL"}; ` +
      `${missed}/${outcomes.length} at or above budget; ${failed} failed launches`,
  );
  return pass;
}

async function main(): Promise<number> {
  if (Deno.args.includes("--help")) {
    console.log(HELP);
    return 0;
  }
  const options = parseOptions(Deno.args);
  const root = await Deno.realPath(new URL("..", import.meta.url));
  const directory = join(root, "build", "release");
  const binary = join(
    directory,
    ...(await usesMultiConfigBuild(directory) ? ["Release"] : []),
    ...(Deno.build.os === "darwin"
      ? ["porydaw.app", "Contents", "MacOS", "porydaw"]
      : [Deno.build.os === "windows" ? "porydaw.exe" : "porydaw"]),
  );
  try {
    if (!(await Deno.stat(binary)).isFile) throw new Error("not a file");
  } catch (error) {
    throw new Error(
      `Release executable unavailable for ${options.until}: ${binary}\n` +
        `Build first: deno task build:app --release\n${error}`,
    );
  }
  console.log(`Release executable: ${binary}`);
  console.log(
    `App selection: ${
      JSON.stringify({ project: options.project, song: options.song })
    }`,
  );
  console.log(
    `Metric: spawn to ${options.until} native frameSwapped (queued presentation, not display scanout)`,
  );
  console.log(
    `Fresh launches: ${options.runs}; ${options.until} budget <${options.budgetMs} ms`,
  );
  console.log(
    "Construction markers content-ready/workspace-ready are not submitted frames; " +
      "workspace-frame does not guarantee restored-song, editor or audio readiness.",
  );
  const outcomes: Outcome[] = [];
  for (let run = 1; run <= options.runs; run++) {
    let outcome: Outcome;
    try {
      outcome = await measure(binary, root, options, run);
    } catch (error) {
      outcome = {
        kind: "failure",
        message: `LAUNCH/CLEANUP failure for ${options.until}: ${error}`,
      };
    }
    outcomes.push(outcome);
    const label = run === 1 ? "first" : "warm";
    console.log(
      `Run ${run} (${label}): ` +
        (outcome.kind === "frame"
          ? `${options.until} ${outcome.ms.toFixed(2)} ms ${
            outcome.ms < options.budgetMs ? "PASS" : "FAIL budget"
          }`
          : outcome.message),
    );
    if (outcome.kind === "interrupted") break;
  }
  summary("First run", outcomes.slice(0, 1), options.budgetMs, options.until);
  if (outcomes.length > 1) {
    summary("Warm runs", outcomes.slice(1), options.budgetMs, options.until);
  } else console.log("Warm runs: none");
  const pass = summary(
    "All runs (including first)",
    outcomes,
    options.budgetMs,
    options.until,
  );
  if (outcomes.some((outcome) => outcome.kind !== "frame")) return 2;
  return options.check && !pass ? 1 : 0;
}

if (import.meta.main) {
  try {
    Deno.exit(await main());
  } catch (error) {
    console.error(
      `bench:startup: ${error instanceof Error ? error.message : error}`,
    );
    console.error("Use deno task bench:startup --help for usage.");
    Deno.exit(2);
  }
}
