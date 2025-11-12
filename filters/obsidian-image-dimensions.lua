-- obsidian-image-dimensions.lua
function Image(el)
  if #el.caption == 1 and el.caption[1].t == "Str" then
    local caption_text = el.caption[1].text
    print( caption_text )

    -- Match |300x200
    local width, height = caption_text:match("|(%d+)x(%d+)$")
    if width and height then
      print("Matched full dimensions: " .. el.src .. " → " .. width .. "x" .. height )
      el.caption = nil
      -- el.caption = {}  -- remove the caption
      -- el.caption[1].text = ""
      el.attributes["width"] = width
      el.attributes["height"] = height
      return el
    end

    -- Match |300
    local width = caption_text:match("|(%d+)$")
    if width then
      print("Matched width only: " .. el.src .. " → width=" .. width )
      el.caption = nil
      -- el.caption = {}  -- remove the caption
      -- el.caption[1].text = ""
      el.attributes["width"] = width
      return el
    end
  end

  return el
end


