#!/bin/bash

# Создание пользователя
sudo useradd -m kiosk

# Установка VLC и библиотек для работы с X
sudo apt-get update
sudo apt-get install -y vlc python3-vlc xvfb xserver-xorg-video-dummy


# Создание корневой директории проекта
PROJECT_DIR="/opt/kiosk"
sudo mkdir -p $PROJECT_DIR
sudo chown kiosk:kiosk $PROJECT_DIR


# Загрузка файлов с 
cd $PROJECT_DIR
sudo -u mediauser wget https://raw.githubusercontent.com/ваш_репозиторий/main/main.py
sudo -u mediauser wget https://raw.githubusercontent.com/ваш_репозиторий/main/download.mp4


# Создание виртуального окружения и установка библиотек
sudo -u mediauser python3 -m venv venv
sudo -u mediauser $PROJECT_DIR/venv/bin/pip install python-vlc requests


# Создание сервисного файла
SERVICE_FILE="/etc/systemd/system/media_project.service"
sudo bash -c "cat > $SERVICE_FILE" << EOL
[Unit]
Description=Media Project Service
After=network.target

[Service]
User=mediauser
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/main.py
Restart=always
# Для автоматического запуска при загрузке системы раскомментируйте следующую строку
# WantedBy=multi-user.target

[Install]
WantedBy=multi-user.target
EOL

# Перезагрузка демона systemd и запуск сервиса
sudo systemctl daemon-reload
sudo systemctl enable media_project.service
sudo systemctl start media_project.service

echo "Установка завершена!"
