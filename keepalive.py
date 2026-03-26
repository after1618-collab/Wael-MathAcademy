from supabase import create_client
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_ANON_KEY")

supabase = create_client(url, key)

# عمل استعلام بسيط لإبقاء المشروع نشط
result = supabase.table('students').select("id").limit(1).execute()
print(f"✅ Supabase is alive! {result}")