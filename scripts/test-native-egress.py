#!/usr/bin/env python3
"""Pinned mihomo outbound/forwarding acceptance. Loopback only; no host settings."""
import base64
import http.server
import json
import os
import pathlib
import select
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

client = urllib.request.build_opener(urllib.request.ProxyHandler({}))
class Origin(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        data = b'ARES_EGRESS_FIXTURE'
        self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *args): pass
class Proxy(Origin):
    def do_CONNECT(self):
        host, port = self.path.rsplit(':', 1)
        if host != '127.0.0.1' or int(port) not in self.server.allowed:
            self.send_error(403); return
        self.server.visits.append(int(port))
        with socket.create_connection((host, int(port)), timeout=3) as upstream:
            self.send_response(200); self.end_headers()
            while True:
                ready, _, _ = select.select([self.connection, upstream], [], [], 3)
                if not ready: return
                for source in ready:
                    data = source.recv(65536)
                    if not data: return
                    (upstream if source is self.connection else self.connection).sendall(data)
class Echo(socketserver.BaseRequestHandler):
    def handle(self): self.request[1].sendto(self.request[0], self.client_address)
def http_server(handler):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
origin = http_server(Origin)
entry = http_server(Proxy)
exit_proxy = http_server(Proxy)
entry.allowed = {exit_proxy.server_port}; entry.visits = []
exit_proxy.allowed = {origin.server_port}; exit_proxy.visits = []
echo = socketserver.ThreadingUDPServer(('127.0.0.1', 0), Echo)
threading.Thread(target=echo.serve_forever, daemon=True).start()
reservations = []
def reserve():
    hold = socket.socket(); hold.bind(('127.0.0.1', 0)); reservations.append(hold); return hold.getsockname()[1]
api, mixed, listener, socks, forward_tcp, forward_udp = [reserve() for _ in range(6)]
process = None
try:
    with tempfile.TemporaryDirectory(prefix='ares-native-egress-') as folder:
        root = pathlib.Path(folder)
        config = {'external-controller': f'127.0.0.1:{api}', 'mixed-port': mixed, 'bind-address': '127.0.0.1',
                  'allow-lan': False, 'log-level': 'silent', 'dns': {'enable': False}, 'tun': {'enable': False},
                  'proxies': [
                      {'name': 'Entry', 'type': 'http', 'server': '127.0.0.1', 'port': entry.server_port},
                      {'name': 'Exit', 'type': 'http', 'server': '127.0.0.1', 'port': exit_proxy.server_port, 'dialer-proxy': 'Entry', 'interface-name': 'lo0'}],
                  'rules': ['MATCH,Exit'],
                  'listeners': [
                      {'name': 'Private HTTP', 'type': 'http', 'listen': '127.0.0.1', 'port': listener, 'proxy': 'DIRECT', 'users': [{'username': 'fixture', 'password': 'local-only'}]},
                      {'name': 'SOCKS', 'type': 'socks', 'listen': '127.0.0.1', 'port': socks, 'udp': True, 'proxy': 'DIRECT'}],
                  'tunnels': [
                      {'network': ['tcp'], 'address': f'127.0.0.1:{forward_tcp}', 'target': f'127.0.0.1:{origin.server_port}', 'proxy': 'DIRECT'},
                      {'network': ['udp'], 'address': f'127.0.0.1:{forward_udp}', 'target': f'127.0.0.1:{echo.server_address[1]}', 'proxy': 'DIRECT'}]}
        path = root / 'config.json'; path.write_text(json.dumps(config))
        for hold in reservations: hold.close()
        clean_env = {k: v for k, v in os.environ.items() if not k.lower().endswith('proxy')}
        with (root / 'core.log').open('wb') as log:
            process = subprocess.Popen([sys.argv[1], '-d', str(root), '-f', str(path)], env=clean_env, stdout=log, stderr=log)
            for _ in range(100):
                try:
                    with client.open(f'http://127.0.0.1:{api}/version', timeout=.2) as response:
                        assert '1.19.34' in json.load(response)['version']
                    break
                except OSError:
                    assert process.poll() is None, (root / 'core.log').read_text()
                    time.sleep(.05)
            else: raise AssertionError('Core did not start')
            def fetch(port, auth=None):
                req = urllib.request.Request(f'http://127.0.0.1:{origin.server_port}/')
                req.set_proxy(f'127.0.0.1:{port}', 'http')
                if auth: req.add_header('Proxy-Authorization', 'Basic ' + base64.b64encode(auth.encode()).decode())
                with client.open(req, timeout=5) as response: assert response.read() == b'ARES_EGRESS_FIXTURE'
            fetch(mixed)
            assert entry.visits == [exit_proxy.server_port], entry.visits
            assert exit_proxy.visits == [origin.server_port], exit_proxy.visits
            print('PASS: actual two-hop dialer-proxy chain Entry → Exit → origin')
            try: fetch(listener); raise AssertionError('Unauthenticated HTTP accepted')
            except urllib.error.HTTPError as error: assert error.code == 407
            fetch(listener, 'fixture:local-only')
            assert len(entry.visits) == 1, 'Listener proxy override ignored'
            print('PASS: HTTP listener authentication and DIRECT target independent of default rule')
            with socket.create_connection(('127.0.0.1', socks), timeout=3) as connection:
                connection.sendall(b'\x05\x01\x00'); assert connection.recv(2) == b'\x05\x00'
                connection.sendall(b'\x05\x01\x00\x01' + socket.inet_aton('127.0.0.1') + struct.pack('!H', origin.server_port))
                answer = connection.recv(32); assert answer[1] == 0, answer
                connection.sendall(b'GET / HTTP/1.0\r\nHost: fixture\r\n\r\n')
                data = b''
                while chunk := connection.recv(4096): data += chunk
                assert b'ARES_EGRESS_FIXTURE' in data
            with client.open(f'http://127.0.0.1:{forward_tcp}/', timeout=3) as response:
                assert response.read() == b'ARES_EGRESS_FIXTURE'
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                udp.settimeout(3); udp.sendto(b'ARES_UDP_FORWARD', ('127.0.0.1', forward_udp))
                assert udp.recvfrom(1024)[0] == b'ARES_UDP_FORWARD'
            print('PASS: SOCKS TCP, fixed TCP forwarding and real UDP forwarding')
            # SOCKS UDP association keeps its TCP control connection alive.
            with socket.create_connection(('127.0.0.1', socks), timeout=3) as control:
                control.sendall(b'\x05\x01\x00'); assert control.recv(2) == b'\x05\x00'
                control.sendall(b'\x05\x03\x00\x01' + b'\x00' * 6)
                response = control.recv(32); assert response[1] == 0, response
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
                    udp.settimeout(3)
                    header = b'\x00\x00\x00\x01' + socket.inet_aton('127.0.0.1') + struct.pack('!H', echo.server_address[1])
                    udp.sendto(header + b'ARES_SOCKS_UDP', ('127.0.0.1', socks))
                    assert udp.recvfrom(1024)[0].endswith(b'ARES_SOCKS_UDP')
            print('PASS: actual SOCKS UDP association and relay')
            # Test actual socket ownership without relying on API-ready alone.
            listing = subprocess.check_output(['/usr/sbin/lsof', '-nP', '-a', '-p', str(process.pid), '-i', '-F', 'pPn'], text=True)
            for port in [api, mixed, listener, socks, forward_tcp, forward_udp]: assert f':{port}' in listing, listing
            if len(sys.argv) > 2:
                subprocess.run([sys.argv[2], str(path), str(api), str(process.pid)], check=True)
            print('PASS: all configured sockets belong to the API core process')
finally:
    if process:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
    for server in [origin, entry, exit_proxy, echo]: server.shutdown(); server.server_close()
    for hold in reservations: hold.close()
    for port in [api, mixed, listener, socks, forward_tcp]:
        with socket.socket() as check: assert check.connect_ex(('127.0.0.1', port)) != 0
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as check: check.bind(('127.0.0.1', forward_udp))
    print('PASS: owned listeners/core cleaned up; host proxy, DNS and TUN untouched')
