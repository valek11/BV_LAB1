
#!/usr/bin/env bash

# проверка аргументов
if [ $# -lt 3 ] || [ $# -gt 4 ]; then
    echo "Использование: $0 LOG_DIR LIMIT M [BACKUP_DIR]"
    exit 1
fi

dir=$1
lim=$2
m=$3
bak=${4:-/backup}

if ! [[ "$lim" =~ ^[0-9]+$ ]] || [ "$lim" -gt 100 ]; then
    echo "Лимит должен быть от 0 до 100"
    exit 1
fi

if ! [[ "$m" =~ ^[0-9]+$ ]] || [ "$m" -lt 1 ]; then
    echo "Количество файлов должно быть больше 0"
    exit 1
fi

if [ ! -d "$dir" ]; then
    echo "Каталог не найден: $dir"
    exit 1
fi

if ! mkdir -p "$bak"; then
    echo "Не удалось создать каталог архивов"
    exit 1
fi

dir=$(cd "$dir" && pwd -P) || exit 1
bak=$(cd "$bak" && pwd -P) || exit 1

if [ "$dir" = "/" ]; then
    echo "Нельзя использовать корневой каталог"
    exit 1
fi

case "$bak/" in
    "$dir/"*)
        echo "Каталог архивов не должен быть внутри каталога журналов"
        exit 1
        ;;
esac

# проверка заполненности диска
used=$(df -P "$dir" | awk 'NR == 2 {print $5}' | tr -d '%')

if ! [[ "$used" =~ ^[0-9]+$ ]]; then
    echo "Не удалось проверить заполненность диска"
    exit 1
fi

echo "Каталог: $dir"
echo "Лимит: $lim%"
echo "Заполненность диска: $used%"

if [ "$used" -le "$lim" ]; then
    echo "Лимит не превышен"
    exit 0
fi

# выбор старых файлов
files=$(find "$dir" -maxdepth 1 -type f \
    ! -name '*.tar' ! -name '*.gz' \
    -printf '%T@ %f\n' |
    sort -n |
    head -n "$m" |
    cut -d' ' -f2-)

if [ -z "$files" ]; then
    echo "Нет файлов для архивации"
    exit 0
fi

archive="$bak/log_backup_$(date +%Y%m%d_%H%M%S)_$$.tar.gz"

# архивация файлов
if printf '%s\n' "$files" |
    tar -czf "$archive" -C "$dir" -T -; then

    while IFS= read -r f; do
        rm -- "$dir/$f" || {
            echo "Не удалось удалить файл: $f"
            exit 1
        }
    done <<< "$files"

    echo "Архив создан: $archive"
    echo "Количество файлов: $(printf '%s\n' "$files" | wc -l)"
else
    rm -f "$archive"
    echo "Ошибка архивации"
    exit 1
fi
