import os


bind = os.getenv("TH4DER_BIND", "127.0.0.1:8000")
workers = int(os.getenv("TH4DER_WORKERS", "2"))
worker_class = os.getenv("TH4DER_WORKER_CLASS", "gevent")
worker_connections = int(os.getenv("TH4DER_WORKER_CONNECTIONS", "1000"))
timeout = int(os.getenv("TH4DER_TIMEOUT", "120"))
graceful_timeout = int(os.getenv("TH4DER_GRACEFUL_TIMEOUT", "30"))
keepalive = int(os.getenv("TH4DER_KEEPALIVE", "5"))

accesslog = "-"
errorlog = "-"
loglevel = os.getenv("TH4DER_LOG_LEVEL", "info")

