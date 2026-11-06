-- 선생님 감시 화면 + 허락 1시간 자동 꺼짐
-- Supabase 대시보드 > SQL Editor 에 붙여 넣고 Run 한 번만 누르면 돼요. (여러 번 실행해도 괜찮아요)
-- 비밀번호는 바꿀 필요 없어요. (기존 선생님 비밀번호를 그대로 써요)

-- 1) 허락한 시각을 기록해서, 1시간이 지나면 학생 화면에서 저절로 꺼진 것으로 봐요
alter table public.omok_players add column if not exists approved_at timestamptz;
update public.omok_players set approved_at = now() where approved and approved_at is null;

create or replace function public.omok_set_approval(p_pin text, p_nums text[], p_approved boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from omok_secret where pin = p_pin) then
    raise exception 'wrong pin';
  end if;
  insert into omok_players(num, approved, approved_at, updated_at)
    select unnest(p_nums), p_approved, case when p_approved then now() end, now()
  on conflict (num) do update
    set approved = excluded.approved, approved_at = excluded.approved_at, updated_at = now();
end $$;

-- 2) 학생이 게임에 들어오면 남기는 기록 (선생님 비밀번호로만 읽을 수 있어요)
create table if not exists public.game_log (
  id    bigserial primary key,
  num   text not null,                 -- "4201"
  game  text not null,                 -- teeball
  event text not null,                 -- open / create / join / start / denied
  room  text,
  at    timestamptz not null default now()
);
alter table public.game_log enable row level security;   -- 정책이 없어서 밖에서 바로 읽거나 쓸 수 없어요
create index if not exists game_log_at_idx on public.game_log (at desc);

create or replace function public.game_log_add(p_num text, p_game text, p_event text, p_room text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_num !~ '^[1-6][1-9][0-9]{2}$' or p_game !~ '^[a-z]{2,12}$' or p_event !~ '^[a-z]{2,12}$' then
    return;
  end if;
  insert into game_log(num, game, event, room)
  values (p_num, p_game, p_event, nullif(left(coalesce(p_room, ''), 8), ''));
  delete from game_log where at < now() - interval '30 days';   -- 30일 지난 기록은 지워요
end $$;

create or replace function public.game_log_list(p_pin text, p_prefix text, p_since timestamptz)
returns setof public.game_log language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from omok_secret where pin = p_pin) then
    raise exception 'wrong pin';
  end if;
  return query
    select * from game_log
    where num like coalesce(p_prefix, '') || '%'
      and at >= coalesce(p_since, now() - interval '1 day')
    order by id desc
    limit 300;
end $$;

grant execute on function public.game_log_add(text, text, text, text) to anon, authenticated;
grant execute on function public.game_log_list(text, text, timestamptz) to anon, authenticated;
