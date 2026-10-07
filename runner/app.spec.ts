import { test, expect, type Page, type Browser } from "@playwright/test";

// PLAN-app.md browser cases against the real remoteStorage app:
// AT2 OAuth consent, AT4 CORS from a page, AT12 unmodified remoteStorage.js.
const NC_URL = process.env.NC_URL ?? "http://nextcloud";
const ORIGIN_URL = process.env.ORIGIN_URL ?? "http://origin";
const NC_USER = process.env.NC_USER ?? "rstest";
const NC_PASS = process.env.NC_PASS ?? "rstest-pass";
const VARIANT = process.env.VARIANT ?? "unknown";
const STORAGE = `${NC_URL}/remote.php/dav/files/${NC_USER}/remoteStorage`;

test.skip(!VARIANT.startsWith("rsapp"), "rsapp variants only");
test.describe.configure({ mode: "serial" });

function oauthUrl(params: Record<string, string>): string {
  const query = new URLSearchParams({
    client_id: ORIGIN_URL,
    redirect_uri: `${ORIGIN_URL}/callback.html`,
    scope: "notes:rw",
    response_type: "token",
    ...params
  });
  return `${NC_URL}/index.php/apps/remotestorage/oauth?${query}`;
}

async function loginIfAsked(page: Page): Promise<void> {
  const user = page.locator("input#user, input[name='user']").first();
  if (await user.count()) {
    await user.fill(NC_USER);
    await page.locator("input#password, input[name='password']").first().fill(NC_PASS);
    await page.locator("button[type='submit'], input[type='submit']").first().click();
  }
}

// A brand-new user's first login shows Nextcloud's first-run wizard on top of
// whatever page comes next — here, the consent page. Close it like a person would.
// It opens a moment after the page loads, so call this once the consent page is up.
async function dismissFirstRunWizard(page: Page): Promise<void> {
  // Two elements carry id="firstrunwizard"; the dialog is the one with the role.
  const wizard = page.locator("[role='dialog']#firstrunwizard");
  try {
    await wizard.waitFor({ state: "visible", timeout: 8000 });
  } catch {
    return;
  }
  console.log("[wizard] first-run wizard shown over the consent page; skipping and closing it");
  // Escape does nothing; the intro animation needs "Skip", then the slides have "Close".
  const skip = wizard.getByRole("button", { name: "Skip" });
  if (await skip.count()) {
    await skip.click();
  }
  await page.locator("[role='dialog'] button[aria-label='Close']").first().click();
  await wizard.waitFor({ state: "hidden", timeout: 5000 });
}

function fragment(url: string): Record<string, string> {
  return Object.fromEntries(new URLSearchParams(new URL(url).hash.slice(1)));
}

async function fetchFromOrigin(page: Page, token: string, method: string, path: string, init: { body?: string; headers?: Record<string, string> } = {}) {
  return page.evaluate(async ({ url, token, method, init }) => {
    try {
      const res = await fetch(url, {
        method,
        body: init.body,
        headers: { Authorization: `Bearer ${token}`, ...(init.headers ?? {}) },
        credentials: "omit"
      });
      return { ok: true, status: res.status, etag: res.headers.get("ETag"), body: await res.text() };
    } catch (error) {
      return { ok: false, status: 0, etag: null, body: String(error) };
    }
  }, { url: `${STORAGE}/${path}`, token, method, init });
}

let token = "";
let consentBrowserContext: Awaited<ReturnType<Browser["newContext"]>> | null = null;

test("AT2a consent: allow returns a token in the redirect fragment", async ({ browser }) => {
  consentBrowserContext = await browser.newContext();
  const page = await consentBrowserContext.newPage();
  await page.goto(oauthUrl({ state: "s-allow" }));
  await loginIfAsked(page);
  await page.locator("#remotestorage-allow").waitFor({ timeout: 20000 });
  await dismissFirstRunWizard(page);
  const consentText = await page.locator(".remotestorage-authorize").innerText();
  await page.click("#remotestorage-allow");
  await page.waitForURL(`${ORIGIN_URL}/callback.html**`, { timeout: 20000 });
  const params = fragment(page.url());
  token = params.access_token ?? "";
  console.log(`[AT2a] consent page names origin+scope: ${consentText.includes(ORIGIN_URL) && consentText.includes("notes")}; fragment keys: ${Object.keys(params).join(",")}; state=${params.state}; token_type=${params.token_type}`);
  expect(consentText).toContain(ORIGIN_URL);
  expect(token).toMatch(/^rs_[A-Za-z0-9]{43}$/);
  expect(params.state).toBe("s-allow");
  expect(params.token_type).toBe("bearer");
});

test("AT4 CORS: the page can PUT, list, read ETags, see 412 and DELETE with the token", async () => {
  const page = await consentBrowserContext!.newPage();
  await page.goto(`${ORIGIN_URL}/callback.html`);
  const put = await fetchFromOrigin(page, token, "PUT", "notes/at4/hello.txt", { body: "hi", headers: { "Content-Type": "text/plain" } });
  const get = await fetchFromOrigin(page, token, "GET", "notes/at4/hello.txt");
  const list = await fetchFromOrigin(page, token, "GET", "notes/at4/");
  const stale = await fetchFromOrigin(page, token, "PUT", "notes/at4/hello.txt", { body: "x", headers: { "If-Match": '"stale"' } });
  const del = await fetchFromOrigin(page, token, "DELETE", "notes/at4/hello.txt");
  const summary = { put: [put.status, put.etag], get: [get.status, get.etag, get.body], list: [list.status, list.etag], stale: stale.status, del: del.status };
  console.log(`[AT4] ${JSON.stringify(summary)}`);
  expect(put.status).toBe(201);
  expect(put.etag).toBeTruthy();
  expect(get.etag).toBe(put.etag);
  expect(get.body).toBe("hi");
  expect(list.status).toBe(200);
  expect(JSON.parse(list.body).items["hello.txt"].ETag).toBe(put.etag!.replace(/"/g, ""));
  expect(list.etag).toBeTruthy();
  expect(stale.status).toBe(412);
  expect(del.status).toBe(200);
  await page.close();
});

test("AT2b consent: deny returns access_denied", async ({ browser }) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(oauthUrl({ state: "s-deny" }));
  await loginIfAsked(page);
  await page.locator("#remotestorage-deny").waitFor({ timeout: 20000 });
  await dismissFirstRunWizard(page);
  await page.click("#remotestorage-deny");
  await page.waitForURL(`${ORIGIN_URL}/callback.html**`, { timeout: 20000 });
  const params = fragment(page.url());
  console.log(`[AT2b] ${JSON.stringify(params)}`);
  expect(params).toEqual({ error: "access_denied", state: "s-deny" });
  await context.close();
});

test("AT2c consent: a client_id that is not the redirect origin gets an error page, no redirect", async ({ browser }) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(oauthUrl({ client_id: "http://evil.example", state: "s-bad" }));
  await loginIfAsked(page);
  const response = await page.waitForResponse((r) => r.url().includes("/apps/remotestorage/oauth"), { timeout: 20000 }).catch(() => null);
  await page.waitForLoadState("domcontentloaded");
  const text = await page.locator("body").innerText();
  console.log(`[AT2c] url=${page.url()} status=${response?.status()} invalid=${/invalid/i.test(text)}`);
  expect(page.url().startsWith(NC_URL)).toBe(true);
  expect(text).toMatch(/invalid/i);
  expect(await page.locator("#remotestorage-allow").count()).toBe(0);
  await context.close();
});

test("AT2d settings: the token is listed and Disconnect revokes it", async () => {
  const page = await consentBrowserContext!.newPage();
  await page.goto(`${NC_URL}/index.php/settings/user/security`);
  const row = page.locator(`#remotestorage-tokens tr[data-client="${ORIGIN_URL}"]`).first();
  await row.waitFor({ timeout: 20000 });
  const listed = await row.innerText();
  const address = await page.locator("#remotestorage code").first().innerText();
  await row.locator(".remotestorage-revoke").click();
  await page.waitForLoadState("domcontentloaded");
  const remaining = await page.locator(`#remotestorage-tokens tr[data-client="${ORIGIN_URL}"]`).count();
  const origin = await consentBrowserContext!.newPage();
  await origin.goto(`${ORIGIN_URL}/callback.html`);
  const after = await fetchFromOrigin(origin, token, "GET", "notes/");
  console.log(`[AT2d] address=${address} listed=${JSON.stringify(listed.replace(/\s+/g, " "))} remaining=${remaining} after-revoke=${after.status}`);
  expect(address).toBe(`${NC_USER}@nextcloud`);
  expect(listed).toContain("notes:rw");
  expect(remaining).toBe(0);
  expect(after.status).toBe(401);
  await consentBrowserContext!.close();
});

// One "device": a fresh browser context running the rs-app page, connected
// through WebFinger, Nextcloud's login and the consent page.
async function connectDevice(browser: Browser): Promise<{ page: Page; connected: boolean; close: () => Promise<void> }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(`${ORIGIN_URL}/rs-app.html`);
  await page.evaluate((address) => { (window as any).rs.connect(address); }, `${NC_USER}@nextcloud`);
  await page.waitForURL(`${NC_URL}/**`, { timeout: 20000 });
  await loginIfAsked(page);
  await page.locator("#remotestorage-allow").waitFor({ timeout: 20000 });
  await dismissFirstRunWizard(page);
  await page.click("#remotestorage-allow");
  await page.waitForURL(`${ORIGIN_URL}/rs-app.html**`, { timeout: 20000 });
  const connected = await page.evaluate(() => Promise.race([
    (window as any).rsConnected,
    new Promise((resolve) => setTimeout(() => resolve(false), 15000))
  ])) as boolean;
  return { page, connected, close: () => context.close() };
}

test("AT12 unmodified remoteStorage.js: two devices connect, sync nested data, edit after a (compressed) read, delete", async ({ browser, playwright }) => {
  const dav = await playwright.request.newContext({ httpCredentials: { username: NC_USER, password: NC_PASS } });
  const readDav = async (path: string) => {
    const res = await dav.get(`${STORAGE}/${path}`);
    return res.ok() ? res.text() : `HTTP ${res.status()}`;
  };

  // Device A writes into a folder that does not exist yet.
  const a = await connectDevice(browser);
  const first = `at12 ${Date.now()}`;
  if (a.connected) {
    await a.page.evaluate(async (text) => {
      await (window as any).rs.scope("/notes/").storeFile("text/plain", "deep/a/b.txt", text);
      await (window as any).rsSync();
    }, first);
  }
  const afterA = await readDav("notes/deep/a/b.txt");
  await a.close();

  // Device B syncs it down (a GET the browser asks to be compressed), edits it
  // (a PUT with If-Match from that GET), then deletes it.
  const b = await connectDevice(browser);
  const second = `${first} edited on device B`;
  const onB = b.connected ? await b.page.evaluate(async (text) => {
    const rs = (window as any).rs;
    const conflicts: unknown[] = [];
    rs.scope("/notes/").on("change", (e: any) => { if (e.origin === "conflict") conflicts.push(e.relativePath); });
    await (window as any).rsSync();
    const read = await rs.scope("/notes/").getFile("deep/a/b.txt");
    await rs.scope("/notes/").storeFile("text/plain", "deep/a/b.txt", text);
    await (window as any).rsSync();
    return { read: read?.data, conflicts, errors: (window as any).rsErrors };
  }, second) : null;
  const afterB = await readDav("notes/deep/a/b.txt");
  if (b.connected) {
    await b.page.evaluate(async () => {
      await (window as any).rs.scope("/notes/").remove("deep/a/b.txt");
      await (window as any).rsSync();
    });
  }
  // The document is gone; its emptied parents stay on disk (the app does not prune
  // them, to avoid racing a concurrent PUT) and listings hide them.
  const deleted = await dav.fetch(`${STORAGE}/notes/deep/a/b.txt`, { method: "PROPFIND", headers: { Depth: "0" } });
  await b.close();

  console.log(`[AT12] A connected=${a.connected} webdav-after-A=${JSON.stringify(afterA)}; B connected=${b.connected} B=${JSON.stringify(onB)} webdav-after-B=${JSON.stringify(afterB)}; document-after-delete=${deleted.status()}`);
  expect(a.connected).toBe(true);
  expect(afterA).toBe(first);
  expect(b.connected).toBe(true);
  expect(onB?.read).toBe(first);
  expect(onB?.conflicts).toEqual([]);
  expect(afterB).toBe(second);
  expect(deleted.status()).toBe(404);
  await dav.dispose();
});
