#!/usr/bin/env python3
"""Isolated guest/CI only. Never launches production app or modifies network settings."""
import base64, http.server, json, os, pathlib, select, socket, subprocess, sys, tempfile, threading, time, urllib.request, urllib.error
core, fixture = sys.argv[1], pathlib.Path(sys.argv[2])
client=urllib.request.build_opener(urllib.request.ProxyHandler({}))
class Origin(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'MANAGED_OK')
    def log_message(self,*args): pass
class Upstream(Origin):
    def do_CONNECT(self):
        host,port=self.path.rsplit(':',1)
        if host!='127.0.0.1' or int(port)!=origin.server_port: self.send_error(403);return
        self.server.visits+=1
        with socket.create_connection((host,int(port)),timeout=3) as upstream:
            self.send_response(200);self.end_headers()
            while True:
                ready,_,_=select.select([self.connection,upstream],[],[],2)
                if not ready:return
                for source in ready:
                    data=source.recv(65536)
                    if not data:return
                    (upstream if source is self.connection else self.connection).sendall(data)
origin=http.server.ThreadingHTTPServer(('127.0.0.1',0),Origin)
upstream=http.server.ThreadingHTTPServer(('127.0.0.1',29454),Upstream);upstream.visits=0
for server in [origin,upstream]:
    server.daemon_threads=True;threading.Thread(target=server.serve_forever,daemon=True).start()
proc=None
try:
 with tempfile.TemporaryDirectory(prefix='ares-managed-core-') as directory:
  path=pathlib.Path(directory)
  def start(mode):
    global proc
    if proc:proc.terminate();proc.wait(timeout=5)
    env={k:v for k,v in os.environ.items() if not k.lower().endswith('proxy')}
    with (path/'log').open('wb') as log:proc=subprocess.Popen([core,'-d',str(path),'-f',str(fixture/(mode+'.yaml'))],env=env,stdout=log,stderr=log)
    for _ in range(100):
      try:
        with client.open('http://127.0.0.1:29451/version',timeout=.2) as r:assert '1.19.34' in json.load(r)['version']
        return
      except OSError:
        assert proc.poll() is None,(path/'log').read_text();time.sleep(.05)
    raise AssertionError('startup timeout')
  def fetch(password='fixture-' + 'only-password'):
    req=urllib.request.Request(f'http://127.0.0.1:{origin.server_port}/')
    req.set_proxy('127.0.0.1:29453','http')
    if password is not None:req.add_header('Proxy-Authorization','Basic '+base64.b64encode(('fixture:'+password).encode()).decode())
    return client.open(req,timeout=4)
  start('enabled')
  for password in [None,'wrong-password']:
    try:fetch(password);raise AssertionError('bad credentials accepted')
    except urllib.error.HTTPError as e:assert e.code in (403,407)
  with fetch() as r:assert r.read()==b'MANAGED_OK'
  assert upstream.visits>0,'selected route was bypassed'
  with client.open('http://127.0.0.1:29451/providers/proxies') as r:assert 'Pool' in json.load(r)['providers']
  # Keep a tunnel open while checking core attribution.
  with socket.create_connection(('127.0.0.1',29453),timeout=3) as c:
    auth=base64.b64encode(b'fixture:fixture-only-password').decode()
    c.sendall(f'CONNECT 127.0.0.1:{origin.server_port} HTTP/1.1\r\nHost: fixture\r\nProxy-Authorization: Basic {auth}\r\n\r\n'.encode())
    assert b'200' in c.recv(4096)
    # CONNECT acknowledgement can precede outbound registration on macOS.
    # Send an incomplete HTTP request to establish real traffic without allowing
    # the origin to close the tunnel before we inspect its connection metadata.
    c.sendall(b'GET / HTTP/1.1\r\nHost: fixture\r\n')
    rows=[]
    for _ in range(40):
      with client.open('http://127.0.0.1:29451/connections',timeout=1) as r:rows=json.load(r).get('connections') or []
      if any(x['metadata'].get('inboundName')=='Ares Device 11111111-1111-1111-1111-111111111111' for x in rows):break
      time.sleep(.025)
    else:raise AssertionError([(x['metadata'].get('inboundName'),x['metadata'].get('type')) for x in rows])
  # SOCKS username/password authentication and TCP forwarding.
  with socket.create_connection(('127.0.0.1',29453),timeout=3) as c:
    c.sendall(b'\x05\x01\x02');assert c.recv(2)==b'\x05\x02'
    user=b'fixture';password=b'fixture-only-password'
    c.sendall(b'\x01'+bytes([len(user)])+user+bytes([len(password)])+password);assert c.recv(2)==b'\x01\x00'
    c.sendall(b'\x05\x01\x00\x01'+socket.inet_aton('127.0.0.1')+origin.server_port.to_bytes(2,'big'));assert c.recv(32)[1]==0
    c.sendall(b'GET / HTTP/1.0\r\nHost: fixture\r\n\r\n');data=b''
    while part:=c.recv(4096):data+=part
    assert b'MANAGED_OK' in data
  print('PASS: composed node/provider/policy, authenticated HTTP/SOCKS TCP, selected route and exact inbound attribution')
  start('blocked')
  try:
    with fetch() as r:assert r.read()!=b'MANAGED_OK'
  except (OSError,urllib.error.URLError):pass
  start('disabled')
  try:socket.create_connection(('127.0.0.1',29453),timeout=.3);raise AssertionError('disabled device still accepts connections')
  except OSError:pass
  print('PASS: reject route blocks traffic and disabled device removes listener')
finally:
 if proc and proc.poll() is None:proc.terminate();proc.wait(timeout=5)
 for server in [origin,upstream]:server.shutdown();server.server_close()
