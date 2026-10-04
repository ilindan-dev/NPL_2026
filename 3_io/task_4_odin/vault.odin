// Задача 3.4 (Odin): генератор надёжных паролей и хранилище.
//
// Программа спрашивает имя сервиса, длину пароля и требования (цифры, спецсимволы),
// генерирует пароль криптографически стойким генератором, выводит его и дописывает
// вместе с именем сервиса в файл-хранилище vault.txt, каждая запись закодирована в Base64.
//
// Режимы:
//   vault                                  - интерактивное меню
//   vault gen <сервис> [длина] [--no-digits] [--no-special]
//   vault list
//
// Написано под Odin dev-2024-12.
package main

import "core:bufio"
import "core:crypto"
import "core:encoding/base64"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

VAULT_FILE :: "vault.txt"

LOWER   :: "abcdefghijklmnopqrstuvwxyz"
UPPER   :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
DIGITS  :: "0123456789"
SPECIAL :: "!@#$%^&*()-_=+[]{};:,.?/"

stdin_reader: bufio.Reader

// ---------------------------------------------------------------------------
// Генерация
// ---------------------------------------------------------------------------

// Случайное число 0..n-1 без перекоса: байты >= limit отбрасываем (rejection sampling),
// иначе остаток от деления давал бы одним символам чуть большую вероятность.
random_index :: proc(n: int) -> int {
	limit := 256 - 256 % n
	for {
		b: [1]u8
		crypto.rand_bytes(b[:])
		if int(b[0]) < limit {
			return int(b[0]) % n
		}
	}
}

// Возвращает пароль и размер алфавита (для оценки стойкости).
generate :: proc(length: int, use_digits, use_special: bool) -> (string, int) {
	classes := make([dynamic]string, context.temp_allocator)
	append(&classes, LOWER, UPPER)
	if use_digits  { append(&classes, DIGITS) }
	if use_special { append(&classes, SPECIAL) }
	alphabet := strings.concatenate(classes[:], context.temp_allocator)

	buf := make([]u8, length)
	// по одному символу из каждого класса - требования гарантированно выполнены
	for cls, i in classes {
		buf[i] = cls[random_index(len(cls))]
	}
	// остальные - из общего алфавита
	for i in len(classes) ..< length {
		buf[i] = alphabet[random_index(len(alphabet))]
	}
	// перемешивание Фишера-Йетса, чтобы обязательные символы не стояли в начале
	for i := length - 1; i > 0; i -= 1 {
		j := random_index(i + 1)
		buf[i], buf[j] = buf[j], buf[i]
	}
	return string(buf), len(alphabet)
}

// ---------------------------------------------------------------------------
// Хранилище
// ---------------------------------------------------------------------------

// Запись: "сервис\tпароль\tдата" -> Base64 -> одна строка файла.
save_entry :: proc(service, password: string) -> bool {
	y, m, d := time.date(time.now())
	plain := fmt.tprintf("%s\t%s\t%04d-%02d-%02d", service, password, y, int(m), d)
	encoded := base64.encode(transmute([]u8)plain, allocator = context.temp_allocator)

	old, _ := os.read_entire_file(VAULT_FILE, context.temp_allocator)   // файла может не быть
	data := strings.concatenate([]string{string(old), encoded, "\n"}, context.temp_allocator)
	return os.write_entire_file(VAULT_FILE, transmute([]u8)data)
}

cmd_list :: proc() {
	data, ok := os.read_entire_file(VAULT_FILE, context.temp_allocator)
	if !ok || len(data) == 0 {
		fmt.println("Хранилище пусто")
		return
	}
	content := string(data)
	fmt.printf("Хранилище %s:\n\n", VAULT_FILE)
	fmt.printf("  %-3s %-24s %-34s %s\n", "№", "Сервис", "Пароль", "Дата")
	n := 0
	for line in strings.split_lines_iterator(&content) {
		if len(line) == 0 { continue }
		decoded := base64.decode(line, allocator = context.temp_allocator)
		parts := strings.split(string(decoded), "\t", context.temp_allocator)
		if len(parts) < 2 { continue }
		n += 1
		fmt.printf("  %-3d %-24s %-34s %s\n", n, parts[0], parts[1], len(parts) > 2 ? parts[2] : "")
	}
	raw_lines := strings.split_lines(string(data), context.temp_allocator)
	fmt.printf("\nВсего записей: %d. На диске они лежат в Base64, например:\n  %s\n", n, raw_lines[0])
}

do_generate :: proc(service: string, length: int, digits, special: bool) {
	password, alphabet := generate(length, digits, special)
	defer delete(password)
	bits := f64(length) * math.log2(f64(alphabet))
	strength := "слабый"
	if bits >= 100 {
		strength = "очень надёжный"
	} else if bits >= 70 {
		strength = "надёжный"
	} else if bits >= 50 {
		strength = "средний"
	}

	fmt.printf("\n  Сервис:  %s\n  Пароль:  %s\n", service, password)
	fmt.printf("  Алфавит: %d символов, энтропия ≈ %.0f бит (%s)\n", alphabet, bits, strength)
	if save_entry(service, password) {
		fmt.printf("  Сохранено в %s (Base64)\n", VAULT_FILE)
	} else {
		fmt.printf("  Не удалось записать %s\n", VAULT_FILE)
	}
}

// ---------------------------------------------------------------------------
// Ввод
// ---------------------------------------------------------------------------

read_line :: proc(prompt: string) -> (string, bool) {
	fmt.print(prompt)
	line, err := bufio.reader_read_string(&stdin_reader, '\n', context.temp_allocator)
	if err != .None && len(line) == 0 {
		return "", false   // конец ввода (Ctrl+D)
	}
	return strings.trim_space(line), true
}

ask_yes :: proc(prompt: string) -> bool {
	ans, _ := read_line(prompt)
	ans = strings.to_lower(ans, context.temp_allocator)
	return ans == "" || ans == "y" || ans == "yes" || ans == "д" || ans == "да"
}

interactive_generate :: proc() {
	service, ok := read_line("Сервис (например, github.com): ")
	if !ok || len(service) == 0 {
		fmt.println("Имя сервиса не может быть пустым")
		return
	}
	length := 16
	len_str, _ := read_line("Длина пароля [16]: ")
	if len(len_str) > 0 {
		n, parsed := strconv.parse_int(len_str)
		if !parsed || n < 4 || n > 128 {
			fmt.println("Длина должна быть числом от 4 до 128")
			return
		}
		length = n
	}
	digits  := ask_yes("Использовать цифры? [Y/n]: ")
	special := ask_yes("Использовать спецсимволы? [Y/n]: ")
	do_generate(service, length, digits, special)
}

// ---------------------------------------------------------------------------

main :: proc() {
	args := os.args[1:]

	// Неинтерактивный режим: vault gen <сервис> [длина] [--no-digits] [--no-special]
	if len(args) > 0 {
		switch args[0] {
		case "list":
			cmd_list()
		case "gen":
			if len(args) < 2 {
				fmt.println("Использование: vault gen <сервис> [длина] [--no-digits] [--no-special]")
				os.exit(1)
			}
			length, digits, special := 16, true, true
			for a in args[2:] {
				switch a {
				case "--no-digits":  digits = false
				case "--no-special": special = false
				case:
					n, ok := strconv.parse_int(a)
					if !ok || n < 4 || n > 128 {
						fmt.println("Длина должна быть числом от 4 до 128")
						os.exit(1)
					}
					length = n
				}
			}
			do_generate(args[1], length, digits, special)
		case:
			fmt.println("Команды: gen <сервис> [длина] [--no-digits] [--no-special] | list")
			os.exit(1)
		}
		return
	}

	// Интерактивное меню
	bufio.reader_init(&stdin_reader, os.stream_from_handle(os.stdin))
	defer bufio.reader_destroy(&stdin_reader)

	fmt.println("=== Генератор паролей и хранилище ===")
	for {
		fmt.println("\n1) Сгенерировать пароль\n2) Показать хранилище\n3) Выход")
		choice, ok := read_line("> ")
		if !ok { break }
		switch choice {
		case "1": interactive_generate()
		case "2": cmd_list()
		case "3", "q": return
		case: fmt.println("Неизвестная команда")
		}
		free_all(context.temp_allocator)
	}
}
