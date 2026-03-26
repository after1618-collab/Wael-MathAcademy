import os
from supabase import create_client
from dotenv import load_dotenv

# تحميل المتغيرات
load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")  # نستخدم service_role هنا
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ======================
# 🎓 Students API
# ======================

def add_student(full_name, email, class_name=None):
    """إضافة طالب جديد"""
    res = supabase.rpc("add_student", {
        "p_full_name": full_name,
        "p_email": email,
        "p_class": class_name
    }).execute()
    return res.data

def update_student(student_id, full_name=None, email=None, class_name=None):
    """تحديث بيانات طالب"""
    res = supabase.rpc("update_student", {
        "p_student_id": student_id,
        "p_full_name": full_name,
        "p_email": email,
        "p_class": class_name
    }).execute()
    return res.data

def delete_student(student_id):
    """حذف طالب"""
    res = supabase.rpc("delete_student", {"p_student_id": student_id}).execute()
    return res.data

def list_students():
    """عرض جميع الطلاب"""
    res = supabase.rpc("get_all_students").execute()
    return res.data

# ======================
# 🔑 Sessions API
# ======================

def start_session(student_id, device_id):
    """بدء جلسة جديدة لطالب"""
    res = supabase.rpc("start_session", {
        "p_student_id": student_id,
        "p_device_id": device_id
    }).execute()
    return res.data

def end_session(token):
    """إنهاء جلسة"""
    res = supabase.rpc("end_session", {"p_token": token}).execute()
    return res.data

def list_active_sessions(student_id):
    """عرض الجلسات الفعالة لطالب"""
    res = supabase.rpc("list_active_sessions", {"p_student_id": student_id}).execute()
    return res.data
# ======================
# 📚 Sections API
# ======================

def add_section(name, description=None):
    """إضافة سيكشن جديد"""
    res = supabase.rpc("add_section", {
        "p_name": name,
        "p_description": description
    }).execute()
    return res.data

def update_section(section_id, name, description=None):
    """تحديث بيانات سيكشن"""
    res = supabase.rpc("update_section", {
        "p_section_id": section_id,
        "p_name": name,
        "p_description": description
    }).execute()
    return res.data

def delete_section(section_id):
    """حذف سيكشن"""
    res = supabase.rpc("delete_section", {"p_section_id": section_id}).execute()
    return res.data

def list_sections():
    """عرض جميع السيكشنات"""
    res = supabase.rpc("list_sections").execute()
    return res.data


# ======================
# ❓ Questions API
# ======================

def add_question(section_id, correct_answer, image_path=None, question_text=None, answer_type="mcq"):
    """إضافة سؤال جديد"""
    res = supabase.table("questions").insert({
        "section_id": section_id,
        "correct_answer": correct_answer,
        "image_path": image_path,
        "question_text": question_text,
        "answer_type": answer_type
    }).execute()
    return res.data

def update_question(question_id, **kwargs):
    """تحديث سؤال موجود"""
    res = supabase.table("questions").update(kwargs).eq("id", question_id).execute()
    return res.data

def delete_question(question_id):
    """حذف سؤال"""
    res = supabase.table("questions").delete().eq("id", question_id).execute()
    return res.data

def list_questions(section_id=None):
    """عرض الأسئلة (بالتصفية على قسم معين لو محتاج)"""
    query = supabase.table("questions").select("*")
    if section_id:
        query = query.eq("section_id", section_id)
    res = query.execute()
    return res.data


# ======================
# 📝 Attempts API
# ======================

def add_attempt(student_id, question_id, submitted_answer, revealed=False):
    """تسجيل محاولة جديدة"""
    res = supabase.rpc("add_attempt", {
        "p_student_id": student_id,
        "p_question_id": question_id,
        "p_submitted_answer": submitted_answer,
        "p_revealed": revealed
    }).execute()
    return res.data

def get_attempts(student_id):
    """عرض المحاولات الخاصة بطالب معين"""
    res = supabase.rpc("get_attempts", {"p_student_id": student_id}).execute()
    return res.data

def admin_get_attempts(student_id=None, question_id=None):
    """عرض كل المحاولات (للمدرّس)"""
    res = supabase.rpc("admin_get_attempts", {
        "p_student_id": student_id,
        "p_question_id": question_id
    }).execute()
    return res.data


# ======================
# 📊 Reports API
# ======================

def student_report(start_date=None, end_date=None):
    res = supabase.rpc("get_student_report", {
        "start_date_param": start_date,
        "end_date_param": end_date
    }).execute()
    return res.data

def question_report(start_date=None, end_date=None):
    res = supabase.rpc("get_question_report", {
        "start_date_param": start_date,
        "end_date_param": end_date
    }).execute()
    return res.data

def section_report(start_date=None, end_date=None):
    res = supabase.rpc("get_section_report", {
        "start_date_param": start_date,
        "end_date_param": end_date
    }).execute()
    return res.data

def global_report(start_date=None, end_date=None):
    res = supabase.rpc("get_global_report", {
        "start_date_param": start_date,
        "end_date_param": end_date
    }).execute()
    return res.data
