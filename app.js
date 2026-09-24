const state={
  demo:true,
  paused:false,
  eas:[
    ["JetBoomer Core",true],
    ["Regime Filter",true],
    ["Risk Guardian",true],
    ["Execution Guard",true],
    ["Audit Engine",true]
  ],
  config:JSON.parse(localStorage.getItem("jetboomer-config")||"null")||{
    risk:.50,daily:2,dd:8,spread:25,positions:2,confidence:.68
  },
  log:JSON.parse(localStorage.getItem("jetboomer-log")||"[]")
};

const $=id=>document.getElementById(id);
function save(){localStorage.setItem("jetboomer-config",JSON.stringify(state.config));localStorage.setItem("jetboomer-log",JSON.stringify(state.log.slice(-100)))}
function toast(s){$("toast").textContent=s;clearTimeout(window._toast);window._toast=setTimeout(()=>$("toast").textContent="",4000)}
function addLog(msg){state.log.push(new Date().toLocaleString()+"  "+msg);save();renderLog()}
function renderLog(){$("log").textContent=state.log.slice(-100).reverse().join("\n")||"No events yet."}
function renderKPIs(){
 const items=state.demo
 ? [["Account feed","SIMULATION","Local only","info"],["Session P/L","—","Not connected",""],["Drawdown","—","Awaiting MT5",""],["AI confidence","—","Awaiting market feed","info"]]
 : [["Account feed","OFFLINE","MT5 bridge required","bad"],["Session P/L","—","No broker data",""],["Drawdown","—","No broker data",""],["AI confidence","—","No market feed","info"]];
 $("kpis").innerHTML=items.map(x=>`<div><small>${x[0]}</small><div class="kpi-value">${x[1]}</div><span class="${x[3]}">${x[2]}</span></div>`).join("");
}
function renderEas(){
 $("eas").innerHTML=state.eas.map((e,i)=>`<div class="ea-row"><div class="ea-name">${e[0]}</div><span class="status ${e[1]?"ok":"bad"}">● ${e[1]?"READY":"PAUSED"}</span><button class="toggle ${e[1]?"on":""}" data-ea="${i}" aria-label="Toggle ${e[0]}"></button></div>`).join("");
 document.querySelectorAll("[data-ea]").forEach(b=>b.onclick=()=>{const i=+b.dataset.ea;state.eas[i][1]=!state.eas[i][1];renderEas();addLog(state.eas[i][0]+(state.eas[i][1]?" enabled":" paused"));});
}
function loadConfig(){
 for(const id of ["risk","daily","dd","spread","positions","confidence"]) $(id).value=state.config[id];
}
function renderScores(values=[0,0,0,0,0,0]){
 const names=["Trend alignment","EMA structure","RSI","ADX regime","Candle quality","Momentum"];
 $("scores").innerHTML=names.map((n,i)=>`<div class="score"><span>${n}</span><div class="bar"><i style="width:${values[i]}%"></i></div><b>${values[i]}%</b></div>`).join("");
 const avg=Math.round(values.reduce((a,b)=>a+b,0)/values.length);
 $("scorePill").textContent=avg+"%";
}
function simulateSignal(){
 const vals=Array.from({length:6},()=>Math.floor(55+Math.random()*42));
 const avg=Math.round(vals.reduce((a,b)=>a+b,0)/6);
 const buy=Math.random()>.45;
 $("price").textContent=(1.17+Math.random()*.01).toFixed(5);
 $("signalText").textContent=buy?"BUY BIAS":"SELL BIAS";
 $("signalMeta").textContent=`Simulation confidence ${avg}% · regime: ${avg>72?"TRENDING":"MIXED"}`;
 $("marketMode").textContent="SIMULATION";
 renderScores(vals);addLog(`Simulation signal generated: ${buy?"BUY":"SELL"} bias @ ${avg}%`);
}
function draw(){
 const c=$("chart"),ctx=c.getContext("2d"),d=devicePixelRatio||1,r=c.getBoundingClientRect();
 c.width=r.width*d;c.height=r.height*d;ctx.setTransform(d,0,0,d,0,0);
 const w=r.width,h=r.height;ctx.clearRect(0,0,w,h);
 ctx.strokeStyle="#202837";ctx.lineWidth=1;
 for(let y=20;y<h;y+=45){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(w,y);ctx.stroke()}
 let pts=[],v=h*.60;for(let i=0;i<60;i++){v+=(-1+Math.random()*2)*5;v=Math.max(35,Math.min(h-25,v));pts.push(v)}
 ctx.beginPath();pts.forEach((y,i)=>{const x=i*w/(pts.length-1);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});
 ctx.strokeStyle="#5792ff";ctx.lineWidth=2;ctx.stroke();
}
$("modeBtn").onclick=()=>{
 state.demo=!state.demo;$("modeBtn").textContent=state.demo?"DEMO MODE":"LIVE / BRIDGE";
 $("modeBtn").classList.toggle("demo",state.demo);
 $("connection").className="connection "+(state.demo?"offline":"offline");
 $("connection span").textContent=state.demo?"MT5 BRIDGE OFFLINE":"MT5 BRIDGE OFFLINE";
 renderKPIs();toast(state.demo?"Demo mode enabled.":"Live controls require a deployed authenticated bridge.");addLog("Mode changed to "+(state.demo?"DEMO":"LIVE / BRIDGE"));
};
$("signalBtn").onclick=()=>state.demo?simulateSignal():toast("No broker market feed. Deploy the bridge first.");
$("refreshEas").onclick=()=>{renderEas();toast("Engine modules refreshed.");addLog("Engine modules refreshed");};
$("saveRisk").onclick=()=>{
 for(const id of ["risk","daily","dd","spread","positions","confidence"]) state.config[id]=Number($(id).value);
 save();toast("Local risk configuration saved.");addLog("Risk configuration saved locally");
};
document.querySelectorAll("[data-action]").forEach(b=>b.onclick=()=>{
 const a=b.dataset.action;
 if(!state.demo){toast("Blocked: authenticated MT5 bridge required.");addLog("BLOCKED command: "+a);return}
 if(a==="PANIC"){state.paused=true;state.eas.forEach(e=>e[1]=false);renderEas();toast("Local PANIC LOCK activated.");addLog("PANIC LOCK activated in demo");return}
 if(a==="PAUSE"){state.paused=true;state.eas.forEach(e=>e[1]=false);renderEas();toast("Local engine paused.");addLog("Engine paused in demo");return}
 toast(a+" recorded in demo only.");addLog("Demo command: "+a);
});
$("clearLog").onclick=()=>{state.log=[];save();renderLog();};
loadConfig();renderKPIs();renderEas();renderScores();renderLog();draw();addEventListener("resize",draw);
