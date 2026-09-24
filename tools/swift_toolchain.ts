import { join } from "node:path";
import { swiftToolchainArgument } from "./local_build_environment.ts";

export type SwiftCompiler = {
  executable: string;
  args: string[];
};

export function compilerArguments(
  command: string,
  windows = Deno.build.os === "windows",
): string[] {
  const args: string[] = [];
  let word = "";
  let quote = "";
  let started = false;
  for (let index = 0; index < command.length; index++) {
    const char = command[index];
    const next = command[index + 1];
    if (windows && char === "\\") {
      let end = index;
      while (command[end] === "\\") end++;
      const count = end - index;
      if (command[end] === '"') {
        word += "\\".repeat(Math.floor(count / 2));
        if (count % 2) {
          word += '"';
          index = end;
        } else {
          index = end - 1;
        }
      } else {
        word += "\\".repeat(count);
        index = end - 1;
      }
      started = true;
      continue;
    }
    if (char === "\\" && quote !== "'" && next !== undefined) {
      if (
        next === '"' || next === "\\" ||
        (!quote && (next === "'" || /\s/.test(next)))
      ) {
        word += next;
        index++;
        started = true;
        continue;
      }
    }
    if (char === quote) {
      quote = "";
      started = true;
    } else if (!quote && (char === '"' || (!windows && char === "'"))) {
      quote = char;
      started = true;
    } else if (!quote && /\s/.test(char)) {
      if (started) args.push(word);
      word = "";
      started = false;
    } else {
      word += char;
      started = true;
    }
  }
  if (quote) throw new Error("Unterminated quote in Swift compiler arguments");
  if (started) args.push(word);
  return args;
}

export async function selectedSwiftCompiler(
  buildDirectory: string,
  root = Deno.cwd(),
): Promise<SwiftCompiler> {
  let cache = "";
  try {
    cache = await Deno.readTextFile(join(buildDirectory, "CMakeCache.txt"));
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const argument = await swiftToolchainArgument(root);
  const cached = /^CMAKE_Swift_COMPILER:[^=]+=(.+)$/m.exec(cache)?.[1];
  const executable = argument?.slice("-DCMAKE_Swift_COMPILER=".length) ||
    (cached?.endsWith("-NOTFOUND") ? undefined : cached);
  if (executable) {
    const args = /^CMAKE_Swift_COMPILER_ARG1:[^=]+=(.*)$/m.exec(cache)?.[1] ||
      "";
    return { executable, args: compilerArguments(args) };
  }
  const command = Deno.env.get("SWIFTC") || "swiftc";
  if (!/["']|\s-/.test(command)) {
    try {
      if ((await Deno.stat(command)).isFile) {
        return { executable: command, args: [] };
      }
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
  }
  const [program, ...args] = compilerArguments(command);
  if (!program) throw new Error("SWIFTC must specify a compiler executable");
  return { executable: program, args };
}

async function runCompiler(compiler: SwiftCompiler, args: string[]) {
  try {
    const result = await new Deno.Command(compiler.executable, {
      args: [...compiler.args, ...args],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const decoder = new TextDecoder();
    return {
      success: result.success,
      output: [decoder.decode(result.stdout), decoder.decode(result.stderr)]
        .map((output) => output.trim()).filter(Boolean).join("\n"),
    };
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return { success: false, output: "" };
    }
    throw error;
  }
}

export async function checkSwiftCompiler(
  selected: string | SwiftCompiler,
  { link = true }: { link?: boolean } = {},
): Promise<string | undefined> {
  const compiler = typeof selected === "string"
    ? { executable: selected, args: [] }
    : selected;
  const installHint =
    "Install Swift 6.4 or newer: https://www.swift.org/install/";
  const version = await runCompiler(compiler, ["--version"]);
  if (!version.success) {
    return `Swift compiler '${compiler.executable}' is missing or cannot run. ${installHint}\n${version.output}`;
  }
  const match = /Swift version (\d+)\.(\d+)/.exec(version.output);
  if (
    !match || Number(match[1]) < 6 ||
    (Number(match[1]) === 6 && Number(match[2]) < 4)
  ) {
    return `Swift 6.4 or newer is required; found ${version.output}. ${installHint}`;
  }
  if (!link) return undefined;
  const directory = await Deno.makeTempDir({ prefix: "porydaw-swift-" });
  try {
    const source = join(directory, "probe.swift");
    await Deno.writeTextFile(source, 'print("Porydaw Swift probe")\n');
    const result = await runCompiler(compiler, [
      "-swift-version",
      "6",
      source,
      "-o",
      join(directory, Deno.build.os === "windows" ? "probe.exe" : "probe"),
    ]);
    if (!result.success) {
      return `Swift compiler '${compiler.executable}' cannot compile and link a Swift 6.4 program:\n${result.output}`;
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}
