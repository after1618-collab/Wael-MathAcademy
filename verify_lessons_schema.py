"""READ-ONLY verification: print the `lessons` table schema. No DDL executed."""
import os
from dotenv import load_dotenv
import psycopg2
from urllib.parse import quote_plus

load_dotenv(".env")
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

ref = SUPABASE_URL.replace("https://", "").replace("http://", "").split(".")[0]
db_host = f"db.{ref}.supabase.co"
password = quote_plus(DB_PASSWORD)
DB_URL = f"postgresql://postgres:{password}@{db_host}:5432/postgres?sslmode=require"

conn = psycopg2.connect(DB_URL)
try:
    cur = conn.cursor()
    cur.execute(
        "SELECT column_name, data_type, is_nullable "
        "FROM information_schema.columns "
        "WHERE table_name = 'lessons' ORDER BY ordinal_position;"
    )
    rows = cur.fetchall()
    print(f"=== lessons table schema ({len(rows)} columns) ===")
    for r in rows:
        print(r)
    cur.close()
finally:
    conn.close()
print("READ-ONLY CHECK DONE")
