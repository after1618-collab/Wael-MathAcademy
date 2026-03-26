-- ================================================================
-- MCP UNIFIED DATABASE SCRIPT
-- ================================================================

-- تنظيف أولي
DROP VIEW IF EXISTS public.student_progress CASCADE;
DROP VIEW IF EXISTS public.question_stats CASCADE;
DROP TABLE IF EXISTS public.attempts CASCADE;
DROP TABLE IF EXISTS public.sessions CASCADE;
DROP TABLE IF EXISTS public.questions CASCADE;
DROP TABLE IF EXISTS public.sections CASCADE;
DROP TABLE IF EXISTS public.students CASCADE;
DROP TYPE IF EXISTS public.answer_type CASCADE;

-- مسح الدوال
DO $$
DECLARE
    func_record RECORD;
BEGIN
    FOR func_record IN (
        SELECT
            'DROP FUNCTION IF EXISTS ' || ns.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ');' AS drop_cmd
        FROM
            pg_proc p
        JOIN
            pg_namespace ns ON p.pronamespace = ns.oid
        WHERE
            ns.nspname = 'public'
    ) LOOP
        EXECUTE func_record.drop_cmd;
    END LOOP;
END $$;

-- ================================================================
-- الإضافات (Extensions)
-- ================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ================================================================
-- الجداول
-- ================================================================

-- جدول الطلاب
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    email TEXT UNIQUE,
    class_name TEXT,
    hashed_password TEXT,
    activated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- جدول الأقسام
CREATE TABLE public.sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ENUM نوع الإجابة
CREATE TYPE public.answer_type AS ENUM ('mcq', 'numeric', 'text');

-- جدول الأسئلة
CREATE TABLE public.questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id UUID REFERENCES public.sections(id) ON DELETE SET NULL,
    question_text TEXT,
    reveal_image_path TEXT,
    image_path TEXT,
    answer_type public.answer_type NOT NULL DEFAULT 'mcq',
    correct_answer TEXT,
    options JSONB,
    allow_text BOOLEAN DEFAULT FALSE,
    accepted_numeric_answers JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- جدول المحاولات
CREATE TABLE public.attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    question_id UUID REFERENCES public.questions(id) ON DELETE CASCADE,
    submitted_answer TEXT,
    is_correct BOOLEAN,
    is_first_attempt BOOLEAN DEFAULT FALSE,
    revealed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- جدول الجلسات
CREATE TABLE public.sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    device_id TEXT,
    session_token UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ================================================================
-- الدوال الأساسية (Core Logic Functions)
-- ================================================================

-- إضافة محاولة (نسخة محسنة)
CREATE OR REPLACE FUNCTION public.add_attempt(
    p_student_id uuid,
    p_question_id uuid,
    p_submitted_answer text,
    p_revealed boolean DEFAULT FALSE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_question RECORD;
    v_is_correct BOOLEAN := FALSE;
    v_is_first BOOLEAN;
    v_attempt_id UUID;
    v_submitted_numeric NUMERIC;
    v_accepted_answer NUMERIC;
BEGIN
    -- جلب بيانات السؤال
    SELECT * INTO v_question
    FROM public.questions q
    WHERE q.id = p_question_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Question with ID % not found', p_question_id;
    END IF;

    -- التحقق من صحة الإجابة بناءً على النوع
    IF v_question.answer_type = 'numeric' AND v_question.accepted_numeric_answers IS NOT NULL THEN
        BEGIN
            v_submitted_numeric := p_submitted_answer::NUMERIC;
            FOR v_accepted_answer IN SELECT (value::NUMERIC) FROM jsonb_array_elements_text(v_question.accepted_numeric_answers)
            LOOP
                IF abs(v_submitted_numeric - v_accepted_answer) < 1e-9 THEN
                    v_is_correct := TRUE;
                    EXIT;
                END IF;
            END LOOP;
        EXCEPTION WHEN others THEN
            v_is_correct := FALSE; -- فشل التحويل إلى رقم
        END;
    ELSE -- 'mcq' or 'text'
        v_is_correct := (trim(lower(p_submitted_answer)) = trim(lower(v_question.correct_answer)));
    END IF;

    -- هل هذه أول محاولة؟
    SELECT NOT EXISTS (
        SELECT 1 FROM public.attempts
        WHERE student_id = p_student_id AND question_id = p_question_id
    ) INTO v_is_first;

    -- إدراج المحاولة
    INSERT INTO public.attempts (student_id, question_id, submitted_answer, is_correct, is_first_attempt, revealed)
    VALUES (p_student_id, p_question_id, p_submitted_answer, v_is_correct, v_is_first, p_revealed)
    RETURNING id INTO v_attempt_id;

    RETURN v_attempt_id;
END;
$$;

-- استرجاع محاولات طالب
CREATE OR REPLACE FUNCTION public.get_attempts(p_student_id uuid)
RETURNS TABLE (
    attempt_id uuid,
    question_id uuid,
    submitted_answer text,
    is_correct boolean,
    is_first_attempt boolean,
    revealed boolean,
    created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT id, question_id, submitted_answer, is_correct, is_first_attempt, revealed, created_at
    FROM public.attempts
    WHERE student_id = p_student_id
    ORDER BY created_at DESC;
$$;

-- بدء جلسة جديدة
CREATE OR REPLACE FUNCTION public.start_session(p_student_id uuid, p_device_id text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_token uuid := gen_random_uuid();
BEGIN
    -- إنهاء أي جلسة نشطة سابقة لنفس الطالب
    UPDATE public.sessions
    SET active = FALSE
    WHERE student_id = p_student_id
      AND active = TRUE;

    -- إضافة الجلسة الجديدة
    INSERT INTO public.sessions (student_id, device_id, session_token, active)
    VALUES (p_student_id, p_device_id, new_token, TRUE);

    RETURN new_token;
END;
$$;

-- إنهاء جلسة
CREATE OR REPLACE FUNCTION public.end_session(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.sessions
    SET active = FALSE
    WHERE session_token = p_token;
END;
$$;

-- ================================================================
-- الدوال الإدارية (Admin & Management Functions)
-- ================================================================

-- 🔹 دوال إدارة الطلاب
CREATE OR REPLACE FUNCTION add_student(p_full_name TEXT, p_email TEXT, p_class_name TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id UUID;
BEGIN
    INSERT INTO public.students(full_name, email, class_name)
    VALUES (p_full_name, p_email, p_class_name)
    RETURNING id INTO new_id;
    RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION update_student(p_id UUID, p_full_name TEXT, p_email TEXT, p_class_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.students
    SET full_name = p_full_name, email = p_email, class_name = p_class_name, updated_at = now()
    WHERE id = p_id;
    RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION delete_student(p_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public.students WHERE id = p_id;
    RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION get_all_students()
RETURNS SETOF public.students
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT * FROM public.students ORDER BY created_at DESC;
$$;

-- 🔹 دوال إدارة الأقسام
CREATE OR REPLACE FUNCTION add_section(p_name TEXT, p_description TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_id UUID;
BEGIN
    INSERT INTO public.sections(name, description)
    VALUES (p_name, p_description)
    RETURNING id INTO new_id;
    RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION update_section(p_id UUID, p_name TEXT, p_description TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.sections SET name = p_name, description = p_description WHERE id = p_id;
    RETURN FOUND;
END $$;

-- استرجاع محاولات جميع الطلاب (للأدمين)
CREATE OR REPLACE FUNCTION public.admin_get_attempts()
RETURNS TABLE (
    attempt_id uuid,
    student_id uuid,
    student_name text,
    question_id uuid,
    submitted_answer text,
    is_correct boolean,
    created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT a.id, a.student_id, st.full_name, a.question_id, a.submitted_answer, a.is_correct, a.created_at
    FROM public.attempts a
    JOIN public.students st ON st.id = a.student_id
    ORDER BY a.created_at DESC;
$$;

-- ================================================================
-- دوال التقارير (Reporting Functions)
-- ================================================================
-- تقرير الطلاب
CREATE OR REPLACE FUNCTION public.get_student_report(
    start_date_param date DEFAULT NULL,
    end_date_param date DEFAULT NULL
)
RETURNS TABLE (
    student_id uuid,
    full_name text,
    email text,
    total_attempts bigint,
    correct_attempts bigint,
    correct_percentage numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
SELECT
    st.id AS student_id,
    st.full_name,
    st.email,
    count(a.id) AS total_attempts,
    count(a.id) FILTER (WHERE a.is_correct) AS correct_attempts,
    CASE
        WHEN count(a.id) > 0 THEN
            round((count(a.id) FILTER (WHERE a.is_correct) * 100.0) / count(a.id), 2)
        ELSE 0
    END AS correct_percentage
FROM public.students st
LEFT JOIN public.attempts a ON st.id = a.student_id
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param)
GROUP BY st.id, st.full_name, st.email
ORDER BY correct_percentage DESC;
$$;

-- تقرير الأسئلة
CREATE OR REPLACE FUNCTION public.get_question_report(
    start_date_param date DEFAULT NULL,
    end_date_param date DEFAULT NULL
)
RETURNS TABLE (
    question_id uuid,
    image_path text,
    total_attempts bigint,
    correct_attempts bigint,
    correct_percentage numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
SELECT
    q.id AS question_id,
    q.image_path,
    count(a.id) AS total_attempts,
    count(a.id) FILTER (WHERE a.is_correct) AS correct_attempts,
    CASE
        WHEN count(a.id) > 0 THEN
            round((count(a.id) FILTER (WHERE a.is_correct) * 100.0) / count(a.id), 2)
        ELSE 0
    END AS correct_percentage
FROM public.questions q
LEFT JOIN public.attempts a ON q.id = a.question_id
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param)
GROUP BY q.id, q.image_path
ORDER BY correct_percentage ASC;
$$;

-- تقرير الأقسام
CREATE OR REPLACE FUNCTION public.get_section_report(
    start_date_param date DEFAULT NULL,
    end_date_param date DEFAULT NULL
)
RETURNS TABLE (
    section_id uuid,
    section_name text,
    total_attempts bigint,
    correct_attempts bigint,
    correct_percentage numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
SELECT
    s.id AS section_id,
    s.name AS section_name,
    count(a.id) AS total_attempts,
    count(a.id) FILTER (WHERE a.is_correct) AS correct_attempts,
    CASE
        WHEN count(a.id) > 0 THEN
            round((count(a.id) FILTER (WHERE a.is_correct) * 100.0) / count(a.id), 2)
        ELSE 0
    END AS correct_percentage
FROM public.sections s
LEFT JOIN public.questions q ON s.id = q.section_id
LEFT JOIN public.attempts a ON q.id = a.question_id
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param)
GROUP BY s.id, s.name
ORDER BY correct_percentage ASC;
$$;

-- تقرير عام
CREATE OR REPLACE FUNCTION public.get_global_report(
    start_date_param date DEFAULT NULL,
    end_date_param date DEFAULT NULL
)
RETURNS TABLE (
    total_students bigint,
    total_questions bigint,
    total_attempts bigint,
    overall_correct_percentage numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $$
SELECT
    (SELECT count(*) FROM public.students) AS total_students,
    (SELECT count(*) FROM public.questions) AS total_questions,
    count(a.id) AS total_attempts,
    CASE
        WHEN count(a.id) > 0 THEN
            round((count(a.id) FILTER (WHERE a.is_correct) * 100.0) / count(a.id), 2)
        ELSE 0
    END AS overall_correct_percentage
FROM public.attempts a
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param);
$$;

-- ================================================================
-- الأمان وسياسات الوصول (RLS - Row-Level Security)
-- ================================================================

-- تفعيل RLS على الجداول
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

-- حذف السياسات القديمة (لضمان عدم التعارض)
DROP POLICY IF EXISTS "Admin full access" ON public.students;
DROP POLICY IF EXISTS "Admin full access" ON public.questions;
DROP POLICY IF EXISTS "Students can view questions" ON public.questions;
DROP POLICY IF EXISTS "Admin full access" ON public.sections;
DROP POLICY IF EXISTS "Students can view sections" ON public.sections;
DROP POLICY IF EXISTS "Admin full access" ON public.attempts;
DROP POLICY IF EXISTS "Students can insert and view own attempts" ON public.attempts;
DROP POLICY IF EXISTS "Admin full access" ON public.sessions;
DROP POLICY IF EXISTS "Students can manage own sessions" ON public.sessions;

-- سياسات عامة: السماح للمدير (service_role) بالوصول الكامل
CREATE POLICY "Admin full access" ON public.students FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Admin full access" ON public.questions FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Admin full access" ON public.sections FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Admin full access" ON public.attempts FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "Admin full access" ON public.sessions FOR ALL USING (auth.role() = 'service_role');

-- سياسات الطلاب (authenticated)
-- الطلاب يمكنهم قراءة الأسئلة والأقسام
CREATE POLICY "Students can view questions" ON public.questions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Students can view sections" ON public.sections FOR SELECT TO authenticated USING (true);

-- الطلاب يمكنهم إضافة وقراءة محاولاتهم فقط
-- ملاحظة: هذا يعتمد على أن الخادم يمرر student_id الصحيح. RLS هنا طبقة أمان إضافية.
CREATE POLICY "Students can insert and view own attempts" ON public.attempts FOR ALL TO authenticated
    USING (student_id = (SELECT id FROM public.students WHERE email = auth.jwt()->>'email'))
    WITH CHECK (student_id = (SELECT id FROM public.students WHERE email = auth.jwt()->>'email'));

-- الطلاب يمكنهم إدارة جلساتهم فقط
CREATE POLICY "Students can manage own sessions" ON public.sessions FOR ALL TO authenticated
    USING (student_id = (SELECT id FROM public.students WHERE email = auth.jwt()->>'email'))
    WITH CHECK (student_id = (SELECT id FROM public.students WHERE email = auth.jwt()->>'email'));

-- ================================================================
-- Grant final permissions
-- ================================================================
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role, authenticated;