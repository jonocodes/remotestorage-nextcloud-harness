import { test } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

type Status = "pass" | "fail" | "error";

interface ProbeResponse {
  ok: boolean;
  status?: number;
  statusText?: string;
  headers?: Record<string, string>;
  body?: string;
  error?: string;
  name?: string;
}

interface ProbeResult {
  id: string;
  variant: string;
  nextcloud_version: string;
  status: Status;
  expected: string;
  observed: string;
  evidence: unknown;
}

interface StartFlow {
  ok: boolean;
  status?: number;
  body?: string;
  error?: string;
}

interface PollOutcome {
  ok: boolean;
  body: string;
  last?: unknown;
}

declare global {
  interface Window {
    __PROBE_CONFIG__: { ncUrl: string; user: string; pass: string };
    probe: {
      config(): { ncUrl: string; user: string; pass: string };
      url(path: string): string;
      dav(relative: string): string;
      req(
        method: string,
        target: string,
        options?: { headers?: Record<string, string>; body?: string }
      ): Promise<ProbeResponse>;
    };
  }
}

const NC_URL = process.env.NC_URL ?? "http://nextcloud";
const ORIGIN_URL = process.env.ORIGIN_URL ?? "http://localhost";
const NC_USER = process.env.NC_USER ?? "rstest";
const NC_PASS = process.env.NC_PASS ?? "rstest-pass";
const VARIANT = process.env.VARIANT ?? "unknown";
const NC_VERSION = process.env.NC_VERSION ?? "unknown";
const RESULTS_DIR = process.env.RESULTS_DIR ?? "/harness/results";

const results: ProbeResult[] = [];

function record(entry: Omit<ProbeResult, "variant" | "nextcloud_version">): void {
  const full = { ...entry, variant: VARIANT, nextcloud_version: NC_VERSION };
  results.push(full);
  console.log(`[${full.id}] ${full.status}: ${full.observed}`);
}

async function withResult(
  id: string,
  expected: string,
  run: () => Promise<{ status: Status; observed: string; evidence?: unknown }>
): Promise<void> {
  try {
    const outcome = await run();
    record({
      id,
      status: outcome.status,
      expected,
      observed: outcome.observed,
      evidence: outcome.evidence ?? null
    });
  } catch (error) {
    record({
      id,
      status: "error",
      expected,
      observed: `harness error: ${String(error)}`,
      evidence: { error: String(error) }
    });
  }
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(
    (config) => {
      window.__PROBE_CONFIG__ = config;
    },
    { ncUrl: NC_URL, user: NC_USER, pass: NC_PASS }
  );
});

test("T11 PROPFIND with Basic auth from another origin", async ({ page }) => {
  await withResult("T11", "PROPFIND succeeds and the response is readable", async () => {
    await page.goto(`${ORIGIN_URL}/probe.html`);
    const control = await page.evaluate(async () => {
      try {
        const res = await fetch(
          `${window.probe.config().ncUrl.replace(/\/+$/, "")}/status.php`,
          { credentials: "omit" }
        );
        return { ok: true, status: res.status };
      } catch (error) {
        return { ok: false, error: String(error) };
      }
    });
    const response = await page.evaluate(() =>
      window.probe.req("PROPFIND", window.probe.dav(""), { headers: { Depth: "1" } })
    );
    if (!response.ok) {
      if (!control.ok || control.status !== 200) {
        return {
          status: "error",
          observed: `PROPFIND fetch failed and the control GET also failed: ${response.error}; control=${JSON.stringify(control)}`,
          evidence: { control, response }
        };
      }
      return {
        status: "fail",
        observed: `fetch failed: ${response.error} (control GET succeeded, so the page reaches Nextcloud)`,
        evidence: { control, response }
      };
    }
    const passed = response.status === 207 && (response.body ?? "").includes("multistatus");
    return {
      status: passed ? "pass" : "fail",
      observed: `HTTP ${response.status}${passed ? "" : " (expected 207 multistatus)"}`,
      evidence: {
        control,
        status: response.status,
        headers: response.headers,
        body: (response.body ?? "").slice(0, 500)
      }
    };
  });
});

test("T12 PUT, GET, DELETE and readable ETag headers", async ({ page }) => {
  await withResult(
    "T12",
    "PUT/GET/DELETE succeed and response.headers.get('ETag') is non-null on PUT and GET (plan T12, amended 2026-10-02)",
    async () => {
      await page.goto(`${ORIGIN_URL}/probe.html`);
      const put = await page.evaluate(() =>
        window.probe.req("PUT", window.probe.dav("t12.txt"), {
          headers: { "Content-Type": "text/plain" },
          body: "t12"
        })
      );
      const get = await page.evaluate(() =>
        window.probe.req("GET", window.probe.dav("t12.txt"))
      );
      const del = await page.evaluate(() =>
        window.probe.req("DELETE", window.probe.dav("t12.txt"))
      );

      const etags = {
        put: put.headers?.etag ?? null,
        get: get.headers?.etag ?? null,
        delete: del.headers?.etag ?? null
      };
      const failures: string[] = [];
      if (!put.ok || (put.status !== 201 && put.status !== 204)) {
        failures.push(`PUT ${put.ok ? put.status : put.error}`);
      }
      if (!get.ok || get.status !== 200) {
        failures.push(`GET ${get.ok ? get.status : get.error}`);
      }
      if (!del.ok || (del.status !== 204 && del.status !== 200)) {
        failures.push(`DELETE ${del.ok ? del.status : del.error}`);
      }
      if (!etags.put) {
        failures.push("PUT response did not expose ETag");
      }
      if (!etags.get) {
        failures.push("GET response did not expose ETag");
      }

      return {
        status: failures.length === 0 ? "pass" : "fail",
        observed:
          failures.length === 0
            ? `PUT/GET/DELETE succeeded; ETag visible on PUT ${etags.put} and GET ${etags.get}; DELETE ETag ${etags.delete ?? "not sent"}`
            : failures.join("; "),
        evidence: {
          statuses: { put: put.status, get: get.status, delete: del.status },
          etags,
          errors: { put: put.error, get: get.error, delete: del.error }
        }
      };
    }
  );
});

test("T13 conditional PUT failure visible to the page", async ({ page }) => {
  await withResult(
    "T13",
    'stale If-Match PUT returns 412 to the page and does not write',
    async () => {
      await page.goto(`${ORIGIN_URL}/probe.html`);
      await page.evaluate(() =>
        window.probe.req("PUT", window.probe.dav("t13.txt"), { body: "original" })
      );
      const stale = await page.evaluate(() =>
        window.probe.req("PUT", window.probe.dav("t13.txt"), {
          headers: { "If-Match": '"stale"' },
          body: "stale"
        })
      );
      const readBack = await page.evaluate(() =>
        window.probe.req("GET", window.probe.dav("t13.txt"))
      );

      if (!stale.ok) {
        return {
          status: "fail",
          observed: `fetch failed instead of returning 412: ${stale.error}`,
          evidence: stale
        };
      }

      const passed = stale.status === 412 && readBack.body === "original";
      return {
        status: passed ? "pass" : "fail",
        observed: passed
          ? "412 visible to the page and content unchanged"
          : `stale PUT returned ${stale.status}; content now '${readBack.body}'`,
        evidence: {
          staleStatus: stale.status,
          staleHeaders: stale.headers,
          readBackStatus: readBack.status,
          readBackBody: readBack.body
        }
      };
    }
  );
});

test("T14 login flow v2 from the browser", async ({ page, context }) => {
  await withResult(
    "T14",
    "browser obtains server/loginName/appPassword via login flow v2 and the app password works",
    async () => {
      await page.goto(`${ORIGIN_URL}/probe.html`);

      const start = await page.evaluate<StartFlow>(async () => {
        try {
          const response = await fetch(
            `${window.probe.config().ncUrl.replace(/\/+$/, "")}/index.php/login/v2`,
            {
              method: "POST",
              headers: { "OCS-APIRequest": "true" },
              credentials: "omit"
            }
          );
          return { ok: true, status: response.status, body: (await response.text()).slice(0, 4000) };
        } catch (error) {
          return { ok: false, error: String(error) };
        }
      });

      if (!start.ok) {
        return {
          status: "fail",
          observed: `POST /index.php/login/v2 failed in the browser: ${start.error}`,
          evidence: start
        };
      }

      let flow: { login?: string; poll?: { token?: string; endpoint?: string } };
      try {
        flow = JSON.parse(start.body ?? "");
      } catch {
        return {
          status: "fail",
          observed: "POST /index.php/login/v2 did not return JSON",
          evidence: { status: start.status, body: start.body }
        };
      }
      if (!flow.login || !flow.poll?.token || !flow.poll?.endpoint) {
        return {
          status: "fail",
          observed: "login flow response is missing login/poll fields",
          evidence: flow
        };
      }

      const loginPage = await context.newPage();
      try {
        await loginPage.goto(flow.login, { waitUntil: "domcontentloaded" });
        const userField = loginPage.locator("input#user, input[name='user']").first();
        if (await userField.count()) {
          await userField.fill(NC_USER);
          await loginPage.locator("input#password, input[name='password']").first().fill(NC_PASS);
          await loginPage.locator("button[type='submit'], input[type='submit']").first().click();
        }
        const grant = loginPage.getByRole("button", { name: /grant access|authorize/i }).first();
        await grant.waitFor({ state: "visible", timeout: 20000 });
        await grant.click();
      } catch (error) {
        return {
          status: "error",
          observed: `could not automate login/grant: ${String(error)}`,
          evidence: { loginUrl: flow.login }
        };
      } finally {
        await loginPage.close();
      }

      const polled = await page.evaluate<PollOutcome, { endpoint: string; token: string }>(
        async ({ endpoint, token }) => {
          const deadline = Date.now() + 30000;
          let last: unknown = null;
          while (Date.now() < deadline) {
            try {
              const response = await fetch(endpoint, {
                method: "POST",
                headers: { "Content-Type": "application/x-www-form-urlencoded" },
                body: new URLSearchParams({ token }).toString(),
                credentials: "omit"
              });
              const body = await response.text();
              last = { status: response.status, body: body.slice(0, 1000) };
              if (response.status === 200) {
                return { ok: true, body };
              }
            } catch (error) {
              last = { error: String(error) };
            }
            await new Promise((resolve) => setTimeout(resolve, 1000));
          }
          return { ok: false, body: "", last };
        },
        { endpoint: flow.poll.endpoint, token: flow.poll.token }
      );

      if (!polled.ok) {
        return {
          status: "fail",
          observed: `polling ${flow.poll.endpoint} never returned 200 (last: ${JSON.stringify(polled.last)})`,
          evidence: { poll: polled.last }
        };
      }

      const credentials = JSON.parse(polled.body);
      const verify = await page.evaluate<
        { ok: boolean; status?: number; error?: string },
        string
      >(async (appPassword) => {
        try {
          const response = await fetch(window.probe.dav(""), {
            method: "PROPFIND",
            headers: {
              Authorization: `Basic ${btoa(`${window.probe.config().user}:${appPassword}`)}`,
              Depth: "0"
            },
            credentials: "omit"
          });
          return { ok: true, status: response.status };
        } catch (error) {
          return { ok: false, error: String(error) };
        }
      }, credentials.appPassword);

      const passed =
        Boolean(credentials.server && credentials.loginName && credentials.appPassword) &&
        verify.ok &&
        verify.status === 207;

      return {
        status: passed ? "pass" : "fail",
        observed: `server=${credentials.server} loginName=${credentials.loginName} appPassword=${
          credentials.appPassword ? `received(${credentials.appPassword.length} chars)` : "missing"
        } verify=${JSON.stringify(verify)}`,
        evidence: {
          server: credentials.server,
          loginName: credentials.loginName,
          appPassword: credentials.appPassword ? "<redacted>" : null,
          verify
        }
      };
    }
  );
});

interface WapMessage {
  origin: string;
  data: { type?: string; loginName?: string; token?: string; webdavUrl?: string };
}

const WAP_PATH = "/index.php/apps/webapppassword/";
const FOREIGN_ORIGIN = "http://evil.example";

test("T15 WebAppPassword connect flow from the browser", async ({ page }) => {
  await withResult(
    "T15",
    "popup to /apps/webapppassword/?target-origin=<origin> posts {loginName, token, webdavUrl} back to the opener; the token works for a cross-origin PROPFIND; a foreign target-origin is refused",
    async () => {
      await page.goto(`${ORIGIN_URL}/probe.html`);
      await page.evaluate(
        ({ ncUrl, wapPath, origin }) => {
          const store = window as unknown as { __wap: unknown[] };
          store.__wap = [];
          window.addEventListener("message", (event) => {
            store.__wap.push({ origin: event.origin, data: event.data });
          });
          const button = document.createElement("button");
          button.id = "connect";
          button.textContent = "Connect";
          button.onclick = () => {
            window.open(
              `${ncUrl.replace(/\/+$/, "")}${wapPath}?target-origin=${encodeURIComponent(origin)}`,
              "wap",
              "width=500,height=600"
            );
          };
          document.body.appendChild(button);
        },
        { ncUrl: NC_URL, wapPath: WAP_PATH, origin: ORIGIN_URL }
      );

      // A real click, so the popup is user-initiated as it would be in an app.
      const popupPromise = page.waitForEvent("popup");
      await page.click("#connect");
      const popup = await popupPromise;
      await popup.waitForLoadState("domcontentloaded");
      const landing = { url: popup.url() };

      const userField = popup.locator("input#user, input[name='user']").first();
      if (await userField.count()) {
        await userField.fill(NC_USER);
        await popup.locator("input#password, input[name='password']").first().fill(NC_PASS);
        await popup.locator("button[type='submit'], input[type='submit']").first().click();
      }

      const received = await page
        .waitForFunction(
          () => ((window as unknown as { __wap: unknown[] }).__wap ?? []).length > 0,
          null,
          { timeout: 30000 }
        )
        .then(() => page.evaluate(() => (window as unknown as { __wap: WapMessage[] }).__wap[0]))
        .catch(() => null);

      const popupState = popup.isClosed()
        ? { closed: true }
        : {
            closed: false,
            url: popup.url(),
            text: (await popup.locator("body").innerText().catch(() => "")).slice(0, 300)
          };

      if (!received) {
        await popup.close().catch(() => undefined);
        return {
          status: "fail",
          observed: `no postMessage reached the opener within 30 s (popup: ${JSON.stringify(popupState)})`,
          evidence: { landing, popup: popupState }
        };
      }

      const message = received.data ?? {};
      const credentialsOk =
        message.type === "webapppassword" &&
        Boolean(message.loginName && message.token && message.webdavUrl);

      const verify = await page.evaluate(
        async ({ loginName, token }) => {
          try {
            const response = await fetch(window.probe.dav(""), {
              method: "PROPFIND",
              headers: { Authorization: `Basic ${btoa(`${loginName}:${token}`)}`, Depth: "0" },
              credentials: "omit"
            });
            return { ok: true, status: response.status };
          } catch (error) {
            return { ok: false, error: String(error) };
          }
        },
        { loginName: message.loginName ?? "", token: message.token ?? "" }
      );

      // Same logged-in popup session, but a target-origin that is not on the allow-list.
      const foreign: { status: number | null; postsMessage: boolean } = { status: null, postsMessage: false };
      if (!popup.isClosed()) {
        const response = await popup.goto(
          `${NC_URL}${WAP_PATH}?target-origin=${encodeURIComponent(FOREIGN_ORIGIN)}`
        );
        const html = response ? await response.text() : "";
        foreign.status = response ? response.status() : null;
        foreign.postsMessage = /webapppassword\/js\/script/.test(html);
        await popup.close();
      }

      const ncOrigin = new URL(NC_URL).origin;
      const failures: string[] = [];
      if (received.origin !== ncOrigin) {
        failures.push(`message origin ${received.origin} (expected ${ncOrigin})`);
      }
      if (!credentialsOk) {
        failures.push("message missing type/loginName/token/webdavUrl");
      }
      if (!verify.ok || verify.status !== 207) {
        failures.push(`token PROPFIND ${verify.ok ? verify.status : verify.error}`);
      }
      if (foreign.status !== 403 || foreign.postsMessage) {
        failures.push(
          `foreign target-origin not refused (HTTP ${foreign.status}, script=${foreign.postsMessage})`
        );
      }

      return {
        status: failures.length === 0 ? "pass" : "fail",
        observed:
          failures.length === 0
            ? `opener received loginName=${message.loginName} token(${message.token?.length} chars) webdavUrl=${message.webdavUrl}; token PROPFIND 207; foreign origin refused with 403`
            : failures.join("; "),
        evidence: {
          landing,
          messageOrigin: received.origin,
          message: {
            type: message.type,
            loginName: message.loginName,
            token: message.token ? `<redacted ${message.token.length} chars>` : null,
            webdavUrl: message.webdavUrl
          },
          verify,
          foreign
        }
      };
    }
  );
});

test.afterAll(() => {
  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  const file = path.join(RESULTS_DIR, `${NC_VERSION}-${VARIANT}-browser.json`);
  fs.writeFileSync(file, `${JSON.stringify(results, null, 2)}\n`);
  console.log(`browser probes written to ${file}`);
});
