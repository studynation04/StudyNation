"""Gunicorn config for Hostinger VPS (Nginx reverse proxy).

Override bind with GUNICORN_BIND, e.g.:
  unix:/run/studynation.sock
  127.0.0.1:8000
"""

import multiprocessing
import os

bind = os.environ.get("GUNICORN_BIND", "127.0.0.1:8000")
workers = int(os.environ.get("WEB_CONCURRENCY", max(2, multiprocessing.cpu_count())))
threads = int(os.environ.get("GUNICORN_THREADS", "2"))
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "120"))
graceful_timeout = 30
keepalive = 5
max_requests = 1000
max_requests_jitter = 50
worker_class = "gthread"
wsgi_app = "config.wsgi:application"
accesslog = "-"
errorlog = "-"
capture_output = True
preload_app = False
worker_tmp_dir = os.environ.get("GUNICORN_WORKER_TMPDIR", "/tmp")
