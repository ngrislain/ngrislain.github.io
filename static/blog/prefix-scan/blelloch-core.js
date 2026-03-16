/* ═══════════════════════════════════════════════════
   Blelloch parallel prefix scan — shared core
   Used by both integer and string visualizations.
   ═══════════════════════════════════════════════════ */

const N = 8, LOG = 3;

/* Layout constants (can be overridden before calling blellochInit) */
var CW = 95, RH = 56, PL = 72, PT = 32, PB = 24, NH = 26;

/* Colors */
const C = {
  active:   { f:'#ddf3fb', s:'#4dc9f6', t:'#0e6e8c' },
  inactive: { f:'#fde8ea', s:'#f67280', t:'#a03848' },
  summary:  { f:'#e4f2da', s:'#82c45e', t:'#3e6e20' },
  identity: { f:'#efefef', s:'#bbb',    t:'#888' },
};

/* ── State ── */
var stages = [], stepIdx = 0, playing = false, timer = null;

/* ── Mode-specific functions (set by blellochInit) ── */
var readInputs, identityVal, combineOp, formatNode, opSymbol, nodeWidth;
var msgs;
var svg;

/* ── Compute all stages ── */
function compute(x) {
  var n = x.length, log = LOG, st = [];
  var a = x.slice();

  /* 0: input */
  st.push({ ph:'input', lv:0, v:a.slice(), c:a.map(function(){return 'active'}), ops:[] });

  /* 1‥3: upsweep */
  for (var d = 0; d < log; d++) {
    var stride = 1 << (d+1), ops = [];
    var types = a.map(function(){return 'active'});
    for (var i = stride-1; i < n; i += stride) {
      var l = i - (stride>>1);
      ops.push({ src:l, dst:i });
      a[i] = combineOp(a[l], a[i]);
      types[l] = 'inactive';
      types[i] = 'summary';
    }
    st.push({ ph:'upsweep', lv:d+1, v:a.slice(), c:types, ops:ops });
  }

  /* 4: set root to identity */
  a[n-1] = identityVal;
  st.push({ ph:'set-root', lv:0, v:a.slice(),
    c: a.map(function(_,i){ return i===n-1 ? 'identity' : 'active' }),
    ops:[{ dst:n-1, identity:true }] });

  /* 5‥7: downsweep */
  for (var d = log-1; d >= 0; d--) {
    var stride = 1 << (d+1), ops = [];
    var types = a.map(function(){return 'active'});
    for (var i = stride-1; i < n; i += stride) {
      var l = i - (stride>>1);
      var tmp = a[l];
      a[l] = a[i];                     /* left child ← parent */
      a[i] = combineOp(a[i], tmp);     /* right child ← parent ⊕ old_left */
      ops.push({ src:i, dst:l, dst2:i, swap:true });
      types[l] = 'summary';
      types[i] = 'summary';
    }
    st.push({ ph:'downsweep', lv:d+1, v:a.slice(), c:types, ops:ops });
  }

  return st;
}

/* ── SVG helpers ── */
function mk(tag, a) {
  var e = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (var k in a) if (a.hasOwnProperty(k)) e.setAttribute(k, a[k]);
  return e;
}
function nx(col) { return PL + col * CW + CW/2; }
function ny(row) { return PT + row * RH + RH/2; }

function drawWireV(x, y1, y2, color, dashed) {
  var a = {x1:x,y1:y1,x2:x,y2:y2,stroke:color,'stroke-width':'1.5'};
  if (dashed) a['stroke-dasharray'] = '4,3';
  svg.appendChild(mk('line',a));
}

function drawWireL(x1, y1, x2, y2, midY, color, arrow, dashed) {
  var d = 'M'+x1+','+y1+' L'+x1+','+midY+' L'+x2+','+midY+' L'+x2+','+y2;
  var a = {d:d, fill:'none', stroke:color, 'stroke-width':'1.5'};
  if (arrow) a['marker-end'] = 'url(#ah)';
  if (dashed) a['stroke-dasharray'] = '4,3';
  svg.appendChild(mk('path',a));
  svg.appendChild(mk('circle',{cx:x1,cy:midY,r:'3',fill:'#fff',stroke:color,'stroke-width':'1.5'}));
}

function drawOpCircle(x, y) {
  svg.appendChild(mk('circle',{cx:x,cy:y,r:'7',fill:'#fff',stroke:'#555','stroke-width':'1.5'}));
  var t = mk('text',{x:x,y:y+1,'font-size': opSymbol.length > 1 ? '9' : '11',
    'font-weight':'800',fill:'#333','text-anchor':'middle','dominant-baseline':'central'});
  t.textContent = opSymbol;
  svg.appendChild(t);
}

/* ── Draw ── */
function draw() {
  var vis = stepIdx + 1;
  var svgW = PL + N*CW + 16;
  var svgH = PT + vis*RH + PB;
  svg.setAttribute('viewBox', '0 0 '+svgW+' '+svgH);
  svg.innerHTML = '';

  /* defs – arrowhead */
  var defs = mk('defs',{});
  var marker = mk('marker',{id:'ah',viewBox:'0 0 10 10',refX:'9',refY:'5',
    markerWidth:'5',markerHeight:'5',orient:'auto-start-reverse'});
  marker.appendChild(mk('path',{d:'M0 0L10 5L0 10z',fill:'#555'}));
  defs.appendChild(marker);
  svg.appendChild(defs);

  for (var s = 0; s < vis; s++) {
    var st = stages[s];
    var y0 = ny(s) - NH/2;
    var y1 = ny(s) + NH/2;

    /* Wires from previous row */
    if (s > 0) {
      var py1 = ny(s-1) + NH/2;
      var midY = (py1 + y0) / 2;

      var touched = {};
      for (var oi = 0; oi < st.ops.length; oi++) {
        var op = st.ops[oi];
        if (op.src !== undefined) touched[op.src] = true;
        if (op.dst !== undefined) touched[op.dst] = true;
        if (op.dst2 !== undefined) touched[op.dst2] = true;
      }
      for (var c = 0; c < N; c++) {
        if (!touched[c]) {
          svg.appendChild(mk('line',{
            x1:nx(c), y1:py1, x2:nx(c), y2:y0,
            stroke:'#ddd','stroke-width':'1','stroke-dasharray':'3,3'
          }));
        }
      }

      for (var oi = 0; oi < st.ops.length; oi++) {
        var op = st.ops[oi];
        if (op.identity) {
          drawWireV(nx(op.dst), py1, y0, '#555', false);
          var lt = mk('text',{x:nx(op.dst)+14, y:midY+3,
            'font-size':'11','font-weight':'700',fill:'#888',
            'text-anchor':'start','dominant-baseline':'central'});
          lt.textContent = 'e';
          svg.appendChild(lt);
        } else if (op.swap) {
          var xr = nx(op.src), xl = nx(op.dst);
          /* Right stays: vertical */
          drawWireV(xr, py1, y0, '#555', false);
          /* Right → Left: copy (green arrow) */
          drawWireL(xr, py1, xl, y0, midY, '#6abb6a', true);
          /* Left → Right: old_left feeds into sum (dashed) */
          drawWireL(xl, py1, xr, y0, midY - 6, '#aaa', false, true);
          /* Op circle on right destination */
          drawOpCircle(xr, y0);
        } else {
          /* Upsweep: src → dst */
          var xs = nx(op.src), xd = nx(op.dst);
          drawWireV(xd, py1, y0, '#555', false);
          drawWireL(xs, py1, xd, y0, midY, '#555', true);
          drawOpCircle(xd, y0);
        }
      }
    }

    /* Nodes */
    for (var c = 0; c < N; c++) {
      var col = C[st.c[c]] || C.active;
      var x = nx(c), y = ny(s);
      var label = formatNode(st.v[c], st.c[c]);
      var w = nodeWidth(label);
      var g = mk('g',{});
      g.appendChild(mk('rect',{
        x:x-w/2, y:y-NH/2, width:w, height:NH, rx:'4', ry:'4',
        fill:col.f, stroke:col.s, 'stroke-width':'1.5'
      }));
      var t = mk('text',{x:x, y:y+1, fill:col.t,
        'font-size':'12','font-weight':'700',
        'text-anchor':'middle','dominant-baseline':'central'});
      if (nodeFont) t.setAttribute('font-family', nodeFont);
      t.textContent = label;
      g.appendChild(t);
      svg.appendChild(g);
    }

    /* Row label */
    var rlabel = '';
    if (st.ph==='input') rlabel = 'Input';
    else if (st.ph==='upsweep') rlabel = 'Up '+st.lv;
    else if (st.ph==='set-root') rlabel = rootLabel;
    else if (st.ph==='downsweep' && s===stages.length-1) rlabel = 'Output';
    else if (st.ph==='downsweep') rlabel = 'Down '+st.lv;
    var lb = mk('text',{x:PL-8, y:ny(s)+1,
      'font-size':'11','font-weight':'700',fill:'#999',
      'text-anchor':'end','dominant-baseline':'central'});
    lb.textContent = rlabel;
    svg.appendChild(lb);
  }
}

/* ── Controls ── */
function reset() {
  stopPlay();
  var inp = readInputs();
  stages = compute(inp);
  stepIdx = 0;
  refresh();
}

function step() {
  if (stepIdx < stages.length-1) { stepIdx++; refresh(); }
  else stopPlay();
}

function togglePlay() {
  if (playing) { stopPlay(); return; }
  playing = true;
  btnPlay.classList.add('playing');
  btnPlay.innerHTML = '&#9646;&#9646; Pause';
  timer = setInterval(function(){
    if (stepIdx < stages.length-1) step(); else stopPlay();
  }, 800);
}

function stopPlay() {
  playing = false;
  clearInterval(timer);
  btnPlay.classList.remove('playing');
  btnPlay.innerHTML = '&#9654; Play';
}

function refresh() {
  draw();
  var st = stages[stepIdx];
  document.getElementById('phInput').classList.toggle('on', st.ph==='input');
  document.getElementById('phUp').classList.toggle('on', st.ph==='upsweep');
  document.getElementById('phDown').classList.toggle('on', st.ph==='downsweep'||st.ph==='set-root');
  var isDone = st.ph==='downsweep' && stepIdx===stages.length-1;
  document.getElementById('phDone').classList.toggle('on', isDone);
  var msg = msgs[st.ph];
  if (typeof msg === 'function') msg = msg(st, isDone);
  document.getElementById('stepInfo').textContent =
    'Step '+stepIdx+'/'+(stages.length-1)+': '+msg;
  document.getElementById('btnStep').disabled = stepIdx >= stages.length-1;
}

var btnStep, btnPlay, btnReset;
var rootLabel = 'Root\u21920';
var nodeFont = null;

/* ── Initialize ── */
function blellochInit(config) {
  /* Apply config */
  if (config.CW) CW = config.CW;
  if (config.identityVal !== undefined) identityVal = config.identityVal;
  combineOp = config.combineOp;
  readInputs = config.readInputs;
  formatNode = config.formatNode;
  opSymbol = config.opSymbol || '+';
  nodeWidth = config.nodeWidth || function() { return 48; };
  msgs = config.msgs;
  rootLabel = config.rootLabel || 'Root\u21920';
  nodeFont = config.nodeFont || null;

  svg = document.getElementById('canvas');
  btnStep = document.getElementById('btnStep');
  btnPlay = document.getElementById('btnPlay');
  btnReset = document.getElementById('btnReset');
  btnStep.addEventListener('click', step);
  btnPlay.addEventListener('click', togglePlay);
  btnReset.addEventListener('click', reset);
  for (var i = 0; i < N; i++)
    document.getElementById('x'+i).addEventListener('input', reset);

  reset();
}
