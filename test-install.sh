#!/bin/bash

set -e
# Gobal verbals

if [[ -f '/etc/systemd/system/kiosk.service' ]] && [[ -f '/usr/local/bin/kiosk' ]]; then
  XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=1
else
  XRAY_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=0
fi

# Функция для установки
install() {
    echo "Начало установки Media Project..."

    echo "Установка успешно завершена!"
}

# Функция для удаления
remove() {
    echo "Начало удаления Media Project..."

    echo "Удаление успешно завершено!"
}

main() {
    # Проверка на аргументы
    local action=${1:-"install"}  # По умолчанию — установка

    case "$action" in
        install)
            echo "▶️ Начало установки..."
            # Ваши команды установки
            ;;
        remove)
            echo "▶️ Удаление..."
            # Ваши команды удаления
            ;;
        *)
            echo "❌ Неизвестное действие: $action" >&2
            echo "Допустимые варианты: install, remove" >&2
            exit 1
            ;;
    esac

    echo "✅ Готово!"
}

# Передаём все аргументы в main
main "$@"
