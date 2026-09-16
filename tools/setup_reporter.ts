import { qtVersion } from "./local_build_environment.ts";

const encoder = new TextEncoder();

const stages = [
  {
    id: "submodule",
    label: "initializing poryaaaa submodule",
    heartbeat: false,
  },
  {
    id: "native-tools",
    label: "installing native build tools",
    heartbeat: false,
  },
  {
    id: "python-tools",
    label: "preparing checkout-local Python tools",
    heartbeat: false,
  },
  { id: "qt", label: `preparing Qt ${qtVersion}.x`, heartbeat: true },
  { id: "configure", label: "configuring Porydaw", heartbeat: false },
  { id: "build", label: "building porydaw", heartbeat: true },
] as const;

export type SetupStage = (typeof stages)[number]["id"];

type Stage = (typeof stages)[number];

type ActiveStage = {
  stage: Stage;
  startedAt: number;
};

function stageFor(id: SetupStage): Stage {
  const stage = stages.find((candidate) => candidate.id === id);
  if (!stage) throw new Error(`unknown setup stage ${id}`);
  return stage;
}

function stagePrefix(stage: Stage): string {
  return `setup: [${
    stages.indexOf(stage) + 1
  }/${stages.length}] ${stage.label}`;
}

function duration(milliseconds: number): string {
  return `${Math.round(milliseconds / 1000)}s`;
}

const cmakeDownload = "https://cmake.org/download/";
const gitDownload = "https://git-scm.com/downloads";
const ninjaDownload = "https://github.com/ninja-build/ninja/releases";
const pythonDownload = "https://www.python.org/downloads/";
const qtInstallerDownload = "https://www.qt.io/download-qt-installer";
const visualStudioDownload = "https://visualstudio.microsoft.com/downloads/";

function nativeToolHints(): string[] {
  const common = [
    `download CMake 3.24+ manually: ${cmakeDownload}`,
    `download Ninja manually: ${ninjaDownload}`,
    `download Python 3 manually: ${pythonDownload}`,
  ];
  switch (Deno.build.os) {
    case "darwin":
      return [
        "install Xcode Command Line Tools with xcode-select --install",
        ...common,
      ];
    case "windows":
      return [
        `download Visual Studio Build Tools and select Desktop development with C++: ${visualStudioDownload}`,
        ...common,
      ];
    default:
      return [
        "install a C++20 compiler with your distribution package manager",
        ...common,
      ];
  }
}

function manualInstallHints(stage: SetupStage | undefined): string[] {
  switch (stage) {
    case "submodule":
      return [`download Git manually: ${gitDownload}`];
    case "native-tools":
      return nativeToolHints();
    case "python-tools":
      return [`download Python 3 manually: ${pythonDownload}`];
    case "qt":
      return [
        `download a matching Qt ${qtVersion} desktop kit: ${qtInstallerDownload}`,
        "then configure CMake manually with -DCMAKE_PREFIX_PATH=<Qt prefix>",
      ];
    case "configure":
      return [
        `if CMake is missing or older than 3.24, download it manually: ${cmakeDownload}`,
      ];
    default:
      return [];
  }
}

export class SetupProgress {
  #active: ActiveStage | undefined;
  #heartbeat: number | undefined;
  #live = false;
  #startedAt = performance.now();
  #ranStage = false;
  #failedStage: SetupStage | undefined;

  printDryRun(platform: string): void {
    console.log(`setup: dry run for ${platform}`);
    for (const stage of stages) {
      console.log(`${stagePrefix(stage)} - would run`);
    }
  }

  async run<T>(
    id: SetupStage,
    operation: () => Promise<T>,
    outcome: (result: T) => string = () => "done",
  ): Promise<T> {
    const stage = stageFor(id);
    this.#active = { stage, startedAt: performance.now() };
    this.#ranStage = true;
    console.log(stagePrefix(stage));
    this.#startHeartbeat();
    try {
      const result = await operation();
      this.#finish(outcome(result));
      return result;
    } catch (error) {
      this.#failedStage = id;
      this.#finish("failed");
      throw error;
    }
  }

  complete(launchCommand: string): void {
    console.log(
      `setup: ready in ${duration(performance.now() - this.#startedAt)}`,
    );
    console.log(`setup: launch with ${launchCommand}`);
    console.log(
      "setup: later builds use deno task build:app or deno task build:checks",
    );
  }

  fail(error: unknown): void {
    console.error(
      `setup: ${error instanceof Error ? error.message : String(error)}`,
    );
    const hints = manualInstallHints(this.#failedStage);
    if (hints.length > 0) {
      console.error("setup: manual installation options:");
      for (const hint of hints) console.error(`setup: ${hint}`);
    }
    if (this.#ranStage) {
      console.error(
        "setup: rerun deno task setup; completed local work is reused.",
      );
    }
  }

  #startHeartbeat(): void {
    if (!this.#active?.stage.heartbeat || !Deno.stderr.isTerminal()) return;
    this.#heartbeat = setInterval(() => {
      const active = this.#active;
      if (!active) return;
      const line = `${stagePrefix(active.stage)} - ${
        duration(performance.now() - active.startedAt)
      } elapsed`;
      try {
        Deno.stderr.writeSync(
          new Uint8Array([
            13,
            ...encoder.encode(line),
            27,
            91,
            75,
          ]),
        );
        this.#live = true;
      } catch {
        // Terminal output must not make setup fail.
      }
    }, 5_000);
  }

  #finish(outcome: string): void {
    const active = this.#active;
    if (!active) return;
    if (this.#heartbeat !== undefined) {
      clearInterval(this.#heartbeat);
      this.#heartbeat = undefined;
    }
    if (this.#live) {
      try {
        Deno.stderr.writeSync(new Uint8Array([13, 27, 91, 75]));
      } catch {
        // Terminal output must not make setup fail.
      }
      this.#live = false;
    }
    console.log(
      `${stagePrefix(active.stage)} - ${outcome} (${
        duration(performance.now() - active.startedAt)
      })`,
    );
    this.#active = undefined;
  }
}
