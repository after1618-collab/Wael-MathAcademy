import os
from supabase import create_client
from dotenv import load_dotenv

# تحميل متغيرات البيئة
load_dotenv()
url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_KEY")

if not url or not key:
    raise RuntimeError("❌ لازم تضيف SUPABASE_URL و SUPABASE_SERVICE_KEY فى ملف .env")

supabase = create_client(url, key)

# حط هنا IDs حقيقية من جدول students و questions
STUDENT_ID = "a8321a93-fbb5-4762-b719-b58c3347f43b"
QUESTION_ID = "ea481ac0-5d2b-4985-9d89-68f5865f69a9"

print("✅ اختبار تسجيل المحاولات")

try:
    # إضافة محاولة جديدة
    res = supabase.rpc("add_attempt", {
        "p_student_id": STUDENT_ID,
        "p_question_id": QUESTION_ID,
        "p_submitted_answer": "B",
        "p_revealed": False
    }).execute()

    print("Add attempt result:", res.data)

    # عرض محاولات الطالب
    res2 = supabase.rpc("get_attempts", {"p_student_id": STUDENT_ID}).execute()
    print("Attempts:", res2.data)

except Exception as e:
    print("❌ Error:", str(e))
