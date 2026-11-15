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
assert source.count('const FORM_CONFIG') == 1 and source.count('<mark class="confirm">') == 8
assert 'form id="lead-form"' in source and 'accessKey:' in source
print(f'Static checks passed: {len(expected)} headings; 8 confirmations; FORM_CONFIG once')

threshold=int(os.environ.get('LAYOUT_MAX_ART_HEIGHT','420'))
instrument='''<script>(function(){const sections=[...document.querySelectorAll("main > section")],art=document.querySelector(".hero-art"),h1=document.querySelector("h1"),copy=document.querySelector(".hero-copy");const visible=e=>{const cs=getComputedStyle(e);return cs.display!=="none"&&cs.visibility!=="hidden"&&!e.closest("[aria-hidden=true],.honeypot,.grid-floor")};function lastContent(section){let last=-Infinity;const walker=document.createTreeWalker(section,NodeFilter.SHOW_TEXT);while(walker.nextNode()){const n=walker.currentNode;if(!n.textContent.trim()||!visible(n.parentElement))continue;const r=document.createRange();r.selectNodeContents(n);for(const box of r.getClientRects())last=Math.max(last,box.bottom+scrollY)}for(const el of section.querySelectorAll("img,input,select,textarea,button,video,canvas")){if(visible(el)){const b=el.getBoundingClientRect();last=Math.max(last,b.bottom+scrollY)}}return last}const data={scrollWidth:document.documentElement.scrollWidth,viewport:innerWidth,pageHeight:document.documentElement.scrollHeight,heroOrder:[...copy.children].map(e=>e.className||e.tagName.toLowerCase()),heroH1Top:h1.getBoundingClientRect().top+scrollY,artHeight:art.getBoundingClientRect().height,desktopSideBySide:getComputedStyle(document.querySelector(".hero-row")).flexDirection!=="column",sections:sections.slice(1).map((s,i)=>({id:s.id||s.querySelector("h2")?.textContent.trim(),gap:s.querySelector("h2").getBoundingClientRect().top+scrollY-lastContent(sections[i]),h2x:s.querySelector("h2").getBoundingClientRect().left}))};const out=document.createElement("pre");out.id="layout-measurements";out.textContent=JSON.stringify(data);document.body.append(out)})()</script>'''
path=root/'.task/layout-instrumented.html'; path.write_text(source.replace('</body>',instrument+'</body>'))
shots=[]
try:
 for width in (375,1280):
   viewport_height=812 if width==375 else 1000
   cmd=['/usr/bin/chromium','--headless','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--allow-file-access-from-files','--hide-scrollbars',f'--window-size={width},{viewport_height}','--virtual-time-budget=1200','--dump-dom',path.as_uri()]
   out=subprocess.run(cmd,capture_output=True,text=True,timeout=15,check=True).stdout
   class Measure(HTMLParser):
    def __init__(self): super().__init__(); self.on=False; self.data=''
    def handle_starttag(self,t,a):
     if dict(a).get('id')=='layout-measurements': self.on=True
    def handle_endtag(self,t):
     if t=='pre' and self.on: self.on=False
    def handle_data(self,d):
     if self.on: self.data+=d
   m=Measure(); m.feed(out); assert m.data, f'No measurements at {width}'
   d=json.loads(m.data)
   print(f'{width}px measurements: {json.dumps(d)}',flush=True)
   assert d['scrollWidth']<=d['viewport'], f'Overflow at {width}: {d}'
   assert all(s['gap']>=48 for s in d['sections']),f'Section content gap below 48px at {width}: {d["sections"]}'
   if width==375:
    expected_order=['p','h1','p','cta-row','p']; assert d['heroOrder'][:5]==expected_order, f'Hero order: {d["heroOrder"]}'
    assert d['heroH1Top']<250, f'H1 top >=250: {d["heroH1Top"]}'
    assert d['artHeight']<=threshold, f'image-height: hero art height {d["artHeight"]} exceeds {threshold}'
   else:
    assert d['desktopSideBySide'], 'Desktop hero is not side-by-side'
    xs=[s['h2x'] for s in d['sections']]; assert max(xs)-min(xs)<=2, f'Desktop h2 x misalignment: {xs}'
   print(f'{width}px measurements passed: overflow={d["scrollWidth"]}/{d["viewport"]}, gaps={[round(s["gap"]) for s in d["sections"]]}')
   with tempfile.NamedTemporaryFile(dir=root/'.task/shots',suffix='.png',delete=False) as tmp: temp_shot=Path(tmp.name)
   shot=['/usr/bin/chromium','--headless','--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--hide-scrollbars',f'--window-size={width},{d["pageHeight"]}','--virtual-time-budget=1000',f'--screenshot={temp_shot}',(root/'index.html').as_uri()]
   subprocess.run(shot,capture_output=True,timeout=15,check=True)
   with temp_shot.open('rb') as image: image.seek(16); dimensions=struct.unpack('>II',image.read(8))
   assert dimensions==(width,d['pageHeight']),f'Screenshot dimensions at {width}: {dimensions}, expected {(width,d["pageHeight"])}'
   shots.append((temp_shot,root/f'.task/shots/{width}.png'))
 for temp_shot,destination in shots: temp_shot.replace(destination)
finally:
 path.unlink(missing_ok=True)
 for temp_shot,_ in shots: temp_shot.unlink(missing_ok=True)
PY
echo "Layout checks elapsed runtime: ${SECONDS-start_time}s"
(( SECONDS-start_time < 30 )) || { echo 'Layout script exceeded 30 seconds' >&2; exit 1; }
