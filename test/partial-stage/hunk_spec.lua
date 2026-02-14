local parser = require("partial-stage.patch_parser")

describe("hunk operations", function()
  local sample_diff = table.concat({
    "diff --git a/file.lua b/file.lua",
    "index abc1234..def5678 100644",
    "--- a/file.lua",
    "+++ b/file.lua",
    "@@ -1,5 +1,7 @@",
    " line1",
    " line2",
    "-old line3",
    "+new line3",
    "+added line3a",
    " line4",
    " line5",
  }, "\n") .. "\n"

  describe("make_patch", function()
    it("creates a valid patch for staging", function()
      local files = parser.parse(sample_diff)
      local patch = parser.make_patch(files[1], files[1].hunks[1])

      -- Should contain the file header
      assert.is_truthy(patch:match("diff %-%-git a/file%.lua b/file%.lua"))
      assert.is_truthy(patch:match("index abc1234%.%.def5678 100644"))
      assert.is_truthy(patch:match("%-%-% a/file%.lua"))
      assert.is_truthy(patch:match("%+%+%+ b/file%.lua"))

      -- Should contain the hunk header
      assert.is_truthy(patch:match("@@ %-1,5 %+1,7 @@"))

      -- Should contain the diff lines
      assert.is_truthy(patch:match("%-old line3"))
      assert.is_truthy(patch:match("%+new line3"))
      assert.is_truthy(patch:match("%+added line3a"))
    end)
  end)

  describe("make_partial_patch for staging", function()
    it("stages only selected added lines", function()
      local files = parser.parse(sample_diff)
      local hunk = files[1].hunks[1]

      -- Select only "+new line3" (index 4 in hunk.lines)
      local patch = parser.make_partial_patch(files[1], hunk, { 4 }, "stage")

      assert.is_truthy(patch:match("%+new line3"))
      assert.is_falsy(patch:match("%+added line3a"))
      -- Unselected "-old line3" becomes context (not staged)
      assert.is_truthy(patch:match(" old line3"))
      assert.is_falsy(patch:match("%-old line3"))
    end)

    it("stages only selected removed lines", function()
      local files = parser.parse(sample_diff)
      local hunk = files[1].hunks[1]

      -- Select only "-old line3" (index 3 in hunk.lines)
      -- But not the additions
      local patch = parser.make_partial_patch(files[1], hunk, { 3 }, "stage")

      assert.is_truthy(patch:match("%-old line3"))
      -- Added lines should not be present
      assert.is_falsy(patch:match("%+new line3"))
      assert.is_falsy(patch:match("%+added line3a"))
    end)

    it("handles selection of all change lines", function()
      local files = parser.parse(sample_diff)
      local hunk = files[1].hunks[1]

      -- hunk.lines: 1=" line1", 2=" line2", 3="-old line3",
      --             4="+new line3", 5="+added line3a", 6=" line4", 7=" line5"
      -- Select all changed lines (indices 3, 4, 5)
      local patch = parser.make_partial_patch(files[1], hunk, { 3, 4, 5 }, "stage")

      assert.is_truthy(patch:match("%-old line3"))
      assert.is_truthy(patch:match("%+new line3"))
      assert.is_truthy(patch:match("%+added line3a"))
      -- old_count=5 (line1,line2,old_line3,line4,line5), new_count=6 (line1,line2,new,added,line4,line5)
      assert.is_truthy(patch:match("@@ %-1,5 %+1,6 @@"))
    end)
  end)

  describe("make_partial_patch for discard", function()
    it("discards only selected added lines, keeps others as context", function()
      local files = parser.parse(sample_diff)
      local hunk = files[1].hunks[1]

      -- hunk.lines: 1=" line1", 2=" line2", 3="-old line3",
      --             4="+new line3", 5="+added line3a", 6=" line4", 7=" line5"
      -- Select only "+new line3" (index 4) for discard
      local patch = parser.make_partial_patch(files[1], hunk, { 4 }, "discard")

      -- Selected "+" line stays as "+"
      assert.is_truthy(patch:match("%+new line3"))
      -- Unselected "+" becomes context (exists in working tree)
      assert.is_truthy(patch:match(" added line3a"))
      assert.is_falsy(patch:match("%+added line3a"))
      -- Unselected "-" is omitted (not in working tree)
      assert.is_falsy(patch:match("old line3"))
    end)

    it("discards only selected removed lines", function()
      local files = parser.parse(sample_diff)
      local hunk = files[1].hunks[1]

      -- Select only "-old line3" (index 3) for discard
      local patch = parser.make_partial_patch(files[1], hunk, { 3 }, "discard")

      -- Selected "-" line stays as "-"
      assert.is_truthy(patch:match("%-old line3"))
      -- Unselected "+" lines become context
      assert.is_truthy(patch:match(" new line3"))
      assert.is_truthy(patch:match(" added line3a"))
    end)

    it("handles all change lines selected for discard", function()
      local files = parser.parse(sample_diff)
      local hunk = files[1].hunks[1]

      -- Select all changed lines (indices 3, 4, 5) for discard
      local patch = parser.make_partial_patch(files[1], hunk, { 3, 4, 5 }, "discard")

      assert.is_truthy(patch:match("%-old line3"))
      assert.is_truthy(patch:match("%+new line3"))
      assert.is_truthy(patch:match("%+added line3a"))
      -- old=5 (4 context + 1 removal), new=6 (4 context + 2 additions)
      assert.is_truthy(patch:match("@@ %-1,5 %+1,6 @@"))
    end)
  end)

  describe("patch reconstruction for new files", function()
    it("handles new file diffs", function()
      local diff = table.concat({
        "diff --git a/new.lua b/new.lua",
        "new file mode 100644",
        "index 0000000..abc1234",
        "--- /dev/null",
        "+++ b/new.lua",
        "@@ -0,0 +1,3 @@",
        "+line1",
        "+line2",
        "+line3",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      assert.are.equal(1, #files)
      assert.are.equal("new.lua", files[1].b_file)

      local patch = parser.make_patch(files[1], files[1].hunks[1])
      assert.is_truthy(patch:match("new file mode 100644"))
      assert.is_truthy(patch:match("%+line1"))
    end)
  end)

  describe("patch reconstruction for deleted files", function()
    it("handles deleted file diffs", function()
      local diff = table.concat({
        "diff --git a/old.lua b/old.lua",
        "deleted file mode 100644",
        "index abc1234..0000000",
        "--- a/old.lua",
        "+++ /dev/null",
        "@@ -1,3 +0,0 @@",
        "-line1",
        "-line2",
        "-line3",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      assert.are.equal(1, #files)

      local patch = parser.make_patch(files[1], files[1].hunks[1])
      assert.is_truthy(patch:match("deleted file mode 100644"))
      assert.is_truthy(patch:match("%-line1"))
    end)
  end)
end)
