#!/usr/bin/env python3
"""Owned mihomo + synthetic loopback UDP resolvers. No host DNS/proxy/TUN changes."""
import http.server
import ipaddress
import json
import os
import pathlib
import socket
import select
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request

client = urllib.request.build_opener(urllib.request.ProxyHandler({}))

class Resolver:
    def __init__(self, address):
        self.address = address
        self.requests = []
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(('127.0.0.1', 0))
        self.socket.settimeout(.2)
        self.port = self.socket.getsockname()[1]
        self.stopped = False
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        while not self.stopped:
            try:
                query, peer = self.socket.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            pos = 12
            labels = []
            while query[pos]:
                length = query[pos]; pos += 1
                labels.append(query[pos:pos + length].decode('ascii')); pos += length
            pos += 1
            kind, _ = struct.unpack('!HH', query[pos:pos + 4]); pos += 4
            name = '.'.join(labels)
            self.requests.append((name, kind))
            missing = name.startswith('missing.')
            empty = name.startswith('empty.')
            data = ipaddress.ip_address('2001:db8::42' if kind == 28 else self.address).packed
            answer = b'' if missing or empty else b'\xc0\x0c' + struct.pack('!HHIH', kind, 1, 90, len(data)) + data
            header = query[:2] + struct.pack('!HHHHH', 0x8183 if missing else 0x8180, 1, int(bool(answer)), 0, 0)
            self.socket.sendto(header + query[12:pos] + answer, peer)

    def close(self):
        self.stopped = True
        self.thread.join(timeout=1)
        self.socket.close()

core = pathlib.Path(sys.argv[1]).resolve()
assert core.is_file()
normal = Resolver('192.0.2.10')
policy = Resolver('192.0.2.20')
direct = Resolver('127.0.0.1')
proxy_host = Resolver('127.0.0.1')
class Origin(http.server.BaseHTTPRequestHandler):
    def do_CONNECT(self):
        # Synthetic proxy terminates the tunnel at our owned HTTP origin only.
        _, port = self.path.rsplit(':', 1)
        if int(port) != self.server.server_port:
            self.send_error(403); return
        with socket.create_connection(('127.0.0.1', int(port)), timeout=3) as upstream:
            self.send_response(200); self.end_headers()
            while True:
                ready, _, _ = select.select([self.connection, upstream], [], [], 3)
                if not ready: return
                for source in ready:
                    data = source.recv(65536)
                    if not data: return
                    (upstream if source is self.connection else self.connection).sendall(data)
    def do_GET(self):
        data = b'ARES_DNS_ROUTE_FIXTURE'
        self.send_response(200); self.send_header('Content-Length', str(len(data)))
        self.end_headers(); self.wfile.write(data)
    def log_message(self, *args): pass
origin = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Origin)
threading.Thread(target=origin.serve_forever, daemon=True).start()
process = None
try:
    with tempfile.TemporaryDirectory(prefix='ares-native-dns-') as directory:
        root = pathlib.Path(directory)
        hold = socket.socket(); hold.bind(('127.0.0.1', 0))
        port = hold.getsockname()[1]
        mixed_hold = socket.socket(); mixed_hold.bind(('127.0.0.1', 0))
        mixed = mixed_hold.getsockname()[1]
        config = {
            'external-controller': f'127.0.0.1:{port}', 'mixed-port': mixed, 'allow-lan': False,
            'bind-address': '127.0.0.1', 'log-level': 'silent', 'ipv6': True,
            'tun': {'enable': False},
            'proxies': [{'name': 'Fixture Proxy', 'type': 'http', 'server': 'node.fixture.test', 'port': origin.server_port}],
            'rules': ['DOMAIN,proxied.fixture.test,Fixture Proxy', 'MATCH,DIRECT'],
            'dns': {'enable': True, 'ipv6': True, 'enhanced-mode': 'redir-host',
                    'use-hosts': True, 'use-system-hosts': False,
                    'nameserver': [f'udp://127.0.0.1:{normal.port}'],
                    'direct-nameserver': [f'udp://127.0.0.1:{direct.port}'],
                    'proxy-server-nameserver': [f'udp://127.0.0.1:{proxy_host.port}'],
                    'nameserver-policy': {'+.policy.test': [f'udp://127.0.0.1:{policy.port}']}},
            'hosts': {'host.fixture.test': '192.0.2.30'}
        }
        path = root / 'config.json'; path.write_text(json.dumps(config))
        env = {k: v for k, v in os.environ.items() if not k.lower().endswith('proxy')}
        hold.close(); mixed_hold.close()
        with (root / 'core.log').open('wb') as log:
            process = subprocess.Popen([str(core), '-d', str(root), '-f', str(path)], env=env, stdout=log, stderr=log)
            base = f'http://127.0.0.1:{port}'
            for _ in range(100):
                try:
                    with client.open(base + '/version', timeout=.2) as response:
                        version = json.load(response)['version']
                    assert '1.19.34' in version, version
                    break
                except (OSError, ValueError):
                    assert process.poll() is None, (root / 'core.log').read_text()
                    time.sleep(.05)
            else:
                raise AssertionError('Owned core did not start')

            def query(name, kind='A'):
                with client.open(base + '/dns/query?' + urllib.parse.urlencode({'name': name, 'type': kind}), timeout=5) as response:
                    return json.load(response)

            answer = query('normal.fixture.test')
            assert answer['Status'] == 0 and answer['Answer'][0]['data'] == '192.0.2.10', answer
            assert 0 < answer['Answer'][0]['TTL'] <= 90, answer
            answer = query('node.policy.test')
            assert answer['Answer'][0]['data'] == '192.0.2.20', answer
            assert ('node.policy.test', 1) in policy.requests
            assert ('node.policy.test', 1) not in normal.requests
            answer = query('ipv6.fixture.test', 'AAAA')
            assert answer['Answer'][0]['type'] == 28 and answer['Answer'][0]['data'] == '2001:db8::42', answer
            answer = query('missing.fixture.test')
            assert answer['Status'] == 3 and not answer.get('Answer'), answer
            answer = query('empty.fixture.test')
            assert answer['Status'] == 0 and not answer.get('Answer'), answer
            # Exercise real outbound traffic; query API cannot simulate these paths.
            for name in ['direct.fixture.test', 'proxied.fixture.test']:
                request = urllib.request.Request(f'http://{name}:{origin.server_port}/')
                request.set_proxy(f'127.0.0.1:{mixed}', 'http')
                with client.open(request, timeout=5) as response:
                    assert response.read() == b'ARES_DNS_ROUTE_FIXTURE'
            assert ('direct.fixture.test', 1) in direct.requests, direct.requests
            assert ('node.fixture.test', 1) in proxy_host.requests, proxy_host.requests
            assert not any(name == 'node.fixture.test' for name, _ in normal.requests)
            print('PASS: actual HTTP flow resolves direct destinations and proxy hostnames through their dedicated resolvers')
            # /dns/query calls DefaultResolver.ExchangeContext: hosts is a different path.
            # Do not promise hosts/fake-IP substitution in the diagnostics UI.
            print('PASS: pinned native DNS API; real A/AAAA/TTL, domain policy isolation, NXDOMAIN and empty response')
finally:
    if process is not None:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
    normal.close(); policy.close(); direct.close(); proxy_host.close()
    origin.shutdown(); origin.server_close()
    for listener in [locals().get('port'), locals().get('mixed')]:
        if listener is not None:
            with socket.socket() as check:
                assert check.connect_ex(('127.0.0.1', listener)) != 0, 'Owned core listener leaked'
    print('PASS: owned DNS fixture/core cleaned up; host DNS, TUN and proxy untouched')
