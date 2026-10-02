# Задача 4.2 (Ruby): сервер-матчмейкер для «Камень-ножницы-бумага».
#
# Клиенты подключаются к серверу и ждут оппонента. Сервер берёт два подключения,
# объединяет их в «комнату» и просит сделать ход. Получив ответы от обоих, сообщает
# каждому результат (победа / поражение / ничья) и закрывает соединение.
#
# Запуск:  ruby rps.rb server [порт]
#          ruby rps.rb client [хост] [порт]          - играть с клавиатуры
#          ruby rps.rb client [хост] [порт] --bot    - бот, ходит случайно
# Только стандартная библиотека (socket, Thread, Queue).

require 'socket'

Encoding.default_external = Encoding::UTF_8
$stdout.sync = true
DEFAULT_PORT = 5002

MOVES = {
  rock:     %w[к камень rock r],
  scissors: %w[н ножницы scissors s],
  paper:    %w[б бумага paper p]
}.freeze
NAMES = { rock: 'камень', scissors: 'ножницы', paper: 'бумага' }.freeze
BEATS = { rock: :scissors, scissors: :paper, paper: :rock }.freeze   # кто кого бьёт

def log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def parse_move(text)
  word = text.to_s.strip.downcase
  MOVES.find { |_, aliases| aliases.include?(word) }&.first
end

# :win / :lose / :draw - с точки зрения игрока с ходом `mine`
def outcome(mine, theirs)
  return :draw if mine == theirs
  BEATS[mine] == theirs ? :win : :lose
end

# ---------------------------------------------------------------------------
# Сервер
# ---------------------------------------------------------------------------

# Читаем ход игрока; до 3 попыток на неверный ввод. nil - игрок отключился.
def read_move(sock)
  3.times do
    line = sock.gets or return nil
    move = parse_move(line)
    if move
      sock.puts "Ход принят (#{NAMES[move]}). Ждём соперника..."
      return move
    end
    sock.puts 'Не понял ход. Введите к, н или б:'
  end
  nil
rescue IOError, SystemCallError
  nil
end

# Проверка, что клиент не отключился, пока стоял в очереди.
def alive?(sock)
  ready, = IO.select([sock], nil, nil, 0)
  !(ready && sock.eof?)
rescue IOError, SystemCallError
  false
end

# Отправка без исключений: false - клиент уже отключился.
def send_line(player, msg)
  player[:sock].puts(msg)
  true
rescue IOError, SystemCallError
  false
end

# Выбросить всё, что клиент успел прислать заранее (до приглашения сделать ход).
def drain(sock)
  loop { sock.read_nonblock(4096) }
rescue IO::WaitReadable, IOError, SystemCallError
  nil
end

def play(room, players, waiting)
  log "Комната ##{room}: игроки #{players.map { |p| p[:name] }.join(' и ')}"
  players.each { |p| drain(p[:sock]) }
  sent = players.each_with_index.map do |p, i|
    send_line(p, "Соперник найден: #{players[1 - i][:name]}. Комната ##{room}.") &&
      send_line(p, 'Ваш ход - камень / ножницы / бумага (к/н/б):')
  end
  # Кто-то отвалился до начала игры - живого игрока возвращаем в очередь
  unless sent.all?
    players.each_with_index do |p, i|
      next unless sent[i]
      send_line(p, 'Соперник отключился, ищем нового...')
      waiting << p
    end
    log "Комната ##{room}: игрок отключился до начала, второй вернулся в очередь"
    players.each_with_index { |p, i| p[:sock].close rescue nil unless sent[i] }
    return
  end

  # Ходы читаются ПАРАЛЛЕЛЬНО: никто не ждёт, пока сходит другой
  moves = players.map { |p| Thread.new { read_move(p[:sock]) } }.map(&:value)

  if moves.include?(nil)
    players.each_with_index do |p, i|
      send_line(p, 'Соперник отключился. Игра отменена.') if moves[i]
    end
    log "Комната ##{room}: игра отменена (игрок отключился)"
    return
  end

  texts = { win: 'ПОБЕДА!', lose: 'Поражение.', draw: 'Ничья.' }
  players.each_with_index do |p, i|
    mine, theirs = moves[i], moves[1 - i]
    send_line(p, "Вы: #{NAMES[mine]}, соперник: #{NAMES[theirs]} → #{texts[outcome(mine, theirs)]}")
  end
  log "Комната ##{room}: #{players[0][:name]} (#{NAMES[moves[0]]}) vs " \
      "#{players[1][:name]} (#{NAMES[moves[1]]}) → " \
      "#{{ win: "победил #{players[0][:name]}", lose: "победил #{players[1][:name]}", draw: 'ничья' }[outcome(moves[0], moves[1])]}"
rescue IOError, SystemCallError => e
  log "Комната ##{room}: ошибка связи (#{e.class})"
ensure
  players.each { |p| p[:sock].close rescue nil } if sent&.all?
end

def run_server(port)
  server = TCPServer.new('0.0.0.0', port)
  waiting = Queue.new        # очередь ожидающих игроков (потокобезопасная)
  log "Матчмейкер запущен на порту #{port}"

  # Поток-матчмейкер: берёт из очереди по два живых игрока и создаёт комнату
  Thread.new do
    room = 0
    loop do
      first = waiting.pop
      next log("#{first[:name]} ушёл из очереди") unless alive?(first[:sock])
      second = waiting.pop
      unless alive?(second[:sock])
        log "#{second[:name]} ушёл из очереди"
        waiting << first          # первого возвращаем ждать дальше
        next
      end
      room += 1
      Thread.new(room) { |r| play(r, [first, second], waiting) }   # каждая комната - свой поток
    end
  end

  counter = 0
  loop do
    sock = server.accept
    sock.set_encoding(Encoding::UTF_8)
    counter += 1
    player = { sock: sock, name: "игрок#{counter}" }
    log "#{player[:name]} подключился, в очереди: #{waiting.size + 1}"
    sock.puts "Привет, #{player[:name]}! Ищем соперника..."
    waiting << player
  end
end

# ---------------------------------------------------------------------------
# Клиент
# ---------------------------------------------------------------------------

def run_client(host, port, bot)
  sock = TCPSocket.new(host, port)
  sock.set_encoding(Encoding::UTF_8)
  inputs = bot ? [sock] : [sock, $stdin]

  # Один поток, IO.select ждёт данных сразу от сервера и от клавиатуры
  loop do
    ready, = IO.select(inputs)
    if ready.include?(sock)
      line = sock.gets or break             # nil - сервер закрыл соединение
      puts line
      if bot && line.include?('Ваш ход')
        sleep(rand(0.5..2.0))
        move = MOVES.keys.sample
        puts "(бот выбрал: #{NAMES[move]})"
        sock.puts NAMES[move]
      end
    end
    if ready.include?($stdin)
      text = $stdin.gets or break
      sock.puts text
    end
  end
  puts 'Соединение закрыто.'
rescue Errno::ECONNREFUSED
  puts "Не удалось подключиться к #{host}:#{port} - сервер запущен?"
  exit 1
rescue IOError, SystemCallError
  puts 'Соединение закрыто сервером.'
end

# ---------------------------------------------------------------------------

case ARGV[0]
when 'server'
  run_server((ARGV[1] || DEFAULT_PORT).to_i)
when 'client'
  bot = ARGV.delete('--bot')
  run_client(ARGV[1] || 'localhost', (ARGV[2] || DEFAULT_PORT).to_i, bot)
else
  puts 'Использование: rps.rb server [порт] | rps.rb client [хост] [порт] [--bot]'
end
