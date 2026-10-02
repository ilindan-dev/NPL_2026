// Задача 2.2 (F#): Lowest Common Ancestor of a Binary Tree (LeetCode 236).
// Найти наименьшего общего предка двух узлов в бинарном дереве.
//
// Дерево задаётся алгебраическим типом (discriminated union),
// поиск - рекурсивный спуск в левое и правое поддерево.
//
// Запуск: dotnet fsi lca.fsx [p q]

/// Бинарное дерево: либо пусто, либо узел со значением и двумя поддеревьями.
type Tree =
    | Empty
    | Node of value: int * left: Tree * right: Tree

/// Построить дерево из массива "по уровням", как в LeetCode: [3,5,1,6,2,0,8,null,null,7,4].
/// Позиция i имеет детей 2i+1 и 2i+2 (null - нет узла).
let fromLevelOrder (items: int option list) : Tree =
    let arr = List.toArray items
    let rec build i =
        if i >= arr.Length then Empty
        else
            match arr.[i] with
            | None -> Empty
            | Some v -> Node(v, build (2 * i + 1), build (2 * i + 2))
    build 0

/// LCA: рекурсивно ищем p и q в поддеревьях.
///  - пустое дерево - ничего не нашли;
///  - текущий узел равен p или q - он и есть ответ для этого поддерева;
///  - если нашли в ОБОИХ поддеревьях - текущий узел и есть общий предок;
///  - иначе ответ "поднимается" из того поддерева, где что-то нашлось.
let rec lca (tree: Tree) (p: int) (q: int) : int option =
    match tree with
    | Empty -> None
    | Node(v, _, _) when v = p || v = q -> Some v
    | Node(v, left, right) ->
        match lca left p q, lca right p q with
        | Some _, Some _ -> Some v
        | Some x, None
        | None, Some x -> Some x
        | None, None -> None

/// Проверка, есть ли значение в дереве.
let rec contains (tree: Tree) (x: int) =
    match tree with
    | Empty -> false
    | Node(v, l, r) -> v = x || contains l x || contains r x

/// Печать дерева "лёжа на боку": правое поддерево сверху, левое снизу.
let rec printTree (tree: Tree) (indent: string) =
    match tree with
    | Empty -> ()
    | Node(v, l, r) ->
        printTree r (indent + "      ")
        printfn "%s── %d" indent v
        printTree l (indent + "      ")

// --------------------------------------------------------------------------

// Пример 1 из LeetCode
let tree =
    fromLevelOrder [ Some 3; Some 5; Some 1; Some 6; Some 2; Some 0; Some 8;
                     None; None; Some 7; Some 4 ]

printfn "Дерево (корень слева, правые ветви сверху):\n"
printTree tree ""
printfn ""

let check p q =
    if not (contains tree p && contains tree q) then
        printfn "LCA(%d, %d): одного из узлов нет в дереве" p q
    else
        match lca tree p q with
        | Some a -> printfn "LCA(%d, %d) = %d" p q a
        | None -> printfn "LCA(%d, %d) не найден" p q

// fsi.CommandLineArgs: [| "lca.fsx"; p; q |]
match fsi.CommandLineArgs |> Array.tail with
| [| p; q |] -> check (int p) (int q)
| _ ->
    // Примеры из условия + пара своих
    check 5 1   // 3
    check 5 4   // 5 - узел может быть предком самого себя
    check 6 4   // 5
    check 7 8   // 3
    check 7 4   // 2
