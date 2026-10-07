import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { Script } from "node:vm";
import { createSourceFile, isFunctionDeclaration, ScriptKind, ScriptTarget } from "typescript";
import { describe, expect, it, vi } from "vitest";
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from "../../packages/shared/src/config/constants";

async function executeVisibleUploaderAcknowledgment(options: {
  output?: string;
  creationRefused?: boolean;
  completed?: boolean;
  exitCode?: number;
  writeOutputs?: boolean;
  distribution?: "file" | "directory" | "missing";
} = {}) {
  const directory = await mkdtemp(join(tmpdir(), "gymloop-visible-uploader-"));
  const artifactPath = join(directory, "synthetic-evidence.bin");
  const runtime = {
    GITHUB_ACTIONS: "true",
    ACTIONS_RUNTIME_TOKEN: "synthetic-runtime-token",
    ACTIONS_RESULTS_URL: "https://synthetic-artifacts.invalid/",
    RUNNER_WORKSPACE: directory,
  };
  const inheritedInputs = { ...runtime, SYNTHETIC_INHERITED_INPUT: "retained" };
  const privateWrite = vi.fn(async (path: string, bytes: Buffer) => {
    if (options.creationRefused) throw new Error("synthetic exclusive creation refused");
    await writeFile(path, bytes, { flag: "wx" });
  });
  let outputPath: string | undefined;
  let initialOutputBytes: Buffer | undefined;
  const capture = vi.fn(async (
    _command: string,
    _args: string[],
    inputs: { cwd: string; env: Record<string, string>; timeoutMs: number; maxBytes: number },
  ) => {
    outputPath = inputs.env.GITHUB_OUTPUT;
    try {
      initialOutputBytes = await readFile(outputPath);
    } catch {
      return {
        completed: true,
        exitCode: 1,
        stdout: "",
        stderr: "synthetic official child refused a missing output channel",
        signal: null,
      };
    }
    if (initialOutputBytes.length !== 0) {
      return {
        completed: true,
        exitCode: 1,
        stdout: "",
        stderr: "synthetic official child refused a nonempty initial output channel",
        signal: null,
      };
    }
    if (options.writeOutputs !== false) {
      await writeFile(outputPath, options.output ?? [
        "artifact-id<<ghadelimiter_visible_id",
        "12345",
        "ghadelimiter_visible_id",
        "artifact-digest<<ghadelimiter_visible_digest",
        "a".repeat(NATIVE_DB_VALIDATION.digestHexLength),
        "ghadelimiter_visible_digest",
        "",
      ].join("\n"));
    }
    return {
      completed: options.completed ?? true,
      exitCode: options.exitCode ?? 0,
      stdout: "synthetic child stdout is not an acknowledgment",
      stderr: "",
      signal: options.completed === false ? "SIGTERM" : null,
    };
  });
  const stat = vi.fn(async (path: string) => {
    if (options.distribution === "missing") throw new Error(`synthetic official distribution absent: ${path}`);
    return { isFile: () => options.distribution !== "directory" };
  });
  const readOutput = vi.fn(readFile);
  const removeOutput = vi.fn(rm);
  const nonce = vi.fn(randomBytes);
  const sourcePath = resolve("scripts/native-database-validation.mjs");
  const parsed = createSourceFile(sourcePath, readFileSync(sourcePath, "utf8"), ScriptTarget.Latest, true, ScriptKind.JS);
  const declaration = parsed.statements.find((statement) => isFunctionDeclaration(statement) && statement.name?.text === "uploadArtifact");
  if (!declaration) throw new Error("existing uploadArtifact mechanical extraction unavailable");
  const invoke = new Script(`(${declaration.getText(parsed)})`).runInNewContext({
    Buffer,
    NATIVE_DB_VALIDATION,
    PHASE8_BACKUP_LIMITS,
    capture,
    join,
    nativeDatabaseProcessEnv: () => inheritedInputs,
    privateWrite,
    process: { execPath: process.execPath, cwd: () => directory },
    randomBytes: nonce,
    readFile: readOutput,
    refuse: (code: string) => { throw new Error(code); },
    resolve,
    rm: removeOutput,
    stat,
  }) as (runtime: Record<string, string>, name: string, path: string, directory: string) => Promise<{ id: string; digest: string }>;
  let result: { id: string; digest: string } | undefined;
  let error: Error | undefined;
  let outputPresentAfter = false;
  try {
    try {
      result = await invoke(runtime, "synthetic-recovery-receipt", artifactPath, directory);
    } catch (caught) {
      error = caught as Error;
    }
    if (outputPath) {
      try {
        await readFile(outputPath);
        outputPresentAfter = true;
      } catch {
        outputPresentAfter = false;
      }
    }
    return {
      result, error, privateWrite, capture, stat, readOutput, removeOutput,
      nonce, outputPath, initialOutputBytes, outputPresentAfter, runtime,
      inheritedInputs, directory, artifactPath,
    };
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

describe("DBV-006/007 official uploader output-file acknowledgment", () => {
  it("creates an empty private channel before the official child and returns its actual acknowledgment", async () => {
    const scenario = await executeVisibleUploaderAcknowledgment();
    expect(scenario.error).toBeUndefined();
    expect(scenario.privateWrite).toHaveBeenCalledOnce();
    expect(scenario.capture).toHaveBeenCalledOnce();
    const [path, bytes] = scenario.privateWrite.mock.calls[0];
    expect(path).toBe(scenario.outputPath);
    expect(Buffer.isBuffer(bytes)).toBe(true);
    expect(bytes.length).toBe(0);
    expect(scenario.initialOutputBytes?.length).toBe(0);
    expect(scenario.result).toEqual({ id: "12345", digest: "a".repeat(NATIVE_DB_VALIDATION.digestHexLength) });
    expect(scenario.privateWrite.mock.invocationCallOrder[0]).toBeLessThan(scenario.capture.mock.invocationCallOrder[0]);
  });

  it("does not spawn an uploader when exclusive private creation is refused", async () => {
    const scenario = await executeVisibleUploaderAcknowledgment({ creationRefused: true });
    expect(scenario.result).toBeUndefined();
    expect(scenario.error).toBeDefined();
    expect(scenario.privateWrite).toHaveBeenCalledOnce();
    expect(scenario.capture).not.toHaveBeenCalled();
  });

  it("preserves the nonce, private directory, official distribution, inputs, limits and no-overwrite request", async () => {
    const scenario = await executeVisibleUploaderAcknowledgment();
    expect(scenario.error).toBeUndefined();
    const [command, args, inputs] = scenario.capture.mock.calls[0];
    expect(command).toBe(process.execPath);
    expect(args).toHaveLength(1);
    expect(args[0]).toBe(scenario.stat.mock.calls[0][0]);
    expect(args[0].replaceAll("\\", "/")).toMatch(/\/actions\/upload-artifact\/v5\/dist\/index\.js$/);
    expect(inputs.cwd).toBe(scenario.directory);
    expect(inputs.timeoutMs).toBe(NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
    expect(inputs.maxBytes).toBe(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes);
    expect(inputs.env).toMatchObject({
      ...scenario.runtime,
      ...scenario.inheritedInputs,
      INPUT_NAME: "synthetic-recovery-receipt",
      INPUT_PATH: scenario.artifactPath,
      INPUT_OVERWRITE: "false",
      "INPUT_RETENTION-DAYS": String(NATIVE_DB_VALIDATION.artifactRetentionDays),
      GITHUB_OUTPUT: scenario.outputPath,
    });
    expect(dirname(scenario.outputPath!)).toBe(scenario.directory);
    expect(scenario.nonce).toHaveBeenCalledWith(PHASE8_BACKUP_LIMITS.ivBytes);
    expect(basename(scenario.outputPath!)).toContain(scenario.nonce.mock.results[0].value.toString("hex"));
  });

  it.each(["\n", "\r\n"])("decodes the child's actual multiline outputs with %j separators", async (separator) => {
    const digest = "b".repeat(NATIVE_DB_VALIDATION.digestHexLength);
    const scenario = await executeVisibleUploaderAcknowledgment({ output: [
      "artifact-id<<ghadelimiter_visible_actual_id", "9876543210", "ghadelimiter_visible_actual_id",
      "artifact-digest<<ghadelimiter_visible_actual_digest", digest, "ghadelimiter_visible_actual_digest", "",
    ].join(separator) });
    expect(scenario.error).toBeUndefined();
    expect(scenario.result).toEqual({ id: "9876543210", digest });
  });

  it("removes the actual output channel after accepted decoding", async () => {
    const scenario = await executeVisibleUploaderAcknowledgment();
    expect(scenario.error).toBeUndefined();
    expect(scenario.readOutput).toHaveBeenCalledWith(scenario.outputPath, "utf8");
    expect(scenario.removeOutput).toHaveBeenCalledWith(scenario.outputPath);
    expect(scenario.readOutput.mock.invocationCallOrder[0]).toBeLessThan(scenario.removeOutput.mock.invocationCallOrder[0]);
    expect(scenario.outputPresentAfter).toBe(false);
  });

  it.each([
    { completed: false, exitCode: 0 },
    { completed: false, exitCode: 1 },
    { completed: true, exitCode: 1 },
  ])("refuses a failed or incomplete child despite valid output bytes: %j", async (child) => {
    const scenario = await executeVisibleUploaderAcknowledgment(child);
    expect(scenario.result).toBeUndefined();
    expect(scenario.error?.message).toBe("RECEIPT_UNAVAILABLE");
  });

  it.each(["missing", "directory"] as const)("refuses an unavailable official v5 distribution: %s", async (distribution) => {
    const scenario = await executeVisibleUploaderAcknowledgment({ distribution });
    expect(scenario.result).toBeUndefined();
    expect(scenario.error).toBeDefined();
    expect(scenario.capture).not.toHaveBeenCalled();
  });

  it.each(["", "0", "-1", "01", "+1", "1.5", " 1", "1 ", "one"])("refuses a missing or noncanonical artifact id: %j", async (id) => {
    const scenario = await executeVisibleUploaderAcknowledgment({ output: [
      "artifact-id<<ghadelimiter_visible_invalid_id", id, "ghadelimiter_visible_invalid_id",
      "artifact-digest<<ghadelimiter_visible_valid_digest", "a".repeat(NATIVE_DB_VALIDATION.digestHexLength), "ghadelimiter_visible_valid_digest", "",
    ].join("\n") });
    expect(scenario.result).toBeUndefined();
    expect(scenario.error?.message).toBe("RECEIPT_UNAVAILABLE");
  });

  it.each([
    "",
    "A".repeat(NATIVE_DB_VALIDATION.digestHexLength),
    "g".repeat(NATIVE_DB_VALIDATION.digestHexLength),
    "a".repeat(NATIVE_DB_VALIDATION.digestHexLength).slice(1),
    `${"a".repeat(NATIVE_DB_VALIDATION.digestHexLength)}a`,
    ` ${"a".repeat(NATIVE_DB_VALIDATION.digestHexLength)}`,
    `${"a".repeat(NATIVE_DB_VALIDATION.digestHexLength)} `,
  ])("refuses a missing or malformed artifact digest: %j", async (digest) => {
    const scenario = await executeVisibleUploaderAcknowledgment({ output: [
      "artifact-id<<ghadelimiter_visible_valid_id", "12345", "ghadelimiter_visible_valid_id",
      "artifact-digest<<ghadelimiter_visible_invalid_digest", digest, "ghadelimiter_visible_invalid_digest", "",
    ].join("\n") });
    expect(scenario.result).toBeUndefined();
    expect(scenario.error?.message).toBe("RECEIPT_UNAVAILABLE");
  });

  it.each([
    "",
    ["artifact-id<<ghadelimiter_visible_id", "12345", "ghadelimiter_visible_id", ""].join("\n"),
    ["artifact-digest<<ghadelimiter_visible_digest", "a".repeat(NATIVE_DB_VALIDATION.digestHexLength), "ghadelimiter_visible_digest", ""].join("\n"),
    `artifact-id=12345\nartifact-digest=${"a".repeat(NATIVE_DB_VALIDATION.digestHexLength)}\n`,
    ["artifact-id<<ghadelimiter_visible_id", "12345", "different_delimiter", "artifact-digest<<ghadelimiter_visible_digest", "a".repeat(NATIVE_DB_VALIDATION.digestHexLength), "ghadelimiter_visible_digest", ""].join("\n"),
  ])("refuses absent fields or malformed multiline acknowledgment: %j", async (output) => {
    const scenario = await executeVisibleUploaderAcknowledgment({ output });
    expect(scenario.result).toBeUndefined();
    expect(scenario.error?.message).toBe("RECEIPT_UNAVAILABLE");
  });

  it("does not turn an empty channel into acknowledgment when the child writes no outputs", async () => {
    const scenario = await executeVisibleUploaderAcknowledgment({ writeOutputs: false });
    expect(scenario.result).toBeUndefined();
    expect(scenario.error?.message).toBe("RECEIPT_UNAVAILABLE");
  });
});
