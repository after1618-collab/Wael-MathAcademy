import os
from dataclasses import dataclass


@dataclass(frozen=True)
class StorageConfig:
    provider: str

    # Supabase
    supabase_url: str
    supabase_key: str
    default_bucket: str

    # Cloudflare R2
    r2_endpoint: str
    r2_access_key: str
    r2_secret_key: str
    r2_bucket: str
    r2_region: str
    r2_public_url: str

    # Bucket names (single source of truth)
    questions_bucket: str
    video_bucket: str


print("CONFIG SUPABASE_URL =", os.getenv("SUPABASE_URL"))
print("CONFIG SUPABASE_KEY EXISTS =", bool(os.getenv("SUPABASE_KEY")))

config = StorageConfig(
    provider=os.getenv("STORAGE_PROVIDER", "supabase").lower(),

    supabase_url=os.getenv("SUPABASE_URL", ""),
    supabase_key=os.getenv("SUPABASE_KEY", ""),
    default_bucket=os.getenv("SUPABASE_BUCKET", ""),

    r2_endpoint=os.getenv("R2_ENDPOINT", ""),
    r2_access_key=os.getenv("R2_ACCESS_KEY", ""),
    r2_secret_key=os.getenv("R2_SECRET_KEY", ""),
    r2_bucket=os.getenv("R2_BUCKET", ""),
    r2_region=os.getenv("R2_REGION", "auto"),
    r2_public_url=os.getenv("R2_PUBLIC_URL", ""),

    questions_bucket=os.getenv("QUESTIONS_BUCKET", "questions"),

    video_bucket=os.getenv("VIDEO_BUCKET", os.getenv("R2_BUCKET", "")),
)
