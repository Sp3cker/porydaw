// Format porydaw's tracked C/C++ sources with the repo .clang-format,
// or verify they are already formatted.
//
// Usage: deno run -P=format tools/format.ts [--check] [files...]
//   no files: formats all tracked src/*.cpp, src/*.h, tools/*.cpp, tools/*.h
//   files:    formats only those paths (useful for `deno task format file.cc`)
// Env: CLANG_FORMAT overrides the clang-format executable.

const root = new URL("../", import.meta.url);
const decoder = new TextDecoder();
let check = false;
const explicitFiles: string[] = [];
for (const arg of Deno.args) {
  if (arg === "--check") {
    check = true;
  } else if (arg.startsWith("-")) {
    console.error("usage: deno task format[--:check] [files...]");
    Deno.exit(2);
  } else {
    explicitFiles.push(arg);
  }
}

async function capture(bin: string, args: string[]): Promise<string> {
  try {
    const output = await new Deno.Command(bin, {
      args,
      cwd: root,
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!output.success) {
      const detail = decoder.decode(output.stderr).trim();
      throw new Error(detail || `${bin} exited with ${output.code}`);
    }
    return decoder.decode(output.stdout);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(`${bin} not found`);
    }
    throw error;
  }
}

async function run(bin: string, args: string[]): Promise<boolean> {
  try {
    const command = new Deno.Command(bin, {
      args,
      cwd: root,
      stdin: "null",
      stdout: "inherit",
      stderr: "inherit",
    });
    return (await command.spawn().status).success;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      throw new Error(`${bin} not found`);
    }
    throw error;
  }
}

try {
  const clangFormat = Deno.env.get("CLANG_FORMAT") || "clang-format";
  const version = await capture(clangFormat, ["--version"]);
  const major = version.match(/\d+/)?.[0];
  if (major !== "22") {
    console.warn(
      `format: warning: clang-format major version ${
        major ?? "unknown"
      }, CI pins 22 — results may differ`,
    );
  }

  let files: string[];
  if (explicitFiles.length > 0) {
    files = [];
    for (const file of explicitFiles) {
      try {
        await Deno.stat(new URL(file, root));
        files.push(file);
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) {
          console.error(`format: not found: ${file}`);
          Deno.exit(2);
        }
        throw error;
      }
    }
  } else {
    const tracked = (await capture("git", [
      "ls-files",
      "src/*.cpp",
      "src/*.h",
      "tools/*.cpp",
      "tools/*.h",
    ])).split("\n").filter(Boolean);
    files = [];
    for (const file of tracked) {
      try {
        await Deno.stat(new URL(file, root));
        files.push(file);
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
    }
  }

  if (files.length === 0) throw new Error("no sources found");

  const args = check ? ["--dry-run", "--Werror", ...files] : ["-i", ...files];
  if (!(await run(clangFormat, args))) {
    if (check) {
      console.error(
        "format: formatting differences found — run deno task format",
      );
    }
    Deno.exit(1);
  }

  console.log(
    check
      ? `format: all ${files.length} C/C++ files formatted`
      : `format: formatted ${files.length} C/C++ files`,
  );
} catch (error) {
  console.error(`format: ${error instanceof Error ? error.message : error}`);
  Deno.exit(2);
}
