/ =====================================================================
/ Data for the two README figures, computed in q and served to KX Dashboards
/ (q port of docs/figures.py, same algorithm, no Python needed).
/ Usage (from the repo root):  q docs/figures.q -p 5001
/   then in KX Dashboards: connection localhost:5001, one q query per series.
/ Tables built:
/   fanoTheo   w | n06 n08 n09 (theory F(T)) | plat06 plat08 plat09 | poisson
/   fanoSim    w | n06 n08 n09 (empirical Fano factor, one simulation per n)
/   exp1       r | cdf                       (Exp(1) reference curve)
/   residCont, residMs, residJit   r | ecdf  (residual CDF near 0, 3 cases)
/   ksTab      case | KS | KS5pct
/ The same tables are also written as CSV to docs/data/.
/ =====================================================================

\S 42
\l lib/hawkes.q

BETA:50f
logspace:{[a;b;k] 10 xexp a+(b-a)*(til k)%k-1}

/ ---------- figure 1: Fano factor vs window length ----------
/ theory: F(w) = 1 + (1/(1-n)^2 - 1) * (1 - (1 - exp(-k w)) / (k w)),  k = beta (1-n)
fanoTheory:{[n;be;w] k:be*1-n; 1+((1%(1-n)xexp 2)-1)*1-(1-exp neg k*w)%k*w}

/ empirical: Var/Mean of counts over consecutive windows of length w on [0,T).
/ Only non-empty windows are materialised (group), the empty ones enter through nb:
/ no 2e8-long count vector for w = 1 ms.
fanoEmp:{[t;T;w]
  nb:floor T%w;
  i:floor t%w; i:i where i<nb;
  m:count[i]%nb;
  c:"f"$value count each group i;
  ((sum[c*c]%nb)-m*m)%m}

Tf:2e5                                                     / long horizon for the Fano curve
ws:logspace[-3;1.3;30]                                     / windows for the simulation dots
wg:logspace[-3.3;1.5;200]                                  / fine grid for the theory curves

-1"simulating n = 0.6 0.8 0.9 on [0, 2e5 s) ...";
s06:hawkesBranch[1f;0.6*BETA;BETA;Tf]
s08:hawkesBranch[1f;0.8*BETA;BETA;Tf]
s09:hawkesBranch[1f;0.9*BETA;BETA;Tf]

nw:count wg
fanoTheo:([] w:wg;
  n06:fanoTheory[0.6;BETA;wg]; n08:fanoTheory[0.8;BETA;wg]; n09:fanoTheory[0.9;BETA;wg];
  plat06:nw#1%(1-0.6)xexp 2; plat08:nw#1%(1-0.8)xexp 2; plat09:nw#1%(1-0.9)xexp 2;
  poisson:nw#1f)

fanoSim:([] w:ws;
  n06:fanoEmp[s06;Tf] each ws; n08:fanoEmp[s08;Tf] each ws; n09:fanoEmp[s09;Tf] each ws)

/ ---------- figure 2: residual CDF near 0 (TSLA, n = 0.9) ----------
muR:1.2; alR:45f
tC:hawkesBranch[muR;alR;BETA;T]                            / continuous times
tM:0.001*"j"$1000*tC                                       / rounded to 1 ms
tJ:asc T&0|tM+0.001*-0.5+count[tM]?1f                      / ties spread within their ms

/ empirical CDF thinned to 1001 points (ecdf levels 0 .. 0.2), cut at r < 0.15
/ like the xlim of the Python figure: light enough for a browser chart
cdfPts:{[t]
  r:asc comp[t;muR;alR;BETA];
  N:count r;
  k:floor N*0.0002*til 1001;
  select from ([] r:r k; ecdf:(1+k)%N) where r<0.15}

residCont:cdfPts tC
residMs:cdfPts tM
residJit:cdfPts tJ
exp1:([] r:0.15*(til 301)%300; cdf:1-exp neg 0.15*(til 301)%300)

ksTab:([] case:`continuous`rounded_1ms`ties_spread;
  KS:ksStat each comp[;muR;alR;BETA] each (tC;tM;tJ);
  KS5pct:3#1.358%sqrt count tC)

-1"== KS on the residuals ==";
show ksTab;

/ ---------- CSV export (for any other charting tool) ----------
system"mkdir -p docs/data";
{(hsym `$"docs/data/",string[x],".csv") 0: csv 0: value x} each
  `fanoTheo`fanoSim`exp1`residCont`residMs`residJit`ksTab;
-1"CSV written to docs/data/";

/ ---------- serve the tables to KX Dashboards ----------
if[0=system"p"; system"p 5001"];
-1"ready: KX Dashboards connection localhost:",string system"p";
