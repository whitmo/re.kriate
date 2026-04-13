// rekriate-voice.scd
// SuperCollider voice engine for re.kriate
//
// A warm subtractive synth with per-track voice management, routed through a
// proper bus/group mixer architecture:
//
//   voice synths (ephemeral)  →  per-track mono bus
//       ↓
//   track strip (persistent, one per track) — level, pan, mute
//       ↓
//   master stereo bus
//       ↓
//   master strip (persistent) — master level → hardware out 0
//
// Mixing state lives on the persistent strip nodes (not on individual voice
// synths) so it survives note lifecycle.
//
// Usage:
//   1. Boot SuperCollider
//   2. Open this file and evaluate the entire block (Cmd+Enter on the outer parens)
//   3. Start re.kriate with voice backend set to "osc"
//
// Default OSC target: 127.0.0.1:57120
//
// OSC responders:
//   Note control (per track 1..4):
//     /rekriate/track/{n}/note           midi_note velocity duration
//     /rekriate/track/{n}/all_notes_off
//     /rekriate/track/{n}/portamento     time_seconds
//   Mixer (per track 1..4):
//     /rekriate/mixer/track/{n}/level    0..2   (linear amplitude)
//     /rekriate/mixer/track/{n}/pan      -1..1
//     /rekriate/mixer/track/{n}/mute     0|1
//   Master:
//     /rekriate/mixer/master/level       0..2

(
s.waitForBoot({

    // If a previous load is still live, tear it down cleanly first so
    // repeated re-evaluation doesn't leak buses, groups, or responders.
    if (~rekriate_cleanup.notNil and: { ~rekriate.notNil }, {
        ~rekriate_cleanup.value;
    });

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_voice
    // ─────────────────────────────────────────────
    //
    // Subtractive synth: detuned saw + pulse through a resonant low-pass
    // filter with its own envelope. Writes MONO to its assigned track bus;
    // panning and level live in the track strip, not here.

    SynthDef(\rekriate_voice, { |out=0, freq=440, gate=1, amp=0.3,
        vel=0.8, dur=1, lagTime=0,
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
            Saw.ar(freqLag * (1 + (detune * 0.01))) * sawMix * 0.5,
            Saw.ar(freqLag * (1 - (detune * 0.01))) * sawMix * 0.5,
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

        // Mono output to the track bus; Pan2 happens in the strip.
        Out.ar(out, sig);
    }).add;

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_trackstrip
    // ─────────────────────────────────────────────
    //
    // Persistent per-track mixer strip.
    // Reads mono audio from the track bus, applies mute → level → pan,
    // then writes stereo into the master bus.

    SynthDef(\rekriate_trackstrip, { |in=0, out=0,
        level=1.0, pan=0, mute=0, lagTime=0.05|
        var sig;
        sig = In.ar(in, 1);                     // mono read
        sig = sig * (1 - mute.clip(0, 1));      // hard mute gate
        sig = sig * Lag.kr(level, lagTime);     // smoothed level
        sig = Pan2.ar(sig, Lag.kr(pan, lagTime));
        Out.ar(out, sig);
    }).add;

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_master
    // ─────────────────────────────────────────────
    //
    // Persistent master strip: reads the stereo master bus, applies master
    // level, and writes to the hardware output.

    SynthDef(\rekriate_master, { |in=0, out=0, level=1.0, lagTime=0.05|
        var sig;
        sig = In.ar(in, 2);                     // stereo read
        sig = sig * Lag.kr(level, lagTime);
        Out.ar(out, sig);
    }).add;

    s.sync;  // wait for SynthDefs to be ready

    ">> rekriate SynthDefs loaded (voice / trackstrip / master)".postln;

    // ─────────────────────────────────────────────
    // Buses, groups, mixer state
    // ─────────────────────────────────────────────

    ~rekriate = IdentityDictionary.new;
    ~rekriate[\tracks] = IdentityDictionary.new;

    // Default pan spread for the 4 tracks (Lua side can override via OSC).
    ~rekriate[\defaultPan] = [-0.5, -0.15, 0.15, 0.5];

    // 4 mono track buses + 1 stereo master bus
    ~rekriate[\trackBuses] = Array.fill(4, { Bus.audio(s, 1) });
    ~rekriate[\masterBus]  = Bus.audio(s, 2);

    // Ordered groups — voices run first, strips mix, master finalizes.
    ~rekriate[\voiceGroup]  = Group.new(s);
    ~rekriate[\mixerGroup]  = Group.after(~rekriate[\voiceGroup]);
    ~rekriate[\masterGroup] = Group.after(~rekriate[\mixerGroup]);

    // Initialize per-track state with a persistent strip synth each.
    4.do({ |i|
        var t = i + 1;
        var bus = ~rekriate[\trackBuses][i];
        var strip = Synth.new(\rekriate_trackstrip, [
            \in,    bus.index,
            \out,   ~rekriate[\masterBus].index,
            \level, 1.0,
            \pan,   ~rekriate[\defaultPan][i],
            \mute,  0,
        ], ~rekriate[\mixerGroup]);

        ~rekriate[\tracks][t] = IdentityDictionary.new;
        ~rekriate[\tracks][t][\synth]      = nil;
        ~rekriate[\tracks][t][\portamento] = 0;
        ~rekriate[\tracks][t][\bus]        = bus;
        ~rekriate[\tracks][t][\strip]      = strip;
    });

    // Persistent master strip.
    ~rekriate[\master] = Synth.new(\rekriate_master, [
        \in,    ~rekriate[\masterBus].index,
        \out,   0,
        \level, 1.0,
    ], ~rekriate[\masterGroup]);

    // ─────────────────────────────────────────────
    // Helper: play a note on a track
    // ─────────────────────────────────────────────

    ~rekriate[\playNote] = { |trackNum, midiNote, velocity, duration|
        var trackState = ~rekriate[\tracks][trackNum];
        var freq = midiNote.midicps;
        var vel = velocity.linlin(0, 127, 0, 1);  // normalize MIDI velocity
        var lagTime = trackState[\portamento] ? 0;
        var existingSynth = trackState[\synth];
        var trackBus = trackState[\bus];

        if (lagTime > 0 && existingSynth.notNil, {
            // Glide: update existing voice, schedule release after duration
            existingSynth.set(\freq, freq, \vel, vel, \amp, 0.3, \lagTime, lagTime);

            SystemClock.sched(duration, {
                existingSynth.set(\gate, 0);
                trackState[\synth] = nil;
                nil;
            });
        }, {
            // Release prior note (if any), start fresh voice into the track bus
            if (existingSynth.notNil, {
                existingSynth.set(\gate, 0);
            });

            trackState[\synth] = Synth.new(\rekriate_voice, [
                \freq,    freq,
                \vel,     vel,
                \amp,     0.3,
                \lagTime, lagTime,
                \gate,    1,
                \out,     trackBus.index,
            ], ~rekriate[\voiceGroup]);

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

        "  track %  note=%  vel=%  dur=%  glide=%".format(
            trackNum, midiNote, velocity, duration.round(0.01), lagTime
        ).postln;
    };

    // ─────────────────────────────────────────────
    // OSC responders
    // ─────────────────────────────────────────────

    ~rekriate[\responders] = List.new;

    // Per-track: note / all_notes_off / portamento + mixer level/pan/mute.
    4.do({ |i|
        var t = i + 1;
        var notePath    = "/rekriate/track/" ++ t ++ "/note";
        var allOffPath  = "/rekriate/track/" ++ t ++ "/all_notes_off";
        var portPath    = "/rekriate/track/" ++ t ++ "/portamento";
        var levelPath   = "/rekriate/mixer/track/" ++ t ++ "/level";
        var panPath     = "/rekriate/mixer/track/" ++ t ++ "/pan";
        var mutePath    = "/rekriate/mixer/track/" ++ t ++ "/mute";

        // /rekriate/track/{n}/note midi_note velocity duration
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var midiNote = msg[1];
                var velocity = msg[2];
                var duration = msg[3];

                // Accept velocity as 0.0-1.0 float or 0-127 integer
                if (velocity <= 1.0, {
                    velocity = (velocity * 127).asInteger;
                });

                // Duration arrives in beats — convert to seconds at current tempo
                duration = duration * TempoClock.default.beatDur;

                ~rekriate[\playNote].value(t, midiNote, velocity, duration);
            }, notePath)
        );

        // /rekriate/track/{n}/all_notes_off
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

        // /rekriate/track/{n}/portamento time_seconds
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var time = msg[1] ? 0;
                ~rekriate[\tracks][t][\portamento] = time;
            }, portPath)
        );

        // /rekriate/mixer/track/{n}/level 0..2
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var level = (msg[1] ? 1.0).clip(0, 2);
                ~rekriate[\tracks][t][\strip].set(\level, level);
                "  mixer track % level=%".format(t, level.round(0.01)).postln;
            }, levelPath)
        );

        // /rekriate/mixer/track/{n}/pan -1..1
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var pan = (msg[1] ? 0).clip(-1, 1);
                ~rekriate[\tracks][t][\strip].set(\pan, pan);
                "  mixer track % pan=%".format(t, pan.round(0.01)).postln;
            }, panPath)
        );

        // /rekriate/mixer/track/{n}/mute 0|1
        ~rekriate[\responders].add(
            OSCFunc({ |msg|
                var mute = (msg[1] ? 0).asInteger.clip(0, 1);
                ~rekriate[\tracks][t][\strip].set(\mute, mute);
                "  mixer track % mute=%".format(t, mute).postln;
            }, mutePath)
        );
    });

    // /rekriate/mixer/master/level 0..2
    ~rekriate[\responders].add(
        OSCFunc({ |msg|
            var level = (msg[1] ? 1.0).clip(0, 2);
            ~rekriate[\master].set(\level, level);
            "  mixer master level=%".format(level.round(0.01)).postln;
        }, "/rekriate/mixer/master/level")
    );

    // ─────────────────────────────────────────────
    // Ready
    // ─────────────────────────────────────────────

    "";
    "╔══════════════════════════════════════════╗".postln;
    "║  re.kriate voice engine ready            ║".postln;
    "║  listening on port %                ║".format(NetAddr.langPort).postln;
    "║  4 tracks → mixer strips → master        ║".postln;
    "╚══════════════════════════════════════════╝".postln;
    "";

});

// ─────────────────────────────────────────────
// Cleanup: evaluate this block to free all responders, voices, strips,
// groups, and buses. CmdPeriod frees synths but leaves buses/groups —
// this releases everything the script allocated.
// ─────────────────────────────────────────────

~rekriate_cleanup = {
    if (~rekriate.notNil, {
        // Free all OSC responders
        ~rekriate[\responders].do({ |r| r.free });
        ~rekriate[\responders].clear;

        // Release any active voice synths
        4.do({ |i|
            var t = i + 1;
            var trackState = ~rekriate[\tracks][t];
            if (trackState[\synth].notNil, {
                trackState[\synth].set(\gate, 0);
                trackState[\synth] = nil;
            });
        });

        // Free the persistent mixer strips and master strip
        ~rekriate[\tracks].do({ |ts|
            if (ts[\strip].notNil, { ts[\strip].free });
        });
        if (~rekriate[\master].notNil, { ~rekriate[\master].free });

        // Free groups (also frees anything left inside them)
        if (~rekriate[\voiceGroup].notNil,  { ~rekriate[\voiceGroup].free  });
        if (~rekriate[\mixerGroup].notNil,  { ~rekriate[\mixerGroup].free  });
        if (~rekriate[\masterGroup].notNil, { ~rekriate[\masterGroup].free });

        // Free audio buses
        if (~rekriate[\trackBuses].notNil, {
            ~rekriate[\trackBuses].do({ |b| b.free });
        });
        if (~rekriate[\masterBus].notNil, { ~rekriate[\masterBus].free });

        ~rekriate = nil;
        ">> rekriate voice engine stopped".postln;
    });
};
)
