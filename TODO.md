## TODO
- anayze custom button code vs key matrix detection, is it less efficient? If so can we fix?
- refactor 2 finger click?
- take over 2finger tap from BTT
- Refactor from the driver/api layer, any efficiency we can gain by rewrites?
- Have Codex refactor the code for compiler efficiency and runtime efficiency. Leave no stone unturned!
- Have Codex refactor the GUI for effiency
- "Auto" set column x,y based on finger splay "4 finger touch"
- Toggle for capturing clicks using CGEventTapCreate??
- logic like phone that keeps a queue and triesto help correct out mistakes based on dictionary?
- If you want the next easy win: add frame coalescing (process only the latest touch frame if the actor is behind). That prevents queue buildup and keeps latency bounded.
- A tiny behavioral footgun in OpenMT listener cleanup
The new “remove dead listeners inline” avoids calling removeListener (which syncs to main and can stall), but it also means you might not stop handling multitouch events when the last listener disappears. That’s not correctness-breaking, but it’s a small energy/overhead leak unless handled elsewhere.
- Keyboard toggle/ keyboard only button. also, mouse only/keyboard only toggle button - how would you implement this?