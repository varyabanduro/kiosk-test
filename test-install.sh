#!/bin/bash

set -e

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

# Обработка аргументов
case "$1" in
    install)
        install
        ;;
    remove)
        remove
        ;;
    *)
        echo "Использование: $0 [install|remove]"
        exit 1
        ;;
esac
