#!/bin/sh
# Tiny mint server for Claude Science, sitting behind the Caddy proxy.
#
# socat runs it once per request (see entrypoint.sh):
#   socat TCP-LISTEN:PORT,reuseaddr,fork EXEC:/usr/local/bin/launcher.sh
#
# Routes (all reached through the proxy, never directly):
#   GET /__cs_auth   mint a single-use login link and 302 to it (relative, so
#                    the browser stays on whatever host/port it is already using)
#   GET /__cs_status small JSON: is the daemon up yet
#
# It returns a *relative* redirect (Location: /?nonce=...). That way the port
# the daemon advertises internally never leaks to the browser: the browser
# resolves it against the public proxy address it is already on.

read -r request_line
path=$(printf '%s' "$request_line" | awk '{print $2}')

send() {
    _body=$3
    _len=$(printf '%s' "$_body" | wc -c)
    printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n%s' \
        "$1" "$2" "$_len" "$_body"
}

reconnecting_page='<!doctype html><meta charset=utf-8><meta http-equiv=refresh content=2><title>Starting</title><body style="font:15px/1.6 system-ui,sans-serif;text-align:center;padding:4rem 1rem;color:#333"><h2>Starting up...</h2><p>Claude Science is getting ready. This page refreshes on its own.</p>'

case "$path" in
    /__cs_status)
        if claude-science status 2>/dev/null | grep -q '"running": true'; then
            send "200 OK" "application/json" '{"ready":true}'
        else
            send "200 OK" "application/json" '{"ready":false}'
        fi
        ;;

    *)  # /__cs_auth and anything else routed here: mint a link
        # The daemon prints e.g. http://localhost:47100/?nonce=abc; keep only the
        # path and query so the redirect stays relative to the public address.
        target=$(claude-science url 2>/dev/null \
            | grep -oE 'https?://[^ ]+' \
            | head -1 \
            | sed -E 's#^https?://[^/]+##')
        if [ -n "$target" ]; then
            printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n' "$target"
        else
            # Daemon not ready (still starting or mid-restart): show a page that
            # retries itself until the mint succeeds.
            send "200 OK" "text/html; charset=utf-8" "$reconnecting_page"
        fi
        ;;
esac
