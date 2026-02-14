local parser = require("partial-stage.patch_parser")

describe("patch_parser", function()
  describe("parse_hunk_header", function()
    it("parses standard hunk header", function()
      local h = parser.parse_hunk_header("@@ -16,10 +17,14 @@")
      assert.are.equal(16, h.old_start)
      assert.are.equal(10, h.old_count)
      assert.are.equal(17, h.new_start)
      assert.are.equal(14, h.new_count)
    end)

    it("parses hunk header without counts", function()
      local h = parser.parse_hunk_header("@@ -1 +1 @@")
      assert.are.equal(1, h.old_start)
      assert.are.equal(1, h.old_count)
      assert.are.equal(1, h.new_start)
      assert.are.equal(1, h.new_count)
    end)

    it("parses hunk header with function context", function()
      local h = parser.parse_hunk_header("@@ -16,10 +17,14 @@ function foo()")
      assert.are.equal(16, h.old_start)
      assert.are.equal(10, h.old_count)
      assert.are.equal(17, h.new_start)
      assert.are.equal(14, h.new_count)
    end)

    it("returns nil for invalid header", function()
      local h = parser.parse_hunk_header("not a header")
      assert.is_nil(h)
    end)
  end)

  describe("make_hunk_header", function()
    it("builds correct header string", function()
      local header = { old_start = 5, old_count = 3, new_start = 5, new_count = 8 }
      assert.are.equal("@@ -5,3 +5,8 @@", parser.make_hunk_header(header))
    end)
  end)

  describe("parse", function()
    it("returns empty table for nil input", function()
      assert.are.same({}, parser.parse(nil))
    end)

    it("returns empty table for empty string", function()
      assert.are.same({}, parser.parse(""))
    end)

    it("parses single file with single hunk", function()
      local diff = table.concat({
        "diff --git a/file.lua b/file.lua",
        "index abc1234..def5678 100644",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,4 @@",
        " line1",
        "-old line",
        "+new line",
        "+added line",
        " line3",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      assert.are.equal(1, #files)
      assert.are.equal("file.lua", files[1].b_file)
      assert.are.equal(1, #files[1].hunks)
      assert.are.equal(1, files[1].hunks[1].header.old_start)
      assert.are.equal(3, files[1].hunks[1].header.old_count)
      assert.are.equal(5, #files[1].hunks[1].lines)
    end)

    it("parses multiple files", function()
      local diff = table.concat({
        "diff --git a/a.lua b/a.lua",
        "index 1111111..2222222 100644",
        "--- a/a.lua",
        "+++ b/a.lua",
        "@@ -1,2 +1,3 @@",
        " line1",
        "+new line",
        " line2",
        "diff --git a/b.lua b/b.lua",
        "index 3333333..4444444 100644",
        "--- a/b.lua",
        "+++ b/b.lua",
        "@@ -1,2 +1,2 @@",
        "-old",
        "+new",
        " context",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      assert.are.equal(2, #files)
      assert.are.equal("a.lua", files[1].b_file)
      assert.are.equal("b.lua", files[2].b_file)
    end)

    it("parses multiple hunks in one file", function()
      local diff = table.concat({
        "diff --git a/file.lua b/file.lua",
        "index abc..def 100644",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,4 @@",
        " line1",
        "+added",
        " line2",
        " line3",
        "@@ -10,3 +11,2 @@",
        " line10",
        "-removed",
        " line12",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      assert.are.equal(1, #files)
      assert.are.equal(2, #files[1].hunks)
      assert.are.equal(1, files[1].hunks[1].header.old_start)
      assert.are.equal(10, files[1].hunks[2].header.old_start)
    end)
  end)

  describe("make_patch", function()
    it("reconstructs a valid patch", function()
      local diff = table.concat({
        "diff --git a/file.lua b/file.lua",
        "index abc..def 100644",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,4 @@",
        " line1",
        "-old",
        "+new",
        "+added",
        " line3",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      local patch = parser.make_patch(files[1], files[1].hunks[1])
      assert.is_truthy(patch:match("^diff %-%-git"))
      assert.is_truthy(patch:match("@@ %-1,3 %+1,4 @@"))
    end)
  end)

  describe("make_partial_patch", function()
    it("creates patch with only selected added lines", function()
      local diff = table.concat({
        "diff --git a/file.lua b/file.lua",
        "index abc..def 100644",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,3 +1,5 @@",
        " line1",
        "+add1",
        "+add2",
        " line2",
        " line3",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      -- Select only the first added line (index 2 in hunk.lines)
      local patch = parser.make_partial_patch(files[1], files[1].hunks[1], { 2 }, "stage")
      assert.is_truthy(patch:match("%+add1"))
      assert.is_falsy(patch:match("%+add2"))
      -- Should have correct counts: 3 old lines (context) + 1 new = 4 new total
      assert.is_truthy(patch:match("@@ %-1,3 %+1,4 @@"))
    end)

    it("converts unselected removed lines to context", function()
      local diff = table.concat({
        "diff --git a/file.lua b/file.lua",
        "index abc..def 100644",
        "--- a/file.lua",
        "+++ b/file.lua",
        "@@ -1,4 +1,2 @@",
        " line1",
        "-del1",
        "-del2",
        " line4",
      }, "\n") .. "\n"

      local files = parser.parse(diff)
      -- Select only the first deleted line (index 2)
      local patch = parser.make_partial_patch(files[1], files[1].hunks[1], { 2 }, "stage")
      assert.is_truthy(patch:match("%-del1"))
      -- del2 should become context line
      assert.is_truthy(patch:match(" del2"))
      -- old_count=4, new_count=3 (1 context + 1 del2-as-context + 1 context = 3 new)
      assert.is_truthy(patch:match("@@ %-1,4 %+1,3 @@"))
    end)
  end)
end)
