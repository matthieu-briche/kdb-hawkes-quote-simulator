/ =====================================================================
/ Feed: replays one day of the "hdbq" HDB in accelerated time, so the
/ real-time stream is exactly a stored day.
/ Usage: q feed.q [speed] [date] [port] [-udp addr:port]
/   speed: acceleration, default 60 -> a 6h30 session replayed in 6 min 30 s
/   date : HDB partition to replay (YYYY.MM.DD), default the first day
/   port : tickerplant port, default 5010
/   -udp : publish UDP datagrams to addr:port (a multicast group such as
/          239.1.1.1:30001, or a unicast address) instead of calling the
/          tickerplant, the way an exchange feed does; fh.q turns them back
/          into .u.upd. Needs KDB-X and the dot.udp module (see lib/mods.q);
/          without them the feed falls back to TCP on the tickerplant port.
/ Requires hdbq (q hawkes_quotes.q) and a tickerplant (q tick/tp.q -p 5010).
/ =====================================================================

\l lib/hawkes.q
\l lib/mods.q

arg:{x til first where "-"=first each x,enlist"-"} .z.x     / positional arguments, before the first -option
opt:.Q.opt .z.x
tpPort:$[2<count arg; arg 2; "5010"]
spd:$[count arg; "F"$arg 0; 60f]

/ ---------- transport: UDP if asked for and available, TCP otherwise ----------
udp:$[`udp in key opt; .mods.load`dot.udp; ()]
if[(`udp in key opt)&not count udp; -1"-udp ignored: publishing to the tickerplant over TCP"];
if[count udp;
  ua:":" vs first opt`udp;
  uaddr:`$ua 0; uport:"J"$last ua;
  if[(2<>count ua)|null uport; -2"-udp expects addr:port, e.g. 239.1.1.1:30001"; exit 1]];
if[not count udp;
  h:@[hopen;`$"::",tpPort;{-2"tickerplant unreachable on port ",tpPort,": ",x; exit 1}]];

system"l hdbq";
dt:$[1<count arg; "D"$arg 1; first date]
if[not dt in date; -2"date not in the HDB: ",string dt; exit 1]

/ one day, all symbols, in global time order (xasc is stable); de-enumerate sym for IPC
day:`time xasc update sym:value sym from select time,sym,bid,ask,bsize,asize from quote where date=dt
-1"quotes to publish for ",string[dt],": ",string[count day],"  (speed x",string[spd],", ",
  $[count udp; "UDP to ",first opt`udp; "TCP to port ",tpPort],")";

/ ---------- publishers: x is a list of columns in schema order ----------
/ TCP: one async .u.upd per batch.
/ UDP: the batch is cut into datagrams of at most udpRows rows, each one carrying
/ its sequence number, (seq;columns) serialised with -8!, so that the feed handler
/ can detect lost or reordered datagrams, like the sequence numbers of MoldUDP/ITCH.
udpRows:200                                                / about 10 KB per datagram, well under the 64 KB limit
udpMax:20                                                  / datagrams per timer tick: a burst larger than the
                                                           / receiver's socket buffer would be dropped by the kernel
seq:0
pubTcp:{neg[h](".u.upd";`quote;x)}
pubUdp:{[x] {[x;i] seq::seq+1; udp[`usend][uaddr;uport;-8!(seq;x@\:i)]}[x] each udpRows cut til count first x}
pub:$[count udp; pubUdp; pubTcp]

/ ---------- accelerated replay: every 100 ms, send the quotes already "due" ----------
/ In UDP mode at most udpRows*udpMax rows leave per tick: at high speed the replay
/ lags behind the simulated clock instead of flooding the receiver.
pos:0
t0:.z.P
maxRows:$[count udp; udpRows*udpMax; count day]
.z.ts:{
  tsim:sessOpen+"n"$spd*"j"$.z.P-t0;                       / simulated clock
  j:(pos+maxRows-1)&day[`time] bin tsim;                   / last quote <= simulated clock, capped
  if[j>=pos;
    pub value flip day pos+til 1+j-pos;
    pos::j+1];
  if[pos>=count day;
    -1"day published: ",string[count day]," quotes",$[count udp; " in ",string[seq]," datagrams"; ""];
    system"t 0"]}
\t 100
