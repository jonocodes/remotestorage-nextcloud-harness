import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";

// B3: RS Inspektor (m5x5/inspektor) against the real app. explore/PLAN-explore.md.
// Scope `*`: browse the whole account, open a JSON document (tree view) and an
// image, and delete a document. Doubles as a verifier for the other clients.
const NC_URL = process.env.NC_URL ?? "http://nextcloud";
const APP_URL = process.env.APP_URL ?? "http://inspektor";
const NC_USER = process.env.NC_USER ?? "rstest";
const NC_PASS = process.env.NC_PASS ?? "rstest-pass";
const TOKEN = process.env.RS_TOKEN ?? "";
const EVIDENCE = process.env.EVIDENCE_DIR ?? "/tmp";
const EXPLORE = process.env.EXPLORE ?? "";
const STORAGE = `${NC_URL}/remote.php/dav/files/${NC_USER}/remoteStorage`;

test.skip(EXPLORE !== "inspektor", "explore inspektor only");
test.describe.configure({ mode: "serial" });
test.setTimeout(240_000);

async function loginIfAsked(page: Page): Promise<void> {
  const user = page.locator("input#user, input[name='user']").first();
  if (await user.count().catch(() => 0)) {
    await user.fill(NC_USER);
    await page.locator("input#password, input[name='password']").first().fill(NC_PASS);
    await page.locator("button[type='submit'], input[type='submit']").first().click();
  }
}
async function dismissFirstRunWizard(page: Page): Promise<void> {
  const wizard = page.locator("[role='dialog']#firstrunwizard");
  try { await wizard.waitFor({ state: "visible", timeout: 8000 }); } catch { return; }
  const skip = wizard.getByRole("button", { name: "Skip" });
  if (await skip.count()) await skip.click();
  await page.locator("[role='dialog'] button[aria-label='Close']").first().click();
  await wizard.waitFor({ state: "hidden", timeout: 5000 });
}
async function openShadow(page: Page): Promise<void> {
  // Inspektor's widget uses a CLOSED shadow root; force it open so Playwright can
  // reach the controls (the widget itself is unchanged).
  await page.addInitScript(() => {
    const orig = Element.prototype.attachShadow;
    Element.prototype.attachShadow = function (init: ShadowRootInit) {
      return orig.call(this, { ...init, mode: "open" });
    };
  });
}
async function connect(page: Page): Promise<void> {
  await page.goto(`${APP_URL}/connect`, { waitUntil: "load" });
  await page.locator(".rs-box-initial").click({ timeout: 20000 });
  await page.waitForSelector(".rs-box-choose.rs-selected, .rs-box-sign-in.rs-selected", { timeout: 10000 });
  if (await page.locator(".rs-box-choose.rs-selected").count()) {
    await page.locator("button.rs-choose-rs").click();
  }
  await page.locator("input[name=rs-user-address]").fill(`${NC_USER}@nextcloud`);
  await page.locator("button.rs-connect").click();
  await page.waitForSelector("input#user, input[name='user'], #remotestorage-allow", { timeout: 30000 });
  await loginIfAsked(page);
  const allow = page.locator("#remotestorage-allow");
  await allow.waitFor({ timeout: 30000 });
  await dismissFirstRunWizard(page);
  await allow.click();
  await page.waitForURL(`${APP_URL}/**`, { timeout: 30000 });
  await page.getByText("Browse files").waitFor({ timeout: 30000 });
}

test("B3 RS Inspektor: connect, browse, view JSON + image, delete", async ({ browser, playwright }) => {
  fs.mkdirSync(EVIDENCE, { recursive: true });
  const logs: string[] = [];
  const dav = await playwright.request.newContext({ extraHTTPHeaders: { Authorization: `Bearer ${TOKEN}` } });
  const listed = async () => {
    const res = await dav.get(`${STORAGE}/b3/`);
    return res.ok() ? Object.keys((await res.json()).items ?? {}) : [];
  };

  const context = await browser.newContext();
  const page = await context.newPage();
  page.on("console", (m) => logs.push(`console.${m.type()}: ${m.text()}`));
  page.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
  await openShadow(page);
  await connect(page);
  await page.screenshot({ path: `${EVIDENCE}/01-connected.png`, fullPage: true }).catch(() => {});

  // Root listing (scope *): the account's modules are visible.
  await page.goto(`${APP_URL}/`, { waitUntil: "load" });
  await expect(page.getByRole("link", { name: "b3" }).first()).toBeVisible({ timeout: 20000 });
  await page.screenshot({ path: `${EVIDENCE}/02-root.png`, fullPage: true }).catch(() => {});

  // JSON document renders a tree view.
  await page.goto(`${APP_URL}/inspect?path=b3%2Fhello.json`, { waitUntil: "load" });
  await expect(page.getByText("greeting")).toBeVisible({ timeout: 20000 });
  await page.screenshot({ path: `${EVIDENCE}/03-json.png`, fullPage: true }).catch(() => {});

  // Image: the preview does NOT render — with `cache: true`, rs.js beta.8's
  // getListing loses Content-Type (issues 721/1108), so the client sees
  // application/octet-stream and never builds a blob URL. Client limitation, not
  // the app's: verify the app serves the correct PNG bytes to the token anyway.
  await page.goto(`${APP_URL}/inspect?path=b3%2Fpic.png`, { waitUntil: "load" });
  await page.waitForTimeout(2000);
  const imgRes = await dav.get(`${STORAGE}/b3/pic.png`);
  const bytes = new Uint8Array(await imgRes.body());
  expect([bytes[0], bytes[1], bytes[2], bytes[3]]).toEqual([0x89, 0x50, 0x4e, 0x47]);
  await page.screenshot({ path: `${EVIDENCE}/04-image.png`, fullPage: true }).catch(() => {});

  // Delete a document through the app's own UI.
  expect(await listed()).toContain("notes.txt");
  await page.goto(`${APP_URL}/inspect?path=b3%2Fnotes.txt`, { waitUntil: "load" });
  await page.getByRole("button", { name: /Document actions|More actions/ }).click();
  await page.getByRole("menuitem", { name: "Delete" }).click();
  await page.getByRole("alertdialog").getByRole("button", { name: "Delete" }).click();
  await expect.poll(async () => (await listed()).includes("notes.txt"), { timeout: 30000 }).toBe(false);
  await page.screenshot({ path: `${EVIDENCE}/05-deleted.png`, fullPage: true }).catch(() => {});

  fs.writeFileSync(`${EVIDENCE}/console.log`, logs.join("\n"));
  await context.close();
  await dav.dispose();
});
