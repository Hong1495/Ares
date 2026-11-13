#!/usr/bin/env python3
"""Real process-path rules and automatic fallback; owned loopback core and fixtures only."""
import http.server
import json
import os
import pathlib
import select
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
clean = {k: v for k, v in os.environ.items() if not k.lower().endswith('proxy')}
class Origin(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        time.sleep(.02)
        self.send_response(204); self.end_headers()
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ARES_WORKFLOW')
    def log_message(self, *args): pass
class Proxy(http.server.BaseHTTPRequestHandler):
    def do_CONNECT(self):
        if not self.server.available:
            self.send_error(503); return
        host, port = self.path.rsplit(':', 1)
        if host != '127.0.0.1' or int(port) != origin.server_port:
            self.send_error(403); return
        with socket.create_connection((host, int(port)), timeout=3) as upstream:
            self.server.visits += 1
            self.send_response(200); self.end_headers()
            while True:
                ready, _, _ = select.select([self.connection, upstream], [], [], 2)
                if not ready: return
                for source in ready:
                    data = source.recv(65536)
                    if not data: return
                    (upstream if source is self.connection else self.connection).sendall(data)
    def log_message(self, *args): pass
servers = []
process = None
holds = []
try:
    for handler in [Origin, Proxy, Proxy]:
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
        server.available = True; server.visits = 0
        threading.Thread(target=server.serve_forever, daemon=True).start(); servers.append(server)
    origin, primary, backup = servers
    for _ in range(2):
        hold = socket.socket(); hold.bind(('127.0.0.1', 0)); holds.append(hold)
    api_port, mixed = [s.getsockname()[1] for s in holds]
    test_url = f'http://127.0.0.1:{origin.server_port}/'
    with tempfile.TemporaryDirectory(prefix='ares-native-workflows-') as directory:
        root = pathlib.Path(directory)
        cfg = {'external-controller': f'127.0.0.1:{api_port}', 'mixed-port': mixed,
               'bind-address': '127.0.0.1', 'allow-lan': False, 'mode': 'rule', 'log-level': 'debug',
               'find-process-mode': 'always', 'dns': {'enable': False}, 'tun': {'enable': False},
               'proxies': [{'name': name, 'type': 'http', 'server': '127.0.0.1', 'port': server.server_port} for name, server in [('Primary', primary), ('Backup', backup)]],
               'proxy-groups': [{'name': 'Fallback', 'type': 'fallback', 'proxies': ['Primary', 'Backup'], 'url': test_url, 'interval': 1, 'lazy': False, 'timeout': 500}],
               'rules': ['PROCESS-PATH,/usr/bin/curl,Fallback', 'MATCH,REJECT']}
        path = root / 'config.json'; path.write_text(json.dumps(cfg))
        for hold in holds: hold.close()
        with (root / 'core.log').open('wb') as log:
            process = subprocess.Popen([sys.argv[1], '-d', directory, '-f', str(path)], stdout=log, stderr=log, env=clean)
            def api(method='GET', path='/version', body=None):
                req = urllib.request.Request(f'http://127.0.0.1:{api_port}{path}', method=method,
                    data=None if body is None else json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
                with client.open(req, timeout=4) as response:
                    data = response.read(); return json.loads(data) if data else None
            for _ in range(100):
                try:
                    assert '1.19.34' in api()['version']; break
                except OSError:
                    assert process.poll() is None, (root / 'core.log').read_text()
                    time.sleep(.05)
            else: raise AssertionError('Core did not start')
            def traffic(success=True):
                result = subprocess.run(['/usr/bin/curl', '--silent', '--fail', '--max-time', '3', '--noproxy', '', '--proxy', f'http://127.0.0.1:{mixed}', test_url], capture_output=True, env=clean)
                assert (result.returncode == 0 and result.stdout == b'ARES_WORKFLOW') == success, (result.returncode, result.stdout, result.stderr, (root / 'core.log').read_text()[-5000:])
            process_identity = True
            try: traffic()
            except AssertionError:
                if 'find process error' not in (root / 'core.log').read_text(): raise
                process_identity = False
                print('SKIP: unprivileged core cannot resolve macOS executable identity; physical privileged/TUN process-rule acceptance remains open')
                assert api(path='/rules')['rules'][0]['type'] == 'ProcessPath'
                cfg['rules'] = ['MATCH,Fallback']
                path.write_text(json.dumps(cfg)); api('PUT', '/configs?force=true', {'path': str(path)})
                traffic()
            assert primary.visits > 0
            if process_identity:
                # Another executable must not pass the exact curl rule.
                request = urllib.request.Request(test_url); request.set_proxy(f'127.0.0.1:{mixed}', 'http')
                try: client.open(request, timeout=2); raise AssertionError('Unmatched process passed')
                except (OSError, urllib.error.URLError): pass
                print('PASS: real macOS curl executable rule routes traffic; unmatched Python process is blocked')
            primary.available = False
            for _ in range(120):
                if api(path='/proxies/Fallback')['now'] == 'Backup': break
                time.sleep(.1)
            else: raise AssertionError('Automatic fallback did not move to Backup')
            traffic(); assert backup.visits > 0
            primary.available = True
            for _ in range(120):
                if api(path='/proxies/Fallback')['now'] == 'Primary': break
                time.sleep(.1)
            else: raise AssertionError('Preferred primary did not recover')
            api('PUT', '/proxies/Fallback', {'name': 'Backup'})
            assert api(path='/proxies/Fallback')['fixed'] == 'Backup'; traffic()
            api('DELETE', '/proxies/Fallback'); assert not api(path='/proxies/Fallback').get('fixed')
            print('PASS: actual primary failure switches to backup; recovery, manual pin and automatic resume confirmed')
            for target in ['Fallback', 'Primary']:
                result = api(path='/proxies/' + target + '/delay?' + urllib.parse.urlencode({'url': test_url, 'timeout': 1000}))
                assert result['delay'] > 0
            primary.available = False
            try:
                api(path='/proxies/Primary/delay?' + urllib.parse.urlencode({'url': test_url, 'timeout': 1000}))
                raise AssertionError('Failed outbound reported success')
            except urllib.error.HTTPError as error: assert error.code in (503, 504), error.code
            primary.available = True
            cfg['rules'] = ['PROCESS-PATH,/usr/bin/curl,REJECT', 'MATCH,DIRECT']
            path.write_text(json.dumps(cfg)); api('PUT', '/configs?force=true', {'path': str(path)})
            if process_identity: traffic(False)
            cfg['rules'] = ['MATCH,DIRECT']; path.write_text(json.dumps(cfg)); api('PUT', '/configs?force=true', {'path': str(path)})
            traffic()
            print('PASS: delay API reports measured success/failure; process rule configuration accepted; removing override restores traffic')
finally:
    if process and process.poll() is None:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
    for hold in holds: hold.close()
    for server in servers: server.shutdown(); server.server_close()
print('PASS: owned fixtures/core cleaned up; system proxy, DNS and TUN untouched')
