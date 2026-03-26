import os
from supabase import create_client
from dotenv import load_dotenv

# -------- تحميل المتغيرات من .env --------
load_dotenv()

# -------- إعداد الاتصال --------
url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_KEY")

if not url or not key:
    raise RuntimeError("❌ SUPABASE_URL و SUPABASE_SERVICE_KEY لازم يكونوا متضافين فى .env")

supabase = create_client(url, key)

# -------- بيانات الطالب للتجربة --------
# لازم تحط ID طالب من جدول students (uuid)
STUDENT_ID = "39b88560-48ef-480b-afef-40d070ca422b"
DEVICE_ID_1 = "device-laptop"
DEVICE_ID_2 = "device-phone"

def start_session(student_id, device_id):
    try:
        res = supabase.rpc("start_session", {
            "p_student_id": student_id,
            "p_device_id": device_id
        }).execute()
        print("Start session:", res.data)
        return res.data
    except Exception as e:
        print("❌ Error in start_session:", e)
        return None

def end_session(token):
    try:
        res = supabase.rpc("end_session", {"p_token": token}).execute()
        print("End session:", res.data)
    except Exception as e:
        print("❌ Error in end_session:", e)

if __name__ == "__main__":
    print("✅ اختبار إدارة الجلسات (جلسة واحدة فقط)")

    # تسجيل دخول من جهاز 1
    token1 = supabase.rpc("start_single_session", {
        "p_student_id": STUDENT_ID,
        "p_device_id": DEVICE_ID_1
    }).execute().data
    print("Start session (device1):", token1)

    # تسجيل دخول من جهاز 2 → يقفل القديمة أوتوماتيك
    token2 = supabase.rpc("start_single_session", {
        "p_student_id": STUDENT_ID,
        "p_device_id": DEVICE_ID_2
    }).execute().data
    print("Start session (device2):", token2)

    # عرض الجلسات الفعالة
    active_sessions = supabase.rpc("list_active_sessions", {
        "p_student_id": STUDENT_ID
    }).execute().data
    print("Active sessions:", active_sessions)
