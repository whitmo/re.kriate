// rekriate-mixer.scd
// SC mixer bus architecture for re.kriate — phases 1-3 of sc-mixer-spec (re-u9w).
//
// Voice synths write mono audio into per-channel buses; channel strips upmix
// to stereo, apply filter → reverb → delay → compressor → level → mute →
// pan, then route to master out and aux send. A shared aux synth adds global
// reverb/delay. A master synth sums the aux return into the hardware output
// and applies a tanh soft-clip limiter via ReplaceOut.
//
//   ┌────────────────────────────────────────────────────────────────┐
//   │  voice synths (mono)   ~rekriate_mixer.groups[\voices]          │
//   │        ↓ out = channelBus[n]                                    │
//   │  \rekriate_channel_strip × 4  ~rekriate_mixer.groups[\channels] │
//   │        ↓ out 0 (hardware)  + aux send                           │
//   │  \rekriate_aux           ~rekriate_mixer.groups[\aux]            │
//   │        ↓ aux return                                              │
//   │  \rekriate_mixer_master  ~rekriate_mixer.groups[\master]         │
//   │        ↓ ReplaceOut hardware 0                                   │
//   └────────────────────────────────────────────────────────────────┘
//
// Terminology: "channel" (1-4, aux, master) refers to the mixer; "track"
// refers to the sequencer. They happen to map 1:1 for channels 1-4, but
// the distinction matters — mixer OSC uses /rekriate/mixer/channel/{n}/...
//
// Deviation from spec §2.1: channel buses are MONO (1 channel) instead of
// stereo. This preserves the existing mono voice synthdef; the channel
// strip upmixes to stereo internally before running the stereo fx chain.
// Aux send/return, master, and all downstream buses remain stereo.
//
// Usage:
//   1. Boot SuperCollider.
//   2. Evaluate sc/rekriate-voice.scd (loads the voice engine).
//   3. Evaluate this file (installs the mixer, patches voice routing).
//   4. Send notes via /rekriate/track/{n}/note — audio flows through mixer.
//
// OSC inbound (Lua → SC):
//   Channel 1..4:
//     /rekriate/mixer/channel/{n}/level            float 0..2
//     /rekriate/mixer/channel/{n}/pan              float -1..1
//     /rekriate/mixer/channel/{n}/mute             int   0|1
//     /rekriate/mixer/channel/{n}/send             float 0..1
//     /rekriate/mixer/channel/{n}/filter_type      int   0=bypass 1=HPF 2=LPF
//     /rekriate/mixer/channel/{n}/filter_freq      float 20..18000
//     /rekriate/mixer/channel/{n}/filter_res       float 0..1
//     /rekriate/mixer/channel/{n}/reverb_mix       float 0..1
//     /rekriate/mixer/channel/{n}/reverb_room      float 0..1
//     /rekriate/mixer/channel/{n}/reverb_damp      float 0..1
//     /rekriate/mixer/channel/{n}/delay_mix        float 0..1
//     /rekriate/mixer/channel/{n}/delay_time       float 0.001..2.0 sec
//     /rekriate/mixer/channel/{n}/delay_feedback   float 0..0.95
//     /rekriate/mixer/channel/{n}/comp_thresh      float 0..1
//     /rekriate/mixer/channel/{n}/comp_ratio       float 1..20
//     /rekriate/mixer/channel/{n}/comp_attack      float 0.001..0.5 sec
//     /rekriate/mixer/channel/{n}/comp_release     float 0.01..1.0 sec
//   Aux:
//     /rekriate/mixer/aux/level                    float 0..2
//     /rekriate/mixer/aux/reverb_mix               float 0..1
//     /rekriate/mixer/aux/reverb_room              float 0..1
//     /rekriate/mixer/aux/reverb_damp              float 0..1
//     /rekriate/mixer/aux/delay_mix                float 0..1
//     /rekriate/mixer/aux/delay_time               float 0.001..2.0 sec
//     /rekriate/mixer/aux/delay_feedback           float 0..0.95
//   Master:
//     /rekriate/mixer/master/level                 float 0..2
//     /rekriate/mixer/master/aux_return_level      float 0..2
//   Metering / bulk:
//     /rekriate/mixer/meter/target "host" port     configure meter forwarding
//     /rekriate/mixer/meter/off                    disable meter forwarding
//
// OSC outbound (SC → Lua) when meter target is configured:
//     /rekriate/mixer/meter/channel/{n} l r        peak L, peak R  (0..1)
//     /rekriate/mixer/meter/aux          l r
//     /rekriate/mixer/meter/master       l r
//   Fired at 30 Hz per source.

(
s.waitForBoot({

    // Tear down prior mixer state so re-evaluation doesn't leak.
    if (~rekriate_mixer_cleanup.notNil and: { ~rekriate_mixer.notNil }, {
        ~rekriate_mixer_cleanup.value;
    });

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_channel_strip
    // ─────────────────────────────────────────────
    //
    // Mono voice input → stereo fx chain → stereo out + aux send.
    // 30 Hz SendReply emits peak L/R for metering, keyed by meter_id.

    SynthDef(\rekriate_channel_strip, { |in_bus=0, out_bus=0, aux_bus=0,
        level=0.8, pan=0, mute=0, send=0,
        // filter
        filter_type=0, filter_freq=10000, filter_res=0.3,
        // reverb (insert)
        reverb_mix=0, reverb_room=0.5, reverb_damp=0.5,
        // delay (insert, stereo-spread comb)
        delay_mix=0, delay_time=0.375, delay_feedback=0.3,
        // compressor
        comp_thresh=0.5, comp_ratio=1, comp_attack=0.01, comp_release=0.1,
        // metering / smoothing
        meter_id=0, lag=0.05|

        var mono, sig, dry, wet, delayed, cutoff, dt;

        // Mono voice read, upmix to stereo for the fx chain.
        mono = In.ar(in_bus, 1);
        sig = [mono, mono];

        // --- Filter (0=bypass, 1=HPF, 2=LPF) ---
        cutoff = Lag.kr(filter_freq.clip(20, 18000), lag);
        sig = Select.ar(filter_type.clip(0, 2), [
            sig,
            HPF.ar(sig, cutoff),
            LPF.ar(sig, cutoff),
        ]);

        // --- Reverb insert (wet/dry) ---
        dry = sig;
        wet = FreeVerb2.ar(sig[0], sig[1],
            1.0,
            reverb_room.clip(0, 1),
            reverb_damp.clip(0, 1)
        );
        sig = (dry * (1 - reverb_mix.clip(0, 1)))
            + (wet * reverb_mix.clip(0, 1));

        // --- Delay insert (stereo comb with slight R offset) ---
        dt = Lag.kr(delay_time.clip(0.001, 2.0), lag);
        dry = sig;
        delayed = CombL.ar(sig, 2.0,
            [dt, dt * 1.03].clip(0.001, 2.0),
            delay_feedback.clip(0, 0.95) * 4
        );
        sig = (dry * (1 - delay_mix.clip(0, 1)))
            + (delayed * delay_mix.clip(0, 1));

        // --- Compressor (downward only) ---
        sig = Compander.ar(sig, sig,
            thresh: comp_thresh.clip(0.001, 1),
            slopeBelow: 1,
            slopeAbove: comp_ratio.clip(1, 20).reciprocal,
            clampTime: comp_attack.clip(0.001, 0.5),
            relaxTime: comp_release.clip(0.01, 1.0)
        );

        // --- Level + Mute + Pan ---
        sig = sig * Lag.kr(level.clip(0, 2), lag) * (1 - mute.clip(0, 1));
        sig = Balance2.ar(sig[0], sig[1], Lag.kr(pan.clip(-1, 1), lag));

        // --- Route ---
        Out.ar(out_bus, sig);
        Out.ar(aux_bus, sig * Lag.kr(send.clip(0, 1), lag));

        // --- Meter ---
        SendReply.kr(Impulse.kr(30),
            "/rekriate_meter",
            [Amplitude.kr(sig[0]), Amplitude.kr(sig[1])],
            meter_id
        );
    }).add;

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_aux
    // ─────────────────────────────────────────────
    //
    // Global send effects: reverb + delay on aux send bus → aux return bus.

    SynthDef(\rekriate_aux, { |in_bus=0, out_bus=0,
        level=0.8,
        reverb_mix=0.6, reverb_room=0.7, reverb_damp=0.4,
        delay_mix=0.3, delay_time=0.375, delay_feedback=0.4,
        meter_id=5, lag=0.05|

        var sig, dry, wet, delayed;

        sig = In.ar(in_bus, 2);

        dry = sig;
        wet = FreeVerb2.ar(sig[0], sig[1],
            1.0,
            reverb_room.clip(0, 1),
            reverb_damp.clip(0, 1)
        );
        sig = (dry * (1 - reverb_mix.clip(0, 1)))
            + (wet * reverb_mix.clip(0, 1));

        dry = sig;
        delayed = CombL.ar(sig, 2.0,
            Lag.kr(delay_time.clip(0.001, 2.0), lag),
            delay_feedback.clip(0, 0.95) * 4
        );
        sig = (dry * (1 - delay_mix.clip(0, 1)))
            + (delayed * delay_mix.clip(0, 1));

        sig = sig * Lag.kr(level.clip(0, 2), lag);

        Out.ar(out_bus, sig);

        SendReply.kr(Impulse.kr(30),
            "/rekriate_meter",
            [Amplitude.kr(sig[0]), Amplitude.kr(sig[1])],
            meter_id
        );
    }).add;

    // ─────────────────────────────────────────────
    // SynthDef: \rekriate_mixer_master
    // ─────────────────────────────────────────────
    //
    // Sums the existing hardware-out content (channel strips) with the aux
    // return, applies master level and a tanh soft-clip limiter, writes
    // back to the hardware out with ReplaceOut so the limiter wins.
    // (Spec calls this \rekriate_master; renamed to avoid collision with
    // the simple master in rekriate-voice.scd.)

    SynthDef(\rekriate_mixer_master, { |aux_return_bus=0, out_bus=0,
        level=0.8, aux_return_level=0.5,
        meter_id=6, lag=0.05|

        var sig, auxSig;

        sig = In.ar(out_bus, 2);
        auxSig = In.ar(aux_return_bus, 2)
            * Lag.kr(aux_return_level.clip(0, 2), lag);

        sig = sig + auxSig;
        sig = sig * Lag.kr(level.clip(0, 2), lag);

        // Soft-clip limiter.
        sig = sig.tanh;

        ReplaceOut.ar(out_bus, sig);

        SendReply.kr(Impulse.kr(30),
            "/rekriate_meter",
            [Amplitude.kr(sig[0]), Amplitude.kr(sig[1])],
            meter_id
        );
    }).add;

    s.sync;

    ">> rekriate mixer SynthDefs loaded (channel_strip / aux / mixer_master)".postln;

    // ─────────────────────────────────────────────
    // Free prior simple-mixer state in the voice engine (if loaded).
    // ─────────────────────────────────────────────
    //
    // The simple mixer in rekriate-voice.scd registers
    // /rekriate/mixer/track/{n}/{level,pan,mute} and
    // /rekriate/mixer/master/level responders that drive persistent
    // trackstrip/master synths. When this mixer takes over it frees those
    // synths and their responders so the new chain is authoritative.

    if (~rekriate.notNil, {
        var killed = 0;

        // Release any active voice so we don't leave orphans mid-note.
        ~rekriate[\tracks].do({ |ts|
            if (ts[\synth].notNil, {
                ts[\synth].set(\gate, 0);
                ts[\synth] = nil;
            });
            if (ts[\strip].notNil, {
                ts[\strip].free;
                ts[\strip] = nil;
            });
        });
        if (~rekriate[\master].notNil, {
            ~rekriate[\master].free;
            ~rekriate[\master] = nil;
        });

        // Free just the mixer responders, leave note/portamento alone.
        if (~rekriate[\responders].notNil, {
            var remaining = List.new;
            ~rekriate[\responders].do({ |r|
                if (r.path.asString.beginsWith("/rekriate/mixer/"), {
                    r.free;
                    killed = killed + 1;
                }, {
                    remaining.add(r);
                });
            });
            ~rekriate[\responders] = remaining;
        });

        ">> rekriate mixer: tore down simple mixer (% responders freed)"
            .format(killed).postln;
    });

    // ─────────────────────────────────────────────
    // Allocate buses, groups, and per-section state.
    // ─────────────────────────────────────────────

    ~rekriate_mixer = IdentityDictionary.new;
    ~rekriate_mixer[\channels]   = IdentityDictionary.new;
    ~rekriate_mixer[\responders] = List.new;
    ~rekriate_mixer[\buses]      = IdentityDictionary.new;
    ~rekriate_mixer[\groups]     = IdentityDictionary.new;
    ~rekriate_mixer[\meterTarget] = nil;       // NetAddr|nil
    ~rekriate_mixer[\meterListener] = nil;     // OSCdef

    // 4 mono channel buses, stereo aux send + aux return.
    ~rekriate_mixer[\buses][\channel]   = Array.fill(4, { Bus.audio(s, 1) });
    ~rekriate_mixer[\buses][\auxSend]   = Bus.audio(s, 2);
    ~rekriate_mixer[\buses][\auxReturn] = Bus.audio(s, 2);

    // Ordered groups: voices → channels → aux → master.
    ~rekriate_mixer[\groups][\voices]   = Group.new(s);
    ~rekriate_mixer[\groups][\channels] =
        Group.after(~rekriate_mixer[\groups][\voices]);
    ~rekriate_mixer[\groups][\aux]      =
        Group.after(~rekriate_mixer[\groups][\channels]);
    ~rekriate_mixer[\groups][\master]   =
        Group.after(~rekriate_mixer[\groups][\aux]);

    // Default channel state (mirrors strip args; used for dump + recall).
    ~rekriate_mixer[\channelDefaults] = (
        level: 0.8, pan: 0.0, mute: 0, send: 0.0,
        filter_type: 0, filter_freq: 10000, filter_res: 0.3,
        reverb_mix: 0.0, reverb_room: 0.5, reverb_damp: 0.5,
        delay_mix: 0.0, delay_time: 0.375, delay_feedback: 0.3,
        comp_thresh: 0.5, comp_ratio: 1.0,
        comp_attack: 0.01, comp_release: 0.1
    );
    ~rekriate_mixer[\auxDefaults] = (
        level: 0.8,
        reverb_mix: 0.6, reverb_room: 0.7, reverb_damp: 0.4,
        delay_mix: 0.3, delay_time: 0.375, delay_feedback: 0.4
    );
    ~rekriate_mixer[\masterDefaults] = (
        level: 0.8, aux_return_level: 0.5
    );

    // Spawn one channel strip synth per channel.
    4.do({ |i|
        var n = i + 1;
        var bus = ~rekriate_mixer[\buses][\channel][i];
        var args = List.new;
        args.addAll([
            \in_bus,  bus.index,
            \out_bus, 0,
            \aux_bus, ~rekriate_mixer[\buses][\auxSend].index,
            \meter_id, n
        ]);
        ~rekriate_mixer[\channelDefaults].keysValuesDo({ |k, v|
            args.addAll([k, v]);
        });
        ~rekriate_mixer[\channels][n] = IdentityDictionary.new;
        ~rekriate_mixer[\channels][n][\bus]   = bus;
        ~rekriate_mixer[\channels][n][\state] =
            ~rekriate_mixer[\channelDefaults].copy;
        ~rekriate_mixer[\channels][n][\strip] = Synth.new(
            \rekriate_channel_strip, args.asArray,
            ~rekriate_mixer[\groups][\channels]
        );
    });

    // Aux synth.
    ~rekriate_mixer[\aux] = IdentityDictionary.new;
    ~rekriate_mixer[\aux][\state] = ~rekriate_mixer[\auxDefaults].copy;
    {
        var args = List.new;
        args.addAll([
            \in_bus,   ~rekriate_mixer[\buses][\auxSend].index,
            \out_bus,  ~rekriate_mixer[\buses][\auxReturn].index,
            \meter_id, 5
        ]);
        ~rekriate_mixer[\auxDefaults].keysValuesDo({ |k, v|
            args.addAll([k, v]);
        });
        ~rekriate_mixer[\aux][\synth] = Synth.new(
            \rekriate_aux, args.asArray,
            ~rekriate_mixer[\groups][\aux]
        );
    }.value;

    // Master synth.
    ~rekriate_mixer[\master] = IdentityDictionary.new;
    ~rekriate_mixer[\master][\state] = ~rekriate_mixer[\masterDefaults].copy;
    {
        var args = List.new;
        args.addAll([
            \aux_return_bus, ~rekriate_mixer[\buses][\auxReturn].index,
            \out_bus,        0,
            \meter_id,       6
        ]);
        ~rekriate_mixer[\masterDefaults].keysValuesDo({ |k, v|
            args.addAll([k, v]);
        });
        ~rekriate_mixer[\master][\synth] = Synth.new(
            \rekriate_mixer_master, args.asArray,
            ~rekriate_mixer[\groups][\master]
        );
    }.value;

    // ─────────────────────────────────────────────
    // Voice routing patch (if voice engine loaded).
    // ─────────────────────────────────────────────
    //
    // Replaces ~rekriate[\playNote] so new voices spawn inside the mixer's
    // voices group and write to the channel bus. The voice synth is still
    // the existing mono \rekriate_voice — channel strips upmix internally.

    if (~rekriate.notNil and: { ~rekriate[\tracks].notNil }, {
        ~rekriate[\playNote] = { |trackNum, midiNote, velocity, duration|
            var trackState   = ~rekriate[\tracks][trackNum];
            var channelEntry = ~rekriate_mixer[\channels][trackNum];
            var channelBus   = channelEntry[\bus];
            var voiceGroup   = ~rekriate_mixer[\groups][\voices];
            var freq    = midiNote.midicps;
            var vel     = velocity.linlin(0, 127, 0, 1);
            var lagTime = trackState[\portamento] ? 0;
            var existing = trackState[\synth];

            if (lagTime > 0 && existing.notNil, {
                existing.set(\freq, freq, \vel, vel,
                    \amp, 0.3, \lagTime, lagTime);
                SystemClock.sched(duration, {
                    existing.set(\gate, 0);
                    trackState[\synth] = nil;
                    nil;
                });
            }, {
                if (existing.notNil, { existing.set(\gate, 0) });
                trackState[\synth] = Synth.new(\rekriate_voice, [
                    \freq,    freq,
                    \vel,     vel,
                    \amp,     0.3,
                    \lagTime, lagTime,
                    \gate,    1,
                    \out,     channelBus.index,
                ], voiceGroup);
                SystemClock.sched(duration, {
                    var synth = trackState[\synth];
                    if (synth.notNil, {
                        synth.set(\gate, 0);
                        trackState[\synth] = nil;
                    });
                    nil;
                });
            });

            "  mixer track %  ch=%  note=%  vel=%  dur=%  glide=%".format(
                trackNum, channelBus.index, midiNote, velocity,
                duration.round(0.01), lagTime
            ).postln;
        };
        ">> rekriate mixer: patched ~rekriate[\\playNote] for channel routing".postln;
    });

    // ─────────────────────────────────────────────
    // OSC responders
    // ─────────────────────────────────────────────

    // Helper: float setter for a channel param that also mirrors state.
    ~rekriate_mixer[\addChannelParam] = { |param, lo=nil, hi=nil|
        4.do({ |i|
            var n = i + 1;
            var path = "/rekriate/mixer/channel/" ++ n ++ "/" ++ param;
            ~rekriate_mixer[\responders].add(
                OSCFunc({ |msg|
                    var v = msg[1] ? 0;
                    if (lo.notNil and: { hi.notNil }, { v = v.clip(lo, hi) });
                    ~rekriate_mixer[\channels][n][\state][param] = v;
                    ~rekriate_mixer[\channels][n][\strip].set(param, v);
                }, path)
            );
        });
    };

    // Integer/boolean setter for a channel param.
    ~rekriate_mixer[\addChannelIntParam] = { |param, lo, hi|
        4.do({ |i|
            var n = i + 1;
            var path = "/rekriate/mixer/channel/" ++ n ++ "/" ++ param;
            ~rekriate_mixer[\responders].add(
                OSCFunc({ |msg|
                    var v = (msg[1] ? 0).asInteger.clip(lo, hi);
                    ~rekriate_mixer[\channels][n][\state][param] = v;
                    ~rekriate_mixer[\channels][n][\strip].set(param, v);
                }, path)
            );
        });
    };

    // Channel: gain/mix controls
    ~rekriate_mixer[\addChannelParam].value(\level, 0, 2);
    ~rekriate_mixer[\addChannelParam].value(\pan,  -1, 1);
    ~rekriate_mixer[\addChannelIntParam].value(\mute, 0, 1);
    ~rekriate_mixer[\addChannelParam].value(\send,  0, 1);

    // Channel: filter
    ~rekriate_mixer[\addChannelIntParam].value(\filter_type, 0, 2);
    ~rekriate_mixer[\addChannelParam].value(\filter_freq, 20, 18000);
    ~rekriate_mixer[\addChannelParam].value(\filter_res, 0, 1);

    // Channel: reverb (insert)
    ~rekriate_mixer[\addChannelParam].value(\reverb_mix, 0, 1);
    ~rekriate_mixer[\addChannelParam].value(\reverb_room, 0, 1);
    ~rekriate_mixer[\addChannelParam].value(\reverb_damp, 0, 1);

    // Channel: delay (insert)
    ~rekriate_mixer[\addChannelParam].value(\delay_mix, 0, 1);
    ~rekriate_mixer[\addChannelParam].value(\delay_time, 0.001, 2.0);
    ~rekriate_mixer[\addChannelParam].value(\delay_feedback, 0, 0.95);

    // Channel: compressor
    ~rekriate_mixer[\addChannelParam].value(\comp_thresh, 0, 1);
    ~rekriate_mixer[\addChannelParam].value(\comp_ratio, 1, 20);
    ~rekriate_mixer[\addChannelParam].value(\comp_attack, 0.001, 0.5);
    ~rekriate_mixer[\addChannelParam].value(\comp_release, 0.01, 1.0);

    // Aux params
    ~rekriate_mixer[\addAuxParam] = { |param, lo=nil, hi=nil|
        var path = "/rekriate/mixer/aux/" ++ param;
        ~rekriate_mixer[\responders].add(
            OSCFunc({ |msg|
                var v = msg[1] ? 0;
                if (lo.notNil and: { hi.notNil }, { v = v.clip(lo, hi) });
                ~rekriate_mixer[\aux][\state][param] = v;
                ~rekriate_mixer[\aux][\synth].set(param, v);
            }, path)
        );
    };
    ~rekriate_mixer[\addAuxParam].value(\level, 0, 2);
    ~rekriate_mixer[\addAuxParam].value(\reverb_mix, 0, 1);
    ~rekriate_mixer[\addAuxParam].value(\reverb_room, 0, 1);
    ~rekriate_mixer[\addAuxParam].value(\reverb_damp, 0, 1);
    ~rekriate_mixer[\addAuxParam].value(\delay_mix, 0, 1);
    ~rekriate_mixer[\addAuxParam].value(\delay_time, 0.001, 2.0);
    ~rekriate_mixer[\addAuxParam].value(\delay_feedback, 0, 0.95);

    // Master params
    ~rekriate_mixer[\addMasterParam] = { |param, lo=nil, hi=nil|
        var path = "/rekriate/mixer/master/" ++ param;
        ~rekriate_mixer[\responders].add(
            OSCFunc({ |msg|
                var v = msg[1] ? 0;
                if (lo.notNil and: { hi.notNil }, { v = v.clip(lo, hi) });
                ~rekriate_mixer[\master][\state][param] = v;
                ~rekriate_mixer[\master][\synth].set(param, v);
            }, path)
        );
    };
    ~rekriate_mixer[\addMasterParam].value(\level, 0, 2);
    ~rekriate_mixer[\addMasterParam].value(\aux_return_level, 0, 2);

    // ─────────────────────────────────────────────
    // Metering: SendReply capture + forward to configurable target.
    // ─────────────────────────────────────────────
    //
    // SynthDefs emit /rekriate_meter with [l_peak, r_peak] replyIDs:
    //   1..4 → channels, 5 → aux, 6 → master.
    // We register a single lang-side OSCdef that rebroadcasts to the
    // configured NetAddr as /rekriate/mixer/meter/channel/{n} (or /aux, /master).
    // If no target is configured, meter messages are simply dropped.

    ~rekriate_mixer[\meterListener] = OSCdef(\rekriate_mixer_meter, { |msg|
        var replyId = msg[2].asInteger;
        var l = msg[3], r = msg[4];
        var target = ~rekriate_mixer[\meterTarget];
        var outPath = nil;

        if (target.notNil, {
            if (replyId >= 1 and: { replyId <= 4 }, {
                outPath = "/rekriate/mixer/meter/channel/" ++ replyId;
            });
            if (replyId == 5, { outPath = "/rekriate/mixer/meter/aux" });
            if (replyId == 6, { outPath = "/rekriate/mixer/meter/master" });
            if (outPath.notNil, { target.sendMsg(outPath, l, r) });
        });
    }, "/rekriate_meter");

    // Meter target configuration OSC responders.
    ~rekriate_mixer[\responders].add(
        OSCFunc({ |msg|
            var host = (msg[1] ? "127.0.0.1").asString;
            var port = (msg[2] ? 57121).asInteger;
            ~rekriate_mixer[\meterTarget] = NetAddr(host, port);
            "  mixer meter target set to %:%".format(host, port).postln;
        }, "/rekriate/mixer/meter/target")
    );
    ~rekriate_mixer[\responders].add(
        OSCFunc({ |msg|
            ~rekriate_mixer[\meterTarget] = nil;
            "  mixer meter target disabled".postln;
        }, "/rekriate/mixer/meter/off")
    );

    // ─────────────────────────────────────────────
    // Bulk: dump full mixer state to the meter target.
    // ─────────────────────────────────────────────

    ~rekriate_mixer[\responders].add(
        OSCFunc({ |msg|
            var target = ~rekriate_mixer[\meterTarget];
            if (target.isNil, {
                "  mixer state/dump: no meter target configured".postln;
            }, {
                4.do({ |i|
                    var n = i + 1;
                    var state = ~rekriate_mixer[\channels][n][\state];
                    state.keysValuesDo({ |k, v|
                        target.sendMsg(
                            "/rekriate/mixer/channel/" ++ n ++ "/" ++ k,
                            v
                        );
                    });
                });
                ~rekriate_mixer[\aux][\state].keysValuesDo({ |k, v|
                    target.sendMsg("/rekriate/mixer/aux/" ++ k, v);
                });
                ~rekriate_mixer[\master][\state].keysValuesDo({ |k, v|
                    target.sendMsg("/rekriate/mixer/master/" ++ k, v);
                });
                "  mixer state/dump: sent to %".format(target).postln;
            });
        }, "/rekriate/mixer/state/dump")
    );

    // ─────────────────────────────────────────────
    // Ready
    // ─────────────────────────────────────────────

    "";
    "╔══════════════════════════════════════════╗".postln;
    "║  re.kriate mixer engine ready            ║".postln;
    "║  4 channels → aux send/return → master   ║".postln;
    "║  responders on /rekriate/mixer/…         ║".postln;
    "║  metering at 30 Hz (set target to fwd)   ║".postln;
    "╚══════════════════════════════════════════╝".postln;
    "";
});
)

// ─────────────────────────────────────────────
// Cleanup: evaluate this block to free mixer state.
// ─────────────────────────────────────────────

~rekriate_mixer_cleanup = {
    if (~rekriate_mixer.notNil, {
        // Responders
        if (~rekriate_mixer[\responders].notNil, {
            ~rekriate_mixer[\responders].do({ |r| r.free });
            ~rekriate_mixer[\responders].clear;
        });
        if (~rekriate_mixer[\meterListener].notNil, {
            ~rekriate_mixer[\meterListener].free;
        });

        // Synths
        if (~rekriate_mixer[\channels].notNil, {
            ~rekriate_mixer[\channels].do({ |c|
                if (c[\strip].notNil, { c[\strip].free });
            });
        });
        if (~rekriate_mixer[\aux].notNil and: { ~rekriate_mixer[\aux][\synth].notNil }, {
            ~rekriate_mixer[\aux][\synth].free;
        });
        if (~rekriate_mixer[\master].notNil and: { ~rekriate_mixer[\master][\synth].notNil }, {
            ~rekriate_mixer[\master][\synth].free;
        });

        // Groups (free anything still inside them)
        if (~rekriate_mixer[\groups].notNil, {
            [\master, \aux, \channels, \voices].do({ |key|
                var g = ~rekriate_mixer[\groups][key];
                if (g.notNil, { g.free });
            });
        });

        // Buses
        if (~rekriate_mixer[\buses].notNil, {
            ~rekriate_mixer[\buses][\channel].do({ |b| b.free });
            if (~rekriate_mixer[\buses][\auxSend].notNil, {
                ~rekriate_mixer[\buses][\auxSend].free;
            });
            if (~rekriate_mixer[\buses][\auxReturn].notNil, {
                ~rekriate_mixer[\buses][\auxReturn].free;
            });
        });

        ~rekriate_mixer = nil;
        ">> rekriate mixer engine stopped".postln;
    });
};
