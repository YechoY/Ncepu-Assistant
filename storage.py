"""本地缓存：SQLite 存课表 / 成绩 / 考试数据，另存 cookie 与账号。
数据统一放在程序目录下的 data/ 文件夹，打包成 exe 后就是 exe 旁边的 data/。"""

import json
import shutil
import sqlite3
import sys
import time
from pathlib import Path


def _app_dir():
    """程序所在目录：源码运行是项目目录，打包成 exe 后是 exe 所在目录。"""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


DATA_DIR = _app_dir() / "data"
DB_PATH = DATA_DIR / "data.db"
COOKIE_PATH = DATA_DIR / "cookies.json"
ACCOUNT_PATH = DATA_DIR / "account.json"
OLD_DIR = Path.home() / ".ncepu_jwc"


def _migrate_old_data():
    """首次运行把旧位置（~/.ncepu_jwc）的数据搬到新位置。"""
    if DB_PATH.exists() or not OLD_DIR.exists():
        return
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("data.db", "cookies.json"):
        src = OLD_DIR / name
        dst = DATA_DIR / name
        if src.exists() and not dst.exists():
            try:
                shutil.copy2(src, dst)
            except OSError:
                pass


class Storage:
    """每个操作单独开一次连接，避免后台线程和界面线程共用连接报错。"""

    @staticmethod
    def _connect():
        _migrate_old_data()
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "CREATE TABLE IF NOT EXISTS kv "
            "(key TEXT PRIMARY KEY, value TEXT, updated_at REAL)"
        )
        return conn

    def save(self, key, value):
        conn = self._connect()
        try:
            conn.execute(
                "INSERT OR REPLACE INTO kv(key, value, updated_at) VALUES (?, ?, ?)",
                (key, json.dumps(value, ensure_ascii=False), time.time()),
            )
            conn.commit()
        finally:
            conn.close()

    def load(self, key, default=None):
        conn = self._connect()
        try:
            row = conn.execute(
                "SELECT value FROM kv WHERE key=?", (key,)
            ).fetchone()
            return json.loads(row[0]) if row else default
        finally:
            conn.close()

    def last_update(self, key):
        conn = self._connect()
        try:
            row = conn.execute(
                "SELECT updated_at FROM kv WHERE key=?", (key,)
            ).fetchone()
            return row[0] if row else None
        finally:
            conn.close()

    def save_cookies(self, cookies):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        COOKIE_PATH.write_text(json.dumps(cookies), encoding="utf-8")

    def load_cookies(self):
        if COOKIE_PATH.exists():
            return json.loads(COOKIE_PATH.read_text(encoding="utf-8"))
        return {}

    def save_account(self, username, password):
        """记住账号密码（明文保存在本地，仅建议个人电脑使用）。"""
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        ACCOUNT_PATH.write_text(
            json.dumps({"username": username, "password": password}, ensure_ascii=False),
            encoding="utf-8",
        )

    def load_account(self):
        if ACCOUNT_PATH.exists():
            try:
                return json.loads(ACCOUNT_PATH.read_text(encoding="utf-8"))
            except (ValueError, OSError):
                return {}
        return {}

    def clear_account(self):
        if ACCOUNT_PATH.exists():
            ACCOUNT_PATH.unlink()
