import os
import sys

# Ensure Server/ is on the import path for Vercel
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_DIR = os.path.join(ROOT_DIR, "Server")
if SERVER_DIR not in sys.path:
    sys.path.insert(0, SERVER_DIR)

from main import app  # noqa: E402
