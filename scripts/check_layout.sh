#!/usr/bin/env bash
set -euo pipefail
start_time=$SECONDS
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/.task/shots"
python3 - "$root" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import json, os, re, subprocess, sys, tempfile, struct

root = Path(sys.argv[1]); source = (root / 'index.html').read_text()
copy = (root / '.task/page-copy-from-docx.md').read_text()
expected = ['Fewer callbacks. Faster diagnosis. Fewer calls to your senior tech.', 'Every stuck tech costs you twice.', 'How it works', 'What your tech sees', 'Built for the owner, not just the tech', 'Where we are today', 'Try it free for 30 days', 'Start your free pilot', 'What happens to our data?', 'How accurate is it?', "Does it replace my techs' judgment?", "What doesn't it do?", 'Which equipment does it cover?', 'Can it connect to our software?', 'What does it cost after the pilot?', 'Your techs are going to get stuck this week anyway.']
class Text(HTMLParser):
    def __init__(self): super().__init__(); self.active=False; self.text=''; self.items=[]
    def handle_starttag(self,t,a):
        if t in {'h1','h2','h3'}: self.active=True; self.text=''
    def handle_endtag(self,t):
        if t in {'h1','h2','h3'} and self.active: self.items.append(' '.join(self.text.split())); self.active=False
    def handle_data(self,d):
        if self.active: self.text+=d
p=Text(); p.feed(source); headings=[next(w for w in expected if x.startswith(w)) for x in p.items if any(x.startswith(w) for w in expected)]
assert headings == expected, f'Heading/FAQ order mismatch: {headings}'
classes=set(token for group in re.findall(r'class="([^"]+)"',source) for token in group.split())
required={'hero-section','grid-floor','grid-floor-plane','hero-art-col','nav-pill','menu-toggle','eyebrow','how-section','timeline','timeline-row','timeline-rail','timeline-dot','timeline-line','timeline-title','timeline-body','mock-card','mock-inner','mock-label','mock-row','mock-title','mock-cite','mock-badge','scope-grid','scope-card','access-section','access-card','divider','footnote'}
assert required <= classes, f'Missing classes: {required-classes}'
for q in expected[8:15]: assert q in copy, f'Missing source-copy question: {q}'
assert not re.search(r'confirm\]|class="confirm"|\[optional', source, re.I)
assert 'EPA' not in source and 'Built by a working HVAC service technician who got tired of flipping through PDFs on a roof.' in source
assert source.count('const FORM_CONFIG') == 1
assert 'form id="lead-form"' in source and 'accessKey:' in source
print(f'Static checks passed: {len(expected)} headings; no confirmation marks or EPA; approved copy; FORM_CONFIG once')

threshold=int(os.environ.get('LAYOUT_MAX_ART_HEIGHT','420'))
instrument=r'''<script>
(async()=>{const frame=document.querySelector("iframe"),width=Number(new URLSearchParams(location.search).get("width"));
frame.style.width=width+"px";frame.style.height=(width===375?812:900)+"px";
await new Promise((resolve,reject)=>{frame.onload=resolve;frame.onerror=reject});
const w=frame.contentWindow,d=w.document; if(w.innerWidth!==width)throw Error(`iframe width ${w.innerWidth}, expected ${width}`);
await Promise.all([d.fonts.ready,...[...d.images].map(i=>i.decode().catch(()=>{}))]);
const y=e=>e.getBoundingClientRect().top+w.scrollY,visible=e=>{const c=w.getComputedStyle(e);return c.display!=="none"&&c.visibility!=="hidden"&&!e.closest('[aria-hidden="true"],.honeypot,.grid-floor')};
function last(s){let bottom=-Infinity;const walker=d.createTreeWalker(s,w.NodeFilter.SHOW_TEXT);while(walker.nextNode()){const n=walker.currentNode;if(!n.textContent.trim()||!visible(n.parentElement))continue;const range=d.createRange();range.selectNodeContents(n);for(const r of range.getClientRects())if(r.width&&r.height)bottom=Math.max(bottom,r.bottom+w.scrollY)}for(const n of s.querySelectorAll("img,input,select,textarea,button,video,canvas")){if(!visible(n))continue;const r=n.getBoundingClientRect();if(r.width&&r.height)bottom=Math.max(bottom,r.bottom+w.scrollY)}return bottom}
const sections=[...d.querySelectorAll("main > section")],data={viewport:w.innerWidth,scrollWidth:d.documentElement.scrollWidth,pageHeight:d.documentElement.scrollHeight,heroOrder:[...d.querySelector(".hero-copy").children].map(e=>e.className||e.tagName.toLowerCase()),heroH1Top:y(d.querySelector("h1")),artHeight:d.querySelector(".hero-art").getBoundingClientRect().height,desktopSideBySide:w.getComputedStyle(d.querySelector(".hero-row")).flexDirection!=="column",sections:sections.slice(1).map((s,i)=>({id:s.id||s.querySelector("h2")?.textContent.trim(),gap:y(s.querySelector("h2"))-last(sections[i]),h2x:s.querySelector("h2").getBoundingClientRect().left}))};
document.querySelector("pre").textContent=JSON.stringify(data);document.documentElement.dataset.ready="yes"})().catch(e=>{document.querySelector("pre").textContent=JSON.stringify({error:String(e)});document.documentElement.dataset.ready="yes"});
</script>'''
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import threading, urllib.parse
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(root),**kwargs)
 def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler); threading.Thread(target=server.serve_forever,daemon=True).start()
wrapper=root/'.task/layout-wrapper.html'; wrapper.write_text('<!doctype html><meta charset="utf-8"><style>body{margin:0}iframe{display:block;border:0}pre{display:none}</style><iframe src="/index.html"></iframe><pre></pre>'+instrument)
try:
 for width in (375,1280):
  url=f'http://127.0.0.1:{server.server_port}/.task/layout-wrapper.html?width={width}'
  cmd=['/usr/bin/chromium','--headless','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--hide-scrollbars','--window-size=500,950','--virtual-time-budget=2500','--dump-dom',url]
  out=subprocess.run(cmd,capture_output=True,text=True,timeout=12,check=True).stdout
  match=re.search(r'<pre>(.*?)</pre>',out,re.S); assert match,f'No measurement JSON for iframe {width}px'
  d=json.loads(match.group(1)); assert 'error' not in d,d.get('error')
  assert d['viewport']==width,f'iframe viewport mismatch {d}'
  print(f'{width}px iframe measurements: {json.dumps(d)}',flush=True)
  assert d['scrollWidth']<=d['viewport'],f'Overflow at {width}: {d}'
  assert all(s['gap']>=48 for s in d['sections']),f'Section content gap below 48px at {width}: {d["sections"]}'
  if width==375:
   assert d['heroH1Top']<250,f'H1 top >=250: {d["heroH1Top"]}'
   assert d['artHeight']<=threshold,f'hero-art height {d["artHeight"]} exceeds {threshold}'
  else:
   assert d['desktopSideBySide'],'Desktop hero is not side-by-side'
   xs=[s['h2x'] for s in d['sections']];assert max(xs)-min(xs)<=2,f'Desktop h2 x misalignment: {xs}'
  print(f'{width}px layout assertions passed: overflow, section gaps >=48px'+(', h1 and art height' if width==375 else ', heading alignment'),flush=True)
finally:
 server.shutdown();wrapper.unlink(missing_ok=True)
PY
echo "Layout checks elapsed runtime: ${SECONDS-start_time}s"
(( SECONDS-start_time < 30 )) || { echo 'Layout script exceeded 30 seconds' >&2; exit 1; }
