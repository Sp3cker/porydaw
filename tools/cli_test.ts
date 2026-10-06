// The root help in cli.ts lists every deno.json task, one line each, so an
// incoming agent finds their lane in one place. Deterministic, no subprocesses.
import { ROOT_HELP } from "./cli.ts";

Deno.test("root help matches the deno.json task table", async () => {
  const tasks = JSON.parse(await Deno.readTextFile("deno.json"))
    .tasks as Record<
      string,
      string
    >;
  const lines = ROOT_HELP.split("\n");
  for (const name of Object.keys(tasks)) {
    const present = lines.some((line) =>
      line.startsWith(`  ${name} `) || line === `  ${name}`
    );
    if (!present) throw new Error(`task '${name}' missing from ROOT_HELP`);
  }
  for (const line of lines) {
    // Task names start with a letter; option lines (--flag) never match.
    const task = line.match(/^  ([A-Za-z][\w:]*)( |$)/)?.[1];
    if (task && !Object.hasOwn(tasks, task)) {
      throw new Error(
        `ROOT_HELP lists '${task}', missing from deno.json tasks`,
      );
    }
  }
});
