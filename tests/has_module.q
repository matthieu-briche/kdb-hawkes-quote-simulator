/ Exit code 0 if the KDB-X module given as argument can be loaded, 1 otherwise.
/ Usage (from the repository root):  q tests/has_module.q dot.udp
\l lib/mods.q
exit $[count .mods.load `$.z.x 0; 0; 1]
