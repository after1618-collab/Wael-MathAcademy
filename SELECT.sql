SELECT
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS parameters
FROM
    pg_proc p
JOIN
    pg_namespace n ON p.pronamespace = n.oid
WHERE
    n.nspname = 'public' -- Or your specific schema if different
ORDER BY
    function_name, parameters;

-- =================================================================
-- REPORTING FUNCTIONS
-- =================================================================

-- 1. Student Performance Report
-- This function analyzes the performance of each student.
CREATE OR REPLACE FUNCTION get_student_report(
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
FROM
    students st
LEFT JOIN
    attempts a ON st.id = a.student_id
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param)
GROUP BY
    st.id, st.full_name, st.email
ORDER BY
    correct_percentage DESC;
$$;

-- 2. Question Performance Report
-- This function analyzes the difficulty and performance of each question.
CREATE OR REPLACE FUNCTION get_question_report(
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
FROM
    questions q
LEFT JOIN
    attempts a ON q.id = a.question_id
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param)
GROUP BY
    q.id, q.image_path
ORDER BY
    correct_percentage ASC;
$$;

-- 3. Section Performance Report
-- This function analyzes the overall performance of each section.
CREATE OR REPLACE FUNCTION get_section_report(
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
FROM
    sections s
LEFT JOIN
    questions q ON s.id = q.section_id
LEFT JOIN
    attempts a ON q.id = a.question_id
WHERE
    (start_date_param IS NULL OR a.created_at >= start_date_param) AND
    (end_date_param IS NULL OR a.created_at <= end_date_param)
GROUP BY
    s.id, s.name
ORDER BY
    correct_percentage ASC;
$$;

ALTER TABLE public.students
ADD COLUMN hashed_password TEXT;

ALTER TABLE public.questions
ADD COLUMN accepted_numeric_answers JSONB;

-- سياسة تسمح فقط للمستخدمين المسجلين بقراءة الأسئلة
CREATE POLICY "Allow authenticated users to read questions"
ON public.questions FOR SELECT
TO authenticated
USING (true);

-- سياسة تسمح فقط للمستخدمين الذين لديهم دور 'admin' بحذف الأسئلة
-- (تفترض أن لديك عمود 'role' في جدول المستخدمين)
CREATE POLICY "Allow admins to delete questions"
ON public.questions FOR DELETE
TO authenticated
USING ( (SELECT auth.jwt() ->> 'role') = 'admin' );

ALTER TABLE public.questions
ADD COLUMN options JSONB DEFAULT '["A", "B", "C", "D"]'::jsonb;

ALTER TABLE public.questions
ADD COLUMN allow_text BOOLEAN DEFAULT FALSE;

-- ============================
-- Students Management Package (Fixed)
-- ============================
ALTER TABLE public.students
ADD COLUMN class_name TEXT;
-- 1) إضافة طالب جديد
create or replace function add_student(
  p_full_name text,
  p_email text,
  p_class text default null
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_new_id uuid;
begin
  -- تأمين: السماح فقط للإدمن
  if auth.role() <> 'authenticated' or not (auth.jwt() ->> 'role' = 'admin') then
    raise exception 'Permission denied';
  end if;

  insert into students (full_name, email, class_name)
  values (p_full_name, p_email, p_class)
  returning id into v_new_id;

  return v_new_id;
end;
$$;

-- 2) تعديل بيانات طالب
create or replace function update_student(
  p_student_id uuid,
  p_full_name text default null,
  p_email text default null,
  p_class text default null
)
returns void
language plpgsql
security definer
as $$
begin
  if auth.role() <> 'authenticated' or not (auth.jwt() ->> 'role' = 'admin') then
    raise exception 'Permission denied';
  end if;

  update students
  set 
    full_name = coalesce(p_full_name, full_name),
    email = coalesce(p_email, email),
    class_name = coalesce(p_class, class_name),
    updated_at = now()
  where id = p_student_id;
end;
$$;

-- 3) حذف طالب
create or replace function delete_student(
  p_student_id uuid
)
returns void
language plpgsql
security definer
as $$
begin
  if auth.role() <> 'authenticated' or not (auth.jwt() ->> 'role' = 'admin') then
    raise exception 'Permission denied';
  end if;

  delete from students where id = p_student_id;
end;
$$;

-- 4) استعراض كل الطلاب
create or replace function get_all_students()
returns table (
  id uuid,
  full_name text,
  email text,
  class_name text,
  created_at timestamptz
)
language sql
security definer
as $$
  select id, full_name, email, class_name, created_at
  from students
  order by created_at desc;
$$;

-- 5) استعراض طالب محدد
create or replace function get_student_by_id(
  p_student_id uuid
)
returns table (
  id uuid,
  full_name text,
  email text,
  class_name text,
  created_at timestamptz
)
language sql
security definer
as $$
  select id, full_name, email, class_name, created_at
  from students
  where id = p_student_id;
$$;

-- 🛑 احذف النسخة القديمة لو موجودة
drop function if exists get_my_summary_by_section();

-- ✅ إنشاء الدالة
create or replace function get_my_summary_by_section()
returns table(
    section_id uuid,
    section_name text,
    total_answered int,
    correct_count int,
    wrong_count int,
    success_rate numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select 
        q.section_id,
        s.name as section_name,
        count(*)::int as total_answered,
        count(*) filter (where a.is_correct)::int as correct_count,
        count(*) filter (where not a.is_correct)::int as wrong_count,
        case when count(*) = 0 
             then 0 
             else round(100.0 * count(*) filter (where a.is_correct) / count(*), 2) 
        end as success_rate
    from answers a
    join questions q on q.id = a.question_id
    join sections s on s.id = q.section_id
    where a.student_id = auth.uid()
    group by q.section_id, s.name
    order by s.name;
end;
$$;

-- 🔐 تأمين الصلاحيات
revoke all on function get_my_summary_by_section() from public;
grant execute on function get_my_summary_by_section() to authenticated;

-- 🛑 احذف النسخة القديمة لو موجودة
drop function if exists get_my_summary();

-- ✅ إنشاء الدالة
create or replace function get_my_summary()
returns table(
    total_answered int,
    correct_count int,
    wrong_count int,
    success_rate numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select 
        count(*)::int as total_answered,
        count(*) filter (where is_correct)::int as correct_count,
        count(*) filter (where not is_correct)::int as wrong_count,
        case when count(*) = 0 
             then 0 
             else round(100.0 * count(*) filter (where is_correct) / count(*), 2) 
        end as success_rate
    from answers
    where student_id = auth.uid();
end;
$$;

-- 🔐 تأمين الصلاحيات
revoke all on function get_my_summary() from public;
grant execute on function get_my_summary() to authenticated;

-- =====================================================
-- 📊 Student Progress Report
-- =====================================================
drop view if exists public.student_progress cascade;
create or replace view public.student_progress as
select
  s.id as student_id,
  s.full_name,
  s.email,
  count(a.*) as total_attempts,
  count(a.*) filter (where a.is_correct) as correct_attempts,
  count(a.*) filter (where not a.is_correct) as wrong_attempts,
  case when count(a.*) = 0 then 0
       else round(100.0 * count(a.*) filter (where a.is_correct)::numeric / count(a.*), 2)
  end as percent_correct
from public.students s
left join public.attempts a on a.student_id = s.id
group by s.id, s.full_name, s.email;

-- =====================================================
-- 📊 Question Statistics Report
-- =====================================================
drop view if exists public.question_stats cascade;
create or replace view public.question_stats as
select
  q.id as question_id,
  coalesce(q.question_text, '[Image Only]') as question_text,
  q.image_path,
  count(a.*) as total_attempts,
  count(a.*) filter (where a.is_correct) as correct_count,
  count(a.*) filter (where not a.is_correct) as wrong_count,
  case when count(a.*) = 0 then 0
       else round(100.0 * count(a.*) filter (where a.is_correct)::numeric / count(a.*), 2)
  end as percent_correct
from public.questions q
left join public.attempts a on a.question_id = q.id
group by q.id, q.question_text, q.image_path;

-- =====================================================
-- 📊 دالة لإحضار تقارير طالب معين
-- =====================================================
drop function if exists public.admin_get_student_report(uuid);
create or replace function public.admin_get_student_report(p_student_id uuid)
returns table (
  attempt_id uuid,
  question_id uuid,
  submitted_answer text,
  is_correct boolean,
  revealed boolean,
  created_at timestamptz
) language sql as $$
  select a.id, a.question_id, a.submitted_answer, a.is_correct, a.revealed, a.created_at
  from public.attempts a
  where a.student_id = p_student_id
  order by a.created_at desc;
$$;

-- =====================================================
-- 🔒 تأمين الوصول
-- =====================================================

-- أولاً: منع الوصول الافتراضي
revoke all on public.student_progress from public;
revoke all on public.question_stats from public;
revoke all on function public.admin_get_student_report(uuid) from public;

-- السماح فقط للـ service_role (المدرّس/الـ backend)
grant select on public.student_progress to service_role;
grant select on public.question_stats to service_role;
grant execute on function public.admin_get_student_report(uuid) to service_role;

-- ملاحظة:
-- ممكن تعمل دالة get_my_progress(uuid) مخصوص للطلاب
-- بحيث الطالب يشوف تقاريره فقط (بـ auth.uid()).

update questions
set section_id = '3b62bb9f-2d0d-43d9-a81b-00bf936dd191'
where section_id is null;

-- إضافة قسم جديد
create or replace function add_section(p_name text, p_description text default null)
returns uuid
language plpgsql
security definer
as $$
declare
  new_id uuid;
begin
  insert into sections (name, description)
  values (p_name, p_description)
  returning id into new_id;

  return new_id;
end;
$$;

-- حذف قسم
create or replace function delete_section(p_section_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  delete from sections where id = p_section_id;
end;
$$;

-- تعديل قسم
create or replace function update_section(p_section_id uuid, p_name text, p_description text default null)
returns void
language plpgsql
security definer
as $$
begin
  update sections
  set name = p_name,
      description = p_description
  where id = p_section_id;
end;
$$;

-- عرض جميع الأقسام
create or replace function list_sections()
returns table (
  id uuid,
  name text,
  description text,
  created_at timestamptz
)
language sql
security definer
as $$
  select id, name, description, created_at
  from sections
  order by created_at desc;
$$;

-- جلب جميع المحاولات مع بيانات الطالب والسؤال (للمشرف)
create or replace function public.admin_get_attempts()
returns table (
  attempt_id uuid,
  student_id uuid,
  student_full_name text,
  question_id uuid,
  submitted_answer text,
  is_correct boolean,
  is_first_attempt boolean,
  revealed boolean,
  created_at timestamptz
)
language sql
security definer
as $$
  select a.id, a.student_id, s.full_name, a.question_id,
         a.submitted_answer, a.is_correct, a.is_first_attempt,
         a.revealed, a.created_at
  from public.attempts a
  join public.students s on s.id = a.student_id
  order by a.created_at desc;
$$;

-- تسجيل محاولة جديدة (مؤمنة)
create or replace function public.secure_add_attempt(
  p_student_id uuid,
  p_question_id uuid,
  p_submitted_answer text,
  p_revealed boolean
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_correct_answer text;
  v_is_first boolean;
  v_attempt_id uuid;
begin
  -- نجيب الإجابة الصحيحة
  select q.correct_answer into v_correct_answer
  from public.questions q
  where q.id = p_question_id;

  -- هل هي أول محاولة؟
  select not exists (
    select 1 from public.attempts a
    where a.student_id = p_student_id
      and a.question_id = p_question_id
  ) into v_is_first;

  -- نضيف المحاولة
  insert into public.attempts (
    student_id, question_id, submitted_answer,
    is_correct, is_first_attempt, revealed
  )
  values (
    p_student_id, p_question_id, p_submitted_answer,
    (p_submitted_answer = v_correct_answer), v_is_first, p_revealed
  )
  returning id into v_attempt_id;

  return v_attempt_id;
end;
$$;

-- جلب محاولات طالب معين (مؤمنة)
create or replace function public.secure_get_attempts(
  p_student_id uuid
)
returns table (
  attempt_id uuid,
  question_id uuid,
  submitted_answer text,
  is_correct boolean,
  is_first_attempt boolean,
  revealed boolean,
  created_at timestamptz
)
language sql
security definer
as $$
  select a.id, a.question_id, a.submitted_answer,
         a.is_correct, a.is_first_attempt, a.revealed, a.created_at
  from public.attempts a
  where a.student_id = p_student_id
  order by a.created_at desc;
$$;

drop function if exists end_session(uuid);
create or replace function end_session(
    p_session_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    update sessions
    set active = false
    where id = p_session_id
      and active = true;

    return found;
end;
$$;

create or replace function start_session(
    p_student_id uuid,
    p_device_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_session_id uuid;
begin
    -- إلغاء أي جلسة قديمة لنفس الطالب ونفس الجهاز
    update sessions
    set active = false
    where student_id = p_student_id
      and device_id = p_device_id
      and active = true;

    -- إنشاء جلسة جديدة
    insert into sessions(student_id, device_id, session_token, active)
    values (p_student_id, p_device_id, gen_random_uuid()::text, true)
    returning id into v_session_id;

    return v_session_id;
end;
$$;
create or replace function end_session(
    p_session_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    update sessions
    set active = false
    where id = p_session_id
      and active = true;

    return found;
end;
$$;
create or replace function end_session(
    p_session_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    update sessions
    set active = false
    where id = p_session_id
      and active = true;

    return found;
end;
$$;
create or replace function get_active_sessions(
    p_student_id uuid
)
returns table(
    id uuid,
    device_id text,
    session_token text,
    created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
    select s.id, s.device_id, s.session_token, s.created_at
    from sessions s
    where s.student_id = p_student_id
      and s.active = true
    order by s.created_at desc;
$$;

create or replace function public.admin_get_attempts(
  p_student_id uuid default null,
  p_question_id uuid default null
)
returns table (
  attempt_id uuid,
  student_name text,
  student_email text,
  question_id uuid,
  submitted_answer text,
  is_correct boolean,
  is_first_attempt boolean,
  revealed boolean,
  created_at timestamptz
)
language sql
security definer
as $$
  select 
    a.id,
    s.full_name,
    s.email,
    a.question_id,
    a.submitted_answer,
    a.is_correct,
    a.is_first_attempt,
    a.revealed,
    a.created_at
  from public.attempts a
  join public.students s on s.id = a.student_id
  where (p_student_id is null or a.student_id = p_student_id)
    and (p_question_id is null or a.question_id = p_question_id)
  order by a.created_at desc;
$$;

create or replace function public.end_session(
  p_token uuid
)
returns void
language plpgsql
security definer
as $$
begin
  update public.sessions
  set active = false
  where session_token = p_token
    and student_id in (
      select id from public.students where auth_uid = auth.uid()
    );
end;
$$;

create or replace function public.start_session(
  p_device_id text
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_student_id uuid;
  v_token uuid := gen_random_uuid();
begin
  -- جلب الـ student_id للطالب الحالي من الـ JWT
  select id into v_student_id
  from public.students
  where auth_uid = auth.uid();

  if v_student_id is null then
    raise exception 'Unauthorized';
  end if;

  -- تعطيل الجلسات السابقة
  update public.sessions
  set active = false
  where student_id = v_student_id;

  -- إدخال جلسة جديدة
  insert into public.sessions(student_id, device_id, session_token, active)
  values (v_student_id, p_device_id, v_token, true);

  return v_token;
end;
$$;

drop function if exists public.get_attempts(uuid);
create or replace function public.get_attempts(
  p_question_id uuid default null
)
returns table (
  attempt_id uuid,
  question_id uuid,
  submitted_answer text,
  is_correct boolean,
  is_first_attempt boolean,
  revealed boolean,
  created_at timestamptz
)
language sql
security definer
as $$
  select a.id, a.question_id, a.submitted_answer, a.is_correct, a.is_first_attempt, a.revealed, a.created_at
  from public.attempts a
  join public.students s on s.id = a.student_id
  where s.auth_uid = auth.uid()
    and (p_question_id is null or a.question_id = p_question_id);
$$;

create or replace function public.add_attempt(
  p_question_id uuid,
  p_submitted_answer text,
  p_revealed boolean default false
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_student_id uuid;
  v_correct text;
  v_first boolean;
  v_attempt_id uuid;
begin
  -- نجيب الطالب المرتبط بالـ JWT الحالي
  select id into v_student_id
  from public.students
  where auth_uid = auth.uid();

  if v_student_id is null then
    raise exception 'Unauthorized student';
  end if;

  -- نجيب الاجابة الصحيحة
  select correct_answer into v_correct
  from public.questions
  where id = p_question_id;

  -- هل دي أول محاولة؟
  select not exists(
    select 1 from public.attempts
    where student_id = v_student_id and question_id = p_question_id
  ) into v_first;

  -- نضيف المحاولة
  insert into public.attempts(student_id, question_id, submitted_answer, is_correct, is_first_attempt, revealed)
  values (v_student_id, p_question_id, p_submitted_answer, (p_submitted_answer = v_correct), v_first, p_revealed)
  returning id into v_attempt_id;

  return v_attempt_id;
end;
$$;

create or replace function public.get_attempts(p_student_id uuid)
returns table (
    attempt_id uuid,
    question_id uuid,
    submitted_answer text,
    is_correct boolean,
    is_first_attempt boolean,
    revealed boolean,
    created_at timestamptz
)
language sql
as $$
    select id, question_id, submitted_answer, is_correct, is_first_attempt, revealed, created_at
    from public.attempts
    where student_id = p_student_id
    order by created_at desc;
$$;

create or replace function public.get_attempts(p_student_id uuid)
returns table (
    attempt_id uuid,
    question_id uuid,
    submitted_answer text,
    is_correct boolean,
    is_first_attempt boolean,
    revealed boolean,
    created_at timestamptz
)
language sql
as $$
    select id, question_id, submitted_answer, is_correct, is_first_attempt, revealed, created_at
    from public.attempts
    where student_id = p_student_id
    order by created_at desc;
$$;

create or replace function public.add_attempt(
    p_student_id uuid,
    p_question_id uuid,
    p_submitted_answer text,
    p_revealed boolean default false
) returns uuid
language plpgsql
as $$
declare
    v_correct_answer text;
    v_answer_type public.answer_type;
    v_tolerance double precision;
    v_is_correct boolean;
    v_is_first boolean;
    v_attempt_id uuid;
begin
    -- نجيب بيانات السؤال
    select q.correct_answer, q.answer_type, coalesce(q.numeric_tolerance, 0.01)
    into v_correct_answer, v_answer_type, v_tolerance
    from public.questions q
    where q.id = p_question_id;

    -- نحدد صحة الإجابة
    if v_answer_type = 'numeric' then
        v_is_correct := abs((p_submitted_answer::double precision) - (v_correct_answer::double precision)) <= v_tolerance;
    else
        v_is_correct := (upper(p_submitted_answer) = upper(v_correct_answer));
    end if;

    -- هل دي أول محاولة؟
    v_is_first := not exists (
        select 1 from public.attempts
        where student_id = p_student_id
          and question_id = p_question_id
    );

    -- نسجّل المحاولة
    insert into public.attempts(student_id, question_id, submitted_answer, is_correct, is_first_attempt, revealed)
    values (p_student_id, p_question_id, p_submitted_answer, v_is_correct, v_is_first, p_revealed)
    returning id into v_attempt_id;

    return v_attempt_id;
end;
$$;

-- دالة لبدء جلسة جديدة مع إنهاء أي جلسات قديمة
create or replace function start_single_session(p_student_id uuid, p_device_id text)
returns uuid
language plpgsql
as $$
declare
  new_token uuid := gen_random_uuid();
begin
  -- إنهاء أي جلسات قديمة لنفس الطالب
  update sessions
  set active = false
  where student_id = p_student_id
    and active = true;

  -- إنشاء جلسة جديدة
  insert into sessions (student_id, device_id, session_token, active)
  values (p_student_id, p_device_id, new_token, true);

  return new_token;
end;
$$;

-- 1) حذف النسخ القديمة
drop function if exists end_session(text);
drop function if exists end_session(uuid);

-- 2) نسخة موحدة لـ end_session
create or replace function end_session(p_token text)
returns void
language plpgsql
as $$
begin
  update sessions
  set active = false
  where session_token::text = p_token;
end;
$$;

-- 3) دالة لعرض الجلسات الفعالة لطالب معين
create or replace function list_active_sessions(p_student_id uuid)
returns table (
  session_id uuid,
  device_id text,
  session_token text,
  created_at timestamptz
)
language sql
as $$
  select id, device_id, session_token, created_at
  from sessions
  where student_id = p_student_id
    and active = true
  order by created_at desc;
$$;

create function end_session(p_token text)
returns void
language plpgsql
as $$
begin
  update sessions
  set active = false
  where session_token::text = p_token;
end;
$$;

drop function if exists end_session(text);
drop function if exists end_session(uuid);

create function end_session(p_token text)
returns void
language plpgsql
as $$
begin
  update sessions
  set active = false
  where session_token = p_token::uuid;
end;
$$;

-- 1. لو مش موجود نضيف جدول الجلسات
create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  device_id text not null,        -- بصمة الجهاز أو random id
  session_token text unique not null,
  active boolean default true,
  created_at timestamptz default now()
);

-- 2. policy: الطالب يشوف جلسته فقط
alter table public.sessions enable row level security;

create policy "Students can only see their own sessions"
on public.sessions
for select
using (student_id = auth.uid()::uuid);

-- 3. function: بداية جلسة جديدة → تعطل القديمة
create or replace function public.start_session(
  p_student_id uuid,
  p_device_id text
) returns uuid
language plpgsql
as $$
declare
  v_token uuid := gen_random_uuid();
begin
  -- عطل أي جلسة قديمة لنفس الطالب
  update public.sessions
  set active = false
  where student_id = p_student_id;

  -- أضف الجلسة الجديدة
  insert into public.sessions (student_id, device_id, session_token, active)
  values (p_student_id, p_device_id, v_token, true);

  return v_token;
end;
$$;

-- 4. function: إنهاء جلسة
create or replace function public.end_session(
  p_token uuid
) returns void
language plpgsql
as $$
begin
  update public.sessions
  set active = false
  where session_token = p_token;
end;
$$;

-- ============================
-- Fix & Secure RLS Policies (casts to avoid uuid = text errors)
-- Run this in Supabase SQL Editor
-- Replace teacher UID below with your actual teacher's auth UID
-- ============================

-- === teacher UID: استبدل بالقيمة الحقيقية بتاعتك ===
-- Example: '22a1e7c0-3d5a-4f5d-9c5d-8a31f70cd123'
-- Keep it as text but we'll cast to uuid in policies.
-- ===================================================
--SET search_path = public;

-- 0) Optional: If students.auth_uid is text, try to convert it to uuid safely
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='auth_uid' AND data_type='text'
  ) THEN
    -- Attempt to convert column to uuid using safe cast; this will fail if some values are not parseable as uuid.
    BEGIN
      ALTER TABLE public.students ALTER COLUMN auth_uid TYPE uuid USING auth_uid::uuid;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Could not CAST students.auth_uid TEXT -> UUID automatically. Ensure values are valid UUIDs or leave as TEXT.';
    END;
  END IF;
END$$;

-- 1) Enable RLS on relevant tables (idempotent)
ALTER TABLE IF EXISTS public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sections ENABLE ROW LEVEL SECURITY;

-- 2) Drop old policies that might be wrong (safe cleanup)
DO $$
BEGIN
  PERFORM 1 FROM pg_policy WHERE polname = 'Only_teacher_manage_students' LIMIT 1;
EXCEPTION WHEN OTHERS THEN
  -- ignore
END$$;

DROP POLICY IF EXISTS "Only teacher can manage students" ON public.students;
DROP POLICY IF EXISTS "Students can view own record" ON public.students;
DROP POLICY IF EXISTS "Only teacher can manage questions" ON public.questions;
DROP POLICY IF EXISTS "Students can view questions" ON public.questions;
DROP POLICY IF EXISTS "Only teacher can manage sections" ON public.sections;
DROP POLICY IF EXISTS "Students manage own attempts" ON public.attempts;
DROP POLICY IF EXISTS "Students view own attempts" ON public.attempts;
DROP POLICY IF EXISTS "Teacher full access attempts" ON public.attempts;
DROP POLICY IF EXISTS "Students manage own sessions" ON public.sessions;
DROP POLICY IF EXISTS "Teacher full access sessions" ON public.sessions;

-- 3) Policies for students table
-- Teacher full management (replace teacher UID below)
CREATE POLICY "Only teacher can manage students"
  ON public.students
  FOR ALL
  USING (auth.uid()::uuid = '70a5ba2f-e52f-4fae-9e65-4e0269b547b2'::uuid OR auth.role() = 'service_role');

-- Student can view/update their own row (auth_uid column expected to be uuid)
CREATE POLICY "Students can view own record"
  ON public.students
  FOR SELECT
  USING (auth.uid()::uuid = auth_uid);

CREATE POLICY "Students can update own record"
  ON public.students
  FOR UPDATE
  USING (auth.uid()::uuid = auth_uid)
  WITH CHECK (auth.uid()::uuid = auth_uid);

-- 4) Policies for questions
-- Students may read questions (public read)
CREATE POLICY "Students can view questions"
  ON public.questions
  FOR SELECT
  USING (true);

-- Teacher can manage questions
CREATE POLICY "Only teacher can manage questions"
  ON public.questions
  FOR ALL
  USING (auth.uid()::uuid = '70a5ba2f-e52f-4fae-9e65-4e0269b547b2'::uuid OR auth.role() = 'service_role');

-- 5) Policies for sections
CREATE POLICY "Students can view sections"
  ON public.sections
  FOR SELECT
  USING (true);

CREATE POLICY "Only teacher can manage sections"
  ON public.sections
  FOR ALL
  USING (auth.uid()::uuid = '70a5ba2f-e52f-4fae-9e65-4e0269b547b2'::uuid OR auth.role() = 'service_role');

-- 6) Policies for attempts
-- Students may INSERT attempts only for their own student_id (check uses students.auth_uid cast)
CREATE POLICY "Students insert own attempts"
  ON public.attempts
  FOR INSERT
  WITH CHECK (
    student_id = (
      SELECT id FROM public.students WHERE auth_uid = auth.uid()::uuid
    )
  );

-- Students may SELECT only their own attempts
CREATE POLICY "Students select own attempts"
  ON public.attempts
  FOR SELECT
  USING (
    student_id = (
      SELECT id FROM public.students WHERE auth_uid = auth.uid()::uuid
    )
  );

-- Teacher / service role can do everything on attempts
CREATE POLICY "Teacher full access attempts"
  ON public.attempts
  FOR ALL
  USING (auth.uid()::uuid = '70a5ba2f-e52f-4fae-9e65-4e0269b547b2'::uuid OR auth.role() = 'service_role');

-- 7) Policies for sessions
-- Students may manage their own sessions
CREATE POLICY "Students manage own sessions"
  ON public.sessions
  FOR ALL
  USING (
    student_id = (
      SELECT id FROM public.students WHERE auth_uid = auth.uid()::uuid
    )
  )
  WITH CHECK (
    student_id = (
      SELECT id FROM public.students WHERE auth_uid = auth.uid()::uuid
    )
  );

-- Teacher / service role can manage sessions too
CREATE POLICY "Teacher full access sessions"
  ON public.sessions
  FOR ALL
  USING (auth.uid()::uuid = '70a5ba2f-e52f-4fae-9e65-4e0269b547b2'::uuid OR auth.role() = 'service_role');

-- 8) Permit public/anon role to read questions if you want unauthenticated reads
-- (Optional) If you want anonymous users (not logged in) to list questions, allow select for anon role.
-- You can instead require login for all reads by not granting this. Uncomment if needed.
-- GRANT SELECT ON public.questions TO anon;

-- 9) Final sanity check message (no-op): ensure policies exist
SELECT
  pol.polname, tbl.relname
FROM pg_policy pol
JOIN pg_class tbl ON pol.polrelid = tbl.oid
WHERE tbl.relname IN ('students','questions','attempts','sessions','sections');

-- 🔒 تفعيل RLS على كل الجداول
alter table public.students enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.sessions enable row level security;

-- 🧑 الطلاب:
-- الطالب يقدر يشوف نفسه فقط
create policy "Students can view themselves"
on public.students for select
using (auth.uid() = auth_uid);

-- فقط المدرس يقدر يعدل/يفعل/يعطل الطلاب
create policy "Only teacher can manage students"
on public.students for all
using (auth.uid() = 'YOUR_TEACHER_UID');  -- حط الـ UID بتاعك من Supabase Auth

-- ❓ الأسئلة:
-- الطالب يقدر يشوف الأسئلة فقط
create policy "Students can view questions"
on public.questions for select
using (true);

-- فقط المدرس يقدر يضيف/يعدل/يحذف الأسئلة
create policy "Only teacher can manage questions"
on public.questions for all
using (auth.uid() = 'YOUR_TEACHER_UID');

-- 📝 المحاولات:
-- الطالب يقدر يضيف Attempt لنفسه فقط
create policy "Students can insert own attempts"
on public.attempts for insert
with check (student_id in (select id from public.students where auth_uid = auth.uid()));

-- الطالب يقدر يشوف Attempts الخاصة بيه فقط
create policy "Students can view own attempts"
on public.attempts for select
using (student_id in (select id from public.students where auth_uid = auth.uid()));

-- 🚪 الجلسات:
-- الطالب يقدر ينشئ/يقرأ جلساته فقط
create policy "Students can manage own sessions"
on public.sessions for all
using (student_id in (select id from public.students where auth_uid = auth.uid()));

-- ✅ إرجاع محاولات طالب
create or replace function get_student_attempts(student_id_text text)
returns setof public.attempts
language sql as $$
  select *
  from public.attempts
  where student_id = student_id_text::uuid;
$$;

-- ✅ إضافة محاولة جديدة
create or replace function add_attempt(
  student_id_text text,
  question_id_text text,
  submitted_answer text,
  is_first boolean default false,
  revealed boolean default false
) returns public.attempts
language plpgsql as $$
declare
  q_correct text;
  tolerance double precision;
  q_type public.answer_type;
  correct boolean;
  new_attempt public.attempts;
begin
  -- هات بيانات السؤال
  select correct_answer, numeric_tolerance, answer_type
  into q_correct, tolerance, q_type
  from public.questions
  where id = question_id_text::uuid;

  -- تحقق من الإجابة
  if q_type = 'numeric' then
    correct := abs(submitted_answer::double precision - q_correct::double precision) <= tolerance;
  else
    correct := (upper(trim(submitted_answer)) = upper(trim(q_correct)));
  end if;

  -- أدخل المحاولة
  insert into public.attempts(student_id, question_id, submitted_answer, is_correct, is_first_attempt, revealed)
  values (student_id_text::uuid, question_id_text::uuid, submitted_answer, correct, is_first, revealed)
  returning * into new_attempt;

  return new_attempt;
end;
$$;

-- ✅ تفعيل أو تعطيل طالب
create or replace function toggle_student_activation(student_id_text text)
returns void
language sql as $$
  update public.students
  set activated = not activated
  where id = student_id_text::uuid;
$$;

-- ✅ تسجيل جلسة طالب (لمنع تعدد الأجهزة)
create or replace function register_session(student_id_text text, device_id text, session_token text)
returns public.sessions
language sql as $$
  insert into public.sessions(student_id, device_id, session_token, active)
  values (student_id_text::uuid, device_id, session_token, true)
  returning *;
$$;

-- ✅ إلغاء الجلسة
create or replace function end_session(session_token text)
returns void
language sql as $$
  update public.sessions
  set active = false
  where session_token = end_session.session_token;
$$;

-- الطلاب يقروا السيكشنز
create policy "Students view sections"
on public.sections
for select
using (true);

-- المدرس يدير كل السيكشنز
create policy "Admin full access to sections"
on public.sections
for all
using (auth.role() = 'service_role');

-- الطلاب يقروا فقط
create policy "Students can view questions"
on public.questions
for select
using (true);

-- المدرس يقدر يضيف ويعدل
create policy "Admin full access to questions"
on public.questions
for all
using (auth.role() = 'service_role');

-- الطلاب
alter table public.students enable row level security;

-- الأسئلة
alter table public.questions enable row level security;

-- المحاولات
alter table public.attempts enable row level security;

-- الجلسات
alter table public.sessions enable row level security;

-- السيكشنز
alter table public.sections enable row level security;

create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  question_id uuid references public.questions(id) on delete cascade,
  submitted_answer text,
  is_correct boolean,
  is_first_attempt boolean default false,
  revealed boolean default false,
  created_at timestamptz default now()
);

create or replace function public.get_report(
    report_type text,
    start_date timestamptz default null,
    end_date timestamptz default null
)
returns setof json
language plpgsql
as $$
begin
    if report_type = 'students' then
        return query
        select to_jsonb(t)
        from (
            select
              s.id as student_id,
              s.full_name,
              count(a.*) filter (where a.is_correct = true) as correct_count,
              count(a.*) filter (where a.is_correct = false) as wrong_count,
              count(a.*) as total_attempts,
              round(
                case when count(a.*)=0 then 0
                     else (100.0 * count(a.*) filter (where a.is_correct = true)::decimal / count(a.*)::decimal)
                end, 2
              ) as percent_correct
            from public.students s
            left join public.attempts a 
              on a.student_id = s.id
              and (start_date is null or a.created_at >= start_date)
              and (end_date is null or a.created_at <= end_date)
            group by s.id, s.full_name
        ) t;
        
    elsif report_type = 'questions' then
        return query
        select to_jsonb(t)
        from (
            select
              q.id as question_id,
              q.question_text,
              count(a.*) filter (where a.is_correct = true) as correct_count,
              count(a.*) filter (where a.is_correct = false) as wrong_count,
              count(a.*) as total_attempts
            from public.questions q
            left join public.attempts a
              on a.question_id = q.id
              and (start_date is null or a.created_at >= start_date)
              and (end_date is null or a.created_at <= end_date)
            group by q.id, q.question_text
        ) t;

    elsif report_type = 'sections' then
        return query
        select to_jsonb(t)
        from (
            select
              sec.id as section_id,
              sec.name,
              count(distinct q.id) as questions_count,
              count(a.*) as total_attempts
            from public.sections sec
            left join public.questions q on q.section_id = sec.id
            left join public.attempts a 
              on a.question_id = q.id
              and (start_date is null or a.created_at >= start_date)
              and (end_date is null or a.created_at <= end_date)
            group by sec.id, sec.name
        ) t;

    elsif report_type = 'global' then
        return query
        select to_jsonb(t)
        from (
            select
              count(distinct s.id) as students_count,
              count(distinct q.id) as questions_count,
              count(a.*) as total_attempts,
              round(
                case when count(a.*)=0 then 0
                     else (100.0 * count(a.*) filter (where a.is_correct = true)::decimal / count(a.*)::decimal)
                end, 2
              ) as percent_correct
            from public.students s
            left join public.attempts a 
              on a.student_id = s.id
              and (start_date is null or a.created_at >= start_date)
              and (end_date is null or a.created_at <= end_date)
            left join public.questions q on a.question_id = q.id
        ) t;
    end if;
end;
$$;

-- SQL to create the function in Supabase
CREATE OR REPLACE FUNCTION get_student_report(start_date_param text, end_date_param text)
RETURNS TABLE (
    student_id uuid,
    full_name text,
    correct_count bigint,
    wrong_count bigint,
    total_attempts bigint,
    percent_correct numeric
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
      s.id,
      s.full_name,
      count(a.*) FILTER (WHERE a.is_correct = true) AS correct_count,
      count(a.*) FILTER (WHERE a.is_correct = false) AS wrong_count,
      count(a.*) AS total_attempts,
      round(
        CASE WHEN count(a.*) = 0 THEN 0
             ELSE (100.0 * count(a.*) FILTER (WHERE a.is_correct = true)::decimal / count(a.*)::decimal)
        END, 2
      ) AS percent_correct
    FROM public.students s
    LEFT JOIN public.attempts a
      ON a.student_id = s.id
      AND (a.created_at >= COALESCE(start_date_param::timestamp, a.created_at))
      AND (a.created_at <= COALESCE(end_date_param::timestamp, a.created_at))
    GROUP BY s.id, s.full_name;
END;
$$;

-- إنشاء جدول Sections
create table public.sections (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,
    description text,
    created_at timestamptz default now()
);

-- تعديل جدول الأسئلة
alter table public.questions
add column section_id uuid references public.sections(id) on delete set null,
add column reveal_image_path text,
add column has_option_e boolean default false,
add column has_text_answer boolean default false;

-- جدول الـ Sections
create table public.sections (
    id uuid primary key default gen_random_uuid(),
    name text not null unique,           -- اسم الـ Section
    description text,                    -- وصف اختياري
    created_at timestamptz default now()
);

-- تعديل جدول الأسئلة لإضافة Section
alter table public.questions
add column section_id uuid references public.sections(id) on delete set null;

-- إنشاء الـ extension لو مش موجود
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- إنشاء جدول الطلاب
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    grade TEXT,
    email TEXT UNIQUE,
    activated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    grade TEXT,
    email TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 1. جدول المستخدمين (students)
create table public.students (
  id uuid primary key default gen_random_uuid(),
  auth_uid text unique,               -- id من Supabase Auth بعد الـ signup
  email text unique,
  full_name text,
  activated boolean default false,    -- المدرّس (أنت) يفعل الحساب
  created_at timestamptz default now()
);

-- 2. جدول الأسئلة
create type public.answer_type as enum ('mcq','numeric');

create table public.questions (
  id uuid primary key default gen_random_uuid(),
  image_path text,                     -- path داخل Supabase Storage
  thumbnail_path text,                 -- مصغرة مضغوطة
  question_text text,                  -- اختياري
  answer_type public.answer_type not null default 'mcq',
  correct_answer text not null,        -- 'A'/'B'/'C'/'D' أو '3.14'
  numeric_tolerance double precision default 0.01, -- tolerance للأجوبة الرقمية
  reveal_image_path text,              -- صورة خطوات الحل (تُعرض عند Reveal)
  created_by text,                     -- teacher id or email
  created_at timestamptz default now()
);

-- 3. محاولات الحل attempts
create table public.attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  question_id uuid references public.questions(id) on delete cascade,
  submitted_answer text,
  is_correct boolean,
  is_first_attempt boolean default false,
  revealed boolean default false,          -- هل الطالب استخدم reveal قبل/بعد الحل؟
  created_at timestamptz default now()
);

-- 4. جلسات الطلاب (enforce 1 session/device)
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete cascade,
  device_id text,               -- client يرسله (مثلاً fingerprint أو random id في localStorage)
  session_token text unique,
  active boolean default true,
  created_at timestamptz default now()
);

-- Helper view for progress (wrong only + percentage)
create view public.student_progress as
select
  s.id as student_id,
  s.email,
  count(a.*) filter (where a.is_correct = false) as wrong_count,
  count(a.*) as total_attempts,
  case when count(a.*)=0 then 0.0
       else round(100.0 * (1 - (count(a.*) filter (where a.is_correct = false)::decimal / count(a.*)::decimal)), 2)
  end as percent_correct
from public.students s
left join public.attempts a on a.student_id = s.id
group by s.id, s.email;


