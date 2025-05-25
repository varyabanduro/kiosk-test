#!/usr/bin/env bash

# if [[ -f '/etc/systemd/system/kiosk.service' ]] && [[ -f '/usr/local/?/kiosk' ]]; then
#   KIOSK_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=1
# else
#   KIOSK_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=0
# fi

PROJECT_DIR=/usr/local/bin/kiosk
CONFIG_FILE=/usr/local/etc/kiosk/config.env
INSTALL_USER='nobody'

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

identify_the_operating_system_and_architecture() {
  if [[ "$(uname)" != 'Linux' ]]; then
    echo "error: This operating system is not supported."
    return 1
  fi
  if [[ -d /run/systemd/system ]] || grep -q systemd <(ls -l /sbin/init); then
    true
  else
    echo "error: Only Linux distributions using systemd are supported."
    return 1
  fi
  if [[ "$(type -P apt)" ]]; then
    PACKAGE_MANAGEMENT_INSTALL='apt -y install'
    PACKAGE_MANAGEMENT_REMOVE='apt purge'
  else
    echo "error: The script does not support the package manager in this operating system."
    return 1
  fi
}
  
check_if_running_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  else
    echo "error: You must run this script as root!"
    return 1
  fi
}

judgment_parameters() {
  while [[ "$#" -gt '0' ]]; do
    case "$1" in
    'install')
      INSTALL='1'
      ;;
    'remove')
      REMOVE='1'
      ;;
    *)
      echo "$0: unknown option -- $1"
      return 1
      ;;
    esac
    shift
  done

  if ((INSTALL + REMOVE == 0)); then
    INSTALL='1'
  elif ((INSTALL + REMOVE > 1)); then
    echo 'You can only choose one action.'
    return 1
  fi
}

remove_kiosk() {
  if ! systemctl is-enabled kiosk.service >/dev/null 2>&1; then
    echo 'error: kiosk service is not installed.'
    exit 1
  fi
  
  local delete_files=('/usr/local/bin/kiosk' '/etc/systemd/system/kiosk.service' '/usr/local/etc/kiosk')
  [[ -d "$PROJECT_DIR" ]] && delete_files+=("$PROJECT_DIR")
  
  if ! systemctl disable kiosk.service; then
    echo 'error: Failed to disable kiosk service.'
    exit 1
  fi
    
  if ! rm -rf "${delete_files[@]}"; then
    echo 'error: Failed to remove kiosk files.'
    exit 1
  fi

  for file in "${delete_files[@]}"; do
    echo "removed: $file"
  done
  
  systemctl daemon-reload
  echo "You may need to execute a command to remove dependent software: $PACKAGE_MANAGEMENT_REMOVE"
  exit 0
}

install_software() {
  package_name="$1"
  
  if apt list --installed "$package_name" 2>/dev/null | grep -q "^$package_name/"; then
    echo "info: $package_name is already installed."
    return 0
  fi
  
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name" >/dev/null 2>&1; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi
}

install_venv() {
  python3 -m venv "$PROJECT_DIR/.venv" || {
    echo "error: Не удалось создать виртуальное окружение"
    return 1
  }

  cat > "${PROJECT_DIR}/requirements.txt" <<EOF
python-vlc
requests
EOF
  
  PIP="${PROJECT_DIR}/.venv/bin/pip"
  "$PIP" install --upgrade pip
  "$PIP" install -r "${PROJECT_DIR}/requirements.txt" || {
      echo "error: Не удалось установить зависимости"
      return 1
    }

}

download_kiosk() {
  DOWNLOAD_LINK="https://github.com/varyabanduro/kiosk-test/raw/main"

  if curl -f -o "${PROJECT_DIR}/main.py" "${DOWNLOAD_LINK}/main.py"; then
    echo "main.py downloaded to ${PROJECT_DIR}"
  else
    echo "error: Failed to download main.py"
    return 1
  fi

  if curl -f -o "${PROJECT_DIR}/files/download.mp4" "${DOWNLOAD_LINK}/download.mp4"; then
    echo "download.mp4 downloaded to ${PROJECT_DIR}/files"
  else
    echo "error: Failed to download download.mp4"
    return 1
  fi
    
}

install_kiosk_service() {
  local SERVICE_FILE="/etc/systemd/system/kiosk.service"
  local PYTHON_EXEC="${PROJECT_DIR}/venv/bin/python"
  local MAIN_SCRIPT="${PROJECT_DIR}/main.py"

  cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Kiosk Python Service
After=network.target

[Service]
User=nobody
WorkingDirectory=${PROJECT_DIR}
ExecStart=${PYTHON_EXEC} ${MAIN_SCRIPT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "$SERVICE_FILE"
  echo "info: kiosk.service unit-файл создан."

  #systemctl daemon-reload
  #systemctl enable kiosk.service
  #systemctl restart kiosk.service
  echo "info: kiosk.service включён и запущен."
}

main() { 
  check_if_running_as_root || return 1
  identify_the_operating_system_and_architecture || return 1
  judgment_parameters "$@" || return 1
  
  [[ "$REMOVE" -eq '1' ]] && remove_kiosk

  install_software 'curl'
  install_software "vlc"
  install_software "python3-pip"
  install_software "python3-venv" 
  install_software "python3-tk"

  install -o nobody -g nogroup -m 755 -d \
    "$PROJECT_DIR" \
    "$PROJECT_DIR/files" \
    "$PROJECT_DIR/media" 
    
  install_venv || return 1
  download_kiosk || return 1
  install_kiosk_service

}


main "$@"
