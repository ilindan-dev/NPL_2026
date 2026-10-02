--  Задача 1.4 (Ada): барьерная синхронизация.
--  Клеточный автомат "Жизнь" Конвея.
--
--  Поле разбито на горизонтальные секторы, каждый сектор считает своя задача (task).
--  Такт состоит из двух фаз, разделённых барьером (Ada.Synchronous_Barriers):
--    1) все задачи считают следующее поколение для своих строк;
--       БАРЬЕР — ждём, пока досчитают все (соседям нужны строки друг друга);
--    2) одна задача (её выбирает барьер, Notified = True) меняет поколения местами
--       и перерисовывает консоль;
--       БАРЬЕР — ждём отрисовки, затем новый такт.
--
--  Запуск: ./life [число_поколений]

with Ada.Text_IO;              use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Synchronous_Barriers; use Ada.Synchronous_Barriers;

procedure Life is

   Rows    : constant := 24;
   Cols    : constant := 60;
   Workers : constant := 4;

   Generations : Positive := 150;

   type Grid is array (0 .. Rows - 1, 0 .. Cols - 1) of Boolean;
   Grids : array (0 .. 1) of Grid := (others => (others => (others => False)));
   Cur   : Natural := 0;   --  индекс текущего поколения, меняется только между барьерами
   pragma Volatile (Cur);

   --  Барьер срабатывает, когда до него дошли все Workers задач.
   Bar : Synchronous_Barrier (Release_Threshold => Workers);

   --  Символ живой клетки для каждого сектора — так на экране видно разбиение
   Marks : constant String (1 .. Workers) := "#@O%";

   function Sector_Of (R : Natural) return Natural is (R * Workers / Rows);

   --  Число живых соседей; поле "замкнуто" в тор (края склеены).
   function Neighbours (G : Grid; R, C : Natural) return Natural is
      N : Natural := 0;
   begin
      for DR in -1 .. 1 loop
         for DC in -1 .. 1 loop
            if not (DR = 0 and DC = 0)
              and then G ((R + DR + Rows) mod Rows, (C + DC + Cols) mod Cols)
            then
               N := N + 1;
            end if;
         end loop;
      end loop;
      return N;
   end Neighbours;

   procedure Draw (Gen : Natural) is
      Alive : Natural := 0;
      Line  : String (1 .. Cols);
   begin
      Put (ASCII.ESC & "[H");   --  курсор в левый верхний угол
      for R in 0 .. Rows - 1 loop
         for C in 0 .. Cols - 1 loop
            if Grids (Cur) (R, C) then
               Line (C + 1) := Marks (Sector_Of (R) + 1);
               Alive := Alive + 1;
            else
               Line (C + 1) := '.';
            end if;
         end loop;
         Put_Line (Line & "  | задача" & Natural'Image (Sector_Of (R) + 1));
      end loop;
      Put_Line ("Поколение" & Natural'Image (Gen) & " из" & Positive'Image (Generations)
                & ", живых клеток:" & Natural'Image (Alive)
                & ", задач:" & Natural'Image (Workers) & "      ");
   end Draw;

   procedure Seed is
      --  Простой линейный конгруэнтный генератор — детерминированное начальное поле
      X : Natural := 2026;
   begin
      for R in 0 .. Rows - 1 loop
         for C in 0 .. Cols - 1 loop
            X := (X * 1103 + 12345) mod 65536;
            Grids (0) (R, C) := X mod 100 < 30;
         end loop;
      end loop;
   end Seed;

   task type Worker (Id : Natural);

   task body Worker is
      First    : constant Natural := Id * Rows / Workers;
      Last     : constant Natural := (Id + 1) * Rows / Workers - 1;
      Notified : Boolean;
   begin
      for Gen in 1 .. Generations loop
         --  Фаза 1: считаем свои строки нового поколения
         for R in First .. Last loop
            for C in 0 .. Cols - 1 loop
               declare
                  N : constant Natural := Neighbours (Grids (Cur), R, C);
               begin
                  Grids (1 - Cur) (R, C) :=
                    (if Grids (Cur) (R, C) then N = 2 or N = 3 else N = 3);
               end;
            end loop;
         end loop;

         Wait_For_Release (Bar, Notified);   --  БАРЬЕР 1: все досчитали

         --  Фаза 2: ровно одна задача (Notified = True) переключает поколение и рисует
         if Notified then
            Cur := 1 - Cur;
            Draw (Gen);
            delay 0.08;
         end if;

         Wait_For_Release (Bar, Notified);   --  БАРЬЕР 2: отрисовка закончена
      end loop;
   end Worker;

   type Worker_Access is access Worker;
   W : Worker_Access;

begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Generations := Positive'Value (Ada.Command_Line.Argument (1));
   end if;

   Seed;
   Put (ASCII.ESC & "[2J");      --  очистить экран
   Draw (0);

   --  Задачи стартуют сразу при создании; процедура Life не завершится,
   --  пока не завершатся все её задачи.
   for I in 0 .. Workers - 1 loop
      W := new Worker (I);
   end loop;
end Life;
