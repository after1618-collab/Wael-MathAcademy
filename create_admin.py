# c:\Users\Mr. Taher\wael mcp\create_admin.py
import os
from dotenv import load_dotenv
from supabase import create_client, Client
import getpass

# تحميل المتغيرات من .env
load_dotenv()
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    raise RuntimeError("Supabase credentials not found in .env file")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

def create_admin_user():
    """
    ينشئ حساب مدير جديد في نظام المصادقة الخاص بـ Supabase.
    """
    print("--- Create New Admin User ---")
    try:
        email = input("Enter admin email: ").strip()
        full_name = input("Enter admin full name: ").strip()
        password = getpass.getpass("Enter admin password: ")

        if not email or not password or not full_name:
            print("❌ Email, full name, and password are required.")
            return

        print(f"Creating admin user: {email}...")

        # إنشاء المستخدم مع تحديد دوره كـ "admin"
        user_response = supabase.auth.admin.create_user({
            "email": email,
            "password": password,
            "email_confirm": True,  # تأكيد البريد الإلكتروني تلقائيًا
            "user_metadata": {
                "role": "admin",
                "full_name": full_name
            }
        })

        if user_response.user:
            print(f"✅ Admin user '{full_name}' created successfully!")
        else:
            print("🚨 An unexpected error occurred and the user was not created.")

    except Exception as e:
        print(f"❌ Creation failed: {e}")

if __name__ == "__main__":
    create_admin_user()
