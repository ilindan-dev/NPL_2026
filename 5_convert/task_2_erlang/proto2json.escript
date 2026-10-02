#!/usr/bin/env escript
%% -*- erlang -*-
%%
%% Задача 5.2 (Erlang): PROTO-сообщения -> JSON.
%%
%% Программа читает:
%%   1) схему .proto (message / enum, поля с типами и номерами, repeated);
%%   2) сообщение в текстовом формате Protobuf (text format, .txtpb):
%%        name: "Alice"
%%        phones { number: "+7 999" type: MOBILE }
%% проверяет данные по схеме (имена полей, типы, диапазоны, значения enum)
%% и собирает стандартный JSON по правилам proto3 JSON mapping:
%%   - имена полей в lowerCamelCase (phone_number -> phoneNumber);
%%   - repeated -> массив; enum -> строка с именем значения;
%%   - int64/uint64 -> строка (в JSON-числах теряется точность больших целых);
%%   - bytes -> Base64; поля порядка схемы, незаданные поля не выводятся.
%%
%% Запуск: escript proto2json.escript <схема.proto> <ТипСообщения> <данные.txtpb> [выход.json]

-mode(compile).

%% ===========================================================================
%% Лексер: общий для .proto и text format
%% Токены: {ident, Line, "name"} {int, Line, 42} {float, Line, 2.5}
%%         {str, Line, "text"}   {punct, Line, ${}
%% ===========================================================================

tokenize(Cs) -> tokenize(Cs, 1, []).

tokenize([], _L, Acc) -> lists:reverse(Acc);
tokenize([$\n | T], L, Acc) -> tokenize(T, L + 1, Acc);
tokenize([C | T], L, Acc) when C =:= $\s; C =:= $\t; C =:= $\r -> tokenize(T, L, Acc);
tokenize([$/, $/ | T], L, Acc) -> tokenize(skip_line(T), L, Acc);
tokenize([$# | T], L, Acc) -> tokenize(skip_line(T), L, Acc);
tokenize([Q | T], L, Acc) when Q =:= $"; Q =:= $' ->
    {S, Rest} = str(T, Q, L, []),
    tokenize(Rest, L, [{str, L, S} | Acc]);
tokenize([C | _] = Cs, L, Acc) when (C >= $0 andalso C =< $9) orelse C =:= $- ->
    {Tok, Rest} = number(Cs, L),
    tokenize(Rest, L, [Tok | Acc]);
tokenize([C | _] = Cs, L, Acc) when (C >= $a andalso C =< $z) orelse (C >= $A andalso C =< $Z) orelse C =:= $_ ->
    {Id, Rest} = lists:splitwith(fun is_ident_char/1, Cs),
    tokenize(Rest, L, [{ident, L, Id} | Acc]);
tokenize([C | T], L, Acc) ->
    case lists:member(C, "{}=;:[]<>,") of
        true -> tokenize(T, L, [{punct, L, C} | Acc]);
        false -> throw({error, L, io_lib:format("неожиданный символ '~tc'", [C])})
    end.

is_ident_char(C) ->
    (C >= $a andalso C =< $z) orelse (C >= $A andalso C =< $Z)
        orelse (C >= $0 andalso C =< $9) orelse C =:= $_ orelse C =:= $..

skip_line(Cs) -> lists:dropwhile(fun(C) -> C =/= $\n end, Cs).

str([Q | T], Q, _L, Acc) -> {lists:reverse(Acc), T};
str([$\\, C | T], Q, L, Acc) -> str(T, Q, L, [unescape(C) | Acc]);
str([$\n | _], _Q, L, _Acc) -> throw({error, L, "незакрытая строка"});
str([C | T], Q, L, Acc) -> str(T, Q, L, [C | Acc]);
str([], _Q, L, _Acc) -> throw({error, L, "незакрытая строка"}).

unescape($n) -> $\n;
unescape($t) -> $\t;
unescape($r) -> $\r;
unescape(C) -> C.

number(Cs, L) ->
    {Text, Rest} = lists:splitwith(
        fun(C) -> (C >= $0 andalso C =< $9) orelse lists:member(C, "-+.eE") end, Cs),
    case string:to_integer(Text) of
        {I, []} -> {{int, L, I}, Rest};
        _ ->
            case string:to_float(normalize_float(Text)) of
                {F, []} -> {{float, L, F}, Rest};
                _ -> throw({error, L, "неверное число " ++ Text})
            end
    end.

%% "1e5" и "3" -> "1.0e5"/"3.0": string:to_float требует точку
normalize_float(Text) ->
    case lists:member($., Text) of
        true -> Text;
        false ->
            {Mant, Exp} = lists:splitwith(fun(C) -> C =/= $e andalso C =/= $E end, Text),
            Mant ++ ".0" ++ Exp
    end.

%% ===========================================================================
%% Парсер .proto -> схема #{messages => #{Имя => [Поле]}, enums => #{Имя => [{Id, N}]}}
%% ===========================================================================

parse_proto(Toks) -> parse_proto(Toks, #{messages => #{}, enums => #{}}).

parse_proto([], S) -> S;
parse_proto([{ident, _, "message"}, {ident, _, Name}, {punct, _, ${} | T], S) ->
    {S1, Rest} = parse_message(Name, T, [], S),
    parse_proto(Rest, S1);
parse_proto([{ident, _, "enum"}, {ident, _, Name}, {punct, _, ${} | T], S) ->
    {S1, Rest} = parse_enum(Name, T, [], S),
    parse_proto(Rest, S1);
parse_proto([{ident, _, K} | T], S)
  when K =:= "syntax"; K =:= "package"; K =:= "option"; K =:= "import" ->
    parse_proto(skip_stmt(T), S);
parse_proto([{_, L, _} | _], _S) ->
    throw({error, L, "ожидалось message, enum, syntax, package, option или import"}).

%% пропустить до ';' включительно (опции, reserved, [packed = true] и т.п.)
skip_stmt([{punct, _, $;} | T]) -> T;
skip_stmt([_ | T]) -> skip_stmt(T);
skip_stmt([]) -> [].

parse_message(Name, [{punct, _, $}} | T], Fields, S) ->
    #{messages := Ms} = S,
    {S#{messages := Ms#{Name => lists:reverse(Fields)}}, T};
parse_message(Name, [{ident, _, "message"}, {ident, _, N}, {punct, _, ${} | T], F, S) ->
    {S1, R} = parse_message(N, T, [], S),           % вложенное сообщение
    parse_message(Name, R, F, S1);
parse_message(Name, [{ident, _, "enum"}, {ident, _, N}, {punct, _, ${} | T], F, S) ->
    {S1, R} = parse_enum(N, T, [], S),              % вложенный enum
    parse_message(Name, R, F, S1);
parse_message(Name, [{ident, _, K} | T], F, S) when K =:= "reserved"; K =:= "option" ->
    parse_message(Name, skip_stmt(T), F, S);
parse_message(Name, [{ident, _, Label}, {ident, _, Type}, {ident, _, FName},
                     {punct, _, $=}, {int, _, Num} | T], F, S)
  when Label =:= "repeated"; Label =:= "optional" ->
    parse_message(Name, skip_stmt(T), [field(FName, Type, Num, Label =:= "repeated") | F], S);
parse_message(Name, [{ident, _, Type}, {ident, _, FName}, {punct, _, $=}, {int, _, Num} | T], F, S) ->
    parse_message(Name, skip_stmt(T), [field(FName, Type, Num, false) | F], S);
parse_message(Name, [{_, L, _} | _], _F, _S) ->
    throw({error, L, "не удалось разобрать поле в message " ++ Name});
parse_message(Name, [], _F, _S) ->
    throw({error, 0, "нет закрывающей '}' у message " ++ Name}).

field(Name, Type, Num, Repeated) ->
    #{name => Name, type => Type, number => Num, repeated => Repeated}.

parse_enum(Name, [{punct, _, $}} | T], Vals, S) ->
    #{enums := Es} = S,
    {S#{enums := Es#{Name => lists:reverse(Vals)}}, T};
parse_enum(Name, [{ident, _, "option"} | T], V, S) ->
    parse_enum(Name, skip_stmt(T), V, S);
parse_enum(Name, [{ident, _, Id}, {punct, _, $=}, {int, _, N} | T], V, S) ->
    parse_enum(Name, skip_stmt(T), [{Id, N} | V], S);
parse_enum(Name, [{_, L, _} | _], _V, _S) ->
    throw({error, L, "не удалось разобрать значение enum " ++ Name});
parse_enum(Name, [], _V, _S) ->
    throw({error, 0, "нет закрывающей '}' у enum " ++ Name}).

%% ===========================================================================
%% Парсер text format -> [{ИмяПоля, Значение, Строка}]
%% Значение: {scalar, Kind, V, Line} | {msg, [Поля]}
%% ===========================================================================

parse_text(Toks) ->
    {Fields, []} = text_fields(Toks, eof, []),
    Fields.

text_fields([], eof, Acc) -> {lists:reverse(Acc), []};
text_fields([], _End, _Acc) -> throw({error, 0, "не хватает закрывающей скобки"});
text_fields([{punct, _, C} | T], End, Acc) when C =:= End -> {lists:reverse(Acc), T};
text_fields([{punct, _, C} | T], End, Acc) when C =:= $,; C =:= $; -> text_fields(T, End, Acc);
text_fields([{ident, L, Name}, {punct, _, $:} | T], End, Acc) ->
    {Vals, Rest} = text_value(T),                       % "поле: значение" или "поле: [a, b]"
    text_fields(Rest, End, lists:reverse([{Name, V, L} || V <- Vals]) ++ Acc);
text_fields([{ident, L, Name}, {punct, _, O} | _] = Toks, End, Acc) when O =:= ${; O =:= $< ->
    {V, Rest} = text_message(tl(Toks)),                 % "поле { ... }"
    text_fields(Rest, End, [{Name, V, L} | Acc]);
text_fields([{_, L, _} | _], _End, _Acc) ->
    throw({error, L, "ожидалось 'поле: значение' или 'поле { ... }'"}).

text_message([{punct, _, O} | T]) ->
    Close = case O of ${ -> $}; $< -> $> end,
    {Fields, Rest} = text_fields(T, Close, []),
    {{msg, Fields}, Rest}.

text_value([{punct, _, $[} | T]) -> text_list(T, []);
text_value([{punct, _, O} | _] = Toks) when O =:= ${; O =:= $< ->
    {V, R} = text_message(Toks),
    {[V], R};
text_value([{Kind, L, V} | T]) when Kind =:= int; Kind =:= float; Kind =:= str; Kind =:= ident ->
    {[{scalar, Kind, V, L}], T};
text_value([{_, L, _} | _]) -> throw({error, L, "ожидалось значение"});
text_value([]) -> throw({error, 0, "ожидалось значение, а файл закончился"}).

text_list([{punct, _, $]} | T], Acc) -> {lists:reverse(Acc), T};
text_list([{punct, _, $,} | T], Acc) -> text_list(T, Acc);
text_list(Toks, Acc) ->
    {[V], R} = text_value(Toks),
    text_list(R, [V | Acc]).

%% ===========================================================================
%% Проверка по схеме и сборка JSON-дерева
%% ===========================================================================

convert(MsgName, Fields, Schema) ->
    #{messages := Ms} = Schema,
    Defs = case maps:find(MsgName, Ms) of
               {ok, D} -> D;
               error -> throw({error, 0, "в схеме нет сообщения " ++ MsgName})
           end,
    Known = [maps:get(name, F) || F <- Defs],
    [throw({error, L, io_lib:format("в сообщении ~ts нет поля '~ts'", [MsgName, N])})
     || {N, _, L} <- Fields, not lists:member(N, Known)],
    Pairs = lists:filtermap(
        fun(F = #{name := Name, repeated := Rep}) ->
            Vals = [{V, L} || {N, V, L} <- Fields, N =:= Name],
            case {Vals, Rep} of
                {[], _} -> false;
                {_, true} -> {true, {json_name(Name), {array, [conv(F, V, L, Schema) || {V, L} <- Vals]}}};
                {[{V, L}], false} -> {true, {json_name(Name), conv(F, V, L, Schema)}};
                {[_, {_, L} | _], false} ->
                    throw({error, L, io_lib:format("поле '~ts' не repeated, но задано несколько раз", [Name])})
            end
        end, Defs),
    {object, Pairs}.

conv(#{name := Name, type := Type}, Value, L, Schema) ->
    Err = fun(What) ->
              throw({error, L, io_lib:format("поле '~ts' (~ts): ~ts", [Name, Type, What])})
          end,
    case {type_kind(Type, Schema), Value} of
        {{int, Min, Max, AsString}, {scalar, int, N, _}} when N >= Min, N =< Max ->
            case AsString of
                true -> {string, integer_to_list(N)};
                false -> {number, integer_to_list(N)}
            end;
        {{int, _, _, _}, {scalar, int, N, _}} ->
            Err(io_lib:format("значение ~p вне допустимого диапазона", [N]));
        {float, {scalar, K, N, _}} when K =:= int; K =:= float ->
            {number, num_to_list(N)};
        {bool, {scalar, ident, B, _}} when B =:= "true"; B =:= "false" ->
            {raw, B};
        {string, {scalar, str, S, _}} ->
            {string, S};
        {bytes, {scalar, str, S, _}} ->
            {string, base64:encode_to_string(unicode:characters_to_binary(S))};
        {{enum, Vals}, {scalar, ident, Id, _}} ->
            case lists:keymember(Id, 1, Vals) of
                true -> {string, Id};
                false -> Err("нет такого значения enum: " ++ Id)
            end;
        {{enum, Vals}, {scalar, int, N, _}} ->
            case lists:keyfind(N, 2, Vals) of
                {Id, _} -> {string, Id};
                false -> Err(io_lib:format("нет значения enum с номером ~p", [N]))
            end;
        {{message, M}, {msg, Fs}} ->
            convert(M, Fs, Schema);
        {unknown, _} ->
            Err("неизвестный тип (нет такого message/enum в схеме)");
        _ ->
            Err("значение не соответствует типу")
    end.

type_kind("int32", _) -> {int, -2147483648, 2147483647, false};
type_kind("sint32", _) -> {int, -2147483648, 2147483647, false};
type_kind("sfixed32", _) -> {int, -2147483648, 2147483647, false};
type_kind("uint32", _) -> {int, 0, 4294967295, false};
type_kind("fixed32", _) -> {int, 0, 4294967295, false};
type_kind("int64", _) -> {int, -9223372036854775808, 9223372036854775807, true};
type_kind("sint64", _) -> {int, -9223372036854775808, 9223372036854775807, true};
type_kind("sfixed64", _) -> {int, -9223372036854775808, 9223372036854775807, true};
type_kind("uint64", _) -> {int, 0, 18446744073709551615, true};
type_kind("fixed64", _) -> {int, 0, 18446744073709551615, true};
type_kind("float", _) -> float;
type_kind("double", _) -> float;
type_kind("bool", _) -> bool;
type_kind("string", _) -> string;
type_kind("bytes", _) -> bytes;
type_kind(Type, #{messages := Ms, enums := Es}) ->
    Short = lists:last(string:split(Type, ".", all)),   % demo.Phone / Person.Type -> короткое имя
    case maps:find(Short, Es) of
        {ok, Vals} -> {enum, Vals};
        error ->
            case maps:is_key(Short, Ms) of
                true -> {message, Short};
                false -> unknown
            end
    end.

num_to_list(N) when is_integer(N) -> integer_to_list(N);
num_to_list(F) -> float_to_list(F, [short]).

%% phone_number -> phoneNumber
json_name(Name) -> camel(Name, false).
camel([], _) -> [];
camel([$_ | T], _) -> camel(T, true);
camel([C | T], true) when C >= $a, C =< $z -> [C - 32 | camel(T, false)];
camel([C | T], _) -> [C | camel(T, false)].

%% ===========================================================================
%% Вывод JSON с отступами
%% ===========================================================================

json({object, []}, _) -> "{}";
json({object, Pairs}, Ind) ->
    Pad = lists:duplicate(Ind + 2, $\s),
    ["{\n",
     lists:join(",\n", [[Pad, quote(K), ": ", json(V, Ind + 2)] || {K, V} <- Pairs]),
     "\n", lists:duplicate(Ind, $\s), "}"];
json({array, []}, _) -> "[]";
json({array, Items}, Ind) ->
    case lists:any(fun({object, _}) -> true; (_) -> false end, Items) of
        false ->                                            % простые значения - в одну строку
            ["[", lists:join(", ", [json(I, Ind) || I <- Items]), "]"];
        true ->
            Pad = lists:duplicate(Ind + 2, $\s),
            ["[\n", lists:join(",\n", [[Pad, json(I, Ind + 2)] || I <- Items]),
             "\n", lists:duplicate(Ind, $\s), "]"]
    end;
json({string, S}, _) -> quote(S);
json({number, N}, _) -> N;
json({raw, B}, _) -> B.

quote(S) -> [$", escape(S), $"].

escape([]) -> [];
escape([$" | T]) -> [$\\, $" | escape(T)];
escape([$\\ | T]) -> [$\\, $\\ | escape(T)];
escape([$\n | T]) -> "\\n" ++ escape(T);
escape([$\t | T]) -> "\\t" ++ escape(T);
escape([$\r | T]) -> "\\r" ++ escape(T);
escape([C | T]) when C < 32 -> io_lib:format("\\u~4.16.0b", [C]) ++ escape(T);
escape([C | T]) -> [C | escape(T)].

%% ===========================================================================
%% main
%% ===========================================================================

read(File) ->
    case file:read_file(File) of
        {ok, Bin} -> unicode:characters_to_list(Bin);
        {error, R} -> throw({error, 0, "не удалось прочитать файл: " ++ file:format_error(R)})
    end.

%% Выполнить F, добавив к ошибке имя файла
in_file(File, F) ->
    try F()
    catch throw:{error, L, Msg} -> throw({error, File, L, Msg})
    end.

main(Args) ->
    io:setopts(standard_io, [{encoding, unicode}]),
    io:setopts(standard_error, [{encoding, unicode}]),
    case Args of
        [Proto, Msg, Data | Out] when length(Out) =< 1 ->
            try
                Schema = in_file(Proto, fun() -> parse_proto(tokenize(read(Proto))) end),
                Fields = in_file(Data, fun() -> parse_text(tokenize(read(Data))) end),
                Tree = in_file(Data, fun() -> convert(Msg, Fields, Schema) end),
                Json = unicode:characters_to_binary([json(Tree, 0), "\n"]),
                case Out of
                    [] -> io:put_chars(Json);
                    [OutFile] ->
                        ok = file:write_file(OutFile, Json),
                        io:format("Готово: ~ts -> ~ts~n", [Data, OutFile])
                end,
                #{messages := Ms, enums := Es} = Schema,
                io:format(standard_error, "Схема: сообщений ~p, enum ~p; проверка по типу ~ts пройдена~n",
                          [map_size(Ms), map_size(Es), Msg])
            catch
                throw:{error, File, Line, Text} ->
                    Where = case Line of 0 -> ""; _ -> io_lib:format(", строка ~p", [Line]) end,
                    io:format(standard_error, "Ошибка (~ts~ts): ~ts~n", [File, Where, Text]),
                    halt(1)
            end;
        _ ->
            io:format("Использование: proto2json.escript <схема.proto> <ТипСообщения> <данные.txtpb> [выход.json]~n"),
            halt(1)
    end.
