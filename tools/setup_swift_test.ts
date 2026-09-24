import { join } from "node:path";
import {
  checkSwiftCompiler,
  compilerArguments,
  selectedSwiftCompiler,
} from "./swift_toolchain.ts";
import {
  ensureNativeBuildTools,
  inspectNativeBuildTools,
} from "./native_build_tools.ts";

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function restoreEnvironment(name: string, value: string | undefined): void {
  if (value === undefined) Deno.env.delete(name);
  else Deno.env.set(name, value);
}

Deno.test("Swift command parsing preserves quoted and escaped arguments without evaluation", () => {
  equal(
    compilerArguments(
      '"/opt/Swift Toolchain/swiftc" -sdk "/opt/My SDK" -target aarch64-unknown-linux-gnu',
    ),
    [
      "/opt/Swift Toolchain/swiftc",
      "-sdk",
      "/opt/My SDK",
      "-target",
      "aarch64-unknown-linux-gnu",
    ],
  );
  equal(
    compilerArguments(
      "swiftc -sdk /opt/My\\ SDK -D '$(no-execution)' ''",
      false,
    ),
    ["swiftc", "-sdk", "/opt/My SDK", "-D", "$(no-execution)", ""],
  );
  equal(
    compilerArguments(
      '"C:\\Program Files\\Swift\\swiftc.exe" -sdk "C:\\My SDK"',
      true,
    ),
    ["C:\\Program Files\\Swift\\swiftc.exe", "-sdk", "C:\\My SDK"],
  );
  equal(
    compilerArguments(
      String.raw`"\\server\Swift tools\swiftc.exe" -sdk "C:\SDK\\"`,
      true,
    ),
    [String.raw`\\server\Swift tools\swiftc.exe`, "-sdk", "C:\\SDK\\"],
  );
  let rejected = false;
  try {
    compilerArguments('swiftc -sdk "unterminated');
  } catch {
    rejected = true;
  }
  equal(rejected, true);
});

Deno.test({
  name: "Swift probes retain environment and cached compiler options",
  ignore: Deno.build.os === "windows",
  async fn() {
    const root = await Deno.makeTempDir({ prefix: "porydaw-swift-args-" });
    const previous = Deno.env.get("SWIFTC");
    try {
      const executable = join(root, "swift compiler");
      await Deno.writeTextFile(
        executable,
        `#!/bin/sh
[ "$1" = "-sdk" ] && [ "$2" = "/SDK with spaces" ] || exit 3
shift 2
if [ "$1" = "--version" ]; then echo 'Swift version 6.4'; exit 0; fi
[ "$1" = "-swift-version" ] && [ "$2" = "6" ] || exit 4
exit 0
`,
      );
      await Deno.chmod(executable, 0o755);
      Deno.env.set("SWIFTC", `"${executable}" -sdk "/SDK with spaces"`);
      const expected = { executable, args: ["-sdk", "/SDK with spaces"] };
      const fromEnvironment = await selectedSwiftCompiler(root, root);
      equal(fromEnvironment, expected);
      equal(await checkSwiftCompiler(fromEnvironment), undefined);
      await Deno.writeTextFile(
        join(root, "CMakeCache.txt"),
        `CMAKE_Swift_COMPILER:FILEPATH=${executable}\nCMAKE_Swift_COMPILER_ARG1:STRING=-sdk "/SDK with spaces"\n`,
      );
      Deno.env.set("SWIFTC", "/missing/swiftc");
      const fromCache = await selectedSwiftCompiler(root, root);
      equal(fromCache, expected);
      equal(await checkSwiftCompiler(fromCache), undefined);
    } finally {
      restoreEnvironment("SWIFTC", previous);
      await Deno.remove(root, { recursive: true });
    }
  },
});

Deno.test({
  name:
    "setup provisions missing native tools before linking Swift and still rejects invalid Swift",
  ignore: Deno.build.os !== "linux",
  async fn() {
    const root = await Deno.makeTempDir({ prefix: "porydaw-provision-" });
    const previousPath = Deno.env.get("PATH");
    const previousSwift = Deno.env.get("SWIFTC");
    const pythonLookup = await new Deno.Command("sh", {
      args: ["-c", "command -v python3"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const python = new TextDecoder().decode(pythonLookup.stdout).trim();
    const installed = join(root, "installed");
    const linked = join(root, "linked");
    const version = join(root, "version");
    try {
      if (!pythonLookup.success) {
        throw new Error("Python is required for the setup test");
      }
      const scripts: Record<string, string> = {
        cmake: 'echo "cmake version 4.4.0"',
        ninja: 'echo "1.13.0"',
        python3: `exec '${python}' "$@"`,
        cc: `[ -f '${installed}' ]`,
        "c++": `[ -f '${installed}' ]`,
        "apt-get": "exit 0",
        sudo: `printf installed > '${installed}'`,
        swiftc: `if [ "$1" = "--version" ]; then
read value < '${version}'
echo "Swift version $value"
exit 0
fi
[ -f '${installed}' ] || { echo 'missing system linker' >&2; exit 1; }
printf linked > '${linked}'`,
      };
      for (const [name, script] of Object.entries(scripts)) {
        const path = join(root, name);
        await Deno.writeTextFile(path, `#!/bin/sh\n${script}\n`);
        await Deno.chmod(path, 0o755);
      }
      Deno.env.set("PATH", root);
      Deno.env.set("SWIFTC", join(root, "swiftc"));
      await Deno.writeTextFile(version, "5.10\n");
      let rejected = false;
      try {
        await ensureNativeBuildTools(join(root, "build"));
      } catch (error) {
        rejected = String(error).includes("Swift 6.4 or newer");
      }
      equal(rejected, true);
      let provisioned = true;
      try {
        await Deno.stat(installed);
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) provisioned = false;
        else throw error;
      }
      equal(provisioned, false);
      await Deno.writeTextFile(version, "6.4\n");
      const before = await inspectNativeBuildTools(join(root, "build"));
      equal(before.incompatibilities, []);
      equal(before.missing, ["compiler"]);
      const result = await ensureNativeBuildTools(join(root, "build"));
      equal(result.installed, ["a C and C++20 compiler"]);
      equal(await Deno.readTextFile(linked), "linked");
    } finally {
      restoreEnvironment("PATH", previousPath);
      restoreEnvironment("SWIFTC", previousSwift);
      await Deno.remove(root, { recursive: true });
    }
  },
});
