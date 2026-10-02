## Задача 1.3 (Nim): Read-Write Lock (Читатели-Писатели).
## Многопоточный in-memory кэш конфигурации.
##
## 10 потоков-читателей постоянно читают настройки из общего словаря,
## 2 потока-писателя раз в пару секунд обновляют их.
## Читатели могут читать ОДНОВРЕМЕННО, писатель получает ЭКСКЛЮЗИВНЫЙ доступ.
##
## В стандартной библиотеке Nim нет готового RWMutex, поэтому он собран
## из обычного мьютекса (Lock) и двух условных переменных (Cond).
##
## Запуск:  ./rwcache            - с блокировкой
##          ./rwcache --nolock   - без блокировки (видно, к чему это приводит)

import std/[locks, tables, os, times, strutils]

# ---------------------------------------------------------------------------
# RW-lock
# ---------------------------------------------------------------------------

type
  RwLock = object
    guard: Lock          # защищает поля ниже
    canRead: Cond        # сигнал "читателям можно заходить"
    canWrite: Cond       # сигнал "писателю можно заходить"
    readers: int         # сколько читателей сейчас внутри
    writer: bool         # внутри ли писатель
    waitingWriters: int  # сколько писателей ждёт (приоритет писателям)
    maxReaders: int      # статистика: максимум одновременных читателей

proc init(rw: var RwLock) =
  initLock(rw.guard)
  initCond(rw.canRead)
  initCond(rw.canWrite)

proc acquireRead(rw: var RwLock) =
  acquire(rw.guard)
  # ждём, пока нет писателя и никто из писателей не стоит в очереди
  while rw.writer or rw.waitingWriters > 0:
    wait(rw.canRead, rw.guard)
  inc rw.readers
  if rw.readers > rw.maxReaders: rw.maxReaders = rw.readers
  release(rw.guard)

proc releaseRead(rw: var RwLock) =
  acquire(rw.guard)
  dec rw.readers
  if rw.readers == 0:
    signal(rw.canWrite)      # последний читатель вышел - будим писателя
  release(rw.guard)

proc acquireWrite(rw: var RwLock) =
  acquire(rw.guard)
  inc rw.waitingWriters
  while rw.writer or rw.readers > 0:
    wait(rw.canWrite, rw.guard)
  dec rw.waitingWriters
  rw.writer = true
  release(rw.guard)

proc releaseWrite(rw: var RwLock) =
  acquire(rw.guard)
  rw.writer = false
  broadcast(rw.canRead)      # будим всех читателей
  signal(rw.canWrite)        # и одного писателя, если он ждёт
  release(rw.guard)

# ---------------------------------------------------------------------------
# Общие данные
# ---------------------------------------------------------------------------

const
  NumReaders = 10
  NumWriters = 2
  RunSeconds = 8.0

var
  rw: RwLock
  config: Table[string, int]     # сам "кэш конфигурации"
  useLock = true
  deadline: float
  readCount: array[NumReaders, int]
  badReads: array[NumReaders, int]
  writeCount: array[NumWriters, int]

# Все настройки выводятся из номера версии - так читатель может проверить,
# что видит СОГЛАСОВАННЫЙ снимок, а не смесь старых и новых значений.
proc fillConfig(v: int) {.gcsafe.} =
  {.cast(gcsafe).}:
    config["cache_ttl"] = v * 10
    sleep(100)                     # "долгое" обновление: между полями снимок неполный
    config["max_connections"] = v * 100
    config["timeout_ms"] = v * 1000
    config["version"] = v

proc snapshot(): tuple[v, ttl, conns, timeout: int] {.gcsafe.} =
  {.cast(gcsafe).}:
    result = (config["version"], config["cache_ttl"],
              config["max_connections"], config["timeout_ms"])

# ---------------------------------------------------------------------------
# Потоки
# ---------------------------------------------------------------------------

proc reader(id: int) {.thread.} =
  var n = 0
  while epochTime() < deadline:
    if useLock: rw.acquireRead()
    let s = snapshot()
    sleep(5)                       # имитация работы с настройками
    if useLock: rw.releaseRead()

    let consistent = s.ttl == s.v * 10 and s.conns == s.v * 100 and
                     s.timeout == s.v * 1000
    if not consistent:
      inc badReads[id]
      echo "  [читатель ", id, "] !!! НЕСОГЛАСОВАННЫЕ данные: ", s
    elif n mod 40 == 0:
      echo "  [читатель ", id, "] версия ", s.v, ": cache_ttl=", s.ttl,
           " max_connections=", s.conns, " timeout_ms=", s.timeout
    inc n
    sleep(20)
  readCount[id] = n

proc writer(id: int) {.thread.} =
  var n = 0
  sleep(800 + id * 1000)
  while epochTime() < deadline:
    if useLock: rw.acquireWrite()
    let v = snapshot().v + 1
    echo "[писатель ", id, "] захватил запись, обновляю конфиг до версии ", v, " ..."
    fillConfig(v)
    echo "[писатель ", id, "] версия ", v, " записана"
    if useLock: rw.releaseWrite()
    inc n
    sleep(2000)
  writeCount[id] = n

# ---------------------------------------------------------------------------

proc main() =
  useLock = not (paramCount() >= 1 and paramStr(1) == "--nolock")
  rw.init()
  fillConfig(1)

  echo "Читателей: ", NumReaders, ", писателей: ", NumWriters,
       ", время работы: ", RunSeconds, " с, блокировка: ",
       (if useLock: "RW-lock" else: "НЕТ")
  echo ""

  deadline = epochTime() + RunSeconds
  var readers: array[NumReaders, Thread[int]]
  var writers: array[NumWriters, Thread[int]]
  for i in 0 ..< NumReaders: createThread(readers[i], reader, i)
  for i in 0 ..< NumWriters: createThread(writers[i], writer, i)
  joinThreads(readers)
  joinThreads(writers)

  var totalReads, totalBad: int
  for i in 0 ..< NumReaders:
    totalReads += readCount[i]
    totalBad += badReads[i]
  echo ""
  echo "===== ИТОГ ====="
  echo "Чтений всего:                    ", totalReads
  echo "Записей: писатель 0 - ", writeCount[0], ", писатель 1 - ", writeCount[1]
  echo "Итоговая версия конфига:         ", snapshot().v
  echo "Несогласованных чтений:          ", totalBad
  if useLock:
    echo "Макс. читателей одновременно:    ", rw.maxReaders,
         "  (читатели не мешают друг другу)"

main()
