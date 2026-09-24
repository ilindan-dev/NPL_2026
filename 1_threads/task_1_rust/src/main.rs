//! Задача 1.1 (Rust): пул потоков + Future/Promise.
//! Конкурентный чекер доступности сайтов.
//!
//! Главный поток формирует 100 URL и отправляет их в пул из N рабочих потоков.
//! Каждый рабочий берёт адрес из общей очереди, "проверяет" его (фиктивная
//! задержка через sleep) и возвращает результат главному потоку через Promise.
//!
//! Запуск:  cargo run --release -- [число_потоков] [число_url]
//!          по умолчанию 4 потока и 100 адресов.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

// ---------------------------------------------------------------------------
// Пул потоков
// ---------------------------------------------------------------------------

/// Задание для рабочего: замыкание, которому передаётся номер рабочего потока.
type Job = Box<dyn FnOnce(usize) + Send + 'static>;

/// "Обещание" результата (Promise/Future). Главный поток получает его сразу
/// при постановке задачи и позже блокируется на `wait()`, пока результат
/// не будет готов.
struct Promise<T> {
    rx: Receiver<T>,
}

impl<T> Promise<T> {
    fn wait(self) -> T {
        self.rx.recv().expect("рабочий поток завершился, не вернув результат")
    }
}

struct Worker {
    id: usize,
    handle: Option<JoinHandle<()>>,
}

impl Worker {
    /// Рабочий в цикле забирает задания из общей очереди.
    /// Очередь - один `Receiver`, разделённый между потоками через `Arc<Mutex<..>>`.
    fn new(id: usize, queue: Arc<Mutex<Receiver<Job>>>) -> Worker {
        let handle = thread::spawn(move || loop {
            // Мьютекс держим только на время извлечения задания,
            // сама работа выполняется уже без блокировки.
            let job = queue.lock().unwrap().recv();
            match job {
                Ok(job) => job(id),
                Err(_) => break, // канал закрыт - заданий больше не будет
            }
        });
        Worker { id, handle: Some(handle) }
    }
}

struct ThreadPool {
    workers: Vec<Worker>,
    sender: Option<Sender<Job>>,
}

impl ThreadPool {
    fn new(size: usize) -> ThreadPool {
        assert!(size > 0, "размер пула должен быть больше нуля");
        let (sender, receiver) = mpsc::channel::<Job>();
        let queue = Arc::new(Mutex::new(receiver));
        let workers = (1..=size)
            .map(|id| Worker::new(id, Arc::clone(&queue)))
            .collect();
        ThreadPool { workers, sender: Some(sender) }
    }

    /// Поставить задачу в очередь. Сразу возвращает Promise с будущим результатом.
    fn submit<F, T>(&self, f: F) -> Promise<T>
    where
        F: FnOnce(usize) -> T + Send + 'static,
        T: Send + 'static,
    {
        let (tx, rx) = mpsc::channel();
        let job: Job = Box::new(move |worker_id| {
            let _ = tx.send(f(worker_id)); // "выполнить обещание"
        });
        self.sender.as_ref().unwrap().send(job).unwrap();
        Promise { rx }
    }
}

impl Drop for ThreadPool {
    /// Корректное завершение: закрываем очередь и дожидаемся всех рабочих.
    fn drop(&mut self) {
        drop(self.sender.take());
        for w in &mut self.workers {
            if let Some(h) = w.handle.take() {
                h.join().unwrap();
                println!("  рабочий #{} остановлен", w.id);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Фиктивная проверка сайта
// ---------------------------------------------------------------------------

const TIMEOUT_MS: u64 = 280;

enum Status {
    Up(u16),
    Down(u16),
    Timeout,
}

struct CheckResult {
    url: String,
    worker: usize,
    status: Status,
    latency_ms: u64,
}

/// Детерминированное "случайное" число из строки (чтобы обойтись без крейта rand).
fn pseudo_random(s: &str) -> u64 {
    let mut h = DefaultHasher::new();
    s.hash(&mut h);
    h.finish()
}

/// Имитация HTTP-запроса: спим от 30 до 330 мс; всё, что дольше TIMEOUT_MS, - таймаут.
fn check_url(url: String, worker: usize) -> CheckResult {
    let r = pseudo_random(&url);
    let delay = 30 + r % 300;

    let (status, latency_ms) = if delay > TIMEOUT_MS {
        thread::sleep(Duration::from_millis(TIMEOUT_MS));
        (Status::Timeout, TIMEOUT_MS)
    } else {
        thread::sleep(Duration::from_millis(delay));
        let status = if (r >> 16) % 8 == 0 { Status::Down(503) } else { Status::Up(200) };
        (status, delay)
    };

    CheckResult { url, worker, status, latency_ms }
}

// ---------------------------------------------------------------------------
// Главный поток
// ---------------------------------------------------------------------------

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let n_workers: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(4);
    let n_urls: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(100);

    let domains = ["example.com", "test.org", "demo.net", "site.io", "web.ru"];
    let urls: Vec<String> = (1..=n_urls)
        .map(|i| format!("https://srv{:03}.{}", i, domains[i % domains.len()]))
        .collect();

    println!("Проверка {} адресов пулом из {} потоков\n", n_urls, n_workers);

    let started = Instant::now();
    let pool = ThreadPool::new(n_workers);

    // 1) Раздаём все задачи — это мгновенно, получаем список обещаний.
    let promises: Vec<Promise<CheckResult>> = urls
        .into_iter()
        .map(|url| pool.submit(move |worker| check_url(url, worker)))
        .collect();

    // 2) Собираем результаты в главном потоке (ждём каждое обещание).
    let mut results = Vec::with_capacity(n_urls);
    for (i, p) in promises.into_iter().enumerate() {
        let r = p.wait();
        let status = match r.status {
            Status::Up(c) => format!("UP      {}", c),
            Status::Down(c) => format!("DOWN    {}", c),
            Status::Timeout => "TIMEOUT    ".to_string(),
        };
        println!(
            "[{:>3}/{}] рабочий #{}  {:<28} {}  {:>3} мс",
            i + 1, n_urls, r.worker, r.url, status, r.latency_ms
        );
        results.push(r);
    }

    let elapsed = started.elapsed();

    // 3) Останавливаем пул (Drop дожидается завершения всех потоков).
    println!("\nОстановка пула:");
    drop(pool);

    // 4) Итоговая статистика.
    let up = results.iter().filter(|r| matches!(r.status, Status::Up(_))).count();
    let down = results.iter().filter(|r| matches!(r.status, Status::Down(_))).count();
    let timeout = results.iter().filter(|r| matches!(r.status, Status::Timeout)).count();
    let sequential_ms: u64 = results.iter().map(|r| r.latency_ms).sum();

    println!("\n===== ИТОГ =====");
    println!("Доступны: {}   Недоступны: {}   Таймаут: {}", up, down, timeout);
    for w in 1..=n_workers {
        let n = results.iter().filter(|r| r.worker == w).count();
        println!("  рабочий #{} обработал {} адресов", w, n);
    }
    println!("Время работы пула:            {:>6} мс", elapsed.as_millis());
    println!("Если бы проверяли по очереди: {:>6} мс", sequential_ms);
    println!(
        "Ускорение: x{:.2}",
        sequential_ms as f64 / elapsed.as_millis().max(1) as f64
    );
}
