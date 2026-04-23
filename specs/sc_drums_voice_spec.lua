-- specs/sc_drums_voice_spec.lua
-- Tests for SuperCollider drum voice backend

package.path = package.path .. ";./?.lua"

-- Mock clock
local beat_counter = 0
local next_coro_id = 1
local cancelled_coros = {}
local clock_run_fns = {}

rawset(_G, "clock", {
  get_beats = function() return beat_counter end,
  run = function(fn)
    local id = next_coro_id
    next_coro_id = next_coro_id + 1
    clock_run_fns[id] = fn
    return id
  end,
  cancel = function(id)
    cancelled_coros[id] = true
    clock_run_fns[id] = nil
  end,
  sync = function() end,
})

-- Mock osc — capture sends for test assertions
local osc_sent = {}
rawset(_G, "osc", {
  send = function(target, path, args)
    table.insert(osc_sent, { target = target, path = path, args = args })
  end,
})

local sc_drums = require("lib/voices/sc_drums")

local function reset()
  beat_counter = 0
  next_coro_id = 1
  cancelled_coros = {}
  clock_run_fns = {}
  osc_sent = {}
end

describe("sc_drums voice", function()

  before_each(function()
    reset()
  end)

  describe("construction", function()
    it("stores track number and target", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      assert.are.equal(1, voice.track_num)
      assert.are.same({"127.0.0.1", 57120}, voice.target)
    end)

    it("starts with empty active_notes", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      assert.are.same({}, voice.active_notes)
    end)
  end)

  describe("play_note", function()
    it("sends /drum OSC message with note, velocity, duration", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:play_note(60, 0.8, 0.5)
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/track/1/drum", osc_sent[1].path)
      assert.are.same({60, 0.8, 0.5}, osc_sent[1].args)
      assert.are.same({"127.0.0.1", 57120}, osc_sent[1].target)
    end)

    it("schedules a clock coroutine for note-off", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:play_note(60, 0.8, 0.5)
      assert.is_not_nil(voice.active_notes[60])
      assert.is_not_nil(clock_run_fns[voice.active_notes[60]])
    end)

    it("uses track number in OSC path", function()
      local voice = sc_drums.new(3, "127.0.0.1", 57120)
      voice:play_note(64, 0.5, 1)
      assert.are.equal("/rekriate/track/3/drum", osc_sent[1].path)
    end)

    it("sends to configured target", function()
      local voice = sc_drums.new(1, "10.0.0.1", 7400)
      voice:play_note(60, 0.8, 0.5)
      assert.are.same({"10.0.0.1", 7400}, osc_sent[1].target)
    end)
  end)

  describe("note_on", function()
    it("sends /drum with duration 0", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:note_on(60, 0.7)
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/track/1/drum", osc_sent[1].path)
      assert.are.same({60, 0.7, 0}, osc_sent[1].args)
    end)
  end)

  describe("note_off", function()
    it("sends /drum_off message", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:note_off(60)
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/track/1/drum_off", osc_sent[1].path)
      assert.are.same({60}, osc_sent[1].args)
    end)

    it("cancels pending coroutine if note is active", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:play_note(60, 0.8, 0.5)
      local coro_id = voice.active_notes[60]
      osc_sent = {}
      voice:note_off(60)
      assert.is_true(cancelled_coros[coro_id])
      assert.is_nil(voice.active_notes[60])
    end)

    it("does not error when note is not active", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      assert.has_no.errors(function()
        voice:note_off(60)
      end)
    end)
  end)

  describe("all_notes_off", function()
    it("cancels all active coroutines and sends drum_off + all_drums_off", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:play_note(60, 0.8, 0.5)
      voice:play_note(64, 0.7, 0.5)
      local coro1 = voice.active_notes[60]
      local coro2 = voice.active_notes[64]
      osc_sent = {}

      voice:all_notes_off()

      assert.is_true(cancelled_coros[coro1])
      assert.is_true(cancelled_coros[coro2])
      assert.are.same({}, voice.active_notes)

      -- Should have sent drum_off for each active note + all_drums_off
      local drum_off_count = 0
      local all_off_count = 0
      for _, msg in ipairs(osc_sent) do
        if msg.path:match("/drum_off$") then
          drum_off_count = drum_off_count + 1
        elseif msg.path:match("/all_drums_off$") then
          all_off_count = all_off_count + 1
        end
      end
      assert.are.equal(2, drum_off_count)
      assert.are.equal(1, all_off_count)
    end)

    it("sends all_drums_off even with no active notes", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:all_notes_off()
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/track/1/all_drums_off", osc_sent[1].path)
    end)
  end)

  describe("set_portamento", function()
    it("sends /drum_portamento message", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:set_portamento(3)
      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/track/1/drum_portamento", osc_sent[1].path)
      assert.are.same({3}, osc_sent[1].args)
    end)

    it("sends 0 for nil portamento", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:set_portamento(nil)
      assert.are.equal(1, #osc_sent)
      assert.are.same({0}, osc_sent[1].args)
    end)
  end)

  describe("set_target", function()
    it("updates OSC target for subsequent messages", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:set_target("10.0.0.1", 7400)
      voice:play_note(60, 0.8, 0.5)
      assert.are.same({"10.0.0.1", 7400}, osc_sent[1].target)
    end)
  end)

  describe("note-off coroutine", function()
    it("sends drum_off and clears active_notes when fired", function()
      local voice = sc_drums.new(1, "127.0.0.1", 57120)
      voice:play_note(60, 0.8, 0.5)
      local coro_id = voice.active_notes[60]
      local fn = clock_run_fns[coro_id]
      osc_sent = {}

      -- Simulate coroutine completing
      fn()

      assert.are.equal(1, #osc_sent)
      assert.are.equal("/rekriate/track/1/drum_off", osc_sent[1].path)
      assert.are.same({60}, osc_sent[1].args)
      assert.is_nil(voice.active_notes[60])
    end)
  end)

  describe("multi-track isolation", function()
    it("different tracks send to different OSC paths", function()
      local v1 = sc_drums.new(1, "127.0.0.1", 57120)
      local v2 = sc_drums.new(2, "127.0.0.1", 57120)
      v1:play_note(60, 0.8, 0.5)
      v2:play_note(64, 0.7, 0.5)
      assert.are.equal("/rekriate/track/1/drum", osc_sent[1].path)
      assert.are.equal("/rekriate/track/2/drum", osc_sent[2].path)
    end)
  end)

end)
