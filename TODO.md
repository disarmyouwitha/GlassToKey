## TODO
- Can we flush memory after Config GUI is closed? It stays at like 50mb after guy like 10mb before
- Is there **ANY** way to refactor edit mode so it isn't laggy garbage? Is it possible to enable move & drag? It's specifically when a button or column is selected which cant be the problem because the green hit detection rect is so quick!
###
- Is the key matrix the most efficient? lets look deeper! How about KeyDispatch? And is key hit detection as clean as it could be?
- anayze custom button code vs key matrix detection, is it less efficient? If so can we fix?
- refactor 2 finger click?
- take over 2finger tap from BTT
- Refactor from the driver/api layer, any efficiency we can gain by rewrites?
- Have Codex refactor the code for compiler efficiency and runtime efficiency. Leave no stone unturned!
###
- Have Codex refactor the GUI for effiency
- Have Codex redesign the GUI for looks, keeping efficiency
###
- "Auto" set column x,y based on finger splay "4 finger touch"
- Toggle for capturing clicks using CGEventTapCreate??
- logic like phone that keeps a queue and triesto help correct out mistakes based on dictionary?
- If you want the next easy win: add frame coalescing (process only the latest touch frame if the actor is behind). That prevents queue buildup and keeps latency bounded.
- A tiny behavioral footgun in OpenMT listener cleanup
The new “remove dead listeners inline” avoids calling removeListener (which syncs to main and can stall), but it also means you might not stop handling multitouch events when the last listener disappears. That’s not correctness-breaking, but it’s a small energy/overhead leak unless handled elsewhere.
- Keyboard toggle/ keyboard only button. also, mouse only/keyboard only toggle button - how would you implement this?
######
Maybe on the same row as the Trackpad Deck, floating to the right we can add a "fingers" toggle? That way we can seperate editing the buttons from drawing the fingers, but still allow the user to toggle them on because it is important sometimes. 