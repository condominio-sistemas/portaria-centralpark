-- =====================================================================
-- Controle de Encomendas — Condomínio Central Park
-- Estrutura do banco (Supabase). Rodar UMA vez no SQL Editor do projeto.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- Porteiros (usuários do sistema). O login é feito por nome de usuário;
-- o e-mail no Supabase Auth é interno e fictício (usuario@DOMINIO).
-- ---------------------------------------------------------------------
create table public.porteiros (
  id         uuid primary key references auth.users(id) on delete cascade,
  usuario    text not null unique,
  nome       text not null,
  papel      text not null default 'porteiro' check (papel in ('porteiro','admin')),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

create or replace function public.eh_porteiro() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.porteiros where id = auth.uid() and ativo);
$$;

create or replace function public.eh_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.porteiros where id = auth.uid() and ativo and papel = 'admin');
$$;

alter table public.porteiros enable row level security;
create policy porteiros_ler on public.porteiros for select to authenticated
  using (public.eh_porteiro() or id = auth.uid());
create policy porteiros_criar on public.porteiros for insert to authenticated
  with check (public.eh_admin());
create policy porteiros_alterar on public.porteiros for update to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

-- ---------------------------------------------------------------------
-- Moradores
-- ---------------------------------------------------------------------
create table public.moradores (
  id         uuid primary key default gen_random_uuid(),
  apto       text not null,
  nome       text,
  telefone   text,
  criado_em  timestamptz not null default now(),
  criado_por uuid references public.porteiros(id) default auth.uid()
);

alter table public.moradores enable row level security;
create policy moradores_ler     on public.moradores for select to authenticated using (public.eh_porteiro());
create policy moradores_criar   on public.moradores for insert to authenticated with check (public.eh_porteiro());
create policy moradores_alterar on public.moradores for update to authenticated using (public.eh_porteiro()) with check (public.eh_porteiro());
create policy moradores_excluir on public.moradores for delete to authenticated using (public.eh_porteiro());

-- ---------------------------------------------------------------------
-- Encomendas (exclusão é lógica, para manter o registro de quem excluiu)
-- ---------------------------------------------------------------------
create table public.encomendas (
  id               uuid primary key default gen_random_uuid(),
  apto             text not null,
  morador          text,
  transportadora   text,
  data_chegada     date not null default current_date,
  telefone         text,
  observacao       text,
  foto_path        text,
  foto_origem      text,          -- 'computador' | 'celular' | 'legado'
  foto_enviada_em  timestamptz,
  foto_enviada_por uuid references public.porteiros(id),
  status           text not null default 'pendente' check (status in ('pendente','entregue')),
  cadastrado_em    timestamptz not null default now(),
  cadastrado_por   uuid references public.porteiros(id),
  entregue_em      timestamptz,
  entregue_por     uuid references public.porteiros(id),
  retirado_por     text,
  excluido_em      timestamptz,
  excluido_por     uuid references public.porteiros(id),
  legado_id        text unique    -- id da versão local (importação de backup)
);
create index encomendas_status_idx on public.encomendas (status) where excluido_em is null;
create index encomendas_apto_idx   on public.encomendas (apto);

alter table public.encomendas enable row level security;
create policy encomendas_ler     on public.encomendas for select to authenticated using (public.eh_porteiro());
create policy encomendas_criar   on public.encomendas for insert to authenticated with check (public.eh_porteiro());
create policy encomendas_alterar on public.encomendas for update to authenticated using (public.eh_porteiro()) with check (public.eh_porteiro());
-- sem política de DELETE: ninguém apaga de verdade pelo sistema

-- Autoria e datas são definidas pelo banco (não dá para forjar pelo navegador)
create or replace function public.encomendas_antes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.legado_id is not null then
      -- importação do backup da versão local: só administrador; autoria antiga não existe
      if not public.eh_admin() then raise exception 'Somente administradores podem importar backup'; end if;
      new.cadastrado_por   := null;
      new.entregue_por     := null;
      new.foto_enviada_por := null;
    else
      new.cadastrado_por := auth.uid();
      new.cadastrado_em  := now();
      new.status         := 'pendente';
      new.entregue_em    := null;
      new.entregue_por   := null;
      if new.foto_path is not null then
        new.foto_enviada_por := auth.uid();
        new.foto_enviada_em  := now();
        new.foto_origem      := 'computador';
      end if;
    end if;
    new.excluido_em  := null;
    new.excluido_por := null;
    return new;
  end if;

  -- UPDATE: campos de criação são imutáveis
  new.cadastrado_por := old.cadastrado_por;
  new.cadastrado_em  := old.cadastrado_em;
  new.legado_id      := old.legado_id;

  if new.status = 'entregue' and old.status <> 'entregue' then
    new.entregue_em  := now();
    new.entregue_por := auth.uid();
  elsif new.status = 'pendente' and old.status = 'entregue' then
    new.entregue_em  := null;
    new.entregue_por := null;
    new.retirado_por := null;
  else
    new.entregue_em  := old.entregue_em;
    new.entregue_por := old.entregue_por;
  end if;

  if new.foto_path is distinct from old.foto_path then
    if new.foto_path is null then
      new.foto_enviada_em  := null;
      new.foto_enviada_por := null;
      new.foto_origem      := null;
    elsif auth.uid() is not null then
      new.foto_enviada_em  := now();
      new.foto_enviada_por := auth.uid();
      new.foto_origem      := 'computador';
    else
      -- envio pelo celular (função registrar_foto_celular): autor já vem preenchido
      new.foto_enviada_em  := now();
    end if;
  else
    new.foto_enviada_em  := old.foto_enviada_em;
    new.foto_enviada_por := old.foto_enviada_por;
    new.foto_origem      := old.foto_origem;
  end if;

  if new.excluido_em is not null and old.excluido_em is null then
    new.excluido_em  := now();
    new.excluido_por := auth.uid();
  elsif old.excluido_em is not null then
    new.excluido_em  := old.excluido_em;
    new.excluido_por := old.excluido_por;
  end if;

  return new;
end $$;

create trigger encomendas_antes before insert or update on public.encomendas
  for each row execute function public.encomendas_antes();

-- ---------------------------------------------------------------------
-- Histórico de ações (quem fez o quê e quando)
-- ---------------------------------------------------------------------
create table public.eventos (
  id           bigint generated always as identity primary key,
  encomenda_id uuid references public.encomendas(id) on delete cascade,
  acao         text not null,
  porteiro_id  uuid references public.porteiros(id),
  em           timestamptz not null default now(),
  detalhes     jsonb
);
create index eventos_encomenda_idx on public.eventos (encomenda_id);

alter table public.eventos enable row level security;
create policy eventos_ler on public.eventos for select to authenticated using (public.eh_porteiro());

create or replace function public.encomendas_depois() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.eventos (encomenda_id, acao, porteiro_id)
    values (new.id, case when new.legado_id is null then 'cadastro' else 'importacao' end, auth.uid());
    return null;
  end if;

  if new.status = 'entregue' and old.status <> 'entregue' then
    insert into public.eventos (encomenda_id, acao, porteiro_id, detalhes)
    values (new.id, 'baixa', auth.uid(), jsonb_build_object('retirado_por', new.retirado_por));
  elsif new.status = 'pendente' and old.status = 'entregue' then
    insert into public.eventos (encomenda_id, acao, porteiro_id) values (new.id, 'reabertura', auth.uid());
  end if;

  if new.foto_path is distinct from old.foto_path then
    insert into public.eventos (encomenda_id, acao, porteiro_id)
    values (new.id,
            case when new.foto_path is null then 'foto_removida'
                 when old.foto_path is null then 'foto_' || coalesce(new.foto_origem, 'computador')
                 else 'foto_trocada_' || coalesce(new.foto_origem, 'computador') end,
            coalesce(auth.uid(), new.foto_enviada_por));
  end if;

  if new.telefone is distinct from old.telefone then
    insert into public.eventos (encomenda_id, acao, porteiro_id) values (new.id, 'telefone_alterado', auth.uid());
  end if;

  if new.excluido_em is not null and old.excluido_em is null then
    insert into public.eventos (encomenda_id, acao, porteiro_id) values (new.id, 'exclusao', auth.uid());
  end if;
  return null;
end $$;

create trigger encomendas_depois after insert or update on public.encomendas
  for each row execute function public.encomendas_depois();

-- ---------------------------------------------------------------------
-- Turnos (entrada e saída de cada porteiro)
-- ---------------------------------------------------------------------
create table public.turnos (
  id                        uuid primary key default gen_random_uuid(),
  porteiro_id               uuid not null references public.porteiros(id),
  inicio                    timestamptz not null default now(),
  fim                       timestamptz,
  ultima_atividade          timestamptz not null default now(),
  encerrado_automaticamente boolean not null default false,
  dispositivo               text
);
create index turnos_inicio_idx on public.turnos (inicio desc);

alter table public.turnos enable row level security;
create policy turnos_ler on public.turnos for select to authenticated
  using (porteiro_id = auth.uid() or public.eh_admin());
-- gravação só pelas funções abaixo (horários definidos pelo servidor)

create or replace function public.iniciar_turno(p_dispositivo text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.eh_porteiro() then raise exception 'Sem acesso'; end if;
  -- fecha turnos deste porteiro que ficaram abertos (navegador fechado sem encerrar)
  update public.turnos set fim = ultima_atividade, encerrado_automaticamente = true
   where porteiro_id = auth.uid() and fim is null;
  insert into public.turnos (porteiro_id, dispositivo) values (auth.uid(), left(p_dispositivo, 200))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.pulsar_turno(p_turno uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.turnos set ultima_atividade = now()
   where id = p_turno and porteiro_id = auth.uid() and fim is null;
  return found;
end $$;

create or replace function public.encerrar_turno(p_turno uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.turnos set fim = now(), ultima_atividade = now()
   where id = p_turno and porteiro_id = auth.uid() and fim is null;
end $$;

-- ---------------------------------------------------------------------
-- Foto pelo celular (QR code): token de uso único, válido por 15 minutos
-- ---------------------------------------------------------------------
create table public.foto_tokens (
  token        uuid primary key default gen_random_uuid(),
  encomenda_id uuid not null references public.encomendas(id) on delete cascade,
  criado_por   uuid not null references public.porteiros(id),
  criado_em    timestamptz not null default now(),
  expira_em    timestamptz not null default now() + interval '15 minutes',
  usado_em     timestamptz
);
alter table public.foto_tokens enable row level security;
-- sem políticas: acesso só pelas funções abaixo

create or replace function public.gerar_token_foto(p_encomenda uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_token uuid;
begin
  if not public.eh_porteiro() then raise exception 'Sem acesso'; end if;
  if not exists (select 1 from public.encomendas where id = p_encomenda and excluido_em is null) then
    raise exception 'Encomenda não encontrada';
  end if;
  delete from public.foto_tokens where expira_em < now() - interval '1 day';
  insert into public.foto_tokens (encomenda_id, criado_por) values (p_encomenda, auth.uid())
  returning token into v_token;
  return v_token;
end $$;

create or replace function public.token_foto_valido(p_token uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.foto_tokens
                  where token = p_token and usado_em is null and expira_em > now());
$$;

create or replace function public.info_token_foto(p_token uuid)
returns table (apto text, morador text, valido boolean, expira_em timestamptz)
language sql stable security definer set search_path = public as $$
  select e.apto, e.morador, (t.usado_em is null and t.expira_em > now()), t.expira_em
    from public.foto_tokens t join public.encomendas e on e.id = t.encomenda_id
   where t.token = p_token and e.excluido_em is null;
$$;

create or replace function public.registrar_foto_celular(p_token uuid, p_caminho text) returns void
language plpgsql security definer set search_path = public as $$
declare v_tk public.foto_tokens%rowtype;
begin
  select * into v_tk from public.foto_tokens where token = p_token for update;
  if not found or v_tk.usado_em is not null or v_tk.expira_em <= now() then
    raise exception 'QR code expirado ou já utilizado. Gere um novo no computador da portaria.';
  end if;
  if p_caminho not like 'celular/' || p_token::text || '/%' then
    raise exception 'Caminho de foto inválido';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'fotos' and name = p_caminho) then
    raise exception 'Foto não encontrada no armazenamento';
  end if;
  update public.encomendas
     set foto_path = p_caminho, foto_enviada_por = v_tk.criado_por, foto_origem = 'celular'
   where id = v_tk.encomenda_id;
  update public.foto_tokens set usado_em = now() where token = p_token;
end $$;

-- ---------------------------------------------------------------------
-- Administração: redefinir senha de um porteiro
-- ---------------------------------------------------------------------
create or replace function public.admin_redefinir_senha(p_porteiro uuid, p_senha text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.eh_admin() then raise exception 'Somente administradores'; end if;
  if length(coalesce(p_senha, '')) < 6 then raise exception 'A senha precisa ter pelo menos 6 caracteres'; end if;
  if not exists (select 1 from public.porteiros where id = p_porteiro) then raise exception 'Usuário não encontrado'; end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_senha, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_porteiro;
end $$;

-- ---------------------------------------------------------------------
-- Permissões das funções (por padrão o Postgres libera para todos)
-- ---------------------------------------------------------------------
revoke execute on function public.iniciar_turno(text), public.pulsar_turno(uuid), public.encerrar_turno(uuid),
  public.gerar_token_foto(uuid), public.token_foto_valido(uuid), public.info_token_foto(uuid),
  public.registrar_foto_celular(uuid, text), public.admin_redefinir_senha(uuid, text),
  public.eh_porteiro(), public.eh_admin()
  from public, anon;

grant execute on function public.eh_porteiro(), public.eh_admin(),
  public.iniciar_turno(text), public.pulsar_turno(uuid), public.encerrar_turno(uuid),
  public.gerar_token_foto(uuid), public.admin_redefinir_senha(uuid, text)
  to authenticated;

-- usadas pela página do celular (sem login)
grant execute on function public.token_foto_valido(uuid), public.info_token_foto(uuid),
  public.registrar_foto_celular(uuid, text)
  to anon, authenticated;


-- ---------------------------------------------------------------------
-- Armazenamento das fotos (bucket privado)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy fotos_porteiro_ler on storage.objects for select to authenticated
  using (bucket_id = 'fotos' and public.eh_porteiro());
create policy fotos_porteiro_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and public.eh_porteiro());
create policy fotos_porteiro_alterar on storage.objects for update to authenticated
  using (bucket_id = 'fotos' and public.eh_porteiro());
create policy fotos_porteiro_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and public.eh_porteiro());

-- celular sem login: só pode ENVIAR, só na pasta do próprio token válido
create policy fotos_celular_enviar on storage.objects for insert to anon
  with check (
    bucket_id = 'fotos'
    and (storage.foldername(name))[1] = 'celular'
    and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
    and public.token_foto_valido(((storage.foldername(name))[2])::uuid)
  );

-- ---------------------------------------------------------------------
-- Atualização em tempo real (foto do celular aparece sozinha no computador)
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table public.encomendas, public.moradores;
