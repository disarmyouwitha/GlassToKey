## TODO
- make toggle for Chordal Shift
- The only efficiency improvement I’d consider: fold chord‑shift contact counting into
    updateIntentGlobal (it already scans both sides). Right now we do a small extra pass per side
    just to count touches, which is still O(n) and very cheap, but can be shaved if we want to be
    extremely tight.
  - Bottom line: keeping it in TouchProcessor is the right place for low latency + low
    allocations. If you want micro‑optimizations, we can merge counting into the existing pass.
###
- take screenshot for transparent stickers
- (Optional Install, CGEventFallback):
- Use Karabiner-DriverKit-VirtualHIDDevice to send keys!
- normalize % to px??
###
- any vestigial code?  
- Is the key matrix the most efficient? lets look deeper! How about KeyDispatch? And is key hit detection as clean as $it could be?
- analyze custom button code vs key matrix detection, is it less efficient? If so can we fix?
- Refactor from the driver/api layer, any efficiency we can gain by rewrites?
- Have Codex refactor the code for compiler efficiency and runtime efficiency. Leave no stone unturned!
- Have Codex refactor the GUI for effiency
- Have Codex redesign the GUI for looks, keeping efficiency
###
- "Auto" set column x,y based on finger splay "4 finger touch" snapsMetro

# blood for the blood god:
- we will need to refractor gestures / gestures candidate now.,, lol
- shift frame gets updated a ton, should it just fset a flag on key up key down?


# bettr auto complete: feed it my resurrection buffer for better results??


# Karabiner stuck, help!
sudo launchctl kickstart -k system/org.pqrs.vhid 