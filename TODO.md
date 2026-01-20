## TODO@
- haptics?
- trackpad battery level?
- Capture all 2-finger input
- key for enable/disable mouse
- two-finger-suppression branch, ignore all 2 finger events, don't send keys.
###
- random quote above textbox
- any vestigial code? legacyColumnSettings, etc..
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
- "Auto" set column x,y based on finger splay "4 finger touch" snapshot
- Toggle for capturing clicks using CGEventTapCreate??
- logic like phone that keeps a queue and triesto help correct out mistakes based on dictionary?
- Keyboard toggle/ keyboard only button. also, mouse only/keyboard only toggle button - how would you implement this?
###
In practice I notice I can move anywhere from 3-10 distance when typing, which I guess is
  why Drag Cancel 15 more or less works for me. Is there a better way? Velocity?

  Maybe when a tap starts, we wait before sending the keystroke for slider (ms) - if another keystroke
  follows, immediately send the key stroke (and the next), otherwise check the velocity since tap started to
  see how far the finger has traveled (slider).. if the finger is traveling, disqualify the keypress.