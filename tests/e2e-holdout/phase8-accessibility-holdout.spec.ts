import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Locator, type Page, type TestInfo } from "@playwright/test";
import { playwrightEnv } from "@gymloop/shared";

const OWNER_EMAIL = "owner@ironbox.example.com";
const SUPER_ADMIN_EMAIL = "admin@gymloop.example.com";
const MEMBER_ID = "00000005-0000-4000-8000-000000000001";
const PAYMENT_ID = "00000007-0000-4000-8000-000000000001";
const ADD_ON_ORDER_ID = "00000010-0000-4000-8000-000000000001";
const GYM_ID = "00000001-0000-4000-8000-000000000001";

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"];
const APPEARANCES = ["light", "dark"] as const;
const VIEWPORTS = [
  { name: "narrow-390", width: 390, height: 844 },
  { name: "desktop-1440", width: 1440, height: 1000 },
] as const;

const OWNER_ROUTES = [
  { name: "member detail", path: `/members/${MEMBER_ID}` },
  { name: "member edit", path: `/members/${MEMBER_ID}/edit` },
  { name: "member creation", path: "/members/new" },
  { name: "membership detail", path: `/memberships/${MEMBER_ID}` },
  { name: "payment detail", path: `/payments/${PAYMENT_ID}` },
  { name: "add-on order detail", path: `/add-ons/orders/${ADD_ON_ORDER_ID}` },
] as const;

const PLATFORM_ROUTES = [
  { name: "gym detail", path: `/platform/${GYM_ID}` },
] as const;

type Appearance = (typeof APPEARANCES)[number];
type RouteUnderTest = (typeof OWNER_ROUTES)[number] | (typeof PLATFORM_ROUTES)[number];
type ViewportUnderTest = (typeof VIEWPORTS)[number];

const { DEMO_ACCOUNT_PASSWORD, PLAYWRIGHT_BASE_URL } = playwrightEnv();

async function signIn(page: Page, email: string, homePath: "/dashboard" | "/platform"): Promise<void> {
  await page.goto(new URL("/sign-in", PLAYWRIGHT_BASE_URL).toString());
  await page.getByText("Use email instead", { exact: true }).click();
  await page.getByLabel("Email", { exact: true }).fill(email);
  await page.getByLabel("Password", { exact: true }).fill(DEMO_ACCOUNT_PASSWORD);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await page.waitForURL((url) => url.pathname === homePath, { waitUntil: "domcontentloaded" });
  expect(new URL(page.url()).pathname).toBe(homePath);
}

async function useVisibleControl(
  controls: Locator[],
  action: (control: Locator) => Promise<void>,
): Promise<boolean> {
  for (const controlsOfOneKind of controls) {
    for (let index = 0; index < (await controlsOfOneKind.count()); index += 1) {
      const control = controlsOfOneKind.nth(index);
      if (await control.isVisible()) {
        await action(control);
        return true;
      }
    }
  }

  return false;
}

async function chooseAppearance(page: Page, appearance: Appearance): Promise<void> {
  const accessibleName = new RegExp(`^${appearance}$`, "i");
  const chooseDirectly = async (): Promise<boolean> => {
    const clicked = await useVisibleControl(
      [
        page.getByRole("button", { name: accessibleName }),
        page.getByRole("radio", { name: accessibleName }),
        page.getByRole("menuitemradio", { name: accessibleName }),
      ],
      async (control) => control.click(),
    );
    if (clicked) {
      return true;
    }

    return useVisibleControl(
      [page.getByRole("combobox", { name: /appearance|theme/i })],
      async (control) => {
        const option = control.locator("option").filter({
          hasText: new RegExp(`^${appearance}$`, "i"),
        });
        expect(await option.count(), `the appearance selector must offer ${appearance}`).toBeGreaterThan(0);
        const value = await option.first().getAttribute("value");
        await control.selectOption(
          value ?? { label: `${appearance.charAt(0).toUpperCase()}${appearance.slice(1)}` },
        );
      },
    );
  };

  if (await chooseDirectly()) {
    return;
  }

  await useVisibleControl(
    [page.getByRole("button", { name: /menu|navigation/i })],
    async (control) => control.click(),
  );
  if (await chooseDirectly()) {
    return;
  }

  await useVisibleControl(
    [page.getByRole("button", { name: /appearance|theme|settings/i })],
    async (control) => control.click(),
  );
  expect(await chooseDirectly(), "an accessible Light/Dark appearance choice must be reachable").toBe(true);
}

async function assertEnglishDocument(page: Page): Promise<void> {
  const languageEvidence = await page.evaluate(() => ({
    documentLanguage: document.documentElement.lang,
    nonEnglishLanguageMarkers: Array.from(document.querySelectorAll<HTMLElement>("[lang]"))
      .map((element) => element.lang.trim().toLowerCase())
      .filter((language) => language !== "en" && !language.startsWith("en-")),
  }));

  expect(languageEvidence.documentLanguage.toLowerCase()).toMatch(/^en(?:-|$)/);
  expect(languageEvidence.nonEnglishLanguageMarkers).toEqual([]);
}

async function assertNoHorizontalOverflow(page: Page, expectedWidth: number): Promise<void> {
  const dimensions = await page.evaluate(() => ({
    viewportWidth: window.innerWidth,
    rootClientWidth: document.documentElement.clientWidth,
    rootScrollWidth: document.documentElement.scrollWidth,
    bodyScrollWidth: document.body.scrollWidth,
  }));

  expect(dimensions.viewportWidth).toBe(expectedWidth);
  expect(dimensions.rootClientWidth).toBe(expectedWidth);
  expect(Math.max(dimensions.rootScrollWidth, dimensions.bodyScrollWidth)).toBeLessThanOrEqual(
    expectedWidth,
  );
}

async function collectAppearanceEvidence(page: Page, appearance: Appearance) {
  const evidence = await page.evaluate(() => {
    const root = document.documentElement;
    const body = document.body;
    return {
      rootAttributes: Array.from(root.attributes).map(({ name, value }) => `${name}=${value}`),
      rootColorScheme: getComputedStyle(root).colorScheme,
      bodyColorScheme: getComputedStyle(body).colorScheme,
      prefersDark: window.matchMedia("(prefers-color-scheme: dark)").matches,
    };
  });
  const renderedAppearance = [
    ...evidence.rootAttributes,
    evidence.rootColorScheme,
    evidence.bodyColorScheme,
  ].join(" ");

  expect(renderedAppearance.toLowerCase()).toContain(appearance);
  return evidence;
}

async function assertAccessibleRoute(
  page: Page,
  testInfo: TestInfo,
  route: RouteUnderTest,
  appearance: Appearance,
  viewport: ViewportUnderTest,
  identity: { audience: "owner" | "super-admin"; email: string },
): Promise<void> {
  const response = await page.goto(new URL(route.path, PLAYWRIGHT_BASE_URL).toString(), {
    waitUntil: "domcontentloaded",
  });

  expect(response, `${route.path} must return a document response`).not.toBeNull();
  expect(response?.ok(), `${route.path} returned ${response?.status()}`).toBe(true);
  expect(new URL(page.url()).pathname).toBe(route.path);
  await expect(page.locator("main")).toBeVisible();
  await page.evaluate(async () => {
    await document.fonts.ready;
  });

  await chooseAppearance(page, appearance);
  const appearanceEvidence = await collectAppearanceEvidence(page, appearance);
  await assertEnglishDocument(page);
  await assertNoHorizontalOverflow(page, viewport.width);

  const axeResult = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  await testInfo.attach(
    `${identity.audience}-${route.name.replaceAll(" ", "-")}-${appearance}-${viewport.name}.json`,
    {
      body: JSON.stringify(
        {
          requirement: "HARD-003",
          session: `${identity.audience}-${appearance}-${viewport.name}`,
          user: identity.email,
          audience: identity.audience,
          gymId: GYM_ID,
          route: route.path,
          appearance,
          viewport: { width: viewport.width, height: viewport.height },
          assertions: [
            "authenticated route returned a successful response",
            "route did not redirect across the role boundary",
            "document language and language markers are English",
            "document has no horizontal overflow",
            "WCAG A/AA axe scan has no violations",
          ],
          appearanceEvidence,
          axeViolations: axeResult.violations,
        },
        null,
        2,
      ),
      contentType: "application/json",
    },
  );

  expect(
    axeResult.violations,
    `${route.path} has axe violations in ${appearance} at ${viewport.width}px:\n${JSON.stringify(
      axeResult.violations,
      null,
      2,
    )}`,
  ).toEqual([]);
}

for (const appearance of APPEARANCES) {
  for (const viewport of VIEWPORTS) {
    for (const route of OWNER_ROUTES) {
      test(`owner ${route.name}: ${appearance}, ${viewport.name}`, async ({ browser }, testInfo) => {
        const context = await browser.newContext({
          baseURL: PLAYWRIGHT_BASE_URL,
          colorScheme: appearance,
        });
        const page = await context.newPage();

        try {
          await signIn(page, OWNER_EMAIL, "/dashboard");
          await page.setViewportSize({ width: viewport.width, height: viewport.height });
          await assertAccessibleRoute(page, testInfo, route, appearance, viewport, {
            audience: "owner",
            email: OWNER_EMAIL,
          });
        } finally {
          await context.close().catch(() => undefined);
        }
      });
    }

    test(`super-admin gym detail: ${appearance}, ${viewport.name}`, async ({ browser }, testInfo) => {
      const context = await browser.newContext({
        baseURL: PLAYWRIGHT_BASE_URL,
        colorScheme: appearance,
      });
      const page = await context.newPage();

      try {
        await signIn(page, SUPER_ADMIN_EMAIL, "/platform");
        await page.setViewportSize({ width: viewport.width, height: viewport.height });
        await assertAccessibleRoute(page, testInfo, PLATFORM_ROUTES[0], appearance, viewport, {
          audience: "super-admin",
          email: SUPER_ADMIN_EMAIL,
          });
      } finally {
        await context.close().catch(() => undefined);
      }
    });
  }
}
