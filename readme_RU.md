# FW_NULL - Firewall Nullifier Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/13winged/fw_null)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)

## 📋 Описание

**FW_NULL** - это bash-скрипт для экстренного сброса настроек файрвола (iptables/UFW/nftables) до стандартных значений ACCEPT ALL. Создан специально для ситуаций, когда администратор случайно блокирует себе доступ к серверу (например, закрывает 22 порт) и теряет возможность подключиться по SSH.

Скрипт сохраняет бэкап всех текущих правил, затем очищает каждую таблицу iptables/ip6tables, выставляет политики INPUT/FORWARD/OUTPUT в ACCEPT, отключает UFW и firewalld, сбрасывает nftables и проверяет, что SSH остался доступен.

## 🎯 Для чего это нужно?

- **Экстренное восстановление доступа** - если случайно заблокировали SSH (порт 22)
- **Сброс "сломанных" правил** - когда файрвол настроен некорректно
- **Подготовка сервера к перенастройке** - нужно начать с чистого листа
- **Миграция серверов** - перенос конфигурации на новое оборудование

## ✨ Возможности

- ✅ **Автоматическое создание бэкапов** - правила iptables, ip6tables, nftables и статус UFW сохраняются перед сбросом
- ✅ **Сначала политики ACCEPT** - INPUT, FORWARD, OUTPUT = ACCEPT *до* очистки, чтобы старый DROP не оставил вас без доступа
- ✅ **Очистка всех таблиц** - filter, nat, mangle, raw, security (IPv4 + IPv6), пользовательские цепочки удаляются
- ✅ **Сброс nftables** - полная очистка ruleset
- ✅ **Отключение UFW** - сервис отключается и убирается из автозагрузки
- ✅ **firewalld останавливается и отключается** - чтобы не вернул правила обратно
- ✅ **Понимание Docker** - перезапускает Docker если активен, чтобы он пересоздал свои цепочки (контейнеры не теряют сеть)
- ✅ **Проверка SSH доступности** - убеждается, что SSH слушает и работает после сброса
- ✅ **Отображение открытых портов** - показывает слушающие сервисы через `ss`
- ✅ **Подтверждение + dry-run** - интерактивный вопрос `[y/N]` по умолчанию, `--force` для автоматизации, `--dry-run` для предпросмотра
- ✅ **Цветной вывод + подробное логирование** - всё записывается в `/var/log/fw_null.log`
- ✅ **Опциональное сохранение** - `--save-empty` сохраняет пустые правила через netfilter-persistent

## 🚀 Быстрый старт

```bash
# Клонирование репозитория
git clone https://github.com/13winged/fw_null.git
cd fw_null

# Делаем скрипт исполняемым
chmod +x fw_null.sh

# Предпросмотр (безопасно, ничего не меняет)
sudo ./fw_null.sh --dry-run

# Запуск (спросит подтверждение)
sudo ./fw_null.sh --force
```

### Или просто скачать скрипт

```bash
wget https://raw.githubusercontent.com/13winged/fw_null/main/fw_null.sh
chmod +x fw_null.sh
sudo ./fw_null.sh --force
```

### Установка в систему

```bash
sudo cp fw_null.sh /usr/local/bin/fw_null
sudo fw_null --force
```

## 📖 Использование

```
fw_null.sh v2.0.0 - emergency firewall reset (iptables/UFW/nftables -> ACCEPT ALL)

Usage: sudo ./fw_null.sh [OPTIONS]

Options:
  -b, --backup-dir DIR   backup directory (default: /root/fw_backups)
  -l, --log-file FILE    log file (default: /var/log/fw_null.log)
  -y, --force, --yes     skip confirmation prompt (required in non-interactive mode)
      --dry-run          print what would be done and exit
      --save-empty       persist empty rules via netfilter-persistent (if available)
  -h, --help             show help and exit
```

Скрипт выполнит следующие шаги:
1. Проверит права root
2. Создаст директорию для бэкапов, сохранит текущие правила (iptables, ip6tables, nftables, статус UFW)
3. Отключит UFW
4. Остановит и отключит netfilter-persistent и firewalld
5. Выставит ACCEPT-политики, очистит все IPv4 таблицы и цепочки
6. Выставит ACCEPT-политики, очистит все IPv6 таблицы и цепочки
7. Сбросит nftables ruleset, перезапустит Docker если активен
8. Опционально сохранит пустые правила (`--save-empty`)
9. Покажет слушающие порты
10. Проверит SSH доступность

### Пример вывода

```
=== Resetting firewall rules ===
SUCCESS: iptables rules reset to default (ACCEPT ALL)
SUCCESS: ip6tables rules reset to default (ACCEPT ALL)

=== Verifying SSH accessibility ===
SUCCESS: SSH appears to be listening and running

--- SUMMARY ---
INFO: Backup directory: /root/fw_backups/fw_null_20260213_143022
INFO: Log file: /var/log/fw_null.log
```

## 🔧 Требования к системе

- **ОС**: Linux (Ubuntu, Debian, CentOS, RHEL и другие)
- **Права**: root или sudo доступ
- **Bash**: версия 4.0 или выше
- **Команды**: iptables / ip6tables / nft (обрабатывается то, что есть)

## 📂 Структура бэкапов

```
/root/fw_backups/
├── fw_null_20260213_143022/
│   ├── iptables.v4
│   ├── iptables.v6
│   ├── nftables.rules
│   ├── ufw_status.txt
│   └── backup_info.txt
├── fw_null_20260213_152037/
│   └── ...
└── ...
```

## ⚠️ Важные замечания

1. **Скрипт должен запускаться с sudo** - без прав root он не сработает
2. **Бэкапы создаются автоматически** - можно восстановиться, если что-то пошло не так
3. **После сброса все порты открыты** - сервер становится уязвимым, настройте файрвол заново
4. **Пустые правила НЕ сохраняются по умолчанию** - перезагрузка может вернуть старые сохранённые правила; передайте `--save-empty` для сохранения или настройте файрвол до перезагрузки
5. **Неинтерактивный запуск требует `--force`** - иначе без TTY скрипт откажется работать

## 🔄 Восстановление из бэкапа

Если нужно вернуть старые правила:

```bash
# Посмотреть доступные бэкапы
ls -la /root/fw_backups/

# Восстановить IPv4 правила
sudo iptables-restore < /root/fw_backups/fw_null_20260213_143022/iptables.v4

# Восстановить IPv6 правила
sudo ip6tables-restore < /root/fw_backups/fw_null_20260213_143022/iptables.v6

# Восстановить nftables ruleset
sudo nft -f /root/fw_backups/fw_null_20260213_143022/nftables.rules

# Включить UFW обратно (если использовался)
sudo systemctl enable ufw
sudo ufw enable
```

## 🐛 Решение проблем

### "Порт 22 все еще не доступен"
```bash
# Проверить статус SSH
systemctl status sshd

# Проверить, слушает ли SSH порт 22
ss -tlnp | grep 22

# Перезапустить SSH
systemctl restart sshd
```

### "Не могу сохранить правила"
```bash
# Установить netfilter-persistent
apt-get install iptables-persistent netfilter-persistent
# или
yum install iptables-services

# Запустить сохранение вручную
iptables-save > /etc/iptables/rules.v4
```

### "После сброса перестал работать DNS"
В версиях до 2.0.0 по ошибке останавливался `systemd-resolved`. Версия 2.0.0+ DNS не трогает — просто перезапустите: `systemctl restart systemd-resolved`.

---

## 🎉 Заключение

**FW_NULL** - это ваш спасательный круг, когда файрвол захлопнул дверь перед вашим носом. Помните: с великой силой приходит великая ответственность. Используйте скрипт для восстановления доступа, но не забывайте потом правильно настроить защиту сервера!

**Happy firewalling!** 🔥
