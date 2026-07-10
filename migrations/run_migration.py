"""Migration runner — executes SQL read from .sql files (NO SQL embedded here).

Usage:
    python migrations/run_migration.py up      # apply
    python migrations/run_migration.py down    # revert

Requires psycopg2 and a reachable Supabase Postgres connection
(env: SUPABASE_URL + DB_PASSWORD). The SQL itself lives in the
001_add_lessons_video_path.up.sql / .down.sql files.
"""
import os
import sys
from dotenv import load_dotenv
import psycopg2
from urllib.parse import quote_plus

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
load_dotenv(os.path.join(BASE_DIR, ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

ref = SUPABASE_URL.replace("https://", "").replace("http://", "").split(".")[0]
db_host = f"db.{ref}.supabase.co"
password = quote_plus(DB_PASSWORD)
DB_URL = f"postgresql://postgres:{password}@{db_host}:5432/postgres?sslmode=require"

DIRECTION = sys.argv[1].lower() if len(sys.argv) > 1 else "up"
if DIRECTION not in ("up", "down"):
    print("Usage: python migrations/run_migration.py [up|down]")
    sys.exit(1)

SQL_FILE = os.path.join(BASE_DIR, "migrations", f"001_add_lessons_video_path.{DIRECTION}.sql")
if not os.path.exists(SQL_FILE):
    print(f"SQL file not found: {SQL_FILE}")
    sys.exit(1)

with open(SQL_FILE, "r", encoding="utf-8") as f:
    sql = f.read()

print(f"=== Applying {DIRECTION} migration from {SQL_FILE} ===")
print(sql.strip())
print("===========================================")

conn = psycopg2.connect(DB_URL)
conn.autocommit = True
try:
    cur = conn.cursor()
    # Execute each statement separately (split on ';') so multi-statement
    # migrations (e.g. ALTER + COMMENT ON COLUMN) run reliably across
    # psycopg2 versions. SQL is read from the .sql file, not embedded here.
    statements = [s.strip() for s in sql.split(";") if s.strip()]
    for stmt in statements:
        print(f"-> {stmt}")
        cur.execute(stmt)
    cur.close()
    print(f"Migration ({DIRECTION}) applied successfully.")
finally:
    conn.close()
