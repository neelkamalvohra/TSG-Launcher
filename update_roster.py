import json, psycopg2

NEW_JS = r"""
// Roster HTML Builder - Mobile Optimised v3
const webhookData = $('Your WebPage').item.json || {};
const selectedDate = webhookData.query?.date ||
  new Date(new Date().toLocaleString("en-US",{timeZone:"Asia/Kolkata"})).toISOString().split('T')[0];
const rosterData = $input.all();

const PRIORITY = {A:1,AWH:1.5,B:2,BWH:2.5,WO:3,L:4,G:5};

function shiftDisplay(s){
  const u=(s||'').toUpperCase();
  return u==='AWH'?'A (WFH)':u==='BWH'?'B (WFH)':(s||'N/A');
}
function shiftCls(s){
  const u=(s||'').toUpperCase();
  if(u==='A'||u==='AWH') return 'shift-a';
  if(u==='B'||u==='BWH') return 'shift-b';
  if(u==='WO') return 'shift-wo';
  if(u==='L')  return 'shift-l';
  if(u==='G')  return 'shift-g';
  return 'shift-unknown';
}
function fmtDate(ds){
  const d=new Date(ds+'T00:00:00');
  return d.toLocaleDateString('en-US',{weekday:'short',day:'numeric',month:'short',year:'numeric'});
}
function addDays(ds,n){
  const d=new Date(ds+'T00:00:00');
  d.setDate(d.getDate()+n);
  return d.toISOString().split('T')[0];
}

const valid=(rosterData||[]).filter(i=>i.json&&i.json.employee_name);
const employeeCount=valid.length;
let gShiftCount=0;
let tableRows='';

const EMPTY=`<tr><td colspan="5">
  <div class="empty-state">
    <span class="empty-icon">📅</span>
    <div class="empty-title">No roster data</div>
    <div class="empty-sub">No employees scheduled for this date</div>
  </div>
</td></tr>`;

if(valid.length>0){
  const sorted=[...valid].sort((a,b)=>
    (PRIORITY[(a.json.shift||'').toUpperCase()]||999)-
    (PRIORITY[(b.json.shift||'').toUpperCase()]||999)
  );
  const nonG=sorted.filter(i=>(i.json.shift||'').toUpperCase()!=='G');
  const gArr=sorted.filter(i=>(i.json.shift||'').toUpperCase()==='G');
  gShiftCount=gArr.length;

  let idx=1;
  function makeRow(item,hidden){
    const d=item.json;
    const ph=d.mobile?`<a href="tel:${d.mobile}" class="ph-lnk">${d.mobile}</a>`:'N/A';
    const em=d.email ?`<a href="mailto:${d.email}" class="em-lnk">${d.email}</a>`:'N/A';
    const hAttr=hidden?' style="display:none"':'';
    const gCls=hidden?' g-row':'';
    return `<tr class="r-row${gCls}"${hAttr}>
  <td class="num" data-label="">${idx++}</td>
  <td class="nm"  data-label="Name">${d.employee_name||'N/A'}</td>
  <td data-label="Shift"><span class="badge ${shiftCls(d.shift)}">${shiftDisplay(d.shift)}</span></td>
  <td data-label="Mobile">${ph}</td>
  <td class="em-col" data-label="Email">${em}</td>
</tr>`;
  }

  tableRows=nonG.map(i=>makeRow(i,false)).join('');
  if(gShiftCount>0){
    tableRows+=`<tr class="g-tog-row"><td colspan="5">
  <button class="g-tog-btn" id="g-btn" onclick="toggleG()">
    👁 Show G Shift (${gShiftCount})
  </button>
</td></tr>`;
    tableRows+=gArr.map(i=>makeRow(i,true)).join('');
  }
} else {
  tableRows=EMPTY;
}

const prevDateStr=addDays(selectedDate,-1);
const nextDateStr=addDays(selectedDate,+1);
const displayDate=fmtDate(selectedDate);
const istTime=new Date().toLocaleString('en-IN',{timeZone:'Asia/Kolkata',dateStyle:'medium',timeStyle:'short'});

const html=`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>TSG Roster</title>
<style>
:root{
  --bg:linear-gradient(135deg,#667eea,#764ba2);
  --card:#fff;--txt:#1a1a2e;--sub:#4a5568;--muted:#718096;
  --bdr:#e2e8f0;--hvr:rgba(59,130,246,.08);--acc:#3b82f6;
  --hdr:linear-gradient(135deg,#3b82f6,#7c3aed);
  --shd:0 4px 24px rgba(0,0,0,.12);
}
[data-theme=dark]{
  --bg:linear-gradient(135deg,#1a1a2e,#16213e,#0f3460);
  --card:#1e2433;--txt:#f0f4ff;--sub:#c4cce0;--muted:#8896b0;
  --bdr:#2d3a52;--hvr:rgba(99,179,237,.1);--acc:#60a5fa;
  --shd:0 4px 24px rgba(0,0,0,.4);
}
*{margin:0;padding:0;box-sizing:border-box}
html,body{max-width:100%;overflow-x:hidden}
body{
  font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
  background:var(--bg);min-height:100vh;padding:8px;
}
.wrap{
  max-width:900px;margin:0 auto;background:var(--card);
  border-radius:16px;overflow:hidden;box-shadow:var(--shd);
  animation:fi .4s ease;
}

/* HEADER */
.hdr{
  background:var(--hdr);color:#fff;
  padding:14px 12px 12px;text-align:center;position:relative;
}
.thm-btn{
  position:absolute;top:10px;right:10px;
  background:rgba(255,255,255,.18);border:none;border-radius:50%;
  width:36px;height:36px;cursor:pointer;font-size:17px;
  display:flex;align-items:center;justify-content:center;transition:.2s;z-index:2;
}
.thm-btn:hover{background:rgba(255,255,255,.3);transform:scale(1.1)}
.ttl{
  font-size:1.1rem;font-weight:700;line-height:1.3;
  padding:0 46px 10px;
  text-shadow:0 2px 6px rgba(0,0,0,.2);
}

/* DATE ROW */
.d-row{
  display:flex;align-items:center;justify-content:center;gap:10px;
  background:rgba(255,255,255,.13);border-radius:50px;
  padding:7px 14px;margin:0 auto;
  width:fit-content;max-width:calc(100% - 12px);
}
.nav-btn{
  background:rgba(255,255,255,.2);border:none;border-radius:50%;
  width:34px;height:34px;min-width:34px;cursor:pointer;
  font-size:13px;color:#fff;
  display:flex;align-items:center;justify-content:center;
  transition:.2s;flex-shrink:0;
}
.nav-btn:hover{background:rgba(255,255,255,.32);transform:scale(1.08)}
.nav-btn:active{transform:scale(.93)}
.d-lbl{
  font-size:.9rem;font-weight:700;color:#ffd166;
  cursor:pointer;padding:4px 8px;border-radius:8px;
  user-select:none;white-space:nowrap;transition:background .2s;
}
.d-lbl:hover{background:rgba(255,255,255,.15)}
.d-lbl::after{content:' 📅';font-size:.75em;opacity:.8}
#dp{position:absolute;opacity:0;pointer-events:none;width:0;height:0;top:0;left:0}

/* TABLE WRAPPER */
.body{padding:12px 8px 8px}
.tbl-w{
  border-radius:10px;overflow:hidden;
  border:1px solid var(--bdr);
  box-shadow:0 2px 8px rgba(0,0,0,.06);
  width:100%;
}

/* TABLE — desktop (>700px): all 5 columns */
table{
  width:100%;border-collapse:collapse;
  table-layout:fixed;
}
col.c-num  {width:34px}
col.c-name {width:auto}
col.c-shft {width:82px}
col.c-mob  {width:118px}
col.c-em   {width:170px}

thead{background:var(--hdr);color:#fff}
thead th{
  padding:10px 8px;font-size:.7rem;font-weight:700;
  text-transform:uppercase;letter-spacing:.5px;text-align:left;
  overflow:hidden;white-space:nowrap;
}
thead th:first-child{text-align:center}
tbody tr{border-bottom:1px solid var(--bdr);transition:background .15s}
tbody tr:last-child{border-bottom:none}
tbody tr:hover{background:var(--hvr)}
td{
  padding:9px 8px;font-size:.84rem;color:var(--txt);
  vertical-align:middle;overflow:hidden;
}
.num{font-weight:700;color:var(--acc);text-align:center;font-size:.78rem}
.nm{font-weight:600;word-break:break-word}
.badge{
  display:inline-block;padding:3px 8px;border-radius:20px;
  font-size:.73rem;font-weight:700;text-transform:uppercase;
  letter-spacing:.3px;white-space:nowrap;
}
.shift-a{background:#ffe0e9;color:#be185d}
.shift-b{background:#d0f4f8;color:#0e7490}
.shift-wo{background:#dcfce7;color:#15803d}
.shift-l{background:#fef9c3;color:#a16207}
.shift-g,.shift-unknown{background:#f1f5f9;color:#64748b}
[data-theme=dark] .shift-a{background:#4a1225;color:#fda4af}
[data-theme=dark] .shift-b{background:#0c3040;color:#67e8f9}
[data-theme=dark] .shift-wo{background:#052e16;color:#86efac}
[data-theme=dark] .shift-l{background:#422006;color:#fde68a}
[data-theme=dark] .shift-g,[data-theme=dark] .shift-unknown{background:#1e293b;color:#94a3b8}
.ph-lnk,.em-lnk{color:var(--acc);text-decoration:none;font-size:.8rem;word-break:break-all}
.ph-lnk:hover,.em-lnk:hover{text-decoration:underline}

/* G-shift toggle */
.g-tog-row td{text-align:center;padding:8px;background:var(--hvr)}
.g-tog-btn{
  background:var(--acc);color:#fff;border:none;border-radius:20px;
  padding:6px 16px;font-size:.78rem;font-weight:700;cursor:pointer;transition:.2s;
}
.g-tog-btn:hover{opacity:.85;transform:scale(1.04)}

/* empty state */
.empty-state{text-align:center;padding:36px 16px}
.empty-icon{font-size:2rem;display:block;margin-bottom:8px}
.empty-title{font-size:.9rem;font-weight:600;color:var(--sub);margin-bottom:4px}
.empty-sub{font-size:.8rem;color:var(--muted)}

/* ── NARROW TABLE (≤700px, >480px): hide email, fit 4 cols ── */
@media(max-width:700px){
  col.c-em{width:0}
  .em-col,thead th:nth-child(5){display:none}
  col.c-num  {width:30px}
  col.c-shft {width:78px}
  col.c-mob  {width:108px}
}

/* ── CARD LAYOUT (≤480px) ── */
@media(max-width:480px){
  table,thead,tbody,th,td,tr{display:block}
  thead{display:none}
  .tbl-w{border:none;background:transparent;box-shadow:none;border-radius:0;overflow:visible}
  tbody tr.r-row{
    background:var(--card);border:1px solid var(--bdr);
    border-radius:12px;margin-bottom:8px;padding:11px 13px;
    position:relative;box-shadow:0 1px 4px rgba(0,0,0,.07);
  }
  td{
    padding:3px 0;display:flex;align-items:flex-start;
    font-size:.87rem;border:none !important;
  }
  td::before{
    content:attr(data-label);
    font-weight:700;font-size:.67rem;text-transform:uppercase;
    letter-spacing:.4px;color:var(--muted);
    min-width:56px;padding-top:2px;flex-shrink:0;
  }
  td.num{position:absolute;top:10px;right:11px;padding:0;font-size:.75rem;font-weight:700;color:var(--acc)}
  td.num::before{display:none}
  td.nm{
    display:block;font-size:.97rem;font-weight:700;
    padding-bottom:7px !important;padding-right:32px !important;
    border-bottom:1px solid var(--bdr) !important;margin-bottom:4px;
  }
  td.nm::before{display:none}
  /* Show email in card mode */
  .em-col{display:flex !important}
  .g-tog-row,.g-tog-row td{
    display:block;border:none !important;padding:5px 0 !important;background:transparent;
  }
  .g-tog-row td::before{display:none}
}

/* FOOTER */
.foot{
  text-align:center;padding:10px;font-size:.72rem;
  color:var(--muted);border-top:1px solid var(--bdr);
}

@keyframes fi{
  from{opacity:0;transform:translateY(12px)}
  to{opacity:1;transform:translateY(0)}
}
</style>
</head>
<body>
<div class="wrap">
  <div class="hdr">
    <button class="thm-btn" onclick="toggleTheme()" id="thm-btn">🌙</button>
    <div class="ttl">Technical Support Group<br>(Roster)</div>
    <div class="d-row">
      <button class="nav-btn" onclick="goDate('${prevDateStr}')" title="Prev">&#9664;</button>
      <span class="d-lbl" onclick="openDP()">${displayDate}</span>
      <input type="date" id="dp" value="${selectedDate}" onchange="goDate(this.value)">
      <button class="nav-btn" onclick="goDate('${nextDateStr}')" title="Next">&#9654;</button>
    </div>
  </div>

  <div class="body">
    <div class="tbl-w">
      <table>
        <colgroup>
          <col class="c-num"><col class="c-name"><col class="c-shft">
          <col class="c-mob"><col class="c-em">
        </colgroup>
        <thead>
          <tr>
            <th>#</th><th>Employee Name</th><th>Shift</th>
            <th>Mobile</th><th>Email</th>
          </tr>
        </thead>
        <tbody>${tableRows}</tbody>
      </table>
    </div>
  </div>

  <div class="foot">⏰ ${istTime} &nbsp;·&nbsp; Made by Neel</div>
</div>

<script>
let theme='dark';
(function(){
  try{theme=localStorage.getItem('roster-theme')||'dark';}catch(e){}
  applyT(theme);
})();
function applyT(t){
  document.documentElement.setAttribute('data-theme',t);
  document.getElementById('thm-btn').textContent=t==='dark'?'☀️':'🌙';
}
function toggleTheme(){
  theme=theme==='dark'?'light':'dark';
  applyT(theme);
  try{localStorage.setItem('roster-theme',theme);}catch(e){}
}
function openDP(){
  const i=document.getElementById('dp');
  try{i.showPicker();}catch(e){i.click();}
}
let gVis=false;
function toggleG(){
  gVis=!gVis;
  document.querySelectorAll('.g-row').forEach(r=>{r.style.display=gVis?'':'none';});
  const b=document.getElementById('g-btn');
  if(b) b.textContent=gVis?'🙈 Hide G Shift (${gShiftCount})':'👁 Show G Shift (${gShiftCount})';
}
function goDate(d){
  document.querySelector('.wrap').style.opacity='.5';
  window.location.href=window.location.pathname+'?date='+encodeURIComponent(d);
}
document.addEventListener('keydown',e=>{
  if(e.key==='ArrowLeft') goDate('${prevDateStr}');
  else if(e.key==='ArrowRight') goDate('${nextDateStr}');
  else if(e.key==='t'||e.key==='T') toggleTheme();
});
</script>
</body>
</html>`;

return [{json:{html, selectedDate, employeeCount}}];
"""
conn = psycopg2.connect(
    host="postgres_n8n", port=5432,
    dbname="n8n_db", user="n8n_user", password="CHANGE_ME_n8n_pg_password"
)
cur = conn.cursor()

cur.execute("SELECT nodes FROM workflow_entity WHERE id = '19Qpg3xDx37sOvoM'")
row = cur.fetchone()
if not row:
    raise Exception("Workflow 19Qpg3xDx37sOvoM not found")

nodes = row[0]  # already parsed as list by psycopg2

updated = False
for node in nodes:
    if node.get("name") == "HTML Builder":
        node["parameters"]["jsCode"] = NEW_JS.strip()
        updated = True
        break

if not updated:
    raise Exception("HTML Builder node not found in workflow")

cur.execute(
    "UPDATE workflow_entity SET nodes = %s WHERE id = '19Qpg3xDx37sOvoM'",
    [json.dumps(nodes)]
)
conn.commit()
cur.close()
conn.close()
print("SUCCESS: Roster_Web_Service HTML Builder updated.")
