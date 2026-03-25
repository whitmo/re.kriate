// rekriate-voice.scd
// SuperCollider voice engine for re.kriate
//
// A warm subtractive synth with per-track voice management.
// Receives OSC from re.kriate's OSC voice backend (lib/voices/osc.lua).
//
// Usage:
//   1. Boot SuperCollider
//   2. Open this file and evaluate the entire block (Cmd+Enter on the outer parens)
//   3. Start re.kriate with voice backend set to "osc"
//
// Default OSC target: 127.0.0.1:57120

(
s.waitForBoot({

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_voice
    // ─────────────────────────────────────────────
    //
    // Subtractive synth: detuned saw + pulse through
    // a resonant low-pass filter with its own envelope.
    // Warm, musical, immediately usable.

    SynthDef(\rekriate_voice, { |out=0, freq=440, gate=1, amp=0.3,
        vel=0.8, dur=1, pan=0, lagTime=0,
        // filter
        cutoff=3000, res=0.3,
        filterAttack=0.005, filterDecay=0.3, filterSustain=0.4, filterRelease=0.5,
        filterEnvAmount=4000,
        // amp envelope
        attack=0.005, decay=0.15, sustain=0.7, release=0.3,
        // oscillator
        detune=0.08, pulseWidth=0.45, sawMix=0.6|

        var sig, filt, ampEnv, filtEnv, freqLag;

        // Portamento: lag the frequency for glide between notes
        freqLag = Lag.kr(freq, lagTime);

        // Oscillators: detuned saw pair + pulse wave
        sig = Mix.ar([
            // Saw with slight detune spread for warmth
            Saw.ar(freqLag * (1 + (detune * 0.01))) * sawMix * 0.5,
            Saw.ar(freqLag * (1 - (detune * 0.01))) * sawMix * 0.5,
            // Pulse wave for body
            Pulse.ar(freqLag, pulseWidth) * (1 - sawMix),
        ]);

        // Amp envelope — gate-controlled with release
        ampEnv = EnvGen.kr(
            Env.adsr(attack, decay, sustain, release),
            gate,
            doneAction: 2  // free synth when envelope completes
        );

        // Filter envelope — velocity opens the filter
        filtEnv = EnvGen.kr(
            Env.adsr(filterAttack, filterDecay, filterSustain, filterRelease),
            gate
        );

        // Velocity scales both amplitude and filter brightness
        filt = MoogFF.ar(
            sig,
            (cutoff + (filtEnv * filterEnvAmount * vel)).clip(20, 18000),
            res * 3.5  // MoogFF resonance 0-4 range
        );

        sig = filt * ampEnv * amp * vel.linlin(0, 1, 0.4, 1.0);

        // Gentle stereo spread
        sig = Pan2.ar(sig, pan);

        Out.ar(out, sig);
    }).add;

    s.sync;  // wait for SynthDef to be ready

    ">> rekriate SynthDef loaded".postln;

    // ─────────────────────────────────────────────
    // Voice manager
    // ─────────────────────────────────────────────
    //
    // Per-track state: current synth node, portamento time.
    // Each track is monophonic with glide — like a monosynth.
    // New notes release the previous note on that track.

    ~rekriate = IdentityDictionary.new;
    ~rekriate[\tracks] = IdentityDictionary.new;

    // Track panning: spread 4 tracks across stereo field
    ~rekriate[\panMap] = [-0.5, -0.15, 0.15, 0.5];

    // Initialize per-track state
    4.do({ |i|
        var t = i + 1;  // 1-indexed to match re.kriate track numbers
        ~rekriate[\tracks][t] = IdentityDictionary.new;
        ~rekriate[\tracks][t][\synth] = nil;
        ~rekriate[\tracks][t][\portamento] = 0;
    });

    // ─────────────────────────────────────────────
    // Helper: play a note on a track
    // ─────────────────────────────────────────────

    ~rekriate[\playNote] = { |trackNum, midiNote, velocity, duration|
        var trackState = ~rekriate[\tracks][trackNum];
        var freq = midiNote.midicps;
        var vel = velocity.linlin(0, 127, 0, 1);  // normalize MIDI velocity
        var pan = ~rekriate[\panMap][trackNum - 1] ? 0;
        var lagTime = trackState[\portamento] ? 0;
        var existingSynth = trackState[\synth];

        // If there's a portamento and an existing synth, glide to new pitch
        if (lagTime > 0 && existingSynth.notNil, {
            // Set new frequency on existing synth (it will glide via Lag)
            existingSynth.set(\freq, freq, \vel, vel, \amp, 0.3, \lagTime, lagTime);

            // Schedule release after duration
            SystemClock.sched(duration, {
                existingSynth.set(\gate, 0);
                trackState[\synth] = nil;
                nil;
            });
        }, {
            // No glide or no existing note: release old, start new
            if (existingSynth.notNil, {
                existingSynth.set(\gate, 0);
            });

            trackState[\synth] = Synth(\rekriate_voice, [
                \freq, freq,
                \vel, vel,
                \amp, 0.3,
                \pan, pan,
                \lagTime, lagTime,
                \gate, 1,
            ]);

            // Schedule note-off after duration (in seconds)
            SystemClock.sched(duration, {
                var synth = trackState[\synth];
                // Only release if this is still the active synth
                if (synth.notNil, {
                    synth.set(\gate, 0);
                    trackState[\synth] = nil;
                });
                nil;
            });
        });

        // Log (comment out for less console noise)
        "  track %  note=%  vel=%  dur=%  glide=%".format(
            trackNum, midiNote, velocity, duration.round(0.01), lagTime
        ).postln;
    };

    // ─────────────────────────────────────────────
    // OSC responders
    // ─────────────────────────────────────────────

    ~rekriate[\responders] = List.new;

    4.do({ |i|
        var t = i + 1;
        var notePath = "/rekriate/track/" ++ t ++ "/note";
        var allOffPath = "/rekriate/track/" ++ t ++ "/all_notes_off";
        var portPath = "/rekriate/track/" ++ t ++ "/portamento";

        // Note messages: /rekriate/track/{n}/note midi_note velocity duration
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                var velocity = msg[2];
                var duration = msg[3];

                // Convert velocity from 0.0-1.0 float to 0-127 range if needed
                if (velocity <= 1.0, {
                    velocity = (velocity * 127).asInteger;
                });

                // Duration arrives in beats — convert to seconds at current tempo
                // re.kriate sends duration in beat fractions; use TempoClock for conversion
                duration = duration * TempoClock.default.beatDur;

                ~rekriate[\playNote].value(t, midiNote, velocity, duration);
            }, notePath)
        );

        // All notes off: /rekriate/track/{n}/all_notes_off
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var trackState = ~rekriate[\tracks][t];
                if (trackState[\synth].notNil, {
                    trackState[\synth].set(\gate, 0);
                    trackState[\synth] = nil;
                });
                "  track % all notes off".format(t).postln;
            }, allOffPath)
        );

        // Portamento: /rekriate/track/{n}/portamento time
        // time is the glide step value (0 = off, or a time in seconds)
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var time = msg[1] ? 0;
                ~rekriate[\tracks][t][\portamento] = time;
            }, portPath)
        );
    });

    // ─────────────────────────────────────────────
    // Ready
    // ─────────────────────────────────────────────

    "";
    "╔══════════════════════════════════════════╗".postln;
    "║  re.kriate voice engine ready            ║".postln;
    "║  listening on port %                ║".format(NetAddr.langPort).postln;
    "║  4 tracks, OSC active                    ║".postln;
    "╚══════════════════════════════════════════╝".postln;
    "";

});

// ─────────────────────────────────────────────
// Cleanup: evaluate this block to free all responders
// and silence all voices when you're done.
// ─────────────────────────────────────────────
// CmdPeriod already frees synths and responders in SC,
// but this gives explicit control.

~rekriate_cleanup = {
    if (~rekriate.notNil, {
        // Free all responders
        ~rekriate[\responders].do({ |r| r.free });
        ~rekriate[\responders].clear;

        // Release any active synths
        4.do({ |i|
            var t = i + 1;
            var trackState = ~rekriate[\tracks][t];
            if (trackState[\synth].notNil, {
                trackState[\synth].set(\gate, 0);
                trackState[\synth] = nil;
            });
        });

        ">> rekriate voice engine stopped".postln;
    });
};
)
