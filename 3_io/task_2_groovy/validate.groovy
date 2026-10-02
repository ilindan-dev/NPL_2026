// Задача 3.2 (Groovy): валидатор конфигурационных .ini файлов с записью отчёта.
//
// Читает файл формата
//     [секция]
//     ключ = значение      ; комментарии через ; или #
// проверяет синтаксис, наличие обязательных полей и типы значений по схеме ниже.
// Результат — в консоль, ошибки дописываются в error.log (с датой и временем).
//
// Запуск: groovy validate.groovy <файл.ini> [ещё файлы...]
// Код выхода: 0 — все файлы корректны, 1 — есть ошибки.

import groovy.transform.Field
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

// ---------------------------------------------------------------------------
// Схема: секция -> ключ -> правило
// ---------------------------------------------------------------------------
@Field Map<String, Map<String, Map>> SCHEMA = [
    server  : [
        host     : [type: 'string', required: true],
        port     : [type: 'int', required: true, min: 1, max: 65535],
        debug    : [type: 'bool', required: false],
    ],
    database: [
        url      : [type: 'string', required: true, pattern: ~/^[a-z]+:\/\/\S+$/, hint: 'схема://адрес'],
        user     : [type: 'string', required: true],
        pool_size: [type: 'int', required: false, min: 1, max: 100],
        timeout  : [type: 'float', required: false, min: 0],
    ],
    logging : [
        level    : [type: 'enum', required: true, values: ['DEBUG', 'INFO', 'WARN', 'ERROR']],
        file     : [type: 'string', required: false],
    ],
]

@Field String LOG_FILE = 'error.log'

// ---------------------------------------------------------------------------

/** Проверка значения по правилу. Возвращает текст ошибки или null. */
String checkValue(String v, Map rule) {
    switch (rule.type) {
        case 'int':
            if (!(v ==~ /-?\d+/)) return "ожидалось целое число, получено '$v'"
            long n = v as long
            if (rule.min != null && n < rule.min) return "значение $n меньше минимума ${rule.min}"
            if (rule.max != null && n > rule.max) return "значение $n больше максимума ${rule.max}"
            return null
        case 'float':
            if (!(v ==~ /-?\d+(\.\d+)?/)) return "ожидалось число, получено '$v'"
            if (rule.min != null && (v as BigDecimal) < rule.min) return "значение $v меньше минимума ${rule.min}"
            return null
        case 'bool':
            return v.toLowerCase() in ['true', 'false', 'yes', 'no', 'on', 'off', '1', '0'] ?
                null : "ожидалось true/false, получено '$v'"
        case 'enum':
            return v in rule.values ? null : "допустимые значения ${rule.values.join('/')}, получено '$v'"
        default: // string
            if (v.isEmpty()) return 'пустое значение'
            if (rule.pattern && !(v ==~ rule.pattern)) return "неверный формат '$v' (ожидается ${rule.hint})"
            return null
    }
}

/** Разбор и проверка одного файла. Возвращает список проблем [level, line, msg]. */
List<Map> validate(File file) {
    def issues = []
    def err  = { int line, String msg -> issues << [level: 'ОШИБКА', line: line, msg: msg] }
    def warn = { int line, String msg -> issues << [level: 'ВНИМАНИЕ', line: line, msg: msg] }

    Map<String, Map<String, Map>> data = [:]   // секция -> ключ -> [value, line]
    String section = null

    file.readLines('UTF-8').eachWithIndex { String raw, int idx ->
        int ln = idx + 1
        String line = raw.trim()
        if (line.isEmpty() || line.startsWith(';') || line.startsWith('#')) return

        def sec = line =~ /^\[\s*([\w.-]+)\s*\]$/
        if (sec.matches()) {
            section = sec.group(1)
            if (data.containsKey(section)) warn(ln, "секция [$section] объявлена повторно")
            data.putIfAbsent(section, [:])
            if (!SCHEMA.containsKey(section)) warn(ln, "неизвестная секция [$section]")
            return
        }

        def kv = line =~ /^([\w.-]+)\s*=\s*(.*)$/
        if (!kv.matches()) { err(ln, "синтаксическая ошибка: '$line'"); return }
        if (section == null) { err(ln, "ключ '${kv.group(1)}' вне секции"); return }

        String key = kv.group(1)
        String value = kv.group(2).replaceAll(/\s+[;#].*$/, '').trim()       // хвостовой комментарий
        if (value ==~ /^".*"$/ || value ==~ /^'.*'$/) value = value[1..-2]   // кавычки

        if (data[section].containsKey(key)) warn(ln, "$section.$key задан повторно (строка ${data[section][key].line})")
        data[section][key] = [value: value, line: ln]
    }

    // Проверка по схеме
    SCHEMA.each { String sec, Map<String, Map> rules ->
        if (!data.containsKey(sec)) {
            if (rules.any { it.value.required }) err(0, "отсутствует обязательная секция [$sec]")
            return
        }
        rules.each { String key, Map rule ->
            def entry = data[sec][key]
            if (entry == null) {
                if (rule.required) err(0, "отсутствует обязательный ключ $sec.$key")
                return
            }
            String problem = checkValue(entry.value as String, rule)
            if (problem) err(entry.line as int, "$sec.$key: $problem")
        }
        (data[sec].keySet() - rules.keySet()).each { k ->
            warn(data[sec][k].line as int, "неизвестный ключ $sec.$k")
        }
    }
    return issues.sort { it.line }
}

// ---------------------------------------------------------------------------

if (args.length == 0) {
    System.err.println 'Использование: groovy validate.groovy <файл.ini> [ещё файлы...]'
    System.exit(2)
}

def stamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern('yyyy-MM-dd HH:mm:ss'))
def log = new File(LOG_FILE)
int totalErrors = 0

args.each { String path ->
    def f = new File(path)
    println "=== $path"
    if (!f.isFile()) {
        println "  [ОШИБКА] файл не найден"
        log.append("[$stamp] $path: файл не найден\n", 'UTF-8')
        totalErrors++
        return
    }

    def issues = validate(f)
    def errors = issues.findAll { it.level == 'ОШИБКА' }
    issues.each { i ->
        def where = i.line > 0 ? "строка ${i.line}" : 'файл'
        println "  [${i.level}] $where: ${i.msg}"
    }
    if (errors) {
        log.append("[$stamp] $path: ошибок ${errors.size()}\n", 'UTF-8')
        errors.each { e ->
            log.append("    ${e.line > 0 ? 'строка ' + e.line : 'файл'}: ${e.msg}\n", 'UTF-8')
        }
        println "  ИТОГ: ошибок ${errors.size()}, предупреждений ${issues.size() - errors.size()} (записано в $LOG_FILE)"
    } else {
        println "  ИТОГ: файл корректен" + (issues ? ", предупреждений ${issues.size()}" : '')
    }
    totalErrors += errors.size()
    println()
}

System.exit(totalErrors > 0 ? 1 : 0)
