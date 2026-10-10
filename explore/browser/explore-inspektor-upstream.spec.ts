import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";

// B3u: upstream RS Inspektor (raucao/inspektor @ 0bece35, Ember 2.16,
// remotestoragejs 1.1.0 with `cache: false`, remotestorage-widget 1.3.0) against
// the real app. explore/PLAN-explore.md, explore/sessions/inspektor-upstream/notes.md.
// Scope `*`: browse the whole account, open a JSON document (tree view) and images,
// record the File info metadata panel, and delete a document.
//
// Key observation (contrast B3, m5x5's Next.js rewrite with `cache: true`): with
// caching off, getListing returns Content-Type / Content-Length / ETag per item,
// so the metadata panel should show the server's values.
const NC_URL = process.env.NC_URL ?? "http://nextcloud";
const APP_URL = process.env.APP_URL ?? "http://localhost:8082";
const NC_USER = process.env.NC_USER ?? "rstest";
const NC_PASS = process.env.NC_PASS ?? "rstest-pass";
const TOKEN = process.env.RS_TOKEN ?? "";
const EVIDENCE = process.env.EVIDENCE_DIR ?? "/tmp";
const EXPLORE = process.env.EXPLORE ?? "";
const STORAGE = `${NC_URL}/remote.php/dav/files/${NC_USER}/remoteStorage`;

test.skip(EXPLORE !== "inspektor-upstream", "explore inspektor-upstream only");
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
  // remotestorage-widget 1.3.0: plain DOM (no shadow root). Inspektor passes
  // skipInitial, so the sign-in box is usually already selected.
  await page.goto(`${APP_URL}/connect`, { waitUntil: "load" });
  const address = page.locator("input[name=rs-user-address]");
  try {
    await address.waitFor({ state: "visible", timeout: 8000 });
  } catch {
    await page.locator(".rs-box-initial, .rs-widget-icon").first().click();
    if (await page.locator(".rs-box-choose.rs-selected").count()) {
      await page.locator("button.rs-choose-rs").click();
    }
    await address.waitFor({ state: "visible", timeout: 10000 });
  }
  await address.fill(`${NC_USER}@nextcloud`);
  await page.locator("input.rs-connect").click();
  await page.waitForSelector("input#user, input[name='user'], #remotestorage-allow", { timeout: 30000 });
  await loginIfAsked(page);
  const allow = page.locator("#remotestorage-allow");
  await allow.waitFor({ timeout: 30000 });
  await dismissFirstRunWizard(page);
  await allow.click();
  await page.waitForURL(`${APP_URL}/**`, { timeout: 30000 });
  await page.locator(".account-info, .username").first().waitFor({ timeout: 30000 });
}
// The File info panel: <section class="meta"><dl><dt>…</dt><dd>…</dd>…</dl>.
async function fileInfo(page: Page): Promise<Record<string, string>> {
  return page.locator("section.meta dl").evaluate((dl) => {
    const out: Record<string, string> = {};
    const dts = Array.from(dl.querySelectorAll("dt"));
    for (const dt of dts) {
      const dd = dt.nextElementSibling;
      out[(dt.textContent ?? "").trim()] = (dd?.textContent ?? "").trim();
    }
    return out;
  });
}
async function openFromListing(page: Page, name: string): Promise<void> {
  await page.locator("main ul.listing a", { has: page.locator(".name", { hasText: new RegExp(`^${name.replace(/[.]/g, "\\.")}$`) }) }).click();
  await page.locator("section.meta").waitFor({ timeout: 20000 });
  await expect(page.locator("section.meta dd").first()).toHaveText(name, { timeout: 20000 });
}
async function backToB3(page: Page): Promise<void> {
  await page.locator("header .node a", { hasText: /^b3$/ }).click();
  await page.locator("main ul.listing").waitFor({ timeout: 20000 });
}

test("B3u upstream RS Inspektor: connect, browse, JSON tree, image preview + metadata, delete", async ({ browser, playwright }) => {
  fs.mkdirSync(EVIDENCE, { recursive: true });
  const logs: string[] = [];
  const observed: Record<string, unknown> = {};
  const dav = await playwright.request.newContext({ extraHTTPHeaders: { Authorization: `Bearer ${TOKEN}` } });
  const serverListing = async () => {
    const res = await dav.get(`${STORAGE}/b3/`);
    return res.ok() ? ((await res.json()).items ?? {}) : {};
  };
  observed.server = await serverListing();

  const context = await browser.newContext();
  const page = await context.newPage();
  page.on("console", (m) => logs.push(`console.${m.type()}: ${m.text()}`));
  page.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
  page.on("dialog", (d) => { logs.push(`dialog: ${d.message()}`); void d.accept(); });

  try {
    await connect(page);
    await page.screenshot({ path: `${EVIDENCE}/01-connected.png`, fullPage: true }).catch(() => {});

    // Root listing (scope *): the account's modules are visible, `b3` among them.
    const b3 = page.locator("main ul.listing a", { has: page.locator(".name", { hasText: /^b3\/$/ }) });
    await expect(b3).toBeVisible({ timeout: 20000 });
    observed.root = await page.locator("main ul.listing .name").allTextContents();
    await page.screenshot({ path: `${EVIDENCE}/02-root.png`, fullPage: true }).catch(() => {});

    // /b3/ listing: per-item size and type columns.
    await b3.click();
    await expect(page.locator("main ul.listing .name", { hasText: /^hello\.json$/ })).toBeVisible({ timeout: 20000 });
    observed.b3Listing = await page.locator("main ul.listing li").evaluateAll((lis) =>
      lis.map((li) => ({
        name: li.querySelector(".name")?.textContent?.trim(),
        size: li.querySelector(".size")?.textContent?.trim(),
        type: li.querySelector(".type")?.textContent?.trim(),
      })));

    // JSON document: tree view (json-tree-view) and its metadata.
    await openFromListing(page, "hello.json");
    await expect(page.locator("#json-tree-view")).toBeVisible({ timeout: 20000 });
    await expect(page.locator("#json-tree-view")).toContainText("greeting", { timeout: 20000 });
    observed.jsonTree = (await page.locator("#json-tree-view").innerText()).replace(/\s+/g, " ").trim();
    observed["hello.json"] = await fileInfo(page);
    await page.screenshot({ path: `${EVIDENCE}/03-json.png`, fullPage: true }).catch(() => {});

    // Images: pic.png stored as plain "image/png" (as B3 seeds it) and pic-rsjs.png
    // as rs.js 1.x stores binaries ("image/png; charset=binary"). Upstream only
    // previews when the type contains charset=binary (isBinary in storage.js).
    const images: Record<string, unknown> = {};
    for (const name of ["pic.png", "pic-rsjs.png"]) {
      await backToB3(page);
      await openFromListing(page, name);
      await page.waitForTimeout(2000);
      const img = page.locator(".file-preview img");
      const src = (await img.count()) ? await img.getAttribute("src") : null;
      const natural = (await img.count())
        ? await img.evaluate((el: HTMLImageElement) => ({ complete: el.complete, w: el.naturalWidth, h: el.naturalHeight }))
        : null;
      const codeText = (await page.locator(".file-preview code").count())
        ? (await page.locator(".file-preview code").innerText()).slice(0, 40)
        : null;
      images[name] = {
        info: await fileInfo(page),
        preview: src && /^(blob:|data:)/.test(src) && natural && natural.w > 0 ? "rendered" : "not rendered",
        imgSrc: src,
        natural,
        codeText,
      };
      const shot = name === "pic.png" ? "04-image.png" : "04b-image-rsjs.png";
      await page.screenshot({ path: `${EVIDENCE}/${shot}`, fullPage: true }).catch(() => {});
    }
    observed.images = images;

    // The app serves the correct PNG bytes regardless of what the client renders.
    const imgRes = await dav.get(`${STORAGE}/b3/pic.png`);
    const bytes = new Uint8Array(await imgRes.body());
    expect([bytes[0], bytes[1], bytes[2], bytes[3]]).toEqual([0x89, 0x50, 0x4e, 0x47]);

    // notes.txt metadata, then delete it through the app's own UI (trash button +
    // window.confirm, accepted by the dialog handler above).
    expect(Object.keys(await serverListing())).toContain("notes.txt");
    await backToB3(page);
    await openFromListing(page, "notes.txt");
    observed["notes.txt"] = await fileInfo(page);
    await page.locator("header nav.actions button.delete").click();
    await expect.poll(async () => Object.keys(await serverListing()).includes("notes.txt"), { timeout: 30000 }).toBe(false);
    await expect(page.locator("main ul.listing .name", { hasText: /^notes\.txt$/ })).toHaveCount(0, { timeout: 20000 });
    await page.screenshot({ path: `${EVIDENCE}/05-deleted.png`, fullPage: true }).catch(() => {});

    // Hard assertions on metadata: with cache:false the panel must carry the
    // server's Content-Type, a size, and an ETag for each file.
    const info = (n: string) => (n.endsWith(".png") ? (images[n] as { info: Record<string, string> }).info : observed[n] as Record<string, string>);
    expect(info("hello.json")["Content type"]).toBe("application/json");
    expect(info("pic.png")["Content type"]).toBe("image/png");
    expect(info("pic-rsjs.png")["Content type"]).toBe("image/png");
    for (const n of ["hello.json", "pic.png", "pic-rsjs.png", "notes.txt"]) {
      expect(info(n)["Size"], `${n} size`).not.toBe("");
      expect(info(n)["Revision (ETag)"], `${n} etag`).not.toBe("");
    }
  } finally {
    console.log(JSON.stringify(observed, null, 2));
    fs.writeFileSync(`${EVIDENCE}/observed.json`, JSON.stringify(observed, null, 2));
    fs.writeFileSync(`${EVIDENCE}/console.log`, logs.join("\n"));
    await context.close();
    await dav.dispose();
  }
});
