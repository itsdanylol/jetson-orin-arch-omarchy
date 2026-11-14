# Fix 010 — cloudflared, and the brain only listens on loopback

**Date:** 2026-11-14
**Layer:** pacman package + user systemd unit (+ an application-level change in the repo)
**Status:** held

## Symptom

No symptom yet — this is the fix applied *before* exposing the brain, because the
original posture was unsafe:

```
$ ss -ltn | grep 8787
LISTEN 0  511  *:8787  *:*          ← every interface, not loopback
$ grep MOROS_DEV ~/.moros/server/brain.env
MOROS_DEV=1                          ← a dev license is loaded
$ sudo nft list ruleset
                                     ← empty; iptables INPUT policy ACCEPT
$ grep -n "server.listen" ~/.moros/sdk/src/server.ts
311: server.listen(PORT, () => {      ← no host argument
```

`server/deploy/Caddyfile` documents the intent — *"the brain speaks plain HTTP on
127.0.0.1:8787"* — but the code bound `::`. Combined with an empty firewall and a live
dev key, anything on the LAN could reach the API and the hosted `/mcp`.

Separately, `/mcp` had **no authentication at all**:

```js
// Hosted MCP endpoint, no principal gate here
if (path === "/mcp") { await serveMcp(req, res); ... }
```

and identity elsewhere was a caller-asserted `x-moros-principal` header.

## Cause

Two independent gaps that only become dangerous together:

1. **Bind** — Node's `server.listen(PORT)` with no host binds all interfaces. The
   deploy docs assumed loopback; the code never implemented it.
2. **Auth** — the hosted MCP surface was written for a trusted-adjacent deployment and
   shipped with a TODO: *"OAuth 2.1 lands with the transport PR."* Until then nothing
   verified who was calling.

A Cloudflare Tunnel removes the need for a public listener entirely: `cloudflared`
dials out, so the brain can bind `127.0.0.1` and still be reachable from Base44.

## Fix

Three parts.

**1. The package** (aarch64 is fine — `extra` ships it):

```sh
sudo pacman -S --needed cloudflared
cloudflared --version    # 2026.10.7
```

**2. The application change** — `sdk/src/server.ts`:

- `MOROS_BIND` (default `127.0.0.1`), passed as `server.listen(PORT, BIND, ...)`.
- Bearer gate, fail-closed on edge traffic:

```ts
const API_TOKEN = process.env.MOROS_API_TOKEN ?? "";
const FORCE_TOKEN = process.env.MOROS_REQUIRE_TOKEN === "1";

function viaEdge(req) {
  return typeof req.headers["cf-ray"] === "string"
      || typeof req.headers["cf-connecting-ip"] === "string";
}

function tokenOk(req) {
  if (FORCE_TOKEN || viaEdge(req)) return tokenMatches(req);
  return true;                      // direct loopback: opencode, same box
}
```

`tokenMatches` returns false when no token is configured, so **a tunnel pointed at an
unconfigured brain gets a 401, not an open door**. Cost: `cloudflared` always stamps
those headers and the brain is loopback-bound, so a caller cannot strip them.

**3. The secrets** — `~/.moros/server/brain.env`, chmod 600:

```
MOROS_API_TOKEN=<32 random bytes, hex>
MOROS_BIND=127.0.0.1
```

The client (`sdk/src/licensing/api.ts`) forwards `MOROS_API_TOKEN` as
`Authorization: Bearer` when its own env has one, so the stdio MCP client works
against a gated brain without further configuration.

## Survives

- [x] `pacman -Syu` — cloudflared is a normal package; the unit lives in
      `~/.config/systemd/user/`, which no package owns
- [x] `omarchy update`
- [x] kernel bump
- [ ] nothing here is exempt

The application change is in the repo (`~/.moros/sdk/src/server.ts`), so it survives
by being rebuilt — `tsc` output in `build/` is derived, not authored.

## Verify

```sh
ss -ltn | grep 8787                 # must be 127.0.0.1:8787, never *:8787
curl -s http://127.0.0.1:8787/healthz          # {"ok":true}
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8787/mcp \
  -H 'cf-ray: verify' -H 'content-type: application/json' -d '{}'   # 401
```

All three are automated in `checks/verify.sh` under fix 010.

## Revert

```sh
sudo pacman -Rns cloudflared
systemctl --user disable --now cloudflared 2>/dev/null
```

To restore the old permissive posture (don't): delete `MOROS_API_TOKEN` and
`MOROS_BIND` from `brain.env`, and drop the gate from `server.ts`. Upstream would make
this unnecessary by shipping real MCP auth — `/mcp` session identity bound to a
verified token, which is still an open item.
