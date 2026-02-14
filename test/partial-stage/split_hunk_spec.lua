local parser = require("partial-stage.patch_parser")

describe("split_hunk", function()
  it("returns nil for unsplittable hunk (single change group)", function()
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
    local result = parser.split_hunk(files[1].hunks[1])
    assert.is_nil(result)
  end)

  it("splits hunk with two change groups separated by context", function()
    local diff = table.concat({
      "diff --git a/file.lua b/file.lua",
      "index abc..def 100644",
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1,9 +1,9 @@",
      " line1",
      "-old2",
      "+new2",
      " line3",
      " line4",
      " line5",
      "-old6",
      "+new6",
      " line7",
    }, "\n") .. "\n"

    local files = parser.parse(diff)
    local result = parser.split_hunk(files[1].hunks[1])

    assert.is_not_nil(result)
    assert.are.equal(2, #result)

    -- First sub-hunk should contain the first change group
    local h1 = result[1]
    local has_old2 = false
    local has_new2 = false
    for _, line in ipairs(h1.lines) do
      if line == "-old2" then has_old2 = true end
      if line == "+new2" then has_new2 = true end
    end
    assert.is_true(has_old2)
    assert.is_true(has_new2)

    -- Second sub-hunk should contain the second change group
    local h2 = result[2]
    local has_old6 = false
    local has_new6 = false
    for _, line in ipairs(h2.lines) do
      if line == "-old6" then has_old6 = true end
      if line == "+new6" then has_new6 = true end
    end
    assert.is_true(has_old6)
    assert.is_true(has_new6)
  end)

  it("splits hunk with three change groups", function()
    local diff = table.concat({
      "diff --git a/file.lua b/file.lua",
      "index abc..def 100644",
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1,11 +1,14 @@",
      " line1",
      "+add2",
      " line3",
      " line4",
      "-del5",
      " line6",
      " line7",
      " line8",
      "-old9",
      "+new9",
      "+extra9",
      " line10",
      " line11",
    }, "\n") .. "\n"

    local files = parser.parse(diff)
    local result = parser.split_hunk(files[1].hunks[1])

    assert.is_not_nil(result)
    assert.are.equal(3, #result)
  end)

  it("produces valid hunk headers with correct line numbers", function()
    local diff = table.concat({
      "diff --git a/file.lua b/file.lua",
      "index abc..def 100644",
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1,7 +1,7 @@",
      " line1",
      "-old2",
      "+new2",
      " line3",
      " line4",
      "-old5",
      "+new5",
      " line6",
    }, "\n") .. "\n"

    local files = parser.parse(diff)
    local result = parser.split_hunk(files[1].hunks[1])

    assert.is_not_nil(result)
    assert.are.equal(2, #result)

    -- First hunk starts at line 1
    assert.are.equal(1, result[1].header.old_start)
    assert.are.equal(1, result[1].header.new_start)

    -- Verify header lines are proper strings
    assert.is_truthy(result[1].header_line:match("^@@ "))
    assert.is_truthy(result[2].header_line:match("^@@ "))
  end)

  it("each sub-hunk can produce a valid patch", function()
    local diff = table.concat({
      "diff --git a/file.lua b/file.lua",
      "index abc..def 100644",
      "--- a/file.lua",
      "+++ b/file.lua",
      "@@ -1,7 +1,7 @@",
      " line1",
      "-old2",
      "+new2",
      " line3",
      " line4",
      "-old5",
      "+new5",
      " line6",
    }, "\n") .. "\n"

    local files = parser.parse(diff)
    local result = parser.split_hunk(files[1].hunks[1])

    for _, sub_hunk in ipairs(result) do
      local patch = parser.make_patch(files[1], sub_hunk)
      assert.is_truthy(patch:match("^diff %-%-git"))
      assert.is_truthy(patch:match("@@ "))
    end
  end)
end)
