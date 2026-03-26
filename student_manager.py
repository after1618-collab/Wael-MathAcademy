import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog
from supabase import create_client
import os
from dotenv import load_dotenv
import requests
import threading
import uvicorn
import pandas as pd
from datetime import datetime

# ✅ استيراد تطبيق الخادم لتشغيله في الخلفية
from mcp_server import app as server_app

# تحميل الإعدادات من .env
script_dir = os.path.dirname(os.path.abspath(__file__))
dotenv_path = os.path.join(script_dir, ".env")
load_dotenv(dotenv_path)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY")
SERVER_URL = os.getenv("SERVER_URL", "http://127.0.0.1:8000")

# ✅ التحقق من وجود كل المتغيرات المطلوبة
required_env_vars = ["SUPABASE_URL", "SUPABASE_SERVICE_KEY", "ADMIN_API_KEY"]
missing_vars = [var for var in required_env_vars if not os.getenv(var)]
if missing_vars:
    raise EnvironmentError(f"❌ Missing required environment variables: {', '.join(missing_vars)}")

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

students_list = []
active_sessions_list = []
auto_refresh_job = None  # ✅ لتتبع مهمة الـ auto-refresh


# ==================== Student Functions ====================

def fetch_students():
    data = supabase.table("students").select("*").order("created_at", desc=True).execute()
    return data.data if data.data else []

def refresh_students():
    # ✅ تعطيل الزر وإظهار Loading
    refresh_btn.config(text="⏳ Loading...", state="disabled")
    threading.Thread(target=_refresh_students_thread, daemon=True).start()

def _refresh_students_thread():
    global students_list
    try:
        data = fetch_students()
        root.after(0, lambda: _update_ui_with_students(data))
    except Exception as e:
        print(f"Error fetching students: {e}")
        root.after(0, lambda: messagebox.showerror(
            "Connection Error",
            f"Failed to connect to Supabase.\nPlease check your internet connection and .env settings.\n\nError: {e}"
        ))
    finally:
        # ✅ إعادة تفعيل الزر بعد التحميل
        root.after(0, lambda: refresh_btn.config(text="🔄 Refresh List", state="normal"))

def _update_ui_with_students(data):
    global students_list
    students_list = data
    update_listbox()

def update_listbox(*_):
    search_term = student_search_var.get().lower()
    student_listbox.delete(0, tk.END)
    for s in students_list:
        class_name = s.get("class_name") or ""
        if (search_term in (s["full_name"] or "").lower()
                or search_term in (s["email"] or "").lower()
                or search_term in class_name.lower()):
            status = "✅" if s["activated"] else "❌"
            display_text = f"{s['full_name']} ({s['email']}) - Class: {class_name} [Active: {status}]"
            student_listbox.insert(tk.END, display_text)

def get_selected_student():
    """✅ دالة مشتركة لجلب الطالب المحدد"""
    selection = student_listbox.curselection()
    if not selection:
        messagebox.showerror("Error", "Please select a student first")
        return None
    selected_text = student_listbox.get(selection[0])
    name_part = selected_text.split(' (')[0]
    student_data = next((s for s in students_list if s["full_name"] == name_part), None)
    if not student_data:
        messagebox.showerror("Error", "Student not found")
        return None
    return student_data

def toggle_activation():
    student_data = get_selected_student()
    if not student_data:
        return

    new_status = not student_data["activated"]
    action = "activate" if new_status else "deactivate"

    # ✅ تأكيد قبل التغيير
    if not messagebox.askyesno("Confirm", f"Are you sure you want to {action} {student_data['full_name']}?"):
        return

    supabase.table("students").update({"activated": new_status}).eq("id", student_data["id"]).execute()
    messagebox.showinfo(
        "Success",
        f"Student {student_data['full_name']} has been {'activated ✅' if new_status else 'deactivated ❌'}"
    )
    refresh_students()

def add_student():
    name = student_add_name_var.get().strip()
    email = student_add_email_var.get().strip()
    class_name = student_add_class_var.get().strip()

    if not name or not email:
        messagebox.showerror("Error", "Please enter name and email")
        return

    password = simpledialog.askstring("Set Initial Password", f"Enter initial password for {name}:", show='*')
    if not password:
        messagebox.showwarning("Cancelled", "Password not set. Student creation was cancelled.")
        return

    try:
        new_user = None
        try:
            user_response = supabase.auth.admin.create_user({
                "email": email,
                "password": password,
                "email_confirm": True,
                "user_metadata": {"role": "student", "full_name": name}
            })
            new_user = user_response.user
        except Exception as auth_error:
            if "already been registered" in str(auth_error):
                messagebox.showinfo("Info", "This user already exists in the authentication system. Attempting to link to a profile.")
                users_list_response = supabase.auth.admin.list_users()
                existing_user = next((u for u in users_list_response if u.email == email), None)
                if existing_user:
                    new_user = existing_user
                else:
                    raise Exception("User exists in Auth but could not be retrieved.")
            else:
                raise auth_error

        if not new_user:
            raise Exception("Failed to create or find the user in the authentication system.")

        supabase.table("students").upsert({
            "id": new_user.id,
            "email": email,
            "full_name": name,
            "class_name": class_name,
            "activated": True
        }).execute()

        messagebox.showinfo("Success", f"Student {name} has been added ✅")
        student_add_name_var.set("")
        student_add_email_var.set("")
        student_add_class_var.set("")
        refresh_students()

    except Exception as e:
        messagebox.showerror("Error", f"Failed to add student: {str(e)}")

def delete_student():
    student_data = get_selected_student()
    if not student_data:
        return

    if messagebox.askyesno("Confirm", f"Are you sure you want to delete {student_data['full_name']}?\nThis will permanently delete them from the system."):
        try:
            # ✅ حذف من الجدول أولاً
            supabase.table("students").delete().eq("id", student_data["id"]).execute()
            # ✅ حذف من Supabase Auth أيضاً
            supabase.auth.admin.delete_user(student_data["id"])
            messagebox.showinfo("Success", f"Student {student_data['full_name']} has been permanently deleted.")
            refresh_students()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to delete student: {str(e)}")

def set_password():
    student_data = get_selected_student()
    if not student_data:
        return

    new_password = simpledialog.askstring("Set Password", f"Enter new password for {student_data['full_name']}:", show='*')
    if not new_password:
        return

    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        payload = {"student_id": student_data["id"], "new_password": new_password}
        response = requests.post(f"{SERVER_URL}/admin/set-password", json=payload, headers=headers)
        response.raise_for_status()
        messagebox.showinfo("Success", "Password updated successfully ✅")
    except requests.exceptions.HTTPError as err:
        messagebox.showerror("Error", f"Failed to set password: {err.response.status_code} - {err.response.text}")
    except Exception as e:
        messagebox.showerror("Error", f"An unexpected error occurred: {e}")

def reset_video_views():
    student_data = get_selected_student()
    if not student_data:
        return

    answer = messagebox.askyesnocancel(
        "Reset Views",
        f"Do you want to reset ALL video views for {student_data['full_name']}?\n\n"
        "Yes = Reset ALL videos\n"
        "No  = Reset a specific video ID\n"
        "Cancel = Abort"
    )

    if answer is None:
        return

    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        if answer:
            response = requests.post(
                f"{SERVER_URL}/admin/lessons/reset-all-watches/{student_data['id']}",
                headers=headers
            )
            response.raise_for_status()
            messagebox.showinfo("Success", f"All video views have been reset for {student_data['full_name']} ✅")
        else:
            lesson_id = simpledialog.askstring("Reset Specific Video", "Enter the exact Lesson ID (UUID):")
            if not lesson_id:
                return
            response = requests.post(
                f"{SERVER_URL}/admin/lessons/{lesson_id.strip()}/reset-watches/{student_data['id']}",
                headers=headers
            )
            response.raise_for_status()
            messagebox.showinfo("Success", f"Video views reset for lesson {lesson_id} ✅")

    except requests.exceptions.HTTPError as err:
        messagebox.showerror("Error", f"Failed to reset views: {err.response.status_code} - {err.response.text}")
    except Exception as e:
        messagebox.showerror("Error", f"An unexpected error occurred: {e}")


# ==================== Session Functions ====================

def fetch_active_sessions():
    global active_sessions_list
    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        response = requests.get(f"{SERVER_URL}/sessions/active", headers=headers)
        response.raise_for_status()
        active_sessions_list = response.json().get("active_sessions", [])
        update_sessions_treeview()
        # ✅ تحديث وقت آخر refresh
        last_refresh_var.set(f"Last updated: {datetime.now().strftime('%H:%M:%S')}")
    except Exception as e:
        messagebox.showerror("Error", f"Failed to fetch active sessions: {e}")
        active_sessions_list = []
        update_sessions_treeview()

def update_sessions_treeview():
    for item in sessions_tree.get_children():
        sessions_tree.delete(item)
    for session in active_sessions_list:
        student_info = session.get("students", {})
        start_time = session.get('created_at', '').replace('T', ' ').split('.')[0]
        sessions_tree.insert("", "end", values=(
            student_info.get("full_name", "N/A"),
            student_info.get("email", "N/A"),
            session.get("device_id", "N/A"),
            start_time
        ), iid=session.get("session_token"))
    # ✅ تحديث عداد الجلسات
    sessions_count_var.set(f"Active Sessions: {len(active_sessions_list)}")

def toggle_auto_refresh():
    """✅ تشغيل/إيقاف Auto-refresh للجلسات"""
    global auto_refresh_job
    if auto_refresh_job is None:
        auto_refresh_sessions()
        auto_refresh_btn.config(text="⏹ Stop Auto-Refresh", bg="red")
    else:
        root.after_cancel(auto_refresh_job)
        auto_refresh_job = None
        auto_refresh_btn.config(text="▶ Start Auto-Refresh (30s)", bg="green")

def auto_refresh_sessions():
    """✅ Auto-refresh كل 30 ثانية"""
    global auto_refresh_job
    fetch_active_sessions()
    auto_refresh_job = root.after(30000, auto_refresh_sessions)

def force_end_selected_session():
    selected_item = sessions_tree.focus()
    if not selected_item:
        messagebox.showerror("Error", "Please select a session to end.")
        return

    if messagebox.askyesno("Confirm", "Are you sure you want to force-end this session?"):
        try:
            headers = {"x-api-key": ADMIN_API_KEY}
            response = requests.post(f"{SERVER_URL}/sessions/force_end/{selected_item}", headers=headers)
            response.raise_for_status()
            messagebox.showinfo("Success", "Session ended successfully ✅")
            fetch_active_sessions()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to end session: {e}")


# ==================== Report Functions ====================

current_report_data = []  # ✅ لحفظ بيانات التقرير للـ Export

def generate_report(report_type: str):
    global current_report_data
    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        response = requests.get(f"{SERVER_URL}/reports/{report_type}", headers=headers)
        response.raise_for_status()
        report_data = response.json()
        current_report_data = report_data

        for item in reports_tree.get_children():
            reports_tree.delete(item)
        reports_tree["columns"] = []

        if not report_data:
            messagebox.showinfo("Info", "No data found for this report.")
            export_btn.config(state="disabled")
            return

        columns = list(report_data[0].keys())
        reports_tree["columns"] = columns
        for col in columns:
            reports_tree.heading(col, text=col.replace('_', ' ').title())
            reports_tree.column(col, width=120)

        for record in report_data:
            reports_tree.insert("", "end", values=list(record.values()))

        # ✅ تفعيل زر Export بعد تحميل البيانات
        export_btn.config(state="normal")

    except requests.exceptions.HTTPError as err:
        try:
            detail = err.response.json().get("detail", err.response.text)
            messagebox.showerror("Report Error", f"Failed to generate report:\n{detail}")
        except Exception:
            messagebox.showerror("Report Error", f"Failed to generate report: {err.response.status_code}\n{err.response.text}")
    except Exception as e:
        messagebox.showerror("Report Error", f"Failed to generate report: {e}")

def export_report_to_excel():
    """✅ تصدير التقرير لـ Excel"""
    if not current_report_data:
        messagebox.showwarning("Warning", "No report data to export. Please generate a report first.")
        return

    file_path = filedialog.asksaveasfilename(
        defaultextension=".xlsx",
        filetypes=[("Excel files", "*.xlsx"), ("All files", "*.*")],
        initialfile=f"report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    )

    if not file_path:
        return

    try:
        df = pd.DataFrame(current_report_data)
        df.to_excel(file_path, index=False)
        messagebox.showinfo("Success", f"Report exported successfully to:\n{file_path} ✅")
    except Exception as e:
        messagebox.showerror("Error", f"Failed to export report: {e}")


# ==================== Server Functions ====================

def run_server():
    try:
        uvicorn.run(server_app, host="127.0.0.1", port=8000)
    except Exception as e:
        print(f"❌ Server thread error: {e}")

def wait_for_server_and_load():
    import time
    print("⏳ Waiting for local server to start...")
    for _ in range(15):
        try:
            requests.get(f"{SERVER_URL}/docs", timeout=1)
            print("✅ Server is ready! Loading sessions...")
            root.after(0, fetch_active_sessions)
            return
        except requests.exceptions.RequestException:
            time.sleep(1)
    print("❌ Local server failed to start in time.")


# ==================== UI Setup ====================

root = tk.Tk()
root.title("🎓 Teacher Control Panel")
root.geometry("900x650")
root.resizable(True, True)

# ✅ ألوان موحدة
BG_COLOR = "#f0f4f8"
root.configure(bg=BG_COLOR)

# --- Notebook (Tabs) ---
notebook = ttk.Notebook(root)
notebook.pack(pady=10, padx=10, fill="both", expand=True)

# ==================== Tab 1: Manage Students ====================
student_tab = ttk.Frame(notebook)
notebook.add(student_tab, text="👨‍🎓 Manage Students")

# Search
search_frame = tk.Frame(student_tab)
search_frame.pack(pady=5, fill="x", padx=10)
tk.Label(search_frame, text="🔍 Search:").pack(side="left", padx=5)
student_search_var = tk.StringVar()
student_search_var.trace("w", update_listbox)
tk.Entry(search_frame, textvariable=student_search_var, width=40).pack(side="left", padx=5)

# Listbox
student_listbox = tk.Listbox(student_tab, width=90, height=12, selectmode=tk.SINGLE)
student_listbox.pack(pady=5, padx=10, fill="x")

# Scrollbar للـ Listbox
scrollbar = tk.Scrollbar(student_tab, orient="vertical", command=student_listbox.yview)
student_listbox.config(yscrollcommand=scrollbar.set)

# Buttons
student_btn_frame = tk.Frame(student_tab)
student_btn_frame.pack(pady=5)

toggle_btn = tk.Button(student_btn_frame, text="✅ Activate / ❌ Deactivate", command=toggle_activation, width=22)
toggle_btn.grid(row=0, column=0, padx=5, pady=3)

set_password_btn = tk.Button(student_btn_frame, text="🔑 Set Password", command=set_password, width=15)
set_password_btn.grid(row=0, column=1, padx=5, pady=3)

reset_views_btn = tk.Button(student_btn_frame, text="🔄 Reset Video Views", command=reset_video_views, bg="#2575FC", fg="white", width=18)
reset_views_btn.grid(row=0, column=2, padx=5, pady=3)

delete_btn = tk.Button(student_btn_frame, text="🗑 Delete Student", command=delete_student, bg="red", fg="white", width=15)
delete_btn.grid(row=0, column=3, padx=5, pady=3)

refresh_btn = tk.Button(student_btn_frame, text="🔄 Refresh List", command=refresh_students, width=15)
refresh_btn.grid(row=0, column=4, padx=5, pady=3)

# Add Student
ttk.Separator(student_tab, orient="horizontal").pack(fill="x", padx=10, pady=5)
student_add_frame = tk.Frame(student_tab)
student_add_frame.pack(pady=5)
tk.Label(student_add_frame, text="➕ Add New Student:", font=("Arial", 10, "bold")).pack(pady=(5, 2))

student_add_fields_frame = tk.Frame(student_add_frame)
student_add_fields_frame.pack(pady=5)

tk.Label(student_add_fields_frame, text="Full Name").grid(row=0, column=0, padx=5, sticky='w')
tk.Label(student_add_fields_frame, text="Email").grid(row=0, column=1, padx=5, sticky='w')
tk.Label(student_add_fields_frame, text="Class").grid(row=0, column=2, padx=5, sticky='w')

student_add_name_var = tk.StringVar()
student_add_email_var = tk.StringVar()
student_add_class_var = tk.StringVar()

tk.Entry(student_add_fields_frame, textvariable=student_add_name_var, width=22).grid(row=1, column=0, padx=5)
tk.Entry(student_add_fields_frame, textvariable=student_add_email_var, width=27).grid(row=1, column=1, padx=5)
tk.Entry(student_add_fields_frame, textvariable=student_add_class_var, width=15).grid(row=1, column=2, padx=5)
tk.Button(student_add_fields_frame, text="➕ Add", command=add_student, bg="green", fg="white").grid(row=1, column=3, padx=5)

# ==================== Tab 2: Live Sessions ====================
sessions_tab = ttk.Frame(notebook)
notebook.add(sessions_tab, text="📡 Active Sessions")

sessions_top_frame = tk.Frame(sessions_tab)
sessions_top_frame.pack(pady=5, fill="x", padx=10)

# ✅ عداد الجلسات
sessions_count_var = tk.StringVar(value="Active Sessions: 0")
tk.Label(sessions_top_frame, textvariable=sessions_count_var, font=("Arial", 11, "bold")).pack(side="left", padx=10)

# ✅ وقت آخر تحديث
last_refresh_var = tk.StringVar(value="Last updated: Never")
tk.Label(sessions_top_frame, textvariable=last_refresh_var, fg="gray").pack(side="right", padx=10)

sessions_btn_frame = tk.Frame(sessions_tab)
sessions_btn_frame.pack(pady=5)

tk.Button(sessions_btn_frame, text="🔄 Refresh Now", command=fetch_active_sessions, width=15).pack(side="left", padx=5)

# ✅ زر Auto-refresh
auto_refresh_btn = tk.Button(
    sessions_btn_frame,
    text="▶ Start Auto-Refresh (30s)",
    command=toggle_auto_refresh,
    bg="green", fg="white", width=22
)
auto_refresh_btn.pack(side="left", padx=5)

tk.Button(
    sessions_btn_frame,
    text="❌ End Selected Session",
    command=force_end_selected_session,
    bg="orange", width=20
).pack(side="left", padx=5)

# Treeview
columns = ("name", "email", "device", "start_time")
sessions_tree = ttk.Treeview(sessions_tab, columns=columns, show="headings")
sessions_tree.heading("name", text="Student Name")
sessions_tree.heading("email", text="Email")
sessions_tree.heading("device", text="Device")
sessions_tree.heading("start_time", text="Start Time")
sessions_tree.column("name", width=200)
sessions_tree.column("email", width=200)
sessions_tree.column("device", width=150)
sessions_tree.column("start_time", width=150)
sessions_tree.pack(pady=10, padx=10, fill="both", expand=True)

# ==================== Tab 3: Reports ====================
reports_tab = ttk.Frame(notebook)
notebook.add(reports_tab, text="📊 Reports")

reports_btn_frame = tk.Frame(reports_tab)
reports_btn_frame.pack(pady=10, fill="x", padx=10)

tk.Button(reports_btn_frame, text="👨‍🎓 Student Performance", command=lambda: generate_report("students"), width=22).pack(side="left", padx=5)
tk.Button(reports_btn_frame, text="❓ Question Performance", command=lambda: generate_report("questions"), width=22).pack(side="left", padx=5)
tk.Button(reports_btn_frame, text="📚 Section Performance", command=lambda: generate_report("sections"), width=22).pack(side="left", padx=5)

# ✅ زر Export
export_btn = tk.Button(
    reports_btn_frame,
    text="📥 Export to Excel",
    command=export_report_to_excel,
    bg="#217346", fg="white",
    width=18,
    state="disabled"  # معطّل حتى يتم تحميل تقرير
)
export_btn.pack(side="right", padx=5)

reports_tree = ttk.Treeview(reports_tab, show="headings")
reports_tree.pack(pady=10, padx=10, fill="both", expand=True)

# ==================== Initial Load ====================
if __name__ == "__main__":
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    print("🚀 Starting backend server in the background...")

    root.after(100, refresh_students)
    threading.Thread(target=wait_for_server_and_load, daemon=True).start()

    root.mainloop()