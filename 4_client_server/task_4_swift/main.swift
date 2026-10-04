// Задача 4.4 (Swift): удалённый мониторинг состояния системы.
//
// Клиент отправляет запрос на сервер, сервер собирает РЕАЛЬНУЮ статистику
// (загрузка CPU, память, load average, uptime - из /proc) и возвращает
// отформатированный отчёт.
//
// Network.framework есть только на платформах Apple, а программа работает в Linux-контейнере,
// поэтому сеть сделана на POSIX-сокетах (socket/bind/listen/accept) - это тот же
// системный API, поверх которого построен и Network.framework.
//
// Протокол - текстовый: клиент шлёт команду строкой, сервер отвечает строками,
// последняя строка ответа - END.
//   ALL | CPU | MEM | LOAD | UPTIME | QUIT
//
// Запуск:  monitor server [порт]
//          monitor client [хост] [команда | watch]

#if canImport(Glibc)
import Glibc
#endif
import Foundation

let defaultPort: UInt16 = 5004

func logMsg(_ msg: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    print("[\(f.string(from: Date()))] \(msg)")
    fflush(stdout)
}

func fail(_ msg: String) -> Never {
    print("Ошибка: \(msg)")
    exit(1)
}

// ---------------------------------------------------------------------------
// Сбор статистики (Linux /proc)
// ---------------------------------------------------------------------------

func readFile(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

/// Суммарные "тики" процессора из первой строки /proc/stat: (простой, всего).
func cpuTicks() -> (idle: UInt64, total: UInt64)? {
    guard let line = readFile("/proc/stat").split(separator: "\n").first(where: { $0.hasPrefix("cpu ") })
    else { return nil }
    let nums = line.split(separator: " ").dropFirst().compactMap { UInt64($0) }
    guard nums.count >= 5 else { return nil }
    return (nums[3] + nums[4], nums.reduce(0, +))     // idle + iowait
}

/// Загрузка CPU в процентах: два замера с интервалом 0.5 с.
func cpuUsage() -> Double {
    guard let a = cpuTicks() else { return -1 }
    usleep(500_000)
    guard let b = cpuTicks() else { return -1 }
    let total = Double(b.total - a.total)
    let idle = Double(b.idle - a.idle)
    return total > 0 ? (1 - idle / total) * 100 : 0
}

/// (всего, доступно) в килобайтах из /proc/meminfo
func memInfo() -> (total: Double, available: Double) {
    var values = [String: Double]()
    for line in readFile("/proc/meminfo").split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let number = parts[1].split(separator: " ").first.flatMap({ Double($0) })
        else { continue }
        values[String(parts[0])] = number
    }
    return (values["MemTotal"] ?? 0, values["MemAvailable"] ?? 0)
}

func bar(_ percent: Double, width: Int = 20) -> String {
    let filled = max(0, min(width, Int((percent / 100 * Double(width)).rounded())))
    return "[" + String(repeating: "#", count: filled) + String(repeating: ".", count: width - filled) + "]"
}

func fmt(_ x: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", x) }

func cpuReport() -> String {
    let usage = cpuUsage()
    let cores = ProcessInfo.processInfo.activeProcessorCount
    return "  CPU:     \(bar(usage)) \(fmt(usage))%  (ядер: \(cores))\n"
}

func memReport() -> String {
    let m = memInfo()
    let used = m.total - m.available
    let percent = m.total > 0 ? used / m.total * 100 : 0
    let gb = { (kb: Double) in fmt(kb / 1024 / 1024, 2) }
    return "  Память:  \(bar(percent)) \(fmt(percent))%  (занято \(gb(used)) из \(gb(m.total)) ГБ)\n"
}

func loadReport() -> String {
    let parts = readFile("/proc/loadavg").split(separator: " ").prefix(3)
    return "  Load avg (1/5/15 мин): \(parts.joined(separator: " "))\n"
}

func uptimeReport() -> String {
    let secs = Int(Double(readFile("/proc/uptime").split(separator: " ").first ?? "0") ?? 0)
    return "  Uptime:  \(secs / 86400) д \(secs % 86400 / 3600) ч \(secs % 3600 / 60) мин\n"
}

func report(_ cmd: String) -> String {
    let header = "== \(ProcessInfo.processInfo.hostName) | \(Date()) ==\n"
    switch cmd {
    case "CPU": return header + cpuReport()
    case "MEM": return header + memReport()
    case "LOAD": return header + loadReport()
    case "UPTIME": return header + uptimeReport()
    case "ALL": return header + cpuReport() + memReport() + loadReport() + uptimeReport()
    default: return "ERROR неизвестная команда '\(cmd)'. Доступны: ALL, CPU, MEM, LOAD, UPTIME, QUIT\n"
    }
}

// ---------------------------------------------------------------------------
// Работа с сокетом
// ---------------------------------------------------------------------------

func sendAll(_ fd: Int32, _ text: String) {
    let bytes = Array(text.utf8)
    var offset = 0
    while offset < bytes.count {
        let n = bytes.withUnsafeBytes { buf in
            write(fd, buf.baseAddress! + offset, bytes.count - offset)
        }
        if n <= 0 { return }        // клиент отключился
        offset += n
    }
}

/// Буферизованное чтение строк из сокета (до '\n').
final class LineReader {
    private let fd: Int32
    private var buffer = [UInt8]()
    init(_ fd: Int32) { self.fd = fd }

    func next() -> String? {
        while true {
            if let i = buffer.firstIndex(of: 10) {               // '\n'
                var line = Array(buffer[..<i])
                buffer.removeFirst(i + 1)
                if line.last == 13 { line.removeLast() }         // '\r' от telnet/nc
                return String(decoding: line, as: UTF8.self)
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, 4096) }
            if n <= 0 { return nil }                              // соединение закрыто
            buffer.append(contentsOf: chunk[0..<n])
        }
    }
}

func makeAddress(_ ip: String, _ port: UInt16) -> sockaddr_in {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian                 // порядок байт сети - big-endian
    guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { fail("неверный IPv4-адрес \(ip)") }
    return addr
}

// ---------------------------------------------------------------------------
// Сервер
// ---------------------------------------------------------------------------

func handle(_ fd: Int32, _ name: String) {
    logMsg("\(name) подключился")
    let reader = LineReader(fd)
    sendAll(fd, "Сервер мониторинга \(ProcessInfo.processInfo.hostName). Команды: ALL, CPU, MEM, LOAD, UPTIME, QUIT\nEND\n")
    while let line = reader.next() {
        let cmd = line.trimmingCharacters(in: .whitespaces).uppercased()
        if cmd.isEmpty { continue }
        if cmd == "QUIT" { sendAll(fd, "BYE\nEND\n"); break }
        logMsg("\(name) запросил \(cmd)")
        sendAll(fd, report(cmd) + "END\n")
    }
    close(fd)
    logMsg("\(name) отключился")
}

func runServer(port: UInt16) {
    signal(SIGPIPE, SIG_IGN)                         // запись в закрытый сокет - не убивать процесс
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    guard fd >= 0 else { fail("socket()") }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var addr = makeAddress("0.0.0.0", port)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard rc == 0 else { fail("bind() - порт \(port) занят?") }
    guard listen(fd, 16) == 0 else { fail("listen()") }
    logMsg("Сервер мониторинга запущен на порту \(port)")

    var counter = 0
    while true {
        let client = accept(fd, nil, nil)            // ждём подключения
        if client < 0 { continue }
        counter += 1
        let name = "клиент#\(counter)"
        Thread { handle(client, name) }.start()      // по потоку на клиента
    }
}

// ---------------------------------------------------------------------------
// Клиент
// ---------------------------------------------------------------------------

func runClient(host: String, port: UInt16, command: String?) {
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    var addr = makeAddress(host == "localhost" ? "127.0.0.1" : host, port)
    let rc = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard rc == 0 else { fail("не удалось подключиться к \(host):\(port) - сервер запущен?") }

    let reader = LineReader(fd)
    /// Печатает ответ до строки END. false - соединение закрыто.
    func printResponse() -> Bool {
        while let line = reader.next() {
            if line == "END" { return true }
            print(line)
        }
        return false
    }

    _ = printResponse()                                       // приветствие

    switch command?.uppercased() {
    case .some("WATCH"):                                      // обновление каждые 2 секунды
        while true {
            sendAll(fd, "ALL\n")
            print("\u{1B}[2J\u{1B}[H", terminator: "")        // очистить экран
            if !printResponse() { break }
            print("\n(обновление каждые 2 с, Ctrl+C - выход)")
            fflush(stdout)
            sleep(2)
        }
    case .some(let cmd):                                      // одна команда
        sendAll(fd, cmd + "\n")
        _ = printResponse()
        sendAll(fd, "QUIT\n")
    case .none:                                               // интерактивный режим
        while true {
            print("> ", terminator: "")
            fflush(stdout)
            guard let line = readLine() else { break }
            sendAll(fd, line + "\n")
            if !printResponse() { break }
            if line.uppercased() == "QUIT" { break }
        }
    }
    close(fd)
}

// ---------------------------------------------------------------------------

// Ctrl+C и docker stop: завершаемся явно. В контейнере программа может оказаться процессом
// с PID 1, а такой процесс ядро не завершает по сигналу, если для него нет обработчика.
func onStopSignal(_ sig: Int32) {
    _exit(0)          // в обработчике сигнала можно вызывать только простые системные функции
}
signal(SIGINT, onStopSignal)
signal(SIGTERM, onStopSignal)

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "server":
    runServer(port: args.count > 2 ? UInt16(args[2]) ?? defaultPort : defaultPort)
case "client":
    runClient(host: args.count > 2 ? args[2] : "localhost",
              port: defaultPort,
              command: args.count > 3 ? args[3] : nil)
default:
    print("Использование: monitor server [порт] | monitor client [хост] [ALL|CPU|MEM|LOAD|UPTIME|watch]")
}
