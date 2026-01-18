## TODO
- In Edit mode can we draw touch frames much less frequently? Like taps should be instant but hold should only draw X Hz. (Can we expose a slider temporarily while I am testing the right value?)
- Is it possible to remove X,Y positioning enable move & drag? (Disable gesure input)
- Is it possible to remove Width/Height and enable drag to resize? (disable gesture input)
-   1. Add “Mouse Intent Window/Distance” sliders logging (recommended). 2. Add velocity-based intent gate instead of distance-only.
###
- Is the key matrix the most efficient? lets look deeper! How about KeyDispatch? And is key hit detection as clean as $it could be?
- analyze custom button code vs key matrix detection, is it less efficient? If so can we fix?
- take over 2finger tap from BTT?
- Refactor from the driver/api layer, any efficiency we can gain by rewrites?
- Have Codex refactor the code for compiler efficiency and runtime efficiency. Leave no stone unturned!
###
- Have Codex refactor the GUI for effiency
- Have Codex redesign the GUI for looks, keeping efficiency
###
- Can we stop using % in the GUI for x, y, width,height and use like PX or something that is based on its logical position and size?
- "Auto" set column x,y based on finger splay "4 finger touch"
- Toggle for capturing clicks using CGEventTapCreate??
- logic like phone that keeps a queue and triesto help correct out mistakes based on dictionary?
- If you want the next easy win: add frame coalescing (process only the latest touch frame if the actor is behind). That prevents queue buildup and keeps latency bounded.
- A tiny behavioral footgun in OpenMT listener cleanup
The new “remove dead listeners inline” avoids calling removeListener (which syncs to main and can stall), but it also means you might not stop handling multitouch events when the last listener disappears. That’s not correctness-breaking, but it’s a small energy/overhead leak unless handled elsewhere.
- Keyboard toggle/ keyboard only button. also, mouse only/keyboard only toggle button - how would you implement this?
######
Maybe on the same row as the Trackpad Deck, floating to the right we can add a "fingers" toggle? That way we can seperate editing the buttons from drawing the fingers, but still allow the user to toggle them on because it is important sometimes. 