from .settings import *

SECURE_SSL_REDIRECT = False
CELERY_TASK_ALWAYS_EAGER = True
REST_FRAMEWORK = {**REST_FRAMEWORK, 'DEFAULT_THROTTLE_CLASSES': []}
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
