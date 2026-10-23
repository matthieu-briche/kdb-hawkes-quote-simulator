/ =====================================================================
/ Feed handler: receives the UDP datagrams published by feed.q -udp and
/ forwards them to the tickerplant, as an exchange feed handler does
/ between a multicast market-data feed and kdb+tick.
/ Usage: q fh.q [addr:port] [tpport]
/   addr:port: multicast group or unicast address to listen on, default 239.1.1.1:30001
/   tpport   : tickerplant port, default 5010
/ Needs KDB-X and the dot.udp module (see lib/mods.q): there is no UDP in plain q.
/ Exit code 2 when the module is missing, so that scripts can skip this path.
/ ---
/ Each datagram is (seq;columns), serialised with -8!. UDP does not guarantee
/ delivery or order, so the handler checks the sequence numbers:
/   .fh.gaps   number of gaps (one or more datagrams missing)
/   .fh.lost   datagrams missing in total
/   .fh.late   datagrams arriving with an old sequence number, dropped
/   .fh.stats[] all counters, e.g. h"fh.stats[]" from another process
/ A real feed handler would request the missing datagrams again (MoldUDP
/ re-request) or resynchronise from a snapshot; here gaps are only counted.
/ =====================================================================

\l lib/mods.q

udp:.mods.load`dot.udp
if[not count udp; -2"fh.q needs KDB-X and the dot.udp module"; exit 2]

ua:":" vs $[count .z.x; .z.x 0; "239.1.1.1:30001"]
addr:`$ua 0; port:"J"$last ua
if[(2<>count ua)|null port; -2"fh.q expects addr:port, e.g. 239.1.1.1:30001"; exit 1]
tpPort:$[1<count .z.x; .z.x 1; "5010"]
tp:@[hopen;`$"::",tpPort;{-2"tickerplant unreachable on port ",tpPort,": ",x; exit 1}]

.fh.seq:0; .fh.rows:0; .fh.gaps:0; .fh.lost:0; .fh.late:0
.fh.stats:{`datagrams`rows`gaps`lost`late!(.fh.seq;.fh.rows;.fh.gaps;.fh.lost;.fh.late)}

/ callback of the udp module: ips = (sender;destination) addresses, msg = the datagram bytes
.fh.recv:{[ips;msg]
  m:@[-9!;msg;{-2"fh: undecodable datagram (",x,")"; ()}];
  if[not 2=count m; :()];
  s:m 0;
  if[s<=.fh.seq; .fh.late+:1; :()];                         / duplicate or reordered: already past it
  if[s>1+.fh.seq; .fh.gaps+:1; .fh.lost+:s-1+.fh.seq;
    -2"fh: gap, ",string[s-1+.fh.seq]," datagram(s) missing before #",string s];
  .fh.seq:s;
  .fh.rows+:count first m 1;
  neg[tp](".u.upd";`quote;m 1);}

/ multicast groups are 224.0.0.0 to 239.255.255.255: join the group, otherwise plain unicast
mcast:("J"$first "." vs string addr) within 224 239
sock:udp[`ulisten][port;.fh.recv]
if[mcast; udp[`ujoin][sock;addr]]
-1"fh: listening on ",string[addr],":",string[port],$[mcast;" (multicast)";""],", forwarding to tickerplant port ",tpPort;
