import pathlib,json,subprocess,tempfile,socket,time,http.server,threading,urllib.request,urllib.error
import argparse
parser=argparse.ArgumentParser(description='Verify Broker routing using a real Mihomo binary and a local HTTP server.')
parser.add_argument('--mihomo',required=True,help='Path to the Mihomo executable')
parser.add_argument('--output',required=True,help='Directory for temporary config, provider, log and results')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
scratch=pathlib.Path(args.output).resolve();scratch.mkdir(parents=True,exist_ok=True)
(scratch/'Broker.list').write_bytes((root/'rules/Broker.list').read_bytes())
e=json.loads((root/'docs/huasheng-evidence.json').read_text())
positive=['web-api.hstbroker.com']+e['primary_domains']+e['compatibility_domains']+e['exact_hosts']
additions=json.loads((root/'docs/broker-additions-2026-10-31.json').read_text())['additions']
positive=list(dict.fromkeys(positive+[a['host'] for a in additions]+[a['rule'].split(',')[1] for a in additions]))
extra=json.loads((root/'docs/broker-followup-evidence-2026-10-31.json').read_text())['additions']
positive=list(dict.fromkeys(positive+[a['host'] for a in extra]+[a['rule'].split(',')[1] for a in extra]))
negative=['hstbroker.com.example.org','fakehstbroker.com','other.zszzcloud.com','other.tigerkickoff.com','schwabplan.com.evil.example','notlongbridge.cn','fakeitigergrowtha.com']
negative += [a['rule'].split(',')[1]+'.example.org' for a in extra]
negative += ['fake'+a['rule'].split(',')[1] for a in extra if a['rule'].startswith('DOMAIN-SUFFIX,')]
negative += ['child.'+a['host'] for a in extra if a['rule'].startswith('DOMAIN,')]
ibkr=json.loads((root/'tests/ibkr_cases.json').read_text())
positive=list(dict.fromkeys(positive+ibkr['positive']))
negative=list(dict.fromkeys(negative+ibkr['negative']))
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):self.send_response(200);self.end_headers();self.wfile.write(b'LOCAL_ROUTE_OK')
 def log_message(self,*a):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
with socket.socket() as s:s.bind(('127.0.0.1',0));controller_port=s.getsockname()[1]
c={'external-controller':f'127.0.0.1:{controller_port}','mixed-port':port,'bind-address':'127.0.0.1','allow-lan':False,'mode':'rule','log-level':'info','ipv6':False,'hosts':{h:'127.0.0.1' for h in positive+negative},'dns':{'enable':False},'profile':{'store-selected':False},'proxy-groups':[{'name':'Broker','type':'select','proxies':['DIRECT']}],'rule-providers':{'Broker':{'type':'file','behavior':'classical','format':'text','path':'Broker.list'}},'rules':['RULE-SET,Broker,Broker','MATCH,REJECT']}
f=scratch/'config.json';f.write_text(json.dumps(c))
cmd=[str(pathlib.Path(args.mihomo).resolve()),'-d',str(scratch),'-f',str(f)]
r=subprocess.run(cmd+['-t'],capture_output=True,text=True);print('CONFIG_TEST',r.returncode,r.stdout,r.stderr)
if r.returncode:raise SystemExit(1)
log=(scratch/'core.log').open('w');proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
results=[]
try:
 # A listening proxy socket does not guarantee that file providers have finished loading.
 expected_count=sum(bool(line.strip()) and not line.lstrip().startswith('#') for line in (scratch/'Broker.list').read_text().splitlines())
 opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 for _ in range(100):
  if proc.poll() is not None:raise RuntimeError('core exited before provider was ready')
  try:
   with opener.open(f'http://127.0.0.1:{controller_port}/providers/rules',timeout=.2) as response:
    provider=json.load(response).get('providers',{}).get('Broker',{})
   if provider.get('ruleCount')==expected_count:break
  except (OSError,urllib.error.URLError):pass
  time.sleep(.05)
 else:raise RuntimeError('Broker provider did not finish loading')
 for h in positive+negative:
  # 直接向本地 HTTP 代理发送 absolute-form，目标只访问本地测试服务。
  with socket.create_connection(('127.0.0.1',port),timeout=3) as sock:
   sock.settimeout(4);url=f'http://{h}:{server.server_port}/test'
   sock.sendall(f'GET {url} HTTP/1.1\r\nHost: {h}:{server.server_port}\r\nConnection: close\r\n\r\n'.encode())
   buf=b''
   try:
    while True:
     chunk=sock.recv(4096)
     if not chunk:break
     buf+=chunk
   except (TimeoutError,ConnectionResetError):pass
   ok=b'LOCAL_ROUTE_OK' in buf;expect=h in positive
   results.append({'host':h,'expected_broker':expect,'reached_local_server':ok,'pass':ok==expect})
finally:
 proc.terminate()
 try:proc.wait(timeout=5)
 except subprocess.TimeoutExpired:proc.kill();proc.wait()
 log.close();server.shutdown();server.server_close()
(scratch/'results.json').write_text(json.dumps(results,indent=2));assert all(x['pass'] for x in results)
print('PASS',len(results),'real-core route checks')
