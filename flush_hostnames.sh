#!/bin/bash

# Путь к файлу с именами хостов
HOSTNAMES_FILE="/hostnames"

# Проверяем, существует ли файл
if [[ ! -f "$HOSTNAMES_FILE" ]]; then
    echo "Файл $HOSTNAMES_FILE не найден!"
    exit 1
fi

# Читаем файл построчно и выполняем rndc flush для каждого имени
while IFS= read -r hostname; do
    # Пропускаем пустые строки и строки, начинающиеся с #
    if [[ -z "$hostname" || "$hostname" == \#* ]]; then
        continue
    fi

    echo "Очистка кэша для $hostname..."
    rndc flushname "$hostname"
done < "$HOSTNAMES_FILE"