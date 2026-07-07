#!/bin/sh
# Tiny launcher HTTP server for Claude Science.
#
# It is run one-connection-per-request by socat (see entrypoint.sh):
#   socat TCP-LISTEN:PORT,reuseaddr,fork EXEC:/usr/local/bin/launcher.sh
#
# Routes:
#   GET  /       welcome page with a "Launch" button
#   GET  /go     mints a single-use login link and 302-redirects to it
#   GET  /status small JSON that says whether the daemon is up yet
#
# The heavy lifting (minting the link) is done by the daemon via
# `claude-science url`; this script just turns that into a click.

read -r request_line
path=$(printf '%s' "$request_line" | awk '{print $2}')

send() {
    # send <status-line> <content-type> <body>
    _body=$3
    _len=$(printf '%s' "$_body" | wc -c)
    printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n%s' \
        "$1" "$2" "$_len" "$_body"
}

case "$path" in
    /go)
        url=$(claude-science url 2>/dev/null | grep -Eo 'https?://[^ ]+' | head -1)
        if [ -n "$url" ]; then
            printf 'HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n' "$url"
        else
            send "503 Service Unavailable" "text/html; charset=utf-8" \
'<!doctype html><meta charset="utf-8"><title>Starting...</title><body style="font-family:system-ui;text-align:center;padding:3rem">
<h1>Almost ready</h1><p>Claude Science is still starting up. Give it a few seconds.</p>
<p><a href="/">Try again</a></p></body>'
        fi
        ;;

    /status)
        if claude-science status 2>/dev/null | grep -q '"running": true'; then
            send "200 OK" "application/json" '{"ready":true}'
        else
            send "200 OK" "application/json" '{"ready":false}'
        fi
        ;;

    *)
        send "200 OK" "text/html; charset=utf-8" "$(cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claude Science</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    background: radial-gradient(1200px 800px at 50% -10%, #2b2440 0%, #14121c 55%, #0d0b12 100%);
    color: #ece9f5; padding: 24px;
  }
  .card {
    width: 100%; max-width: 460px; text-align: center;
    background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08);
    border-radius: 20px; padding: 40px 32px; backdrop-filter: blur(6px);
    box-shadow: 0 24px 60px rgba(0,0,0,0.45);
  }
  .logo {
    width: 60px; height: 60px; margin: 0 auto 20px; border-radius: 16px;
    display: grid; place-items: center; font-size: 30px;
    background: linear-gradient(135deg, #d97757, #b8532f);
  }
  h1 { font-size: 1.55rem; margin: 0 0 6px; letter-spacing: -0.02em; }
  p.sub { margin: 0 0 28px; color: #a9a4bd; font-size: 0.98rem; line-height: 1.5; }
  .btn {
    display: inline-block; width: 100%; padding: 15px 20px; border: 0; cursor: pointer;
    font-size: 1.05rem; font-weight: 600; border-radius: 12px; text-decoration: none;
    color: #fff; background: linear-gradient(135deg, #d97757, #c05f38);
    transition: transform .06s ease, filter .2s ease;
  }
  .btn:hover { filter: brightness(1.07); }
  .btn:active { transform: translateY(1px); }
  .hint { margin-top: 18px; font-size: 0.82rem; color: #7f7a95; line-height: 1.5; }
  .status { margin-top: 22px; font-size: 0.85rem; color: #8f8aa6; }
  .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background:#b6803a; margin-right:6px; vertical-align: middle; }
  .dot.ok { background:#4a9d5b; }
  .foot { margin-top: 26px; font-size: 0.78rem; color: #6c6784; }
  .foot a { color: #a99; }
</style>
</head>
<body>
  <main class="card">
    <div class="logo">&#129514;</div>
    <h1>Claude Science</h1>
    <p class="sub">Your AI workbench for research is running in this container. Click below to open it and sign in with your Claude account.</p>
    <a class="btn" id="launch" href="/go">Launch Claude Science</a>
    <div class="status"><span class="dot" id="dot"></span><span id="statusText">Checking status...</span></div>
    <p class="hint">The button creates a one-time sign-in link that lasts about 3 minutes. If it stops working, just come back here and click again.</p>
    <div class="foot">Unofficial Docker packaging &middot; not affiliated with Anthropic</div>
  </main>
  <script>
    (function () {
      var dot = document.getElementById('dot');
      var txt = document.getElementById('statusText');
      var btn = document.getElementById('launch');
      function poll() {
        fetch('/status').then(function (r) { return r.json(); }).then(function (d) {
          if (d.ready) {
            dot.className = 'dot ok'; txt.textContent = 'Ready';
            btn.textContent = 'Launch Claude Science';
          } else {
            dot.className = 'dot'; txt.textContent = 'Starting up, please wait...';
            setTimeout(poll, 3000);
          }
        }).catch(function () { setTimeout(poll, 3000); });
      }
      poll();
    })();
  </script>
</body>
</html>
HTML
)"
        ;;
esac
