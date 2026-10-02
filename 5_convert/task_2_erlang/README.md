# 5.2 Erlang - PROTO-сообщения → JSON

Программа читает **схему `.proto`** и **сообщение в текстовом формате Protobuf**
(text format, `.txtpb`, так Protobuf печатает сообщения для людей), проверяет данные
по схеме и собирает из них стандартный JSON.

```
# person.txtpb                          // результат
name: "Алиса"                           {
id: 1234                                  "name": "Алиса",
phones { number: "+7 999" type: MOBILE }  "id": 1234,
is_active: true                           "phones": [ { "number": "+7 999", "type": "MOBILE" } ],
last_login_ms: 1790000000000              "isActive": true,
                                          "lastLoginMs": "1790000000000"
                                        }
```

## Запуск

```bash
./run.sh 5_convert/task_2_erlang examples/addressbook.proto Person examples/person.txtpb
./run.sh 5_convert/task_2_erlang examples/addressbook.proto AddressBook examples/addressbook.txtpb
./run.sh 5_convert/task_2_erlang examples/addressbook.proto Person examples/person.txtpb out.json
./run.sh 5_convert/task_2_erlang examples/addressbook.proto Person examples/bad.txtpb   # ошибка
```

Аргументы: `<схема.proto> <ТипСообщения> <данные.txtpb> [выход.json]`.

## Как устроено

Три этапа, все на сопоставлении с образцом:

1. **Лексер `tokenize`** (общий для обоих файлов) превращает текст в токены
   `{ident, Строка, "name"}`, `{int, Строка, 42}`, `{str, ...}`, `{punct, ..., ${}`.
   Пропускает комментарии `//` и `#` и запоминает номер строки для сообщений об ошибках.
2. **Два парсера:**
   - `parse_proto` - схема: `message`, `enum`, вложенные сообщения, поля
     `[repeated] Тип имя = номер;`. `syntax`, `package`, `option`, `reserved` пропускаются;
   - `parse_text` - данные: `поле: значение`, `поле { ... }`, списки `поле: [a, b]`.
   Каждое правило грамматики - отдельная клауза функции, образец описывает, какие токены
   должны идти подряд.
3. **`convert`** - проверка по схеме и сборка JSON-дерева по правилам **proto3 JSON mapping**:
   - порядок полей как в схеме, незаданные поля не выводятся;
   - имена полей в `lowerCamelCase` (`is_active` → `isActive`);
   - `repeated` → массив (даже из одного элемента), повтор не-`repeated` поля → ошибка;
   - проверка типов и диапазонов (`int32`, `uint32`, ...), неизвестные поля → ошибка;
   - `enum` → строка с именем (можно задать и номером: `type: 2` → `"WORK"`);
   - `int64`/`uint64` → **строка**: в JSON числа - это double, и большие целые потеряли бы точность;
   - `bytes` → Base64; вложенные сообщения → рекурсия.

Ошибки бросаются через `throw({error, Строка, Текст})` и ловятся в `main`. Пользователь
видит файл, строку и понятную причину.
