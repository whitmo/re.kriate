-- specs/scale_spec.lua
-- Tests for lib/scale.lua

package.path = package.path .. ";./?.lua"

-- Mock musicutil before requiring scale
-- C major scale from any root: root, root+2, root+4, root+5, root+7, root+9, root+11, root+12, ...
package.loaded["musicutil"] = {
  generate_scale = function(root, scale_type, num_octaves)
    -- Generate a diatonic-like pattern (whole, whole, half, whole, whole, whole, half)
    local intervals = {0, 2, 4, 5, 7, 9, 11}
    local notes = {}
    for oct = 0, num_octaves - 1 do
      for _, interval in ipairs(intervals) do
        table.insert(notes, root + oct * 12 + interval)
      end
    end
    -- Add the final octave root
    table.insert(notes, root + num_octaves * 12)
    return notes
  end,
}

-- Store the mock so we can modify it for specific tests
local mock_musicutil = package.loaded["musicutil"]

local scale = require("lib/scale")

describe("scale", function()

  describe("build_scale", function()

    it("returns a non-empty array", function()
      local notes = scale.build_scale(60, "Major")
      assert.is_true(#notes > 0)
    end)

    it("calls musicutil.generate_scale with root-36", function()
      -- build_scale(60, "Major") should call generate_scale(60-36=24, "Major", 8)
      local called_root, called_type, called_octaves
      local orig = mock_musicutil.generate_scale
      mock_musicutil.generate_scale = function(root, stype, octaves)
        called_root = root
        called_type = stype
        called_octaves = octaves
        return orig(root, stype, octaves)
      end
      scale.build_scale(60, "Major")
      assert.are.equal(called_root, 24)
      assert.are.equal(called_type, "Major")
      assert.are.equal(called_octaves, 8)
      mock_musicutil.generate_scale = orig
    end)

    it("returns all number values", function()
      local notes = scale.build_scale(60, "Major")
      for i, n in ipairs(notes) do
        assert.are.equal(type(n), "number", "note at index " .. i .. " should be a number")
      end
    end)

    it("returns enough notes for 8 octaves of a 7-note scale", function()
      local notes = scale.build_scale(60, "Major")
      -- 8 octaves * 7 degrees + 1 = 57
      assert.is_true(#notes >= 56, "expected at least 56 notes, got " .. #notes)
    end)

    it("returns ascending notes", function()
      local notes = scale.build_scale(60, "Major")
      for i = 2, #notes do
        assert.is_true(notes[i] >= notes[i - 1],
          "notes should be ascending: index " .. i .. " (" .. notes[i] ..
          ") < index " .. (i - 1) .. " (" .. notes[i - 1] .. ")")
      end
    end)

    it("first note matches root - 36", function()
      local notes = scale.build_scale(60, "Major")
      -- generate_scale is called with root=24, so first note = 24
      assert.are.equal(notes[1], 24)
    end)

    it("different roots produce different note arrays", function()
      local notes_c = scale.build_scale(60, "Major")
      local notes_d = scale.build_scale(62, "Major")
      assert.are_not.same(notes_c, notes_d)
    end)

    it("different scale types produce different note arrays", function()
      -- Mock a second scale type with a different interval pattern
      local orig = mock_musicutil.generate_scale
      local call_count = 0
      mock_musicutil.generate_scale = function(root, stype, octaves)
        call_count = call_count + 1
        if stype == "Minor" then
          -- Minor intervals: 0, 2, 3, 5, 7, 8, 10
          local intervals = {0, 2, 3, 5, 7, 8, 10}
          local notes = {}
          for oct = 0, octaves - 1 do
            for _, interval in ipairs(intervals) do
              table.insert(notes, root + oct * 12 + interval)
            end
          end
          table.insert(notes, root + octaves * 12)
          return notes
        end
        return orig(root, stype, octaves)
      end

      local notes_major = scale.build_scale(60, "Major")
      local notes_minor = scale.build_scale(60, "Minor")
      assert.are_not.same(notes_major, notes_minor)

      mock_musicutil.generate_scale = orig
    end)

  end)

  describe("to_midi", function()

    -- Build a reference scale for testing
    -- With root=60: generate_scale(24, "Major", 8)
    -- Notes: 24,26,28,29,31,33,35, 36,38,40,41,43,45,47, ...
    local scale_notes

    before_each(function()
      scale_notes = scale.build_scale(60, "Major")
    end)

    it("returns a number", function()
      local note = scale.to_midi(1, 4, scale_notes)
      assert.are.equal(type(note), "number")
    end)

    it("degree=1, octave=4 returns the center root", function()
      -- idx = (3 + 0) * 7 + 1 = 22
      -- scale_notes[22] should be the 4th octave's root
      local note = scale.to_midi(1, 4, scale_notes)
      assert.are.equal(note, scale_notes[22])
    end)

    it("increasing degree returns higher or equal notes", function()
      local prev = scale.to_midi(1, 4, scale_notes)
      for deg = 2, 7 do
        local curr = scale.to_midi(deg, 4, scale_notes)
        assert.is_true(curr >= prev,
          "degree " .. deg .. " (" .. curr .. ") should be >= degree " .. (deg - 1) .. " (" .. prev .. ")")
        prev = curr
      end
    end)

    it("increasing octave returns higher notes for same degree", function()
      local prev = scale.to_midi(1, 1, scale_notes)
      for oct = 2, 7 do
        local curr = scale.to_midi(1, oct, scale_notes)
        assert.is_true(curr > prev,
          "octave " .. oct .. " (" .. curr .. ") should be > octave " .. (oct - 1) .. " (" .. prev .. ")")
        prev = curr
      end
    end)

    it("degree=1, octave=5 is 12 semitones above degree=1, octave=4", function()
      local note4 = scale.to_midi(1, 4, scale_notes)
      local note5 = scale.to_midi(1, 5, scale_notes)
      assert.are.equal(note5 - note4, 12)
    end)

    it("octave=4 is center (offset=0)", function()
      -- With the mock: root in scale_notes at index (3+0)*7+1 = 22
      -- That should be the 4th group (0-indexed 3rd), degree 1
      -- scale_notes[22] = 24 + (22-1)*... let's just verify the formula
      local note = scale.to_midi(1, 4, scale_notes)
      local expected_idx = 3 * 7 + 1  -- 22
      assert.are.equal(note, scale_notes[expected_idx])
    end)

    it("different degrees return different notes within same octave", function()
      local seen = {}
      for deg = 1, 7 do
        local note = scale.to_midi(deg, 4, scale_notes)
        assert.is_nil(seen[note], "degree " .. deg .. " produced duplicate note " .. note)
        seen[note] = true
      end
    end)

    it("clamps when index is below 1", function()
      -- octave=1 is offset -3, degree=1 -> idx = (3-3)*7+1 = 1 (just at boundary)
      -- Let's push further: using octave=-10 (way below) -> idx would be negative
      -- to_midi clamps idx < 1 to 1
      local note = scale.to_midi(1, -10, scale_notes)
      assert.are.equal(note, scale_notes[1])
    end)

    it("clamps when index exceeds scale length", function()
      -- Using a very high octave
      local note = scale.to_midi(7, 100, scale_notes)
      assert.are.equal(note, scale_notes[#scale_notes])
    end)

    it("returns first scale note for minimum valid inputs", function()
      -- degree=1, octave so low that idx < 1
      local note = scale.to_midi(1, -100, scale_notes)
      assert.are.equal(note, scale_notes[1])
    end)

    it("returns last scale note for maximum valid inputs", function()
      local note = scale.to_midi(7, 200, scale_notes)
      assert.are.equal(note, scale_notes[#scale_notes])
    end)

    it("degree 3 at center octave returns correct scale member", function()
      -- idx = 3*7 + 3 = 24
      local note = scale.to_midi(3, 4, scale_notes)
      assert.are.equal(note, scale_notes[24])
    end)

    it("returns values from the scale_notes table", function()
      -- Any degree/octave combination should return a value present in scale_notes
      local scale_set = {}
      for _, n in ipairs(scale_notes) do scale_set[n] = true end
      for oct = 1, 7 do
        for deg = 1, 7 do
          local note = scale.to_midi(deg, oct, scale_notes)
          assert.is_true(scale_set[note],
            "to_midi(" .. deg .. ", " .. oct .. ") = " .. note .. " should be in scale")
        end
      end
    end)

  end)

end)
