#!/usr/bin/env bash
# scripts/image-gen.sh — Shared Bild-Generierung fuer ALLE Bobs (Cloudflare Workers AI).
#
# Provider: Cloudflare Workers AI. Default-Modell @cf/black-forest-labs/flux-1-schnell
#   (4-Step, schnell, Apache-2.0 -> Output kommerziell nutzbar/lizenzfrei; Free-Tier ~170 Bilder/Tag).
#   Hoehere Qualitaet/PNG: GEN_MODEL=@cf/stabilityai/stable-diffusion-xl-base-1.0 (rohe PNG-Bytes).
# Creds (NIE im Repo): liegen im zentralen Secrets-Ordner $BOBNET_SECRETS als
#   cloudflare_account_id + cloudflare_api_token.
#
# Nutzung:  image-gen.sh "<prompt>" [outfile.jpg]      (Default-Outfile: image.jpg)
#   Env:    BOBNET_SECRETS=/abs/zum/secrets-dir   (optional, Default ~/.claude/.secrets)
#           GEN_MODEL=<cf-model>                            (optional, ueberschreibt Default)
# Exit:  0 ok · 2 Usage · 3 Creds fehlen · 4 keine Bilddaten in Response.
set -uo pipefail

prompt="${1:-}"; out="${2:-image.jpg}"
if [ "$prompt" = "--help" ] || [ -z "$prompt" ]; then sed -n '2,13p' "$0"; exit 2; fi

: "${BOBNET_SECRETS:=$HOME/.claude/.secrets}"
acct_f="$BOBNET_SECRETS/cloudflare_account_id"; tok_f="$BOBNET_SECRETS/cloudflare_api_token"
if [ ! -r "$acct_f" ] || [ ! -r "$tok_f" ]; then
  echo "image-gen: Creds fehlen in $BOBNET_SECRETS (cloudflare_account_id + cloudflare_api_token)" >&2; exit 3
fi
acct="$(cat "$acct_f")"; tok="$(cat "$tok_f")"
model="${GEN_MODEL:-@cf/black-forest-labs/flux-1-schnell}"
url="https://api.cloudflare.com/client/v4/accounts/$acct/ai/run/$model"

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -s -X POST "$url" \
  -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
  --data "$(python3 -c 'import json,sys; print(json.dumps({"prompt": sys.argv[1]}))' "$prompt")" \
  -o "$tmp"

python3 - "$tmp" "$out" <<'PY'
import json, base64, sys
resp_file, out = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(resp_file))
except Exception as e:
    sys.stderr.write("image-gen: Response nicht lesbar: %s\n" % e); sys.exit(4)
img = (d.get("result") or {}).get("image")
if not img:
    sys.stderr.write("image-gen: keine Bilddaten in Response: %s\n" % json.dumps(d)[:300]); sys.exit(4)
open(out, "wb").write(base64.b64decode(img))
print(out)
PY
