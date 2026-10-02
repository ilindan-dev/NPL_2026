//> using scala 3.3.4

// Задача 2.3 (Scala): Top K Frequent Elements (LeetCode 347).
// Найти k самых часто встречающихся элементов массива.
//
// Основное решение — цепочка методов коллекций без изменяемого состояния:
//   группировка -> подсчёт -> сортировка по частоте -> первые k.
// Дополнительно — "блочная сортировка" за O(n), как просит follow-up в LeetCode.
//
// Запуск: scala-cli run TopK.scala -- [k] [числа...]

/** Основное решение: O(n log n), только неизменяемые коллекции. */
def topKFrequent(nums: Seq[Int], k: Int): Seq[Int] =
  nums
    .groupMapReduce(identity)(_ => 1)(_ + _) // Map(число -> сколько раз встретилось)
    .toSeq
    .sortBy((num, count) => (-count, num))   // по убыванию частоты, при равенстве — по значению
    .take(k)
    .map(_._1)

/** Вариант за O(n): bucket sort по частоте. buckets(c) — числа, встретившиеся c раз. */
def topKFrequentBuckets(nums: Seq[Int], k: Int): Seq[Int] =
  val freq = nums.groupMapReduce(identity)(_ => 1)(_ + _)
  val buckets = Vector.tabulate(nums.length + 1)(c => freq.collect { case (n, `c`) => n }.toSeq.sorted)
  // идём от самой большой частоты к меньшей, пока не наберём k
  buckets.reverseIterator.flatten.take(k).toSeq

def demo(nums: Seq[Int], k: Int): Unit =
  println(s"nums = ${nums.mkString("[", ",", "]")}, k = $k")

  val freq = nums.groupMapReduce(identity)(_ => 1)(_ + _)
  println("  1) частоты:     " + freq.toSeq.sortBy(-_._2).map((n, c) => s"$n→$c").mkString(", "))
  val sorted = freq.toSeq.sortBy((n, c) => (-c, n))
  println("  2) сортировка:  " + sorted.map(_._1).mkString(", "))

  val a = topKFrequent(nums, k)
  val b = topKFrequentBuckets(nums, k)
  println(s"  3) первые $k:    ${a.mkString("[", ",", "]")}")
  println(s"  bucket sort:    ${b.mkString("[", ",", "]")}  ${if a.toSet == b.toSet then "(совпадает)" else "(РАЗЛИЧАЕТСЯ!)"}")
  println()

@main def topK(args: String*): Unit =
  if args.nonEmpty then
    val k = args.head.toInt
    val nums = args.tail.map(_.toInt).toVector
    demo(nums, k)
  else
    // Примеры из условия LeetCode
    demo(Vector(1, 1, 1, 2, 2, 3), 2)   // [1,2]
    demo(Vector(1), 1)                  // [1]
    // Свой пример побольше
    val rnd = scala.util.Random(42)
    val big = Vector.fill(30)(rnd.nextInt(8) + rnd.nextInt(3))
    demo(big, 3)
