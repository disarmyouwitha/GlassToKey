## TODO
- I been thinking.. we currently draw 2 trackpads in 2 seperate canvases and draw them seperately.. (I can tell when I put a finger on each trackpad it bounces back and forth between which one draws) It seems much smarter to have 1 canvas and draw both trackpads on it? (we could draw a rect around each one). Thoughts?
-   1. Add “Mouse Intent Window/Distance” sliders logging (recommended). 2. Add velocity-based intent gate instead of distance-only.
###

About mouse vs keyboard intent

  - A better signal than just drag-cancel is usually a “mouse intent window”: if movement exceeds X within the first Y ms, disqualify as mouse; otherwise allow keyboard. This catches quick cursor nudges without killing taps/holds. We can add two sliders: Mouse Intent Window (ms) and Mouse Intent Distance (mm).
  - Another option: “hold-to-type window”: require movement to stay under a tiny threshold for the first N ms before classifying as keyboard, but still allow later wiggle. This reduces accidental mouse taps.
  - You can also incorporate velocity (distance / time) rather than raw distance; fast motion early is a strong mouse signal even if distance is small.

  If you want, I can wire those thresholds as live sliders + logs next.


  Next steps

  1. Add “Mouse Intent Window/Distance” sliders + logging (recommended).
  2. Add velocity-based intent gate instead of distance-only.


Please wire up those controls for me to play with! 3. add hold-to-type window slider too! If it is 
conflicting set it to 0 so I can at least try it. Build to make sure it all works!,
###
- Can we have Backspace use Drag Cancel + 10 to give more wiggle room for that specific button?
- Is it possible to remove X,Y positioning enable move & drag? Is it possible to remove Width/Height and enable drag to resize? (Disable drawing touches with a toggle initially?)
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
- A tiny behavioral footgun in OpenMT listener cleanup: The new “remove dead listeners inline” avoids calling removeListener (which syncs to main and can stall), but it also means you might not stop handling multitouch events when the last listener disappears. That’s not correctness-breaking, but it’s a small energy/overhead leak unless handled elsewhere.
- Keyboard toggle/ keyboard only button. also, mouse only/keyboard only toggle button - how would you implement this?
######
Maybe on the same row as the Trackpad Deck, floating to the right we can add a "fingers" toggle? That way we can seperate editing the buttons from drawing the fingers, but still allow the user to toggle them on because it is important sometimes. 