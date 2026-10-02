:- encoding(utf8).
% Задача 2.1 (Prolog): Generate Parentheses (LeetCode 22).
% Сгенерировать все правильные скобочные последовательности из N пар скобок.
%
% Решение — перебор с возвратом (backtracking), который в Prolog встроен:
% правило parens/3 описывает, КАК можно продолжить строку, а Prolog сам
% перебирает все варианты.
%
% Запуск: swipl parens.pl [N]        (по умолчанию N = 3)

:- use_module(library(main)).
:- initialization(main, main).

% parens(+Open, +Close, -Chars)
%   Open  — сколько открывающих скобок ещё можно поставить,
%   Close — сколько закрывающих ещё нужно поставить,
%   Chars — получившийся хвост последовательности.

% Скобки кончились — последовательность готова.
parens(0, 0, []).

% Можно открыть скобку, если открывающие ещё остались.
parens(Open, Close, ['('|Rest]) :-
    Open > 0,
    Open1 is Open - 1,
    parens(Open1, Close, Rest).

% Можно закрыть скобку, если открытых сейчас больше, чем закрытых,
% то есть закрывающих осталось больше, чем открывающих.
parens(Open, Close, [')'|Rest]) :-
    Close > Open,
    Close1 is Close - 1,
    parens(Open, Close1, Rest).

% generate(+N, -S): S — одна правильная последовательность из N пар.
% При возврате (backtracking) выдаёт следующую.
generate(N, S) :-
    parens(N, N, Chars),
    atom_chars(S, Chars).

% Все ответы списком — как в LeetCode.
generate_all(N, List) :-
    findall(S, generate(N, S), List).

% Число Каталана C(n) = (2n)! / ((n+1)! n!) — сколько должно получиться ответов.
catalan(N, C) :-
    fact(2 * N, A), fact(N + 1, B), fact(N, D),
    C is A // (B * D).

fact(N0, F) :- N is N0, ( N =< 1 -> F = 1 ; N1 is N - 1, fact(N1, F1), F is N * F1 ).

main(Argv) :-
    ( Argv = [Arg|_] -> atom_number(Arg, N) ; N = 3 ),
    format("n = ~w~n~n", [N]),
    generate_all(N, List),
    forall(nth1(I, List, S), format("  ~t~w~4|. ~w~n", [I, S])),
    length(List, Len),
    catalan(N, C),
    format("~nВсего: ~w (число Каталана C(~w) = ~w)~n", [Len, N, C]),
    format("Ответ в формате LeetCode: ~q~n~n", [List]),
    format("Проверка для n = 1..8:~n"),
    forall(between(1, 8, K),
           ( generate_all(K, L), length(L, LK), catalan(K, CK),
             ( LK =:= CK -> Ok = "ok" ; Ok = "ОШИБКА" ),
             format("  n=~w: ~w последовательностей, C(~w)=~w  ~w~n", [K, LK, K, CK, Ok]) )).
