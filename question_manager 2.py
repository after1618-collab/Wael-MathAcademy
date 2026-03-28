import os
import re  # ✅ NEW
import threading
import logging
import time
import json
import csv
from tkinter import filedialog, messagebox, simpledialog
import customtkinter as ctk
from supabase import create_client, Client
from dotenv import load_dotenv
from dataclasses import dataclass
from typing import List
from io import BytesIO

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
    max_file_size: int = 10 * 1024 * 1024
    allowed_extensions: List[str] = None
    page_size: int = 50  # ✅ CHANGED from 20

    def __post_init__(self):
        if self.allowed_extensions is None:
            self.allowed_extensions = ['.png', '.jpg', '.jpeg']

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

# --- Logging Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

config = AppConfig()
supabase: Client = create_client(config.supabase_url, config.supabase_key)

# --- APP CLASS ---
class QuestionManagerApp:
    def __init__(self):
        ctk.set_appearance_mode("System")
        ctk.set_default_color_theme("blue")

        self.app = ctk.CTk()
        self.app.geometry("1200x800")
        self.app.title("📚 Question Manager Pro")

        # Vars
        self.sections = []
        self.buckets = []
        self.current_questions = []
        self.selected_section = ctk.StringVar()
        self.selected_bucket = ctk.StringVar()
        self.enable_e = ctk.BooleanVar(value=False)
        self.enable_text_answer = ctk.BooleanVar(value=False)
        self.image_references = []
        self.question_checkbox_vars = {}
        self.thumbnail_cache = {}
        self.current_page = 1
        self.display_job = None
        self.answer_entries = []   # ✅ NEW: track answer entries for navigation
        self.save_timers = {}      # ✅ NEW: debounce timers per question

        # Build UI
        self.setup_ui()
        self.load_initial_data()

        # Triggers
        self.selected_bucket.trace_add("write", self.clear_thumbnail_cache)

    # ✅ NEW: Extract answer letter from image filename
    @staticmethod
    def extract_answer_from_filename(filename):
        """Extract a standalone single letter (A-E) from the filename as the correct answer.
        Examples: '1_B.png' -> 'B', 'Q5-c.jpg' -> 'C', 'A.png' -> 'A'
        """
        name = os.path.splitext(os.path.basename(filename))[0]
        # Find standalone letters A-E (not part of a longer word)
        matches = re.findall(r'(?<![a-zA-Z])([A-Ea-e])(?![a-zA-Z])', name)
        if matches:
            return matches[-1].upper()
        return "A"  # Default if no standalone letter found

    # === UI ===
    def setup_ui(self):
        self.setup_top_bar()
        self.questions_frame = ctk.CTkScrollableFrame(self.app, width=1150, height=600)
        self.questions_frame.pack(fill="both", expand=True, padx=10, pady=10)
        self.setup_bottom_bar()

    def setup_top_bar(self):
        top_container = ctk.CTkFrame(self.app, fg_color="transparent")
        top_container.pack(pady=5, fill="x", padx=10)

        # --- Row 1: Navigation & Configuration ---
        row1 = ctk.CTkFrame(top_container)
        row1.pack(fill="x", pady=(0, 5))

        ctk.CTkLabel(row1, text="Section:").pack(side="left", padx=5)
        self.section_menu = ctk.CTkOptionMenu(row1, values=[], variable=self.selected_section, command=lambda choice: self.refresh_questions())
        self.section_menu.pack(side="left", padx=5)
        ctk.CTkButton(row1, text="➕ Add Section", width=100, command=self.add_section).pack(side="left", padx=5)
        ctk.CTkButton(row1, text="📂 Manage", width=80, command=self.manage_sections).pack(side="left", padx=5)

        ctk.CTkLabel(row1, text="Bucket:").pack(side="left", padx=(20, 5))
        self.bucket_menu = ctk.CTkOptionMenu(row1, values=[], variable=self.selected_bucket)
        self.bucket_menu.pack(side="left", padx=5)
        ctk.CTkButton(row1, text="➕ Add Bucket", width=100, command=self.add_bucket).pack(side="left", padx=5)

        # --- Row 2: Actions & Filters ---
        row2 = ctk.CTkFrame(top_container)
        row2.pack(fill="x")

        ctk.CTkCheckBox(row2, text="Enable E", variable=self.enable_e).pack(side="left", padx=10, pady=5)
        ctk.CTkCheckBox(row2, text="Enable Text Answer", variable=self.enable_text_answer).pack(side="left", padx=5, pady=5)

        ctk.CTkButton(row2, text="🗑️ Delete Selected", fg_color="red", width=110, command=self.delete_selected_questions).pack(side="right", padx=5, pady=5)
        ctk.CTkButton(row2, text="📦 Move Selected", width=110, command=self.move_selected_questions).pack(side="right", padx=5, pady=5)
        ctk.CTkButton(row2, text="⚙️ Edit Selected", width=110, command=self.bulk_edit_selected_questions).pack(side="right", padx=5, pady=5)
        ctk.CTkButton(row2, text="📤 Upload Images", width=110, command=self.upload_images).pack(side="right", padx=5, pady=5)
        ctk.CTkButton(row2, text="✅ Select All", width=90, command=self.toggle_select_all_questions).pack(side="right", padx=5, pady=5)

    def setup_bottom_bar(self):
        bottom = ctk.CTkFrame(self.app)
        bottom.pack(pady=5, fill="x", padx=10)

        self.prev_page_btn = ctk.CTkButton(bottom, text="⬅️ Previous", command=self.prev_page, state="disabled")
        self.prev_page_btn.pack(side="left", padx=10)

        self.page_label = ctk.CTkLabel(bottom, text="Page 1 / 1")
        self.page_label.pack(side="left", expand=True)

        self.next_page_btn = ctk.CTkButton(bottom, text="Next ➡️", command=self.next_page, state="disabled")
        self.next_page_btn.pack(side="right", padx=10)

    # === LOAD DATA ===
    def load_initial_data(self):
        def worker():
            try:
                sections_resp = supabase.table("sections").select("*").execute()
                buckets_resp = supabase.storage.list_buckets()

                sections = [s["name"] for s in sections_resp.data]
                buckets = [b.name for b in buckets_resp]

                def do_initial_setup():
                    self.sections = sections
                    self.buckets = buckets
                    self.section_menu.configure(values=self.sections)
                    self.bucket_menu.configure(values=self.buckets)
                    if self.buckets:
                        self.selected_bucket.set(self.buckets[0])
                    if self.sections:
                        self.selected_section.set(self.sections[0])
                        self.refresh_questions()

                self.app.after(0, do_initial_setup)
            except Exception as e:
                self.app.after(0, lambda: self.show_error("Initial data load failed", e))
        threading.Thread(target=worker, daemon=True).start()

    def load_sections(self):
        resp = supabase.table("sections").select("*").execute()
        self.sections = [s["name"] for s in resp.data]
        self.app.after(0, lambda: self.section_menu.configure(values=self.sections))

    def load_buckets(self):
        resp = supabase.storage.list_buckets()
        self.buckets = [b.name for b in resp]
        self.app.after(0, lambda: self.bucket_menu.configure(values=self.buckets))

    # === ADD ===
    def add_section(self):
        name = simpledialog.askstring("New Section", "Enter section name:")
        if name:
            name = name.strip()
        if not name:
            return
        try:
            supabase.table("sections").insert({"name": name}).execute()
            self.load_sections()
            self.selected_section.set(name)
        except Exception as e:
            self.show_error("Failed to add section", e)

    def add_bucket(self):
        name = simpledialog.askstring("New Bucket", "Enter bucket name:")
        if not name:
            return
        try:
            supabase.storage.create_bucket(name)
            self.load_buckets()
            self.selected_bucket.set(name)
        except Exception as e:
            self.show_error("Failed to add bucket", e)

    def manage_sections(self):
        dialog = ctk.CTkToplevel(self.app)
        dialog.title("Manage Sections")
        dialog.geometry("500x600")
        dialog.transient(self.app)
        dialog.grab_set()

        top_frame = ctk.CTkFrame(dialog)
        top_frame.pack(fill="x", padx=10, pady=10)

        section_vars = {}

        def toggle_select_all():
            if not section_vars: return
            any_unchecked = any(not var.get() for var in section_vars.values())
            new_state = True if any_unchecked else False
            for var in section_vars.values():
                var.set(new_state)

        def delete_selected():
            selected = [name for name, var in section_vars.items() if var.get()]
            if not selected:
                messagebox.showinfo("Info", "No sections selected.", parent=dialog)
                return

            if not messagebox.askyesno("Confirm", f"Delete {len(selected)} sections?\n\n⚠️ WARNING: This will delete ALL questions in these sections!", parent=dialog):
                return

            try:
                res = supabase.table("sections").select("id").in_("name", selected).execute()
                ids = [item['id'] for item in res.data]
                if ids:
                    supabase.table("sections").delete().in_("id", ids).execute()
                messagebox.showinfo("Success", "Sections deleted", parent=dialog)
                dialog.destroy()
                self.load_sections()
                if self.selected_section.get() in selected:
                    self.selected_section.set(self.sections[0] if self.sections else "")
                    self.refresh_questions()
            except Exception as e:
                self.show_error("Failed to delete sections", e)

        ctk.CTkButton(top_frame, text="✅ Select All", command=toggle_select_all).pack(side="left", padx=5)
        ctk.CTkButton(top_frame, text="🗑️ Delete Selected", fg_color="red", command=delete_selected).pack(side="right", padx=5)

        scroll = ctk.CTkScrollableFrame(dialog)
        scroll.pack(fill="both", expand=True, padx=10, pady=10)

        if not self.sections:
            ctk.CTkLabel(scroll, text="No sections found.").pack(pady=20)

        for section_name in self.sections:
            row = ctk.CTkFrame(scroll)
            row.pack(fill="x", pady=2)
            var = ctk.BooleanVar()
            section_vars[section_name] = var
            ctk.CTkCheckBox(row, text=section_name, variable=var).pack(side="left", padx=10, pady=5)

    # === UPLOAD ===
    def upload_images(self):
        files = filedialog.askopenfilenames(
            title="Select Images",
            filetypes=[("Images", "*.png *.jpg *.jpeg")]
        )
        if not files:
            return

        section = self.selected_section.get()
        bucket = self.selected_bucket.get()
        if not section or not bucket:
            messagebox.showerror("Error", "Please select section and bucket first")
            return

        try:
            section_id = supabase.table("sections").select("id").eq("name", section).limit(1).execute().data[0]["id"]
        except (IndexError, Exception) as e:
            self.show_error(f"Could not find Section ID for '{section}'", e)
            return

        for file_path in files:
            try:
                filename = os.path.basename(file_path)
                storage_path = f"{section}/{filename}"
                with open(file_path, "rb") as f:
                    supabase.storage.from_(bucket).upload(storage_path, f, {"x-upsert": "true"})

                # ✅ CHANGED: extract answer from filename instead of hardcoded "A"
                extracted_answer = self.extract_answer_from_filename(filename)

                supabase.table("questions").insert({
                    "image_path": storage_path,
                    "section_id": section_id,
                    "answer_type": "mcq",
                    "correct_answer": extracted_answer,
                    "options": ["A", "B", "C", "D"] + (["E"] if self.enable_e.get() else []),
                    "allow_text": self.enable_text_answer.get()
                }).execute()
            except Exception as e:
                logging.error(f"Upload failed for {filename}: {e}")

        messagebox.showinfo("Done", f"Uploaded {len(files)} questions!")
        self.refresh_questions()

    # === DISPLAY QUESTIONS ===
    def refresh_questions(self, page_change=False):
        section_name = self.selected_section.get()
        if not section_name:
            self.current_questions = []
            self.display_questions()
            return
        try:
            section_res = supabase.table("sections").select("id").eq("name", section_name).limit(1).execute()
            if not section_res.data:
                messagebox.showerror("Error", f"Section '{section_name}' not found.")
                self.current_questions = []
                self.display_questions()
                return

            if not page_change:
                self.current_page = 1

            section_id = section_res.data[0]["id"]

            count_res = supabase.table("questions").select("id", count='exact').eq("section_id", section_id).execute()
            total_items = count_res.count
            total_pages = (total_items + config.page_size - 1) // config.page_size
            if total_pages == 0: total_pages = 1

            start_index = (self.current_page - 1) * config.page_size
            end_index = start_index + config.page_size - 1
            resp = supabase.table("questions").select("*").eq("section_id", section_id).order("created_at", desc=True).range(start_index, end_index).execute()

            self.current_questions = resp.data or []
            self.display_questions()

            # ✅ CHANGED: show question range in pagination label
            start_num = start_index + 1
            end_num = min(start_index + config.page_size, total_items)
            self.page_label.configure(
                text=f"Questions {start_num}-{end_num} of {total_items}  •  Page {self.current_page} / {total_pages}"
            )
            self.prev_page_btn.configure(state="normal" if self.current_page > 1 else "disabled")
            self.next_page_btn.configure(state="normal" if self.current_page < total_pages else "disabled")
        except Exception as e:
            self.show_error("Failed to load questions", e)
            self.current_questions = []
            self.display_questions()

    def display_questions(self):
        if self.display_job:
            self.app.after_cancel(self.display_job)

        for widget in self.questions_frame.winfo_children():
            widget.destroy()
        self.image_references.clear()
        self.question_checkbox_vars.clear()
        self.answer_entries = []  # ✅ NEW: reset entry list for navigation

        if not self.current_questions:
            ctk.CTkLabel(self.questions_frame, text="No questions found for this section.",
                         font=("", 14), text_color="gray50").pack(pady=40)
        else:
            # ✅ CHANGED: batch rendering with index tracking
            self._render_index = 0
            self._render_next_batch()

    # ✅ NEW: replaces _display_next_question - renders in batches for speed
    def _render_next_batch(self):
        batch_size = 5
        end = min(self._render_index + batch_size, len(self.current_questions))

        for i in range(self._render_index, end):
            self._create_question_widget(self.current_questions[i], i)

        self._render_index = end
        if self._render_index < len(self.current_questions):
            self.display_job = self.app.after(10, self._render_next_batch)
        else:
            self.display_job = None

    # ✅ COMPLETELY REWRITTEN: compact rows + auto-save + navigation
    def _create_question_widget(self, q, index):
        bucket = self.selected_bucket.get()

        # Alternating row colors for readability
        is_even = index % 2 == 0
        frame = ctk.CTkFrame(self.questions_frame,
                              fg_color=("gray95", "gray14") if is_even else ("gray88", "gray18"),
                              corner_radius=6, height=90)
        frame.pack(fill="x", pady=1, padx=5)
        frame.pack_propagate(False)

        # Row number
        row_num = (self.current_page - 1) * config.page_size + index + 1
        ctk.CTkLabel(frame, text=str(row_num), width=30,
                     text_color="gray50", font=("", 11)).pack(side="left", padx=(5, 2))

        # Checkbox
        var = ctk.BooleanVar()
        self.question_checkbox_vars[q['id']] = var
        ctk.CTkCheckBox(frame, text="", variable=var, width=24,
                        checkbox_height=18, checkbox_width=18).pack(side="left", padx=2)

        # ✅ Compact Thumbnail (80x80 instead of 480x480)
        img_label = ctk.CTkLabel(frame, text="⏳", width=80, height=80)
        img_label.pack(side="left", padx=5)
        if PIL_AVAILABLE and bucket and q.get("image_path"):
            image_path = q.get("image_path")
            img_label.bind("<Button-1>", lambda e, b=bucket, p=image_path: self.show_full_image(b, p))
            img_label.configure(cursor="hand2")
            threading.Thread(target=self._load_thumbnail, args=(img_label, bucket, image_path), daemon=True).start()
        else:
            img_label.configure(text="🖼️")

        # Filename
        filename = os.path.basename(q["image_path"])
        ctk.CTkLabel(frame, text=filename, anchor="w",
                     font=("", 12)).pack(side="left", padx=8, fill="x", expand=True)

        # ✅ Answer entry with auto-save
        answer_frame = ctk.CTkFrame(frame, fg_color="transparent")
        answer_frame.pack(side="left", padx=5)
        ctk.CTkLabel(answer_frame, text="Answer:", font=("", 11),
                     text_color="gray60").pack(side="left")

        answer_var = ctk.StringVar(value=q.get('correct_answer', 'A'))
        answer_entry = ctk.CTkEntry(answer_frame, textvariable=answer_var,
                                     width=45, height=28, justify="center",
                                     font=("", 13, "bold"))
        answer_entry.pack(side="left", padx=3)

        # Track entry for Enter/Tab navigation
        self.answer_entries.append(answer_entry)
        entry_index = len(self.answer_entries) - 1

        # --- Auto-save bindings ---
        save_timer = [None]

        def do_save(event=None):
            if save_timer[0]:
                self.app.after_cancel(save_timer[0])
                save_timer[0] = None
            self.auto_save_answer(q['id'], answer_entry)

        def on_key_release(event):
            # Ignore modifier/navigation keys
            if event.keysym in ('Return', 'Tab', 'Shift_L', 'Shift_R',
                                'Control_L', 'Control_R', 'Alt_L', 'Alt_R',
                                'Left', 'Right', 'Up', 'Down'):
                return
            if save_timer[0]:
                self.app.after_cancel(save_timer[0])
            save_timer[0] = self.app.after(500, do_save)

        def on_enter_or_tab(event):
            do_save()
            next_idx = entry_index + 1
            if next_idx < len(self.answer_entries):
                nxt = self.answer_entries[next_idx]
                nxt.focus_set()
                nxt.select_range(0, 'end')
            return "break"

        answer_entry.bind("<KeyRelease>", on_key_release)
        answer_entry.bind("<Return>", on_enter_or_tab)
        answer_entry.bind("<Tab>", on_enter_or_tab)
        answer_entry.bind("<FocusOut>", do_save)

        # ✅ Compact action buttons
        btn_frame = ctk.CTkFrame(frame, fg_color="transparent")
        btn_frame.pack(side="right", padx=5)
        ctk.CTkButton(btn_frame, text="✏", width=32, height=28,
                       command=lambda q=q: self.edit_question(q)).pack(side="left", padx=1)
        ctk.CTkButton(btn_frame, text="📦", width=32, height=28,
                       command=lambda q=q: self.move_question(q)).pack(side="left", padx=1)
        ctk.CTkButton(btn_frame, text="🗑", width=32, height=28, fg_color="#e74c3c",
                       command=lambda q=q: self.delete_question(q)).pack(side="left", padx=1)

    # ✅ NEW: auto-save answer in background thread (no Enter needed)
    def auto_save_answer(self, question_id, entry_widget):
        new_answer = entry_widget.get().strip().upper()
        if not new_answer:
            return

        # Skip if unchanged
        for q in self.current_questions:
            if q['id'] == question_id:
                if q.get('correct_answer') == new_answer:
                    return
                break

        def worker():
            try:
                supabase.table("questions").update({"correct_answer": new_answer}).eq("id", question_id).execute()
                def on_success():
                    try:
                        entry_widget.configure(border_color="#2ecc71")
                        self.app.after(1500, lambda: entry_widget.configure(
                            border_color=("#979DA2", "#565B5E")))
                    except Exception:
                        pass  # Widget may have been destroyed
                    for q in self.current_questions:
                        if q['id'] == question_id:
                            q['correct_answer'] = new_answer
                            break
                self.app.after(0, on_success)
            except Exception as e:
                self.app.after(0, lambda: entry_widget.configure(border_color="#e74c3c"))
                logging.error(f"Auto-save failed for {question_id}: {e}")

        threading.Thread(target=worker, daemon=True).start()

    # === EDIT ===
    def edit_question(self, question):
        self.open_properties_dialog([question])

    # === DELETE ===
    def delete_question(self, question):
        if not messagebox.askyesno("Confirm", f"Delete {question['image_path']}?"):
            return
        try:
            supabase.table("questions").delete().eq("id", question["id"]).execute()
            self.refresh_questions()
        except Exception as e:
            self.show_error("Failed to delete question", e)

    # === MOVE ===
    def move_question(self, question):
        new_section = self.ask_for_section_dialog()
        if not new_section:
            return
        try:
            section_data = supabase.table("sections").select("id").eq("name", new_section).execute().data
            if not section_data:
                messagebox.showerror("Error", f"Section '{new_section}' not found")
                return
            target_id = section_data[0]["id"]

            supabase.table("questions").update({"section_id": target_id}).eq("id", question["id"]).execute()
            self.refresh_questions()
            messagebox.showinfo("Success", f"Moved to {new_section}")
        except Exception as e:
            self.show_error("Failed to move question", e)

    # === BULK ACTIONS & DIALOG ===
    def toggle_select_all_questions(self):
        if not self.question_checkbox_vars:
            return
        any_unchecked = any(not var.get() for var in self.question_checkbox_vars.values())
        new_state = True if any_unchecked else False
        for var in self.question_checkbox_vars.values():
            var.set(new_state)

    def get_selected_question_ids(self):
        return [qid for qid, var in self.question_checkbox_vars.items() if var.get()]

    def delete_selected_questions(self):
        selected_ids = self.get_selected_question_ids()
        if not selected_ids:
            messagebox.showinfo("Info", "No questions selected.")
            return

        if not messagebox.askyesno("Confirm", f"Delete {len(selected_ids)} selected questions? This cannot be undone."):
            return

        try:
            supabase.table("questions").delete().in_("id", selected_ids).execute()
            messagebox.showinfo("Success", f"Deleted {len(selected_ids)} questions.")
            self.refresh_questions()
        except Exception as e:
            self.show_error("Failed to delete selected questions", e)

    def move_selected_questions(self):
        selected_ids = self.get_selected_question_ids()
        if not selected_ids:
            messagebox.showinfo("Info", "No questions selected.")
            return

        new_section = self.ask_for_section_dialog()
        if not new_section:
            return

        try:
            section_data = supabase.table("sections").select("id").eq("name", new_section).execute().data
            if not section_data:
                messagebox.showerror("Error", f"Section '{new_section}' not found")
                return
            target_id = section_data[0]["id"]

            supabase.table("questions").update({"section_id": target_id}).in_("id", selected_ids).execute()
            self.refresh_questions()
            messagebox.showinfo("Success", f"Moved {len(selected_ids)} questions to {new_section}")
        except Exception as e:
            self.show_error("Failed to move questions", e)

    def bulk_edit_selected_questions(self):
        selected_ids = self.get_selected_question_ids()
        if not selected_ids:
            messagebox.showinfo("Info", "No questions selected.")
            return

        questions_to_edit = [{'id': qid} for qid in selected_ids]
        self.open_properties_dialog(questions_to_edit)

    def open_properties_dialog(self, questions_to_edit: list):
        is_bulk_edit = len(questions_to_edit) > 1
        title = f"Edit Properties for {len(questions_to_edit)} Questions" if is_bulk_edit else "Edit Question Properties"

        dialog = ctk.CTkToplevel(self.app)
        dialog.title(title)
        dialog.transient(self.app)
        dialog.grab_set()

        single_question = questions_to_edit[0] if not is_bulk_edit else {}

        answer_type_options = ['(No Change)', 'mcq', 'text', 'numeric'] if is_bulk_edit else ['mcq', 'text', 'numeric']
        answer_type_var = ctk.StringVar(value=single_question.get('answer_type', 'mcq') if not is_bulk_edit else '(No Change)')

        options_list = single_question.get('options', [])
        enable_e_current_val = 'E' in options_list
        options_mode_options = ['(No Change)', 'A,B,C,D', 'A,B,C,D,E'] if is_bulk_edit else ['A,B,C,D', 'A,B,C,D,E']
        options_mode_var = ctk.StringVar(value='A,B,C,D,E' if enable_e_current_val else 'A,B,C,D' if not is_bulk_edit else '(No Change)')

        allow_text_options = ['(No Change)', 'Enable', 'Disable'] if is_bulk_edit else ['Enable', 'Disable']
        allow_text_current_val = single_question.get('allow_text', False)
        allow_text_var = ctk.StringVar(value='Enable' if allow_text_current_val else 'Disable' if not is_bulk_edit else '(No Change)')

        numeric_answer_vars = [ctk.StringVar() for _ in range(4)]
        if not is_bulk_edit and single_question.get('answer_type') == 'numeric':
            accepted = single_question.get('accepted_numeric_answers') or []
            for i, val in enumerate(accepted):
                if i < 4: numeric_answer_vars[i].set(str(val))

        frame = ctk.CTkFrame(dialog); frame.pack(padx=20, pady=20, fill="both", expand=True)
        frame.columnconfigure(1, weight=1)

        ctk.CTkLabel(frame, text="Answer Type:").grid(row=1, column=0, padx=5, pady=5, sticky="w")
        ctk.CTkOptionMenu(frame, variable=answer_type_var, values=answer_type_options).grid(row=1, column=1, padx=5, pady=5, sticky="ew")

        mcq_options_frame = ctk.CTkFrame(frame, fg_color="transparent")
        mcq_options_frame.grid(row=2, column=0, columnspan=2, pady=0, sticky="ew")
        mcq_options_frame.columnconfigure(1, weight=1)
        ctk.CTkLabel(mcq_options_frame, text="Choices:").grid(row=0, column=0, padx=5, pady=5, sticky="w")
        ctk.CTkOptionMenu(mcq_options_frame, variable=options_mode_var, values=options_mode_options).grid(row=0, column=1, padx=5, pady=5, sticky="ew")
        ctk.CTkLabel(mcq_options_frame, text="Allow Text Input (for MCQ):").grid(row=1, column=0, padx=5, pady=5, sticky="w")
        ctk.CTkOptionMenu(mcq_options_frame, variable=allow_text_var, values=allow_text_options).grid(row=1, column=1, padx=5, pady=5, sticky="ew")

        numeric_answers_frame = ctk.CTkFrame(frame)
        numeric_answers_frame.grid(row=2, column=0, columnspan=2, pady=0, sticky="ew")
        ctk.CTkLabel(numeric_answers_frame, text="Accepted Numeric Answers:").pack(anchor="w", padx=5, pady=(5,0))
        for i in range(4):
            entry_frame = ctk.CTkFrame(numeric_answers_frame, fg_color="transparent")
            entry_frame.pack(fill="x", padx=5, pady=2)
            ctk.CTkLabel(entry_frame, text=f"{i+1}:", width=20).pack(side="left")
            ctk.CTkEntry(entry_frame, textvariable=numeric_answer_vars[i]).pack(side="left", fill="x", expand=True)

        def update_dialog_view(*args):
            selected_type = answer_type_var.get()
            if selected_type == 'mcq':
                mcq_options_frame.grid()
                numeric_answers_frame.grid_remove()
            elif selected_type == 'numeric':
                mcq_options_frame.grid_remove()
                numeric_answers_frame.grid()
            else:
                mcq_options_frame.grid_remove()
                numeric_answers_frame.grid_remove()

        answer_type_var.trace_add("write", update_dialog_view)
        update_dialog_view()

        def on_save():
            payload = {}
            if answer_type_var.get() != '(No Change)': payload['answer_type'] = answer_type_var.get()
            if options_mode_var.get() != '(No Change)':
                payload['options'] = ['A', 'B', 'C', 'D', 'E'] if options_mode_var.get() == 'A,B,C,D,E' else ['A', 'B', 'C', 'D']
            if allow_text_var.get() != '(No Change)':
                payload['allow_text'] = True if allow_text_var.get() == 'Enable' else False

            new_answer_type = answer_type_var.get()
            if new_answer_type != '(No Change)':
                if new_answer_type == 'numeric':
                    payload['correct_answer'] = None
                else:
                    payload['accepted_numeric_answers'] = []

            if answer_type_var.get() == 'numeric' or (is_bulk_edit and answer_type_var.get() == '(No Change)'):
                numeric_answers = []
                for var in numeric_answer_vars:
                    val_str = var.get().strip()
                    if val_str:
                        try:
                            numeric_answers.append(float(val_str))
                        except ValueError:
                            messagebox.showerror("Error", f"'{val_str}' is not a valid number.", parent=dialog)
                            return
                payload['accepted_numeric_answers'] = numeric_answers

            if not payload:
                messagebox.showinfo("Info", "No changes were made.", parent=dialog)
                return

            try:
                query = supabase.table("questions").update(payload)
                if is_bulk_edit:
                    question_ids = [q['id'] for q in questions_to_edit]
                    query.in_("id", question_ids).execute()
                    messagebox.showinfo("Success", f"Updated {len(question_ids)} questions.")
                else:
                    query.eq("id", single_question['id']).execute()
                    messagebox.showinfo("Success", "Question updated successfully.")
                self.refresh_questions(); dialog.destroy()
            except Exception as e: self.show_error("Failed to update", e)

        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent"); btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="Save Changes", command=on_save).pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)
        self.app.wait_window(dialog)

    def ask_for_section_dialog(self):
        dialog = ctk.CTkToplevel(self.app)
        dialog.title("Select Section")
        dialog.geometry("300x150")
        dialog.transient(self.app)
        dialog.grab_set()
        result = [None]
        ctk.CTkLabel(dialog, text="Choose a destination section:").pack(pady=10)
        section_var = ctk.StringVar(value=self.sections[0] if self.sections else "")
        menu = ctk.CTkOptionMenu(dialog, variable=section_var, values=self.sections)
        menu.pack(pady=10, padx=20, fill="x")
        def on_ok(): result[0] = section_var.get(); dialog.destroy()
        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent"); btn_frame.pack(pady=10)
        ctk.CTkButton(btn_frame, text="OK", command=on_ok).pack(side="left", padx=10)
        ctk.CTkButton(btn_frame, text="Cancel", command=dialog.destroy, fg_color="gray").pack(side="left", padx=10)
        self.app.wait_window(dialog)
        return result[0]

    # === PAGINATION CONTROLS ===
    def next_page(self):
        self.current_page += 1
        self.refresh_questions(page_change=True)

    def prev_page(self):
        if self.current_page > 1:
            self.current_page -= 1
            self.refresh_questions(page_change=True)

    # === IMAGE HANDLING ===
    def show_full_image(self, bucket, path):
        if not path or not bucket or not PIL_AVAILABLE:
            return

        top = ctk.CTkToplevel(self.app)
        top.title(os.path.basename(path))
        top.geometry("800x600")
        top.transient(self.app)

        image_label = ctk.CTkLabel(top, text="Downloading full image...")
        image_label.pack(expand=True, fill="both", padx=10, pady=10)

        def load_and_display():
            def download_action():
                img_data = supabase.storage.from_(bucket).download(path)
                img = Image.open(BytesIO(img_data))

                screen_width = self.app.winfo_screenwidth() - 100
                screen_height = self.app.winfo_screenheight() - 150
                img.thumbnail((screen_width, screen_height), Image.Resampling.LANCZOS)

                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(img.width, img.height))
                return img, ctk_img

            try:
                img, ctk_img = self._execute_with_retry(download_action)

                def update_ui():
                    image_label.configure(image=ctk_img, text="")
                    top.geometry(f"{img.width + 20}x{img.height + 20}")
                    top.image = ctk_img
                self.app.after(0, update_ui)

            except Exception as e:
                logging.error(f"Failed to load full image {path} after all attempts: {e}")
                self.app.after(0, lambda exc=e: image_label.configure(text=f"Error loading image:\n{exc}", image=None))

        threading.Thread(target=load_and_display, daemon=True).start()

    def _load_thumbnail(self, image_label, bucket, path):
        if path in self.thumbnail_cache:
            cached_img = self.thumbnail_cache[path]
            self.app.after(0, lambda: image_label.configure(image=cached_img, text=""))
            return

        def download_action():
            img_data = supabase.storage.from_(bucket).download(path)
            img = Image.open(BytesIO(img_data))
            img.thumbnail((80, 80))  # ✅ CHANGED from (480, 480)
            return ctk.CTkImage(light_image=img, dark_image=img, size=(img.width, img.height))

        try:
            ctk_img = self._execute_with_retry(download_action)

            def update_label():
                image_label.configure(image=ctk_img, text="")
                self.image_references.append(ctk_img)
                self.thumbnail_cache[path] = ctk_img

            self.app.after(0, update_label)
        except Exception as e:
            self.app.after(0, lambda: image_label.configure(image=None, text="[No Preview]"))
            logging.warning(f"Failed to load thumbnail for {path} after all attempts: {e}")

    def clear_thumbnail_cache(self, *args):
        logging.info("Bucket changed, clearing thumbnail cache.")
        self.thumbnail_cache.clear()

    # === EXPORT / IMPORT ===
    def export_questions(self):
        file_path = filedialog.asksaveasfilename(defaultextension=".json")
        if not file_path:
            return
        try:
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(self.current_questions, f, indent=2, ensure_ascii=False)
            messagebox.showinfo("Exported", f"Saved to {file_path}")
        except Exception as e:
            self.show_error("Export failed", e)

    def import_questions(self):
        file_path = filedialog.askopenfilename(filetypes=[("JSON files", "*.json")])
        if not file_path:
            return
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            for q in data:
                if "id" in q:
                    del q["id"]
                supabase.table("questions").insert(q).execute()
            self.refresh_questions()
            messagebox.showinfo("Imported", f"Imported {len(data)} questions")
        except Exception as e:
            self.show_error("Import failed", e)

    # === HELPERS ===
    def _execute_with_retry(self, action, max_attempts=5, initial_delay=1.0):
        def is_retryable(e):
            err_str = str(e).lower()
            return "'statuscode': 404" in err_str or "not_found" in err_str

        for attempt in range(max_attempts):
            try:
                return action()
            except Exception as e:
                if is_retryable(e) and attempt < max_attempts - 1:
                    delay = initial_delay * (2 ** attempt)
                    logging.warning(f"Retryable error for '{getattr(action, '__name__', 'action')}', attempt {attempt + 1}. Retrying in {delay:.1f}s...")
                    time.sleep(delay)
                else:
                    logging.error(f"Action '{getattr(action, '__name__', 'action')}' failed after {max_attempts} attempts.")
                    raise e

    def show_error(self, user_message, error_exception):
        logging.error(f"{user_message}: {error_exception}")
        messagebox.showerror("Error", f"{user_message}.\nSee logs for more details.")

    # === RUN ===
    def run(self):
        self.app.mainloop()

# MAIN
if __name__ == "__main__":
    app = QuestionManagerApp()
    app.run()