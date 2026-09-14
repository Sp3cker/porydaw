// Shared by the public CLI (before building) and the check runner.
// Keep Qt's terminal payload opaque: only the runner options are ours to parse.
export const DEFAULT_CHECK_POOL = Math.max(
  1,
  Math.min(6, navigator.hardwareConcurrency),
);

export const VERIFY_HELP =
  `usage: deno task verify [options] [--qt <Qt arguments...>]
  default: build, then run all non-opt-in checks
  --filter <name>       substring match; repeatable; includes opt-in checks
  --exclude <name>      exclude exact harness name; repeatable
  --all                include opt-in checks
  --no-windowing-checks omit checks requiring the native desktop
  --reporter quiet|verbose  default: quiet
  --verbose, -v        show per-harness results
  --pool=<n>           offscreen workers: 1..64 (default: ${DEFAULT_CHECK_POOL})
  --help               show this help without building
  --qt <args...>       Qt arguments for ONE harness selected by --filter;
                      all following arguments belong to Qt, not this runner

Examples:
  deno task verify --filter=automation-presentation
  deno task verify --filter=automation-presentation --qt -functions
  deno task verify --filter=automation-presentation --qt selectedInactiveParametersKeepScopeIndicators

--qt does not select a harness. --no-build is not supported; builds are incremental.`;

export interface CheckOptions {
  selection: "--default" | "--all" | "--no-windowing-checks";
  reporterMode: "quiet" | "verbose";
  filters: string[];
  exclusions: string[];
  poolSize: number;
  qtPayload: string[] | undefined;
  help: boolean;
}

export function parseCheckOptions(args: readonly string[]): CheckOptions {
  const options: CheckOptions = {
    selection: "--default",
    reporterMode: "quiet",
    filters: [],
    exclusions: [],
    poolSize: DEFAULT_CHECK_POOL,
    qtPayload: undefined,
    help: false,
  };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--qt") {
      options.qtPayload = args.slice(i + 1);
      if (options.qtPayload.length === 0) {
        throw new Error(
          "--qt requires Qt arguments; use --filter=<harness> --qt -functions to list functions",
        );
      }
      break;
    }
    if (arg === "--help") {
      options.help = true;
    } else if (arg === "--all" || arg === "--no-windowing-checks") {
      options.selection = arg;
    } else if (arg === "--verbose") {
      options.reporterMode = "verbose";
    } else if (arg.startsWith("--pool=")) {
      const value = Number(arg.slice("--pool=".length));
      if (!Number.isInteger(value) || value < 1 || value > 64) {
        throw new Error(
          "--pool requires an integer from 1 to 64; use --pool=<n>",
        );
      }
      options.poolSize = value;
    } else if (
      arg === "--filter" || arg.startsWith("--filter=") ||
      arg === "--exclude" || arg.startsWith("--exclude=") ||
      arg === "--reporter" || arg.startsWith("--reporter=")
    ) {
      const separator = arg.indexOf("=");
      const flag = separator === -1 ? arg : arg.slice(0, separator);
      const value = separator === -1 ? args[++i] : arg.slice(separator + 1);
      if (!value || (separator === -1 && value.startsWith("-"))) {
        throw new Error(`${flag} requires a value`);
      }
      if (flag === "--filter") options.filters.push(value);
      else if (flag === "--exclude") options.exclusions.push(value);
      else if (value === "quiet" || value === "verbose") {
        options.reporterMode = value;
      } else {
        throw new Error("--reporter must be quiet or verbose");
      }
    } else if (arg === "--no-build") {
      throw new Error(
        "--no-build is not supported; omit it (verification builds incrementally)",
      );
    } else {
      throw new Error(`unknown argument ${arg}`);
    }
  }
  return options;
}
