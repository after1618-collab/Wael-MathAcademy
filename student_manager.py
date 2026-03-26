import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
from supabase import create_client
import os
from dotenv import load_dotenv
import requests
import threading
import uvicorn

# ✅ استيراد تطبيق الخادم لتشغيله في الخلفية
from mcp_server import app as server_app

# تحميل الإعدادات من .env
script_dir = os.path.dirname(os.path.abspath(__file__))
dotenv_path = os.path.join(script_dir, ".env")
load_dotenv(dotenv_path)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY")
SERVER_URL = "http://127.0.0.1:8000" # عنوان الخادم المحلي


supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

students_list = []
active_sessions_list = []

def fetch_students():
    data = supabase.table("students").select("*").order("created_at", desc=True).execute()
    return data.data if data.data else []

def refresh_students():
    # تشغيل عملية الجلب في خيط منفصل لمنع تجميد الواجهة أثناء التحميل
    threading.Thread(target=_refresh_students_thread, daemon=True).start()

def _refresh_students_thread():
    global students_list
    try:
        data = fetch_students()
        # تحديث الواجهة يجب أن يتم دائمًا في الخيط الرئيسي (Main Thread)
        root.after(0, lambda: _update_ui_with_students(data))
    except Exception as e:
        print(f"Error fetching students: {e}")
        root.after(0, lambda: messagebox.showerror("Connection Error", f"Failed to connect to Supabase.\nPlease check your internet connection and .env settings.\n\nError: {e}"))

def _update_ui_with_students(data):
    global students_list
    students_list = data
    update_listbox()

def update_listbox(*_):
    search_term = student_search_var.get().lower()
    student_listbox.delete(0, tk.END)
    for s in students_list:
        class_name = s.get("class_name") or ""
        if search_term in (s["full_name"] or "").lower() or search_term in (s["email"] or "").lower() or search_term in class_name.lower():
            status = "✅" if s["activated"] else "❌"
            display_text = f"{s['full_name']} ({s['email']}) - Class: {class_name} [Active: {status}]"
            student_listbox.insert(tk.END, display_text)

def toggle_activation():
    selection = student_listbox.curselection()
    if not selection:
        messagebox.showerror("Error", "Please select a student first")
        return
    selected_text = student_listbox.get(selection[0])
    name_part = selected_text.split(' (')[0]
    student_data = next((s for s in students_list if s["full_name"] == name_part), None)
    if not student_data:
        messagebox.showerror("Error", "Student not found")
        return
    new_status = not student_data["activated"]
    supabase.table("students").update({"activated": new_status}).eq("id", student_data["id"]).execute()
    messagebox.showinfo("Success", f"Student {student_data['full_name']} has been {'activated' if new_status else 'deactivated'}")
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
            # 1. Attempt to create the user in Supabase Auth
            user_response = supabase.auth.admin.create_user({
                "email": email,
                "password": password,
                "email_confirm": True, # Auto-confirm the email
                "user_metadata": {"role": "student", "full_name": name}
            })
            new_user = user_response.user
        except Exception as auth_error:
            # 2. If user already exists in Auth, try to find them
            if "already been registered" in str(auth_error):
                messagebox.showinfo("Info", "This user already exists in the authentication system. Attempting to link to a profile.")
                users_list_response = supabase.auth.admin.list_users()
                existing_user = next((u for u in users_list_response if u.email == email), None)
                if existing_user:
                    new_user = existing_user
                else:
                    # This case is rare, but handle it
                    raise Exception("User exists in Auth but could not be retrieved.")
            else:
                # For other auth errors, re-raise them
                raise auth_error

        if not new_user:
            raise Exception("Failed to create or find the user in the authentication system.")

        # 3. Use `upsert` to create or update the student profile.
        # This is more robust than relying on the trigger's speed.
        # If the trigger already created the row, this will update it.
        # If the trigger was slow, this will create it.
        # The `id` is the conflict resolution column.
        supabase.table("students").upsert({
            "id": new_user.id, "email": email, "full_name": name, "class_name": class_name, "activated": True
        }).execute()

        messagebox.showinfo("Success", f"Student {name} has been added.")

        # Clear fields after successful addition
        student_add_name_var.set("")
        student_add_email_var.set("")
        student_add_class_var.set("")
        refresh_students()
    except Exception as e:
        messagebox.showerror("Error", f"Failed to add student: {str(e)}")

def delete_student():
    selection = student_listbox.curselection()
    if not selection:
        messagebox.showerror("Error", "Please select a student first")
        return
    selected_text = student_listbox.get(selection[0])
    name_part = selected_text.split(' (')[0]
    student_data = next((s for s in students_list if s["full_name"] == name_part), None)
    if not student_data:
        messagebox.showerror("Error", "Student not found")
        return
    if messagebox.askyesno("Confirm", f"Are you sure you want to delete student {student_data['full_name']}?"):
        supabase.table("students").delete().eq("id", student_data["id"]).execute()
        messagebox.showinfo("Success", f"Student {student_data['full_name']} has been deleted.")
        refresh_students()

def set_password():
    selection = student_listbox.curselection()
    if not selection:
        messagebox.showerror("Error", "Please select a student first")
        return
    selected_text = student_listbox.get(selection[0])
    name_part = selected_text.split(' (')[0]
    student_data = next((s for s in students_list if s["full_name"] == name_part), None)
    if not student_data:
        messagebox.showerror("Error", "Student not found")
        return

    new_password = simpledialog.askstring("Set Password", f"Enter new password for {student_data['full_name']}:", show='*')
    if not new_password:
        return

    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        payload = {"student_id": student_data["id"], "new_password": new_password}
        response = requests.post(f"{SERVER_URL}/admin/set-password", json=payload, headers=headers)
        response.raise_for_status() # Will raise an exception for 4xx/5xx errors
        messagebox.showinfo("Success", "Password updated successfully.")
    except requests.exceptions.HTTPError as err:
        messagebox.showerror("Error", f"Failed to set password: {err.response.status_code} - {err.response.text}")
    except Exception as e:
        messagebox.showerror("Error", f"An unexpected error occurred: {e}")

def reset_video_views():
    selection = student_listbox.curselection()
    if not selection:
        messagebox.showerror("Error", "Please select a student first")
        return
    selected_text = student_listbox.get(selection[0])
    name_part = selected_text.split(' (')[0]
    student_data = next((s for s in students_list if s["full_name"] == name_part), None)
    if not student_data:
        messagebox.showerror("Error", "Student not found")
        return

    # Ask if they want to reset ALL or Specific
    answer = messagebox.askyesnocancel("Reset Views", 
        f"Do you want to reset ALL video views for {student_data['full_name']}?\n\n"
        "Yes = Reset ALL videos\n"
        "No  = Reset a specific video ID\n"
        "Cancel = Abort")
        
    if answer is None: # Cancel
        return

    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        if answer: # Yes = All
            response = requests.post(f"{SERVER_URL}/admin/lessons/reset-all-watches/{student_data['id']}", headers=headers)
            response.raise_for_status()
            messagebox.showinfo("Success", f"All video views have been reset for {student_data['full_name']}.")
        else: # No = Specific
            lesson_id = simpledialog.askstring("Reset Specific Video", "Enter the exact Lesson ID (UUID):")
            if not lesson_id:
                return
            response = requests.post(f"{SERVER_URL}/admin/lessons/{lesson_id.strip()}/reset-watches/{student_data['id']}", headers=headers)
            response.raise_for_status()
            messagebox.showinfo("Success", f"Video views reset for lesson {lesson_id}.")
            
    except requests.exceptions.HTTPError as err:
        messagebox.showerror("Error", f"Failed to reset views: {err.response.status_code} - {err.response.text}")
    except Exception as e:
        messagebox.showerror("Error", f"An unexpected error occurred: {e}")

# --- Live Session Monitoring Functions ---
def fetch_active_sessions():
    global active_sessions_list
    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        response = requests.get(f"{SERVER_URL}/sessions/active", headers=headers)
        response.raise_for_status()
        active_sessions_list = response.json().get("active_sessions", [])
        update_sessions_treeview()
    except Exception as e:
        messagebox.showerror("Error", f"Failed to fetch active sessions: {e}")
        active_sessions_list = []
        update_sessions_treeview()

def update_sessions_treeview():
    # Clear existing items
    for item in sessions_tree.get_children():
        sessions_tree.delete(item)
    # Add new items
    for session in active_sessions_list:
        student_info = session.get("students", {})
        start_time = session.get('created_at', '').replace('T', ' ').split('.')[0]
        sessions_tree.insert("", "end", values=(
            student_info.get("full_name", "N/A"),
            student_info.get("email", "N/A"),
            session.get("device_id", "N/A"),
            start_time
        ), iid=session.get("session_token"))

def force_end_selected_session():
    selected_item = sessions_tree.focus()
    if not selected_item:
        messagebox.showerror("Error", "Please select a session to end.")
        return

    session_token = selected_item
    if messagebox.askyesno("Confirm", "Are you sure you want to force-end this session?"):
        try:
            headers = {"x-api-key": ADMIN_API_KEY}
            response = requests.post(f"{SERVER_URL}/sessions/force_end/{session_token}", headers=headers)
            response.raise_for_status()
            messagebox.showinfo("Success", "Session ended successfully.")
            fetch_active_sessions() # Refresh the list
        except Exception as e:
            messagebox.showerror("Error", f"Failed to end session: {e}")

# --- Reporting Functions ---
def generate_report(report_type: str):
    """Fetches and displays a report from the backend."""
    try:
        headers = {"x-api-key": ADMIN_API_KEY}
        response = requests.get(f"{SERVER_URL}/reports/{report_type}", headers=headers)
        response.raise_for_status()
        report_data = response.json()

        # Clear previous report
        for item in reports_tree.get_children():
            reports_tree.delete(item)
        reports_tree["columns"] = []

        if not report_data:
            messagebox.showinfo("Info", "No data found for this report.")
            return

        # Dynamically configure columns
        columns = list(report_data[0].keys())
        reports_tree["columns"] = columns
        for col in columns:
            reports_tree.heading(col, text=col.replace('_', ' ').title())
            reports_tree.column(col, width=120)

        # Populate data
        for record in report_data:
            reports_tree.insert("", "end", values=list(record.values()))
    except requests.exceptions.HTTPError as err:
        try:
            # Try to get the detailed error from the server
            detail = err.response.json().get("detail", err.response.text)
            messagebox.showerror("Report Error", f"Failed to generate report:\n{detail}")
        except Exception: # If the response is not JSON
            messagebox.showerror("Report Error", f"Failed to generate report: {err.response.status_code}\n{err.response.text}")
    except Exception as e:
        messagebox.showerror("Report Error", f"Failed to generate report: {e}")

# --- Server Function ---
def run_server():
    """
    Runs the Uvicorn server in a separate thread.
    `reload=True` is disabled as it's not suitable for a background process.
    """
    try:
        uvicorn.run(server_app, host="127.0.0.1", port=8000)
    except Exception as e:
        # This might not be visible if the main app closes, but it's good practice.
        print(f"❌ Server thread error: {e}")

def wait_for_server_and_load():
    """Waits for the local server to be ready before fetching sessions."""
    import time
    print("⏳ Waiting for local server to start...")
    for _ in range(15):  # Try for 15 seconds
        try:
            requests.get(f"{SERVER_URL}/docs", timeout=1)
            print("✅ Server is ready! Loading sessions...")
            root.after(0, fetch_active_sessions)
            return
        except requests.exceptions.RequestException:
            time.sleep(1)
    print("❌ Local server failed to start in time.")

# --- UI Setup ---
root = tk.Tk()
root.title("Teacher Control Panel")
root.geometry("800x600")

# --- Notebook (Tabs) ---
notebook = ttk.Notebook(root)
notebook.pack(pady=10, padx=10, fill="both", expand=True)

# --- Tab 1: Manage Students ---
student_tab = ttk.Frame(notebook)
notebook.add(student_tab, text="Manage Students")

student_search_var = tk.StringVar()
student_search_var.trace("w", update_listbox)
tk.Label(student_tab, text="Search for student by name or email:").pack(pady=5)
search_entry = tk.Entry(root, textvariable=student_search_var, width=40)
search_entry.pack(in_=student_tab, pady=5)

student_listbox = tk.Listbox(student_tab, width=80, height=15)
student_listbox.pack(pady=10, padx=10, fill="x")

student_btn_frame = tk.Frame(student_tab)
student_btn_frame.pack(pady=5)

toggle_btn = tk.Button(student_btn_frame, text="Activate / Deactivate", command=toggle_activation)
toggle_btn.grid(row=0, column=0, padx=5)
set_password_btn = tk.Button(student_btn_frame, text="Set Password", command=set_password)
set_password_btn.grid(row=0, column=1, padx=5)
# ✅ Add Reset Views button
reset_views_btn = tk.Button(student_btn_frame, text="Reset Video Views", command=reset_video_views, bg="#2575FC", fg="white")
reset_views_btn.grid(row=0, column=2, padx=5)

delete_btn = tk.Button(student_btn_frame, text="Delete Student", command=delete_student, bg="red", fg="white")
delete_btn.grid(row=0, column=3, padx=5)
refresh_btn = tk.Button(student_btn_frame, text="Refresh List", command=refresh_students)
refresh_btn.grid(row=0, column=4, padx=5)

student_add_frame = tk.Frame(student_tab)
student_add_frame.pack(pady=5)
tk.Label(student_add_frame, text="Add New Student:").pack(pady=(10, 2))
student_add_fields_frame = tk.Frame(student_add_frame)
student_add_fields_frame.pack(pady=5)
tk.Label(student_add_fields_frame, text="Full Name").grid(row=0, column=0, padx=5, sticky='w')
tk.Label(student_add_fields_frame, text="Email").grid(row=0, column=1, padx=5, sticky='w')
tk.Label(student_add_fields_frame, text="Class").grid(row=0, column=2, padx=5, sticky='w')

student_add_name_var = tk.StringVar()
student_add_email_var = tk.StringVar()
student_add_class_var = tk.StringVar()

tk.Entry(student_add_fields_frame, textvariable=student_add_name_var, width=20).grid(row=1, column=0, padx=5)
tk.Entry(student_add_fields_frame, textvariable=student_add_email_var, width=25).grid(row=1, column=1, padx=5)
tk.Entry(student_add_fields_frame, textvariable=student_add_class_var, width=15).grid(row=1, column=2, padx=5)
tk.Button(student_add_fields_frame, text="Add", command=add_student).grid(row=1, column=3, padx=5)

# --- Tab 2: Live Sessions ---
sessions_tab = ttk.Frame(notebook)
notebook.add(sessions_tab, text="Active Sessions")

sessions_btn_frame = tk.Frame(sessions_tab)
sessions_btn_frame.pack(pady=10)
tk.Button(sessions_btn_frame, text="🔄 Refresh Sessions", command=fetch_active_sessions).pack(side="left", padx=10)
tk.Button(sessions_btn_frame, text="❌ End Selected Session", command=force_end_selected_session, bg="orange").pack(side="left", padx=10)

columns = ("name", "email", "device", "start_time")
sessions_tree = ttk.Treeview(sessions_tab, columns=columns, show="headings")
sessions_tree.heading("name", text="Student Name")
sessions_tree.heading("email", text="Email")
sessions_tree.heading("device", text="Device")
sessions_tree.heading("start_time", text="Start Time")
sessions_tree.pack(pady=10, padx=10, fill="both", expand=True)

# --- Tab 3: Reports ---
reports_tab = ttk.Frame(notebook)
notebook.add(reports_tab, text="Reports")

reports_btn_frame = tk.Frame(reports_tab)
reports_btn_frame.pack(pady=10, fill="x", padx=10)
tk.Button(reports_btn_frame, text="📊 Student Performance Report", command=lambda: generate_report("students")).pack(side="left", padx=5)
tk.Button(reports_btn_frame, text="❓ Question Performance Report", command=lambda: generate_report("questions")).pack(side="left", padx=5)
tk.Button(reports_btn_frame, text="📚 Section Performance Report", command=lambda: generate_report("sections")).pack(side="left", padx=5)

reports_tree = ttk.Treeview(reports_tab, show="headings")
reports_tree.pack(pady=10, padx=10, fill="both", expand=True)

# --- Initial Load ---
if __name__ == "__main__":
    # ✅ بدء تشغيل الخادم في خيط خلفي
    # استخدام `daemon=True` يضمن إغلاق الخادم عند إغلاق الواجهة
    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()
    print("🚀 Starting backend server in the background...")

    # تحميل البيانات الأولية للواجهة
    # نستخدم root.after لضمان ظهور النافذة قبل البدء في العمليات الثقيلة
    root.after(100, refresh_students)
    
    # تشغيل خيط انتظار السيرفر لتحميل الجلسات دون تجميد الواجهة أو التسبب في خطأ اتصال
    threading.Thread(target=wait_for_server_and_load, daemon=True).start()

    # تشغيل الواجهة الرسومية
    root.mainloop()
