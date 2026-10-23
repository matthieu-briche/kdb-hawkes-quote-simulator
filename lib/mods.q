/ =====================================================================
/ Optional KDB-X modules, with a pure-q fallback.
/ .mods.load[`dot.udp] returns the module's dictionary of functions, or ()
/ when it cannot be loaded: plain kdb+ 4.x has no `use`, or the module is not
/ installed in the KDB-X mod directory (https://github.com/adotsch/kdb-x).
/ Callers test `count` on the result and keep their pure-q path otherwise,
/ so the project still runs on the free kdb+ personal edition.
/ =====================================================================

.mods.load:{[m]
  @[{use x};m;{[m;e] -1"module ",string[m]," not available (",e,"): pure-q fallback"; ()}[m]]}
