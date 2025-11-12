-- lilypond.lua — Quarto/Pandoc filter (simple, cache-first, **SVG**)
-- v1.0
--
-- • Turns ```{.lilypond ...}``` code blocks into LilyPond-rendered **SVG**.
-- • Caches by SHA-1 of (preamble + code + compile_opts).
-- • Writes stable hashed files (ly-<H>.ly/.svg) under lilypond-out/,
--   and also creates timestamp-named symlinks (or copies) for findability.
--
-- Metadata:
--   lilypond-preamble: |   (string/block)  → prepended to every snippet
--     \version "2.24.0"
--     \paper { indent = 0\mm }
--   lilypond: off       (bool/string 'off') → disable filter globally
--
-- Per-block supported attributes:
--   width, height, alt, title, align(left|center|right)
--
-- Notes:
-- • Requires `lilypond` in PATH.
-- • For LaTeX/PDF output, use a PDF engine that supports SVG (e.g. lualatex with `svg`).
-- • Never crashes a build; on failure emits a fenced code block with class .lilypond-error.

local CFG = {
  outdir = "lilypond-out",
  utc = true,
  compile_opts = "--svg", -- included in cache hash (fixed in v1)
}

local META = {
  preamble = "",
  disabled = false,
}

-- Files to watch (relative to project root)
local WATCH_FILES = {}

local is_windows = package.config:sub(1,1) == "\\"

-- ---------- tiny fs helpers ----------
local function file_exists(path)
  if type(path) ~= "string" or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_file(path, text)
  local f, err = io.open(path, "wb")
  if not f then
    return false, ("write_file: %s"):format(err or "unknown error")
  end
  f:write(text or "")
  f:close()
  return true
end

local function mkdir_p(dir)
  if is_windows then
    -- Powershell: creates if missing; succeeds if already exists.
    os.execute(('powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path \'%s\' | Out-Null"'):format(dir))
  else
    os.execute(('mkdir -p %q'):format(dir))
  end
end

local function nowstamp_utc()
  -- ISO 8601 basic, UTC: YYYYMMDDThhmmss
  return os.date(CFG.utc and "!%Y%m%dT%H%M%S" or "%Y%m%dT%H%M%S")
end

-- ---------- hashing ----------
local function sha1_hex(s)
  return pandoc.utils.sha1(s or "")
end

-- ---------- symlink/copy timestamp anchors ----------
local function copy_file(src, dst)
  local data = read_file(src)
  if not data then return false, "copy: read failed: "..src end
  return write_file(dst, data)
end


local function dirname(p) return p:match("^(.*)/[^/]+$") end
local function find_project_root(start_dir)
  local d = start_dir
  while d and d ~= "" do
    if file_exists(d .. "/_quarto.yml") then return d end
    local up = dirname(d)
    if not up or up == d then break end
    d = up
  end
  return start_dir
end

-- returns canonical absolute path (resolves symlinks)
local function realpath(path)
  local ok, out = pcall(function()
    return pandoc.pipe("realpath", {path}, "")
  end)
  if ok and type(out) == "string" and out ~= "" then
    return out:gsub("%s+$", "")
  end
  -- fallback: construct absolute path
  local base = (PANDOC_STATE and PANDOC_STATE.cwd) or "."
  if path:match("^/") then
    return path
  else
    return (base .. "/" .. path):gsub("//+", "/")
  end
end

-- local function project_root(outdir_abs)
--   local env = os.getenv("QUARTO_PROJECT_DIR")
--   if env and env ~= "" then return env end
--   io.stderr:write("[lilypond] ERROR: QUARTO_PROJECT_DIR not set. Please export it in your build.\n")
--   error("lilypond.lua: missing QUARTO_PROJECT_DIR")
-- end

-- Rhythmpress protocol: prefer RHYTHMPRESS_ROOT, then QUARTO_PROJECT_DIR.
local function project_root()
  local rp = os.getenv("RHYTHMPRESS_ROOT")
  if rp and rp ~= "" then return rp end
  local qd = os.getenv("QUARTO_PROJECT_DIR")
  if qd and qd ~= "" then return qd end
  io.stderr:write("[lilypond] ERROR: RHYTHMPRESS_ROOT (or QUARTO_PROJECT_DIR) not set. Please export it (see rhythmpress_env).\n")
  error("lilypond.lua: missing project root environment")
end


local function rel_from_root(abs)
  local root = realpath(project_root())
  if abs:sub(1, #root) == root then
    local r = abs:sub(#root + 1)
    return (r:gsub("^/+", ""))  -- strip leading /
  end
  return abs
end

local function add_watch(abs_path)
  local rel = rel_from_root(abs_path)
  WATCH_FILES[rel] = true
end


-- ---------- lilypond compile ----------
local function compile_svg(base_h)

  -- base_h: lilypond-out/ly-<H> (no extension). We already wrote .ly.
  -- local args = { "--svg",                              "-o", base_h, base_h .. ".ly" }
  -- local args = { "--svg", "-I", ".", "-I", CFG.outdir, "-o", base_h, base_h .. ".ly" }
  -- base_h is already lilypond-out/ly-<hash> (no extension)

  -- local SRC_DIR = pandoc.path.directory(PANDOC_STATE.input_files[1])        -- absolute
  -- local PROJECT_ROOT = find_project_root(SRC_DIR)                           -- absolute
  -- local OUTDIR_ABS = pandoc.path.make_absolute(CFG.outdir)                  -- absolute

  --   local OUTDIR_ABS   = realpath(CFG.outdir)
  --   local SRC_FILE     = realpath(PANDOC_STATE.input_files[1] or ".")
  --   local SRC_DIR      = SRC_FILE:match("^(.*)/[^/]+$") or "."
  --   local PROJECT_ROOT = realpath(project_root(SRC_DIR))

  local OUTDIR_ABS   = realpath(CFG.outdir)
  local SRC_FILE     = realpath(PANDOC_STATE.input_files[1] or ".")
  local SRC_DIR      = SRC_FILE:match("^(.*)/[^/]+$") or "."
  local PROJECT_ROOT = realpath(project_root())

  io.stderr:write( "[lilypond] PROJECT_ROOT =" .. PROJECT_ROOT  .. "\n" );
  io.stderr:write( "[lilypond] OUTPUTDIR_ABS=" .. OUTDIR_ABS  .. "\n" );
  io.stderr:write( "[lilypond] SRC_DIR      =" .. SRC_DIR  .. "\n" );

  local args = {
    "--svg",
    "-I", PROJECT_ROOT,   -- project root (so \include "filters/..." works)
    "-I", OUTDIR_ABS,     -- lilypond-out (where the temp .ly is)
    "-I", SRC_DIR,        -- the page directory (so ../../includes work)
    "-o", base_h,
    base_h .. ".ly"
  }

  -- Run lilypond; capture stdout; on nonzero exit pandoc.pipe throws (we show the error message).
  local ok, out_or_err = pcall(pandoc.pipe, "lilypond", args, "")
  if not ok then
    return false, out_or_err or "lilypond: unknown error"
  end
  return true
end






-- ---------- meta handling ----------
local function meta_to_string(mv)
  if not mv then return "" end
  return pandoc.utils.stringify(mv)
end

local function resolve_preamble1(mv)
  if type(mv) == "table" and mv.t == "MetaList" then
    local parts = {}
    for _, item in ipairs(mv) do parts[#parts+1] = pandoc.utils.stringify(item) end
    local txt = table.concat(parts, "\n")
    if txt ~= "" and txt:sub(-1) ~= "\n" then txt = txt .. "\n" end
    return txt
  end
  -- fallback (may be collapsed to one line by Quarto)
  local s = pandoc.utils.stringify(mv or "")
  if s ~= "" and s:sub(-1) ~= "\n" then s = s .. "\n" end
  return s
end

-- in your filter:
local function slurp(p) local f=io.open(p,"rb"); if not f then return nil end local s=f:read("*a"); f:close(); return s end
local function resolve_preamble2(mv)

  local s = pandoc.utils.stringify(mv or "")
  if type(s) ~= "string" then s = "" end
  s = s:gsub("^%s+",""):gsub("%s+$","")

  if s:match("%.ly$") or s:find("[/\\]") then
    local body = slurp(s) or ""
    if body ~= "" and body:sub(-1) ~= "\n" then body = body .. "\n" end
    return body
  end
  if s ~= "" and s:sub(-1) ~= "\n" then s = s .. "\n" end
  return s
end

local function resolve_preamble(mv)
  return resolve_preamble2(mv)
end

function Meta(m)
  -- io.stderr:write("[lilypond] preamble\n")
  -- io.stderr:write("All metadata:\n")
  -- for k,v in pairs(m) do
  --   io.stderr:write("  ", k, " = ", pandoc.utils.stringify(v), "\n")
  -- end

  -- global disable
  local lv = m["lilypond"]
  if lv ~= nil then
    local s = tostring(pandoc.utils.stringify(lv)):lower()
    if s == "off" or s == "false" or s == "0" then
      io.stderr:write("[lilypond] disabled\n")
      META.disabled = true
    end
  end


  -- preamble
  local pre = m["lilypond-preamble"]
  if pre then
    local s = resolve_preamble(pre)
    -- io.stderr:write("[lilypond] preamble start<<<\n")
    -- io.stderr:write( s .. "\n")
    -- io.stderr:write("[lilypond] preamble end>>>\n")
    if #s > 0 and s:sub(-1) ~= "\n" then s = s .. "\n" end
    META.preamble = s
  end
end


local function collect_svgs(base_h)
  local single = base_h .. ".svg"
  if file_exists(single) then
    return { single }
  end
  local svgs, i = {}, 1
  while true do
    local p = string.format("%s-%d.svg", base_h, i)
    if file_exists(p) then
      svgs[#svgs+1] = p
      i = i + 1
    else
      break
    end
  end
  return svgs
end


-- ---------- attr helpers ----------
local function first_nonempty_line(s)
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    local t = line:gsub("^%s+", ""):gsub("%s+$", "")
    if #t > 0 then return t end
  end
  return ""
end

local function shorten(s, n)
  n = n or 80
  if #s <= n then return s end
  return s:sub(1, n - 1) .. "…"
end

local function build_image_block(svg_path, cb)
  -- alt
  local alt = cb.attributes and cb.attributes.alt
  if not alt or alt == "" then
    alt = shorten(first_nonempty_line(cb.text or "LilyPond"))
  end
  local alt_inlines = { pandoc.Str(alt) }

  -- title
  local title = cb.attributes and cb.attributes.title or ""

  -- image attributes
  local img_attr = pandoc.Attr("", {}, {})
  if cb.attributes then
    local w = cb.attributes.width
    local h = cb.attributes.height
    if w and w ~= "" then img_attr.attributes.width = w end
    if h and h ~= "" then img_attr.attributes.height = h end
  end

  local image = pandoc.Image(alt_inlines, svg_path, title, img_attr)
  image.classes:insert("lilypond")
  local para = pandoc.Para({ image })

  -- alignment wrapper
  local align = cb.attributes and cb.attributes.align
  if align then
    align = tostring(align):lower()
    if align == "left" or align == "center" or align == "right" then
      local div_attr = pandoc.Attr("", {}, { style = ("text-align:%s;"):format(align) })
      return pandoc.Div({ para }, div_attr)
    end
  end

  return para
end


-- ---------- main handler ----------
local function handle_codeblock(cb)
  mkdir_p(CFG.outdir)

  -- local mv = PANDOC_DOCUMENT.meta["lilypond-preamble"]
  -- META.preamble = mv and pandoc.utils.stringify(mv) or ""

  local code = cb.text or ""
  local effective = (META.preamble or "") .. code
  io.stderr:write("[lilypond] preamble-2 start<<<\n")
  io.stderr:write( (META.preamble or "") .. "\n")
  io.stderr:write("[lilypond] preamble-2 end>>>\n")
  local hash_input = effective .. "\n-- compile_opts:" .. (CFG.compile_opts or "")
  local H = sha1_hex(hash_input)

  local base_h = CFG.outdir .. "/ly-" .. H
  local ly_path = base_h .. ".ly"

  -- write .ly if missing or content changed
  local need_write = true
  if file_exists(ly_path) then
    local cur = read_file(ly_path)
    if cur == effective then need_write = false end
  end
  if need_write then
    local ok, err = write_file(ly_path, effective)
    if not ok then
      local msg = ("[lilypond.lua] failed to write %s\n%s"):format(ly_path, err or "")
      io.stderr:write(msg.."\n")
      return pandoc.CodeBlock(msg, pandoc.Attr("", {"lilypond-error"}, {}))
    end
  end

  local must_compile = need_write or (#(collect_svgs(base_h)) == 0)
  if must_compile then
    local ok, err = compile_svg(base_h)
    if not ok then
      local cmd_disp = ("lilypond --svg -o %s %s"):format(base_h, ly_path)
      local err_head = (err or "unknown error"):gsub("%s+$","")
      -- show only the first ~20 lines of error text
      local lines, shown, limit = {}, 0, 20
      for line in (err_head .. "\n"):gmatch("([^\n]*)\n") do
        shown = shown + 1
        if shown > limit then
          table.insert(lines, "… (truncated) …")
          break
        end
        table.insert(lines, line)
      end
      local msg = ("# lilypond compile failed\n$ %s\n%s"):format(cmd_disp, table.concat(lines, "\n"))
      io.stderr:write("[lilypond.lua] compile error: " .. err_head .. "\n")
      return pandoc.CodeBlock(msg, pandoc.Attr("", {"lilypond-error"}, {}))
    end
  end

  local svg_paths = collect_svgs(base_h)
  if #svg_paths == 0 then
    io.stderr:write("[lilypond] no SVG produced for " .. base_h .. "\n")
    return pandoc.CodeBlock("# lilypond: no SVG produced", pandoc.Attr("", {"lilypond-error"}, {}))
  end

  if #svg_paths > 0 then
    local blocks = {}
    for _, p in ipairs(svg_paths) do
      blocks[#blocks+1] = build_image_block(p, cb)
    end
    return blocks
  end
end

local function watch_hint(rel)
  if FORMAT:match("html") then
    return pandoc.RawBlock("html", ('<link rel="preload" href="%s" as="fetch">'):format(rel))
  end
  -- non-HTML (PDF) still benefits because dependency is tracked; return a meta string fallback
  return pandoc.Para({ pandoc.Str(" ") })  -- harmless noop
end

-- ---------- new handler: lilypond-file (no refactor; standalone) ----------
local function handle_lilypond_file(cb)
  mkdir_p(CFG.outdir)

  -- path is the first non-empty line
  local raw = cb.text or ""
  local path = first_nonempty_line(raw)
  if path == "" then
    return pandoc.CodeBlock("# lilypond-file: empty path", pandoc.Attr("", {"lilypond-error"}, {}))
  end

--   -- resolve relative to current input file directory
--   local SRC_FILE = realpath(PANDOC_STATE.input_files[1] or ".")
--   local SRC_DIR  = SRC_FILE:match("^(.*)/[^/]+$") or "."
--   local abs_path = path
--   if not path:match("^/") then abs_path = (SRC_DIR .. "/" .. path):gsub("//+","/") end
--   abs_path = realpath(abs_path)

  -- resolve relative to **project root** per rhythmpress protocol
  local PROJECT_ROOT = realpath(project_root())
  local abs_path = path
  if not path:match("^/") then
    abs_path = (PROJECT_ROOT .. "/" .. path):gsub("//+","/")
  end
  abs_path = realpath(abs_path)

  local bytes = read_file(abs_path)
  if not bytes then
    local msg = "# lilypond-file: cannot read file: " .. abs_path
    return pandoc.CodeBlock(msg, pandoc.Attr("", {"lilypond-error"}, {}))
  end

  -- 1
  -- mark this source file as a dependency so Quarto watches it
  add_watch(abs_path)
  io.stderr:write("[lilypond.lua] add_watch: " .. abs_path .. "\n")

  -- 2
  -- compute rel path from project root
  local rel = rel_from_root(abs_path)
  local w = watch_hint(rel)
  -- when you return the blocks for the image(s), append w:
  -- blocks[#blocks+1] = w  (if w ~= nil)


  -- Effective source = preamble + file contents
  local effective = (META.preamble or "") .. bytes

  -- identical caching & compile path as handle_codeblock
  local hash_input = effective .. "\n-- compile_opts:" .. (CFG.compile_opts or "")
  local H = sha1_hex(hash_input)
  local base_h = CFG.outdir .. "/ly-" .. H
  local ly_path = base_h .. ".ly"

  -- write .ly if missing or content changed
  local need_write = true
  if file_exists(ly_path) then
    local cur = read_file(ly_path)
    if cur == effective then need_write = false end
  end
  if need_write then
    local ok, err = write_file(ly_path, effective)
    if not ok then
      local msg = ("[lilypond.lua] failed to write %s\n%s"):format(ly_path, err or "")
      io.stderr:write(msg.."\n")
      return pandoc.CodeBlock(msg, pandoc.Attr("", {"lilypond-error"}, {}))
    end
  end

  local must_compile = need_write or (#(collect_svgs(base_h)) == 0)
  if must_compile then
    local ok, err = compile_svg(base_h)
    if not ok then
      local cmd_disp = ("lilypond --svg -o %s %s"):format(base_h, ly_path)
      local err_head = (err or "unknown error"):gsub("%s+$","")
      local lines, shown, limit = {}, 0, 20
      for line in (err_head .. "\n"):gmatch("([^\n]*)\n") do
        shown = shown + 1
        if shown > limit then
          table.insert(lines, "… (truncated) …")
          break
        end
        table.insert(lines, line)
      end
      local msg = ("# lilypond compile failed\n$ %s\n%s"):format(cmd_disp, table.concat(lines, "\n"))
      io.stderr:write("[lilypond.lua] compile error: " .. err_head .. "\n")
      return pandoc.CodeBlock(msg, pandoc.Attr("", {"lilypond-error"}, {}))
    end
  end

  local svg_paths = collect_svgs(base_h)
  if #svg_paths == 0 then
    io.stderr:write("[lilypond] no SVG produced for " .. base_h .. "\n")
    return pandoc.CodeBlock("# lilypond: no SVG produced", pandoc.Attr("", {"lilypond-error"}, {}))
  end

  local blocks = {}
  for _, p in ipairs(svg_paths) do
    blocks[#blocks+1] = build_image_block(p, cb)
  end
  if w ~= nil then
    blocks[#blocks + 1] = w
  end
  return blocks
end


local function CodeBlock(cb)
  if META.disabled then return nil end
  if cb.classes:includes("lilypond") then
    return handle_codeblock(cb)
  end
  if cb.classes:includes("lilypond-file") then
    return handle_lilypond_file(cb)
  end
  return nill;
end

-- After processing blocks, inject watched files into page metadata resources
function Pandoc(doc)
  if next(WATCH_FILES) ~= nil then
    io.stderr:write("[lilypond.lua] Pandoc: " )
    local res = {}
    -- start from existing resources if present
    if doc.meta and doc.meta.resources and doc.meta.resources.t == "MetaList" then
      for _, it in ipairs(doc.meta.resources) do table.insert(res, it) end
    end
    -- append our watched files (dedup via table set)
    for rel, _ in pairs(WATCH_FILES) do
      table.insert(res, pandoc.MetaString(rel))
    end
    doc.meta.resources = pandoc.MetaList(res)
  end
  return doc
end

return {
  { Pandoc=Pandoc },
  { Meta=Meta },
  { CodeBlock = CodeBlock },
}

