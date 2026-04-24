# video_manager.py
# 🎬 Video & Course Manager - Desktop Admin Tool (with Upload Support)
import os
import threading
import logging
import time
import json
from tkinter import filedialog, messagebox, simpledialog
import customtkinter as ctk
from supabase import create_client, Client
from dotenv import load_dotenv
from dataclasses import dataclass
from typing import List
from io import BytesIO

# ── Drag-and-drop support (optional dependency) ──────────────────────────
try:
    from tkinterdnd2 import TkinterDnD, DND_FILES
    HAS_DND = True
except ImportError:
    HAS_DND = False
    DND_FILES = None
    logging.info("tkinterdnd2 not installed – drag-and-drop disabled.")
    logging.info("  Install with: pip install tkinterdnd2")

try:
    from PIL import Image, ImageTk
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("PIL not available. No image preview.")

# --- CONFIG ---
@dataclass
class AppConfig:
    supabase_url: str = None
    supabase_key: str = None
    page_size: int = 20
    video_bucket: str = "videos"
    thumbnail_bucket: str = "videos"  # Same bucket, different folder
    max_video_size: int = 50 * 1024 * 1024  # 50MB (Supabase Free Tier Limit)
    allowed_video_ext: List[str] = None

    def __post_init__(self):
        if self.allowed_video_ext is None:
            self.allowed_video_ext = ['.mp4', '.webm', '.mov', '.avi', '.mkv']
        if self.supabase_url is None:
            self.supabase_url = os.getenv("SUPABASE_URL")
        if self.supabase_key is None:
            self.supabase_key = os.getenv("SUPABASE_SERVICE_KEY")
        if not self.supabase_url or not self.supabase_key:
            raise ValueError("Supabase credentials not found in .env")

# --- INIT ---
script_dir = os.path.dirname(os.path.abspath(__file__))
dotenv_path = os.path.join(script_dir, ".env")
load_dotenv(dotenv_path)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

config = AppConfig()
supabase: Client = create_client(config.supabase_url, config.supabase_key)

# --- CONSTANTS ---
CONTENT_TYPES = {
    '.mp4': 'video/mp4',
    '.webm': 'video/webm',
    '.mov': 'video/quicktime',
    '.avi': 'video/x-msvideo',
    '.mkv': 'video/x-matroska'
}


# --- MAIN APP ---
class VideoManagerApp:
    def __init__(self):
        ctk.set_appearance_mode("System")
        ctk.set_default_color_theme("blue")

        # Use TkinterDnD-aware root when the library is available
        if HAS_DND:
            self.app = TkinterDnD.Tk()
            # Re-apply customtkinter theme after TkinterDnD.Tk() creation
            ctk.set_appearance_mode("System")
            ctk.set_default_color_theme("blue")
        else:
            self.app = ctk.CTk()
        self.app.geometry("1300x850")
        self.app.title("🎬 Video & Course Manager")

        # Data
        self.courses = []
        self.current_lessons = []
        self.selected_course_id = None
        self.selected_course_name = ctk.StringVar()
        self.lesson_checkbox_vars = {}
        self.current_page = 1
        self.display_job = None
        self.upload_in_progress = False
        self.order_changed = False
        self._search_after_id = None

        # Build UI
        self.setup_ui()
        self.load_courses()

    # ===========================
    # UI SETUP
    # ===========================
    def setup_ui(self):
        # Status bar at the bottom
        status_bar = ctk.CTkFrame(self.app, height=28, corner_radius=0)
        status_bar.pack(fill="x", side="bottom")
        status_bar.pack_propagate(False)
        self.status_label = ctk.CTkLabel(
            status_bar, text="✅ جاهز", font=("", 11), anchor="w"
        )
        self.status_label.pack(side="left", padx=10)

        self.main_container = ctk.CTkFrame(self.app)
        self.main_container.pack(fill="both", expand=True, padx=10, pady=10)

        self.setup_courses_panel()
        self.setup_lessons_panel()
        self.setup_bottom_bar()

    def set_status(self, msg, color="gray"):
        self.app.after(0, lambda: self.status_label.configure(text=msg, text_color=color))

    def setup_courses_panel(self):
        left_frame = ctk.CTkFrame(self.main_container, width=350)
        left_frame.pack(side="left", fill="y", padx=(0, 5))
        left_frame.pack_propagate(False)

        header = ctk.CTkFrame(left_frame)
        header.pack(fill="x", padx=5, pady=5)
        ctk.CTkLabel(header, text="📚 Courses", font=("", 18, "bold")).pack(side="left", padx=10)
        ctk.CTkButton(header, text="➕ Add", width=80, command=self.add_course).pack(side="right", padx=5)

        self.course_search_var = ctk.StringVar()
        self.course_search_var.trace_add("write", self.filter_courses)
        ctk.CTkEntry(
            left_frame, placeholder_text="🔍 Search courses...",
            textvariable=self.course_search_var
        ).pack(fill="x", padx=10, pady=5)

        self.courses_list_frame = ctk.CTkScrollableFrame(left_frame)
        self.courses_list_frame.pack(fill="both", expand=True, padx=5, pady=5)

    def setup_lessons_panel(self):
        right_frame = ctk.CTkFrame(self.main_container)
        right_frame.pack(side="right", fill="both", expand=True, padx=(5, 0))

        top = ctk.CTkFrame(right_frame)
        top.pack(fill="x", padx=5, pady=5)

        self.lessons_title_label = ctk.CTkLabel(
            top, text="🎬 Select a course to view lessons",
            font=("", 16, "bold")
        )
        self.lessons_title_label.pack(side="left", padx=10)

        # Buttons row 1
        self.btn_add_lesson = ctk.CTkButton(
            top, text="➕ Add Lesson", command=self.add_lesson, state="disabled"
        )
        self.btn_add_lesson.pack(side="right", padx=5)

        self.btn_upload_video = ctk.CTkButton(
            top, text="📤 Bulk Upload", command=self.upload_multiple_videos,
            state="disabled", fg_color="#8B5CF6"
        )
        self.btn_upload_video.pack(side="right", padx=5)

        self.btn_delete_selected = ctk.CTkButton(
            top, text="🗑️ Delete Selected", fg_color="red",
            command=self.delete_selected_lessons, state="disabled"
        )
        self.btn_delete_selected.pack(side="right", padx=5)

        self.btn_reorder = ctk.CTkButton(
            top, text="🔃 Save Order", command=self.save_lesson_order, state="disabled"
        )
        self.btn_reorder.pack(side="right", padx=5)

        # Upload progress bar (hidden by default)
        self.upload_progress_frame = ctk.CTkFrame(right_frame)
        self.upload_progress_label = ctk.CTkLabel(
            self.upload_progress_frame, text="Uploading...", font=("", 12)
        )
        self.upload_progress_label.pack(side="left", padx=10)
        self.upload_progress_bar = ctk.CTkProgressBar(self.upload_progress_frame, width=400)
        self.upload_progress_bar.pack(side="left", padx=10, fill="x", expand=True)
        self.upload_progress_bar.set(0)
        self.upload_percent_label = ctk.CTkLabel(
            self.upload_progress_frame, text="0%", font=("", 12, "bold"), width=50
        )
        self.upload_percent_label.pack(side="right", padx=10)
        # Hidden initially
        # self.upload_progress_frame.pack(...)

        # Drag-and-drop zone hint label (shown only when DnD is available)
        if HAS_DND:
            self.dnd_hint_label = ctk.CTkLabel(
                right_frame,
                text="📂 اسحب ملفات الفيديو هنا للرفع التلقائي  (Drag & Drop videos here)",
                font=("", 12), text_color="gray",
                fg_color=("gray90", "gray18"), corner_radius=8
            )
            self.dnd_hint_label.pack(fill="x", padx=5, pady=(0, 4))

        # Lessons list
        self.lessons_frame = ctk.CTkScrollableFrame(right_frame)
        self.lessons_frame.pack(fill="both", expand=True, padx=5, pady=5)

        # Register drag-and-drop on the main window after widgets are ready
        if HAS_DND:
            self.app.after(100, self._setup_drag_drop)

    def setup_bottom_bar(self):
        bottom = ctk.CTkFrame(self.app)
        bottom.pack(pady=5, fill="x", padx=10)

        self.prev_page_btn = ctk.CTkButton(
            bottom, text="⬅️ Previous", command=self.prev_page, state="disabled"
        )
        self.prev_page_btn.pack(side="left", padx=10)

        self.page_label = ctk.CTkLabel(bottom, text="Page 1 / 1")
        self.page_label.pack(side="left", expand=True)

        self.next_page_btn = ctk.CTkButton(
            bottom, text="Next ➡️", command=self.next_page, state="disabled"
        )
        self.next_page_btn.pack(side="right", padx=10)

        self.stats_label = ctk.CTkLabel(bottom, text="", font=("", 12))
        self.stats_label.pack(side="right", padx=20)

    # ===========================
    # UPLOAD PROGRESS UI
    # ===========================
    def show_upload_progress(self, filename=""):
        self.upload_progress_frame.pack(fill="x", padx=5, pady=(0, 5))
        self.upload_progress_label.configure(text=f"📤 Uploading: {filename}")
        self.upload_progress_bar.set(0)
        self.upload_percent_label.configure(text="0%")
        self.upload_in_progress = True

    def update_upload_progress(self, progress, status_text=None):
        self.upload_progress_bar.set(progress)
        self.upload_percent_label.configure(text=f"{int(progress * 100)}%")
        if status_text:
            self.upload_progress_label.configure(text=status_text)

    def hide_upload_progress(self):
        self.upload_progress_frame.pack_forget()
        self.upload_in_progress = False

    # ===========================
    # VIDEO FILE UPLOAD
    # ===========================
    def upload_video_file(self):
        """Upload a video file from the computer and create a lesson."""
        if not self.selected_course_id:
            messagebox.showerror("Error", "Select a course first!")
            return

        if self.upload_in_progress:
            messagebox.showwarning("Warning", "An upload is already in progress!")
            return

        file_path = filedialog.askopenfilename(
            title="Select Video File",
            filetypes=[
                ("Video files", "*.mp4 *.webm *.mov *.avi *.mkv"),
                ("MP4", "*.mp4"),
                ("WebM", "*.webm"),
                ("MOV", "*.mov"),
                ("All files", "*.*")
            ]
        )
        if not file_path:
            return

        # Validate file
        file_size = os.path.getsize(file_path)
        file_ext = os.path.splitext(file_path)[1].lower()

        if file_ext not in config.allowed_video_ext:
            messagebox.showerror("Error", f"Unsupported format: {file_ext}\nAllowed: {', '.join(config.allowed_video_ext)}")
            return

        if file_size > config.max_video_size:
            size_mb = config.max_video_size // (1024 * 1024)
            messagebox.showerror("Error", f"File too large! Max: {size_mb}MB")
            return

        # Show upload dialog for lesson details
        self._show_upload_lesson_dialog(file_path, file_size)

    def _show_upload_lesson_dialog(self, file_path, file_size):
        """Dialog to fill lesson details before uploading."""
        filename = os.path.basename(file_path)
        file_size_mb = file_size / (1024 * 1024)

        dialog = ctk.CTkToplevel(self.app)
        dialog.title("📤 Upload Video & Create Lesson")
        dialog.geometry("550x550")
        dialog.transient(self.app)
        dialog.grab_set()

        frame = ctk.CTkFrame(dialog)
        frame.pack(padx=20, pady=20, fill="both", expand=True)

        # File info
        info_frame = ctk.CTkFrame(frame, fg_color=("gray90", "gray17"))
        info_frame.pack(fill="x", padx=10, pady=(10, 15))

        ctk.CTkLabel(info_frame, text="📁 Selected File:", font=("", 12, "bold")).pack(anchor="w", padx=10, pady=(8, 0))
        ctk.CTkLabel(info_frame, text=filename, font=("", 11)).pack(anchor="w", padx=10)
        ctk.CTkLabel(info_frame, text=f"Size: {file_size_mb:.1f} MB", font=("", 11), text_color="gray").pack(anchor="w", padx=10, pady=(0, 8))

        # Title
        ctk.CTkLabel(frame, text="Lesson Title *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(5, 2))
        title_entry = ctk.CTkEntry(frame, placeholder_text="e.g., Lesson 1 - Introduction")
        # Auto-fill title from filename
        auto_title = os.path.splitext(filename)[0].replace("_", " ").replace("-", " ")
        title_entry.insert(0, auto_title)
        title_entry.pack(fill="x", padx=10, pady=(0, 10))

        # Description
        ctk.CTkLabel(frame, text="Description", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(5, 2))
        desc_text = ctk.CTkTextbox(frame, height=60)
        desc_text.pack(fill="x", padx=10, pady=(0, 10))

        # Duration
        ctk.CTkLabel(frame, text="Duration (minutes)", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(5, 2))
        duration_entry = ctk.CTkEntry(frame, placeholder_text="e.g., 15")
        duration_entry.pack(fill="x", padx=10, pady=(0, 10))

        # Options
        options_frame = ctk.CTkFrame(frame, fg_color="transparent")
        options_frame.pack(fill="x", padx=10, pady=5)

        published_var = ctk.BooleanVar(value=True)
        ctk.CTkCheckBox(options_frame, text="Published", variable=published_var).pack(side="left", padx=10)

        free_var = ctk.BooleanVar(value=False)
        ctk.CTkCheckBox(options_frame, text="Free Preview", variable=free_var).pack(side="left", padx=10)

        def start_upload():
            title = title_entry.get().strip()
            if not title:
                messagebox.showerror("Error", "Title is required!", parent=dialog)
                return

            try:
                duration_val = int(duration_entry.get().strip()) if duration_entry.get().strip() else None
            except ValueError:
                duration_val = None

            lesson_data = {
                "title": title,
                "description": desc_text.get("1.0", "end-1c").strip() or None,
                "duration_minutes": duration_val,
                "is_published": published_var.get(),
                "is_free": free_var.get(),
                "sort_order": len(self.current_lessons)
            }

            dialog.destroy()
            self._execute_video_upload(file_path, lesson_data)

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="📤 Upload & Create", command=start_upload, fg_color="#8B5CF6").pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)

        self.app.wait_window(dialog)

    def _execute_video_upload(self, file_path, lesson_data):
        """Execute the actual upload in a background thread."""
        filename = os.path.basename(file_path)

        self.app.after(0, lambda: self.show_upload_progress(filename))

        def worker():
            try:
                # Step 1: Get next sort order from DB
                max_res = supabase.table("lessons").select("sort_order")\
                    .eq("course_id", self.selected_course_id)\
                    .order("sort_order", desc=True).limit(1).execute()
                next_order = (max_res.data[0]["sort_order"] + 1) if max_res.data else 0

                # Step 2: Generate unique storage path
                import uuid
                file_ext = os.path.splitext(filename)[1]
                unique_name = f"{uuid.uuid4().hex}{file_ext}"
                course_id = self.selected_course_id
                storage_path = f"courses/{course_id}/{unique_name}"

                file_size = os.path.getsize(file_path)

                # Step 3: Upload to Supabase Storage
                self.app.after(0, lambda: self.update_upload_progress(0.1, f"📤 جارٍ التحميل: {filename} ..."))

                with open(file_path, "rb") as f:
                    file_data = f.read()

                content_type = CONTENT_TYPES.get(file_ext.lower(), 'video/mp4')
                self.app.after(0, lambda: self.update_upload_progress(0.4, f"📤 جارٍ الرفع إلى التخزين..."))

                supabase.storage.from_(config.video_bucket).upload(
                    storage_path,
                    file_data,
                    {"content-type": content_type, "x-upsert": "true"}
                )

                self.app.after(0, lambda: self.update_upload_progress(0.8, "✅ اكتمل الرفع! يتم الحفظ..."))

                video_url = supabase.storage.from_(config.video_bucket).get_public_url(storage_path)

                # Step 4: Create lesson record
                supabase.table("lessons").insert({
                    "course_id": course_id,
                    "title": lesson_data["title"],
                    "description": lesson_data.get("description"),
                    "video_url": video_url,
                    "video_type": "direct",
                    "duration_minutes": lesson_data.get("duration_minutes"),
                    "sort_order": next_order,
                    "is_published": lesson_data.get("is_published", True),
                    "is_free": lesson_data.get("is_free", False)
                }).execute()

                self.app.after(0, lambda: self.update_upload_progress(1.0, "✅ تم بنجاح!"))
                
                time.sleep(1)

                def on_complete():
                    self.hide_upload_progress()
                    messagebox.showinfo("✅ تم الرفع", 
                        f"تم بنجاح رفع: {lesson_data['title']}\n"
                        f"الحجم: {file_size / (1024*1024):.1f} MB")
                    self.refresh_lessons()
                    self.load_courses()

                self.app.after(0, on_complete)

            except Exception as e:
                self.app.after(0, lambda: [self.hide_upload_progress(), self.show_error("فشل رفع الملف", e)])

        threading.Thread(target=worker, daemon=True).start()

    def upload_multiple_videos(self):
        """Upload multiple video files at once."""
        if not self.selected_course_id:
            messagebox.showerror("Error", "Select a course first!")
            return

        if self.upload_in_progress:
            messagebox.showwarning("Warning", "An upload is already in progress!")
            return

        files = filedialog.askopenfilenames(
            title="Select Video Files",
            filetypes=[
                ("Video files", "*.mp4 *.webm *.mov *.avi *.mkv"),
                ("All files", "*.*")
            ]
        )
        if not files:
            return

        # Validate all files first
        valid_files = []
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            size = os.path.getsize(f)
            if ext not in config.allowed_video_ext:
                messagebox.showwarning("Skipped", f"Skipping {os.path.basename(f)}: unsupported format")
                continue
            if size > config.max_video_size:
                messagebox.showwarning("Skipped", f"Skipping {os.path.basename(f)}: too large")
                continue
            valid_files.append(f)

        if not valid_files:
            return

        if not messagebox.askyesno("Confirm", f"Upload {len(valid_files)} videos to the selected course?"):
            return

        self.app.after(0, lambda: self.show_upload_progress(f"{len(valid_files)} files"))

        def worker():
            import uuid
            total = len(valid_files)
            succeeded = 0
            failed_files = []
            
            # Accurate sort order for batch
            try:
                max_res = supabase.table("lessons").select("sort_order")\
                    .eq("course_id", self.selected_course_id)\
                    .order("sort_order", desc=True).limit(1).execute()
                next_order = (max_res.data[0]["sort_order"] + 1) if max_res.data else 0
            except:
                next_order = 0

            for i, file_path in enumerate(valid_files):
                try:
                    filename = os.path.basename(file_path)
                    file_ext = os.path.splitext(filename)[1]
                    unique_name = f"{uuid.uuid4().hex}{file_ext}"
                    storage_path = f"courses/{self.selected_course_id}/{unique_name}"

                    progress = (i + 1) / total
                    self.app.after(0, lambda p=progress, fn=filename, cur=i+1:
                        self.update_upload_progress(p, f"📤 [{cur}/{total}] {fn}"))

                    content_type = CONTENT_TYPES.get(file_ext.lower(), 'video/mp4')

                    with open(file_path, "rb") as f:
                        file_data = f.read()

                    supabase.storage.from_(config.video_bucket).upload(
                        storage_path, file_data,
                        {"content-type": content_type, "x-upsert": "true"}
                    )

                    video_url = supabase.storage.from_(config.video_bucket).get_public_url(storage_path)
                    auto_title = os.path.splitext(filename)[0].replace("_", " ").replace("-", " ")

                    supabase.table("lessons").insert({
                        "course_id": self.selected_course_id,
                        "title": auto_title,
                        "video_url": video_url,
                        "video_type": "direct",
                        "sort_order": next_order + i,
                        "is_published": True,
                        "is_free": False
                    }).execute()
                    succeeded += 1

                except Exception as e:
                    logging.error(f"Failed to upload {filename}: {e}", exc_info=True)
                    failed_files.append(f"{filename}: {e}")

            self.app.after(0, lambda: self.update_upload_progress(1.0, "✅ اكتملت جميع الرفوعات!"))
            time.sleep(1)

            def on_complete(s=succeeded, f=failed_files):
                self.hide_upload_progress()
                if not f:
                    messagebox.showinfo("✅ تم الرفع", f"تم رفع جميع الملفات ({s}) بنجاح.")
                else:
                    messagebox.showwarning("⚠️ اكتمل بنجاح جزئي", f"تم رفع {s} وفشل {len(f)} ملفات.")
                self.refresh_lessons()
                self.load_courses()
            self.app.after(0, on_complete)

        threading.Thread(target=worker, daemon=True).start()

    # ===========================
    # COURSES - CRUD
    # ===========================
    def load_courses(self):
        def worker():
            try:
                resp = supabase.table("courses").select("*").order("sort_order").execute()
                courses = resp.data or []

                if courses:
                    # Optimized: Single query for all counts instead of N queries
                    ids = [c["id"] for c in courses]
                    counts_resp = supabase.table("lessons")\
                        .select("course_id")\
                        .in_("course_id", ids)\
                        .execute()

                    count_map = {}
                    for row in (counts_resp.data or []):
                        cid = row["course_id"]
                        count_map[cid] = count_map.get(cid, 0) + 1

                    for course in courses:
                        course["lesson_count"] = count_map.get(course["id"], 0)

                self.app.after(0, lambda: self._display_courses(courses))
            except Exception as e:
                self.app.after(0, lambda: self.show_error("فشل تحميل الكورسات", e))
        threading.Thread(target=worker, daemon=True).start()

    def _display_courses(self, courses):
        self.courses = courses
        self._render_course_list(courses)

    def _render_course_list(self, courses_to_show):
        for widget in self.courses_list_frame.winfo_children():
            widget.destroy()
        if not courses_to_show:
            ctk.CTkLabel(
                self.courses_list_frame, text="No courses yet.\nClick '➕ Add' to create one.",
                font=("", 14), text_color="gray"
            ).pack(pady=40)
            return
        for course in courses_to_show:
            self._create_course_card(course)

    def _create_course_card(self, course):
        is_selected = (course["id"] == self.selected_course_id)
        card_color = ("#1f6aa5", "#1a5276") if is_selected else ("gray85", "gray20")

        card = ctk.CTkFrame(self.courses_list_frame, fg_color=card_color, corner_radius=10)
        card.pack(fill="x", pady=4, padx=5)
        card.bind("<Button-1>", lambda e, c=course: self.select_course(c))

        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(fill="x", padx=10, pady=8)
        inner.bind("<Button-1>", lambda e, c=course: self.select_course(c))

        title_frame = ctk.CTkFrame(inner, fg_color="transparent")
        title_frame.pack(fill="x")
        title_frame.bind("<Button-1>", lambda e, c=course: self.select_course(c))

        title_text_color = "white" if is_selected else None
        title = ctk.CTkLabel(
            title_frame, text=course.get("title", "Untitled"),
            font=("", 14, "bold"), text_color=title_text_color, anchor="w"
        )
        title.pack(side="left", fill="x", expand=True)
        title.bind("<Button-1>", lambda e, c=course: self.select_course(c))

        published = course.get("is_published", True)
        badge_text = "✅" if published else "🚫"
        badge_color = "green" if published else "orange"
        ctk.CTkLabel(title_frame, text=badge_text, font=("", 11), text_color=badge_color).pack(side="right")

        info_frame = ctk.CTkFrame(inner, fg_color="transparent")
        info_frame.pack(fill="x", pady=(4, 0))
        info_frame.bind("<Button-1>", lambda e, c=course: self.select_course(c))

        lesson_count = course.get("lesson_count", 0)
        info_text_color = "white" if is_selected else "gray"
        ctk.CTkLabel(
            info_frame, text=f"📹 {lesson_count} lessons",
            font=("", 12), text_color=info_text_color
        ).pack(side="left")

        btn_frame = ctk.CTkFrame(info_frame, fg_color="transparent")
        btn_frame.pack(side="right")
        ctk.CTkButton(btn_frame, text="✏️", width=30, height=25, command=lambda c=course: self.edit_course(c)).pack(side="left", padx=2)
        ctk.CTkButton(btn_frame, text="🗑️", width=30, height=25, fg_color="red", command=lambda c=course: self.delete_course(c)).pack(side="left", padx=2)

    def filter_courses(self, *args):
        if self._search_after_id:
            self.app.after_cancel(self._search_after_id)
        self._search_after_id = self.app.after(250, self._do_filter)

    def _do_filter(self):
        term = self.course_search_var.get().strip().lower()
        filtered = self.courses if not term else [
            c for c in self.courses if term in c.get("title", "").lower()
        ]
        self._render_course_list(filtered)

    def select_course(self, course):
        self.selected_course_id = course["id"]
        self.selected_course_name.set(course.get("title", ""))
        self.lessons_title_label.configure(text=f"🎬 {course.get('title', '')}")
        self.btn_add_lesson.configure(state="normal")
        self.btn_upload_video.configure(state="normal")
        self.btn_delete_selected.configure(state="normal")
        self.btn_reorder.configure(state="normal")

        self._render_course_list(
            [c for c in self.courses if self.course_search_var.get().strip().lower() in c.get("title", "").lower()]
            if self.course_search_var.get().strip() else self.courses
        )
        self.current_page = 1
        self.order_changed = False
        self.refresh_lessons()

    def add_course(self):
        dialog = ctk.CTkToplevel(self.app)
        dialog.title("➕ Add New Course")
        dialog.geometry("500x500")
        dialog.transient(self.app)
        dialog.grab_set()

        frame = ctk.CTkFrame(dialog)
        frame.pack(padx=20, pady=20, fill="both", expand=True)

        ctk.CTkLabel(frame, text="Course Title *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        title_entry = ctk.CTkEntry(frame, placeholder_text="e.g., Chapter 1 - Introduction")
        title_entry.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Description", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        desc_text = ctk.CTkTextbox(frame, height=100)
        desc_text.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Thumbnail (optional)", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))

        thumb_frame = ctk.CTkFrame(frame, fg_color="transparent")
        thumb_frame.pack(fill="x", padx=10, pady=(0, 10))
        thumb_entry = ctk.CTkEntry(thumb_frame, placeholder_text="URL or click Browse to upload")
        thumb_entry.pack(side="left", fill="x", expand=True, padx=(0, 5))

        def browse_thumbnail():
            img_path = filedialog.askopenfilename(
                title="Select Thumbnail Image",
                filetypes=[("Images", "*.png *.jpg *.jpeg *.webp")]
            )
            if img_path:
                thumb_entry.delete(0, "end")
                thumb_entry.insert(0, f"[LOCAL]{img_path}")

        ctk.CTkButton(thumb_frame, text="📁 Browse", width=80, command=browse_thumbnail).pack(side="right")

        ctk.CTkLabel(frame, text="Sort Order", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        sort_entry = ctk.CTkEntry(frame)
        sort_entry.insert(0, str(len(self.courses)))
        sort_entry.pack(fill="x", padx=10, pady=(0, 10))

        published_var = ctk.BooleanVar(value=True)
        ctk.CTkCheckBox(frame, text="Published", variable=published_var).pack(anchor="w", padx=10, pady=10)

        def save():
            title = title_entry.get().strip()
            if not title:
                messagebox.showerror("Error", "Title required!", parent=dialog)
                return

            try:
                sort_val = int(sort_entry.get().strip() or "0")
            except ValueError:
                sort_val = 0

            thumb_url = None
            thumb_value = thumb_entry.get().strip()

            # Handle local thumbnail upload
            if thumb_value.startswith("[LOCAL]"):
                local_path = thumb_value.replace("[LOCAL]", "")
                try:
                    import uuid
                    ext = os.path.splitext(local_path)[1]
                    storage_path = f"thumbnails/{uuid.uuid4().hex}{ext}"
                    with open(local_path, "rb") as f:
                        supabase.storage.from_(config.thumbnail_bucket).upload(
                            storage_path, f.read(),
                            {"content-type": f"image/{ext.replace('.', '')}", "x-upsert": "true"}
                        )
                    thumb_url = supabase.storage.from_(config.thumbnail_bucket).get_public_url(storage_path)
                except Exception as e:
                    self.show_error("Thumbnail upload failed", e)
                    # Process continues without thumbnail
            elif thumb_value:
                thumb_url = thumb_value

            try:
                supabase.table("courses").insert({
                    "title": title,
                    "description": desc_text.get("1.0", "end-1c").strip() or None,
                    "thumbnail_url": thumb_url,
                    "sort_order": sort_val,
                    "is_published": published_var.get()
                }).execute()
                messagebox.showinfo("Success", f"Course '{title}' created!", parent=dialog)
                dialog.destroy()
                self.load_courses()
            except Exception as e:
                self.show_error("Failed to create course", e)

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="💾 Save", command=save).pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)
        self.app.wait_window(dialog)

    def edit_course(self, course):
        dialog = ctk.CTkToplevel(self.app)
        dialog.title(f"✏️ Edit: {course.get('title', '')}")
        dialog.geometry("500x500")
        dialog.transient(self.app)
        dialog.grab_set()

        frame = ctk.CTkFrame(dialog)
        frame.pack(padx=20, pady=20, fill="both", expand=True)

        ctk.CTkLabel(frame, text="Course Title *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        title_entry = ctk.CTkEntry(frame)
        title_entry.insert(0, course.get("title", ""))
        title_entry.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Description", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        desc_text = ctk.CTkTextbox(frame, height=100)
        desc_text.insert("1.0", course.get("description", "") or "")
        desc_text.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Thumbnail URL", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        thumb_entry = ctk.CTkEntry(frame)
        thumb_entry.insert(0, course.get("thumbnail_url", "") or "")
        thumb_entry.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Sort Order", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        sort_entry = ctk.CTkEntry(frame)
        sort_entry.insert(0, str(course.get("sort_order", 0)))
        sort_entry.pack(fill="x", padx=10, pady=(0, 10))

        published_var = ctk.BooleanVar(value=course.get("is_published", True))
        ctk.CTkCheckBox(frame, text="Published", variable=published_var).pack(anchor="w", padx=10, pady=10)

        def save():
            title = title_entry.get().strip()
            if not title:
                messagebox.showerror("Error", "Title required!", parent=dialog)
                return
            try:
                sort_val = int(sort_entry.get().strip() or "0")
            except ValueError:
                sort_val = 0
            try:
                supabase.table("courses").update({
                    "title": title,
                    "description": desc_text.get("1.0", "end-1c").strip() or None,
                    "thumbnail_url": thumb_entry.get().strip() or None,
                    "sort_order": sort_val,
                    "is_published": published_var.get()
                }).eq("id", course["id"]).execute()
                messagebox.showinfo("Success", "Course updated!", parent=dialog)
                dialog.destroy()
                self.load_courses()
            except Exception as e:
                self.show_error("Failed to update course", e)

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="💾 Save", command=save).pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)
        self.app.wait_window(dialog)

    def delete_course(self, course):
        lesson_count = course.get("lesson_count", 0)
        msg = f"Delete course '{course['title']}'?"
        if lesson_count > 0:
            msg += f"\n\n⚠️ This will also delete {lesson_count} lessons!"
        if not messagebox.askyesno("Confirm Delete", msg):
            return
        try:
            supabase.table("courses").delete().eq("id", course["id"]).execute()
            if self.selected_course_id == course["id"]:
                self.selected_course_id = None
                self.current_lessons = []
                self._clear_lessons_display()
                self.lessons_title_label.configure(text="🎬 Select a course")
                self.btn_add_lesson.configure(state="disabled")
                self.btn_upload_video.configure(state="disabled")
            self.load_courses()
        except Exception as e:
            self.show_error("Failed to delete course", e)

    # ===========================
    # LESSONS - CRUD
    # ===========================
    def refresh_lessons(self, page_change=False):
        if not self.selected_course_id:
            return
        if not page_change:
            self.current_page = 1

        # Show loading indicator
        self._clear_lessons_display()
        ctk.CTkLabel(
            self.lessons_frame,
            text="⏳ جارٍ تحميل الدروس...",
            font=("", 14), text_color="gray"
        ).pack(pady=40)
        self.set_status("⏳ جارٍ التحميل...")

        def worker():
            try:
                course_id = self.selected_course_id
                count_resp = supabase.table("lessons").select("id", count="exact").eq("course_id", course_id).execute()
                total_items = count_resp.count or 0
                total_pages = max(1, (total_items + config.page_size - 1) // config.page_size)

                start = (self.current_page - 1) * config.page_size
                end = start + config.page_size - 1
                resp = supabase.table("lessons").select("*").eq("course_id", course_id).order("sort_order").range(start, end).execute()
                lessons = resp.data or []

                def on_success():
                    self.set_status(f"✅ تم تحميل {total_items} درس")
                    self._apply_lesson_data(lessons, total_pages, total_items)

                self.app.after(0, on_success)
            except Exception as e:
                self.app.after(0, lambda: self.show_error("Failed to load lessons", e))
        threading.Thread(target=worker, daemon=True).start()

    def _apply_lesson_data(self, lessons, total_pages, total_items):
        self.current_lessons = lessons
        self.display_lessons()
        self.page_label.configure(text=f"Page {self.current_page} / {total_pages}")
        self.prev_page_btn.configure(state="normal" if self.current_page > 1 else "disabled")
        self.next_page_btn.configure(state="normal" if self.current_page < total_pages else "disabled")
        self.stats_label.configure(text=f"Total: {total_items} lessons")

    def display_lessons(self):
        if self.display_job:
            self.app.after_cancel(self.display_job)
        self._clear_lessons_display()
        self.lesson_checkbox_vars.clear()

        if not self.current_lessons:
            ctk.CTkLabel(
                self.lessons_frame,
                text="No lessons yet.\nClick '➕ Add Lesson' or '📤 Upload Video' to start.",
                font=("", 14), text_color="gray"
            ).pack(pady=40)
        else:
            lesson_iterator = iter(enumerate(self.current_lessons))
            self._display_next_lesson(lesson_iterator)

    def _display_next_lesson(self, iterator):
        try:
            index, lesson = next(iterator)
            self._create_lesson_widget(lesson, index)
            self.display_job = self.app.after(10, self._display_next_lesson, iterator)
        except StopIteration:
            self.display_job = None

    def _create_lesson_widget(self, lesson, index):
        card = ctk.CTkFrame(self.lessons_frame, corner_radius=10)
        card.pack(fill="x", pady=4, padx=5)

        var = ctk.BooleanVar()
        self.lesson_checkbox_vars[lesson["id"]] = var
        ctk.CTkCheckBox(card, text="", variable=var, width=20).pack(side="left", padx=(10, 5))

        num_label = ctk.CTkLabel(card, text=f"#{index + 1}", font=("", 14, "bold"), width=40)
        num_label.pack(side="left", padx=5)

        video_type = lesson.get("video_type", "youtube")
        type_icons = {"youtube": "🔴 YT", "vimeo": "🔵 Vim", "direct": "🎞️ File", "drive": "📁 Drv"}
        ctk.CTkLabel(card, text=type_icons.get(video_type, "📹"), font=("", 11), width=70).pack(side="left", padx=5)

        info_frame = ctk.CTkFrame(card, fg_color="transparent")
        info_frame.pack(side="left", fill="x", expand=True, padx=10)

        ctk.CTkLabel(info_frame, text=lesson.get("title", "Untitled"), font=("", 14, "bold"), anchor="w").pack(fill="x")

        meta_frame = ctk.CTkFrame(info_frame, fg_color="transparent")
        meta_frame.pack(fill="x")

        duration = lesson.get("duration_minutes")
        if duration:
            ctk.CTkLabel(meta_frame, text=f"⏱️ {duration}m", font=("", 11), text_color="gray").pack(side="left", padx=(0, 8))
        if lesson.get("is_free"):
            ctk.CTkLabel(meta_frame, text="🆓", font=("", 11), text_color="green").pack(side="left", padx=(0, 8))

        published = lesson.get("is_published", True)
        status = "✅" if published else "🚫"
        ctk.CTkLabel(meta_frame, text=status, font=("", 11)).pack(side="left")

        url = lesson.get("video_url", "")
        short = url[:50] + "..." if len(url) > 50 else url
        ctk.CTkLabel(meta_frame, text=f"🔗 {short}", font=("", 10), text_color="gray").pack(side="left", padx=(8, 0))

        # Move buttons for reordering
        move_frame = ctk.CTkFrame(card, fg_color="transparent")
        move_frame.pack(side="right", padx=5)
        ctk.CTkButton(
            move_frame, text="⬆", width=28, height=26,
            command=lambda i=index: self.move_lesson(i, -1)
        ).pack(pady=1)
        ctk.CTkButton(
            move_frame, text="⬇", width=28, height=26,
            command=lambda i=index: self.move_lesson(i, 1)
        ).pack(pady=1)

        # Buttons
        btn_frame = ctk.CTkFrame(card, fg_color="transparent")
        btn_frame.pack(side="right", padx=5)
        ctk.CTkButton(btn_frame, text="✏️", width=30, height=28, command=lambda l=lesson: self.edit_lesson(l)).pack(side="left", padx=2)
        ctk.CTkButton(btn_frame, text="📋", width=30, height=28, fg_color="gray", command=lambda l=lesson: self.copy_video_url(l)).pack(side="left", padx=2)
        ctk.CTkButton(btn_frame, text="🗑️", width=30, height=28, fg_color="red", command=lambda l=lesson: self.delete_lesson(l)).pack(side="left", padx=2)

    def _clear_lessons_display(self):
        for widget in self.lessons_frame.winfo_children():
            widget.destroy()

    def move_lesson(self, index, direction):
        new_index = index + direction
        if new_index < 0 or new_index >= len(self.current_lessons):
            return
        
        # Swap in memory
        self.current_lessons[index], self.current_lessons[new_index] = \
            self.current_lessons[new_index], self.current_lessons[index]
        
        # Mark as changed
        self.order_changed = True
        self.btn_reorder.configure(text="💾 Save Order ●", fg_color="orange")
        
        # Redraw
        self.display_lessons()

    def add_lesson(self):
        if not self.selected_course_id:
            return

        dialog = ctk.CTkToplevel(self.app)
        dialog.title("➕ Add New Lesson")
        dialog.geometry("550x700")
        dialog.transient(self.app)
        dialog.grab_set()

        frame = ctk.CTkFrame(dialog)
        frame.pack(padx=20, pady=20, fill="both", expand=True)

        # Title
        ctk.CTkLabel(frame, text="Lesson Title *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        title_entry = ctk.CTkEntry(frame, placeholder_text="e.g., Lesson 1 - Introduction")
        title_entry.pack(fill="x", padx=10, pady=(0, 10))

        # ===== Video Source Selection =====
        ctk.CTkLabel(frame, text="Video Source *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))

        source_var = ctk.StringVar(value="url")
        source_frame = ctk.CTkFrame(frame, fg_color="transparent")
        source_frame.pack(fill="x", padx=10, pady=(0, 5))

        ctk.CTkRadioButton(source_frame, text="🔗 URL (YouTube/Vimeo/etc)", variable=source_var, value="url").pack(side="left", padx=10)
        ctk.CTkRadioButton(source_frame, text="📁 Upload from Computer", variable=source_var, value="file").pack(side="left", padx=10)

        # --- URL Input Frame ---
        url_frame = ctk.CTkFrame(frame, fg_color="transparent")
        url_frame.pack(fill="x", padx=10, pady=(0, 5))

        ctk.CTkLabel(url_frame, text="Video URL:").pack(anchor="w")
        url_entry = ctk.CTkEntry(url_frame, placeholder_text="https://www.youtube.com/watch?v=...")
        url_entry.pack(fill="x", pady=(2, 0))

        # Video Type (for URL)
        type_frame = ctk.CTkFrame(url_frame, fg_color="transparent")
        type_frame.pack(fill="x", pady=(5, 0))
        ctk.CTkLabel(type_frame, text="Type:").pack(side="left")
        type_var = ctk.StringVar(value="youtube")
        ctk.CTkOptionMenu(type_frame, variable=type_var, values=["youtube", "vimeo", "direct", "drive"], width=120).pack(side="left", padx=5)

        # --- File Input Frame ---
        file_frame = ctk.CTkFrame(frame, fg_color="transparent")
        # Hidden initially

        selected_file_path = ctk.StringVar(value="")

        file_inner = ctk.CTkFrame(file_frame, fg_color="transparent")
        file_inner.pack(fill="x")

        file_label = ctk.CTkLabel(file_inner, text="No file selected", text_color="gray", anchor="w")
        file_label.pack(side="left", fill="x", expand=True)

        file_size_label = ctk.CTkLabel(file_inner, text="", text_color="gray", width=100)
        file_size_label.pack(side="right")

        def browse_file():
            file_path = filedialog.askopenfilename(
                title="Select Video File",
                filetypes=[
                    ("Video files", "*.mp4 *.webm *.mov *.avi *.mkv"),
                    ("MP4", "*.mp4"),
                    ("WebM", "*.webm"),
                    ("All files", "*.*")
                ]
            )
            if file_path:
                selected_file_path.set(file_path)
                filename = os.path.basename(file_path)
                size_mb = os.path.getsize(file_path) / (1024 * 1024)

                file_label.configure(text=f"📁 {filename}", text_color="white")
                file_size_label.configure(text=f"{size_mb:.1f} MB")

                # Auto-fill title if empty
                if not title_entry.get().strip():
                    auto_title = os.path.splitext(filename)[0].replace("_", " ").replace("-", " ")
                    title_entry.delete(0, "end")
                    title_entry.insert(0, auto_title)

        ctk.CTkButton(file_frame, text="📁 Browse Video File", command=browse_file, fg_color="#8B5CF6").pack(fill="x", pady=(5, 0))

        # --- Toggle visibility based on source ---
        def toggle_source(*args):
            if source_var.get() == "url":
                url_frame.pack(fill="x", padx=10, pady=(0, 5))
                file_frame.pack_forget()
            else:
                url_frame.pack_forget()
                file_frame.pack(fill="x", padx=10, pady=(0, 5))

        source_var.trace_add("write", toggle_source)
        toggle_source()  # Initial state

        # ===== Common Fields =====

        # Description
        ctk.CTkLabel(frame, text="Description", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        desc_text = ctk.CTkTextbox(frame, height=80)
        desc_text.pack(fill="x", padx=10, pady=(0, 10))

        # Duration
        ctk.CTkLabel(frame, text="Duration (minutes)", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(5, 2))
        duration_entry = ctk.CTkEntry(frame, placeholder_text="e.g., 15")
        duration_entry.pack(fill="x", padx=10, pady=(0, 10))

        # Sort Order
        ctk.CTkLabel(frame, text="Sort Order", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(5, 2))
        sort_entry = ctk.CTkEntry(frame)
        sort_entry.insert(0, str(len(self.current_lessons)))
        sort_entry.pack(fill="x", padx=10, pady=(0, 10))

        # Options
        options_frame = ctk.CTkFrame(frame, fg_color="transparent")
        options_frame.pack(fill="x", padx=10, pady=5)
        published_var = ctk.BooleanVar(value=True)
        ctk.CTkCheckBox(options_frame, text="Published", variable=published_var).pack(side="left", padx=10)
        free_var = ctk.BooleanVar(value=False)
        ctk.CTkCheckBox(options_frame, text="Free Preview", variable=free_var).pack(side="left", padx=10)

        # ===== Save Logic =====
        def save():
            title = title_entry.get().strip()
            if not title:
                messagebox.showerror("Error", "Title is required!", parent=dialog)
                return

            try:
                dur = int(duration_entry.get().strip()) if duration_entry.get().strip() else None
            except ValueError:
                dur = None
            try:
                sort_val = int(sort_entry.get().strip() or "0")
            except ValueError:
                sort_val = 0

            description = desc_text.get("1.0", "end-1c").strip() or None

            if source_var.get() == "url":
                # --- URL Mode ---
                url = url_entry.get().strip()
                if not url:
                    messagebox.showerror("Error", "Video URL is required!", parent=dialog)
                    return

                try:
                    supabase.table("lessons").insert({
                        "course_id": self.selected_course_id,
                        "title": title,
                        "video_url": url,
                        "video_type": type_var.get(),
                        "description": description,
                        "duration_minutes": dur,
                        "sort_order": sort_val,
                        "is_published": published_var.get(),
                        "is_free": free_var.get()
                    }).execute()
                    messagebox.showinfo("Success ✅", f"Lesson '{title}' added successfully.", parent=dialog)
                    dialog.destroy()
                    self.refresh_lessons()
                    self.load_courses()
                except Exception as e:
                    self.show_error("Failed to add lesson", e)

            else:
                # --- File Upload Mode ---
                file_path = selected_file_path.get()
                if not file_path or not os.path.exists(file_path):
                    messagebox.showerror("Error", "Please select a video file!", parent=dialog)
                    return

                file_size = os.path.getsize(file_path)
                if file_size > config.max_video_size:
                    size_mb = config.max_video_size // (1024 * 1024)
                    messagebox.showerror("Error", f"File too large! Max: {size_mb}MB", parent=dialog)
                    return

                lesson_data = {
                    "title": title,
                    "description": description,
                    "duration_minutes": dur,
                    "sort_order": sort_val,
                    "is_published": published_var.get(),
                    "is_free": free_var.get()
                }
                dialog.destroy()
                self._execute_video_upload(file_path, lesson_data)

        # ===== Buttons =====
        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="💾 Save / Upload", command=save, fg_color="#8B5CF6").pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)

        self.app.wait_window(dialog)

    def edit_lesson(self, lesson):
        dialog = ctk.CTkToplevel(self.app)
        dialog.title(f"✏️ Edit: {lesson.get('title', '')}")
        dialog.geometry("550x550")
        dialog.transient(self.app)
        dialog.grab_set()

        frame = ctk.CTkFrame(dialog)
        frame.pack(padx=20, pady=20, fill="both", expand=True)

        ctk.CTkLabel(frame, text="Title *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        title_entry = ctk.CTkEntry(frame)
        title_entry.insert(0, lesson.get("title", ""))
        title_entry.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Video URL *", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        url_entry = ctk.CTkEntry(frame)
        url_entry.insert(0, lesson.get("video_url", ""))
        url_entry.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Video Type", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        type_var = ctk.StringVar(value=lesson.get("video_type", "youtube"))
        ctk.CTkOptionMenu(frame, variable=type_var, values=["youtube", "vimeo", "direct", "drive"]).pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Description", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        desc_text = ctk.CTkTextbox(frame, height=60)
        desc_text.insert("1.0", lesson.get("description", "") or "")
        desc_text.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Duration (min)", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        duration_entry = ctk.CTkEntry(frame)
        if lesson.get("duration_minutes"):
            duration_entry.insert(0, str(lesson["duration_minutes"]))
        duration_entry.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(frame, text="Sort Order", font=("", 13, "bold")).pack(anchor="w", padx=10, pady=(10, 2))
        sort_entry = ctk.CTkEntry(frame)
        sort_entry.insert(0, str(lesson.get("sort_order", 0)))
        sort_entry.pack(fill="x", padx=10, pady=(0, 10))

        options_frame = ctk.CTkFrame(frame, fg_color="transparent")
        options_frame.pack(fill="x", padx=10, pady=5)
        published_var = ctk.BooleanVar(value=lesson.get("is_published", True))
        ctk.CTkCheckBox(options_frame, text="Published", variable=published_var).pack(side="left", padx=10)
        free_var = ctk.BooleanVar(value=lesson.get("is_free", False))
        ctk.CTkCheckBox(options_frame, text="Free", variable=free_var).pack(side="left", padx=10)

        def save():
            title = title_entry.get().strip()
            url = url_entry.get().strip()
            if not title or not url:
                messagebox.showerror("Error", "Title and URL required!", parent=dialog)
                return
            try:
                dur = int(duration_entry.get().strip()) if duration_entry.get().strip() else None
            except ValueError:
                dur = None
            try:
                sort_val = int(sort_entry.get().strip() or "0")
            except ValueError:
                sort_val = 0
            try:
                supabase.table("lessons").update({
                    "title": title, "video_url": url, "video_type": type_var.get(),
                    "description": desc_text.get("1.0", "end-1c").strip() or None,
                    "duration_minutes": dur, "sort_order": sort_val,
                    "is_published": published_var.get(), "is_free": free_var.get()
                }).eq("id", lesson["id"]).execute()
                dialog.destroy()
                self.app.after(0, self.refresh_lessons)
            except Exception as e:
                self.show_error("Failed to update lesson", e)

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="💾 Save", command=save).pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)
        self.app.wait_window(dialog)

    def delete_lesson(self, lesson):
        if not messagebox.askyesno("Confirm", f"Delete '{lesson.get('title', '')}'?"):
            return
        try:
            # Also delete from storage if it's a direct upload
            if lesson.get("video_type") == "direct" and lesson.get("video_url"):
                try:
                    url = lesson["video_url"]
                    # Extract storage path from URL
                    if f"/storage/v1/object/public/{config.video_bucket}/" in url:
                        storage_path = url.split(f"/storage/v1/object/public/{config.video_bucket}/")[1]
                        supabase.storage.from_(config.video_bucket).remove([storage_path])
                        logging.info(f"Deleted video from storage: {storage_path}")
                except Exception as e:
                    logging.warning(f"Could not delete video from storage: {e}")

            supabase.table("lessons").delete().eq("id", lesson["id"]).execute()
            self.refresh_lessons()
            self.load_courses()
        except Exception as e:
            self.show_error("Failed to delete lesson", e)

    def delete_selected_lessons(self):
        selected_ids = [lid for lid, var in self.lesson_checkbox_vars.items() if var.get()]
        if not selected_ids:
            messagebox.showinfo("⚠️ تنبيه", "اختر درساً أو أكثر أولاً.")
            return
        if not messagebox.askyesno("⚠️ تأكيد الحذف",
            f"هل تريد حذف {len(selected_ids)} درس؟\n\n⚠️ لا يمكن التراجع!"):
            return

        lessons_to_delete = [l for l in self.current_lessons if l["id"] in selected_ids]

        def worker():
            # Delete files from storage for direct videos
            for lesson in lessons_to_delete:
                if lesson.get("video_type") == "direct" and lesson.get("video_url"):
                    try:
                        url = lesson["video_url"]
                        key = f"/storage/v1/object/public/{config.video_bucket}/"
                        if key in url:
                            path = url.split(key)[1]
                            supabase.storage.from_(config.video_bucket).remove([path])
                    except Exception as e:
                        logging.warning(f"Storage delete failed: {e}")

            try:
                supabase.table("lessons").delete().in_("id", selected_ids).execute()
                def on_done():
                    messagebox.showinfo("✅ تم الحذف", f"تم حذف {len(selected_ids)} درس بنجاح.")
                    self.refresh_lessons()
                    self.load_courses()
                self.app.after(0, on_done)
            except Exception as e:
                self.app.after(0, lambda: self.show_error("فشل حذف الدروس", e))

        threading.Thread(target=worker, daemon=True).start()

    def save_lesson_order(self):
        if not self.current_lessons:
            return
        if not self.order_changed:
            messagebox.showinfo("ℹ️", "لم يتم تغيير أي ترتيب.")
            return

        page_offset = (self.current_page - 1) * config.page_size
        # New order = list position + page offset
        updates = [
            (lesson["id"], lesson.get("title", ""), page_offset + i)
            for i, lesson in enumerate(self.current_lessons)
        ]

        self.btn_reorder.configure(state="disabled", text="⏳ جارٍ الحفظ...")

        def worker():
            failed = []
            for lesson_id, title, new_order in updates:
                try:
                    supabase.table("lessons").update(
                        {"sort_order": new_order}
                    ).eq("id", lesson_id).execute()
                except Exception as e:
                    logging.error(f"Failed to update order for {lesson_id}: {e}")
                    failed.append(title)

            def on_done(f=list(failed)):
                self.order_changed = False
                self.btn_reorder.configure(
                    state="normal", text="🔃 Save Order", fg_color=["#3B8ED0", "#1F6AA5"]
                )
                if f:
                    messagebox.showwarning(
                        "⚠️ اكتمل مع أخطاء",
                        f"✅ تم تحديث {len(updates) - len(f)} درس.\n"
                        f"❌ فشل: {', '.join(f)}"
                    )
                else:
                    messagebox.showinfo("✅ تم الحفظ", f"تم حفظ ترتيب {len(updates)} درس بنجاح.")
                self.refresh_lessons()

            self.app.after(0, on_done)

        threading.Thread(target=worker, daemon=True).start()

    def copy_video_url(self, lesson):
        url = lesson.get("video_url", "")
        self.app.clipboard_clear()
        self.app.clipboard_append(url)
        messagebox.showinfo("Copied", "URL copied!")

    # ===========================
    # PAGINATION
    # ===========================
    def next_page(self):
        self.current_page += 1
        self.refresh_lessons(page_change=True)

    def prev_page(self):
        if self.current_page > 1:
            self.current_page -= 1
            self.refresh_lessons(page_change=True)

    # ===========================
    # HELPERS
    # ===========================
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
            friendly = "⚠️ انتهت مهلة الاتصال — حاول مرة أخرى."
        else:
            friendly = raw

        logging.error(f"{msg}: {raw}", exc_info=True)
        messagebox.showerror("❌ خطأ", f"{msg}\n\n{friendly}\n\n(راجع الـ logs للتفاصيل)")

    # ===========================
    # DRAG AND DROP
    # ===========================
    def _setup_drag_drop(self):
        """Register the main window as a drop target for video files."""
        if not HAS_DND:
            return
        try:
            self.app.drop_target_register(DND_FILES)
            self.app.dnd_bind('<<Drop>>', self._handle_drop)
            logging.info("✅ Drag-and-drop enabled.")
        except Exception as e:
            logging.warning(f"Drag-and-drop registration failed: {e}")

    def _handle_drop(self, event):
        """
        Called when the user drops files onto the window.
        Filters video files and triggers the upload flow.
        """
        if not HAS_DND:
            return

        if not self.selected_course_id:
            messagebox.showwarning(
                "⚠️ لم يتم اختيار كورس",
                "الرجاء اختيار كورس أولاً ثم اسحب الملف مرة أخرى."
            )
            return

        if self.upload_in_progress:
            messagebox.showwarning("⚠️ رفع جارٍ", "يوجد رفع قيد التنفيذ. انتظر حتى ينتهي.")
            return

        # splitlist handles paths with spaces and curly-brace quoting
        try:
            raw_files = self.app.splitlist(event.data)
        except Exception:
            raw_files = event.data.split()

        allowed_ext = tuple(config.allowed_video_ext)   # e.g. ('.mp4', '.mkv', ...)
        valid_files = [
            f for f in raw_files
            if os.path.isfile(f) and os.path.splitext(f)[1].lower() in allowed_ext
        ]
        skipped = len(raw_files) - len(valid_files)

        if skipped:
            logging.warning(f"{skipped} file(s) skipped (unsupported format or not a file).")

        if not valid_files:
            messagebox.showwarning(
                "⚠️ لا توجد ملفات صالحة",
                "لم يتم العثور على ملفات فيديو صالحة.\n"
                f"الامتدادات المسموح بها: {', '.join(config.allowed_video_ext)}"
            )
            return

        if len(valid_files) == 1:
            # Single file → show the detailed dialog for title/description
            file_path = valid_files[0]
            file_size = os.path.getsize(file_path)
            if file_size > config.max_video_size:
                size_mb = config.max_video_size // (1024 * 1024)
                messagebox.showerror("❌ الملف كبير جداً", f"الحد الأقصى للحجم: {size_mb} MB")
                return
            self._show_upload_lesson_dialog(file_path, file_size)
        else:
            # Multiple files → validate sizes then bulk-upload
            oversized = []
            ok_files  = []
            for f in valid_files:
                if os.path.getsize(f) > config.max_video_size:
                    oversized.append(os.path.basename(f))
                else:
                    ok_files.append(f)

            if oversized:
                messagebox.showwarning(
                    "⚠️ ملفات كبيرة جداً – سيتم تخطيها",
                    "\n".join(oversized)
                )

            if not ok_files:
                return

            if not messagebox.askyesno(
                "📤 تأكيد الرفع",
                f"رفع {len(ok_files)} ملف فيديو إلى الكورس المختار؟"
            ):
                return

            # Re-use the existing bulk-upload worker
            self.app.after(0, lambda: self.show_upload_progress(f"{len(ok_files)} files"))

            def worker(files=ok_files):
                import uuid
                total = len(files)
                succeeded = 0
                failed_files = []
                try:
                    max_res = supabase.table("lessons").select("sort_order")\
                        .eq("course_id", self.selected_course_id)\
                        .order("sort_order", desc=True).limit(1).execute()
                    next_order = (max_res.data[0]["sort_order"] + 1) if max_res.data else 0
                except Exception:
                    next_order = 0

                for i, file_path in enumerate(files):
                    try:
                        filename  = os.path.basename(file_path)
                        file_ext  = os.path.splitext(filename)[1]
                        unique    = f"{uuid.uuid4().hex}{file_ext}"
                        spath     = f"courses/{self.selected_course_id}/{unique}"
                        ctype     = CONTENT_TYPES.get(file_ext.lower(), 'video/mp4')
                        progress  = (i + 1) / total
                        self.app.after(0, lambda p=progress, fn=filename, cur=i+1:
                            self.update_upload_progress(p, f"📤 [{cur}/{total}] {fn}"))
                        with open(file_path, "rb") as fh:
                            data = fh.read()
                        supabase.storage.from_(config.video_bucket).upload(
                            spath, data, {"content-type": ctype, "x-upsert": "true"}
                        )
                        video_url  = supabase.storage.from_(config.video_bucket).get_public_url(spath)
                        auto_title = os.path.splitext(filename)[0].replace("_", " ").replace("-", " ")
                        supabase.table("lessons").insert({
                            "course_id":  self.selected_course_id,
                            "title":      auto_title,
                            "video_url":  video_url,
                            "video_type": "direct",
                            "sort_order": next_order + i,
                            "is_published": True,
                            "is_free": False
                        }).execute()
                        succeeded += 1
                    except Exception as e:
                        logging.error(f"DnD upload failed for {filename}: {e}", exc_info=True)
                        failed_files.append(os.path.basename(file_path))

                self.app.after(0, lambda: self.update_upload_progress(1.0, "✅ اكتملت جميع الرفوعات!"))
                import time as _time; _time.sleep(1)

                def on_complete(s=succeeded, f=list(failed_files)):
                    self.hide_upload_progress()
                    if not f:
                        messagebox.showinfo("✅ تم الرفع", f"تم رفع جميع الملفات ({s}) بنجاح.")
                    else:
                        messagebox.showwarning(
                            "⚠️ اكتمل بنجاح جزئي",
                            f"تم رفع {s} وفشل {len(f)} ملفات:\n" + "\n".join(f)
                        )
                    self.refresh_lessons()
                    self.load_courses()

                self.app.after(0, on_complete)

            import threading as _threading
            _threading.Thread(target=worker, daemon=True).start()

    def run(self):
        self.app.mainloop()


if __name__ == "__main__":
    app = VideoManagerApp()
    app.run()