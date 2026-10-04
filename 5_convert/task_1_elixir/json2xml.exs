# Задача 5.1 (Elixir): конвертер JSON -> XML.
#
# Читает JSON-файл с объектами и массивами и рекурсивно переводит его в XML-теги
# с отступами (pretty-print).
#
# JSON разбирается собственным рекурсивным парсером на сопоставлении с образцом
# по бинарным строкам (стандартный модуль JSON появился только в Elixir 1.18 и
# не сохраняет порядок ключей, а для XML порядок важен).
#
# Правила преобразования:
#   объект {"a": 1}      -> <a>1</a> внутри родительского тега
#   массив "list": [x,y] -> <list><item>x</item><item>y</item></list>
#   null, {} и []        -> пустой тег <tag/>
#   недопустимые в XML имена ключей ("first name", "2fa") исправляются: first_name, _2fa
#   спецсимволы & < > " ' экранируются
#
# Запуск: elixir json2xml.exs <вход.json> [выход.xml]

defmodule Json do
  @moduledoc "Мини-парсер JSON. Объект -> {:object, [{ключ, значение}]} (порядок сохраняется)."

  def parse(text) do
    {value, rest} = value(skip_ws(text))

    case skip_ws(rest) do
      "" -> {:ok, value}
      other -> fail("лишние символы после JSON", other)
    end
  catch
    {:json_error, msg, rest} ->
      # позиция ошибки = сколько байт уже разобрано
      consumed = binary_part(text, 0, byte_size(text) - byte_size(rest))
      lines = String.split(consumed, "\n")
      {:error, "#{msg} (строка #{length(lines)}, столбец #{String.length(List.last(lines)) + 1})"}
  end

  defp fail(msg, rest), do: throw({:json_error, msg, rest})

  defp skip_ws(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r], do: skip_ws(rest)
  defp skip_ws(s), do: s

  # --- значение: выбор по первому символу -----------------------------------
  defp value("{" <> rest), do: object(skip_ws(rest), [])
  defp value("[" <> rest), do: array(skip_ws(rest), [])

  defp value("\"" <> rest) do
    {s, rest} = string(rest, [])
    {{:string, s}, rest}
  end

  defp value("true" <> rest), do: {true, rest}
  defp value("false" <> rest), do: {false, rest}
  defp value("null" <> rest), do: {nil, rest}

  defp value(s) do
    case Regex.run(~r/^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/, s) do
      [num | _] -> {{:number, num}, binary_part(s, byte_size(num), byte_size(s) - byte_size(num))}
      nil -> fail("ожидалось значение", s)
    end
  end

  # --- объект ---------------------------------------------------------------
  defp object("}" <> rest, []), do: {{:object, []}, rest}

  defp object("\"" <> rest, acc) do
    {key, rest} = string(rest, [])

    rest =
      case skip_ws(rest) do
        ":" <> r -> skip_ws(r)
        other -> fail("ожидалось ':' после ключа \"#{key}\"", other)
      end

    {val, rest} = value(rest)
    acc = [{key, val} | acc]

    case skip_ws(rest) do
      "," <> r -> object(skip_ws(r), acc)
      "}" <> r -> {{:object, Enum.reverse(acc)}, r}
      other -> fail("ожидалось ',' или '}'", other)
    end
  end

  defp object(s, _acc), do: fail("ожидался ключ в кавычках", s)

  # --- массив ---------------------------------------------------------------
  defp array("]" <> rest, []), do: {{:array, []}, rest}

  defp array(s, acc) do
    {val, rest} = value(s)
    acc = [val | acc]

    case skip_ws(rest) do
      "," <> r -> array(skip_ws(r), acc)
      "]" <> r -> {{:array, Enum.reverse(acc)}, r}
      other -> fail("ожидалось ',' или ']'", other)
    end
  end

  # --- строка с escape-последовательностями ---------------------------------
  defp string("\"" <> rest, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  # суррогатная пара 😀 -> один символ (эмодзи и т.п.)
  defp string(<<"\\u", hi::binary-size(4), "\\u", lo::binary-size(4), rest::binary>> = s, acc) do
    h = hex(hi, s)
    l = hex(lo, s)

    if h in 0xD800..0xDBFF and l in 0xDC00..0xDFFF do
      code = 0x10000 + (h - 0xD800) * 0x400 + (l - 0xDC00)
      string(rest, [<<code::utf8>> | acc])
    else
      string(<<"\\u", lo::binary, rest::binary>>, [codepoint(h, s) | acc])
    end
  end

  defp string(<<"\\u", hx::binary-size(4), rest::binary>> = s, acc),
    do: string(rest, [codepoint(hex(hx, s), s) | acc])

  defp string(<<"\\", c, rest::binary>> = s, acc) do
    ch =
      case c do
        ?" -> "\""
        ?\\ -> "\\"
        ?/ -> "/"
        ?b -> "\b"
        ?f -> "\f"
        ?n -> "\n"
        ?r -> "\r"
        ?t -> "\t"
        _ -> fail("неизвестная escape-последовательность \\#{<<c>>}", s)
      end

    string(rest, [ch | acc])
  end

  defp string(<<c::utf8, rest::binary>>, acc), do: string(rest, [<<c::utf8>> | acc])
  defp string(s, _acc), do: fail("незакрытая строка", s)

  defp hex(h, s) do
    case Integer.parse(h, 16) do
      {n, ""} -> n
      _ -> fail("неверная последовательность \\u#{h}", s)
    end
  end

  defp codepoint(n, s) when n in 0xD800..0xDFFF, do: fail("одиночный суррогат \\u#{Integer.to_string(n, 16)}", s)
  defp codepoint(n, _s), do: <<n::utf8>>
end

defmodule Xml do
  @moduledoc "Перевод разобранного JSON в XML с отступами."

  def document(value, root \\ "root") do
    IO.iodata_to_binary([~s(<?xml version="1.0" encoding="UTF-8"?>\n), element(root, value, 0)])
  end

  # Рекурсия: каждое значение превращается в тег, вложенность = глубина отступа
  defp element(name, value, depth) do
    tag = tag_name(name)
    pad = String.duplicate("  ", depth)

    case value do
      {:object, []} -> [pad, "<", tag, "/>\n"]
      {:array, []} -> [pad, "<", tag, "/>\n"]
      nil -> [pad, "<", tag, "/>\n"]

      {:object, pairs} ->
        children = Enum.map(pairs, fn {k, v} -> element(k, v, depth + 1) end)
        [pad, "<", tag, ">\n", children, pad, "</", tag, ">\n"]

      {:array, items} ->
        children = Enum.map(items, &element("item", &1, depth + 1))
        [pad, "<", tag, ">\n", children, pad, "</", tag, ">\n"]

      scalar ->
        [pad, "<", tag, ">", escape(text(scalar)), "</", tag, ">\n"]
    end
  end

  defp text({:string, s}), do: s
  defp text({:number, n}), do: n
  defp text(true), do: "true"
  defp text(false), do: "false"

  # Имя XML-тега: буквы, цифры, _ . - ; начинаться должно с буквы или _
  defp tag_name(name) do
    n = Regex.replace(~r/[^\p{L}\p{N}_.-]/u, name, "_")
    if Regex.match?(~r/^[\p{L}_]/u, n), do: n, else: "_" <> n
  end

  defp escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  # Статистика для отчёта
  def stats({:object, pairs}), do: add(%{objects: 1}, Enum.map(pairs, fn {_, v} -> stats(v) end))
  def stats({:array, items}), do: add(%{arrays: 1}, Enum.map(items, &stats/1))
  def stats(_), do: %{values: 1}

  defp add(acc, list),
    do: Enum.reduce(list, acc, fn m, a -> Map.merge(a, m, fn _k, x, y -> x + y end) end)
end

# ---------------------------------------------------------------------------

case System.argv() do
  [input | rest] when length(rest) <= 1 ->
    with {:ok, text} <- File.read(input),
         {:ok, json} <- Json.parse(text) do
      xml = Xml.document(json)
      s = Xml.stats(json)

      case rest do
        [output] ->
          File.write!(output, xml)
          IO.puts("Готово: #{input} -> #{output}")

        [] ->
          IO.write(xml)
      end

      IO.puts(:stderr,
        "Объектов: #{Map.get(s, :objects, 0)}, массивов: #{Map.get(s, :arrays, 0)}, " <>
          "значений: #{Map.get(s, :values, 0)}")
    else
      {:error, reason} when is_atom(reason) ->
        IO.puts(:stderr, "Не удалось прочитать #{input}: #{:file.format_error(reason)}")
        System.halt(1)

      {:error, msg} ->
        IO.puts(:stderr, "Ошибка в JSON: #{msg}")
        System.halt(1)
    end

  _ ->
    IO.puts("Использование: elixir json2xml.exs <вход.json> [выход.xml]")
    System.halt(1)
end
