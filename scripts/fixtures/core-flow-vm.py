#!/usr/bin/env python3
"""Run ONLY inside the disposable Linux VM. Never imports a user's subscription."""
import http.server
import json
import os
import pathlib
import platform
import subprocess
import threading
import time
import urllib.request

assert platform.system() == 'Linux', 'This test changes routes; run only inside the disposable VM'
assert pathlib.Path('/tmp/ares-flow/normal.yaml').exists()
for key in list(os.environ):
    if key.lower().endswith('proxy'): os.environ.pop(key)
ROOT = pathlib.Path('/tmp/ares-flow')
client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
servers = []
for port, label in [(18081, 'NODE_A'), (18082, 'NODE_B')]:
    class Handler(http.server.BaseHTTPRequestHandler):
        marker = label
        def do_CONNECT(self):
            self.send_response(200)
            self.end_headers()
            # Serve a deterministic HTTP response inside the proxy tunnel.
            self.rfile.readline()
            while self.rfile.readline().strip(): pass
            body = self.marker.encode()
            self.wfile.write(b'HTTP/1.1 200 OK\r\nContent-Length: ' + str(len(body)).encode() + b'\r\nConnection: close\r\n\r\n' + body)
            self.wfile.flush()
        def do_GET(self):
            body = self.marker.encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args): pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    servers.append(server)

def api(port, path, method='GET', value=None):
    request = urllib.request.Request(f'http://127.0.0.1:{port}{path}', data=None if value is None else json.dumps(value).encode(), method=method, headers={'Content-Type':'application/json'})
    with client.open(request, timeout=2) as response:
        data = response.read()
        return json.loads(data) if data else None

def request(args):
    result = subprocess.run(['curl','--fail','--silent','--show-error','--max-time','8'] + args + ['http://198.19.0.10/flow'], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout == 'NODE_B', result.stdout

def run(tun):
    directory = ROOT / ('tun' if tun else 'normal')
    directory.mkdir(exist_ok=True)
    config = ROOT / ('tun.yaml' if tun else 'normal.yaml')
    subprocess.run([str(ROOT/'mihomo'), '-t', '-d', str(directory), '-f', str(config)], check=True, stdout=subprocess.DEVNULL)
    log = open(directory/'core.log', 'w')
    proc = subprocess.Popen([str(ROOT/'mihomo'),'-d',str(directory),'-f',str(config)], stdout=log, stderr=log)
    port = 19097 if tun else 9097
    try:
        for _ in range(100):
            try:
                api(port, '/version')
                break
            except Exception: time.sleep(.1)
        else: raise AssertionError('Core API did not start')
        groups = api(port, '/proxies')['proxies']
        assert set(groups['Proxy']['all']) == {'Node A','Node B'}
        # The UI's saved choice is reapplied after every normal/TUN launch.
        api(port, '/proxies/Proxy', 'PUT', {'name':'Node B'})
        assert api(port, '/proxies/Proxy')['now'] == 'Node B'
        config_state = api(port, '/configs')
        assert config_state['tun']['enable'] == tun
        request(['--noproxy','','--proxy',f'http://127.0.0.1:{17890 if tun else 7890}'])
        request(['--noproxy','','--socks5-hostname',f'127.0.0.1:{17891 if tun else 7891}'])
        if tun:
            request(['--noproxy','*'])
            assert 'ares-test' in subprocess.check_output(['ip','link','show'], text=True)
        print(('TUN' if tun else 'Normal') + ': configuration, selection readback, HTTP/SOCKS' + (', direct TUN routing' if tun else '') + ' PASS', flush=True)
    finally:
        proc.terminate()
        try: proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill();proc.wait();raise AssertionError('Core failed to stop')
        log.close()

try:
    run(False)
    run(True)
    run(False)
    print('Normal → TUN → Normal, preserved selection and traffic: PASS', flush=True)
finally:
    for server in servers: server.shutdown()
