-- specs/direction_spec.lua
-- Tests for lib/direction.lua

package.path = package.path .. ";./?.lua"

local direction = require("lib/direction")

local function make_param(steps, loop_start, loop_end, pos)
  return {
    steps = steps or {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16},
    loop_start = loop_start or 1,
    loop_end = loop_end or #(steps or {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}),
    pos = pos or (loop_start or 1),
    advancing_forward = true,
  }
end

describe("direction", function()

  describe("MODES", function()
    it("contains all 5 direction modes", function()
      assert.are.same(
        {"forward", "reverse", "pendulum", "drunk", "random"},
        direction.MODES
      )
    end)
  end)

  describe("advance returns the step value at position BEFORE advancing", function()
    it("returns correct value from steps array", function()
      local p = make_param({10, 20, 30, 40, 50, 60, 70, 80}, 1, 8, 1)
      local v1 = direction.advance(p, "forward")
      assert.are.equal(10, v1)  -- value at pos 1 before advancing
      local v2 = direction.advance(p, "forward")
      assert.are.equal(20, v2)  -- value at pos 2 before advancing
      local v3 = direction.advance(p, "forward")
      assert.are.equal(30, v3)  -- value at pos 3 before advancing
    end)
  end)

  describe("forward", function()
    it("steps through positions 1-8 then wraps to 1", function()
      local p = make_param({1,2,3,4,5,6,7,8}, 1, 8, 1)
      local positions = {}
      for i = 1, 9 do
        table.insert(positions, p.pos)
        direction.advance(p, "forward")
      end
      -- positions visited: 1,2,3,4,5,6,7,8, then wraps to 1
      assert.are.same({1,2,3,4,5,6,7,8,1}, positions)
    end)

    it("returns correct values from steps array", function()
      local p = make_param({10, 20, 30, 40, 50, 60, 70, 80}, 1, 8, 1)
      local values = {}
      for _ = 1, 8 do
        table.insert(values, direction.advance(p, "forward"))
      end
      assert.are.same({10, 20, 30, 40, 50, 60, 70, 80}, values)
    end)
  end)

  describe("reverse", function()
    it("steps backward through positions 8-1 then wraps to 8", function()
      local p = make_param({1,2,3,4,5,6,7,8}, 1, 8, 8)
      local positions = {}
      for i = 1, 9 do
        table.insert(positions, p.pos)
        direction.advance(p, "reverse")
      end
      -- positions visited: 8,7,6,5,4,3,2,1, then wraps to 8
      assert.are.same({8,7,6,5,4,3,2,1,8}, positions)
    end)

    it("returns correct values from steps array in reverse", function()
      local p = make_param({10, 20, 30, 40, 50, 60, 70, 80}, 1, 8, 8)
      local values = {}
      for _ = 1, 8 do
        table.insert(values, direction.advance(p, "reverse"))
      end
      assert.are.same({80, 70, 60, 50, 40, 30, 20, 10}, values)
    end)
  end)

  describe("pendulum", function()
    it("bounces back and forth: 1,2,3,4,3,2,1,2", function()
      local p = make_param({10, 20, 30, 40}, 1, 4, 1)
      p.advancing_forward = true
      local positions = {}
      for _ = 1, 8 do
        table.insert(positions, p.pos)
        direction.advance(p, "pendulum")
      end
      assert.are.same({1, 2, 3, 4, 3, 2, 1, 2}, positions)
    end)

    it("returns correct values during pendulum traversal", function()
      local p = make_param({10, 20, 30, 40}, 1, 4, 1)
      p.advancing_forward = true
      local values = {}
      for _ = 1, 8 do
        table.insert(values, direction.advance(p, "pendulum"))
      end
      assert.are.same({10, 20, 30, 40, 30, 20, 10, 20}, values)
    end)

    it("does not crash on single-step loop", function()
      local p = make_param({42}, 1, 1, 1)
      p.advancing_forward = true
      -- should not error and should stay at position 1
      for _ = 1, 5 do
        local v = direction.advance(p, "pendulum")
        assert.are.equal(42, v)
        assert.are.equal(1, p.pos)
      end
    end)
  end)

  describe("drunk", function()
    it("stays within loop bounds after many steps", function()
      local p = make_param({1,2,3,4,5,6,7,8}, 3, 6, 4)
      for _ = 1, 200 do
        direction.advance(p, "drunk")
        assert.is_true(p.pos >= 3, "pos " .. p.pos .. " below loop_start 3")
        assert.is_true(p.pos <= 6, "pos " .. p.pos .. " above loop_end 6")
      end
    end)

    it("returns valid step values", function()
      local p = make_param({10, 20, 30, 40, 50, 60, 70, 80}, 1, 8, 4)
      for _ = 1, 50 do
        local v = direction.advance(p, "drunk")
        assert.is_not_nil(v)
        assert.is_true(v >= 10 and v <= 80)
      end
    end)
  end)

  describe("random", function()
    it("stays within loop bounds after many steps", function()
      local p = make_param({1,2,3,4,5,6,7,8}, 2, 7, 3)
      for _ = 1, 200 do
        direction.advance(p, "random")
        assert.is_true(p.pos >= 2, "pos " .. p.pos .. " below loop_start 2")
        assert.is_true(p.pos <= 7, "pos " .. p.pos .. " above loop_end 7")
      end
    end)

    it("returns valid step values", function()
      local p = make_param({10, 20, 30, 40, 50, 60, 70, 80}, 1, 8, 1)
      for _ = 1, 50 do
        local v = direction.advance(p, "random")
        assert.is_not_nil(v)
      end
    end)
  end)

  -- T021-T024: Quality hardening — direction mode transitions
  describe("direction mode transitions", function()

    -- T021: forward-to-reverse mid-sequence
    it("changing from forward to reverse at step 8 produces step 7 next", function()
      local p = make_param({1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}, 1, 16, 1)
      -- Advance forward to step 8
      for _ = 1, 7 do
        direction.advance(p, "forward")
      end
      assert.are.equal(8, p.pos)

      -- Switch to reverse — next advance should read step 8, then move to step 7
      local val = direction.advance(p, "reverse")
      assert.are.equal(8, val)  -- value at pos 8 before advancing
      assert.are.equal(7, p.pos)  -- now at step 7
    end)

    -- T022: pendulum-to-forward transition
    it("changing from pendulum to forward continues forward from current position", function()
      local p = make_param({10,20,30,40,50,60,70,80}, 1, 8, 1)
      p.advancing_forward = true

      -- Advance in pendulum: 1->2->3->4->5->6->7->8->7->6
      for _ = 1, 9 do
        direction.advance(p, "pendulum")
      end
      -- After 9 advances from pos 1: 1,2,3,4,5,6,7,8,7 -> pos should be 6
      assert.are.equal(6, p.pos)

      -- Switch to forward — should continue forward from 6
      local val = direction.advance(p, "forward")
      assert.are.equal(60, val)  -- value at pos 6
      assert.are.equal(7, p.pos)  -- moved forward to 7

      val = direction.advance(p, "forward")
      assert.are.equal(70, val)
      assert.are.equal(8, p.pos)
    end)

    -- T023: single-step loop direction change
    it("single-step loop stays on that step regardless of direction mode", function()
      local modes = {"forward", "reverse", "pendulum", "drunk", "random"}
      for _, mode in ipairs(modes) do
        local p = make_param({42}, 1, 1, 1)
        p.advancing_forward = true
        for _ = 1, 10 do
          local val = direction.advance(p, mode)
          assert.are.equal(42, val, "value should be 42 in mode: " .. mode)
          assert.are.equal(1, p.pos, "pos should stay 1 in mode: " .. mode)
        end
      end
    end)

    -- T024: drunk mid-change boundary test
    it("switching to drunk keeps all subsequent steps within loop bounds", function()
      local p = make_param({1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}, 5, 12, 5)
      -- Advance forward a few steps
      for _ = 1, 3 do
        direction.advance(p, "forward")
      end
      -- Now switch to drunk and verify bounds for many steps
      for _ = 1, 200 do
        direction.advance(p, "drunk")
        assert.is_true(p.pos >= 5, "pos " .. p.pos .. " below loop_start 5")
        assert.is_true(p.pos <= 12, "pos " .. p.pos .. " above loop_end 12")
      end
    end)

  end)

  describe("nil/missing direction defaults to forward", function()
    it("treats nil direction as forward", function()
      local p = make_param({10, 20, 30, 40}, 1, 4, 1)
      local values = {}
      for _ = 1, 4 do
        table.insert(values, direction.advance(p, nil))
      end
      assert.are.same({10, 20, 30, 40}, values)
      assert.are.equal(1, p.pos) -- wrapped back
    end)

    it("treats missing direction as forward", function()
      local p = make_param({10, 20, 30, 40}, 1, 4, 1)
      local values = {}
      for _ = 1, 4 do
        table.insert(values, direction.advance(p))
      end
      assert.are.same({10, 20, 30, 40}, values)
      assert.are.equal(1, p.pos) -- wrapped back
    end)
  end)

end)
