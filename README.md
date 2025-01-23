# Периодическое удаление имён на кэширующем сервере DNS применительно к BIND
Предполагается, что на сервере работает кэширующий сервер DNS BIND.
Если на сервере не натроен rndc.key, то следует его созать и настроить.
1. Создание ключа rndc
```bash
sudo rndc-confgen -a -c /etc/bind/rndc.key
```
- `-a`: Автоматически создает файл ключа.
- `-c`: Указывает путь, куда сохранить ключ (в данном случае `/etc/bind/rndc.key`).
После выполнения команды файл /etc/bind/rndc.key будет создан, и в нем будет содержаться ключ для управления BIND.
2. Установление прав доступа
```bash
sudo chown root:bind /etc/bind/rndc.key
sudo chmod 640 /etc/bind/rndc.key
```
3. Настройка bind для использования `rndc.key`
В файл `/etc/bind/named.conf.options` добавить следующие строки:
```
include "/etc/bind/rndc.key";

controls {
    inet 127.0.0.1 port 953
        allow { 127.0.0.1; }
        keys { "rndc-key"; };
};
```
4. Проверка работы rndc
После настройки перезапустите BIND, чтобы применить изменения:
```bash
sudo systemctl restart named
```
Затем проверьте, что rndc работает корректно, выполнив команду:
```bash
sudo rndc status
```
Попробуйте удалить кэшированную запись DNS:
```bash
sudo rndc flushname www.cnn.com
```
Проверьте в системном журнале что запись удалена:
```bash
sudo journalctl -u named --since "1 minute ago"
```
Там будет что-то наподобие:
```
-- Logs begin at Wed 2024-07-17 19:17:01 MSK, end at Thu 2025-01-23 11:48:48 MSK. --
янв 23 11:48:24 muumipeikko named[392026]: received control channel command 'flushname www.cnn.com'
янв 23 11:48:24 muumipeikko named[392026]: flushing name 'www.cnn.com' in all cache views succeeded
```
5. Создание скрипта
Создадим скрипт, который будет читать файл /hostnames и выполнять rndc flush для каждого имени.
```bash
sudo nano /usr/local/bin/flush_hostnames.sh
```
Текст скрипта
```bash
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
```
- Скрипт читает файл /hostnames построчно.
- Для каждой строки (кроме пустых и закомментированных, начинающихся с #) выполняется команда `rndc flushname`.
- Логирование выводится в консоль.
Сделайте скрипт исполняемым:
```bash
sudo chmod +x /usr/local/bin/flush_hostnames.sh
```
Файл `/hostnames` должен содержать список доменных имен, по одному на строку. Например:
```plaintext
bbc.com
www.cnn.com
www.nvidia.com
# Это комментарий, он будет пропущен
x.com
```
6. Создание systemd-сервиса
Теперь создайте systemd-сервис, который будет запускать этот скрипт. Создайте файл сервиса.
```bash
sudo nano /etc/systemd/system/flush-hostnames.service
```
Текст сервиса
```ini
[Unit]
Description=Flush DNS cache for hostnames listed in /hostnames

[Service]
Type=oneshot
ExecStart=/usr/local/bin/flush_hostnames.sh
```
Перечитываем конфигурацию systemd:
```bash
sudo systemctl daemon-reload
```
Пробуем запустить сервис:
```bash
sudo systemctl start flush-hostnames.service
```
Смотрим на результат запуска:
```bash
sudo systemctl status flush-hostnames.service
```
```plaintext
● flush-hostnames.service - Flush DNS cache for hostnames listed in /hostnames
     Loaded: loaded (/etc/systemd/system/flush-hostnames.service; static; vendor preset: enabled)
     Active: inactive (dead)

янв 23 12:14:00 muumipeikko systemd[1]: Starting Flush DNS cache for hostnames listed in /hostnames...
янв 23 12:14:00 muumipeikko flush_hostnames.sh[396497]: Очистка кэша для bbc.com...
янв 23 12:14:00 muumipeikko flush_hostnames.sh[396497]: Очистка кэша для www.cnn.com...
янв 23 12:14:00 muumipeikko flush_hostnames.sh[396497]: Очистка кэша для www.nvidia.com...
янв 23 12:14:00 muumipeikko flush_hostnames.sh[396497]: Очистка кэша для x.com...
янв 23 12:14:00 muumipeikko systemd[1]: flush-hostnames.service: Succeeded.
янв 23 12:14:00 muumipeikko systemd[1]: Finished Flush DNS cache for hostnames listed in /hostnames.
```
```bash
sudo journalctl -u named --since "1 minute ago"
```
```plaintext
-- Logs begin at Wed 2024-07-17 19:17:01 MSK, end at Thu 2025-01-23 12:14:12 MSK. --
янв 23 12:14:00 muumipeikko named[392026]: received control channel command 'flushname bbc.com'
янв 23 12:14:00 muumipeikko named[392026]: flushing name 'bbc.com' in all cache views succeeded
янв 23 12:14:00 muumipeikko named[392026]: received control channel command 'flushname www.cnn.com'
янв 23 12:14:00 muumipeikko named[392026]: flushing name 'www.cnn.com' in all cache views succeeded
янв 23 12:14:00 muumipeikko named[392026]: received control channel command 'flushname www.nvidia.com'
янв 23 12:14:00 muumipeikko named[392026]: flushing name 'www.nvidia.com' in all cache views succeeded
янв 23 12:14:00 muumipeikko named[392026]: received control channel command 'flushname x.com'
янв 23 12:14:00 muumipeikko named[392026]: flushing name 'x.com' in all cache views succeeded
```
7. Создание systemd-таймера
Создаём файл таймера:
```bash
sudo nano /etc/systemd/system/flush-hostnames.timer
```
Со следующим содержимым:
```ini
[Unit]
Description=Run flush-hostnames.service every 5 minutes

[Timer]
OnCalendar=*:0/5
Unit=flush-hostnames.service

[Install]
WantedBy=timers.target
```
- `OnCalendar=*:0/5`: Запускать каждые 5 минут.
- `Unit=flush-hostnames.service`: Указывает, какой сервис запускать.
- `WantedBy=timers.target`: Указывает, что таймер должен быть включен в систему.
Перечитываем конфигурацию systemd:
```bash
sudo systemctl daemon-reload
```
Включаем и запускаем таймер:
```bash
sudo systemctl enable flush-hostnames.timer
sudo systemctl start flush-hostnames.timer
```
Проверяем статус таймера:
```bash
sudo systemctl list-timers
```
Ждём срабатывания таймера и сомтрим результаты работы:
```bash
sudo journalctl --since "5 minutes ago"
```
Вывод должен быть наподобие этого:
```plaintext
янв 23 14:30:12 muumipeikko systemd[1]: Starting Flush DNS cache for hostnames listed in /hostnames...
янв 23 14:30:12 muumipeikko flush_hostnames.sh[396868]: Очистка кэша для bbc.com...
янв 23 14:30:12 muumipeikko named[392026]: received control channel command 'flushname bbc.com'
янв 23 14:30:12 muumipeikko named[392026]: flushing name 'bbc.com' in all cache views succeeded
янв 23 14:30:12 muumipeikko flush_hostnames.sh[396868]: Очистка кэша для www.cnn.com...
янв 23 14:30:12 muumipeikko named[392026]: received control channel command 'flushname www.cnn.com'
янв 23 14:30:12 muumipeikko named[392026]: flushing name 'www.cnn.com' in all cache views succeeded
янв 23 14:30:12 muumipeikko flush_hostnames.sh[396868]: Очистка кэша для www.nvidia.com...
янв 23 14:30:12 muumipeikko named[392026]: received control channel command 'flushname www.nvidia.com'
янв 23 14:30:12 muumipeikko named[392026]: flushing name 'www.nvidia.com' in all cache views succeeded
янв 23 14:30:12 muumipeikko flush_hostnames.sh[396868]: Очистка кэша для x.com...
янв 23 14:30:12 muumipeikko named[392026]: received control channel command 'flushname x.com'
янв 23 14:30:12 muumipeikko named[392026]: flushing name 'x.com' in all cache views succeeded
янв 23 14:30:12 muumipeikko systemd[1]: flush-hostnames.service: Succeeded.
янв 23 14:30:12 muumipeikko systemd[1]: Finished Flush DNS cache for hostnames listed in /hostnames.
```