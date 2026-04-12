// rekriate_synths.scd
// Multi-SynthDef SuperCollider companion for re.kriate's sc_synth voice.
//
// Hosts three melodic SynthDefs — \rekriate_sub (subtractive),
// \rekriate_fm (2-op FM), \rekriate_wt (wavetable) — and listens for
// OSC messages from lib/voices/sc_synth.lua.
//
// Usage:
//   1. Boot the SuperCollider server (Cmd+B / Ctrl+B)
//   2. Place cursor inside the outer parentheses and evaluate (Cmd+Enter)
//   3. In re.kriate, set a track's voice to "sc_synth" and pick the
//      SynthDef via the "sc synthdef" param (sub / fm / wavetable)
//
// Default OSC port: 57120 (SuperCollider's default sclang port)
//
// OSC paths (sent by lib/voices/sc_synth.lua):
//   /rekriate/synth/{n}/play          midi_note velocity duration
//   /rekriate/synth/{n}/note_on       midi_note velocity
//   /rekriate/synth/{n}/note_off      midi_note
//   /rekriate/synth/{n}/all_notes_off
//   /rekriate/synth/{n}/portamento    time
//   /rekriate/synth/{n}/synthdef      name        ("sub"|"fm"|"wavetable")

(
s.waitForBoot({

    // ─── \rekriate_sub ───────────────────────────────
    // Subtractive: Saw -> RLPF (velocity-scaled cutoff) -> Env.perc.
    // Supports gate=1 (sustain) or dur>0 (timed, self-freeing).

    SynthDef(\rekriate_sub, {
        |out=0, freq=440, amp=0.5, dur=0.5, cutoff=2000,
         porta=0.0, gate=1, timed=0|
        var sig, env, freqLag;
        freqLag = Lag.kr(freq, porta);
        sig = Saw.ar(freqLag);
        sig = RLPF.ar(sig, cutoff.clip(20, 20000), 0.3);
        env = Select.kr(timed, [
            EnvGen.kr(Env.asr(0.005, 1.0, 0.05), gate, doneAction: 2),
            EnvGen.kr(Env.perc(0.01, dur.max(0.01)), doneAction: 2)
        ]);
        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    // ─── \rekriate_fm ────────────────────────────────
    // 2-operator FM: carrier modulated by a sine at ratio*freq.
    // modIndex scales with velocity for musical expressiveness.

    SynthDef(\rekriate_fm, {
        |out=0, freq=440, amp=0.5, dur=0.5, cutoff=4000,
         porta=0.0, gate=1, timed=0, ratio=2.0, modIndex=3.0|
        var sig, mod, env, freqLag;
        freqLag = Lag.kr(freq, porta);
        mod = SinOsc.ar(freqLag * ratio) * freqLag * modIndex;
        sig = SinOsc.ar(freqLag + mod);
        sig = LPF.ar(sig, cutoff.clip(20, 20000));
        env = Select.kr(timed, [
            EnvGen.kr(Env.asr(0.005, 1.0, 0.1), gate, doneAction: 2),
            EnvGen.kr(Env.perc(0.005, dur.max(0.01)), doneAction: 2)
        ]);
        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    // ─── \rekriate_wt ────────────────────────────────
    // Wavetable-esque: blend of Saw/Square/Tri via VarSaw shaping.
    // Uses a shape argument driven by velocity for timbral motion.

    SynthDef(\rekriate_wt, {
        |out=0, freq=440, amp=0.5, dur=0.5, cutoff=5000,
         porta=0.0, gate=1, timed=0, shape=0.5|
        var sig, env, freqLag;
        freqLag = Lag.kr(freq, porta);
        sig = VarSaw.ar(freqLag, 0, shape.clip(0.01, 0.99));
        sig = sig + (Pulse.ar(freqLag * 0.5, 0.5) * 0.3);
        sig = LPF.ar(sig, cutoff.clip(20, 20000));
        env = Select.kr(timed, [
            EnvGen.kr(Env.asr(0.01, 1.0, 0.2), gate, doneAction: 2),
            EnvGen.kr(Env.perc(0.01, dur.max(0.01)), doneAction: 2)
        ]);
        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    s.sync;

    // ─── Track voice state ───────────────────────────
    // Per-track: timed nodes (self-free), gated nodes (by MIDI note),
    // portamento time, and current SynthDef selection.

    ~synthDefFor = (
        \sub: \rekriate_sub,
        \fm: \rekriate_fm,
        \wavetable: \rekriate_wt
    );

    ~tracks = Array.fill(4, {
        (
            timedNodes: List.new,
            gatedNodes: Dictionary.new,
            portaTime: 0.0,
            synthDef: \rekriate_sub
        )
    });

    // ─── OSC responders ──────────────────────────────

    ~responders = List.new;

    4.do({ |i|
        var t = i + 1;
        var track = ~tracks[i];

        // Timed note: play + self-free after duration.
        ~responders.add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                var velocity = msg[2];
                var duration = msg[3];
                var vel = velocity.isNumber.if({
                    (velocity > 1).if({ velocity / 127.0 }, { velocity });
                }, { 0.5 });
                var synth = Synth(track[\synthDef], [
                    \freq, midiNote.midicps,
                    \amp, vel.clip(0, 1),
                    \dur, duration,
                    \cutoff, vel.linlin(0, 1, 400, 8000),
                    \porta, track[\portaTime],
                    \timed, 1
                ]);
                track[\timedNodes].add(synth);
                synth.onFree({ track[\timedNodes].remove(synth) });
                "[synth %] play %: midi=% vel=% dur=%".format(
                    t, track[\synthDef], midiNote, vel.round(0.01),
                    duration.round(0.01)
                ).postln;
            }, "/rekriate/synth/" ++ t ++ "/play")
        );

        // Sustained note-on: holds until matching note_off.
        ~responders.add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                var velocity = msg[2];
                var vel = velocity.isNumber.if({
                    (velocity > 1).if({ velocity / 127.0 }, { velocity });
                }, { 0.5 });
                var synth;
                // Release any existing gated synth on this MIDI note.
                track[\gatedNodes][midiNote] !? { |old|
                    old.set(\gate, 0);
                };
                synth = Synth(track[\synthDef], [
                    \freq, midiNote.midicps,
                    \amp, vel.clip(0, 1),
                    \cutoff, vel.linlin(0, 1, 400, 8000),
                    \porta, track[\portaTime],
                    \timed, 0,
                    \gate, 1
                ]);
                track[\gatedNodes][midiNote] = synth;
                "[synth %] note_on %: midi=% vel=%".format(
                    t, track[\synthDef], midiNote, vel.round(0.01)
                ).postln;
            }, "/rekriate/synth/" ++ t ++ "/note_on")
        );

        // Note-off: releases the matching gated synth.
        ~responders.add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                track[\gatedNodes][midiNote] !? { |synth|
                    synth.set(\gate, 0);
                    track[\gatedNodes].removeAt(midiNote);
                };
                "[synth %] note_off: midi=%".format(t, midiNote).postln;
            }, "/rekriate/synth/" ++ t ++ "/note_off")
        );

        // All notes off: free timed + gated.
        ~responders.add(
            OSCFunc({ |msg|
                track[\timedNodes].do({ |synth| synth.free });
                track[\timedNodes].clear;
                track[\gatedNodes].do({ |synth| synth.set(\gate, 0) });
                track[\gatedNodes].clear;
                "[synth %] all notes off".format(t).postln;
            }, "/rekriate/synth/" ++ t ++ "/all_notes_off")
        );

        // Portamento time.
        ~responders.add(
            OSCFunc({ |msg|
                var time = msg[1] ? 0;
                track[\portaTime] = time;
                "[synth %] portamento: %s".format(t, time).postln;
            }, "/rekriate/synth/" ++ t ++ "/portamento")
        );

        // SynthDef selection.
        ~responders.add(
            OSCFunc({ |msg|
                var name = msg[1].asSymbol;
                var def = ~synthDefFor[name];
                def.notNil.if({
                    track[\synthDef] = def;
                    "[synth %] synthdef -> %".format(t, def).postln;
                }, {
                    "[synth %] unknown synthdef: %".format(t, name).postln;
                });
            }, "/rekriate/synth/" ++ t ++ "/synthdef")
        );
    });

    // ─── Ready ───────────────────────────────────────

    "".postln;
    "re.kriate sc_synth listener ready on port %".format(
        NetAddr.langPort
    ).postln;
    "  4 tracks, % OSC responders active, SynthDefs: sub / fm / wavetable"
        .format(~responders.size).postln;
    "".postln;
});
)
