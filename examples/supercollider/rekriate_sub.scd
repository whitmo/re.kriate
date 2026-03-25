// rekriate_sub.scd
// SuperCollider companion for re.kriate sequencer
//
// A simple subtractive synth that listens for OSC messages from
// re.kriate's OSC voice backend (lib/voices/osc.lua).
//
// Usage:
//   1. Boot SuperCollider server (Cmd+B / Ctrl+B)
//   2. Place cursor inside outer parentheses and evaluate (Cmd+Enter / Ctrl+Enter)
//   3. Start re.kriate with voice backend set to "osc"
//
// Default OSC port: 57120 (SuperCollider's default sclang port)

(
s.waitForBoot({

    // ─── SynthDef: \rekriate_sub ─────────────────────
    // Subtractive synth: Saw → RLPF → Env.perc
    // Self-freeing after duration elapses (doneAction: 2).

    SynthDef(\rekriate_sub, {
        |out=0, freq=440, amp=0.5, dur=0.5, cutoff=2000, porta=0.0|

        var sig, env, freqLag;

        // Portamento: lag frequency for glide between notes
        freqLag = Lag.kr(freq, porta);

        // Oscillator
        sig = Saw.ar(freqLag);

        // Resonant low-pass filter (velocity-sensitive cutoff)
        sig = RLPF.ar(sig, cutoff.clip(20, 20000), 0.3);

        // Amplitude envelope: percussive, self-freeing
        // Min release of 0.01s prevents clicks on very short durations
        env = EnvGen.kr(
            Env.perc(0.01, dur.max(0.01)),
            doneAction: 2
        );

        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    s.sync;

    // ─── Track voice state ───────────────────────────
    // Per-track: list of active synth nodes + portamento time.
    // Polyphonic — each track can have multiple simultaneous notes.

    ~tracks = Array.fill(4, {
        (nodes: List.new, portaTime: 0.0)
    });

    // ─── OSC responders (12 total: 4 tracks x 3 types) ──

    ~responders = List.new;

    4.do({ |i|
        var t = i + 1;
        var track = ~tracks[i];

        // /rekriate/track/{n}/note  midi_note velocity duration
        ~responders.add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                var velocity = msg[2];
                var duration = msg[3];
                var synth;

                synth = Synth(\rekriate_sub, [
                    \freq, midiNote.midicps,
                    \amp, (velocity / 127.0).clip(0, 1),
                    \dur, duration,
                    \cutoff, velocity.linlin(0, 127, 400, 8000),
                    \porta, track[\portaTime],
                ]);

                track[\nodes].add(synth);

                // Remove from list when synth frees itself (doneAction: 2)
                synth.onFree({ track[\nodes].remove(synth) });

                "[track %] note: midi=% vel=% dur=%".format(
                    t, midiNote, velocity, duration.round(0.01)
                ).postln;
            }, "/rekriate/track/" ++ t ++ "/note")
        );

        // /rekriate/track/{n}/all_notes_off
        ~responders.add(
            OSCFunc({ |msg|
                track[\nodes].do({ |synth| synth.free });
                track[\nodes].clear;
                "[track %] all notes off".format(t).postln;
            }, "/rekriate/track/" ++ t ++ "/all_notes_off")
        );

        // /rekriate/track/{n}/portamento  time
        ~responders.add(
            OSCFunc({ |msg|
                var time = msg[1] ? 0;
                track[\portaTime] = time;
                "[track %] portamento: %s".format(t, time).postln;
            }, "/rekriate/track/" ++ t ++ "/portamento")
        );
    });

    // ─── Ready ───────────────────────────────────────

    "".postln;
    "re.kriate listener ready on port %".format(NetAddr.langPort).postln;
    "  4 tracks, 12 OSC responders active".postln;
    "".postln;
});
)
