const root = Deno.cwd();
const vendor = `${root}/third_party/voicegroup-core`;

function selectedTarget(): string {
  if (Deno.build.os === "darwin" && Deno.build.arch === "aarch64") {
    return "aarch64-apple-darwin";
  }
  if (Deno.build.os === "darwin" && Deno.build.arch === "x86_64") {
    return "x86_64-apple-darwin";
  }
  if (Deno.build.os === "linux" && Deno.build.arch === "x86_64") {
    return "x86_64-unknown-linux-gnu";
  }
  if (Deno.build.os === "windows" && Deno.build.arch === "x86_64") {
    return "x86_64-pc-windows-msvc";
  }
  throw new Error(
    `unsupported verification host ${Deno.build.os}/${Deno.build.arch}`,
  );
}

interface VendorManifest {
  target_triple: string;
  architecture: string;
  abi_version: number;
  header: string;
  library: string;
  header_sha256: string;
  lib_sha256: string;
  [key: string]: unknown;
}

interface VerificationCase {
  name: string;
  expectedError?: string;
  mutate?: (manifest: VendorManifest) => void;
}

const target = selectedTarget();
const sourceManifestPath = `${vendor}/lib/${target}/manifest.json`;
const sourceManifest = JSON.parse(
  await Deno.readTextFile(sourceManifestPath),
) as VendorManifest;
const scratch = await Deno.makeTempDir({ prefix: "porydaw-vg-vendor-" });

try {
  const scratchVendor = `${scratch}/vendor`;
  const scratchTarget = `${scratchVendor}/lib/${target}`;
  await Deno.mkdir(`${scratchVendor}/include`, { recursive: true });
  await Deno.mkdir(scratchTarget, { recursive: true });
  await Deno.copyFile(
    `${vendor}/${sourceManifest.header}`,
    `${scratchVendor}/${sourceManifest.header}`,
  );
  await Deno.copyFile(
    `${vendor}/${sourceManifest.library}`,
    `${scratchVendor}/${sourceManifest.library}`,
  );

  const cases: VerificationCase[] = [
    { name: "success" },
    {
      name: "header-checksum",
      expectedError: "voicegroup-core header checksum mismatch",
      mutate: (manifest) => manifest.header_sha256 = "0".repeat(64),
    },
    {
      name: "archive-checksum",
      expectedError: "voicegroup-core archive checksum mismatch",
      mutate: (manifest) => manifest.lib_sha256 = "0".repeat(64),
    },
    {
      name: "target",
      expectedError: "voicegroup-core target mismatch",
      mutate: (manifest) => manifest.target_triple = "invalid-target",
    },
    {
      name: "architecture",
      expectedError: "voicegroup-core architecture mismatch",
      mutate: (manifest) => manifest.architecture = "invalid-architecture",
    },
    {
      name: "abi",
      expectedError: "voicegroup-core ABI mismatch",
      mutate: (manifest) => manifest.abi_version += 1,
    },
  ];

  for (const testCase of cases) {
    const manifest = structuredClone(sourceManifest);
    testCase.mutate?.(manifest);
    await Deno.writeTextFile(
      `${scratchTarget}/manifest.json`,
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    const buildDir = `${scratch}/build-${testCase.name}`;
    const command = new Deno.Command("cmake", {
      cwd: root,
      args: [
        "-S",
        root,
        "-B",
        buildDir,
        "-G",
        "Ninja",
        "-DPORYDAW_VERIFY_VOICEGROUP_VENDOR_ONLY=ON",
        "-DPORYDAW_BUILD_CHECKS=OFF",
        `-DPORYDAW_VOICEGROUP_CORE_VENDOR_DIR=${scratchVendor}`,
      ],
      stdout: "piped",
      stderr: "piped",
    });
    const result = await command.output();
    const output = `${new TextDecoder().decode(result.stdout)}\n${
      new TextDecoder().decode(result.stderr)
    }`;
    if (!testCase.expectedError) {
      if (!result.success) {
        throw new Error(`success case failed:\n${output}`);
      }
    } else {
      if (result.success || !output.includes(testCase.expectedError)) {
        throw new Error(
          `${testCase.name} did not fail with '${testCase.expectedError}':\n${output}`,
        );
      }
    }
    console.log(`vendor gate: ${testCase.name} ok`);
  }
} finally {
  await Deno.remove(scratch, { recursive: true });
}
