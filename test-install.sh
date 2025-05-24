#!/usr/bin/env bash

# if [[ -f '/etc/systemd/system/kiosk.service' ]] && [[ -f '/usr/local/?/kiosk' ]]; then
#   KIOSK_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=1
# else
#   KIOSK_IS_INSTALLED_BEFORE_RUNNING_SCRIPT=0
# fi

PROJECT_DIR=/usr/local/?/kiosk
INSTALL_USER='nobody'

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
  
  local delete_files=('/usr/local/?/kiosk' '/etc/systemd/system/kiosk.service')
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
  file_to_detect="$2"
  type -P "$file_to_detect" >/dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name" >/dev/null 2>&1; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi
}

main() { 
  check_if_running_as_root || return 1
  identify_the_operating_system_and_architecture || return 1
  judgment_parameters "$@" || return 1
  
  [[ "$REMOVE" -eq '1' ]] && remove_kiosk

  install_software 'curl' 'curl'
  install_software "python3-pip" "pip3"
  

}


main "$@"
