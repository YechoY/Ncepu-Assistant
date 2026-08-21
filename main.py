"""NCEPU 教务助手：pywebview + Vue 桌面端入口。"""

import os
import sys

import webview

from bridge import Api


def resource_path(relative):
    """打包成 exe 后资源在临时解压目录，源码运行时就是项目目录。"""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, relative)


if __name__ == "__main__":
    api = Api()
    index_html = resource_path(os.path.join("web", "index.html"))
    webview.create_window(
        "NCEPU 教务助手",
        index_html,
        js_api=api,
        width=1120,
        height=780,
        min_size=(960, 660),
        background_color="#EEF2FF",
    )
    webview.start()
    # 窗口关闭后按规则清理本地保存的账号密码
    api.cleanup_on_close()
