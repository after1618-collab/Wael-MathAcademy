"""READ-ONLY verification of `video_path` existence via Supabase REST API (IPv4, working).
Selecting a non-existent column raises an API error, which tells us the column is missing.
No DDL is executed.
"""
import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv(".env")
url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_KEY") or os.getenv("SUPABASE_KEY")
supabase = create_client(url, key)

try:
    res = supabase.table("lessons").select("video_path").limit(1).execute()
    print("RESULT DATA:", res.data)
    print("=> video_path COLUMN EXISTS (select succeeded)")
except Exception as e:
    msg = str(e)
    print("ERROR MESSAGE:", msg)
    low = msg.lower()
    if "video_path" in msg and ("could not find" in low or "column" in low or "404" in low or "does not exist" in low):
        print("=> video_path COLUMN DOES NOT EXIST")
    else:
        print("=> INCONCLUSIVE (unexpected error)")
print("READ-ONLY CHECK DONE")
