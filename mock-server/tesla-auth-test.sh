#!/usr/bin/env bash
#
# tesla-auth-test.sh — walk the whole Tesla Fleet API setup by hand.
#
# Same sequence the app performs, but printing Tesla's raw answer at
# every step, so a failure names itself instead of surfacing as an
# opaque dialog. No Xcode, no build.
#
#   ./tesla-auth-test.sh check      # config sanity, no credentials needed
#   ./tesla-auth-test.sh token      # partner token (machine-to-machine)
#   ./tesla-auth-test.sh register   # register partner account, both regions
#   ./tesla-auth-test.sh login      # full browser sign-in → real vehicle data
#   ./tesla-auth-test.sh all        # token → register → login
#
# Credentials come from the environment or a .env file beside this
# script (gitignored — never commit it):
#
#   TESLA_CLIENT_ID=...
#   TESLA_CLIENT_SECRET=...
#   TESLA_KEY_DOMAIN=tesla-xxxx.weareheavy.dev
#
set -uo pipefail

AUTH_HOST="https://auth.tesla.com"
TOKEN_HOST="https://fleet-auth.prd.vn.cloud.tesla.com"
NA="https://fleet-api.prd.na.vn.cloud.tesla.com"
EU="https://fleet-api.prd.eu.vn.cloud.tesla.com"
REDIRECT="http://localhost:8973/callback"
SCOPES="openid offline_access vehicle_device_data"
WELL_KNOWN=".well-known/appspecific/com.tesla.3p.public-key.pem"

cd "$(dirname "$0")"
[ -f .env ] && . ./.env

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }

# Pretty-print JSON when python is available, else raw.
show() { python3 -m json.tool 2>/dev/null || cat; }

need_creds() {
  : "${TESLA_CLIENT_ID:?set TESLA_CLIENT_ID (env or .env)}"
  : "${TESLA_CLIENT_SECRET:?set TESLA_CLIENT_SECRET (env or .env)}"
}

# ---------------------------------------------------------------- check

cmd_check() {
  bold "1. Client ID format"
  if [ -z "${TESLA_CLIENT_ID:-}" ]; then
    bad "TESLA_CLIENT_ID not set"
  elif [ ${#TESLA_CLIENT_ID} -eq 36 ]; then
    ok "36 characters"
  else
    bad "${#TESLA_CLIENT_ID} characters — a Tesla client ID is 36 (8-4-4-4-12)"
    info "a paste that dropped a character fails later as 'client_not_found'"
  fi

  bold "2. Public key reachable where Tesla looks"
  if [ -z "${TESLA_KEY_DOMAIN:-}" ]; then
    bad "TESLA_KEY_DOMAIN not set"
  else
    local url="https://$TESLA_KEY_DOMAIN/$WELL_KNOWN"
    local code; code=$(curl -s -o /tmp/tat-key.pem -w '%{http_code}' --max-time 20 "$url")
    if [ "$code" = 200 ] && grep -q 'BEGIN PUBLIC KEY' /tmp/tat-key.pem; then
      ok "$url"
      if command -v openssl >/dev/null && openssl ec -pubin -in /tmp/tat-key.pem -noout 2>/dev/null; then
        ok "parses as an EC public key"
      fi
    else
      bad "HTTP $code at $url"
    fi
  fi

  bold "3. Authorize URL accepted"
  local au="$AUTH_HOST/oauth2/v3/authorize?client_id=${TESLA_CLIENT_ID:-none}&redirect_uri=$(printf %s "$REDIRECT" | sed 's|:|%3A|g;s|/|%2F|g')&response_type=code&scope=$(printf %s "$SCOPES" | sed 's/ /%20/g')&state=probe"
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
    -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15' "$au")
  [ "$code" = 200 ] && ok "Tesla serves the login page (HTTP 200)" \
                    || bad "HTTP $code — client_id or redirect_uri rejected outright"
  info "note: 'No policy rules' renders inside the page and cannot be seen here"

  bold "4. Port 8973 free for the callback"
  if command -v lsof >/dev/null && lsof -i :8973 >/dev/null 2>&1; then
    bad "in use — quit every running Teslaris:"
    lsof -i :8973 | sed 's/^/      /'
  else
    ok "free"
  fi
}

# ---------------------------------------------------------------- token

# Partner token. No `audience`: an app can be registered with an audience
# no request matches, and Tesla then rejects any explicit value.
partner_token() {
  curl -s --max-time 30 -X POST "$TOKEN_HOST/oauth2/v3/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_id=$TESLA_CLIENT_ID" \
    --data-urlencode "client_secret=$TESLA_CLIENT_SECRET" \
    --data-urlencode "scope=openid vehicle_device_data"
}

cmd_token() {
  need_creds
  bold "Partner token (machine-to-machine)"
  local body; body=$(partner_token)
  local token; token=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
  if [ -n "$token" ]; then
    ok "issued (${#token} chars)"
    # aud shows which regions Tesla considers this app registered for —
    # the field that explains most audience errors.
    printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+' \
      | python3 -c '
import base64,json,sys
s=sys.stdin.read().strip(); s+="="*(-len(s)%4)
try:
    c=json.loads(base64.b64decode(s))
    print("    aud:", c.get("aud"))
    print("    scp:", c.get("scp") or c.get("scope"))
except Exception: pass' 2>/dev/null
    printf '%s' "$token" > /tmp/tat-partner-token
  else
    bad "no token"
    printf '%s' "$body" | show | sed 's/^/    /'
    return 1
  fi
}

# ------------------------------------------------------------- register

cmd_register() {
  need_creds
  : "${TESLA_KEY_DOMAIN:?set TESLA_KEY_DOMAIN}"
  cmd_token >/dev/null || { bold "Partner token failed — run: $0 token"; return 1; }
  local token; token=$(cat /tmp/tat-partner-token)

  bold "Register partner account in every region"
  for pair in "North America:$NA" "Europe:$EU"; do
    local name="${pair%%:*}" base="${pair#*:}"
    local body; body=$(curl -s --max-time 30 -X POST "$base/api/1/partner_accounts" \
      -H 'Content-Type: application/json' -H "Authorization: Bearer $token" \
      -d "{\"domain\": \"$TESLA_KEY_DOMAIN\"}")
    if printf '%s' "$body" | grep -q '"error"'; then
      bad "$name"
      printf '%s' "$body" | show | sed 's/^/      /'
    else
      ok "$name"
    fi
  done
}

# ---------------------------------------------------------------- login

cmd_login() {
  need_creds
  local state; state=$(uuidgen 2>/dev/null || date +%s)
  local enc_redirect; enc_redirect=$(printf %s "$REDIRECT" | sed 's|:|%3A|g;s|/|%2F|g')
  local enc_scope; enc_scope=$(printf %s "$SCOPES" | sed 's/ /%20/g')
  local url="$AUTH_HOST/oauth2/v3/authorize?client_id=$TESLA_CLIENT_ID&redirect_uri=$enc_redirect&response_type=code&scope=$enc_scope&state=$state"

  bold "Open this in a browser and sign in:"
  echo
  echo "  $url"
  echo
  command -v open >/dev/null && open "$url" 2>/dev/null

  bold "Waiting for Tesla to redirect back to $REDIRECT …"
  info "(the browser will show 'can't be reached' — that is expected)"
  echo
  read -r -p "  Paste the full localhost URL from the address bar: " cb
  local code; code=$(printf '%s' "$cb" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
  [ -z "$code" ] && { bad "no ?code= in that URL"; return 1; }
  ok "authorization code received"

  bold "Exchanging code for tokens"
  local body; body=$(curl -s --max-time 30 -X POST "$TOKEN_HOST/oauth2/v3/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' \
    --data-urlencode "client_id=$TESLA_CLIENT_ID" \
    --data-urlencode "client_secret=$TESLA_CLIENT_SECRET" \
    --data-urlencode "code=$code" \
    --data-urlencode "redirect_uri=$REDIRECT")
  local access; access=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
  if [ -z "$access" ]; then
    bad "token exchange failed"
    printf '%s' "$body" | show | sed 's/^/    /'
    return 1
  fi
  ok "access token issued"
  printf '%s' "$access" > /tmp/tat-access-token

  bold "Fetching vehicles — real data"
  for pair in "Europe:$EU" "North America:$NA"; do
    local name="${pair%%:*}" base="${pair#*:}"
    local vb; vb=$(curl -s --max-time 30 "$base/api/1/vehicles" -H "Authorization: Bearer $access")
    if printf '%s' "$vb" | grep -q '"vin"'; then
      ok "$name"
      printf '%s' "$vb" | show | sed 's/^/      /'
      return 0
    fi
    info "$name: $(printf '%s' "$vb" | head -c 160)"
  done
  bad "no vehicles returned in either region"
}

case "${1:-check}" in
  check)    cmd_check ;;
  token)    cmd_token ;;
  register) cmd_register ;;
  login)    cmd_login ;;
  all)      cmd_token && cmd_register && cmd_login ;;
  *) echo "usage: $0 {check|token|register|login|all}"; exit 1 ;;
esac
