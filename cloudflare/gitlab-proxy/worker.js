// Proxies gitlab.latha.org to the GitLab running on Modal.
const ORIGIN = "codegod100--gitlab-web.modal.run";
const REWRITE = /^(text\/html|application\/json|text\/plain|application\/javascript|text\/javascript)/;

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const publicHost = url.host;
    url.host = ORIGIN;
    url.protocol = "https:";
    url.port = "";

    const headers = new Headers(request.headers);
    headers.set("X-Forwarded-Host", publicHost);
    headers.set("X-Forwarded-Proto", "https");

    const resp = await fetch(url, {
      method: request.method,
      headers,
      body: request.body,
      redirect: "manual",
    });

    // WebSocket upgrades pass straight through.
    if (resp.status === 101) return resp;

    const out = new Headers(resp.headers);
    const loc = out.get("Location");
    if (loc) out.set("Location", loc.replaceAll(ORIGIN, publicHost));
    const cookies = resp.headers.getSetCookie?.() ?? [];
    if (cookies.length) {
      out.delete("Set-Cookie");
      for (const c of cookies) out.append("Set-Cookie", c.replace(/;\s*domain=[^;]*/i, ""));
    }

    // Until GitLab's external_url points at the public host, it renders absolute
    // URLs with the Modal hostname; rewrite those in text bodies.
    const type = out.get("Content-Type") || "";
    if (REWRITE.test(type) && resp.body) {
      const text = await resp.text();
      out.delete("Content-Length");
      return new Response(text.replaceAll(ORIGIN, publicHost), { status: resp.status, statusText: resp.statusText, headers: out });
    }
    return new Response(resp.body, { status: resp.status, statusText: resp.statusText, headers: out });
  },
};
