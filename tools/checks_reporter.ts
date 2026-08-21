// Presentation layer for run_checks - quiet default, live name line, verbose fallback.
// Split from tools/run_checks.ts on execution/presentation seam (keep-files-small).

export interface CheckResult {
  readonly code: number;
  readonly output: string;
  readonly signal: string | null;
  readonly timedOut: boolean;
  readonly durationMs: number;
}

export interface Reporter {
  onCheckStart?(name: string): void;
  onCheckPass(
    name: string,
    durationMs: number,
    detail: string | undefined,
  ): void;
  onCheckFail(name: string, result: CheckResult): void;
  onSummary(
    failures: string[],
    suiteMs: number,
    total: number,
    runnable: number,
  ): void;
}

export function createReporter(
  mode: "quiet" | "verbose",
  total: number,
): Reporter {
  const isQuiet = mode === "quiet";
  const isTTY = Deno.stderr.isTerminal();
  let completed = 0;
  let current = "";

  function clearLive(): void {
    if (isQuiet && isTTY && current) {
      try {
        Deno.stderr.writeSync(new TextEncoder().encode("\r\x1b[K"));
      } catch {
        // ignore
      }
      current = "";
    }
  }

  function renderLive(name: string): void {
    if (!isQuiet || !isTTY) return;
    current = name;
    const line = `verify: ${name} (${completed}/${total})`;
    try {
      Deno.stderr.writeSync(new TextEncoder().encode(`\r${line}\x1b[K`));
    } catch {
      // ignore
    }
  }

  return {
    onCheckStart(name: string): void {
      renderLive(name);
    },
    onCheckPass(
      name: string,
      durationMs: number,
      detail: string | undefined,
    ): void {
      clearLive();
      completed++;
      if (!isQuiet) {
        const sec = (durationMs / 1000).toFixed(2);
        const suffix = detail ? ` — ${detail}` : "";
        console.log(`ok: ${name} (${sec}s)${suffix}`);
      }
    },
    onCheckFail(name: string, result: CheckResult): void {
      clearLive();
      completed++;
      const sec = (result.durationMs / 1000).toFixed(2);
      // Also emit legacy line for CI greps that look for run_checks: FAIL
      console.log(`not ok: ${name} (${sec}s)`);
      const output = result.output.trim();
      if (output) {
        const lines = output.split("\n");
        // Print last 40 lines like old printFailure
        console.log(lines.slice(-40).join("\n"));
      }
      if (result.timedOut) {
        console.log(`timed out after ${sec}s`);
      }
      if (result.signal) {
        console.log(`signal: ${result.signal}`);
      }
    },
    onSummary(
      failures: string[],
      suiteMs: number,
      totalManifest: number,
      runnable: number,
    ): void {
      clearLive();
      const sec = (suiteMs / 1000).toFixed(2);
      const skipped = totalManifest - runnable;
      const skippedPart = skipped > 0 ? `, ${skipped} skipped` : "";
      if (failures.length === 0) {
        // Primary human summary
        console.log(
          `\nverify: ${runnable}/${totalManifest} ok (${sec}s${skippedPart})`,
        );
        // Legacy line for CI greps that look for run_checks: PASS
        console.log(`run_checks: PASS (all harnesses in ${sec}s)`);
      } else {
        console.log(
          `\nverify: ${
            runnable - failures.length
          }/${totalManifest} ok, ${failures.length} failed (${sec}s${skippedPart})`,
        );
        console.log(
          `run_checks: FAIL (${failures.length}) ${failures.join(" ")}`,
        );
      }
    },
  };
}
