// THROWAWAY launcher for the native-host prototype — NOT production code.
// Compiles native_host.cpp with pkg-config Qt6 flags into a temp dir and runs
// it against CompositionPrototype.qml next to this file.
// Build/run via: deno run --allow-run --allow-read --allow-write --allow-env src/ui/songview/quick/composition-prototype/native_host.ts [--build-only]
import { fileURLToPath } from "node:url";

const dir = fileURLToPath(new URL(".", import.meta.url));
const cpp = dir + "native_host.cpp";
const qml = dir + "CompositionPrototype.qml";
const buildOnly = Deno.args.includes("--build-only");

class FlagsError extends Error {
  constructor(readonly code: number) {
    super("pkg-config failed");
  }
}

async function flags(args: string[]): Promise<string[]> {
  const out = await new Deno.Command("pkg-config", {
    args: [...args, "Qt6Widgets", "Qt6Quick", "Qt6Qml"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!out.success) {
    console.error(new TextDecoder().decode(out.stderr));
    throw new FlagsError(out.code);
  }
  return new TextDecoder().decode(out.stdout).trim().split(/\s+/);
}

const tmp = await Deno.makeTempDir({ prefix: "porydaw-native-host-" });
const bin = tmp + "/native_host";

try {
  const compile = new Deno.Command("clang++", {
    args: [
      "-std=c++20",
      "-O0",
      "-g",
      "-fPIC",
      ...(await flags(["--cflags"])),
      cpp,
      ...(await flags(["--libs"])),
      "-o",
      bin,
    ],
    stdout: "inherit",
    stderr: "inherit",
  });
  const compiled = await compile.output();
  if (!compiled.success) {
    Deno.exitCode = compiled.code;
  } else if (buildOnly) {
    console.log("native host compile verified; removing temporary build dir");
  } else {
    console.log("native host binary:", bin);
    const child = new Deno.Command(bin, {
      args: [qml],
      stdout: "inherit",
      stderr: "inherit",
      stdin: "inherit",
    }).spawn();

    // Forward termination so hub stopping the launcher kills the GUI child.
    const forward = (sig: "SIGINT" | "SIGTERM") => () => {
      try {
        child.kill(sig);
      } catch { /* already gone */ }
    };
    const onSigint = forward("SIGINT");
    const onSigterm = forward("SIGTERM");
    Deno.addSignalListener("SIGINT", onSigint);
    Deno.addSignalListener("SIGTERM", onSigterm);
    try {
      const status = await child.status;
      Deno.exitCode = status.code;
    } finally {
      Deno.removeSignalListener("SIGINT", onSigint);
      Deno.removeSignalListener("SIGTERM", onSigterm);
    }
  }
} catch (e) {
  if (e instanceof FlagsError) Deno.exitCode = e.code;
  else throw e;
} finally {
  await Deno.remove(tmp, { recursive: true });
}
