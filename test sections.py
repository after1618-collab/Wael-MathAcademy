import os
from supabase import create_client
from dotenv import load_dotenv

load_dotenv()
url = os.getenv("SUPABASE_URL")
key = os.getenv("SUPABASE_SERVICE_KEY")
supabase = create_client(url, key)

print("✅ اختبار دوال الأقسام")

# 1. إضافة قسم جديد
res = supabase.rpc("add_section", {
    "p_name": "Algebra",
    "p_description": "قسم خاص بجبر المعادلات"
}).execute()
section_id = res.data
print("Add section:", section_id)

# 2. عرض الأقسام
res2 = supabase.rpc("list_sections").execute()
print("Sections:", res2.data)

# 3. تعديل القسم
if section_id:
    supabase.rpc("update_section", {
        "p_section_id": section_id,
        "p_name": "Algebra Updated",
        "p_description": "وصف جديد"
    }).execute()

    # نعرض تاني بعد التعديل
    res3 = supabase.rpc("list_sections").execute()
    print("Updated Sections:", res3.data)

# 4. حذف القسم
if section_id:
    supabase.rpc("delete_section", {
        "p_section_id": section_id
    }).execute()

    # نعرض بعد الحذف
    res4 = supabase.rpc("list_sections").execute()
    print("After Delete:", res4.data)
