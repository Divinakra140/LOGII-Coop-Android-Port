#!/bin/zsh
# Locks the GLOBAL MULTIPLAYER lobby list with a password (Cloudflare secret LOBBY_KEY) and writes
# project/lobby_server.txt (line 1: address, line 2: password) for builds. Both stay out of the repo.
# Needs lobby/.cloudflare_token (an API token of the account that runs the worker).
B="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://log2-lobbies.log2coop.workers.dev"
T=$(tr -d ' \r\n\t' < "$B/lobby/.cloudflare_token") || exit 1
ID=$(curl -s https://api.cloudflare.com/client/v4/accounts -H "Authorization: Bearer $T" | python3 -I -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])") || { echo "Could not reach the Cloudflare account."; exit 1; }
echo "Choose the lobby password (12 or more characters: letters, numbers and symbols - no spaces). Nothing shows while you type."
read -s "P1?Password: "; echo
read -s "P2?Again:    "; echo
[ "$P1" = "$P2" ] || { echo "They do not match - nothing changed."; exit 1; }
[ ${#P1} -ge 12 ] || { echo "Too short (12 or more) - nothing changed."; exit 1; }
[[ "$P1" =~ '^[!-~]+$' ]] || { echo "No spaces or accented letters, please - nothing changed."; exit 1; }
# (the password goes to Cloudflare as JSON built by python, so symbols like " and \ are safe)
BODY=$(LOBBY_PW="$P1" python3 -I -c 'import json,os; print(json.dumps({"name": "LOBBY_KEY", "text": os.environ["LOBBY_PW"], "type": "secret_text"}))')
R=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$ID/workers/scripts/log2-lobbies/secrets" -H "Authorization: Bearer $T" -H "Content-Type: application/json" --data "$BODY")
echo "$R" | grep -q -E '"success": *true' || { echo "Cloudflare did not take it:"; echo "$R" | python3 -I -c "import sys,json; print([e.get('message') for e in json.load(sys.stdin).get('errors',[])])"; exit 1; }
umask 077
printf '%s\n%s\n' "$URL" "$P1" > "$B/project/lobby_server.txt"
echo "Done: the lobby list is locked, and project/lobby_server.txt is saved (it is not in git)."
