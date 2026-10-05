// Configures and builds an isolated debug, release, or ASAN tree under build/
// and prints only what an agent can act on; build.log in the tree keeps the rest.
import { join, resolve } from "node:path";
import {
  type BuildConfig,
  buildDirectory,
  cmakeConfigureArgs,
  localQtPrefix,
} from "./local_build_environment.ts";
import { poryaaaaConfiguration } from "./poryaaaa_source.ts";
import { summarizeBuild } from "./build_output.ts";
import { type ExecResult, run } from "./lib/exec.ts";

const SHOWN_LINES = 20;

async function prepareWindowsEnvironment(): Promise<void> {
  if (Deno.build.os !== "windows") return;
  const vswhere = join(
    Deno.env.get("ProgramFiles(x86)") ?? "C:\\Program Files (x86)",
    "Microsoft Visual Studio",
    "Installer",
    "vswhere.exe",
  );
  const found = await run(vswhere, [
    "-latest",
    "-products",
    "*",
    "-property",
    "installationPath",
  ]);
  const vsRoot = found.text().trim();
  if (!found.success || !vsRoot) {
    throw new Error("Visual Studio C++ tools are required for Windows builds");
  }
  const devCmd = join(vsRoot, "Common7", "Tools", "VsDevCmd.bat");
  const envScript = await Deno.makeTempFile({ suffix: ".cmd" });
  let devEnv;
  try {
    await Deno.writeTextFile(
      envScript,
      `@echo off\r\ncall "${devCmd}" -arch=x64 -host_arch=x64 >nul\r\nif errorlevel 1 exit /b 1\r\nset\r\n`,
    );
    devEnv = await run("cmd.exe", ["/d", "/c", envScript]);
  } finally {
    await Deno.remove(envScript);
  }
  if (!devEnv.success) throw new Error(devEnv.text("stderr"));
  for (const line of devEnv.text().split(/\r?\n/)) {
    const equal = line.indexOf("=");
    if (equal > 0) Deno.env.set(line.slice(0, equal), line.slice(equal + 1));
  }
  const version = (await Deno.readTextFile(".swift-version")).trim();
  const swiftRoot = join(
    Deno.env.get("LOCALAPPDATA") ?? "",
    "Programs",
    "Swift",
  );
  const toolchainBin = join(
    swiftRoot,
    "Toolchains",
    `${version}+Asserts`,
    "usr",
    "bin",
  );
  const runtimeBin = join(swiftRoot, "Runtimes", version, "usr", "bin");
  const sdk = join(
    swiftRoot,
    "Platforms",
    version,
    "Windows.platform",
    "Developer",
    "SDKs",
    "Windows.sdk",
  );
  if (
    !(await exists(join(toolchainBin, "swiftc.exe"))) ||
    !(await exists(runtimeBin)) || !(await exists(sdk))
  ) {
    throw new Error(
      `Swift ${version} toolchain, runtime, and SDK are required under ${swiftRoot}`,
    );
  }
  Deno.env.set("SDKROOT", sdk);
  Deno.env.set(
    "PATH",
    `${toolchainBin};${runtimeBin};${Deno.env.get("PATH") ?? ""}`,
  );
}

async function exists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
}

async function readCache(directory: string): Promise<string | undefined> {
  try {
    return await Deno.readTextFile(join(directory, "CMakeCache.txt"));
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return undefined;
    throw error;
  }
}

export async function usesMultiConfigBuild(
  directory: string,
): Promise<boolean> {
  const cache = await readCache(directory);
  return cache !== undefined &&
    /^CMAKE_CONFIGURATION_TYPES:[^=]*=.+$/m.test(cache);
}

async function hasBuildSystem(directory: string): Promise<boolean> {
  if (
    (await exists(join(directory, "build.ninja"))) ||
    (await exists(join(directory, "Makefile")))
  ) return true;
  try {
    for await (const entry of Deno.readDir(directory)) {
      if (entry.isFile && entry.name.endsWith(".sln")) return true;
    }
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return false;
    throw error;
  }
  return false;
}

// Returns the configure output, or undefined when the tree is already current.
async function configure(
  directory: string,
  config: BuildConfig,
  buildChecks: boolean | undefined,
): Promise<ExecResult | undefined> {
  const poryaaaa = await poryaaaaConfiguration(directory);
  const buildType = config === "release" ? "Release" : "Debug";
  const cache = await readCache(directory);
  const args = await cmakeConfigureArgs({
    buildDirectory: directory,
    poryaaaaArgument: poryaaaa.cmakeArgument,
    qtPrefix: await localQtPrefix(Deno.cwd(), undefined, undefined, directory),
    buildType,
    buildChecks,
    asan: config === "asan",
  });
  const compilersMatch = args.filter((arg) =>
    /^-DCMAKE_(C|CXX|OBJCXX)_COMPILER=/.test(arg)
  ).every((arg) => {
    const [key, value] = arg.slice(2).split("=");
    return cache?.split(/\r?\n/).some((line) =>
      line.startsWith(`${key}:`) && line.endsWith(`=${value}`)
    );
  });
  const typeMatches = (await usesMultiConfigBuild(directory)) ||
    /^CMAKE_BUILD_TYPE:STRING=(.*)$/m.exec(cache ?? "")?.[1] === buildType;
  const cachedChecks = /^PORYDAW_BUILD_CHECKS:BOOL=(.*)$/m.exec(cache ?? "")
    ?.[1];
  const checksMatch = buildChecks === undefined ||
    cachedChecks === (buildChecks ? "ON" : "OFF");
  const asanMatches = /^PORYDAW_ASAN:BOOL=(.*)$/m.exec(cache ?? "")?.[1] ===
    (config === "asan" ? "ON" : "OFF");
  if (
    (await hasBuildSystem(directory)) && poryaaaa.cacheMatches &&
    typeMatches && checksMatch && asanMatches && compilersMatch
  ) return undefined;
  if (cache !== undefined && !compilersMatch) {
    // Replacing compilers resets CMake's cache; retain all requested options.
    const generator = /^CMAKE_GENERATOR:INTERNAL=(.*)$/m.exec(cache)?.[1];
    args.push("--fresh");
    if (generator) args.push("-G", generator);
  }
  return await run("cmake", args);
}

// Swift's incremental driver reuses an object whenever the sources and their
// dependency graph are unchanged — compile flags included. Ninja re-runs a
// target's compile edge after a reconfigure, but the driver then reports no
// work and the stale objects survive, so a CMake flag edit would keep the old
// binary. Dropping the edge's objects is what makes the flag edit land; the
// stamp records the commands the objects on disk were built with.
interface SwiftCompileEdge {
  readonly rule: string;
  readonly objects: string[];
  readonly signature: string;
}

async function swiftCompileEdges(
  directory: string,
): Promise<SwiftCompileEdge[]> {
  const ninjaPath = join(directory, "build.ninja");
  if (!(await exists(ninjaPath))) return [];
  const marker = ": Swift_COMPILER__";
  const lines = (await Deno.readTextFile(ninjaPath)).split(/\r?\n/);
  const edges: SwiftCompileEdge[] = [];
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (!line.startsWith("build ")) continue;
    const colon = line.indexOf(marker);
    if (colon === -1) continue;
    const directives: string[] = [];
    for (
      let next = index + 1;
      next < lines.length && lines[next].startsWith("  ");
      next++
    ) {
      const directive = lines[next].slice(2);
      if (/^(?:FLAGS|INCLUDES|DEFINES|CONFIG) = /.test(directive)) {
        directives.push(directive);
      }
    }
    edges.push({
      rule: line.slice(colon + marker.length).trim().split(/\s+/)[0],
      objects: line.slice("build ".length, colon)
        .split(/\s+/)
        .filter((output) => output.endsWith(".o"))
        .map((output) => join(directory, output)),
      signature: directives.join("\n"),
    });
  }
  return edges;
}

async function recordedSwiftCommands(
  stamp: string,
): Promise<Record<string, string> | undefined> {
  try {
    const recorded: unknown = JSON.parse(await Deno.readTextFile(stamp));
    return recorded && typeof recorded === "object"
      ? recorded as Record<string, string>
      : undefined;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound || error instanceof SyntaxError) {
      return undefined;
    }
    throw error;
  }
}

// Returns whether any stale Swift objects were dropped.
async function reconcileSwiftObjects(directory: string): Promise<boolean> {
  const edges = await swiftCompileEdges(directory);
  if (edges.length === 0) return false;
  const stamp = join(directory, ".porydaw-swift-commands.json");
  const recorded = await recordedSwiftCommands(stamp);
  const signatures: Record<string, string> = {};
  let dropped = false;
  for (const edge of edges) {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(edge.signature),
    );
    signatures[edge.rule] = Array.from(
      new Uint8Array(digest),
      (byte) => byte.toString(16).padStart(2, "0"),
    ).join("");
    if (recorded?.[edge.rule] === signatures[edge.rule]) continue;
    for (const object of edge.objects) {
      try {
        await Deno.remove(object);
        dropped = true;
      } catch (error) {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      }
    }
  }
  await Deno.writeTextFile(stamp, JSON.stringify(signatures, null, 2) + "\n");
  return dropped;
}

function artifactPath(directory: string, target: string, multi: boolean) {
  const root = multi ? join(directory, "Release") : directory;
  if (Deno.build.os === "windows") return join(root, `${target}.exe`);
  if (Deno.build.os === "darwin" && target === "porydaw") {
    return join(root, "porydaw.app", "Contents", "MacOS", "porydaw");
  }
  return join(root, target);
}

function printCapped(lines: string[], log: string): void {
  for (const line of lines.slice(0, SHOWN_LINES)) {
    console.error(`  ${line.replaceAll("\n", "\n  ")}`);
  }
  if (lines.length > SHOWN_LINES) {
    console.error(`  … ${lines.length - SHOWN_LINES} more in ${log}`);
  }
}

// A single-config tree from before the debug/release split: nothing builds it.
async function warnLegacyTree(): Promise<void> {
  if (!(await exists(join("build", "CMakeCache.txt")))) return;
  console.error(
    "build: build/ still holds an unused pre-split tree; builds use build/debug, " +
      "build/release, and build/asan.",
  );
}

export async function runBuild(
  targets: string[],
  config: BuildConfig,
  buildChecks?: boolean,
): Promise<string> {
  await prepareWindowsEnvironment();
  const started = performance.now();
  const directory = buildDirectory(config);
  const log = join(directory, "build.log");
  const outputs: string[] = [];
  const roots = { repo: Deno.cwd(), build: resolve(directory) };
  const seconds = () => ((performance.now() - started) / 1000).toFixed(1);
  const fail = async (what: string, code: number): Promise<never> => {
    const output = outputs.join("\n");
    await Deno.mkdir(directory, { recursive: true });
    await Deno.writeTextFile(log, output);
    const summary = summarizeBuild(output, roots);
    const steps = summary.failedSteps.filter(Boolean);
    console.error(
      `build: ${what}failed (${config}, ${seconds()}s)${
        steps.length > 0 ? `: ${steps.join("; ")}` : ""
      }`,
    );
    printCapped(
      summary.errors.length > 0
        ? summary.errors
        : output.split(/\r?\n/).filter((line) => line.trim()).slice(-15),
      log,
    );
    console.error(`  full log: ${log} (read it; rebuilding adds no detail)`);
    Deno.exit(code || 1);
  };

  await warnLegacyTree();
  const configured = await configure(directory, config, buildChecks);
  if (configured) {
    outputs.push(configured.text() + configured.text("stderr"));
    if (!configured.success) await fail("configure ", configured.code);
  }
  const multi = await usesMultiConfigBuild(directory);
  const buildArgs = [
    "--build",
    directory,
    "-j",
    String(navigator.hardwareConcurrency),
    ...(config === "release" || multi ? ["--config", "Release"] : []),
    ...(targets.length > 0 ? ["--target", ...targets] : []),
  ];
  await reconcileSwiftObjects(directory);
  let built = await run("cmake", buildArgs);
  outputs.push(built.text() + built.text("stderr"));
  // A reconfigure inside the build rewrites compile commands after the
  // reconcile above, so the objects it left behind can still be stale.
  if (built.success && await reconcileSwiftObjects(directory)) {
    built = await run("cmake", buildArgs);
    outputs.push(built.text() + built.text("stderr"));
  }
  if (!built.success) await fail("", built.code);

  const output = outputs.join("\n");
  await Deno.writeTextFile(log, output);
  const summary = summarizeBuild(output, roots);
  const artifact = targets.length > 0
    ? ` ${artifactPath(directory, targets[0], multi)}`
    : "";
  console.log(
    summary.steps === 0
      ? `build: up to date (${config}, ${seconds()}s)${artifact}`
      : `build: ok (${config}, ${summary.steps} steps, ${seconds()}s)${artifact}`,
  );
  if (summary.warnings.length > 0) {
    console.error(
      `build: ${summary.warnings.length} warning(s) in project sources`,
    );
    printCapped(summary.warnings, log);
  }
  return directory;
}
