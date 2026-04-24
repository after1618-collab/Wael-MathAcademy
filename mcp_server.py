# mcp_server.py
import os
import uuid
import hashlib
import time
from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException, Depends, Header, Security
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel, EmailStr
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from dotenv import load_dotenv
from passlib.context import CryptContext

# -----------------------------
# تحميل المتغيرات من .env
# -----------------------------
script_dir = os.path.dirname(os.path.abspath(__file__))
dotenv_path = os.path.join(script_dir, ".env")

# ✅ إذا كان الملف مسمى 'env' بدون نقطة، سنقوم بالتحقق منه واستخدامه
if not os.path.exists(dotenv_path) and os.path.exists(os.path.join(script_dir, "env")):
    dotenv_path = os.path.join(script_dir, "env")

env_loaded = load_dotenv(dotenv_path)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY") # ⚠️ إضافة مفتاح أمان للمعلم

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    error_msg = f"❌ Environment variables missing.\nChecked file: {dotenv_path}\nFile Found: {env_loaded}"
    if not env_loaded: error_msg += "\n\n⚠️ Ensure the '.env' file exists in the project root folder."
    raise RuntimeError(error_msg)

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# --- Security (Hashing) ---
# إعداد سياق التشفير باستخدام bcrypt
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


# -----------------------------
# FastAPI app
# -----------------------------
app = FastAPI(title="WAEL MCP Backend", version="1.0", description="Server for managing student sessions.")

# Enable CORS (Cross-Origin Resource Sharing)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://wael-mathacademy.up.railway.app",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------
# نماذج البيانات (Models)
# -----------------------------
class SessionLogin(BaseModel):
    email: EmailStr  # Using EmailStr for validation
    password: str    # ⚠️ إضافة حقل كلمة المرور
    device_id: str

class SessionLogout(BaseModel):
    session_token: str

class SetPasswordRequest(BaseModel):
    student_id: str
    new_password: str

class Hash:
    def bcrypt(password: str):
        return pwd_context.hash(password)
    def verify(hashed_password: str, plain_password: str):
        return pwd_context.verify(plain_password, hashed_password)

class SubmitAnswerRequest(BaseModel):
    question_id: str
    submitted_answer: str
    revealed: bool = False

class SessionRequest(BaseModel):
    student_id: str
    device_id: str

class StudentData(BaseModel):
    full_name: str
    email: str
    class_name: str = None

# -----------------------------
# Dependency for protected routes
# -----------------------------
# ⚠️ هام جداً للأداء: تم تغيير async def إلى def
# مكتبة supabase-py متزامنة (blocking)، استخدام async هنا يسبب تجميد الخادم مع عدد الطلاب الكبير
def get_current_student(authorization: str = Header(..., description="Student's active session token as 'Bearer <token>'")):
    """
    Dependency that checks for a valid session token in the request header.
    If valid, it returns the student_id. Otherwise, it raises an HTTPException.
    """
    try:
        if not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Invalid authorization scheme. Use 'Bearer <token>'.")
        
        token = authorization.split(" ")[1]

        res = supabase.table("sessions").select("student_id").eq("session_token", token).eq("active", True).limit(1).execute()
        if not res.data:
            raise HTTPException(status_code=401, detail="Invalid or expired session token")
        return res.data[0]["student_id"]
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Session validation error: {e}")

def get_admin_access(x_api_key: str = Header(..., description="Admin's secret API key.")):
    """
    Dependency that checks for a valid admin API key in the request header.
    This is a simple way to protect teacher/admin-only endpoints.
    """
    if not ADMIN_API_KEY:
        raise HTTPException(status_code=500, detail="Admin API key is not configured on the server.")
    if x_api_key != ADMIN_API_KEY:
        raise HTTPException(status_code=403, detail="Invalid Admin API Key.")


# -----------------------------
# Endpoints
# -----------------------------

@app.get("/google0e59f1440c6a05bd.html", include_in_schema=False)
def serve_google_verification():
    """خدمة ملف التحقق من Google Search Console"""
    return FileResponse(os.path.join(script_dir, "google0e59f1440c6a05bd.html"))

# --- Session Management ---
@app.post("/sessions/login", summary="Student login and session creation")
def login_and_create_session(data: SessionLogin):
    """
    - يتحقق من وجود الطالب وحالته (مفعّل).
    - يلغي أي جلسات قديمة نشطة لنفس الطالب.
    - ينشئ جلسة جديدة ويعيد الـ token.
    """
    try:
        # 1. التحقق من أن الطالب موجود ومفعّل
        student_res = supabase.table("students").select("id, activated, hashed_password").eq("email", data.email).limit(1).execute()
        if not student_res.data:
            raise HTTPException(status_code=404, detail="Student not found")
        
        student = student_res.data[0]
        if not student["activated"]:
            raise HTTPException(status_code=403, detail="Student account is not activated")
        
        # ⚠️ التحقق من كلمة المرور
        if not student.get("hashed_password"):
            raise HTTPException(status_code=400, detail="A password has not been set for this account")
        
        if not Hash.verify(student["hashed_password"], data.password[:72]):
            raise HTTPException(status_code=401, detail="Incorrect password")

        student_id = student["id"]

        # 2. إلغاء أي جلسات قديمة نشطة للطالب
        supabase.table("sessions").update({"active": False}).eq("student_id", student_id).eq("active", True).execute()

        # 3. إنشاء جلسة جديدة
        session_token = str(uuid.uuid4())
        new_session = {
            "student_id": student_id,
            "device_id": data.device_id,
            "session_token": session_token,
            "active": True,
            "created_at": datetime.utcnow().isoformat()
        }
        supabase.table("sessions").insert(new_session).execute()
        
        return {"status": "success", "session_token": session_token, "student_id": student_id}
    except HTTPException as http_exc:
        raise http_exc
    except Exception as e:
        print(f"Error during login: {e}")
        raise HTTPException(status_code=500, detail=f"An unexpected error occurred: {e}")

@app.get("/sessions/validate/{session_token}", summary="Validate session token")
def validate_session(session_token: str):
    """
    يتحقق مما إذا كان الـ token لجلسة نشطة.
    يعيد بيانات الجلسة إذا كانت صالحة.
    """
    try:
        result = supabase.table("sessions").select("*, students(full_name, email)").eq("session_token", session_token).eq("active", True).limit(1).execute()
        if not result.data:
            return {"valid": False, "detail": "Invalid or expired session"}
        return {"valid": True, "session": result.data[0]}
    except Exception as e:
        raise HTTPException(status_code=500, detail="An error occurred while validating the session.")

@app.post("/sessions/logout", summary="Student logout")
def logout_session(data: SessionLogout):
    """
    إنهاء جلسة الطالب بناءً على الـ token.
    """
    try:
        result = supabase.table("sessions").select("id").eq("session_token", data.session_token).eq("active", True).execute()
        if not result.data:
            return {"status": "not_found", "detail": "Session not found or already ended."}

        supabase.table("sessions").update({"active": False}).eq("session_token", data.session_token).execute()
        return {"status": "logged_out"}
    except Exception as e:
        raise HTTPException(status_code=500, detail="An error occurred during logout.")

@app.get("/sessions/active", summary="(Admin) List all active sessions")
def list_active_sessions(_: bool = Depends(get_admin_access)):
    """
    يعرض قائمة بكل الجلسات النشطة حالياً مع بيانات الطلاب المرتبطين بها.
    """
    try:
        result = supabase.table("sessions").select("*, students(full_name, email)").eq("active", True).execute()
        return {"active_sessions": result.data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to retrieve active sessions.")

@app.post("/sessions/force_end/{session_token}", summary="(Admin) Force end a student session")
def force_end_session(session_token: str, _: bool = Depends(get_admin_access)):
    """
    يسمح للمعلم بإنهاء جلسة طالب محددة بالقوة.
    """
    try:
        result = supabase.table("sessions").select("id").eq("session_token", session_token).eq("active", True).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="Active session with this token not found.")

        supabase.table("sessions").update({"active": False}).eq("session_token", session_token).execute()
        return {"status": "force_ended"}
    except HTTPException as http_exc:
        raise http_exc
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
# ⚠️ تم حذف نقاط النهاية المكررة والقديمة /start_session و /end_session

@app.post("/admin/set-password", summary="(Admin) Set a student's password")
def set_student_password(req: SetPasswordRequest, _: bool = Depends(get_admin_access)):
    """
    يسمح للمعلم بتعيين أو تحديث كلمة مرور طالب.
    """
    try:
        hashed_pw = Hash.bcrypt(req.new_password[:72])
        supabase.table("students").update({"hashed_password": hashed_pw}).eq("id", req.student_id).execute()
        return {"status": "success", "detail": "Password updated successfully."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to set password: {e}")

# --- Student Management (Admin) ---

@app.get("/admin/students", summary="(Admin) Get all students")
def get_all_students(_: bool = Depends(get_admin_access)):
    try:
        res = supabase.table("students").select("*").order("created_at").execute()
        return res.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch students: {e}")

@app.post("/admin/students", summary="(Admin) Add a new student")
def add_student(student: StudentData, _: bool = Depends(get_admin_access)):
    try:
        new_student = {
            "full_name": student.full_name,
            "email": student.email,
            "class_name": student.class_name,
            "activated": True # Default to activated
        }
        res = supabase.table("students").insert(new_student).execute()
        return res.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to add student: {e}")

@app.put("/admin/students/{student_id}", summary="(Admin) Update student")
def update_student(student_id: str, student: StudentData, _: bool = Depends(get_admin_access)):
    try:
        updates = {
            "full_name": student.full_name,
            "email": student.email,
            "class_name": student.class_name
        }
        # Remove None values
        updates = {k: v for k, v in updates.items() if v is not None}
        
        res = supabase.table("students").update(updates).eq("id", student_id).execute()
        return res.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update student: {e}")

@app.delete("/admin/students/{student_id}", summary="(Admin) Delete student")
def delete_student(student_id: str, _: bool = Depends(get_admin_access)):
    try:
        res = supabase.table("students").delete().eq("id", student_id).execute()
        return {"status": "deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete student: {e}")

@app.post("/admin/students/{student_id}/toggle-activation", summary="(Admin) Toggle student activation")
def toggle_student_activation(student_id: str, _: bool = Depends(get_admin_access)):
    try:
        current = supabase.table("students").select("activated").eq("id", student_id).single().execute()
        new_status = not current.data["activated"]
        
        res = supabase.table("students").update({"activated": new_status}).eq("id", student_id).execute()
        return {"status": "toggled", "activated": new_status}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to toggle activation: {e}")

@app.get("/progress/{student_id}", summary="(Admin) Get a specific student's progress")
def get_student_progress(student_id: str, _: bool = Depends(get_admin_access)):
    result = supabase.table("student_progress").select("*").eq("student_id", student_id).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="No progress found for this student")
    return {"progress": result.data[0]}

@app.get("/progress", summary="(Admin) Get all students' progress")
def get_all_progress(_: bool = Depends(get_admin_access)):
    result = supabase.table("student_progress").select("*, students(full_name, email)").execute()
    return {"all_progress": result.data}

# --- Questions and Attempts (Protected) ---

@app.get("/questions", summary="Get student questions (Protected)")
def get_student_questions(section_id: str = None, student_id: str = Depends(get_current_student)):
    """
    يجلب قائمة الأسئلة. يتطلب `session_token` صالح في الـ header.
    يمكن فلترة الأسئلة اختيارياً بواسطة `section_id`.
    """
    try:
        query = supabase.table("questions").select("*")
        if section_id:
            query = query.eq("section_id", section_id)
        questions = query.execute().data
        return {"questions": questions}
    except Exception as e:
        print(f"❌ Error fetching questions: {e}")
        raise HTTPException(status_code=500, detail="Failed to retrieve questions.")

@app.post("/attempts/submit", summary="Submit student answer (Protected)")
def submit_student_answer(req: SubmitAnswerRequest, student_id: str = Depends(get_current_student)):
    """
    يسجل إجابة الطالب على سؤال. يتطلب `session_token` صالح في الـ header.
    """
    try:
        # --- Rate Limiting (from your suggestion) ---
        # Prevent submitting for the same question within 5 seconds
        last_attempt_res = supabase.table("attempts").select("created_at").eq("student_id", student_id).eq("question_id", req.question_id).order("created_at", desc=True).limit(1).execute()
        if last_attempt_res.data:
            last_attempt_time = datetime.fromisoformat(last_attempt_res.data[0]['created_at'])
            # Ensure current time is timezone-aware for correct comparison
            current_time = datetime.now(timezone.utc)
            if (current_time - last_attempt_time).total_seconds() < 5:
                raise HTTPException(
                    status_code=429, detail="Too many attempts. Please wait a few seconds."
                )

        # 1. Fetch question to check the answer
        question_res = supabase.table("questions").select("*").eq("id", req.question_id).limit(1).execute()
        if not question_res.data:
            raise HTTPException(status_code=404, detail="Question not found")
        question = question_res.data[0]

        # 2. Grade the answer
        is_correct = False
        answer_type = question.get("answer_type", "mcq")
        
        if answer_type == "mcq":
            correct_answer = question.get("correct_answer", "")
            is_correct = req.submitted_answer.strip().upper() == correct_answer.strip().upper()
        elif answer_type == "numeric":
            accepted_answers = question.get("accepted_numeric_answers")
            if accepted_answers: # New logic: check against list
                try:
                    submitted_val = float(req.submitted_answer)
                    is_correct = any(abs(submitted_val - accepted_val) < 1e-9 for accepted_val in accepted_answers)
                except (ValueError, TypeError):
                    is_correct = False
        else:  # Handles 'text', 'short_answer', etc.
            correct_answer = question.get("correct_answer", "")
            is_correct = req.submitted_answer.strip().lower() == correct_answer.strip().lower()

        # 3. Check if this is the first attempt for this question
        first_attempt_res = supabase.table("attempts").select("id", count='exact').eq("student_id", student_id).eq("question_id", req.question_id).execute()
        is_first_attempt = first_attempt_res.count == 0

        # 4. Record the attempt (FIX: This line was missing)
        supabase.table("attempts").insert({
            "student_id": student_id,
            "question_id": req.question_id,
            "submitted_answer": req.submitted_answer,
            "is_correct": is_correct,
            "revealed": req.revealed,
            "is_first_attempt": is_first_attempt,
        }).execute()

        return {"is_correct": is_correct, "question_id": req.question_id, "is_first_attempt": is_first_attempt}
    except Exception as e:
        raise HTTPException(status_code=500, detail="An error occurred while submitting the answer.")

# --- Reporting Endpoints ---
# Note: These endpoints assume you have created corresponding RPC functions in Supabase
# for security and performance. This is safer than a generic "exec_sql" function.

@app.get("/reports/students", summary="(Admin) Generate student performance report")
def get_student_report(start_date: str = None, end_date: str = None, _: bool = Depends(get_admin_access)):
    """
    Calls a specific RPC function `get_student_report` in Supabase.
    This is the recommended secure way to run complex SQL queries.
    """
    try:
        params = {"start_date_param": start_date, "end_date_param": end_date}
        result = supabase.rpc("get_student_report", params).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Report generation failed: {e}")

@app.get("/reports/questions", summary="(Admin) Generate question performance report")
def get_question_report(start_date: str = None, end_date: str = None, _: bool = Depends(get_admin_access)):
    """
    Calls a specific RPC function `get_question_report` in Supabase.
    """
    try:
        params = {"start_date_param": start_date, "end_date_param": end_date}
        result = supabase.rpc("get_question_report", params).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Report generation failed: {e}")

@app.get("/reports/sections", summary="(Admin) Generate section performance report")
def get_section_report(start_date: str = None, end_date: str = None, _: bool = Depends(get_admin_access)):
    """
    Calls a specific RPC function `get_section_report` in Supabase.
    """
    try:
        params = {"start_date_param": start_date, "end_date_param": end_date}
        result = supabase.rpc("get_section_report", params).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Report generation failed: {e}")

@app.get("/reports/global", summary="(Admin) Generate global performance report")
def get_global_report(start_date: str = None, end_date: str = None, _: bool = Depends(get_admin_access)):
    """
    Calls a specific RPC function `get_global_report` in Supabase.
    """
    try:
        params = {"start_date_param": start_date, "end_date_param": end_date}
        result = supabase.rpc("get_global_report", params).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Report generation failed: {e}")

# --- New Endpoints: Sections & Questions via Server ---

@app.get("/sections", summary="Get all sections (Protected)")
def get_sections(student_id: str = Depends(get_current_student)):
    """
    يجلب كل الأقسام المتاحة. يتطلب session_token صالح.
    """
    try:
        result = supabase.table("sections").select("id, name, description").order("created_at").execute()
        return {"sections": result.data}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to retrieve sections.")


@app.get("/sections/{section_id}/questions", summary="Get questions for a section (Protected)")
def get_section_questions(section_id: str, student_id: str = Depends(get_current_student)):
    """
    يجلب أسئلة قسم معين مع روابط الصور. يتطلب session_token صالح.
    """
    try:
        result = supabase.table("questions").select("*").eq("section_id", section_id).order("created_at").execute()
        
        questions = result.data
        # ✅ أضف رابط الصورة الكامل لكل سؤال
        for q in questions:
            if q.get("image_path"):
                q["image_url"] = supabase.storage.from_("questions").get_public_url(q["image_path"])
            else:
                q["image_url"] = None
        
        return {"questions": questions}
    except Exception as e:
        raise HTTPException(status_code=500, detail="Failed to retrieve questions.")


@app.get("/student/profile", summary="Get current student profile (Protected)")
def get_student_profile(student_id: str = Depends(get_current_student)):
    """
    يجلب بيانات الطالب الحالي (الاسم، الفصل، معدل النجاح).
    """
    try:
        # بيانات الطالب
        student_res = supabase.table("students").select("id, full_name, email, class_name").eq("id", student_id).limit(1).execute()
        if not student_res.data:
            raise HTTPException(status_code=404, detail="Student not found")
        
        student = student_res.data[0]
        
        # ✅ حساب معدل النجاح من أول محاولة فقط
        total_res = supabase.table("attempts").select("id", count="exact").eq("student_id", student_id).eq("is_first_attempt", True).execute()
        correct_res = supabase.table("attempts").select("id", count="exact").eq("student_id", student_id).eq("is_first_attempt", True).eq("is_correct", True).execute()
        
        total = total_res.count or 0
        correct = correct_res.count or 0
        success_rate = (correct / total * 100) if total > 0 else 0.0
        
        return {
            "student": {
                "id": student["id"],
                "full_name": student["full_name"],
                "email": student["email"],
                "class_name": student.get("class_name", "Not assigned"),
                "success_rate": round(success_rate, 1),
                "total_attempts": total,
                "correct_attempts": correct,
            }
        }
    except HTTPException as http_exc:
        raise http_exc
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get profile: {e}")

@app.get("/student/wrong-answers", summary="Get student's wrong answers (Protected)")
def get_student_wrong_answers(student_id: str = Depends(get_current_student)):
    try:
        # Get all wrong first attempts
        attempts_res = supabase.table("attempts").select(
            "question_id, submitted_answer, created_at"
        ).eq("student_id", student_id).eq("is_first_attempt", True).eq("is_correct", False).order("created_at", desc=True).execute()

        if not attempts_res.data:
            return {"wrong_answers": [], "total": 0}

        # Get question details
        question_ids = [a["question_id"] for a in attempts_res.data]
        questions_res = supabase.table("questions").select(
            "id, correct_answer, answer_type, section_id, image_path, options, accepted_numeric_answers"
        ).in_("id", question_ids).execute()

        questions_map = {q["id"]: q for q in questions_res.data}

        # Get section names
        section_ids = list(set(q.get("section_id") for q in questions_res.data if q.get("section_id")))
        sections_map = {}
        if section_ids:
            sections_res = supabase.table("sections").select("id, name").in_("id", section_ids).execute()
            sections_map = {s["id"]: s["name"] for s in sections_res.data}

        # Combine data
        wrong_answers = []
        for attempt in attempts_res.data:
            q = questions_map.get(attempt["question_id"])
            if not q:
                continue

            image_url = None
            if q.get("image_path"):
                image_url = supabase.storage.from_("questions").get_public_url(q["image_path"])

            wrong_answers.append({
                "question_id": q["id"],
                "question_text": "",
                "options": q.get("options"),
                "answer_type": q.get("answer_type", "mcq"),
                "correct_answer": q.get("correct_answer", ""),
                "accepted_numeric_answers": q.get("accepted_numeric_answers"),
                "student_answer": attempt["submitted_answer"],
                "section_name": sections_map.get(q.get("section_id"), "Unknown"),
                "image_url": image_url,
                "attempted_at": attempt["created_at"],
            })

        return {"wrong_answers": wrong_answers, "total": len(wrong_answers)}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get wrong answers: {e}")

# =============================================
# VIDEO LESSONS ENDPOINTS
# =============================================

# --- Models ---
class CourseData(BaseModel):
    title: str
    description: str = None
    thumbnail_url: str = None
    sort_order: int = 0
    is_published: bool = True

class LessonData(BaseModel):
    course_id: str
    title: str
    description: str = None
    video_url: str
    video_type: str = "youtube"
    duration_minutes: int = None
    sort_order: int = 0
    is_published: bool = True
    is_free: bool = False

class LessonProgressUpdate(BaseModel):
    lesson_id: str
    watch_percentage: int = 0

# --- Student Endpoints ---

@app.get("/courses", summary="Get all published courses (Protected)")
def get_courses(student_id: str = Depends(get_current_student)):
    try:
        result = supabase.table("courses").select("*").eq(
            "is_published", True
        ).order("sort_order").execute()
        courses = result.data or []

        for course in courses:
            lessons_res = supabase.table("lessons").select("id").eq(
                "course_id", course["id"]
            ).eq("is_published", True).execute()
            lesson_ids = [l["id"] for l in (lessons_res.data or [])]
            course["total_lessons"] = len(lesson_ids)

            if lesson_ids:
                watched_res = supabase.table("lesson_progress").select(
                    "id", count="exact"
                ).eq("student_id", student_id).eq(
                    "watched", True
                ).in_("lesson_id", lesson_ids).execute()
                course["watched_lessons"] = watched_res.count or 0
            else:
                course["watched_lessons"] = 0

            if course["total_lessons"] > 0:
                course["progress_percentage"] = round(
                    (course["watched_lessons"] / course["total_lessons"]) * 100
                )
            else:
                course["progress_percentage"] = 0

        return {"courses": courses}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get courses: {e}")


@app.get("/courses/{course_id}/lessons", summary="Get lessons for a course (Protected)")
def get_course_lessons(course_id: str, student_id: str = Depends(get_current_student)):
    try:
        result = supabase.table("lessons").select("*").eq(
            "course_id", course_id
        ).eq("is_published", True).order("sort_order").execute()
        lessons = result.data or []

        for lesson in lessons:
            progress_res = supabase.table("lesson_progress").select(
                "watched, watch_percentage, last_watched_at"
            ).eq("student_id", student_id).eq(
                "lesson_id", lesson["id"]
            ).limit(1).execute()

            if progress_res.data:
                lesson["watched"] = progress_res.data[0]["watched"]
                lesson["watch_percentage"] = progress_res.data[0]["watch_percentage"]
                lesson["last_watched_at"] = progress_res.data[0]["last_watched_at"]
            else:
                lesson["watched"] = False
                lesson["watch_percentage"] = 0
                lesson["last_watched_at"] = None

        return {"lessons": lessons}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get lessons: {e}")


@app.post("/lessons/progress", summary="Update lesson watch progress (Protected)")
def update_lesson_progress(
    data: LessonProgressUpdate,
    student_id: str = Depends(get_current_student)
):
    try:
        watched = data.watch_percentage >= 90

        existing = supabase.table("lesson_progress").select("id").eq(
            "student_id", student_id
        ).eq("lesson_id", data.lesson_id).limit(1).execute()

        if existing.data:
            supabase.table("lesson_progress").update({
                "watch_percentage": data.watch_percentage,
                "watched": watched,
                "last_watched_at": datetime.utcnow().isoformat()
            }).eq("student_id", student_id).eq(
                "lesson_id", data.lesson_id
            ).execute()
        else:
            supabase.table("lesson_progress").insert({
                "student_id": student_id,
                "lesson_id": data.lesson_id,
                "watch_percentage": data.watch_percentage,
                "watched": watched,
                "last_watched_at": datetime.utcnow().isoformat()
            }).execute()

        return {
            "status": "updated",
            "watched": watched,
            "watch_percentage": data.watch_percentage
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update progress: {e}")


@app.get("/student/courses/progress", summary="Get student course progress (Protected)")
def get_student_courses_progress(student_id: str = Depends(get_current_student)):
    try:
        result = supabase.rpc("get_student_course_progress", {"p_student_id": student_id}).execute()
        return {"progress": result.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get progress: {e}")


# --- Admin Endpoints ---

@app.get("/admin/courses", summary="(Admin) Get all courses")
def admin_get_courses(_: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("courses").select("*").order("sort_order").execute()
        return {"courses": result.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get courses: {e}")


@app.post("/admin/courses", summary="(Admin) Create a course")
def admin_create_course(course: CourseData, _: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("courses").insert({
            "title": course.title,
            "description": course.description,
            "thumbnail_url": course.thumbnail_url,
            "sort_order": course.sort_order,
            "is_published": course.is_published
        }).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create course: {e}")


@app.put("/admin/courses/{course_id}", summary="(Admin) Update a course")
def admin_update_course(course_id: str, course: CourseData, _: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("courses").update({
            "title": course.title,
            "description": course.description,
            "thumbnail_url": course.thumbnail_url,
            "sort_order": course.sort_order,
            "is_published": course.is_published
        }).eq("id", course_id).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update course: {e}")


@app.delete("/admin/courses/{course_id}", summary="(Admin) Delete a course")
def admin_delete_course(course_id: str, _: bool = Depends(get_admin_access)):
    try:
        supabase.table("courses").delete().eq("id", course_id).execute()
        return {"status": "deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete course: {e}")


@app.get("/admin/courses/{course_id}/lessons", summary="(Admin) Get all lessons for a course")
def admin_get_course_lessons(course_id: str, _: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("lessons").select("*").eq(
            "course_id", course_id
        ).order("sort_order").execute()
        return {"lessons": result.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get lessons: {e}")


@app.post("/admin/lessons", summary="(Admin) Create a lesson")
def admin_create_lesson(lesson: LessonData, _: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("lessons").insert({
            "course_id": lesson.course_id,
            "title": lesson.title,
            "description": lesson.description,
            "video_url": lesson.video_url,
            "video_type": lesson.video_type,
            "duration_minutes": lesson.duration_minutes,
            "sort_order": lesson.sort_order,
            "is_published": lesson.is_published,
            "is_free": lesson.is_free
        }).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create lesson: {e}")


@app.put("/admin/lessons/{lesson_id}", summary="(Admin) Update a lesson")
def admin_update_lesson(lesson_id: str, lesson: LessonData, _: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("lessons").update({
            "course_id": lesson.course_id,
            "title": lesson.title,
            "description": lesson.description,
            "video_url": lesson.video_url,
            "video_type": lesson.video_type,
            "duration_minutes": lesson.duration_minutes,
            "sort_order": lesson.sort_order,
            "is_published": lesson.is_published,
            "is_free": lesson.is_free
        }).eq("id", lesson_id).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update lesson: {e}")


@app.delete("/admin/lessons/{lesson_id}", summary="(Admin) Delete a lesson")
def admin_delete_lesson(lesson_id: str, _: bool = Depends(get_admin_access)):
    try:
        supabase.table("lessons").delete().eq("id", lesson_id).execute()
        return {"status": "deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete lesson: {e}")


@app.get("/admin/video-stats", summary="(Admin) Get video statistics")
def admin_get_video_stats(_: bool = Depends(get_admin_access)):
    try:
        result = supabase.rpc("get_video_stats").execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get stats: {e}")


@app.get("/admin/courses/{course_id}/report", summary="(Admin) Get course detail report")
def admin_get_course_report(course_id: str, _: bool = Depends(get_admin_access)):
    try:
        result = supabase.rpc("get_course_detail_report", {"p_course_id": course_id}).execute()
        return result.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get report: {e}")

# =============================================
# PROTECTED VIDEO SYSTEM
# =============================================

class VideoAccessRequest(BaseModel):
    lesson_id: str

class RecordWatchRequest(BaseModel):
    lesson_id: str

@app.post("/video/request-access", summary="Request temporary video access (Protected)")
def request_video_access(
    req: VideoAccessRequest,
    student_id: str = Depends(get_current_student)
):
    """
    يتحقق من عدد المشاهدات ويعطي رابط مؤقت للفيديو.
    الحد الأقصى: مشاهدتين لكل درس.
    """
    try:
        # 1. Check watch count فقط بدون زيادة
        watch_res = supabase.table("lesson_progress").select(
            "watch_count, blocked"
        ).eq("student_id", student_id).eq(
            "lesson_id", req.lesson_id
        ).limit(1).execute()

        max_watches = 2  # ✅ الحد الأقصى للمشاهدة

        if watch_res.data:
            progress = watch_res.data[0]
            
            if progress.get("blocked", False):
                raise HTTPException(
                    status_code=403,
                    detail="You have been blocked from viewing this lesson."
                )
            
            current_count = progress.get("watch_count", 0)
            last_watched = progress.get("last_watched_at")
            
            # ✅ Sliding window logic: If last watched within 6 hours, it's the SAME attempt.
            increment_watch = True
            if last_watched:
                try:
                    last_watched_time = datetime.fromisoformat(last_watched.replace("Z", "+00:00"))
                    if last_watched_time.tzinfo is None:
                        last_watched_time = last_watched_time.replace(tzinfo=timezone.utc)
                    hours_diff = (datetime.now(timezone.utc) - last_watched_time).total_seconds() / 3600.0
                    if hours_diff < 6.0:
                        increment_watch = False
                except Exception as e:
                    print(f"Error parsing last_watched: {e}")
            
            if increment_watch and current_count >= max_watches:
                raise HTTPException(
                    status_code=403,
                    detail=f"Watch limit reached ({max_watches}/{max_watches}). Contact your teacher for reset."
                )
        else:
            current_count = 0
            increment_watch = True

        # 2. Get lesson info
        lesson_res = supabase.table("lessons").select(
            "video_url, video_type, title"
        ).eq("id", req.lesson_id).limit(1).execute()

        if not lesson_res.data:
            raise HTTPException(status_code=404, detail="Lesson not found")

        lesson = lesson_res.data[0]

        # 3. Generate temporary signed token
        expires_at = int(time.time()) + 3600  # 1 hour
        raw = f"{student_id}:{req.lesson_id}:{expires_at}:{ADMIN_API_KEY}"
        signature = hashlib.sha256(raw.encode()).hexdigest()[:32]

        video_token = f"{expires_at}.{signature}"

        # Get student details for watermark
        student_info = supabase.table("students").select("full_name, email").eq("id", student_id).single().execute()
        student_name = student_info.data.get("full_name", "Student") if student_info.data else "Student"
        student_email = student_info.data.get("email", "") if student_info.data else ""

        # ✅ مش بنزود العداد هنا خالص
        return {
            "status": "granted",
            "video_url": lesson["video_url"],
            "video_type": lesson["video_type"],
            "video_token": video_token,
            "expires_in": 3600,
            "watches_used": current_count,
            "watches_remaining": max_watches - current_count,
            "student_name": student_name,  # For watermark
            "student_email": student_email,
            "student_id": student_id,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to request access: {e}")

@app.post("/video/record-watch", summary="Record a video watch at 70% (Protected)")
def record_video_watch(
    req: RecordWatchRequest,
    student_id: str = Depends(get_current_student)
):
    """
    ✅ يُستدعى فقط لما الطالب يشاهد 70% من الفيديو.
    بيزود watch_count بمقدار 1.
    """
    try:
        max_watches = 2

        watch_res = supabase.table("lesson_progress").select(
            "watch_count, blocked"
        ).eq("student_id", student_id).eq(
            "lesson_id", req.lesson_id
        ).limit(1).execute()

        if watch_res.data:
            progress = watch_res.data[0]

            if progress.get("blocked", False):
                raise HTTPException(
                    status_code=403,
                    detail="You have been blocked from viewing this lesson."
                )

            current_count = progress.get("watch_count", 0)

            if current_count >= max_watches:
                raise HTTPException(
                    status_code=403,
                    detail=f"Watch limit already reached ({current_count}/{max_watches})."
                )

            # ✅ زود العداد
            new_count = current_count + 1
            supabase.table("lesson_progress").update({
                "watch_count": new_count,
                "watched": True,
                "watch_percentage": 70,
                "last_watched_at": datetime.utcnow().isoformat()
            }).eq("student_id", student_id).eq(
                "lesson_id", req.lesson_id
            ).execute()

        else:
            # أول مشاهدة
            new_count = 1
            supabase.table("lesson_progress").insert({
                "student_id": student_id,
                "lesson_id": req.lesson_id,
                "watch_count": new_count,
                "watched": True,
                "watch_percentage": 70,
                "last_watched_at": datetime.utcnow().isoformat()
            }).execute()

        return {
            "status": "recorded",
            "watches_used": new_count,
            "watches_remaining": max_watches - new_count
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to record watch: {e}")

@app.post("/video/verify-token", summary="Verify video access token (Protected)")
def verify_video_token(
    lesson_id: str,
    video_token: str,
    student_id: str = Depends(get_current_student)
):
    """يتحقق من صلاحية الـ token المؤقت"""
    try:
        parts = video_token.split(".")
        if len(parts) != 2:
            raise HTTPException(status_code=403, detail="Invalid token")

        expires_at = int(parts[0])
        signature = parts[1]

        # Check expiry
        if time.time() > expires_at:
            raise HTTPException(status_code=403, detail="Token expired")

        # Verify signature
        raw = f"{student_id}:{lesson_id}:{expires_at}:{ADMIN_API_KEY}"
        expected = hashlib.sha256(raw.encode()).hexdigest()[:32]

        if signature != expected:
            raise HTTPException(status_code=403, detail="Invalid token")

        return {"valid": True}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=403, detail="Invalid token")


# --- Admin: Reset watch count ---
@app.post("/admin/lessons/{lesson_id}/reset-watches/{student_id}",
          summary="(Admin) Reset student watch count")
def admin_reset_watch_count(
    lesson_id: str,
    student_id: str,
    _: bool = Depends(get_admin_access)
):
    try:
        supabase.table("lesson_progress").update({
            "watch_count": 0,
            "blocked": False
        }).eq("student_id", student_id).eq(
            "lesson_id", lesson_id
        ).execute()
        return {"status": "reset", "detail": "Watch count reset to 0"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reset: {e}")


@app.post("/admin/lessons/reset-all-watches/{student_id}",
          summary="(Admin) Reset ALL watch counts for a student")
def admin_reset_all_watches(
    student_id: str,
    _: bool = Depends(get_admin_access)
):
    try:
        supabase.table("lesson_progress").update({
            "watch_count": 0,
            "blocked": False
        }).eq("student_id", student_id).execute()
        return {"status": "reset_all"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reset: {e}")


@app.get("/admin/watch-report", summary="(Admin) Get watch count report")
def admin_watch_report(_: bool = Depends(get_admin_access)):
    try:
        result = supabase.table("lesson_progress").select(
            "student_id, lesson_id, watch_count, watched, last_watched_at, "
            "students(full_name, email), lessons(title)"
        ).gt("watch_count", 0).order("watch_count", desc=True).execute()
        return {"report": result.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed: {e}")

# -----------------------------
# Static Files (Web Build)
# -----------------------------
_static_dir = os.path.join(script_dir, "build", "web")

if os.path.isdir(_static_dir):
    app.mount("/", StaticFiles(directory=_static_dir, html=True), name="static")
else:
    print(f"⚠️ Static files not found at: {_static_dir} — Skipping static mount.")

# -----------------------------
# Run (للتجربة المحلية فقط)
# -----------------------------
if __name__ == "__main__":
    import uvicorn
    from multiprocessing import freeze_support

    freeze_support()  # Add this for Windows multiprocessing support
    # To prevent the reloader from scanning the entire user directory on Windows,
    # which can cause errors with long file paths (like in .gradle caches),
    # we explicitly specify the project directory to watch for changes.
    project_dir = os.path.dirname(os.path.abspath(__file__))
    uvicorn.run(
        "mcp_server:app", host="0.0.0.0", port=8000, reload=True, reload_dirs=[project_dir]
    )
