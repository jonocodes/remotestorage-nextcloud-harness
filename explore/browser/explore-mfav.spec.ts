import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";

// B1: My Favorite Drinks (remotestorage/myfavoritedrinks) against the real app.
// explore/PLAN-explore.md. Connect via the remoteStorage widget's own flow, add a
// drink, verify on the server, reload (second device), delete. Screenshots and a
// console log go to EVIDENCE_DIR.
const NC_URL = process.env.NC_URL ?? "http://nextcloud";
const APP_URL = process.env.APP_URL ?? "http://mfav";
const NC_USER = process.env.NC_USER ?? "rstest";
const NC_PASS = process.env.NC_PASS ?? "rstest-pass";
const TOKEN = process.env.RS_TOKEN ?? "";
const EVIDENCE = process.env.EVIDENCE_DIR ?? "/tmp";
const EXPLORE = process.env.EXPLORE ?? "";
const STORAGE = `${NC_URL}/remote.php/dav/files/${NC_USER}/remoteStorage`;

test.skip(EXPLORE !== "mfav", "explore mfav only");
test.describe.configure({ mode: "serial" });
test.setTimeout(180_000);

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
  try {
    await wizard.waitFor({ state: "visible", timeout: 8000 });
  } catch {
    return;
  }
  const skip = wizard.getByRole("button", { name: "Skip" });
  if (await skip.count()) await skip.click();
  await page.locator("[role='dialog'] button[aria-label='Close']").first().click();
  await wizard.waitFor({ state: "hidden", timeout: 5000 });
}

test("B1 My Favorite Drinks: connect, add, sync, reload, delete", async ({ browser, playwright }) => {
  fs.mkdirSync(EVIDENCE, { recursive: true });
  const logs: string[] = [];
  const context = await browser.newContext();
  const page = await context.newPage();
  page.on("console", (m) => logs.push(`console.${m.type()}: ${m.text()}`));
  page.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));

  const shot = async (name: string) => { await page.screenshot({ path: `${EVIDENCE}/${name}.png`, fullPage: true }).catch(() => {}); };

  await page.goto(`${APP_URL}/`, { waitUntil: "load" });
  await shot("01-loaded");
  const widgetIcon = page.locator("#remotestorage-widget");
  await widgetIcon.waitFor({ timeout: 15000 });
  await widgetIcon.click();
  const address = page.locator("input[name=rs-user-address]");
  if (!(await address.isVisible().catch(() => false))) {
    await page.locator("button.rs-choose-rs").click();
  }
  await address.fill(`${NC_USER}@nextcloud`);
  await shot("02-widget-address");
  await page.click("button.rs-connect");

  // The OAuth URL lands on Nextcloud's login first (redirecting through /login),
  // then the consent page. Wait for whichever appears before acting.
  await page.waitForSelector("input#user, input[name='user'], #remotestorage-allow", { timeout: 30000 });
  await loginIfAsked(page);
  const allow = page.locator("#remotestorage-allow");
  await allow.waitFor({ timeout: 30000 });
  await dismissFirstRunWizard(page);
  await shot("03-consent");
  await allow.click();
  await page.waitForURL(`${APP_URL}/**`, { timeout: 30000 });

  await page.waitForFunction(() => (window as any).remoteStorage?.connected === true, null, { timeout: 30000 });
  await shot("04-connected");

  const dav = await playwright.request.newContext({ extraHTTPHeaders: { Authorization: `Bearer ${TOKEN}` } });
  const items = async (): Promise<Record<string, any>> => {
    const res = await dav.get(`${STORAGE}/myfavoritedrinks/`);
    return res.ok() ? (await res.json()).items ?? {} : {};
  };
  // Folder listings carry metadata only, so read each document's body for the name.
  const drinkNames = async () => {
    const names: string[] = [];
    for (const id of Object.keys(await items())) {
      const doc = await dav.get(`${STORAGE}/myfavoritedrinks/${id}`);
      if (doc.ok()) names.push((await doc.json()).name);
    }
    return names.sort();
  };

  // Add a drink through the app's form.
  await page.fill("#add-drink input", "Coffee");
  await page.click("#add-drink button[type='submit']");
  await expect.poll(drinkNames, { timeout: 20000 }).toEqual(["Coffee"]);
  await expect(page.locator("#drink-list li input[type=text]").first()).toHaveValue("Coffee");
  await shot("05-drink-added");

  // Reload = a second device reading from the server.
  await page.reload({ waitUntil: "load" });
  await page.waitForFunction(() => (window as any).remoteStorage?.connected === true, null, { timeout: 30000 });
  await expect(page.locator("#drink-list li input[type=text]").first()).toHaveValue("Coffee", { timeout: 20000 });
  await shot("06-after-reload");

  // Delete through the app.
  await page.click("#drink-list li button.delete");
  await expect.poll(drinkNames, { timeout: 20000 }).toEqual([]);
  await shot("07-deleted");

  fs.writeFileSync(`${EVIDENCE}/console.log`, logs.join("\n"));
  await context.close();
  await dav.dispose();
});
