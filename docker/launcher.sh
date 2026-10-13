#!/bin/sh
# Tiny mint server for Claude Science, sitting behind the Caddy proxy.
#
# socat runs it once per request (see entrypoint.sh):
#   socat TCP-LISTEN:PORT,reuseaddr,fork EXEC:/usr/local/bin/launcher.sh
#
# Routes (all reached through the proxy, never directly):
#   GET /__cs_auth   mint a single-use login nonce and return a tiny page that
#                    POSTs it to the daemon's /api/auth/nonce, signing the
#                    browser in without the daemon's "Sign in" click-through
#   GET /__cs_status small JSON: is the daemon up yet
#
# Since 0.1.5x the daemon no longer signs you in on GET /?nonce=...; that link
# only renders a "Sign in" button which POSTs the nonce. We submit that form
# for the user. The form action is a *path* (no host), so the port the daemon
# advertises internally never leaks to the browser: it resolves against the
# public proxy address the browser is already on.

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
        if claude-science status 2>/dev/null | grep -Eq '"running": *true'; then
            send "200 OK" "application/json" '{"ready":true}'
        else
            send "200 OK" "application/json" '{"ready":false}'
        fi
        ;;

    *)  # /__cs_auth and anything else routed here: mint a nonce
        # The daemon prints e.g. http://localhost:47100/?nonce=abc (or
        # .../<base-path>/?nonce=abc); keep the path prefix and the nonce.
        link=$(claude-science url 2>/dev/null | grep -oE 'https?://[^ ]+' | head -1)
        nonce=$(printf '%s' "$link" | sed -nE 's#.*[?&]nonce=([0-9A-Za-z_-]+).*#\1#p')
        prefix=$(printf '%s' "$link" | sed -E 's#^https?://[^/]+##; s#\?.*##; s#/*$#/#')
        if [ -n "$nonce" ]; then
            send "200 OK" "text/html; charset=utf-8" "<!doctype html><meta charset=utf-8><title>Signing in</title><body style=\"font:15px/1.6 system-ui,sans-serif;text-align:center;padding:4rem 1rem;color:#333\"><form method=post action=\"${prefix}api/auth/nonce\"><input type=hidden name=nonce value=\"${nonce}\"><input type=hidden name=dest value=\"${prefix}\"><p>Signing you in...</p><noscript><button type=submit>Continue</button></noscript></form><script>document.forms[0].submit()</script>"
        else
            # Daemon not ready (still starting or mid-restart): show a page that
            # retries itself until the mint succeeds.
            send "200 OK" "text/html; charset=utf-8" "$reconnecting_page"
        fi
        ;;
esac
