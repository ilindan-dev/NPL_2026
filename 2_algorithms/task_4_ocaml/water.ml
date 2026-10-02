(* Задача 2.4 (OCaml): Container With Most Water (LeetCode 11).
   Дан массив высот вертикальных линий. Найти две линии, которые вместе с осью X
   образуют контейнер с наибольшей площадью воды.

   Решение - "два указателя": начинаем с крайних линий и двигаем к центру
   ту, что НИЖЕ. Один проход, O(n).

   Запуск: ./water [высоты...]      по умолчанию 1 8 6 2 5 4 8 3 7 *)

(* Основной алгоритм. Возвращает (площадь, левый индекс, правый индекс). *)
let max_area ?(trace = false) (h : int array) : int * int * int =
  let l = ref 0 and r = ref (Array.length h - 1) in
  let best = ref 0 and bl = ref 0 and br = ref 0 in
  while !l < !r do
    let width = !r - !l in
    let height = min h.(!l) h.(!r) in
    let area = width * height in
    if trace then
      Printf.printf "  l=%d (h=%d)  r=%d (h=%d)  площадь = %d * %d = %d%s\n"
        !l h.(!l) !r h.(!r) width height area
        (if area > !best then "  <- новый максимум" else "");
    if area > !best then begin
      best := area; bl := !l; br := !r
    end;
    (* Двигаем меньшую стенку: двигать большую бессмысленно -
       ширина уменьшится, а высота всё равно ограничена меньшей. *)
    if h.(!l) < h.(!r) then incr l else decr r
  done;
  (!best, !bl, !br)

(* Полный перебор O(n^2) - для проверки правильности. *)
let brute_force (h : int array) : int =
  let n = Array.length h and best = ref 0 in
  for i = 0 to n - 1 do
    for j = i + 1 to n - 1 do
      best := max !best ((j - i) * min h.(i) h.(j))
    done
  done;
  !best

(* Рисунок: '#' - линии, '~' - вода между выбранными линиями. *)
let draw (h : int array) (bl : int) (br : int) =
  let top = Array.fold_left max 0 h in
  let water = min h.(bl) h.(br) in
  for level = top downto 1 do
    Printf.printf "%3d |" level;
    Array.iteri (fun i x ->
        let c =
          if x >= level then '#'
          else if i > bl && i < br && level <= water then '~'
          else ' '
        in
        Printf.printf " %c" c)
      h;
    print_newline ()
  done;
  Printf.printf "    +%s\n     " (String.make (2 * Array.length h) '-');
  Array.iteri (fun i _ -> Printf.printf "%2d" i) h;
  print_newline ()

let () =
  let heights =
    if Array.length Sys.argv > 1 then
      Array.map int_of_string (Array.sub Sys.argv 1 (Array.length Sys.argv - 1))
    else [| 1; 8; 6; 2; 5; 4; 8; 3; 7 |]
  in
  if Array.length heights < 2 then begin
    print_endline "Нужно хотя бы две линии"; exit 1
  end;
  Printf.printf "height = [%s]\n\nШаги двух указателей:\n"
    (String.concat "," (Array.to_list (Array.map string_of_int heights)));
  let area, bl, br = max_area ~trace:true heights in
  Printf.printf "\nОтвет: %d (линии %d и %d)\n\n" area bl br;
  draw heights bl br;

  (* Самопроверка на случайных массивах *)
  Random.init 2026;
  let ok = ref true in
  for _i = 1 to 1000 do
    let a = Array.init (2 + Random.int 50) (fun _ -> Random.int 100) in
    let fast, _, _ = max_area a in
    if fast <> brute_force a then ok := false
  done;
  Printf.printf "\nПроверка на 1000 случайных массивах против перебора O(n^2): %s\n"
    (if !ok then "все совпали" else "ЕСТЬ РАСХОЖДЕНИЯ")
