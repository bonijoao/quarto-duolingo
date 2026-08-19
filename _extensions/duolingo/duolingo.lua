--[[
  quarto-duolingo — mostra ofensiva, XP e cursos de um perfil Duolingo.

  Tudo acontece no momento do render: o Pandoc busca o perfil na API publica,
  e o shortcode devolve HTML estatico. Como quem faz a requisicao e a maquina
  do build (e nao o navegador do visitante), nao ha problema de CORS e a
  pagina publicada nao precisa de JavaScript nenhum.

  Consequencia: os dados sao do momento do build. Ver "Keeping it up to date"
  no README.
]]

local API = "https://www.duolingo.com/2017-06-30/users?username="
local PROFILE_URL = "https://www.duolingo.com/profile/"

-- Caches por processo Pandoc: varios shortcodes no mesmo documento fazem uma
-- unica requisicao (e um unico base64 do avatar, que nao e de graca).
-- Paginas diferentes rodam em processos separados.
local cache = {}
local avatar_cache = {}

-- Lista explicita: em Lua uma chave com valor nil nao existe na tabela, entao
-- `user` (sem default) jamais apareceria em pairs(DEFAULTS).
local OPTION_KEYS = {
  "user", "lang", "theme", "accent", "layout",
  "avatar", "stats", "courses", "link", "on-error",
}

local DEFAULTS = {
  lang = "en",
  theme = "auto",
  accent = "#58cc02",
  layout = "card",
  avatar = true,
  stats = { "streak", "xp", "since" },
  courses = 4,
  link = true,
  ["on-error"] = "warn",
}

--=========================================================================
-- i18n
--=========================================================================

local I18N = {
  en = { streak = "Day streak", xp = "Total XP", since = "Member since",
         learning = "Learning", updated = "Updated", super = "Super",
         from = "since", sep = ",",
         months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" } },
  pt = { streak = "Ofensiva", xp = "XP total", since = "Membro desde",
         learning = "Aprendendo", updated = "Atualizado", super = "Super",
         from = "desde", sep = ".",
         months = { "jan", "fev", "mar", "abr", "mai", "jun",
                    "jul", "ago", "set", "out", "nov", "dez" } },
  es = { streak = "Racha", xp = "XP total", since = "Miembro desde",
         learning = "Aprendiendo", updated = "Actualizado", super = "Super",
         from = "desde", sep = ".",
         months = { "ene", "feb", "mar", "abr", "may", "jun",
                    "jul", "ago", "sep", "oct", "nov", "dic" } },
  fr = { streak = "Série", xp = "XP total", since = "Membre depuis",
         learning = "Apprentissage", updated = "Mis à jour", super = "Super",
         from = "depuis", sep = " ",
         months = { "janv.", "févr.", "mars", "avr.", "mai", "juin",
                    "juil.", "août", "sept.", "oct.", "nov.", "déc." } },
  de = { streak = "Tage-Serie", xp = "Gesamt-XP", since = "Mitglied seit",
         learning = "Lernt", updated = "Aktualisiert", super = "Super",
         from = "seit", sep = ".",
         months = { "Jan.", "Feb.", "März", "Apr.", "Mai", "Juni",
                    "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez." } },
}

-- Nomes de curso vem em ingles da API; traduzimos os mais comuns pelo codigo
-- do idioma aprendido e caimos no title original quando nao houver traducao.
local COURSE_NAMES = {
  pt = { en = "Inglês", es = "Espanhol", fr = "Francês", de = "Alemão",
         it = "Italiano", ja = "Japonês", ko = "Coreano", zh = "Chinês",
         ru = "Russo", pt = "Português", nl = "Holandês", sv = "Sueco" },
  es = { en = "Inglés", es = "Español", fr = "Francés", de = "Alemán",
         it = "Italiano", ja = "Japonés", ko = "Coreano", zh = "Chino",
         ru = "Ruso", pt = "Portugués", nl = "Neerlandés", sv = "Sueco" },
  fr = { en = "Anglais", es = "Espagnol", fr = "Français", de = "Allemand",
         it = "Italien", ja = "Japonais", ko = "Coréen", zh = "Chinois",
         ru = "Russe", pt = "Portugais", nl = "Néerlandais", sv = "Suédois" },
  de = { en = "Englisch", es = "Spanisch", fr = "Französisch", de = "Deutsch",
         it = "Italienisch", ja = "Japanisch", ko = "Koreanisch", zh = "Chinesisch",
         ru = "Russisch", pt = "Portugiesisch", nl = "Niederländisch", sv = "Schwedisch" },
}

local FLAGS = {
  en = "🇺🇸", es = "🇪🇸", fr = "🇫🇷", de = "🇩🇪", it = "🇮🇹", pt = "🇧🇷",
  ja = "🇯🇵", ko = "🇰🇷", zh = "🇨🇳", ru = "🇷🇺", nl = "🇳🇱", sv = "🇸🇪",
  ar = "🇸🇦", hi = "🇮🇳", tr = "🇹🇷", pl = "🇵🇱", el = "🇬🇷", he = "🇮🇱",
  ga = "🇮🇪", cy = "🏴󠁧󠁢󠁷󠁬󠁳󠁿", da = "🇩🇰", nb = "🇳🇴", fi = "🇫🇮", cs = "🇨🇿",
  uk = "🇺🇦", hu = "🇭🇺", ro = "🇷🇴", vi = "🇻🇳", id = "🇮🇩", eo = "🟩",
  la = "🏛️", hw = "🏝️", nv = "🪶", gd = "🏴󠁧󠁢󠁳󠁣󠁴󠁿", yi = "✡️", hv = "🐉", tlh = "🖖",
}

local function t(lang)
  return I18N[lang] or I18N.en
end

--=========================================================================
-- Formatacao
--=========================================================================

--- Separador de milhar: nao da para contar com locale do sistema no Lua.
local function group(n, sep)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1\1"):reverse()
  out = out:gsub("^\1", ""):gsub("\1", sep)
  return out
end

--- "2023-03-25" -> "mar 2023" (no idioma escolhido).
local function month_year(iso, lang)
  if type(iso) ~= "string" then return nil end
  local y, m = iso:match("^(%d%d%d%d)%-(%d%d)")
  if not y then return nil end
  local months = t(lang).months
  return (months[tonumber(m)] or m) .. " " .. y
end

local ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;",
                  ['"'] = "&quot;", ["'"] = "&#39;" }

--- Texto vindo da API vai para dentro de HTML cru: escapar sempre.
local function esc(s)
  return (tostring(s or ""):gsub("[&<>\"']", ESCAPES))
end

--=========================================================================
-- Opcoes: kwargs do shortcode > meta do YAML > default
--=========================================================================

--- Converte um valor de metadados do Pandoc para string/boolean/lista.
--- Uma MetaList chega como tabela de tabelas; MetaInlines chega como tabela de
--- elementos userdata (Str, Space, ...) e precisa ser concatenada, nao iterada.
local function meta_to_value(v)
  if v == nil then return nil end
  local ty = type(v)
  if ty == "boolean" or ty == "number" or ty == "string" then return v end
  if ty == "table" and #v > 0 and type(v[1]) ~= "userdata" then
    local out = {}
    for _, item in ipairs(v) do out[#out + 1] = meta_to_value(item) end
    return out
  end
  return pandoc.utils.stringify(v)
end

local function truthy(v, fallback)
  if v == nil then return fallback end
  if type(v) == "boolean" then return v end
  v = tostring(v):lower()
  return v == "true" or v == "yes" or v == "1"
end

local function read_options(kwargs, meta)
  local opts = {}
  for k, v in pairs(DEFAULTS) do opts[k] = v end

  local from_meta = meta and meta.duolingo
  if from_meta then
    for _, key in ipairs(OPTION_KEYS) do
      local v = meta_to_value(from_meta[key])
      if v ~= nil then opts[key] = v end
    end
  end

  for _, key in ipairs(OPTION_KEYS) do
    local v = kwargs and kwargs[key]
    if v ~= nil then
      v = pandoc.utils.stringify(v)
      if v ~= "" then opts[key] = v end
    end
  end

  if type(opts.user) == "table" then opts.user = opts.user[1] end
  opts.avatar = truthy(opts.avatar, true)
  opts.link = truthy(opts.link, true)
  opts.courses = math.floor(tonumber(opts.courses) or 0)
  if type(opts.stats) == "string" then
    local list = {}
    for item in tostring(opts.stats):gmatch("[^,%s]+") do list[#list + 1] = item end
    opts.stats = list
  end
  if not I18N[opts.lang] then opts.lang = "en" end
  if opts.theme ~= "light" and opts.theme ~= "dark" then opts.theme = "auto" end
  if opts.layout ~= "compact" then opts.layout = "card" end

  return opts
end

--=========================================================================
-- Rede
--=========================================================================

--- Busca o perfil. Devolve (profile, nil) ou (nil, mensagem de erro).
local function fetch_profile(user)
  if cache[user] ~= nil then
    local hit = cache[user]
    return hit.profile, hit.err
  end

  local function store(profile, err)
    cache[user] = { profile = profile, err = err }
    return profile, err
  end

  local ok, _, body = pcall(pandoc.mediabag.fetch, API .. user)
  if not ok or not body then
    return store(nil, "could not reach the Duolingo API")
  end

  local parsed_ok, parsed = pcall(quarto.json.decode, body)
  if not parsed_ok or type(parsed) ~= "table" then
    return store(nil, "the Duolingo API returned something that is not JSON")
  end

  -- A API responde 200 com {"users": []} para usuario inexistente, entao
  -- checar o corpo e obrigatorio: status 200 nao significa perfil valido.
  local users = parsed.users
  if type(users) ~= "table" or #users == 0 then
    return store(nil, "no Duolingo user named '" .. user .. "'")
  end

  return store(users[1], nil)
end

--- Avatar embutido como data URI: o card fica autossuficiente e compativel
--- com embed-resources. Falhar aqui nao derruba o card.
local function fetch_avatar(picture)
  if type(picture) ~= "string" or picture == "" then return nil end
  if avatar_cache[picture] ~= nil then
    return avatar_cache[picture] or nil
  end

  local url = picture
  if url:match("^//") then url = "https:" .. url end
  -- Sem sufixo de tamanho o CDN responde 400.
  local ok, mime, body = pcall(pandoc.mediabag.fetch, url .. "/xlarge")
  if not ok or not body or body == "" then
    avatar_cache[picture] = false
    return nil
  end
  if type(mime) ~= "string" or mime == "" then mime = "image/png" end

  local uri = "data:" .. mime .. ";base64," .. quarto.base64.encode(body)
  avatar_cache[picture] = uri
  return uri
end

--=========================================================================
-- Normalizacao do perfil
--=========================================================================

local function normalize(raw, opts)
  local streak = raw.streakData and raw.streakData.currentStreak or {}
  local courses = {}
  for _, c in ipairs(raw.courses or {}) do
    courses[#courses + 1] = {
      code = c.learningLanguage,
      title = c.title,
      xp = tonumber(c.xp) or 0,
    }
  end
  table.sort(courses, function(a, b) return a.xp > b.xp end)

  local names = COURSE_NAMES[opts.lang] or {}
  for _, c in ipairs(courses) do
    c.label = names[c.code] or c.title or c.code
    c.flag = FLAGS[c.code] or "🏳️"
  end

  return {
    username = raw.username or opts.user,
    name = raw.name or raw.username or opts.user,
    picture = raw.picture,
    super = raw.hasPlus == true,
    streak = tonumber(streak.length) or tonumber(raw.streak) or 0,
    streak_start = streak.startDate,
    xp = tonumber(raw.totalXp) or 0,
    member_since = raw.creationDate
      and tonumber(os.date("!%Y", math.floor(raw.creationDate))) or nil,
    courses = courses,
  }
end

--=========================================================================
-- Render HTML
--=========================================================================

local function stat_tile(kind, profile, tr, lang)
  local value, label, icon, note
  if kind == "streak" then
    icon, label = "🔥", tr.streak
    value = group(profile.streak, tr.sep)
    local since = month_year(profile.streak_start, lang)
    if since and profile.streak > 0 then note = tr.from .. " " .. since end
  elseif kind == "xp" then
    icon, label, value = "⚡", tr.xp, group(profile.xp, tr.sep)
  elseif kind == "since" then
    if not profile.member_since then return "" end
    icon, label, value = "📅", tr.since, tostring(profile.member_since)
  else
    return ""
  end

  return table.concat({
    '<div class="duolingo-stat">',
    '<div class="duolingo-stat-value"><span class="duolingo-stat-icon">',
    icon, '</span>', esc(value), '</div>',
    '<div class="duolingo-stat-label">', esc(label), '</div>',
    note and ('<div class="duolingo-stat-note">' .. esc(note) .. '</div>') or '',
    '</div>',
  })
end

local function courses_html(profile, opts, tr)
  if opts.courses <= 0 or #profile.courses == 0 then return "" end

  local top = profile.courses[1].xp
  if top <= 0 then top = 1 end

  local rows = {}
  for i, c in ipairs(profile.courses) do
    if i > opts.courses then break end
    -- Barra proporcional ao curso lider: da para ler o peso de cada idioma
    -- de relance, sem precisar comparar numeros.
    local pct = math.max(2, math.floor((c.xp / top) * 100 + 0.5))
    rows[#rows + 1] = table.concat({
      '<div class="duolingo-course">',
      '<span class="duolingo-course-flag">', c.flag, '</span>',
      '<span class="duolingo-course-name">', esc(c.label), '</span>',
      '<span class="duolingo-course-track"><span class="duolingo-course-bar" style="width:',
      pct, '%"></span></span>',
      '<span class="duolingo-course-xp">', esc(group(c.xp, tr.sep)), ' XP</span>',
      '</div>',
    })
  end

  return '<div class="duolingo-courses"><div class="duolingo-section-label">'
    .. esc(tr.learning) .. '</div>' .. table.concat(rows) .. '</div>'
end

local function render_html(profile, opts, avatar)
  local tr = t(opts.lang)
  local classes = { "duolingo-card" }
  if opts.layout ~= "card" then
    classes[#classes + 1] = "duolingo-" .. opts.layout
  end
  if opts.theme ~= "auto" then
    classes[#classes + 1] = "duolingo-theme-" .. opts.theme
  end

  local avatar_html = ""
  if avatar then
    avatar_html = '<img class="duolingo-avatar" src="' .. avatar
      .. '" alt="' .. esc(profile.name) .. '" width="56" height="56" />'
  end

  local stats = {}
  for _, kind in ipairs(opts.stats) do
    stats[#stats + 1] = stat_tile(kind, profile, tr, opts.lang)
  end

  local head = table.concat({
    '<div class="duolingo-head">',
    avatar_html,
    '<div class="duolingo-identity">',
    '<div class="duolingo-name">', esc(profile.name),
    profile.super and ('<span class="duolingo-super">' .. esc(tr.super) .. '</span>') or '',
    '</div>',
    '<div class="duolingo-handle">@', esc(profile.username), '</div>',
    '</div>',
    '<span class="duolingo-owl" aria-hidden="true">🦉</span>',
    '</div>',
  })

  local body = table.concat({
    head,
    '<div class="duolingo-stats">', table.concat(stats), '</div>',
    opts.layout == "card" and courses_html(profile, opts, tr) or "",
    '<div class="duolingo-foot">', esc(tr.updated), ' ',
    esc(os.date("!%Y-%m-%d")), '</div>',
  })

  local style = 'style="--duolingo-accent:' .. esc(opts.accent) .. '"'
  local html
  if opts.link then
    html = '<a class="' .. table.concat(classes, " ") .. '" ' .. style
      .. ' href="' .. PROFILE_URL .. esc(profile.username)
      .. '" target="_blank" rel="noopener">' .. body .. '</a>'
  else
    html = '<div class="' .. table.concat(classes, " ") .. '" ' .. style .. '>'
      .. body .. '</div>'
  end

  return pandoc.RawBlock("html", html)
end

--=========================================================================
-- Render para formatos nao-HTML (PDF, DOCX, ...)
--=========================================================================

local function render_fallback(profile, opts)
  local tr = t(opts.lang)
  local parts = {
    pandoc.Str(profile.name), pandoc.Space(),
    pandoc.Str("(@" .. profile.username .. ")"), pandoc.Str(" — "),
    pandoc.Str(tr.streak .. ": " .. group(profile.streak, tr.sep)),
    pandoc.Str("; "),
    pandoc.Str(tr.xp .. ": " .. group(profile.xp, tr.sep)),
  }
  if opts.courses > 0 and #profile.courses > 0 then
    local names = {}
    for i, c in ipairs(profile.courses) do
      if i > opts.courses then break end
      names[#names + 1] = c.label .. " (" .. group(c.xp, tr.sep) .. " XP)"
    end
    parts[#parts + 1] = pandoc.Str("; ")
    parts[#parts + 1] = pandoc.Str(tr.learning .. ": " .. table.concat(names, ", "))
  end
  return pandoc.Para(parts)
end

--=========================================================================
-- Shortcode
--=========================================================================

--- Erro nao deve derrubar o build de um site por causa de rede instavel, entao
--- o padrao e avisar e omitir o card.
---
--- Para `on-error: fail` usamos os.exit em vez de error(): o Quarto captura
--- erros de shortcode e segue renderizando, entao error() so imprimiria uma
--- mensagem vermelha e o build terminaria com exit 0 — o oposto do que a
--- opcao promete. os.exit(1) derruba o pandoc e o build falha de fato.
local function bail(message, opts)
  local text = "[duolingo] " .. message
  if opts and opts["on-error"] == "fail" then
    io.stderr:write("ERROR: " .. text .. "\n")
    os.exit(1)
  end
  quarto.log.warning(text)
  return pandoc.Null()
end

return {
  ["duolingo"] = function(args, kwargs, meta)
    local opts = read_options(kwargs, meta)

    if not opts.user or opts.user == "" then
      return bail("no username set — add `duolingo: {user: your-username}` to "
        .. "your YAML, or write {{< duolingo user=\"your-username\" >}}", opts)
    end

    local profile, err = fetch_profile(opts.user)
    if not profile then return bail(err, opts) end

    profile = normalize(profile, opts)

    if not quarto.doc.is_format("html:js") then
      return render_fallback(profile, opts)
    end

    quarto.doc.add_html_dependency({
      name = "duolingo",
      stylesheets = { "duolingo.css" },
    })

    local avatar = opts.avatar and fetch_avatar(profile.picture) or nil
    return render_html(profile, opts, avatar)
  end,
}
