/**
 * Задача 1.2 (D): паттерн Map-Reduce.
 * Параллельное применение фильтра к "изображению".
 *
 * Генерируется большой одномерный массив яркостей пикселей (0..255).
 * Массив делится на чанки, каждый чанк обрабатывает свой поток:
 *   MAP    - к каждому пикселю применяется фильтр (гамма-коррекция + контраст),
 *            поток заодно считает частичную сумму своего чанка;
 *   REDUCE - главный поток складывает частичные суммы.
 * Для сравнения то же самое считается в одном потоке.
 *
 * Запуск: ./mapreduce [число_потоков] [число_пикселей]
 */
import core.thread : Thread;
import std.stdio : writeln, writefln;
import std.conv : to;
import std.math : pow, abs;
import std.datetime.stopwatch : StopWatch, AutoStart;

// Данные общие для всех потоков. __gshared - "обычная" глобальная переменная,
// видимая из всех потоков (в D глобальные переменные по умолчанию у каждого потока свои).
__gshared double[] source;    // исходное изображение
__gshared double[] result;    // результат фильтра
__gshared double[] partial;   // частичные суммы: partial[i] пишет только поток i

/// Фильтр для одного пикселя: гамма-коррекция (γ = 2.2) + усиление контраста.
double filter(double p)
{
    double v = 255.0 * pow(p / 255.0, 1.0 / 2.2);   // осветление тёмных участков
    v = (v - 128.0) * 1.2 + 128.0;                   // контраст +20%
    if (v < 0) v = 0;
    if (v > 255) v = 255;
    return v;
}

/// MAP-шаг для одного чанка [from, to): фильтруем и считаем сумму.
void mapChunk(size_t id, size_t lo, size_t hi)
{
    double sum = 0;
    foreach (i; lo .. hi)
    {
        result[i] = filter(source[i]);
        sum += result[i];
    }
    partial[id] = sum;
}

/// Возвращает делегат для потока. Отдельная функция нужна, чтобы каждый
/// делегат захватил СВОИ значения id/lo/hi (а не общую переменную цикла).
void delegate() makeTask(size_t id, size_t lo, size_t hi)
{
    return () { mapChunk(id, lo, hi); };
}

void main(string[] args)
{
    immutable size_t nThreads = args.length > 1 ? args[1].to!size_t : 4;
    immutable size_t nPixels  = args.length > 2 ? args[2].to!size_t : 20_000_000;

    // --- Генерация "изображения": градиент + шум (простой LCG, без внешних библиотек)
    source = new double[nPixels];
    result = new double[nPixels];
    uint seed = 12345;
    foreach (i; 0 .. nPixels)
    {
        seed = seed * 1_103_515_245 + 12_345;
        double gradient = 255.0 * (i % 4096) / 4096.0;
        double noise = ((seed >> 16) % 41) - 20.0;
        double v = gradient + noise;
        source[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
    }

    writefln("Изображение: %s пикселей, потоков: %s", nPixels, nThreads);
    writefln("Первые пиксели ДО фильтра:    %(%6.1f %)", source[0 .. 6]);

    // --- Последовательный вариант (эталон)
    auto sw = StopWatch(AutoStart.yes);
    double seqSum = 0;
    foreach (i, p; source)
    {
        result[i] = filter(p);
        seqSum += result[i];
    }
    immutable seqMs = sw.peek.total!"msecs";

    // --- Параллельный Map-Reduce
    partial = new double[nThreads];
    sw.reset();

    // MAP: делим массив на чанки и запускаем по потоку на чанк
    Thread[] threads;
    immutable chunk = (nPixels + nThreads - 1) / nThreads;
    foreach (id; 0 .. nThreads)
    {
        size_t lo = id * chunk;
        size_t hi = lo + chunk > nPixels ? nPixels : lo + chunk;
        writefln("  поток %s: пиксели [%9s .. %9s)", id, lo, hi);
        threads ~= new Thread(makeTask(id, lo, hi)).start();
    }
    foreach (t; threads) t.join();   // ждём окончания всех MAP-задач

    // REDUCE: главный поток складывает частичные суммы
    double parSum = 0;
    foreach (s; partial) parSum += s;
    immutable parMs = sw.peek.total!"msecs";

    writefln("Первые пиксели ПОСЛЕ фильтра: %(%6.1f %)", result[0 .. 6]);
    writeln();
    writeln("Частичные суммы (Map):");
    foreach (id, s; partial) writefln("  поток %s: %.0f", id, s);
    writeln();
    writefln("Reduce: сумма яркостей = %.0f, средняя яркость %.2f -> %.2f",
             parSum, avg(source), parSum / nPixels);
    writefln("Проверка с последовательным расчётом: %s",
             abs(parSum - seqSum) / seqSum < 1e-9 ? "совпадает" : "НЕ совпадает!");
    writeln();
    writefln("Один поток:   %5s мс", seqMs);
    writefln("%s потока(ов): %5s мс", nThreads, parMs);
    writefln("Ускорение:    x%.2f", cast(double) seqMs / (parMs > 0 ? parMs : 1));
}

double avg(const double[] a)
{
    double s = 0;
    foreach (x; a) s += x;
    return s / a.length;
}
