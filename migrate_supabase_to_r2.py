import boto3
from botocore.exceptions import ClientError
from supabase import create_client
from pathlib import Path
from dotenv import load_dotenv
import os

BASE_DIR = Path(__file__).resolve().parent
ENV_PATH = BASE_DIR / ".env"

print("ENV PATH =", ENV_PATH)
print("FILE EXISTS =", ENV_PATH.exists())

load_dotenv(dotenv_path=ENV_PATH)

print("SUPABASE_URL =", repr(os.getenv("SUPABASE_URL")))
print("SUPABASE_SERVICE_ROLE_KEY exists =", os.getenv("SUPABASE_SERVICE_ROLE_KEY") is not None)

# =========================
# Supabase
# =========================

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

print("ENV FILE:", os.path.abspath(".env"))
print("SUPABASE_URL =", os.getenv("SUPABASE_URL"))
print("SUPABASE_SERVICE_ROLE_KEY =", os.getenv("SUPABASE_SERVICE_ROLE_KEY"))

print("=" * 50)
print("Current file:", __file__)
print("Working dir :", os.getcwd())

print("SUPABASE_URL =", repr(SUPABASE_URL))
print("SUPABASE_SERVICE_KEY exists =", SUPABASE_SERVICE_KEY is not None)
print("SUPABASE_SERVICE_KEY length =", len(SUPABASE_SERVICE_KEY) if SUPABASE_SERVICE_KEY else 0)
print("=" * 50)

supabase = create_client(
    SUPABASE_URL,
    SUPABASE_SERVICE_KEY
)

# =========================
# Buckets
# =========================

EXCLUDED_BUCKETS = set()  # لا استثناء افتراضيًا؛ أضف مؤقتًا عند الحاجة


def get_buckets():
    buckets = []

    for bucket in supabase.storage.list_buckets():

        if bucket.name in EXCLUDED_BUCKETS:
            print(f"Skipping excluded bucket: {bucket.name}")
            continue

        buckets.append(bucket.name)

    return buckets


# =========================
# Cloudflare R2
# =========================

R2_ACCOUNT_ID = os.getenv("R2_ACCOUNT_ID")
R2_ACCESS_KEY = os.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_KEY = os.getenv("R2_SECRET_ACCESS_KEY")

R2_BUCKET = "wael-math-storage"

s3 = boto3.client(
    "s3",
    endpoint_url=f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
    aws_access_key_id=R2_ACCESS_KEY,
    aws_secret_access_key=R2_SECRET_KEY,
)


# =========================
# Migration
# =========================

def upload_file(bucket, path):

    try:
        # Resume support: if the object already exists in R2, skip the upload.
        # Avoids re-downloading/re-uploading and makes the script safe to run
        # any number of times (idempotent / resumable).
        try:
            s3.head_object(Bucket=R2_BUCKET, Key=path)
            print(f"Skipping (already in R2): {path}")
            return
        except ClientError:
            pass  # Not in R2 yet -> proceed with the upload

        print(f"Uploading: {path}")

        data = supabase.storage.from_(bucket).download(path)

        s3.put_object(
            Bucket=R2_BUCKET,
            Key=path,
            Body=data
        )

        # True move: delete from Supabase only after a successful copy to R2
        supabase.storage.from_(bucket).remove([path])
        print("Done (copied to R2 & removed from Supabase)")

    except Exception as e:
        print("Failed:", path)
        print(e)


def migrate_folder(bucket, folder=""):

    files = supabase.storage.from_(bucket).list(
        folder
    )

    for item in files:

        name = item["name"]

        full_path = (
            f"{folder}/{name}"
            if folder
            else name
        )

        # لو مجلد
        if "." not in name:
            migrate_folder(bucket, full_path)

        else:
            upload_file(bucket, full_path)


if __name__ == "__main__":

    print("Starting migration...")

    for bucket in get_buckets():

        print("=" * 60)
        print(f"Migrating bucket: {bucket}")
        print("=" * 60)

        migrate_folder(bucket)

    print("\nFinished.")