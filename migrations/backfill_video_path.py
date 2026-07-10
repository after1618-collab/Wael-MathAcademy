"""
backfill_video_path.py  (Phase 4 data migration)

Populates `lessons.video_path` from existing direct-uploaded videos' `video_url`.

Why:
    lessons.video_url historically mixed two concepts:
      * external URLs (YouTube / Vimeo / Google Drive)
      * provider-generated URLs for directly uploaded videos
    The new model stores the provider-independent storage key in `video_path`
    and generates the URL at read time via storage.get_url(). This script
    backfills `video_path` for legacy direct uploads so the read endpoints can
    resolve them the same way as new uploads.

Safety guarantees:
    * Idempotent: only rows with `video_path IS NULL` are considered, so
      re-running only fills still-missing rows and never overwrites a value.
    * External URLs are NEVER modified. A row is only touched when its
      `video_url` is a storage URL (Supabase public or R2 public); YouTube /
      Vimeo / Drive links are skipped untouched.
    * Optional R2 existence check (`--verify`) so we never point `video_path`
      at an object that isn't in R2 yet (which would 404). When R2 credentials
      are missing the check is skipped with a warning.
    * `--dry-run` previews every change without writing.

Usage:
    python migrations/backfill_video_path.py --dry-run
    python migrations/backfill_video_path.py            # apply
    python migrations/backfill_video_path.py --verify   # also confirm object in R2
"""
import os
import re
import sys
import argparse
from pathlib import Path
from urllib.parse import urlparse

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(dotenv_path=BASE_DIR / ".env")

try:
    from supabase import create_client
except ImportError:
    print("ERROR: supabase-py not installed (pip install supabase)", file=sys.stderr)
    sys.exit(1)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    print("ERROR: SUPABASE_URL / SUPABASE_SERVICE_KEY missing", file=sys.stderr)
    sys.exit(1)

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# --- R2 (optional verification) ---
R2_ACCOUNT_ID = os.getenv("R2_ACCOUNT_ID")
R2_ACCESS_KEY = os.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_KEY = os.getenv("R2_SECRET_ACCESS_KEY")
R2_BUCKET = os.getenv("R2_BUCKET", "wael-math-storage")
R2_PUBLIC_URL = (os.getenv("R2_PUBLIC_URL") or "").rstrip("/")

# Supabase public storage URL pattern (bucket-agnostic: the bucket name segment
# is stripped so the returned key is the object path, e.g. "courses/.../file.mp4").
SUPABASE_PUBLIC_RE = re.compile(r"/storage/v1/object/public/[^/]+/(.+)$")


def extract_key(video_url: str) -> str | None:
    """Return the R2 storage key for a direct-upload video_url, else None."""
    if not video_url:
        return None
    # 1) Supabase public storage URL -> object path after the bucket segment.
    m = SUPABASE_PUBLIC_RE.search(video_url)
    if m:
        return m.group(1).strip("/")
    # 2) R2 public URL: r2.dev host OR the configured custom public URL
    #    (R2_PUBLIC_URL from .env covers both r2.dev and any future custom domain).
    is_r2 = ("r2.dev" in video_url) or (R2_PUBLIC_URL and video_url.startswith(R2_PUBLIC_URL))
    if is_r2:
        path = urlparse(video_url).path.lstrip("/")
        return path or None
    # Anything else (YouTube / Vimeo / Drive / unknown) is not a storage key.
    return None


def r2_object_exists(key: str) -> bool:
    """Best-effort R2 existence check. Returns True if it can't be verified."""
    if not (R2_ACCOUNT_ID and R2_ACCESS_KEY and R2_SECRET_KEY):
        print("  [warn] R2 credentials missing -> skipping existence check")
        return True
    try:
        import boto3
        from botocore.exceptions import ClientError
    except ImportError:
        print("  [warn] boto3 missing -> skipping existence check")
        return True
    try:
        s3 = boto3.client(
            "s3",
            endpoint_url=f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
            aws_access_key_id=R2_ACCESS_KEY,
            aws_secret_access_key=R2_SECRET_KEY,
        )
        s3.head_object(Bucket=R2_BUCKET, Key=key)
        return True
    except ClientError:
        return False
    except Exception as e:
        print(f"  [warn] R2 check failed ({e}) -> assuming exists")
        return True


def main() -> None:
    ap = argparse.ArgumentParser(description="Backfill lessons.video_path from video_url")
    ap.add_argument("--dry-run", action="store_true", help="Preview only, no writes")
    ap.add_argument("--verify", action="store_true", help="Verify object exists in R2 before writing")
    args = ap.parse_args()

    # Only rows that still lack video_path and have some video_url.
    res = (
        supabase.table("lessons")
        .select("id, video_url, video_path, video_type")
        .is_("video_path", "null")
        .not_.is_("video_url", "null")
        .execute()
    )
    rows = res.data or []
    print(f"Found {len(rows)} lessons with NULL video_path and a video_url")

    updated = 0
    skipped_external = 0
    skipped_missing_r2 = 0

    for row in rows:
        row_id = row.get("id")
        vid = row.get("video_url") or ""
        key = extract_key(vid)
        if not key:
            # Not a storage URL -> external/unknown; leave completely untouched.
            skipped_external += 1
            print(f"  SKIP (external/unknown) id={row_id} type={row.get('video_type')} url={vid[:80]}")
            continue
        if args.verify and not r2_object_exists(key):
            skipped_missing_r2 += 1
            print(f"  SKIP (not in R2)       id={row_id} key={key}")
            continue
        if args.dry_run:
            print(f"  WOULD SET id={row_id} video_path={key}")
            updated += 1
            continue
        supabase.table("lessons").update({"video_path": key}).eq("id", row_id).is_("video_path", "null").execute()
        updated += 1
        print(f"  SET id={row_id} video_path={key}")

    print("\n--- Summary ---")
    print(f"Updated (or would update): {updated}")
    print(f"Skipped (external/unknown): {skipped_external}")
    print(f"Skipped (not in R2)      : {skipped_missing_r2}")
    print("Done.")


if __name__ == "__main__":
    main()
