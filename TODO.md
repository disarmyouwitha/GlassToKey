## TODO
- Use Karabiner-DriverKit-VirtualHIDDevice to send keys!
###

# bettr auto complete: feed it my resurrection buffer for better results??

- normalize % to px??
- any vestigial code?  
- Is the key matrix the most efficient? lets look deeper! How about KeyDispatch? And is key hit detection as clean as $it could be?
- analyze custom button code vs key matrix detection, is it less efficient? If so can we fix?
- Refactor from the driver/api layer, any efficiency we can gain by rewrites?
- Have Codex refactor the code for compiler efficiency and runtime efficiency. Leave no stone unturned!
- Have Codex refactor the GUI for effiency
- Have Codex redesign the GUI for looks, keeping efficiency
###
- "Auto" set column x,y based on finger splay "4 finger touch" snapsMetro.


# Karabiner:

## activate
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate

## run daemon: 
sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'

## stuck, help!
sudo launchctl kickstart -k system/org.pqrs.vhid 