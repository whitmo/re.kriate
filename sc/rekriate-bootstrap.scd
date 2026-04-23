// sc/rekriate-bootstrap.scd
// One-shot SuperCollider bootstrap for re.kriate.
//
// Loads the full companion stack into a single sclang session:
//   - sc/rekriate-voice.scd               (primary voice engine + mixer strips)
//   - examples/supercollider/rekriate_synths.scd   (sc_synth multi-SynthDef)
//   - examples/supercollider/rekriate_drums.scd    (sc_drums percussion)
//
// Launched by bin/start-sc. All three scripts each register a ping
// responder, so the Lua bridge accumulates {voice, mixer, sc_synth, sc_drums,
// ...} under one handshake nonce.

(
    var base = PathName(thisProcess.nowExecutingPath).pathOnly;
    var repo = PathName(base).parentPath;  // sc/ → repo root

    "═══════════════════════════════════════════════════".postln;
    "  re.kriate SuperCollider bootstrap".postln;
    "  repo root: %".format(repo).postln;
    "═══════════════════════════════════════════════════".postln;

    // Load voice engine + mixer (note: this file is already wrapped in its
    // own parenthesized async block using s.waitForBoot, so executeFile is
    // the right way to evaluate it).
    thisProcess.interpreter.executeFile(repo ++ "sc/rekriate-voice.scd");

    // Load sc_synth multi-SynthDef listener.
    thisProcess.interpreter.executeFile(
        repo ++ "examples/supercollider/rekriate_synths.scd"
    );

    // Load sc_drums percussion listener.
    thisProcess.interpreter.executeFile(
        repo ++ "examples/supercollider/rekriate_drums.scd"
    );

    "".postln;
    "bootstrap: all three companion scripts dispatched".postln;
    "  Lua ping → pong from each — features merge on the bridge side".postln;
    "".postln;
)
