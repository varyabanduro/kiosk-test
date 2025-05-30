import os
import vlc
import time
import subprocess
import signal
import requests
import logging
import threading
import tkinter as tk
from contextlib import contextmanager
from dotenv import load_dotenv


logging.basicConfig(level=logging.INFO)

MEDIA_PATH = "/usr/local/bin/kiosk/media"
BASE_PATH = "/usr/local/bin/kiosk/files"
CONFIG_FILE = "/usr/local/etc/kiosk/config.env"
BASE_URL = "https://cloud-api.yandex.net/v1/disk/public/resources?public_key="
load_dotenv(dotenv_path=CONFIG_FILE)
PUBLIC_PATH = os.getenv("PUBLIC_PATH", None)
SHOW_TIME = os.getenv("SHOW_TIME", 2)

@contextmanager
def x_server():
    """
    Контекстный менеджер для запуска/остановки X-сервера.
    """
    display=":0"
    args = ["X", display, "-ac"]
    proc = subprocess.Popen(
        args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid
    )
    os.environ["DISPLAY"] = display

    try:
        yield proc
    finally:
        logging.info("STOP X")
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass



class Media:
    def __init__(self):
        self.path = MEDIA_PATH
        self.base_url = BASE_URL
        self.public_url = PUBLIC_PATH
        self.download = None
        self.lock = threading.Lock()

    def _fetch_url(self) -> dict:
        if not self.public_url:
            raise ValueError(f"Add PUBLIC_PATH in {CONFIG_FILE}\n"
                             " and restart kisosk.service")
        resp = requests.get(self.base_url + self.public_url)
        if resp.status_code != 200:
            raise ValueError(f"API error status code: {resp.status_code}")
        data = resp.json()
        if data.get("type", None) != "dir":
            raise ValueError("The link does not lead to the folder")
        return data

    def _get_local_media(self):
        """Список файлов в текущей папке в формате {}"""
        list_media = {}
        try:
            with os.scandir(self.path) as it:
                for entry in it:
                    if entry.is_file():
                        list_media[(entry.name, os.path.getsize(entry))] = os.path.join(self.path, entry.name)
        except Exception as e:
            logging.error(f"Ошбка чтения папки {e}")
        else:
            logging.info(f"Файлы {self.path} ОК: {len(list_media)} шт")
        return list_media

    def _get_disk_media(self):
        """Список файлов на Я Диске """
        media_links = {}
        data = {}
        try:
            data = self._fetch_url()
        except Exception as e:
            logging.error(str(e))
            return str(e)
        else:
            logging.info(f"Запрос к {self.public_url} ОК")

        for item in data.get("_embedded", {}).get("items", []):
            if item.get("media_type", None):
                media_links[(item.get("name"), item.get("size"))] = item.get("file")
        logging.info(f"ЯДиск файлы ОК: {len(media_links)} шт")
        return media_links


    def _delete_file(self, file_path):
        """Удалить файл на диске"""
        try:
            os.remove(file_path)
        except Exception as e:
            logging.error(f"Ошибка при удалении {file_path}")
        else:
            logging.info(f"{file_path} удалён:ОК")


    def _download_file(self, filename, url):
        """Загрузить файл по URL в указанную папку"""
        try:
            response = requests.get(url, stream=True)
            response.raise_for_status()

            save_path = os.path.join(self.path, filename)

            with open(save_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)

        except Exception as e:
            logging.warning(f"Ошибка скачивания {filename}: {e}")
        else:
            logging.info(f"Файл {filename} скачен")


    def sync_media(self):
        """Пиводит папку в соответствие с ЯДиском"""
        folder = self._get_local_media()
        disk = self._get_disk_media()
        if isinstance(disk, str):
            with self.lock:
                self.download = disk
            return 
        delete_media = folder.keys() - disk.keys()
        download_media = disk.keys() - folder.keys()

        logging.info(f"{len(delete_media)} для удаления")
        for i in delete_media:
            self._delete_file(folder[i])

        logging.info(f"{len(download_media)} для загрузки")
        for i in download_media:
            with self.lock:
                self.download = f"Файл {i[0]} загружается"
            self._download_file(i[0], disk[i])
            with self.lock:
                self.download = None

    def get_links(self):
        """Список ссылок к воспроизведению"""
        media_list = self._get_local_media()
        return media_list.values()


class NewVLC:
    def __init__(self, media):
        self.thread = None
        self.widget = tk.Tk()
        screen_width = self.widget.winfo_screenwidth()  # Ширина экрана
        screen_height = self.widget.winfo_screenheight()  # Высота экрана
        self.widget.geometry(f"{screen_width}x{screen_height}+0+0")

        self.vlc_instance = vlc.Instance(
            "--quiet",
            "--no-xlib",
            "--avcodec-hw=none",
            "--autoscale",
            "--fullscreen",
            "--no-mouse-events",
            "--no-audio",
            f"--image-duration={SHOW_TIME}"
            )

        self.base_player = self.vlc_instance.media_player_new()
        self.base_player.set_xwindow(self.widget.winfo_id())
        self.base_player.video_set_marquee_int(vlc.VideoMarqueeOption.Size, 22)
        self.base_player.video_set_marquee_int(vlc.VideoMarqueeOption.Position, 8)
        self.base_player.event_manager(
            ).event_attach(
                vlc.EventType.MediaPlayerEndReached,
                self._update_manager,
                media
                )
        
        self.list_player = self.vlc_instance.media_list_player_new()
        self.list_player.set_media_player(self.base_player)
        self.list_player.set_playback_mode(vlc.PlaybackMode.loop)

        self._update_manager(None, media)

    def _update_manager(self, event, media):
        if not self.thread or not self.thread.is_alive():
            logging.info(f"Старт синхронизации")
            self.thread = threading.Thread(target=media.sync_media)
            self.thread.start()
            time.sleep(1)

        match media.download:
            case str():
                logging.info(media.download)
                self.base_player.video_set_marquee_int(vlc.VideoMarqueeOption.Enable, 1)
                self.base_player.video_set_marquee_string(vlc.VideoMarqueeOption.Text, media.download)
                links = [ os.path.join(BASE_PATH, "download.mp4"),]
            case None:
                logging.info(f"Файлы не требую загрузки")
                self.base_player.video_set_marquee_int(vlc.VideoMarqueeOption.Enable, 0)
                links = media.get_links()
                if links == []:
                    links = [os.path.join(BASE_PATH, "logo.jpg"),]

        self.media_list = self.vlc_instance.media_list_new(links)
        self.list_player.set_media_list(self.media_list)
        self.list_player.play()


with x_server() as x:
    time.sleep(1)
    media = Media()
    NewVLC(media)
    while True:
        pass
