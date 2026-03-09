-- specs/events_spec.lua
-- Tests for lib/events.lua

package.path = package.path .. ";./?.lua"

local events = require("lib/events")

describe("events", function()

  local bus

  before_each(function()
    bus = events.new()
  end)

  describe("new", function()
    it("creates an independent bus instance", function()
      assert.is_not_nil(bus)
      assert.is_table(bus)
    end)

    it("multiple instances are independent", function()
      local bus_a = events.new()
      local bus_b = events.new()
      local a_called = false
      local b_called = false

      bus_a:on("test:event", function() a_called = true end)
      bus_b:on("test:event", function() b_called = true end)

      bus_a:emit("test:event")
      assert.is_true(a_called)
      assert.is_false(b_called)

      bus_b:emit("test:event")
      assert.is_true(b_called)
    end)
  end)

  describe("on / emit", function()
    it("calls handler when event is emitted", function()
      local received = nil
      bus:on("voice:note", function(data)
        received = data
      end)
      bus:emit("voice:note", {note = 60})
      assert.is_not_nil(received)
      assert.are.equal(60, received.note)
    end)

    it("passes data table to handler", function()
      local got = {}
      bus:on("sequencer:step", function(data)
        got.track = data.track
        got.step = data.step_num
      end)
      bus:emit("sequencer:step", {track = 2, step_num = 5})
      assert.are.equal(2, got.track)
      assert.are.equal(5, got.step)
    end)

    it("provides empty table when no data given", function()
      local received = nil
      bus:on("sequencer:start", function(data)
        received = data
      end)
      bus:emit("sequencer:start")
      assert.is_table(received)
    end)
  end)

  describe("multiple subscribers", function()
    it("calls all handlers in FIFO order", function()
      local order = {}
      bus:on("test:event", function() table.insert(order, "first") end)
      bus:on("test:event", function() table.insert(order, "second") end)
      bus:on("test:event", function() table.insert(order, "third") end)
      bus:emit("test:event")
      assert.are.same({"first", "second", "third"}, order)
    end)

    it("each handler gets its own copy of data", function()
      local data_a, data_b
      bus:on("test:event", function(data)
        data.mutated = true
        data_a = data
      end)
      bus:on("test:event", function(data)
        data_b = data
      end)
      bus:emit("test:event", {value = 1})
      assert.is_true(data_a.mutated)
      assert.is_nil(data_b.mutated) -- second handler got a clean copy
    end)
  end)

  describe("unsubscribe via returned function", function()
    it("removes the handler", function()
      local count = 0
      local unsub = bus:on("test:event", function() count = count + 1 end)
      bus:emit("test:event")
      assert.are.equal(1, count)

      unsub()
      bus:emit("test:event")
      assert.are.equal(1, count) -- not called again
    end)

    it("is idempotent (calling twice is safe)", function()
      local unsub = bus:on("test:event", function() end)
      unsub()
      unsub() -- should not error
    end)

    it("only removes the specific handler", function()
      local a_count, b_count = 0, 0
      local unsub_a = bus:on("test:event", function() a_count = a_count + 1 end)
      bus:on("test:event", function() b_count = b_count + 1 end)

      unsub_a()
      bus:emit("test:event")
      assert.are.equal(0, a_count)
      assert.are.equal(1, b_count)
    end)
  end)

  describe("off", function()
    it("removes all handlers for an event", function()
      local count = 0
      bus:on("test:event", function() count = count + 1 end)
      bus:on("test:event", function() count = count + 1 end)
      bus:off("test:event")
      bus:emit("test:event")
      assert.are.equal(0, count)
    end)

    it("does not affect other events", function()
      local a_count, b_count = 0, 0
      bus:on("event:a", function() a_count = a_count + 1 end)
      bus:on("event:b", function() b_count = b_count + 1 end)
      bus:off("event:a")
      bus:emit("event:a")
      bus:emit("event:b")
      assert.are.equal(0, a_count)
      assert.are.equal(1, b_count)
    end)
  end)

  describe("clear", function()
    it("removes all handlers from all events", function()
      local count = 0
      bus:on("event:a", function() count = count + 1 end)
      bus:on("event:b", function() count = count + 1 end)
      bus:on("event:*", function() count = count + 1 end)
      bus:clear()
      bus:emit("event:a")
      bus:emit("event:b")
      assert.are.equal(0, count)
    end)
  end)

  describe("count", function()
    it("returns 0 for events with no handlers", function()
      assert.are.equal(0, bus:count("nonexistent:event"))
    end)

    it("returns correct count after subscribe", function()
      bus:on("test:event", function() end)
      bus:on("test:event", function() end)
      assert.are.equal(2, bus:count("test:event"))
    end)

    it("updates after unsubscribe", function()
      local unsub = bus:on("test:event", function() end)
      bus:on("test:event", function() end)
      assert.are.equal(2, bus:count("test:event"))
      unsub()
      assert.are.equal(1, bus:count("test:event"))
    end)

    it("returns 0 after off", function()
      bus:on("test:event", function() end)
      bus:off("test:event")
      assert.are.equal(0, bus:count("test:event"))
    end)

    it("counts wildcard handlers separately", function()
      bus:on("test:event", function() end)
      bus:on("test:*", function() end)
      assert.are.equal(1, bus:count("test:event"))
      assert.are.equal(1, bus:count("test:*"))
    end)
  end)

  describe("wildcard subscriptions", function()
    it("matches events with matching prefix", function()
      local received = {}
      bus:on("note:*", function(event_name, data)
        table.insert(received, {event = event_name, data = data})
      end)
      bus:emit("note:fired", {n = 60})
      bus:emit("note:off", {n = 60})
      assert.are.equal(2, #received)
      assert.are.equal("note:fired", received[1].event)
      assert.are.equal("note:off", received[2].event)
    end)

    it("does not match events without colon suffix", function()
      local called = false
      bus:on("note:*", function()
        called = true
      end)
      -- "note" alone has no colon, so wildcard "note:*" should not match
      bus:emit("note")
      assert.is_false(called)
    end)

    it("does not match unrelated prefixes", function()
      local called = false
      bus:on("note:*", function()
        called = true
      end)
      bus:emit("voice:note", {})
      assert.is_false(called)
    end)

    it("handler receives event_name and data", function()
      local got_name, got_data
      bus:on("seq:*", function(event_name, data)
        got_name = event_name
        got_data = data
      end)
      bus:emit("seq:step", {track = 1})
      assert.are.equal("seq:step", got_name)
      assert.are.equal(1, got_data.track)
    end)

    it("can be unsubscribed via returned function", function()
      local count = 0
      local unsub = bus:on("test:*", function() count = count + 1 end)
      bus:emit("test:foo")
      assert.are.equal(1, count)
      unsub()
      bus:emit("test:bar")
      assert.are.equal(1, count)
    end)

    it("off removes wildcard handlers", function()
      local count = 0
      bus:on("test:*", function() count = count + 1 end)
      bus:off("test:*")
      bus:emit("test:foo")
      assert.are.equal(0, count)
    end)

    it("both exact and wildcard handlers fire", function()
      local exact_called = false
      local wild_called = false
      bus:on("voice:note", function() exact_called = true end)
      bus:on("voice:*", function() wild_called = true end)
      bus:emit("voice:note", {})
      assert.is_true(exact_called)
      assert.is_true(wild_called)
    end)
  end)

  describe("once", function()
    it("fires only once then auto-unsubscribes", function()
      local count = 0
      bus:once("test:event", function() count = count + 1 end)
      bus:emit("test:event")
      bus:emit("test:event")
      bus:emit("test:event")
      assert.are.equal(1, count)
    end)

    it("receives data like a regular handler", function()
      local received = nil
      bus:once("test:event", function(data) received = data end)
      bus:emit("test:event", {val = 42})
      assert.are.equal(42, received.val)
    end)

    it("can be unsubscribed before firing", function()
      local count = 0
      local unsub = bus:once("test:event", function() count = count + 1 end)
      unsub()
      bus:emit("test:event")
      assert.are.equal(0, count)
    end)

    it("works with wildcards", function()
      local received_events = {}
      bus:once("test:*", function(event_name, data)
        table.insert(received_events, event_name)
      end)
      bus:emit("test:foo")
      bus:emit("test:bar")
      assert.are.equal(1, #received_events)
      assert.are.equal("test:foo", received_events[1])
    end)

    it("count decreases after once fires", function()
      bus:once("test:event", function() end)
      assert.are.equal(1, bus:count("test:event"))
      bus:emit("test:event")
      assert.are.equal(0, bus:count("test:event"))
    end)
  end)

  describe("error handling", function()
    it("does not crash the bus when a handler errors", function()
      local second_called = false
      bus:on("test:event", function()
        error("handler blew up")
      end)
      bus:on("test:event", function()
        second_called = true
      end)
      -- should not throw
      bus:emit("test:event")
      assert.is_true(second_called)
    end)

    it("prints error message (captured via stub)", function()
      -- We can't easily capture print output in busted, but we can
      -- verify the bus survives and other handlers still fire
      local count = 0
      bus:on("test:event", function() error("boom") end)
      bus:on("test:event", function() count = count + 1 end)
      bus:emit("test:event")
      assert.are.equal(1, count)
    end)

    it("error in wildcard handler does not crash bus", function()
      local exact_called = false
      bus:on("test:*", function() error("wild boom") end)
      bus:on("test:event", function() exact_called = true end)
      bus:emit("test:event")
      assert.is_true(exact_called)
    end)
  end)

  describe("re-entrancy", function()
    it("emitting from within a handler works", function()
      local inner_called = false
      bus:on("outer:event", function()
        bus:emit("inner:event", {})
      end)
      bus:on("inner:event", function()
        inner_called = true
      end)
      bus:emit("outer:event")
      assert.is_true(inner_called)
    end)

    it("subscribing from within a handler works", function()
      local late_called = false
      bus:on("setup:event", function()
        bus:on("late:event", function()
          late_called = true
        end)
      end)
      bus:emit("setup:event")
      bus:emit("late:event")
      assert.is_true(late_called)
    end)

    it("unsubscribing from within a handler is safe", function()
      local unsub_b
      local order = {}

      bus:on("test:event", function()
        table.insert(order, "a")
        unsub_b() -- remove b during iteration
      end)
      unsub_b = bus:on("test:event", function()
        table.insert(order, "b")
      end)
      bus:on("test:event", function()
        table.insert(order, "c")
      end)

      bus:emit("test:event")
      -- "a" fires, removes "b", "b" should NOT fire, "c" should fire
      assert.are.same({"a", "c"}, order)
    end)
  end)

  describe("safe iteration / unsubscribe during emit", function()
    it("handler removing itself does not skip next handler", function()
      local order = {}
      local unsub_self

      unsub_self = bus:on("test:event", function()
        table.insert(order, "self-removing")
        unsub_self()
      end)
      bus:on("test:event", function()
        table.insert(order, "next")
      end)

      bus:emit("test:event")
      assert.are.same({"self-removing", "next"}, order)
    end)

    it("all handlers removing themselves is safe", function()
      local count = 0
      local unsubs = {}
      for i = 1, 5 do
        unsubs[i] = bus:on("test:event", function()
          count = count + 1
          unsubs[i]()
        end)
      end
      bus:emit("test:event")
      assert.are.equal(5, count)
      assert.are.equal(0, bus:count("test:event"))
    end)
  end)

  describe("no subscribers", function()
    it("emitting to an event with no subscribers is a no-op", function()
      -- should not error
      bus:emit("nonexistent:event", {data = true})
    end)

    it("emitting with nil data and no subscribers is safe", function()
      bus:emit("nothing:here")
    end)
  end)

  describe("event data immutability", function()
    it("handlers receive independent copies of data", function()
      local copies = {}
      bus:on("test:event", function(data)
        data.x = 999
        table.insert(copies, data)
      end)
      bus:on("test:event", function(data)
        table.insert(copies, data)
      end)

      bus:emit("test:event", {x = 1})
      assert.are.equal(999, copies[1].x)
      assert.are.equal(1, copies[2].x) -- unaffected by first handler
    end)

    it("original data table is not modified", function()
      bus:on("test:event", function(data)
        data.corrupted = true
      end)

      local original = {value = 42}
      bus:emit("test:event", original)
      assert.is_nil(original.corrupted)
    end)
  end)

  describe("handler execution order", function()
    it("exact handlers fire in subscription order (FIFO)", function()
      local order = {}
      for i = 1, 5 do
        bus:on("test:event", function()
          table.insert(order, i)
        end)
      end
      bus:emit("test:event")
      assert.are.same({1, 2, 3, 4, 5}, order)
    end)

    it("exact handlers fire before wildcard handlers", function()
      local order = {}
      bus:on("test:*", function()
        table.insert(order, "wild")
      end)
      bus:on("test:event", function()
        table.insert(order, "exact")
      end)
      bus:emit("test:event")
      -- exact fires first, then wildcard
      assert.are.same({"exact", "wild"}, order)
    end)
  end)

  describe("edge cases", function()
    it("event names with multiple colons work for exact match", function()
      local called = false
      bus:on("deep:nested:event", function() called = true end)
      bus:emit("deep:nested:event")
      assert.is_true(called)
    end)

    it("wildcard on multi-colon events matches first prefix", function()
      local called = false
      bus:on("deep:*", function() called = true end)
      bus:emit("deep:nested:event")
      assert.is_true(called)
    end)

    it("empty data table works", function()
      local received = nil
      bus:on("test:event", function(data) received = data end)
      bus:emit("test:event", {})
      assert.is_table(received)
    end)

    it("numeric data values are preserved", function()
      local received = nil
      bus:on("test:event", function(data) received = data end)
      bus:emit("test:event", {note = 60, vel = 0.8, dur = 0.25})
      assert.are.equal(60, received.note)
      assert.are.equal(0.8, received.vel)
      assert.are.equal(0.25, received.dur)
    end)
  end)

end)
