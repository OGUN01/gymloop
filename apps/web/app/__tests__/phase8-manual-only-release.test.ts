import { readdir } from "node:fs/promises";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { addonSaleRequestSchema } from "../../../../packages/shared/src/api/addons";
import { paymentRequestSchema } from "../../../../packages/shared/src/api/payments";

const TEST_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const WEB_API_DIRECTORY = join(TEST_DIRECTORY, "..", "api");
const MOBILE_DIRECTORY = join(TEST_DIRECTORY, "..", "..", "..", "mobile");
const PROVIDER_ROUTE_SEGMENT = /(^|[-_/])(razorpay|webhook|charge|checkout|payment-intent)([-_/]|$)/i;
const CREDENTIAL_ROUTE_SEGMENT = /(^|[-_/])(card|upi)([-_/]|$)/i;
const MANUAL_METHODS = ["cash", "upi", "card", "bank_transfer"] as const;

async function filePaths(directory: string): Promise<string[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = join(directory, entry.name);

      return entry.isDirectory() ? filePaths(path) : [path];
    }),
  );

  return nested.flat();
}

function methodIsRejected(
  schema: { safeParse: (value: unknown) => { success: boolean; error?: { issues: Array<{ path: PropertyKey[] }> } } },
  field: "method" | "paymentMethod",
  method: string,
): boolean {
  const result = schema.safeParse({ [field]: method });

  return !result.success && (result.error?.issues.some((issue) => issue.path.join(".") === field) ?? false);
}

describe("PAY-012 initial manual-only release", () => {
  it("does not expose a provider, charge-initiation, credential-capture, or webhook route in web or mobile", async () => {
    const [webApiFiles, mobileFiles] = await Promise.all([
      filePaths(WEB_API_DIRECTORY),
      filePaths(MOBILE_DIRECTORY),
    ]);
    const publicRoutePaths = [...webApiFiles, ...mobileFiles]
      .map((path) => relative(TEST_DIRECTORY, path).split(sep).join("/"));

    expect(publicRoutePaths.filter((path) => PROVIDER_ROUTE_SEGMENT.test(path))).toEqual([]);
    expect(publicRoutePaths.filter((path) => CREDENTIAL_ROUTE_SEGMENT.test(path))).toEqual([]);
  });

  it("keeps the desk payment command manual while refusing razorpay", () => {
    expect(methodIsRejected(paymentRequestSchema, "method", "razorpay")).toBe(true);

    for (const method of MANUAL_METHODS) {
      expect(methodIsRejected(paymentRequestSchema, "method", method)).toBe(false);
    }
  });

  it("keeps the front-desk add-on sale command manual while refusing razorpay", () => {
    const methodFields = ["method", "paymentMethod"] as const;

    expect(methodFields.some((field) => methodIsRejected(addonSaleRequestSchema, field, "razorpay"))).toBe(true);

    for (const method of MANUAL_METHODS) {
      expect(methodFields.every((field) => !methodIsRejected(addonSaleRequestSchema, field, method))).toBe(true);
    }
  });
});
