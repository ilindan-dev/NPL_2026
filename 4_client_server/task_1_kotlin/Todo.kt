// Задача 4.1 (Kotlin): синхронизация общего списка задач (To-Do) в реальном времени.
//
// Сервер хранит список задач в памяти. Клиенты подключаются по TCP и шлют команды:
//   ADD <текст>    — добавить задачу
//   REMOVE <id>    — удалить задачу
//   LIST           — получить список
//   QUIT           — отключиться
// При ЛЮБОМ изменении сервер рассылает обновлённый список ВСЕМ подключённым клиентам.
//
// Запуск:  java -jar todo.jar server [порт]
//          java -jar todo.jar client [хост] [порт]
// Только стандартная библиотека (java.net, kotlin.concurrent).

import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.PrintWriter
import java.net.ServerSocket
import java.net.Socket
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread
import kotlin.system.exitProcess

const val DEFAULT_PORT = 5001

data class Task(val id: Int, val text: String)

fun log(msg: String) =
    println("[${LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"))}] $msg")

// ---------------------------------------------------------------------------
// Сервер
// ---------------------------------------------------------------------------

class TodoServer(private val port: Int) {
    private val tasks = mutableListOf<Task>()       // общее состояние
    private var nextId = 1
    private val lock = Any()                        // защищает tasks и nextId
    private val clients = CopyOnWriteArrayList<Client>()

    /** Одно подключение. send синхронизирован, чтобы сообщения разных потоков не перемешались. */
    class Client(val socket: Socket, val name: String) {
        private val out = PrintWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8), true)
        fun send(msg: String) = synchronized(out) { out.println(msg) }
    }

    fun start() {
        val server = ServerSocket(port)
        log("Сервер To-Do запущен на порту $port")
        var counter = 0
        while (true) {
            val socket = server.accept()            // ждём нового клиента
            val client = Client(socket, "клиент#${++counter}")
            clients += client
            thread(name = client.name) { handle(client) }   // по потоку на клиента
        }
    }

    private fun handle(c: Client) {
        log("${c.name} подключился, клиентов: ${clients.size}")
        c.send("Привет, ${c.name}! Команды: ADD <текст> | REMOVE <id> | LIST | QUIT")
        c.send(render())
        try {
            val input = BufferedReader(InputStreamReader(c.socket.getInputStream(), Charsets.UTF_8))
            while (true) {
                val line = input.readLine() ?: break        // null — клиент закрыл соединение
                val parts = line.trim().split(" ", limit = 2)
                val cmd = parts[0].uppercase()
                val arg = parts.getOrElse(1) { "" }.trim()

                when (cmd) {
                    "ADD" ->
                        if (arg.isEmpty()) c.send("ERROR пустая задача")
                        else {
                            val task = synchronized(lock) { Task(nextId++, arg).also { tasks += it } }
                            broadcast("${c.name} добавил #${task.id} «${task.text}»")
                        }
                    "REMOVE" -> {
                        val id = arg.toIntOrNull()
                        val removed = id != null && synchronized(lock) { tasks.removeIf { it.id == id } }
                        if (removed) broadcast("${c.name} удалил #$id")
                        else c.send("ERROR нет задачи с id '$arg'")
                    }
                    "LIST" -> c.send(render())
                    "QUIT" -> break
                    "" -> {}
                    else -> c.send("ERROR неизвестная команда '$cmd'")
                }
            }
        } catch (e: IOException) {
            // клиент оборвал соединение — просто отключаем его
        } finally {
            clients -= c
            c.socket.close()
            log("${c.name} отключился, клиентов: ${clients.size}")
        }
    }

    /** Широковещательная рассылка: событие + актуальный список — всем клиентам. */
    private fun broadcast(event: String) {
        log(event)
        val msg = ">>> $event\n" + render()
        clients.forEach { it.send(msg) }
    }

    /** Снимок списка под блокировкой, чтобы не прочитать его в момент изменения. */
    private fun render(): String = synchronized(lock) {
        buildString {
            append("---- Список задач (${tasks.size}) ----")
            if (tasks.isEmpty()) append("\n   (пусто)")
            tasks.forEach { append("\n   #${it.id}  ${it.text}") }
            append("\n------------------------------")
        }
    }
}

// ---------------------------------------------------------------------------
// Клиент
// ---------------------------------------------------------------------------

fun runClient(host: String, port: Int) {
    val socket = try {
        Socket(host, port)
    } catch (e: IOException) {
        println("Не удалось подключиться к $host:$port — сервер запущен?")
        exitProcess(1)
    }
    val out = PrintWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8), true)
    val input = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))

    // Отдельный поток печатает всё, что присылает сервер (в том числе чужие изменения)
    thread(isDaemon = true) {
        try {
            while (true) println(input.readLine() ?: break)
        } catch (e: IOException) {
        }
        println("Соединение закрыто")
        exitProcess(0)
    }

    // Главный поток читает команды с клавиатуры и отправляет на сервер
    val console = BufferedReader(InputStreamReader(System.`in`, Charsets.UTF_8))
    while (true) {
        val line = console.readLine() ?: break
        out.println(line)
        if (line.trim().equals("QUIT", ignoreCase = true)) break
    }
    socket.close()
}

fun main(args: Array<String>) {
    when (args.getOrNull(0)) {
        "server" -> TodoServer(args.getOrNull(1)?.toIntOrNull() ?: DEFAULT_PORT).start()
        "client" -> runClient(args.getOrNull(1) ?: "localhost", args.getOrNull(2)?.toIntOrNull() ?: DEFAULT_PORT)
        else -> println("Использование: todo server [порт] | todo client [хост] [порт]")
    }
}
