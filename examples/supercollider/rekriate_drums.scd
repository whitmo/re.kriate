// rekriate_drums.scd
// SuperCollider drum voice companion for re.kriate sequencer
//
// Four drum SynthDefs: kick, snare, hat, perc
// MIDI note selects drum type via note % 4:
//   0 = kick, 1 = snare, 2 = hat, 3 = perc
// Octave/pitch tunes the selected drum.
// Velocity controls amplitude and character.
//
// Usage:
//   1. Boot SuperCollider server (Cmd+B / Ctrl+B)
//   2. Place cursor inside outer parentheses and evaluate (Cmd+Enter / Ctrl+Enter)
//   3. Start re.kriate with voice backend set to "sc_drums"
//
// Default OSC port: 57120 (SuperCollider's default sclang port)

(
s.waitForBoot({

    // ─── SynthDef: \rekriate_kick ────────────────────
    // Sine body with pitch envelope sweep (high → low).
    // Velocity controls punch and sub weight.

    SynthDef(\rekriate_kick, {
        |out=0, freq=60, amp=0.5, dur=0.5|

        var sig, env, pitchEnv;

        // Pitch sweep: start 4x above target, drop quickly
        pitchEnv = XLine.kr(freq * 4, freq.max(20), 0.04);

        sig = SinOsc.ar(pitchEnv);
        // Add sub harmonic for weight
        sig = sig + SinOsc.ar(pitchEnv * 0.5, 0, 0.3);
        // Soft clip for warmth
        sig = sig.tanh;

        env = EnvGen.kr(
            Env.perc(0.005, dur.max(0.05)),
            doneAction: 2
        );

        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    // ─── SynthDef: \rekriate_snare ───────────────────
    // Sine body + filtered noise crack.
    // Velocity controls noise brightness and body tone.

    SynthDef(\rekriate_snare, {
        |out=0, freq=200, amp=0.5, dur=0.2|

        var body, noise, sig, bodyEnv, noiseEnv;

        // Tonal body: sine with pitch drop
        body = SinOsc.ar(XLine.kr(freq * 2, freq, 0.01));
        bodyEnv = EnvGen.kr(Env.perc(0.005, 0.1.min(dur)));

        // Noise crack: bandpass filtered white noise
        noise = WhiteNoise.ar;
        noise = BPF.ar(noise, (freq * 4).clip(200, 18000), 0.6);
        noiseEnv = EnvGen.kr(Env.perc(0.002, dur.max(0.03)));

        sig = (body * bodyEnv * 0.7) + (noise * noiseEnv);

        // Master envelope
        sig = sig * EnvGen.kr(
            Env.perc(0.001, dur.max(0.03)),
            doneAction: 2
        ) * amp;

        Out.ar(out, sig ! 2);
    }).add;

    // ─── SynthDef: \rekriate_hat ─────────────────────
    // High-pass filtered noise. Short = closed, long = open.
    // Velocity controls brightness. Duration controls decay.

    SynthDef(\rekriate_hat, {
        |out=0, freq=8000, amp=0.3, dur=0.05|

        var sig, env;

        // Mix of square waves at inharmonic intervals for metallic character
        sig = Pulse.ar(freq * 1.0, 0.5, 0.1)
            + Pulse.ar(freq * 1.4471, 0.5, 0.1)
            + Pulse.ar(freq * 1.6170, 0.5, 0.1);
        sig = HPF.ar(sig, freq.clip(2000, 18000));

        env = EnvGen.kr(
            Env.perc(0.001, dur.max(0.01)),
            doneAction: 2
        );

        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    // ─── SynthDef: \rekriate_perc ────────────────────
    // FM synthesis for metallic/bell percussion.
    // Tunable — great for cowbell, clave, rim, toms.

    SynthDef(\rekriate_perc, {
        |out=0, freq=800, amp=0.5, dur=0.3|

        var sig, mod, env;

        // FM: carrier * modulator for metallic partials
        mod = SinOsc.ar(freq * 1.4, 0, freq * 2);
        sig = SinOsc.ar(freq + mod);
        // Add a detuned partial for richness
        sig = sig + SinOsc.ar(freq * 2.76, 0, 0.3);

        env = EnvGen.kr(
            Env.perc(0.001, dur.max(0.02)),
            doneAction: 2
        );

        sig = sig * env * amp;
        Out.ar(out, sig ! 2);
    }).add;

    s.sync;

    // ─── Drum type lookup ────────────────────────────

    ~drumDefs = [\rekriate_kick, \rekriate_snare, \rekriate_hat, \rekriate_perc];
    ~drumNames = ["kick", "snare", "hat", "perc"];

    // ─── Track voice state ───────────────────────────
    // Per-track: list of active synth nodes + portamento time.

    ~tracks = Array.fill(4, {
        (nodes: List.new, portaTime: 0.0)
    });

    // ─── OSC responders (16 total: 4 tracks x 4 types) ──

    ~responders = List.new;

    4.do({ |i|
        var t = i + 1;
        var track = ~tracks[i];

        // /rekriate/track/{n}/drum  midi_note velocity duration
        ~responders.add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                var velocity = msg[2];
                var duration = msg[3];
                var drumIdx, synthName, freq, amp, synth;

                // Select drum type: note % 4
                drumIdx = midiNote.asInteger % 4;
                synthName = ~drumDefs[drumIdx];

                // Derive frequency from MIDI note
                freq = midiNote.midicps;

                // Velocity to amplitude (handle both 0-1 and 0-127 ranges)
                amp = if(velocity > 1.0, { velocity / 127.0 }, { velocity }).clip(0, 1);

                synth = Synth(synthName, [
                    \freq, freq,
                    \amp, amp,
                    \dur, duration,
                ]);

                track[\nodes].add(synth);
                synth.onFree({ track[\nodes].remove(synth) });

                "[track %] drum %: midi=% vel=% dur=%".format(
                    t, ~drumNames[drumIdx], midiNote, velocity, duration.round(0.01)
                ).postln;
            }, "/rekriate/track/" ++ t ++ "/drum")
        );

        // /rekriate/track/{n}/drum_off  midi_note
        ~responders.add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                "[track %] drum_off: midi=%".format(t, midiNote).postln;
                // Drums are self-freeing via doneAction:2, so this is mostly a no-op.
                // Could be used for open-hat choke in future extensions.
            }, "/rekriate/track/" ++ t ++ "/drum_off")
        );

        // /rekriate/track/{n}/all_drums_off
        ~responders.add(
            OSCFunc({ |msg|
                track[\nodes].do({ |synth| synth.free });
                track[\nodes].clear;
                "[track %] all drums off".format(t).postln;
            }, "/rekriate/track/" ++ t ++ "/all_drums_off")
        );

        // /rekriate/track/{n}/drum_portamento  time
        ~responders.add(
            OSCFunc({ |msg|
                var time = msg[1] ? 0;
                track[\portaTime] = time;
                "[track %] drum portamento: %s".format(t, time).postln;
            }, "/rekriate/track/" ++ t ++ "/drum_portamento")
        );
    });

    // ─── Ready ───────────────────────────────────────

    "".postln;
    "re.kriate DRUM listener ready on port %".format(NetAddr.langPort).postln;
    "  4 drum SynthDefs: kick, snare, hat, perc".postln;
    "  4 tracks, 16 OSC responders active".postln;
    "  Drum type = MIDI note %% 4 (0=kick, 1=snare, 2=hat, 3=perc)".postln;
    "".postln;
});
)
