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
- weld mode (rather than saving all the cframe data for all cfarmes, save weld cframe data for parts connected to welds)
- ignoredescendents (dont add new descendents of activemodels)
- cache replay (may or may not be a good idea, will see)
- record light & particle properties
- replay compression (lzw)
- replay serialization (base64)
- instance serializer
- plugin to insert replay
- generate moon animator animation for replay

## Maybe?
- storing timestamp of previous change to make going back faster on non-cached replays
- doing fps along with framefrequency (idk why you would need this but i guess it could be helpful for people who run at a higher fps?)