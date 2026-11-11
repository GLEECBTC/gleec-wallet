"""Read only the existing wallet-host route through the established CI account."""
import fnmatch
import json
import os
from pathlib import Path
import urllib.error
import urllib.request


def main():
    token = os.environ.pop("CLOUDFLARE_API_TOKEN")
    account = os.environ.pop("CLOUDFLARE_ACCOUNT_ID")

    def get(path):
        request = urllib.request.Request("https://api.cloudflare.com/client/v4/" + path,
                                         headers={"Authorization": "Bearer " + token})
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                value = json.load(response)
                return {"httpStatus": response.status, "success": value.get("success", False), "result": value.get("result")}
        except urllib.error.HTTPError as error:
            return {"httpStatus": error.code, "success": False}

    zones = get("zones?name=gleec.com&per_page=50")
    evidence = {"readOnly": True, "zoneReadStatus": zones["httpStatus"], "zoneAccessible": False}
    evidence["namedZoneCount"] = len([row for row in zones.get("result") or [] if row.get("name") == "gleec.com"])
    candidates = [row for row in zones.get("result") or [] if row.get("name") == "gleec.com" and row.get("account", {}).get("id") == account]
    if len(candidates) == 1:
        zone = candidates[0]["id"]
        evidence.update(zoneAccessible=True, zoneId=zone)
        dns = get(f"zones/{zone}/dns_records?name=dex.gleec.com&per_page=100")
        evidence["dnsReadStatus"] = dns["httpStatus"]
        evidence["records"] = [{key: row[key] for key in ("id", "type", "name", "content", "proxied", "ttl") if key in row}
                               for row in dns.get("result") or [] if row.get("name") == "dex.gleec.com" and row.get("type") in ("A", "AAAA", "CNAME")]
        routes = get(f"zones/{zone}/workers/routes")
        evidence["routesReadStatus"] = routes["httpStatus"]
        # Record all matching routes, including wildcard routes, for a reviewer
        # to resolve before any mutation. No unrelated route content is exported.
        evidence["walletRoutes"] = [{key: row[key] for key in ("id", "pattern", "script") if key in row}
                                    for row in routes.get("result") or [] if fnmatch.fnmatchcase("dex.gleec.com", row.get("pattern", "").split("://")[-1].split("/")[0])]
        settings = {}
        for name in ("ssl", "always_use_https", "min_tls_version", "automatic_https_rewrites"):
            result = get(f"zones/{zone}/settings/{name}")
            settings[name] = {"httpStatus": result["httpStatus"], "value": (result.get("result") or {}).get("value")}
        evidence["zoneSettings"] = settings
    Path("cloudflare-wallet-snapshot.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"readOnly": True, "zoneAccessible": evidence["zoneAccessible"], "zoneReadStatus": evidence["zoneReadStatus"]}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        raise SystemExit("Cloudflare read-only snapshot failed (" + type(error).__name__ + "); details suppressed") from None
