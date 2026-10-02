# Задача 5.4 (Julia): конвертер YAML -> TOML.
#
# Разбирает простое подмножество YAML (словари по отступам, списки "- ",
# инлайн-списки [a, b] и словари {a: 1}, строки в кавычках, числа, bool, null, даты,
# комментарии) и записывает те же данные в TOML, соблюдая синтаксис ключей и секций:
#   вложенный словарь   -> секция [родитель.ключ]
#   список словарей     -> массив таблиц [[ключ]]
#   список значений     -> массив key = [1, 2, 3]
#
# Результат проверяется стандартным парсером TOML из библиотеки Julia:
# после обратного чтения данные должны совпасть с исходными.
#
# Запуск: julia yaml2toml.jl <вход.yaml> [выход.toml]

using TOML, Dates

# Словарь с сохранением порядка ключей (обычный Dict порядок не хранит)
struct OMap
    pairs::Vector{Pair{String,Any}}
end
OMap() = OMap(Pair{String,Any}[])

struct Line
    num::Int        # номер строки в файле (для сообщений об ошибках)
    indent::Int     # отступ в пробелах
    text::String    # содержимое без отступа и комментария
end

struct YamlError <: Exception
    line::Int
    msg::String
end

struct ConvertError <: Exception
    msg::String
end

# ===========================================================================
# Чтение YAML
# ===========================================================================

# Убрать комментарий "# ..." (но не '#' внутри кавычек)
function strip_comment(s::AbstractString)
    quote_char = nothing
    prev = ' '
    for (i, c) in pairs(s)
        if quote_char === nothing
            if c == '"' || c == '\''
                quote_char = c
            elseif c == '#' && isspace(prev)
                return rstrip(s[firstindex(s):prevind(s, i)])
            end
        elseif c == quote_char && prev != '\\'
            quote_char = nothing
        end
        prev = c
    end
    return rstrip(s)
end

function read_lines(text::AbstractString)
    lines = Line[]
    for (n, raw) in enumerate(split(text, '\n'))
        s = strip_comment(replace(raw, '\r' => ""))
        t = strip(s)
        (isempty(t) || t == "---" || t == "...") && continue
        indent = length(s) - length(lstrip(s))
        occursin('\t', s[1:indent]) && throw(YamlError(n, "табуляция в отступе (YAML допускает только пробелы)"))
        push!(lines, Line(n, indent, String(lstrip(s))))
    end
    return lines
end

is_item(t) = startswith(t, "- ") || t == "-"

# "- key: value" — начинается ли элемент списка со словаря
is_map_start(t) = occursin(r"^(\"[^\"]*\"|'[^']*'|[^\"'\[{][^:]*?):(\s|$)", t)

# Блок на данном отступе: список или словарь
function parse_block(L::Vector{Line}, i::Int, indent::Int)
    return is_item(L[i].text) ? parse_list(L, i, indent) : parse_map(L, i, indent)
end

# "ключ: значение" -> (ключ, значение-строка)
function split_key(line::Line)
    t = line.text
    if startswith(t, '"') || startswith(t, '\'')                  # ключ в кавычках
        j = findnext(t[1], t, 2)
        j === nothing && throw(YamlError(line.num, "незакрытая кавычка в ключе"))
        rest = t[nextind(t, j):end]
        startswith(rest, ':') || throw(YamlError(line.num, "ожидалось ':' после ключа"))
        return String(t[2:prevind(t, j)]), String(strip(rest[2:end]))
    end
    m = match(r"^([^:]+?):(\s+(.*))?$", t)
    m === nothing && throw(YamlError(line.num, "ожидалось «ключ: значение», а получено «$t»"))
    value = m.captures[3] === nothing ? "" : String(strip(m.captures[3]))
    return String(strip(m.captures[1])), value
end

function parse_map(L::Vector{Line}, i::Int, indent::Int)
    m = OMap()
    while i <= length(L) && L[i].indent == indent
        line = L[i]
        is_item(line.text) && throw(YamlError(line.num, "элемент списка там, где ожидался ключ"))
        key, rest = split_key(line)
        any(p -> p.first == key, m.pairs) && throw(YamlError(line.num, "повторный ключ «$key»"))
        i += 1
        if !isempty(rest)
            value = parse_scalar(rest, line.num)
        elseif i <= length(L) && L[i].indent > indent              # вложенный блок
            value, i = parse_block(L, i, L[i].indent)
        elseif i <= length(L) && L[i].indent == indent && is_item(L[i].text)
            value, i = parse_list(L, i, indent)                     # список на том же отступе
        else
            value = nothing                                         # "ключ:" без значения = null
        end
        push!(m.pairs, key => value)
    end
    if i <= length(L) && L[i].indent > indent
        throw(YamlError(L[i].num, "неожиданный отступ"))
    end
    return m, i
end

function parse_list(L::Vector{Line}, i::Int, indent::Int)
    items = Any[]
    while i <= length(L) && L[i].indent == indent && is_item(L[i].text)
        line = L[i]
        rest = line.text == "-" ? "" : String(strip(line.text[3:end]))
        if isempty(rest)
            i += 1
            value = nothing
            if i <= length(L) && L[i].indent > indent
                value, i = parse_block(L, i, L[i].indent)
            end
        elseif is_map_start(rest) || is_item(rest)
            # "- key: v" или "- - x": содержимое элемента начинается на отступе indent + 2,
            # подменяем строку и разбираем её как обычный блок
            L[i] = Line(line.num, indent + 2, rest)
            value, i = parse_block(L, i, indent + 2)
        else
            value = parse_scalar(rest, line.num)
            i += 1
        end
        push!(items, value)
    end
    return items, i
end

# Разбить "a, [b, c], 'd, e'" по запятым верхнего уровня
function split_flow(s::AbstractString)
    parts = String[]
    depth, quote_char, start = 0, nothing, firstindex(s)
    for (i, c) in pairs(s)
        if quote_char !== nothing
            c == quote_char && (quote_char = nothing)
        elseif c == '"' || c == '\''
            quote_char = c
        elseif c == '[' || c == '{'
            depth += 1
        elseif c == ']' || c == '}'
            depth -= 1
        elseif c == ',' && depth == 0
            push!(parts, strip(s[start:prevind(s, i)]))
            start = nextind(s, i)
        end
    end
    push!(parts, strip(s[start:end]))
    return filter(!isempty, parts)
end

inner(s) = strip(s[nextind(s, firstindex(s)):prevind(s, lastindex(s))])

function parse_scalar(raw::AbstractString, num::Int)
    s = strip(raw)
    if startswith(s, '"')
        (length(s) >= 2 && endswith(s, '"')) || throw(YamlError(num, "незакрытая строка"))
        return unescape_string(s[2:prevind(s, lastindex(s))])     # \n, \t, \", \uXXXX
    elseif startswith(s, '\'')
        (length(s) >= 2 && endswith(s, '\'')) || throw(YamlError(num, "незакрытая строка"))
        return replace(s[2:prevind(s, lastindex(s))], "''" => "'")
    elseif startswith(s, '[')
        endswith(s, ']') || throw(YamlError(num, "незакрытый список [...]"))
        return Any[parse_scalar(x, num) for x in split_flow(inner(s))]
    elseif startswith(s, '{')
        endswith(s, '}') || throw(YamlError(num, "незакрытый словарь {...}"))
        m = OMap()
        for part in split_flow(inner(s))
            k = findfirst(':', part)
            k === nothing && throw(YamlError(num, "ожидалось «ключ: значение» в {...}"))
            push!(m.pairs, String(strip(part[1:prevind(part, k)])) => parse_scalar(part[nextind(part, k):end], num))
        end
        return m
    elseif s == "|" || s == ">"
        throw(YamlError(num, "многострочные строки (| и >) не поддерживаются"))
    elseif s in ("null", "Null", "NULL", "~")
        return nothing
    elseif s in ("true", "True", "TRUE")
        return true
    elseif s in ("false", "False", "FALSE")
        return false
    elseif occursin(r"^[-+]?\d+$", s)
        return parse(Int, s)
    elseif occursin(r"^[-+]?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?$", s)
        return parse(Float64, s)
    elseif s in (".inf", "+.inf")
        return Inf
    elseif s == "-.inf"
        return -Inf
    elseif occursin(r"^\d{4}-\d{2}-\d{2}$", s)
        d = tryparse(Date, s)                       # дата -> в TOML будет "local date"
        return d === nothing ? String(s) : d
    else
        return String(s)                            # строка без кавычек
    end
end

function parse_yaml(text::AbstractString)
    L = read_lines(text)
    isempty(L) && return OMap()
    value, i = parse_block(L, 1, L[1].indent)
    i <= length(L) && throw(YamlError(L[i].num, "неожиданный отступ"))
    return value
end

# ===========================================================================
# Запись TOML
# ===========================================================================

key(k) = occursin(r"^[A-Za-z0-9_-]+$", k) ? k : toml_string(k)   # "bare key" или в кавычках

function toml_string(s::AbstractString)
    io = IOBuffer()
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\t'
            print(io, "\\t")
        elseif c == '\r'
            print(io, "\\r")
        elseif c < ' ' || c == '\x7f'
            print(io, "\\u", lpad(string(UInt32(c), base = 16), 4, '0'))
        else
            print(io, c)
        end
    end
    print(io, '"')
    return String(take!(io))
end

toml_value(x::AbstractString) = toml_string(x)
toml_value(x::Bool) = x ? "true" : "false"
toml_value(x::Integer) = string(x)
toml_value(x::Date) = string(x)
toml_value(x::AbstractFloat) = isnan(x) ? "nan" : isinf(x) ? (x > 0 ? "inf" : "-inf") : string(x)
toml_value(x::AbstractVector) = "[" * join(map(toml_value, x), ", ") * "]"
toml_value(x::OMap) = "{ " * join(["$(key(k)) = $(toml_value(v))" for (k, v) in x.pairs], ", ") * " }"
toml_value(::Nothing) = throw(ConvertError("null внутри списка или инлайн-словаря нельзя записать в TOML"))

is_table_array(v) = v isa AbstractVector && !isempty(v) && all(x -> x isa OMap, v)

# Секция TOML: сначала простые "ключ = значение", потом вложенные таблицы
# (в TOML простые ключи таблицы обязаны идти до её подтаблиц)
function write_table(io::IO, m::OMap, path::Vector{String})
    for (k, v) in m.pairs
        if v === nothing
            println(io, "# ", key(k), " = null  (в TOML нет null — ключ пропущен)")
        elseif !(v isa OMap) && !is_table_array(v)
            println(io, key(k), " = ", toml_value(v))
        end
    end
    for (k, v) in m.pairs
        p = [path; k]
        header = join(key.(p), ".")
        if v isa OMap
            print(io, "\n[", header, "]\n")
            write_table(io, v, p)
        elseif is_table_array(v)
            for item in v
                print(io, "\n[[", header, "]]\n")
                write_table(io, item, p)
            end
        end
    end
end

# Для проверки: наши данные -> Dict, как их вернёт TOML.parse (null-ключи пропускаются)
to_plain(x::OMap) = Dict{String,Any}(k => to_plain(v) for (k, v) in x.pairs if v !== nothing)
to_plain(x::AbstractVector) = Any[to_plain(e) for e in x]
to_plain(x) = x

count_keys(x::OMap) = sum((1 + count_keys(v) for (_, v) in x.pairs); init = 0)
count_keys(x::AbstractVector) = sum((count_keys(e) for e in x); init = 0)
count_keys(_) = 0

# ===========================================================================

function main(args)
    if isempty(args) || length(args) > 2
        println("Использование: julia yaml2toml.jl <вход.yaml> [выход.toml]")
        exit(1)
    end
    input = args[1]
    isfile(input) || (println(stderr, "Файл не найден: $input"); exit(1))

    data = try
        parse_yaml(read(input, String))
    catch e
        e isa YamlError || rethrow()
        println(stderr, "Ошибка YAML ($input, строка $(e.line)): $(e.msg)")
        exit(1)
    end
    data isa OMap || (println(stderr, "Корень YAML должен быть словарём: TOML-документ — это всегда таблица"); exit(1))

    io = IOBuffer()
    try
        write_table(io, data, String[])
    catch e
        e isa ConvertError || rethrow()
        println(stderr, "Ошибка преобразования: $(e.msg)")
        exit(1)
    end
    out = String(lstrip(String(take!(io)), '\n'))

    if length(args) == 2
        write(args[2], out)
        println("Готово: $input -> $(args[2])")
    else
        print(out)
    end

    # Самопроверка стандартным парсером TOML
    same = TOML.parse(out) == to_plain(data)
    println(stderr, "\nКлючей: $(count_keys(data)). Проверка TOML.parse: синтаксис корректен, данные ",
            same ? "совпадают с исходными" : "ОТЛИЧАЮТСЯ от исходных")
end

main(ARGS)
