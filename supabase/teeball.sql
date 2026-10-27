-- 우리 반 티볼: 진도 저장용 표와 저장 함수
-- Supabase 대시보드 > SQL Editor 에 붙여 넣고 Run 한 번만 누르면 돼요. (여러 번 실행해도 괜찮아요)

create table if not exists public.teeball_progress (
  num        text        not null,          -- "4201" (학년·반·번호)
  lesson     text        not null,          -- 단계 id (field, inning, ...)
  stars      int         not null default 1 check (stars between 1 and 3),
  updated_at timestamptz not null default now(),
  primary key (num, lesson)
);

alter table public.teeball_progress enable row level security;

drop policy if exists "teeball_progress read" on public.teeball_progress;
create policy "teeball_progress read" on public.teeball_progress
  for select to anon, authenticated using (true);

-- 학생 화면은 이 함수로만 저장해요 (별은 더 많을 때만 올라가요)
create or replace function public.teeball_save(p_num text, p_lesson text, p_stars int)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_num !~ '^\d{4}$' or p_lesson !~ '^[a-z]{2,20}$' or p_stars not between 1 and 3 then
    raise exception 'invalid input';
  end if;
  insert into public.teeball_progress (num, lesson, stars, updated_at)
  values (p_num, p_lesson, p_stars, now())
  on conflict (num, lesson) do update
    set stars = greatest(public.teeball_progress.stars, excluded.stars),
        updated_at = now();
end;
$$;

revoke all on function public.teeball_save(text, text, int) from public;
grant execute on function public.teeball_save(text, text, int) to anon, authenticated;
