-- Задача 4.3 (Lua): TCP-заглушка API погоды на luasocket.
--
-- Клиент шлёт название города (одна строка). Сервер случайно генерирует температуру
-- и погодные условия, упаковывает в строку и отправляет обратно.
-- Сервер однопоточный, но обслуживает много клиентов сразу через socket.select().
--
-- Запуск:  lua weather.lua server [порт]
--          lua weather.lua client [хост] [порт] [город ...]
--          (без городов - интерактивный режим)

local socket = require("socket")
local unpack = table.unpack or unpack

local DEFAULT_PORT = 5003
local CACHE_SECONDS = 60      -- для одного города погода стабильна в течение минуты

local function log(fmt, ...)
  print(os.date("[%H:%M:%S] ") .. string.format(fmt, ...))
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------------------------------------------------------------------------
-- "Погода"
-- ---------------------------------------------------------------------------

local cache = {}   -- [город] = { text = ..., time = ... }

local function pick(list) return list[math.random(#list)] end

local function make_weather(city)
  local t = math.random(-25, 35)
  local cond
  if t <= 0 then
    cond = pick({ "снег", "ясно", "облачно", "метель", "туман" })
  elseif t < 15 then
    cond = pick({ "дождь", "облачно", "переменная облачность", "туман", "ясно" })
  else
    cond = pick({ "солнечно", "ясно", "переменная облачность", "гроза", "дождь" })
  end
  return string.format("%s: %+d°C, %s, ветер %d м/с, влажность %d%%",
    city, t, cond, math.random(0, 15), math.random(30, 95))
end

local function get_weather(city)
  local now = os.time()
  local entry = cache[city]
  if not entry or now - entry.time >= CACHE_SECONDS then
    entry = { text = make_weather(city), time = now }
    cache[city] = entry
  end
  return "OK " .. entry.text
end

-- ---------------------------------------------------------------------------
-- Сервер
-- ---------------------------------------------------------------------------

local function run_server(port)
  math.randomseed(os.time())
  local server = assert(socket.bind("*", port))
  local clients = {}        -- список клиентских сокетов
  local names = {}          -- [сокет] = "клиент#N"
  local counter = 0
  log("Сервер погоды запущен на порту %d", port)

  local function drop(c)
    for i, s in ipairs(clients) do
      if s == c then table.remove(clients, i) break end
    end
    log("%s отключился, клиентов: %d", names[c], #clients)
    names[c] = nil
    c:close()
  end

  while true do
    -- select ждёт, пока хотя бы один сокет станет готов к чтению:
    -- либо новый клиент на server, либо строка от уже подключённого
    local readable = socket.select({ server, unpack(clients) }, nil)

    for _, s in ipairs(readable) do
      if s == server then
        local c = server:accept()
        if c then
          c:settimeout(5)
          counter = counter + 1
          names[c] = "клиент#" .. counter
          table.insert(clients, c)
          log("%s подключился, клиентов: %d", names[c], #clients)
          c:send("Сервер погоды. Отправьте название города (QUIT - выход)\n")
        end
      else
        local line = s:receive("*l")
        if not line then
          drop(s)
        else
          local city = trim(line)
          if city:upper() == "QUIT" then
            s:send("BYE\n")
            drop(s)
          elseif city == "" then
            s:send("ERROR пустое название города\n")
          else
            local answer = get_weather(city)
            log("%s спросил «%s» -> %s", names[s], city, answer)
            s:send(answer .. "\n")
          end
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Клиент
-- ---------------------------------------------------------------------------

local function run_client(host, port, cities)
  local c, err = socket.connect(host, port)
  if not c then
    print("Не удалось подключиться к " .. host .. ":" .. port .. " (" .. tostring(err) .. ")")
    os.exit(1)
  end
  print(c:receive("*l"))

  local function ask(city)
    c:send(city .. "\n")
    local answer = c:receive("*l")
    if not answer then print("Соединение закрыто") os.exit(0) end
    print(answer)
  end

  if #cities > 0 then                       -- разовые запросы из аргументов
    for _, city in ipairs(cities) do ask(city) end
    c:send("QUIT\n")
  else                                      -- интерактивный режим
    while true do
      io.write("Город> ")
      io.flush()
      local city = io.read("*l")
      if not city then break end
      ask(city)
      if trim(city):upper() == "QUIT" then break end
    end
  end
  c:close()
end

-- ---------------------------------------------------------------------------

local mode = arg[1]
if mode == "server" then
  run_server(tonumber(arg[2]) or DEFAULT_PORT)
elseif mode == "client" then
  run_client(arg[2] or "localhost", tonumber(arg[3]) or DEFAULT_PORT, { select(4, unpack(arg)) })
else
  print("Использование: weather.lua server [порт] | weather.lua client [хост] [порт] [город ...]")
end
