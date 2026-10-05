import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";

// B2: Notes Together (DougReeder/notes-together) against the real app.
// explore/PLAN-explore.md. Connect via the app's widget/OAuth (module `documents`),
// create a note, verify it on the server, read it from a second browser context,
// then delete it through the app.
const NC_URL = process.env.NC_URL ?? "http://nextcloud";
const APP_URL = process.env.APP_URL ?? "http://nt";
const NC_USER = process.env.NC_USER ?? "rstest";
const NC_PASS = process.env.NC_PASS ?? "rstest-pass";
const TOKEN = process.env.RS_TOKEN ?? "";
const EVIDENCE = process.env.EVIDENCE_DIR ?? "/tmp";
const EXPLORE = process.env.EXPLORE ?? "";
const STORAGE = `${NC_URL}/remote.php/dav/files/${NC_USER}/remoteStorage`;
const TEXT = "Hello from Notes Together";

test.skip(EXPLORE !== "nt", "explore nt only");
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

async function connect(page: Page): Promise<void> {
  await page.waitForSelector("#remotestorage-widget", { timeout: 20000 });
  await page.click("#remotestorage-widget");
  // This app sets Dropbox/Drive API keys, so the widget first shows the provider
  // chooser; pick remoteStorage. (Apps without keys skip straight to sign-in.)
  await page.waitForSelector(".rs-box-choose.rs-selected, .rs-box-sign-in.rs-selected", { timeout: 10000 });
  if (await page.locator(".rs-box-choose.rs-selected").count()) {
    await page.click("button.rs-choose-rs");
    await page.waitForSelector(".rs-box-sign-in.rs-selected", { timeout: 10000 });
  }
  const address = page.locator("input[name=rs-user-address]");
  await address.fill(`${NC_USER}@nextcloud`);
  await page.click("button.rs-connect");
  await page.waitForSelector("input#user, input[name='user'], #remotestorage-allow", { timeout: 30000 });
  await loginIfAsked(page);
  const allow = page.locator("#remotestorage-allow");
  await allow.waitFor({ timeout: 30000 });
  await dismissFirstRunWizard(page);
  // The widget collapses to a hidden icon once connected, so watch its state class
  // (or the app's own "remoteStorage connected" log), not element visibility.
  const connectedMsg = page
    .waitForEvent("console", { predicate: (m) => m.text().includes("remoteStorage connected"), timeout: 30000 })
    .catch(() => null);
  await allow.click();
  await page.waitForURL(`${APP_URL}/**`, { timeout: 30000 });
  await Promise.race([
    page.waitForFunction(
      () => document.getElementById("remotestorage-widget")?.className.includes("rs-state-connected"),
      null, { timeout: 30000 }
    ).catch(() => null),
    connectedMsg,
  ]);
}

async function serverContents(dav: import("@playwright/test").APIRequestContext): Promise<string[]> {
  const res = await dav.get(`${STORAGE}/documents/notes/`);
  if (!res.ok()) return [];
  const items = (await res.json()).items ?? {};
  const out: string[] = [];
  for (const id of Object.keys(items)) {
    if (id.endsWith("/")) continue;
    const doc = await dav.get(`${STORAGE}/documents/notes/${id}`);
    if (doc.ok()) {
      const body = await doc.json();
      out.push(`${body.title ?? ""}\n${body.content ?? ""}`);
    }
  }
  return out;
}

test("B2 Notes Together: connect, create, server, second device, delete", async ({ browser, playwright }) => {
  fs.mkdirSync(EVIDENCE, { recursive: true });
  const logs: string[] = [];
  const dav = await playwright.request.newContext({ extraHTTPHeaders: { Authorization: `Bearer ${TOKEN}` } });

  // --- device A: connect and create a note through the editor ---
  const ctxA = await browser.newContext();
  const pageA = await ctxA.newPage();
  pageA.on("console", (m) => logs.push(`A console.${m.type()}: ${m.text()}`));
  pageA.on("pageerror", (e) => logs.push(`A pageerror: ${e.message}`));
  await pageA.goto(`${APP_URL}/`, { waitUntil: "load" });
  await pageA.screenshot({ path: `${EVIDENCE}/01-loaded.png`, fullPage: true }).catch(() => {});
  await connect(pageA);
  await pageA.screenshot({ path: `${EVIDENCE}/02-connected.png`, fullPage: true }).catch(() => {});

  await pageA.click('button[title="Create new note"]');
  const editor = pageA.locator("[data-slate-editor], [contenteditable=true]").first();
  await editor.waitFor({ timeout: 15000 });
  await editor.click();
  await pageA.waitForTimeout(300);
  // Slate drops/scrambles characters when typed too fast; go at a human pace.
  await editor.pressSequentially(TEXT, { delay: 120 });
  await expect(editor).toContainText(TEXT, { timeout: 10000 });
  await pageA.screenshot({ path: `${EVIDENCE}/03-note-typed.png`, fullPage: true }).catch(() => {});

  await expect.poll(async () => (await serverContents(dav)).some((c) => c.includes(TEXT)), { timeout: 30000 }).toBe(true);
  await ctxA.close();

  // --- device B: fresh browser, connect, read the note from the server ---
  const ctxB = await browser.newContext();
  const pageB = await ctxB.newPage();
  pageB.on("console", (m) => logs.push(`B console.${m.type()}: ${m.text()}`));
  pageB.on("pageerror", (e) => logs.push(`B pageerror: ${e.message}`));
  await pageB.goto(`${APP_URL}/`, { waitUntil: "load" });
  await connect(pageB);
  const listItem = pageB.locator("ol.list li.summary", { hasText: TEXT }).first();
  await expect(listItem).toBeVisible({ timeout: 30000 });
  await pageB.screenshot({ path: `${EVIDENCE}/04-second-device.png`, fullPage: true }).catch(() => {});

  // --- delete through the app: right-click the item, then Delete ---
  await listItem.click({ button: "right" });
  await listItem.getByRole("button", { name: "Delete" }).click();
  await expect.poll(async () => (await serverContents(dav)).some((c) => c.includes(TEXT)), { timeout: 30000 }).toBe(false);
  await pageB.screenshot({ path: `${EVIDENCE}/05-deleted.png`, fullPage: true }).catch(() => {});

  fs.writeFileSync(`${EVIDENCE}/console.log`, logs.join("\n"));
  await ctxB.close();
  await dav.dispose();
});
