
#!/usr/bin/env bash

script=${1:-./log_archive.sh}

if [ ! -f "$script" ]; then
    echo "Скрипт не найден: $script"
    exit 1
fi

script="$(cd "$(dirname "$script")" && pwd)/$(basename "$script")"

root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT

passed=0
failed=0

mkdir -p "$root/bin"

cat > "$root/bin/df" <<'EOF'
#!/bin/sh
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000 800 200 ${DF_PERCENT:-50}% /"
EOF

chmod +x "$root/bin/df"

run_test() {
    name="$1"
    percent="$2"
    expected="$3"
    shift 3

    if DF_PERCENT="$percent" PATH="$root/bin:$PATH" \
        bash "$script" "$@" > "$root/output" 2>&1; then
        result=0
    else
        result=$?
    fi

    if [ "$expected" = "ok" ] && [ "$result" -eq 0 ]; then
        echo "PASS: $name"
        passed=$((passed + 1))
    elif [ "$expected" = "fail" ] && [ "$result" -ne 0 ]; then
        echo "PASS: $name"
        passed=$((passed + 1))
    else
        echo "FAIL: $name"
        cat "$root/output"
        failed=$((failed + 1))
    fi
}

mkdir -p "$root/t1/log" "$root/t1/backup"
echo "test" > "$root/t1/log/app.log"

run_test "Лимит не превышен" 50 ok \
    "$root/t1/log" 60 1 "$root/t1/backup"

if [ -f "$root/t1/log/app.log" ] &&
   [ -z "$(find "$root/t1/backup" -name '*.tar.gz' -print -quit)" ]; then
    echo "Файл остался на месте"
else
    echo "FAIL: Файл изменён"
    failed=$((failed + 1))
    passed=$((passed - 1))
fi

mkdir -p "$root/t2/log" "$root/t2/backup"
echo "old" > "$root/t2/log/old file.log"
echo "new" > "$root/t2/log/new.log"

touch -d '2020-01-01' "$root/t2/log/old file.log"
touch -d '2022-01-01' "$root/t2/log/new.log"

run_test "Архивация старого файла" 90 ok \
    "$root/t2/log" 80 1 "$root/t2/backup"

archive=$(find "$root/t2/backup" -name '*.tar.gz' -print -quit)

if [ -n "$archive" ] &&
   gzip -t "$archive" &&
   tar -tzf "$archive" | grep -Fq 'old file.log' &&
   [ ! -e "$root/t2/log/old file.log" ] &&
   [ -f "$root/t2/log/new.log" ]; then
    echo "Архив проверен"
else
    echo "FAIL: Ошибка проверки архива"
    failed=$((failed + 1))
    passed=$((passed - 1))
fi

mkdir -p "$root/t3/backup"

run_test "Несуществующий каталог" 90 fail \
    "$root/missing" 80 1 "$root/t3/backup"

mkdir -p "$root/t4/log" "$root/t4/backup"

run_test "Неверный лимит" 90 fail \
    "$root/t4/log" 150 1 "$root/t4/backup"

mkdir -p "$root/t5/log" "$root/t5/backup"
echo "test" > "$root/t5/log/app.gz"
echo "test" > "$root/t5/log/app.tar"

run_test "Нет подходящих файлов" 90 ok \
    "$root/t5/log" 80 1 "$root/t5/backup"

echo
echo "Тестов пройдено: $passed из 5"
echo "Тестов провалено: $failed из 5"

if [ "$failed" -gt 0 ]; then
    exit 1
fi

exit 0
