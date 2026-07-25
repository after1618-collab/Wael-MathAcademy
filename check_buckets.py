import boto3
from supabase import create_client
from pathlib import Path
from dotenv import load_dotenv
import os

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(dotenv_path=BASE_DIR / ".env")
supabase = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_SERVICE_KEY"))


def count(bucket, folder=""):
    total = 0
    for item in supabase.storage.from_(bucket).list(folder):
        name = item["name"]
        if "." not in name:
            total += count(bucket, (folder + "/" + name) if folder else name)
        else:
            total += 1
    return total


for b in supabase.storage.list_buckets():
    print(b.name, "->", count(b.name), "files")
