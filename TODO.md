## TODO
- 4 finger tap chord click shift
- Mouse Grace (ms) where it stays in mouse state for X ms after last mouse event. no typing allowed but gestures yes!
- can we expose the slider for when click becomes double click?
- take screenshot for transparent stickers
- (Optional Install, CGEventFallback): Use Karabiner-DriverKit-VirtualHIDDevice to send keys!
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