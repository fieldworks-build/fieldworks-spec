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

local function cell_len(cell)
  local n = 0
  pandoc.walk_block(pandoc.Div(cell.contents), {
    Str = function(s) n = n + (utf8.len(s.text) or 0) end,
    Space = function() n = n + 1 end,
    Code = function(c) n = n + (utf8.len(c.text) or 0) * CODE_WEIGHT end,
  })
  return math.min(n, MAX_LEN)
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

  local longest = {}
  for i = 1, ncols do longest[i] = 1 end
  local function scan(rows)
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row.cells) do
        if i <= ncols then longest[i] = math.max(longest[i], cell_len(cell)) end
      end
    end
  end
  scan(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do scan(body.body) end

  local total = 0
  for i = 1, ncols do total = total + longest[i] end

  -- Raise every column to the floor, then rescale the rest to fill the page.
  local shares, fixed, flexible = {}, 0, 0
  for i = 1, ncols do
    shares[i] = longest[i] / total
    if shares[i] < MIN_SHARE then
      shares[i] = MIN_SHARE
      fixed = fixed + MIN_SHARE
    else
      flexible = flexible + shares[i]
    end
  end
  for i = 1, ncols do
    if shares[i] > MIN_SHARE then
      shares[i] = shares[i] / flexible * (1 - fixed)
    end
    tbl.colspecs[i] = { tbl.colspecs[i][1], shares[i] }
  end
  return tbl
end
