-- filters/meta-dates.lua
function Meta(meta)
  local function S(x) return pandoc.utils.stringify(x) end
  local hi = meta['header-includes'] or {}

  if meta.mdate then
    local v = S(meta.mdate)
    table.insert(hi, pandoc.RawBlock("html",
      '<meta name="mdate" content="' .. v .. '">'))
    table.insert(hi, pandoc.RawBlock("html",
      '<meta property="article:modified_time" content="' .. v .. '">'))
  end

  if meta.cdate then
    local v = S(meta.cdate)
    table.insert(hi, pandoc.RawBlock("html",
      '<meta name="cdate" content="' .. v .. '">'))
    table.insert(hi, pandoc.RawBlock("html",
      '<meta property="article:published_time" content="' .. v .. '">'))
  end

  meta['header-includes'] = hi
  return meta
end

