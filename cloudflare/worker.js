const latestVersion = "0.1.1";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/download") {
      const assetUrl = new URL(`/downloads/MailJay-${latestVersion}.dmg`, url.origin);
      const response = await env.ASSETS.fetch(new Request(assetUrl.toString(), request));
      const headers = new Headers(response.headers);
      headers.set("content-type", "application/x-apple-diskimage");
      headers.set("content-disposition", "attachment; filename=\"MailJay-latest.dmg\"");
      headers.set("cache-control", "no-store");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers
      });
    }

    if (url.pathname === "/downloads/MailJay-latest.dmg" || url.pathname === "/downloads/MailJay-latest.zip") {
      const extension = url.pathname.endsWith(".dmg") ? "dmg" : "zip";
      const contentType = extension === "dmg" ? "application/x-apple-diskimage" : "application/zip";
      const assetUrl = new URL(`/downloads/MailJay-${latestVersion}.${extension}`, url.origin);
      const response = await env.ASSETS.fetch(new Request(assetUrl.toString(), request));
      const headers = new Headers(response.headers);
      headers.set("content-type", contentType);
      headers.set("content-disposition", `attachment; filename="MailJay-latest.${extension}"`);
      headers.set("cache-control", "no-store");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers
      });
    }

    const response = await env.ASSETS.fetch(request);
    const headers = new Headers(response.headers);

    if (url.pathname.endsWith(".xml")) {
      headers.set("content-type", "application/xml; charset=utf-8");
      headers.set("cache-control", "public, max-age=300");
    } else if (url.pathname.endsWith(".zip")) {
      headers.set("content-type", "application/zip");
      headers.set("cache-control", "public, max-age=3600");
      headers.set("content-disposition", `attachment; filename="${url.pathname.split("/").pop()}"`);
    } else if (url.pathname.endsWith(".dmg")) {
      headers.set("content-type", "application/x-apple-diskimage");
      headers.set("cache-control", "public, max-age=3600");
      headers.set("content-disposition", `attachment; filename="${url.pathname.split("/").pop()}"`);
    } else {
      headers.set("cache-control", "public, max-age=0, must-revalidate");
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers
    });
  }
};
