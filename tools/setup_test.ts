import { join } from "node:path";
import {
  cmakeConfigureArgs,
  localQtPrefix,
  type QtInstallation,
  qtInstallationDirectory,
} from "./local_build_environment.ts";
import { checkSwiftCompiler } from "./swift_toolchain.ts";

function equal(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(`Expected ${expected}, received ${actual}`);
  }
}

function contains(actual: string | undefined, expected: string): void {
  if (!actual?.includes(expected)) {
    throw new Error(`Expected '${expected}' in '${actual}'`);
  }
}

Deno.test("setup help succeeds and invalid Qt versions stop before provisioning", async () => {
  for (
    const [args, code, message] of [
      [["--help"], 0, "--qt-version"],
      [["--qt-version"], 2, "requires a 6.11.<patch> version"],
      [["--qt-version", "6.10.1"], 2, "requires a 6.11.<patch> version"],
      [["--qt-version", "6.11.invalid"], 2, "requires a 6.11.<patch> version"],
    ] as const
  ) {
    const result = await new Deno.Command(Deno.execPath(), {
      args: ["run", "tools/setup.ts", ...args],
      stdout: "piped",
      stderr: "piped",
    }).output();
    equal(result.code, code);
    contains(new TextDecoder().decode(result.stderr), message);
  }
});

Deno.test("Qt version switching clears cached component paths and remains selected", async () => {
  const root = await Deno.makeTempDir({ prefix: "porydaw-qt-switch-" });
  try {
    const installation = {
      host: "linux_arm64",
      architecture: "linux_gcc_arm64",
    };
    const prefixes = ["6.11.1", "6.11.2"].map((version) =>
      join(qtInstallationDirectory(root, installation), version, "gcc_arm64")
    );
    for (const prefix of prefixes) {
      for (const pkg of ["Qt6", "Qt6Core"]) {
        const directory = join(prefix, "lib", "cmake", pkg);
        await Deno.mkdir(directory, { recursive: true });
        await Deno.writeTextFile(
          join(directory, `${pkg}Config.cmake`),
          pkg === "Qt6" ? "find_package(Qt6Core CONFIG REQUIRED)\n" : "",
        );
      }
    }
    const buildDirectory = join(root, "build");
    await Deno.mkdir(buildDirectory);
    for (const prefix of [prefixes[1], prefixes[0]]) {
      const args = await cmakeConfigureArgs({
        buildDirectory,
        poryaaaaArgument: "-DPORYAAAA_DIR=unused",
        qtPrefix: prefix,
        buildChecks: false,
      });
      equal(args.includes("-UQt6*_DIR"), true);
      equal(args.includes(`-DCMAKE_PREFIX_PATH=${prefix}`), true);
      equal(
        args.includes(`-DQt6_DIR:PATH=${join(prefix, "lib", "cmake", "Qt6")}`),
        true,
      );
      await Deno.writeTextFile(
        join(buildDirectory, "CMakeCache.txt"),
        `Qt6_DIR:PATH=${join(prefix, "lib", "cmake", "Qt6")}\n`,
      );
      equal(await localQtPrefix(root, installation), prefix);
    }
    equal(await localQtPrefix(root, installation, "6.11.2"), prefixes[1]);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("setup finds the Qt installer layouts on each platform", async () => {
  const root = await Deno.makeTempDir();
  try {
    const kits: [QtInstallation, string][] = [
      [{ host: "linux_arm64", architecture: "linux_gcc_arm64" }, "gcc_arm64"],
      [{ host: "linux", architecture: "gcc_64" }, "gcc_64"],
      [{ host: "mac", architecture: "clang_64" }, "clang_64"],
      [{ host: "windows", architecture: "win64_msvc2022_64" }, "msvc2022_64"],
    ];
    for (const [installation, kit] of kits) {
      equal(await localQtPrefix(root, installation), undefined);
      const prefix = join(
        qtInstallationDirectory(root, installation),
        "6.11.2",
        kit,
      );
      const configDirectory = join(prefix, "lib", "cmake", "Qt6");
      await Deno.mkdir(configDirectory, { recursive: true });
      equal(await localQtPrefix(root, installation), undefined);
      await Deno.writeTextFile(join(configDirectory, "Qt6Config.cmake"), "");
      equal(await localQtPrefix(root, installation), prefix);
      equal(await localQtPrefix(root, installation, "6.11.2"), prefix);
      equal(await localQtPrefix(root, installation, "6.11.3"), undefined);
    }
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("setup reports a missing Swift compiler before provisioning", async () => {
  const root = await Deno.makeTempDir();
  try {
    contains(
      await checkSwiftCompiler(join(root, "swiftc")),
      "missing or cannot run",
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test({
  name: "setup rejects old, unloadable, and non-linking Swift compilers",
  ignore: Deno.build.os === "windows",
  async fn() {
    const root = await Deno.makeTempDir();
    const compiler = join(root, "swiftc");
    try {
      const cases = [
        {
          script: "echo 'Apple Swift version 5.10'",
          expected: "Swift 6.4 or newer is required",
        },
        {
          script:
            "echo 'libncurses.so.6: cannot open shared object file' >&2\nexit 127",
          expected: "libncurses.so.6",
        },
        {
          script:
            'if [ "$1" = "--version" ]; then\necho "Swift version 6.4"\nexit 0\nfi\necho "missing runtime library" >&2\nexit 1',
          expected: "cannot compile and link a Swift 6.4 program",
        },
      ];
      for (const { script, expected } of cases) {
        await Deno.writeTextFile(compiler, `#!/bin/sh\n${script}\n`);
        await Deno.chmod(compiler, 0o755);
        contains(await checkSwiftCompiler(compiler), expected);
      }
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  },
});
