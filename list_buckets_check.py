import boto3
from supabase import create_client
from pathlib import Path
from dotenv import load_dotenv
import os

BASE_DIR = Path(__file__).resolve().parent
ENV_PATH = BASE_DIR / ".env"
load_dotenv(dotenv_path=ENV_PATH)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

buckets = supabase.storage.list_buckets()

print("TYPE(buckets) =", type(buckets))
print("LEN(buckets) =", len(buckets))

for b in buckets:
    print(type(b))
    print(b)
    print(vars(b) if hasattr(b, "__dict__") else b)
    print("-" * 50)
