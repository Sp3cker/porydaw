// Table-of-contents handling: run metadata, template name, schema discovery.
import {
  child,
  childList,
  firstLine,
  isObj,
  parseXml,
  runCapture,
  text,
} from "./xml.ts";

export type SchemaName = "cpu-profile" | "time-profile" | "os-signpost";

export interface RunInfo {
  number: number;
  template: string;
  startEpoch: number;
  endEpoch: number;
  durationSec: number;
  schemas: string[];
}

function epochSeconds(value: string): number {
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) throw new Error(`unparsable TOC date ${value}`);
  return ms / 1000;
}

function runFromNode(node: unknown): RunInfo {
  const numAttr = isObj(node) &&
      typeof node["@_number"] === "string"
    ? Number(node["@_number"])
    : NaN;
  if (!isObj(node) || !Number.isSafeInteger(numAttr)) {
    throw new Error("unparsable TOC: run without a number");
  }
  const info = child(node, "info");
  const summary = child(info, "summary");
  const template = text(child(summary, "template-name")) ||
    "(unknown template)";
  const data = child(node, "data");
  const schemas: string[] = [];
  for (const table of childList(data, "table")) {
    if (isObj(table) && typeof table["@_schema"] === "string") {
      schemas.push(table["@_schema"]);
    }
  }
  return {
    number: numAttr,
    template,
    startEpoch: epochSeconds(text(child(summary, "start-date"))),
    endEpoch: epochSeconds(text(child(summary, "end-date"))),
    durationSec: Number(text(child(summary, "duration")) || "NaN"),
    schemas,
  };
}

/** Export --toc for a trace and return one RunInfo per run. */
export async function loadToc(trace: string): Promise<RunInfo[]> {
  let xml: string;
  try {
    xml = await runCapture("xcrun", [
      "xctrace",
      "export",
      "--input",
      trace,
      "--toc",
    ]);
  } catch (error) {
    throw new Error(`cannot read trace ${trace}: ${firstLine(error)}`);
  }
  const doc = parseXml(xml);
  const toc = child(doc, "trace-toc");
  const runs = childList(toc, "run").map(runFromNode);
  if (runs.length === 0) throw new Error(`unparsable TOC: no runs in ${trace}`);
  return runs;
}

export function findRun(runs: RunInfo[], number: number): RunInfo {
  const run = runs.find((candidate) => candidate.number === number);
  if (!run) {
    throw new Error(
      `run ${number} missing (trace has ${
        runs.map((r) => r.number).join(", ")
      })`,
    );
  }
  return run;
}

/** cpu-profile wins over time-profile wins over os-signpost: CPU Profiler
 *  template traces also carry PointsOfInterest os-signpost tables. */
export function inferSchema(run: RunInfo): SchemaName {
  const present: Record<string, true> = {};
  for (const schema of run.schemas) present[schema] = true;
  if (present["cpu-profile"]) return "cpu-profile";
  if (present["time-profile"]) return "time-profile";
  if (present["os-signpost"]) return "os-signpost";
  throw new Error(
    `no cpu-profile, time-profile or os-signpost table in run ${run.number}`,
  );
}

export function parseSchemaName(value: string): SchemaName {
  if (
    value === "cpu-profile" || value === "time-profile" ||
    value === "os-signpost"
  ) {
    return value;
  }
  throw new Error(
    `bad schema ${value} (want cpu-profile|time-profile|os-signpost)`,
  );
}
