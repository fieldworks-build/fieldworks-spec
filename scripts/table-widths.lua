-- Size table columns by their content for the PDF.
--
-- Pipe tables carry no widths unless a row is wider than pandoc's --columns,
-- so most come through with equal columns: a "Required: yes" column gets as
-- much room as a two-sentence description. Give each column a share of the
-- page proportional to its longest cell, with a floor so short columns stay
-- readable. The Markdown stays plain; this only affects rendered output.

local MIN_SHARE = 0.12
local MAX_LEN = 60  -- cap, so one long cell doesn't starve its neighbors
local CODE_WEIGHT = 1.5  -- monospace glyphs are wider than body text
-- A code span never wraps, so its column needs room for the whole span:
-- about this many body-text characters fit across the page.
local PAGE_CHARS = 100
local CODE_PAD = 4  -- the code box and cell inset, in characters

-- A cell's length for sharing out the page, and its longest code span.
local function cell_len(cell)
  local n, code = 0, 0
  pandoc.walk_block(pandoc.Div(cell.contents), {
    Str = function(s) n = n + (utf8.len(s.text) or 0) end,
    Space = function() n = n + 1 end,
    Code = function(c)
      local len = (utf8.len(c.text) or 0) * CODE_WEIGHT
      n = n + len
      code = math.max(code, len)
    end,
  })
  return math.min(n, MAX_LEN), code
end

-- GFM tables can only break lines inside a cell with <br>, which reaches
-- pandoc as raw HTML that the Typst writer drops. Make it a real break.
function RawInline(el)
  if el.format == "html" and el.text:match("^<br%s*/?>$") then
    return pandoc.LineBreak()
  end
end

function Table(tbl)
  local ncols = #tbl.colspecs
  if ncols < 2 then return nil end

  local longest, floor = {}, {}
  for i = 1, ncols do longest[i], floor[i] = 1, MIN_SHARE end
  local function scan(rows)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        if i <= ncols then
          local len, code = cell_len(cell)
          longest[i] = math.max(longest[i], len)
          if code > 0 then
            floor[i] = math.max(floor[i], (code + CODE_PAD) / PAGE_CHARS)
          end
        end
      end
    end
  end
  scan(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do scan(body.body) end

  local total = 0
  for i = 1, ncols do total = total + longest[i] end

  -- Raise every column to its floor (MIN_SHARE, or its longest code span),
  -- then rescale the rest to fill the page.
  local shares, pinned, fixed, flexible = {}, {}, 0, 0
  for i = 1, ncols do
    shares[i] = longest[i] / total
    if shares[i] < floor[i] then
      shares[i], pinned[i] = floor[i], true
      fixed = fixed + floor[i]
    else
      flexible = flexible + shares[i]
    end
  end
  for i = 1, ncols do
    if not pinned[i] then
      shares[i] = shares[i] / flexible * (1 - fixed)
    end
    tbl.colspecs[i] = { tbl.colspecs[i][1], shares[i] }
  end
  return tbl
end
