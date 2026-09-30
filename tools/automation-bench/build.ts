import { join, resolve } from "node:path";
import { runBuild } from "../build.ts";

if (Deno.build.os !== "darwin") {
  throw new Error("automation-bench currently targets macOS Instruments");
}
if (Deno.args.length !== 0) {
  throw new Error(
    "Usage: deno task automation-bench:build (optimized, with symbols)",
  );
}
const directory = await runBuild(["automation_bench"], "release", true);
const binary = resolve(join(directory, "automation-bench"));
const result = await new Deno.Command("xcrun", {
  args: ["dsymutil", binary, "-o", `${binary}.dSYM`],
  stdout: "inherit",
  stderr: "inherit",
}).output();
if (!result.success) Deno.exit(result.code);
console.log(`Benchmark: ${binary}`);
console.log(`Symbols: ${binary}.dSYM`);
