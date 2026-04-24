import os
import threading
import logging
import time
from datetime import datetime
from tkinter import messagebox, simpledialog, filedialog, ttk

import customtkinter as ctk
from supabase import create_client
import requests
from dotenv import load_dotenv

try:
    import pandas as pd
    PANDAS_AVAILABLE = True
except ImportError:
    PANDAS_AVAILABLE = False

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

class StudentManagerApp:
    def __init__(self):
        ctk.set_appearance_mode("System")
        ctk.set_default_color_theme("blue")

        self.root = ctk.CTk()
        self.root.title("🎓 Teacher Control Panel")
        self.root.geometry("1100x750")

        # Data State
        self.students_list = []
        self.active_sessions_list = []
        self.current_report_data = []
        self.auto_refresh_job = None
        self._search_after_id = None
        self.selected_session_token = None

        # UI Setup
        self.setup_ui()
        
        # Initial Server Startup
        server_thread = threading.Thread(target=self.run_server, daemon=True)
        server_thread.start()
        
        self.root.after(100, self.refresh_students)
        threading.Thread(target=self.wait_for_server_and_load, daemon=True).start()

    def setup_ui(self):
        # Notebook (Tabs)
        self.tabview = ctk.CTkTabview(self.root)
        self.tabview.pack(fill="both", expand=True, padx=10, pady=(10, 0))
        
        self.tab_students = self.tabview.add("👨‍🎓 Manage Students")
        self.tab_sessions = self.tabview.add("📡 Active Sessions")
        self.tab_reports = self.tabview.add("📊 Reports")

        self.setup_students_tab()
        self.setup_sessions_tab()
        self.setup_reports_tab()

        # Status Bar at the bottom
        self.status_bar = ctk.CTkFrame(self.root, height=30, corner_radius=0)
        self.status_bar.pack(fill="x", side="bottom")
        self.status_bar.pack_propagate(False)
        self.status_label = ctk.CTkLabel(self.status_bar, text="✅ Ready", font=("Segoe UI", 14, "bold"), anchor="w", text_color="black")
        self.status_label.pack(side="left", padx=10)

    def setup_students_tab(self):
        # Search Area
        search_frame = ctk.CTkFrame(self.tab_students, fg_color="transparent")
        search_frame.pack(fill="x", padx=10, pady=5)
        
        self.student_search_var = ctk.StringVar()
        self.student_search_var.trace_add("write", self.update_listbox)
        
        ctk.CTkLabel(search_frame, text="🔍 Search:").pack(side="left", padx=5)
        ctk.CTkEntry(search_frame, textvariable=self.student_search_var, width=400).pack(side="left", padx=5)
        
        self.refresh_btn = ctk.CTkButton(search_frame, text="🔄 Refresh List", command=self.refresh_students, width=120)
        self.refresh_btn.pack(side="right", padx=5)

        # Students Listbox (Using a Scrollable Frame for Custom Looks)
        self.students_frame = ctk.CTkScrollableFrame(self.tab_students, height=350)
        self.students_frame.pack(fill="both", expand=True, padx=10, pady=5)

        # Controls Area
        controls_frame = ctk.CTkFrame(self.tab_students)
        controls_frame.pack(fill="x", padx=10, pady=10)
        
        ctk.CTkButton(controls_frame, text="✅ Toggle Activation", command=self.toggle_activation).pack(side="left", padx=5, pady=10)
        ctk.CTkButton(controls_frame, text="🔑 Set Password", command=self.set_password).pack(side="left", padx=5)
        
        # WhatsApp Button
        ctk.CTkButton(controls_frame, text="📱 واتساب (تحديث ونسخ)", 
                      command=self.prepare_whatsapp_msg, 
                      fg_color="#25D366", hover_color="#128C7E", 
                      font=("Segoe UI", 13, "bold")).pack(side="left", padx=5)

        ctk.CTkButton(controls_frame, text="🔄 Reset Views", command=self.reset_video_views, fg_color="#2575FC").pack(side="left", padx=5)
        ctk.CTkButton(controls_frame, text="🗑 Delete Student", command=self.delete_student, fg_color="#e74c3c").pack(side="right", padx=5)

        # Add Student Form
        add_frame = ctk.CTkFrame(self.tab_students)
        add_frame.pack(fill="x", padx=10, pady=5)
        
        ctk.CTkLabel(add_frame, text="➕ Add New Student:", font=("Segoe UI", 15, "bold")).pack(pady=5)
        
        form_inner = ctk.CTkFrame(add_frame, fg_color="transparent")
        form_inner.pack(pady=5)

        # Labels for the inputs
        ctk.CTkLabel(form_inner, text="الاسم بالكامل (Full Name):", font=("Segoe UI", 13, "bold"), text_color="black").grid(row=0, column=0, padx=5, sticky="w")
        ctk.CTkLabel(form_inner, text="البريد الإلكتروني (Email):", font=("Segoe UI", 13, "bold"), text_color="black").grid(row=0, column=1, padx=5, sticky="w")
        ctk.CTkLabel(form_inner, text="الفصل (Class):", font=("Segoe UI", 13, "bold"), text_color="black").grid(row=0, column=2, padx=5, sticky="w")

        self.add_name_var = ctk.StringVar()
        self.add_email_var = ctk.StringVar()
        self.add_class_var = ctk.StringVar()

        ctk.CTkEntry(form_inner, textvariable=self.add_name_var, placeholder_text="e.g. Ahmed Ali", width=200).grid(row=1, column=0, padx=5, pady=(2, 10))
        ctk.CTkEntry(form_inner, textvariable=self.add_email_var, placeholder_text="e.g. ahmed@gmail.com", width=250).grid(row=1, column=1, padx=5, pady=(2, 10))
        ctk.CTkEntry(form_inner, textvariable=self.add_class_var, placeholder_text="e.g. Group A", width=120).grid(row=1, column=2, padx=5, pady=(2, 10))
        ctk.CTkButton(form_inner, text="➕ Add Student", command=self.add_student, fg_color="green", width=120, font=("Segoe UI", 13, "bold")).grid(row=1, column=3, padx=5, pady=(2, 10))

    def setup_sessions_tab(self):
        top_frame = ctk.CTkFrame(self.tab_sessions, fg_color="transparent")
        top_frame.pack(fill="x", padx=10, pady=10)
        
        self.sessions_count_var = ctk.StringVar(value="Active Sessions: 0")
        ctk.CTkLabel(top_frame, textvariable=self.sessions_count_var, font=("Segoe UI", 16, "bold"), text_color="black").pack(side="left")
        
        self.last_refresh_var = ctk.StringVar(value="Last updated: Never")
        ctk.CTkLabel(top_frame, textvariable=self.last_refresh_var, text_color="gray").pack(side="right")

        btn_frame = ctk.CTkFrame(self.tab_sessions, fg_color="transparent")
        btn_frame.pack(fill="x", padx=10, pady=5)
        
        ctk.CTkButton(btn_frame, text="🔄 Refresh Now", command=self.fetch_active_sessions).pack(side="left", padx=5)
        self.auto_refresh_btn = ctk.CTkButton(btn_frame, text="▶ Start Auto-Refresh", command=self.toggle_auto_refresh, fg_color="green")
        self.auto_refresh_btn.pack(side="left", padx=5)
        ctk.CTkButton(btn_frame, text="❌ Force End Session", command=self.force_end_selected_session, fg_color="orange").pack(side="right", padx=5)

        # Use a list-based view for sessions for simplicity or a simple treeview wrapper
        # Here we'll keep the logic but wrap it in a scrollable frame for consistent look
        self.sessions_list_frame = ctk.CTkScrollableFrame(self.tab_sessions)
        self.sessions_list_frame.pack(fill="both", expand=True, padx=10, pady=10)

    def setup_reports_tab(self):
        btn_frame = ctk.CTkFrame(self.tab_reports)
        btn_frame.pack(fill="x", padx=10, pady=10)
        
        ctk.CTkButton(btn_frame, text="👨‍🎓 Students Performance", command=lambda: self.generate_report("students")).pack(side="left", padx=5, pady=10)
        ctk.CTkButton(btn_frame, text="❓ Questions Report", command=lambda: self.generate_report("questions")).pack(side="left", padx=5)
        
        self.export_btn = ctk.CTkButton(btn_frame, text="📥 Export to Excel", command=self.export_report_to_excel, fg_color="#217346", state="disabled")
        self.export_btn.pack(side="right", padx=5)

        # Removed reports_display as we now use Popups with Treeview
        ctk.CTkLabel(self.tab_reports, text="📊 اختر نوع التقرير لعرضه في نافذة مستقلة", 
                     font=("Segoe UI", 15, "bold"), text_color="black").pack(pady=50)

    # --- Logic ---

    def refresh_students(self):
        # أظهر placeholder فوراً في القائمة لتوفير Feedback للمستخدم
        for widget in self.students_frame.winfo_children():
            widget.destroy()
        ctk.CTkLabel(self.students_frame, text="⏳ Loading students...", 
                     font=("", 14), text_color="black").pack(pady=40)

        self.refresh_btn.configure(text="⏳ Loading...", state="disabled")
        self.set_status("⏳ Fetching students list...", "orange")
        threading.Thread(target=self._refresh_thread, daemon=True).start()

    def _refresh_thread(self):
        try:
            # تحسين: جلب الأعمدة المطلوبة فقط لتقليل حجم البيانات
            data = supabase.table("students").select(
                "id, full_name, email, class_name, activated"
            ).order("created_at", desc=True).execute()

            def success():
                self._update_ui_students(data.data or [])
                self.set_status(f"✅ Loaded {len(data.data)} students", "green")
            self.root.after(0, success)
        except Exception as e:
            # عرض الخطأ داخل القائمة ليكون أكثر وضوحاً في حال الـ Cold Start
            def failure(exc=e):
                for widget in self.students_frame.winfo_children():
                    widget.destroy()
                ctk.CTkLabel(self.students_frame, text=f"❌ Failed to load: {exc}", 
                             font=("", 14), text_color="red").pack(pady=40)
                self.show_error("فشل تحديث القائمة", exc)
            self.root.after(0, failure)
        finally:
            self.root.after(0, lambda: self.refresh_btn.configure(text="🔄 Refresh List", state="normal"))

    def _update_ui_students(self, data):
        self.students_list = data
        self.update_listbox()

    def update_listbox(self, *args):
        if self._search_after_id:
            self.root.after_cancel(self._search_after_id)
        self._search_after_id = self.root.after(300, self._do_search)

    def _do_search(self):
        for widget in self.students_frame.winfo_children():
            widget.destroy()
            
        search = self.student_search_var.get().lower()
        for s in self.students_list:
            name = s.get("full_name") or "Unnamed"
            email = s.get("email") or ""
            if search in name.lower() or search in email.lower():
                self._create_student_row(s)

    def _create_student_row(self, s):
        row = ctk.CTkFrame(self.students_frame)
        row.pack(fill="x", pady=2, padx=5)
        
        status_color = "green" if s.get("activated") else "red"
        status_dot = ctk.CTkLabel(row, text="●", text_color=status_color, width=20, font=("", 16))
        status_dot.pack(side="left", padx=(10, 5))
        
        # Name (Solid Black)
        name_lbl = ctk.CTkLabel(row, text=s['full_name'], 
                                text_color="black", 
                                font=("Segoe UI", 15, "bold"), anchor="w")
        name_lbl.pack(side="left", padx=5)
        
        ctk.CTkLabel(row, text="|", text_color="black").pack(side="left", padx=2)
        
        # Email (Solid Black)
        email_lbl = ctk.CTkLabel(row, text=f"📩 {s['email']}", 
                                 text_color="black", 
                                 font=("Segoe UI", 14), anchor="w")
        email_lbl.pack(side="left", padx=10)
        
        ctk.CTkLabel(row, text="|", text_color="black").pack(side="left", padx=2)
        
        # Class (Solid Black)
        class_lbl = ctk.CTkLabel(row, text=f"🏫 {s.get('class_name') or 'N/A'}", 
                                 text_color="black", 
                                 font=("Segoe UI", 14), anchor="w")
        class_lbl.pack(side="left", padx=10)

        # Make whole row clickable
        for widget in [row, status_dot, name_lbl, email_lbl, class_lbl]:
            widget.bind("<Button-1>", lambda e, x=s: self._on_student_click(x))
        
    def _on_student_click(self, student):
        self.selected_student = student
        # Highlighting logic could go here

    def get_selected(self):
        if not hasattr(self, 'selected_student') or not self.selected_student:
            messagebox.showwarning("Warning", "Please select a student row first!")
            return None
        return self.selected_student

    def toggle_activation(self):
        s = self.get_selected()
        if not s: return
        new_val = not s["activated"]
        self.set_status(f"⏳ Updating {s['full_name']}...", "orange")
        
        def worker():
            try:
                supabase.table("students").update({"activated": new_val}).eq("id", s["id"]).execute()
                self.root.after(0, lambda: [
                    self.set_status(f"✅ Student {s['full_name']} updated", "green"),
                    self.refresh_students()
                ])
            except Exception as e:
                self.root.after(0, lambda err=e: self.show_error("فشل تغيير حالة التفعيل", err))
        threading.Thread(target=worker, daemon=True).start()

    def add_student(self):
        name = self.add_name_var.get().strip()
        email = self.add_email_var.get().strip()
        if not name or not email: return
        
        pw = simpledialog.askstring("Password", f"Set password for {name}:", show='*')
        if not pw: return
        
        self.set_status(f"⏳ Creating student {name}...", "orange")
        def worker():
            try:
                # Auth Create
                user_res = supabase.auth.admin.create_user({
                    "email": email, "password": pw, "email_confirm": True,
                    "user_metadata": {"role": "student", "full_name": name}
                })
                # Profile Create/Update
                supabase.table("students").upsert({
                    "id": user_res.user.id, "email": email, "full_name": name,
                    "class_name": self.add_class_var.get().strip(), "activated": True
                }).execute()
                
                self.root.after(0, lambda: [self.set_status(f"✅ Created: {name}", "green"), self.refresh_students()])
            except Exception as e:
                self.root.after(0, lambda err=e: self.show_error("فشل إضافة الطالب", err))
        
        threading.Thread(target=worker, daemon=True).start()

    def set_password(self):
        s = self.get_selected()
        if not s: return
        new_pw = simpledialog.askstring("Password", "Enter new password:", show="*")
        if not new_pw: return
        
        self.set_status(f"⏳ Updating password for {s['full_name']}...", "orange")
        def worker():
            try:
                headers = {"x-api-key": ADMIN_API_KEY}
                res = requests.post(f"{SERVER_URL}/admin/set-password", 
                                    json={"student_id": s["id"], "new_password": new_pw}, 
                                    headers=headers, timeout=10)
                res.raise_for_status()
                self.root.after(0, lambda: [
                    self.set_status(f"✅ Password updated for {s['full_name']}", "green"),
                    messagebox.showinfo("Success", "Password updated successfully.")
                ])
            except Exception as e:
                self.root.after(0, lambda err=e: self.show_error("فشل تغيير كلمة المرور", err))
        
        threading.Thread(target=worker, daemon=True).start()

    def prepare_whatsapp_msg(self):
        s = self.get_selected()
        if not s: return
        
        # Ask for the password to be sent
        new_pw = simpledialog.askstring("رسالة الواتساب", f"أدخل كلمة المرور الجديدة للطالب {s['full_name']}:", show="*")
        if not new_pw: return
        
        self.set_status(f"⏳ جاري التحديث ونسخ بيانات {s['full_name']}...", "orange")
        
        def worker():
            try:
                headers = {"x-api-key": ADMIN_API_KEY}
                res = requests.post(
                    f"{SERVER_URL}/admin/set-password", 
                    json={"student_id": s["id"], "new_password": new_pw}, 
                    headers=headers, timeout=10
                )
                res.raise_for_status()
                
                # Message Content
                msg = f"مرحباً {s['full_name']}،\n\nإليك بيانات الدخول الخاصة بك للمنصة:\n📧 الإيميل: {s['email']}\n🔑 كلمة المرور: {new_pw}\n\nبالتوفيق!"
                
                self.root.after(0, lambda: [
                    self.root.clipboard_clear(),
                    self.root.clipboard_append(msg),
                    self.set_status("✅ تم التحديث والنسخ بنجاح", "green"),
                    messagebox.showinfo("تم النسخ ✅", f"تم تحديث كلمة المرور لـ {s['full_name']} ونسخ الرسالة بنجاح!\n\nيمكنك الآن عمل لصق (Paste) في الواتساب.")
                ])
            except Exception as e:
                self.root.after(0, lambda err=e: self.show_error("فشل إعداد رسالة الواتساب", err))
                
        threading.Thread(target=worker, daemon=True).start()

    def reset_video_views(self):
        s = self.get_selected()
        if not s: return
        if messagebox.askyesno("Reset", f"Reset all video watch counts for {s['full_name']}?"):
            self.set_status(f"⏳ Resetting views for {s['full_name']}...", "orange")
            def worker():
                try:
                    headers = {"x-api-key": ADMIN_API_KEY}
                    requests.post(f"{SERVER_URL}/admin/lessons/reset-all-watches/{s['id']}", 
                                  headers=headers, timeout=10).raise_for_status()
                    self.root.after(0, lambda: [
                        self.set_status(f"✅ Watch counts reset for {s['full_name']}", "green"),
                        messagebox.showinfo("Success", "Reset complete.")
                    ])
                except Exception as e:
                    self.root.after(0, lambda err=e: self.show_error("فشل إعادة تعيين المشاهدات", err))
            
            threading.Thread(target=worker, daemon=True).start()

    # --- Session Management ---

    def fetch_active_sessions(self, silent=False):
        def worker():
            try:
                headers = {"x-api-key": ADMIN_API_KEY}
                res = requests.get(f"{SERVER_URL}/sessions/active", headers=headers, timeout=10)
                res.raise_for_status()
                data = res.json().get("active_sessions", [])
                self.root.after(0, lambda: self._update_session_ui(data))
            except Exception as e:
                logging.error(f"Session fetch failed: {e}")
                if not silent:
                    self.root.after(0, lambda err=e: self.show_error("فشل جلب الجلسات النشطة", err))
                else:
                    self.set_status("⚠️ Session refresh failed", "red")
        threading.Thread(target=worker, daemon=True).start()

    def _update_session_ui(self, data):
        self.active_sessions_list = data
        for w in self.sessions_list_frame.winfo_children(): w.destroy()
        
        for sess in data:
            token = sess.get("session_token")
            f = ctk.CTkFrame(self.sessions_list_frame)
            f.pack(fill="x", pady=2, padx=5)

            # Visual feedback for selection
            if self.selected_session_token == token:
                f.configure(border_width=2, border_color="orange")

            def select_this(e, t=token):
                self.selected_session_token = t
                self._update_session_ui(self.active_sessions_list)

            student = sess.get("students", {})
            txt = f"👤 {student.get('full_name')} | 📱 {sess.get('device_id')} | 🕒 {sess.get('created_at','')[:16]}"
            lbl = ctk.CTkLabel(f, text=txt, anchor="w", font=("Segoe UI", 15), text_color="black")
            lbl.pack(side="left", padx=10, fill="x", expand=True)

            # Bind clicks for selection
            f.bind("<Button-1>", select_this)
            lbl.bind("<Button-1>", select_this)

            ctk.CTkButton(f, text="End", width=60, fg_color="orange", 
                          command=lambda t=token: self.force_end_session(t)).pack(side="right", padx=5)
        
        self.sessions_count_var.set(f"Active Sessions: {len(data)}")
        self.last_refresh_var.set(f"Updated: {datetime.now().strftime('%H:%M:%S')}")

    def force_end_selected_session(self):
        if not self.selected_session_token:
            messagebox.showwarning("Warning", "Please select a session row first (click on the row).")
            return

        if messagebox.askyesno("Confirm", "Are you sure you want to force-end the selected session?"):
            self.force_end_session(self.selected_session_token)
            self.selected_session_token = None

    def force_end_session(self, token):
        if not token: return
        self.set_status("⏳ Ending session...", "orange")
        def worker():
            try:
                headers = {"x-api-key": ADMIN_API_KEY}
                requests.post(f"{SERVER_URL}/sessions/force_end/{token}", headers=headers, timeout=10).raise_for_status()
                self.root.after(0, lambda: [
                    self.set_status("✅ Session force-ended", "green"),
                    self.fetch_active_sessions()
                ])
            except Exception as e:
                self.root.after(0, lambda err=e: self.show_error("فشل إنهاء الجلسة", err))
        threading.Thread(target=worker, daemon=True).start()

    def toggle_auto_refresh(self):
        if self.auto_refresh_job is None:
            self.auto_refresh_sessions()
            self.auto_refresh_btn.configure(text="⏹ Stop Auto-Refresh", fg_color="red")
        else:
            self.root.after_cancel(self.auto_refresh_job)
            self.auto_refresh_job = None
            self.auto_refresh_btn.configure(text="▶ Start Auto-Refresh", fg_color="green")

    def auto_refresh_sessions(self):
        self.fetch_active_sessions(silent=True)
        self.auto_refresh_job = self.root.after(30000, self.auto_refresh_sessions)

    # --- Reports ---

    def generate_report(self, r_type):
        self.set_status(f"⏳ Generating {r_type} report...", "orange")
        def worker():
            try:
                headers = {"x-api-key": ADMIN_API_KEY}
                res = requests.get(f"{SERVER_URL}/reports/{r_type}", headers=headers, timeout=15)
                res.raise_for_status()
                data = res.json()
                self.current_report_data = data
                
                self.root.after(0, lambda: [
                    self.show_report_popup(r_type, data), 
                    self.export_btn.configure(state="normal"),
                    self.set_status(f"✅ {r_type} report generated", "green")
                ])
            except Exception as e:
                self.root.after(0, lambda err=e: self.show_error("فشل إنشاء التقرير", err))
        threading.Thread(target=worker, daemon=True).start()

    def show_report_popup(self, report_type, data):
        if not data:
            messagebox.showinfo("تنبيه", "لا توجد أي بيانات لعرضها في هذا التقرير.")
            return

        top = ctk.CTkToplevel(self.root)
        top.title(f"📊 تقرير {report_type.title()}")
        top.geometry("950x550")
        top.grab_set()

        tree_frame = ctk.CTkFrame(top)
        tree_frame.pack(fill="both", expand=True, padx=15, pady=15)

        tree_scroll_y = ttk.Scrollbar(tree_frame)
        tree_scroll_y.pack(side="right", fill="y")
        tree_scroll_x = ttk.Scrollbar(tree_frame, orient="horizontal")
        tree_scroll_x.pack(side="bottom", fill="x")

        columns = list(data[0].keys())
        
        style = ttk.Style()
        style.theme_use("clam") # 'clam' usually looks better with CustomTkinter colors
        style.configure("Treeview.Heading", font=("Segoe UI", 11, "bold"), background="#f0f0f0")
        style.configure("Treeview", rowheight=30, font=("Segoe UI", 10))

        tree = ttk.Treeview(tree_frame, columns=columns, show="headings", 
                            yscrollcommand=tree_scroll_y.set, xscrollcommand=tree_scroll_x.set)
        
        tree_scroll_y.config(command=tree.yview)
        tree_scroll_x.config(command=tree.xview)

        for col in columns:
            col_name = str(col).replace("_", " ").title()
            tree.heading(col, text=col_name)
            col_width = 230 if "email" in col.lower() or "name" in col.lower() else 110
            tree.column(col, width=col_width, anchor="center")

        tree.pack(fill="both", expand=True)

        for row in data:
            values = [str(row.get(col, "")) for col in columns]
            tree.insert("", "end", values=values)

        ctk.CTkButton(top, text="❌ إغلاق", command=top.destroy, width=150, fg_color="#e74c3c").pack(pady=10)

    def export_report_to_excel(self):
        if not PANDAS_AVAILABLE:
            messagebox.showerror("Error", "Library 'pandas' and 'openpyxl' are required for export.\nRun: pip install pandas openpyxl")
            return
            
        path = filedialog.asksaveasfilename(defaultextension=".xlsx", filetypes=[("Excel", "*.xlsx")])
        if not path: return
        try:
            df = pd.DataFrame(self.current_report_data)
            df.to_excel(path, index=False)
            messagebox.showinfo("Success", "Exported successfully!")
        except Exception as e: messagebox.showerror("Error", str(e))

    # --- Server Mgmt ---
    def run_server(self):
        import uvicorn
        try:
            uvicorn.run(server_app, host="127.0.0.1", port=8000, log_level="warning")
        except Exception as e:
            if "address already in use" in str(e).lower():
                logging.warning("⚠️ Server already running on port 8000")
            else:
                logging.error(f"Server Error: {e}")

    def wait_for_server_and_load(self):
        for _ in range(10):
            try:
                requests.get(f"{SERVER_URL}/docs", timeout=2)
                self.root.after(0, self.fetch_active_sessions)
                return
            except: time.sleep(1)

    def delete_student(self):
        s = self.get_selected()
        if not s: return
        if messagebox.askyesno("Confirm", f"Permanently delete {s['full_name']}?"):
            self.set_status(f"⏳ Deleting {s['full_name']}...", "orange")
            def worker():
                try:
                    supabase.table("students").delete().eq("id", s["id"]).execute()
                    supabase.auth.admin.delete_user(s["id"])
                    self.root.after(0, lambda: [
                        self.set_status(f"🗑️ Deleted {s['full_name']}", "green"),
                        self.refresh_students()
                    ])
                except Exception as e:
                    self.root.after(0, lambda err=e: self.show_error("فشل حذف الطالب", err))
            threading.Thread(target=worker, daemon=True).start()

    def show_error(self, msg, e):
        raw = str(e)
        if hasattr(e, 'message'):
            raw = e.message

        # Translate common errors
        if "duplicate key" in raw.lower():
            friendly = "⚠️ يوجد تكرار في البيانات — تأكد من عدم وجود عنصر مشابه."
        elif "foreign key" in raw.lower():
            friendly = "⚠️ لا يمكن الحذف — يوجد بيانات مرتبطة بهذا العنصر."
        elif "network" in raw.lower() or "connection" in raw.lower():
            friendly = "⚠️ خطأ في الاتصال بالخادم — تحقق من الإنترنت."
        elif "jwt" in raw.lower() or "auth" in raw.lower():
            friendly = "⚠️ خطأ في المصادقة — تحقق من مفاتيح Supabase في .env"
        elif "not found" in raw.lower():
            friendly = "⚠️ العنصر غير موجود — ربما تم حذفه مسبقاً."
        elif "timeout" in raw.lower():
            friendly = "⚠️ انتهت مهلة الاتصال بالخادم."
        else:
            friendly = raw

        logging.error(f"{msg}: {raw}", exc_info=True)
        self.set_status(f"❌ Error: {msg}", "red")
        messagebox.showerror("❌ خطأ", f"{msg}\n\n{friendly}\n\n(راجع الـ logs للتفاصيل)")

    def set_status(self, msg, color="gray"):
        """تحديث شريط الحالة في أسفل الشاشة"""
        try:
            self.status_label.configure(text=msg, text_color=color)
        except Exception:
            print(f"[STATUS] {msg}")

    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    app = StudentManagerApp()
    app.run()