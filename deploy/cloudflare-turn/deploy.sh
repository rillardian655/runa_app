#!/usr/bin/env bash
###############################################################################
# Deploy the Cloudflare-TURN credential function to the self-hosted Supabase
# stack. Cloudflare's anycast TURN servers do the UDP relay, so this works even
# though our VPS sits behind a UDP-less NAT.
#
# Run as root ON THE VPS (token stays on the server — never paste it in chat):
#
#   TURN_KEY_ID=<key-id> TURN_API_TOKEN=<api-token> bash deploy.sh
#
# Get those two from: dash.cloudflare.com -> Realtime -> TURN -> Create.
# Optional: SUPABASE_DOCKER_DIR=/path/to/supabase/docker (default below).
###############################################################################
set -euo pipefail

DIR="${SUPABASE_DOCKER_DIR:-/root/supabase/docker}"
: "${TURN_KEY_ID:?set TURN_KEY_ID=... (Cloudflare TURN key id)}"
: "${TURN_API_TOKEN:?set TURN_API_TOKEN=... (Cloudflare TURN API token)}"

cd "$DIR"
COMPOSE=docker-compose.yml
FN_DIR=volumes/functions/turn-credentials
install -d "$FN_DIR"

echo "==> Writing $FN_DIR/index.ts (Cloudflare TURN proxy)…"
cat > "$FN_DIR/index.ts" <<'TSEOF'
// Ru.na — short-lived TURN credentials via Cloudflare Realtime TURN.
//
// The app calls this function per call; we proxy to Cloudflare so the TURN API
// token NEVER ships inside the APK. Cloudflare mints credentials that expire on
// their own (24h), and its anycast TURN servers handle the UDP relay (our VPS is
// behind a UDP-less NAT, so self-hosted coturn can't relay through it).
//
// Server env (set in the self-hosted stack's .env + functions compose service):
//   TURN_KEY_ID     — Cloudflare TURN key id     (dash.cloudflare.com → Realtime → TURN)
//   TURN_API_TOKEN  — Cloudflare TURN API token   (shown once when the key is created)
//
// JWT verification is handled by the gateway; supabase.functions.invoke()
// attaches the user's access token automatically.

const TTL_SECONDS = 86_400; // creds valid for 24h

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const keyId = Deno.env.get("TURN_KEY_ID");
  const apiToken = Deno.env.get("TURN_API_TOKEN");
  if (!keyId || !apiToken) {
    return json({ error: "Cloudflare TURN is not configured" }, 500);
  }

  let cf: Response;
  try {
    cf = await fetch(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${keyId}/credentials/generate-ice-servers`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${apiToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ ttl: TTL_SECONDS }),
      },
    );
  } catch (e) {
    return json({ error: "Could not reach Cloudflare TURN", detail: String(e) }, 502);
  }

  if (!cf.ok) {
    const detail = (await cf.text()).slice(0, 300);
    return json({ error: "Cloudflare TURN request failed", status: cf.status, detail }, 502);
  }

  // Cloudflare returns: { iceServers: [ {urls:[stun...]}, {urls:[turn...], username, credential} ] }
  // Flatten to the {username, credential, urls[]} shape the app already parses.
  const data = await cf.json();
  const list = (data?.iceServers ?? []) as Array<
    { urls?: string | string[]; username?: string; credential?: string }
  >;

  let username = "";
  let credential = "";
  const urls: string[] = [];
  for (const s of list) {
    const u = Array.isArray(s.urls) ? s.urls : s.urls ? [s.urls] : [];
    urls.push(...u);
    if (s.username) username = s.username;
    if (s.credential) credential = s.credential;
  }

  if (urls.length === 0) {
    return json({ error: "Cloudflare TURN returned no ICE servers" }, 502);
  }

  return json({ username, credential, ttl: TTL_SECONDS, urls });
});
TSEOF

echo "==> Updating .env (set TURN_KEY_ID / TURN_API_TOKEN, drop old TURN_SECRET)…"
touch .env
upsert() { local k="$1" v="$2"; sed -i "/^${k}=/d" .env; printf '%s=%s\n' "$k" "$v" >> .env; }
sed -i '/^TURN_SECRET=/d' .env
upsert TURN_KEY_ID    "$TURN_KEY_ID"
upsert TURN_API_TOKEN "$TURN_API_TOKEN"

echo "==> Wiring vars into the functions service in $COMPOSE…"
# remove the old coturn secret line if present
sed -i '/^      TURN_SECRET: ${TURN_SECRET}$/d' "$COMPOSE"
add_env() {
  local k="$1"
  grep -qF "      ${k}: \${${k}}" "$COMPOSE" || \
    sed -i "/^      VERIFY_JWT: /a\\      ${k}: \${${k}}" "$COMPOSE"
}
add_env TURN_KEY_ID
add_env TURN_API_TOKEN
docker compose config -q && echo "    compose config OK"

echo "==> Recreating the functions container…"
docker compose up -d --no-deps functions
st=none
for _ in $(seq 1 15); do
  st=$(docker inspect -f '{{.State.Health.Status}}' supabase-edge-functions 2>/dev/null || echo none)
  [ "$st" = healthy ] && break; sleep 2
done
echo "    functions health=$st"

echo "==> Testing turn-credentials via the local gateway…"
ANON="$(grep '^ANON_KEY=' .env | cut -d= -f2-)"
echo "    (expect http=200 and a JSON body with username/credential/urls)"
curl -s -w '\n    http=%{http_code}\n' \
  http://localhost:8000/functions/v1/turn-credentials \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON"

cat <<'NOTE'

Done. If http=200 with username/credential/urls -> Cloudflare TURN is live.

Optional cleanup (coturn is no longer used on this NAT'd box):
  systemctl disable --now coturn
  # and delete the turn.vantageos.my.id DNS record in Cloudflare if you like.
NOTE
