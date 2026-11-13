#!/usr/bin/env python3
"""Native mihomo smoke test: synthetic config, loopback listeners only, TUN/DNS disabled.
No user subscriptions, proxy preferences, privileged commands or process-name killing.
"""
import http.server
import json
import os
import pathlib
import platform
import socket
import select
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

assert platform.system() == 'Darwin', 'This harness verifies the macOS core'
core = pathlib.Path(sys.argv[1]).resolve()
assert core.is_file()
clean_env = {k: v for k, v in os.environ.items() if not k.lower().endswith('proxy')}
client = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def reserve():
    s = socket.socket(); s.bind(('127.0.0.1', 0)); return s

class Handler(http.server.BaseHTTPRequestHandler):
    provider_payload = b''
    def do_CONNECT(self):
        host, port = self.path.rsplit(':', 1)
        if host != '127.0.0.1' or int(port) != self.server.server_port:
            self.send_error(403); return
        with socket.create_connection((host, int(port)), timeout=3) as upstream:
            self.send_response(200); self.end_headers()
            sockets = [self.connection, upstream]
            while True:
                ready, _, _ = select.select(sockets, [], [], 3)
                if not ready: break
                for source in ready:
                    data = source.recv(65536)
                    if not data: return
                    (upstream if source is self.connection else self.connection).sendall(data)
    def do_HEAD(self):
        time.sleep(.02)
        self.send_response(200); self.send_header('Content-Length', '0'); self.end_headers()
    def do_GET(self):
        if self.path == '/proxies.yaml':
            data = self.provider_payload
            self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        data = b'payload:\n  - IP-CIDR,127.0.0.1/32,no-resolve\n' if self.path == '/rules.yaml' else b'ARES_NATIVE_FIXTURE'
        self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *args): pass

with tempfile.TemporaryDirectory(prefix='ares-native-core-') as name:
    root = pathlib.Path(name)
    origin = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=origin.serve_forever, daemon=True).start()
    holds = [reserve() for _ in range(4)]
    mixed, socks, http, api_port = [s.getsockname()[1] for s in holds]
    config = {'mixed-port': mixed, 'socks-port': socks, 'port': http,
              'external-controller': f'127.0.0.1:{api_port}', 'allow-lan': False,
              'bind-address': '127.0.0.1', 'mode': 'rule', 'log-level': 'silent',
              'ipv6': False, 'find-process-mode': 'always', 'tun': {'enable': False},
              'dns': {'enable': False}, 'proxies': [],
              'proxy-groups': [{'name': 'Fixture', 'type': 'select', 'proxies': ['DIRECT', 'REJECT']}],
              'rule-providers': {'Fixture Rules': {'type': 'http', 'behavior': 'classical',
                  'url': f'http://127.0.0.1:{origin.server_port}/rules.yaml', 'path': './rules.yaml', 'interval': 3600}},
              'rules': ['RULE-SET,Fixture Rules,Fixture', 'MATCH,REJECT']}
    (root / 'rules.yaml').write_text('payload:\n  - IP-CIDR,127.0.0.1/32,no-resolve\n')
    path = root / 'config.yaml'; path.write_text(json.dumps(config))
    proc = None
    def api(method='GET', path='/configs', data=None):
        req = urllib.request.Request(f'http://127.0.0.1:{api_port}{path}', method=method,
              data=None if data is None else json.dumps(data).encode(), headers={'Content-Type': 'application/json'})
        with client.open(req, timeout=2) as response:
            body = response.read(); return json.loads(body) if body else None
    def traffic():
        result = subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '3',
             '--noproxy', '', '--proxy', f'http://127.0.0.1:{mixed}',
             f'http://127.0.0.1:{origin.server_port}/'], env=clean_env, capture_output=True)
        assert result.returncode == 0 and result.stdout == b'ARES_NATIVE_FIXTURE', result.stderr
    def start():
        global_proc = subprocess.Popen([str(core), '-d', str(root)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=clean_env)
        try:
            for _ in range(80):
                if global_proc.poll() is not None: raise AssertionError('Core exited before readiness')
                try: api(); break
                except (OSError, urllib.error.URLError): time.sleep(.05)
            else: raise AssertionError('API timeout')
            return global_proc
        except BaseException:
            global_proc.terminate(); global_proc.wait(timeout=5); raise
    def stop(process):
        if process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait(); raise AssertionError('Graceful stop timed out')
        for port in [mixed, socks, http, api_port]:
            with socket.socket() as probe:
                assert probe.connect_ex(('127.0.0.1', port)) != 0, 'Listener survived stop'
    try:
        version = subprocess.check_output([str(core), '-v'], env=clean_env, text=True).splitlines()[0]
        assert 'v1.19.34' in version, 'Use the pinned core baseline'
        subprocess.run([str(core), '-t', '-d', str(root)], env=clean_env, check=True, stdout=subprocess.DEVNULL)
        for s in holds: s.close()
        proc = start()
        readback = api()
        for key in ['mixed-port', 'socks-port', 'port', 'mode', 'log-level', 'ipv6', 'allow-lan', 'find-process-mode']:
            assert readback[key] == config[key], (key, readback[key])
        assert readback['tun']['enable'] is False
        traffic()
        rules = api(path='/rules')['rules']
        assert rules[0]['index'] == 0 and rules[0]['payload'] == 'Fixture Rules'
        # The optional wrapper counter is checked only if this build exposes it.
        if 'extra' in rules[0]: assert rules[0]['extra']['hitCount'] >= 1
        provider = api(path='/providers/rules')['providers']['Fixture Rules']
        assert provider['ruleCount'] == 1 and provider['vehicleType'] == 'HTTP'
        api('PUT', '/providers/rules/Fixture%20Rules')
        assert api(path='/providers/rules')['providers']['Fixture Rules']['ruleCount'] == 1
        traffic()
        print('PASS: real RULE-SET matching, provider count/source, HTTP resource update and readback')
        api('PUT', '/proxies/Fixture', {'name': 'REJECT'})
        assert api(path='/proxies/Fixture')['now'] == 'REJECT'
        api('PUT', '/proxies/Fixture', {'name': 'DIRECT'}); traffic()
        bad = root / 'invalid.yaml'; bad.write_text('proxies: [')
        try: api('PUT', '/configs?force=true', {'path': str(bad)}); raise AssertionError('Invalid reload accepted')
        except urllib.error.HTTPError as error: assert error.code == 400
        traffic()
        # Exercise ordered local rules, nested provider references and sub-rule execution.
        nested = dict(config)
        nested['rules'] = ['SUB-RULE,(NETWORK,tcp),Nested', 'MATCH,REJECT']
        nested['sub-rules'] = {'Nested': ['AND,((RULE-SET,Fixture Rules),(NETWORK,tcp)),Fixture', 'MATCH,REJECT']}
        candidate = root / 'nested.yaml'; candidate.write_text(json.dumps(nested))
        api('PUT', '/configs?force=true', {'path': str(candidate)})
        traffic()
        reject_first = dict(config)
        reject_first['rules'] = ['IP-CIDR,127.0.0.1/32,REJECT,no-resolve'] + config['rules']
        candidate.write_text(json.dumps(reject_first))
        api('PUT', '/configs?force=true', {'path': str(candidate)})
        try: traffic(); raise RuntimeError('Priority rule did not reject traffic')
        except AssertionError: pass
        reject_first['rules'] = config['rules'] + ['IP-CIDR,127.0.0.1/32,REJECT,no-resolve']
        candidate.write_text(json.dumps(reject_first))
        api('PUT', '/configs?force=true', {'path': str(candidate)})
        traffic()
        api('PUT', '/configs?force=true', {'path': str(path)})
        traffic()
        print('PASS: nested RULE-SET, SUB-RULE execution and actual first-match rule ordering')
        # All four policy types and a real HTTP provider, only loopback traffic.
        payload = {'proxies': [{'name': 'Provider A', 'type': 'http', 'server': '127.0.0.1', 'port': origin.server_port},
                               {'name': 'Provider B', 'type': 'http', 'server': '127.0.0.1', 'port': origin.server_port}]}
        Handler.provider_payload = json.dumps(payload).encode()
        (root / 'proxy-resource.yaml').write_bytes(Handler.provider_payload)
        policy = dict(config)
        test_url = f'http://127.0.0.1:{origin.server_port}/health'
        policy['proxy-providers'] = {'Remote Nodes': {'type': 'http', 'url': f'http://127.0.0.1:{origin.server_port}/proxies.yaml',
            'path': './proxy-resource.yaml', 'interval': 3600, 'health-check': {'enable': True, 'url': test_url, 'interval': 600, 'lazy': False}}}
        policy['proxy-groups'] = [
            {'name': 'Pick', 'type': 'select', 'proxies': ['Auto', 'Fallback', 'Balance'], 'use': ['Remote Nodes']},
            {'name': 'Auto', 'type': 'url-test', 'use': ['Remote Nodes'], 'url': test_url, 'interval': 600, 'tolerance': 30},
            {'name': 'Fallback', 'type': 'fallback', 'use': ['Remote Nodes'], 'url': test_url, 'interval': 600},
            {'name': 'Balance', 'type': 'load-balance', 'use': ['Remote Nodes'], 'url': test_url, 'interval': 600, 'strategy': 'round-robin'}]
        policy['rules'] = ['MATCH,Pick']
        candidate.write_text(json.dumps(policy))
        api('PUT', '/configs?force=true', {'path': str(candidate)})
        for group, kind in [('Pick', 'Selector'), ('Auto', 'URLTest'), ('Fallback', 'Fallback'), ('Balance', 'LoadBalance')]:
            assert api(path='/proxies/' + group)['type'] == kind
        api('GET', '/providers/proxies/Remote%20Nodes/healthcheck')
        resource = api(path='/providers/proxies')['providers']['Remote Nodes']
        assert len(resource['proxies']) == 2 and all(node.get('history') and node['history'][-1]['delay'] > 0 for node in resource['proxies']), resource
        for group in ['Auto', 'Fallback']:
            api('PUT', '/proxies/' + group, {'name': 'Provider B'})
            assert api(path='/proxies/' + group)['fixed'] == 'Provider B', (group, api(path='/proxies/' + group))
            api('DELETE', '/proxies/' + group)
            assert not api(path='/proxies/' + group).get('fixed')
        for member in ['Auto', 'Fallback', 'Balance', 'Provider A']:
            api('PUT', '/proxies/Pick', {'name': member}); traffic()
        payload['proxies'].append({'name': 'Provider C', 'type': 'http', 'server': '127.0.0.1', 'port': origin.server_port})
        Handler.provider_payload = json.dumps(payload).encode()
        api('PUT', '/providers/proxies/Remote%20Nodes')
        assert len(api(path='/providers/proxies')['providers']['Remote Nodes']['proxies']) == 3
        assert 'Provider C' in api(path='/proxies/Pick')['all']
        api('PUT', '/proxies/Pick', {'name': 'Provider C'}); traffic()
        api('PUT', '/configs?force=true', {'path': str(path)})
        traffic()
        print('PASS: four policy types, nested selections, auto/fallback pin/reset, load-balanced traffic, HTTP provider update, health history and new member selection')
        # Graceful stop and abrupt exit both release only this test's listeners.
        stop(proc); proc = start(); traffic()
        proc.kill(); proc.wait(timeout=5); stop(proc)
        proc = start(); traffic(); stop(proc); proc = None
        print('PASS: macOS arm64 v1.19.34 readback, real loopback proxy traffic, node selection, invalid reload retention, graceful stop, crash/restart')
    finally:
        if proc is not None:
            if proc.poll() is None: proc.kill(); proc.wait(timeout=5)
        for s in holds: s.close()
        origin.shutdown(); origin.server_close()
