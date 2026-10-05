// Interleaved startup comparison of two or more Release binaries.
//
// Serial runs of two binaries are not comparable: system load drifts by 15–80 %
// across minutes (indexing after a build, other apps), which is larger than any
// startup change under test. Alternating launches put both binaries under the
// same load, so only the relative numbers here are trustworthy.
import { measure, parseOptions } from "./startup_bench.ts";

const HELP =
  `usage: deno task bench:startup:ab [options] <label>=<binary> <label>=<binary> [...]
  --runs <count>       launches per binary, interleaved (default 11)
  --until <stage>      first-frame|chrome-frame|workspace-frame|editor-frame (default first-frame)
  --project <path>     project root passed to every app (optional)
  --song <label>       song label passed to every app (optional)
  --timeout-ms <ms>    deadline per launch (default 10000)
  --stages             also print median ms per PORYDAW_STARTUP_TRACE stage
  --help               show this help without launching

Binaries are the executables themselves (macOS: Foo.app/Contents/MacOS/porydaw).
Keep a copy of the baseline bundle outside build/ before rebuilding, e.g.
  cp -R build/release/porydaw.app /tmp/porydaw-baseline.app
  deno task bench:startup:ab --until editor-frame --stages \\
    old=/tmp/porydaw-baseline.app/Contents/MacOS/porydaw \\
    new=build/release/porydaw.app/Contents/MacOS/porydaw
Order alternates every round (A B, B A, ...). There is no budget and no pass/fail;
exit 2 if any launch fails or times out. Each launch stops at the selected marker.`;

interface Binary {
  label: string;
  path: string;
}

async function main(): Promise<number> {
  if (Deno.args.includes("--help")) {
    console.log(HELP);
    return 0;
  }
  const stages = Deno.args.includes("--stages");
  const binaries: Binary[] = [];
  const rest: string[] = [];
  for (const arg of Deno.args) {
    if (arg === "--stages") continue;
    const match = /^([^-=][^=]*)=(.+)$/.exec(arg);
    if (match) binaries.push({ label: match[1], path: match[2] });
    else rest.push(arg);
  }
  const options = parseOptions(rest);
  if (binaries.length < 2) {
    throw new Error("at least two <label>=<binary> arguments are required");
  }
  for (const binary of binaries) {
    const info = await Deno.stat(binary.path).catch(() => undefined);
    if (!info?.isFile) {
      throw new Error(`${binary.label}: not a file: ${binary.path}`);
    }
  }
  const root = await Deno.realPath(new URL("..", import.meta.url));
  console.log(
    `Metric: spawn to ${options.until} native frameSwapped; ${options.runs} interleaved launches per binary`,
  );
  for (const binary of binaries) {
    console.log(`  ${binary.label} = ${binary.path}`);
  }

  const samples: Record<string, number[]> = {};
  const failures: Record<string, number> = {};
  const stageSamples: Record<string, Record<string, number[]>> = {};
  for (const binary of binaries) {
    samples[binary.label] = [];
    failures[binary.label] = 0;
    stageSamples[binary.label] = {};
  }
  let failed = false;
  for (let run = 1; run <= options.runs; run++) {
    const order = run % 2 ? binaries : [...binaries].reverse();
    for (const binary of order) {
      const outcome = await measure(binary.path, root, options, run);
      if (outcome.kind === "frame") {
        samples[binary.label].push(outcome.ms);
        for (const [stage, ms] of Object.entries(outcome.stages)) {
          (stageSamples[binary.label][stage] ??= []).push(ms);
        }
        console.log(`run ${run} ${binary.label}: ${outcome.ms.toFixed(0)} ms`);
      } else {
        failures[binary.label]++;
        failed = true;
        console.log(`run ${run} ${binary.label}: ${outcome.message}`);
        if (outcome.kind === "interrupted") return 2;
      }
      // Let the previous process's teardown settle before the next spawn.
      const settle = Promise.withResolvers<void>();
      setTimeout(settle.resolve, 400);
      await settle.promise;
    }
  }

  const width = Math.max(...binaries.map((binary) => binary.label.length));
  for (const binary of binaries) {
    const sorted = [...samples[binary.label]].sort((a, b) => a - b);
    const line = sorted.length
      ? `median ${quantile(sorted, 0.5)}  p25 ${quantile(sorted, 0.25)}  p75 ${
        quantile(sorted, 0.75)
      }  min ${sorted[0].toFixed(0)}  max ${
        sorted[sorted.length - 1].toFixed(0)
      }`
      : "no samples";
    console.log(
      `${
        binary.label.padEnd(width)
      }  ${options.until}: n=${sorted.length} ${line}  failed launches ${
        failures[binary.label]
      }`,
    );
  }
  if (stages) {
    const first = binaries[0].label;
    const order = Object.entries(stageSamples[first])
      .map(([stage, ms]) =>
        [stage, quantile([...ms].sort((a, b) => a - b), 0.5)] as const
      )
      .sort((a, b) => Number(a[1]) - Number(b[1]));
    console.log(
      `\n${"median ms since spawn".padEnd(22)}` +
        binaries.map((binary) => binary.label.padStart(width + 2)).join(""),
    );
    for (const [stage] of order) {
      const cells = binaries.map((binary) => {
        const ms = stageSamples[binary.label][stage];
        return (ms ? quantile([...ms].sort((a, b) => a - b), 0.5) : "–")
          .padStart(width + 2);
      });
      console.log(`${stage.padEnd(22)}${cells.join("")}`);
    }
  }
  return failed ? 2 : 0;
}

// Nearest-rank quantile of an ascending array, formatted for the tables above.
function quantile(sorted: number[], p: number): string {
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))]
    .toFixed(0);
}

if (import.meta.main) {
  try {
    Deno.exit(await main());
  } catch (error) {
    console.error(
      `bench:startup:ab: ${error instanceof Error ? error.message : error}`,
    );
    console.error("Use deno task bench:startup:ab --help for usage.");
    Deno.exit(2);
  }
}
