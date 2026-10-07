// Streaming XML for xctrace exports: SAX over the export's stdout builds small
// element trees, resolving xctrace's id/ref reuse in document order.
//
// Discovered xctrace column names (see tables.ts for row shapes):
//   cpu-profile : time/sample-time, thread/thread, process/process, core/core,
//                 thread-state/thread-state, weight/cycle-weight, stack/tagged-backtrace
//   time-profile: same, but weight/weight
//   os-signpost : time/event-time, thread/thread, process/process,
//                 event-type/event-type, scope/string, identifier/os-signpost-identifier,
//                 name/signpost-name, format-string/format-string, backtrace/text-backtrace
//                 (empty cells export as <sentinel/>), subsystem/subsystem,
//                 category/category, message/os-log-metadata, emit-location/return-location
//   toc run info: target/device/process/environment, summary/start-date/end-date/
//                 duration/template-name, processes/process, data/table[@schema]
import { SaxesParser } from "saxes";

/** One element; ref'd elements are the shared, read-only id definition. */
export interface XmlElement {
  readonly name: string;
  readonly attrs: Readonly<Record<string, string>>;
  readonly children: XmlElement[];
  text: string;
}

export function firstLine(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.split("\n")[0];
}

/** First child named `name`. */
export function child(
  element: XmlElement | undefined,
  name: string,
): XmlElement | undefined {
  return element?.children.find((candidate) => candidate.name === name);
}

export function children(
  element: XmlElement | undefined,
  name: string,
): XmlElement[] {
  return element?.children.filter((candidate) => candidate.name === name) ??
    [];
}

/** Attribute value, or "" when absent. */
export function attr(element: XmlElement | undefined, name: string): string {
  return element?.attrs[name] ?? "";
}

/** Trimmed text; "" for absent or empty (<sentinel/>) cells. */
export function text(element: XmlElement | undefined): string {
  return element?.text.trim() ?? "";
}

/** Numeric leaf value; NaN when absent/unparsable (callers decide strictness). */
export function num(element: XmlElement | undefined): number {
  const raw = text(element);
  return raw ? Number(raw) : NaN;
}

/**
 * Run `xcrun <args>` and yield each closed element named in `names`, detached
 * from its parent so consumed rows are never retained.
 */
export async function* exportElements(
  args: string[],
  names: Readonly<Record<string, true>>,
): AsyncGenerator<XmlElement> {
  let process: Deno.ChildProcess;
  try {
    process = new Deno.Command("xcrun", {
      args,
      stdin: "null",
      stdout: "piped",
      stderr: "piped",
    }).spawn();
  } catch (error) {
    throw new Error(`xcrun failed to start: ${firstLine(error)}`);
  }
  const stderr = new Response(process.stderr).text();
  const parser = new SaxesParser();
  const ids = new Map<string, XmlElement>();
  const open: XmlElement[] = [];
  let ready: XmlElement[] = [];
  const appendText = (value: string) => {
    const top = open.at(-1);
    if (top) top.text += value;
  };
  parser.on("opentag", (tag) => {
    open.push({
      name: tag.name,
      attrs: tag.attributes,
      children: [],
      text: "",
    });
  });
  parser.on("text", appendText);
  parser.on("cdata", appendText);
  parser.on("closetag", () => {
    let element = open.pop()!;
    const ref = element.attrs.ref;
    if (ref !== undefined) {
      const target = ids.get(ref);
      if (target === undefined) throw new Error(`unresolved ref ${ref}`);
      element = target;
    } else if (element.attrs.id !== undefined) {
      ids.set(element.attrs.id, element);
    }
    if (Object.hasOwn(names, element.name)) ready.push(element);
    else open.at(-1)?.children.push(element);
  });
  const feed = (chunk: string | null) => {
    try {
      if (chunk === null) parser.close();
      else parser.write(chunk);
    } catch (error) {
      throw new Error(`unparsable XML: ${firstLine(error)}`);
    }
    const batch = ready;
    ready = [];
    return batch;
  };
  let finished = false;
  try {
    for await (
      const chunk of process.stdout.pipeThrough(new TextDecoderStream())
    ) {
      yield* feed(chunk);
    }
    const status = await process.status;
    finished = true;
    if (!status.success) {
      throw new Error(
        `xcrun ${args[0] ?? ""} failed: ${
          firstLine((await stderr).trim() || `code ${status.code}`)
        }`,
      );
    }
    yield* feed(null);
  } finally {
    if (!finished) {
      try {
        process.kill();
      } catch {
        // Already exited.
      }
    }
  }
}
