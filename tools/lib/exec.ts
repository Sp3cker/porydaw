type Options = Pick<Deno.CommandOptions, "cwd" | "env" | "stdin"> & {
  inherit?: boolean;
};

export type ExecResult = Deno.CommandOutput & {
  text(stream?: "stdout" | "stderr"): string;
};

const decoder = new TextDecoder();

// Capture outputs unless inherited; streamed runners own their spawn and reaping.
export async function run(
  executable: string,
  args: string[],
  { inherit = false, ...options }: Options = {},
): Promise<ExecResult> {
  const result = await new Deno.Command(executable, {
    args,
    stdout: inherit ? "inherit" : "piped",
    stderr: inherit ? "inherit" : "piped",
    ...options,
  }).output();
  return Object.assign(result, {
    text: (stream: "stdout" | "stderr" = "stdout") =>
      decoder.decode(result[stream]),
  });
}
