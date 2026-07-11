# Remote Control API

Design a pluggable API that allows remote control of the re.kriate sequencer from external tools, UIs, and protocols. Transport-agnostic core with swappable backends (OSC, MIDI CC, websocket, etc.). Any external tool can read sequencer state and send commands without touching ctx directly.
