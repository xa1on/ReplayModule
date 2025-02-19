# ReplayModule

this project is only being worked on sporadically. updates not guaranteed.

## Features
- highly customizable save state replay system
- all active models are observed and recorded, even if they are generated during recording
- fast and efficient storage and replay (compared to the competition)
- custom types and a lot of very annoying typechecking
- custom viewport frame creator
- smooth interpolation

## WIP
- metatables to avoid creating new functions per replay created
- doubly linked-lists for storing frames (reference to previous change frame included for each new frame) REQUIRES MAJOR OVERHAUL OF PLAYBACK AND RECORDING
- ignoredescendents (dont add new descendents of activemodels)
- weld mode (rather than saving all the cframe data for all cfarmes, save weld cframe data for parts connected to welds)
- record light & particle properties
- cache replay (may or may not be a good idea considering the amount of data replays take)
- record value differences as opposed to storing the current value of each changing property (every 5 differences or so it should recalibrate and return the actual value)
- benchmark best value for rounding to ensure space efficiency while minimizing error
- replay compression (lzw)
- replay serialization (base64)
- instance serializer
- plugin to insert replay
- generate moon animator animation for replay

## Maybe?
- storing timestamp of previous change to make going back faster on non-cached replays
- doing fps along with framefrequency (idk why you would need this but i guess it could be helpful for people who run at a higher fps?)
- chunking/task scheduler for playback/export