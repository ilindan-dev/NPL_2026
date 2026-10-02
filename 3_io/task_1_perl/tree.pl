#!/usr/bin/env perl
# Задача 3.1 (Perl): CLI-генератор структуры директорий (аналог команды tree).
#
# Рекурсивно обходит папку и рисует псевдографическое дерево вложенности.
#
# Использование:
#   perl tree.pl [опции] [папка]
#     -a          показывать скрытые файлы (начинающиеся с точки)
#     -d          только папки
#     -L N        максимальная глубина
#     -s          показывать размер файлов
#     -o FILE     дополнительно сохранить дерево в файл (без цветов)
#     --no-color  без цветов
use strict;
use warnings;
use utf8;
use Getopt::Long qw(:config bundling no_ignore_case);
use File::Spec;
use Encode qw(decode);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# Имена файлов из ФС - байты; для вывода декодируем их как UTF-8.
sub disp { decode('UTF-8', $_[0], Encode::FB_DEFAULT) }

my ($show_all, $dirs_only, $max_depth, $show_size, $out_file, $no_color) = (0, 0, undef, 0, undef, 0);
GetOptions(
    'a'        => \$show_all,
    'd'        => \$dirs_only,
    'L=i'      => \$max_depth,
    's'        => \$show_size,
    'o=s'      => \$out_file,
    'no-color' => \$no_color,
    'h|help'   => sub { print_usage(); exit 0 },
) or do { print_usage(); exit 1 };

my $root = shift @ARGV // '.';
die "Ошибка: '" . disp($root) . "' не является папкой\n" unless -d $root;

my $use_color = !$no_color && -t STDOUT;
my %C = $use_color
    ? (dir => "\e[1;34m", exe => "\e[1;32m", link => "\e[1;36m", reset => "\e[0m")
    : (dir => '', exe => '', link => '', reset => '');

my ($n_dirs, $n_files) = (0, 0);
my @plain;   # строки без цветов - для сохранения в файл

emit($C{dir} . disp($root) . $C{reset}, disp($root));
walk($root, '', 1);

my $summary = sprintf "\n%d %s, %d %s",
    $n_dirs,  plural($n_dirs,  'папка', 'папки', 'папок'),
    $n_files, plural($n_files, 'файл',  'файла', 'файлов');
emit($summary, $summary);

if (defined $out_file) {
    open my $fh, '>:encoding(UTF-8)', $out_file or die "Не могу записать $out_file: $!\n";
    print $fh "$_\n" for @plain;
    close $fh;
    print "\nДерево сохранено в $out_file\n";
}

# --------------------------------------------------------------------------

# Рекурсивный обход: $prefix - накопленные "│   " / "    " от родителей.
sub walk {
    my ($dir, $prefix, $depth) = @_;
    return if defined $max_depth && $depth > $max_depth;

    opendir(my $dh, $dir) or do { emit("$prefix└── [нет доступа]", "$prefix└── [нет доступа]"); return };
    my @entries = grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;

    @entries = grep { !/^\./ } @entries unless $show_all;
    @entries = grep { -d File::Spec->catfile($dir, $_) } @entries if $dirs_only;
    # Сначала папки, потом файлы; внутри - по алфавиту без учёта регистра
    @entries = sort {
        my $da = -d File::Spec->catfile($dir, $a) ? 0 : 1;
        my $db = -d File::Spec->catfile($dir, $b) ? 0 : 1;
        $da <=> $db or lc($a) cmp lc($b)
    } @entries;

    for my $i (0 .. $#entries) {
        my $name = $entries[$i];
        my $path = File::Spec->catfile($dir, $name);
        my $last = ($i == $#entries);
        my $branch = $last ? '└── ' : '├── ';

        my ($colored, $plain) = describe($path, $name);
        emit("$prefix$branch$colored", "$prefix$branch$plain");

        if (-d $path && !-l $path) {
            $n_dirs++;
            walk($path, $prefix . ($last ? '    ' : '│   '), $depth + 1);
        } else {
            $n_files++;
        }
    }
}

# Имя с цветом и пометками (размер, ссылка).
sub describe {
    my ($path, $raw) = @_;
    my $name = disp($raw);
    my $size = ($show_size && -f $path) ? ' [' . human_size(-s $path) . ']' : '';
    if (-l $path) {
        my $target = disp(readlink($path) // '?');
        return ("$C{link}$name$C{reset} -> $target", "$name -> $target");
    }
    return ("$C{dir}$name$C{reset}/", "$name/") if -d $path;
    return ("$C{exe}$name$C{reset}$size", "$name$size") if -x $path;
    return ("$name$size", "$name$size");
}

sub emit {
    my ($colored, $plain) = @_;
    print "$colored\n";
    push @plain, $plain;
}

sub human_size {
    my $b = shift;
    my @u = ('B', 'K', 'M', 'G');
    my $i = 0;
    while ($b >= 1024 && $i < $#u) { $b /= 1024; $i++ }
    return $i ? sprintf('%.1f%s', $b, $u[$i]) : "$b$u[$i]";
}

# Русские окончания: 1 файл, 2 файла, 5 файлов.
sub plural {
    my ($n, $one, $few, $many) = @_;
    my ($m10, $m100) = ($n % 10, $n % 100);
    return $one if $m10 == 1 && $m100 != 11;
    return $few if $m10 >= 2 && $m10 <= 4 && ($m100 < 12 || $m100 > 14);
    return $many;
}

sub print_usage {
    print <<'USAGE';
Использование: perl tree.pl [опции] [папка]
  -a          показывать скрытые файлы
  -d          только папки
  -L N        максимальная глубина
  -s          показывать размеры файлов
  -o FILE     сохранить дерево в файл
  --no-color  без цветов
USAGE
}
