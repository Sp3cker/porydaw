// Local-only coverage lane. CI never calls this — .github/workflows/build.yml
// pins to `deno task checks`. Keeps -O0 + instrumentation out of remote builds.
//
// Usage: deno task coverage [-- html|report]  (default: both)
// Env: none. Always writes to build-cov/ (gitignored via build-*/).

const BUILD_DIR = "build-cov";
const PROFILES_DIR = `${BUILD_DIR}/profiles`;
const PROF_DATA = `${BUILD_DIR}/cov.profdata`;
const HTML_DIR = `${BUILD_DIR}/coverage`;
const decoder = new TextDecoder();

function run(cmd: string[], opts: { env?: Record<string, string> } = {}): void {
  const [bin, ...args] = cmd;
  const child = new Deno.Command(bin, {
    args,
    stdout: "piped",
    stderr: "piped",
    env: opts.env,
  }).outputSync();
  const out = decoder.decode(child.stdout) + decoder.decode(child.stderr);
  if (!child.success) {
    console.error(out);
    throw new Error(`${cmd.join(" ")} failed with ${child.code}`);
  }
  if (out.trim() && Deno.args.includes("--verbose")) console.log(out);
}

function which(bin: string): string {
  try {
    const r = new Deno.Command("which", { args: [bin], stdout: "piped" })
      .outputSync();
    if (r.success) return decoder.decode(r.stdout).trim();
  } catch { /* ignore */ }
  return bin;
}

if (Deno.env.get("CI") && !Deno.env.get("PORYDAW_COVERAGE_IN_CI")) {
  console.log(
    "coverage: CI detected — continuing because you invoked coverage explicitly. Remote CI should use `deno task checks`.",
  );
}

const mode = Deno.args.includes("html")
  ? "html"
  : Deno.args.includes("report")
  ? "report"
  : "both";
const llvmProfdata = which("llvm-profdata");
const llvmCov = which("llvm-cov");

// 1. Configure if needed.
try {
  await Deno.stat(`${BUILD_DIR}/build.ninja`);
} catch {
  console.log(`coverage: configuring ${BUILD_DIR} with -DPORYDAW_COVERAGE=ON`);
  run([
    "cmake",
    "-S",
    ".",
    "-B",
    BUILD_DIR,
    "-G",
    "Ninja",
    "-DPORYDAW_COVERAGE=ON",
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo",
  ]);
}

// 2. Build.
console.log("coverage: building");
run(["cmake", "--build", BUILD_DIR, "-j", `${navigator.hardwareConcurrency}`]);

// 3. Collect.
console.log("coverage: running harnesses");
await Deno.remove(PROFILES_DIR, { recursive: true }).catch(() => {});
await Deno.mkdir(PROFILES_DIR, { recursive: true });
const checksBin = `${BUILD_DIR}/porydaw_checks`;
const covEnv = { LLVM_PROFILE_FILE: `${PROFILES_DIR}/cov-%p.profraw` };
run(["deno", "task", "checks", checksBin], { env: covEnv });

// 4. Merge (glob doesn't expand in Deno.Command, so handle fallback).
console.log("coverage: merging");
try {
  run([
    llvmProfdata,
    "merge",
    "-sparse",
    `${PROFILES_DIR}/cov-*.profraw`,
    "-o",
    PROF_DATA,
  ]);
  await Deno.stat(PROF_DATA);
} catch {
  const profiles: string[] = [];
  for await (const f of Deno.readDir(PROFILES_DIR)) {
    if (f.name.endsWith(".profraw")) profiles.push(`${PROFILES_DIR}/${f.name}`);
  }
  if (!profiles.length) throw new Error("no .profraw profiles found");
  run([llvmProfdata, "merge", "-sparse", "-o", PROF_DATA, ...profiles]);
}

// 5. Report.
const ignoreRe = ".*/build.*|.*external/.*|.*/moc_.*\\.cpp|.*\\.moc";
const checksObj = `${BUILD_DIR}/porydaw_checks`;
const appObj = `${BUILD_DIR}/porydaw.app/Contents/MacOS/porydaw`;
let appExists = false;
try {
  await Deno.stat(appObj);
  appExists = true;
} catch { /* linux/windows path differs */ }
const covArgs = appExists ? [checksObj, appObj] : [checksObj];

if (mode === "report" || mode === "both") {
  const cmd = new Deno.Command(llvmCov, {
    args: [
      "report",
      ...covArgs,
      `--instr-profile=${PROF_DATA}`,
      `--ignore-filename-regex=${ignoreRe}`,
    ],
    stdout: "piped",
    stderr: "piped",
  }).outputSync();
  console.log(decoder.decode(cmd.stdout));
  if (!cmd.success) console.error(decoder.decode(cmd.stderr));
}
if (mode === "html" || mode === "both") {
  run([
    llvmCov,
    "show",
    ...covArgs,
    `--instr-profile=${PROF_DATA}`,
    `--ignore-filename-regex=${ignoreRe}`,
    "--format=html",
    `--output-dir=${HTML_DIR}`,
  ]);
  console.log(`coverage: html → ${HTML_DIR}/index.html`);
}
