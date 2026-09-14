drop schema if exists auth cascade;

create table auth.realm(
  id bigserial primary key,
  "name" varchar(100) unique not null,
  "description" text,
  "lock" boolean not null default true
);

comment on table auth.realm is 'область/домен';
comment on column  auth.realm.name is 'имя домена';
comment on column  auth.realm.description is 'описание';
comment on column  auth.realm.lock is 'признак блокировки. по умолчанию весь домен заблокирован';


create table auth.login_suffix(
  id bigserial primary key,
  "name" varchar(100) unique not null,
  "description" text
);

comment on table auth.login_suffix is 'суффикс для разделения учетных записей. например, в ivan/admin@CORP.LOCAL суффикс это admin';


create table auth."user"(
  id bigserial primary key,
  "login" varchar(100) unique not null,
  "login_name" varchar(100),
  "user_name" varchar(100),
  realm_id bigint references auth.realm(id),
  suffix_id bigint references auth.login_suffix(id),
  "lock" boolean not null default true
);

comment on table auth.user is 'списорк пользователей';
comment on column  auth.user.login is 'полный логин с суфиксом и доменом';
comment on column  auth.user.login_name is 'логин без суфикса и домена';
comment on column  auth.user.user_name is 'имя пользователя для отображения (из LDAP)';
comment on column  auth.user.realm_id is 'домен (для управления доменом целиком)';
comment on column  auth.user.suffix_id is 'суффикс (для сортировки поиска и отчетов)';

create table auth."role"(
  id bigserial primary key,
  parent_id bigint references auth."role"(id),
  "name" varchar(100) not null,
  constraint role_uk unique (parent_id, "name")
);

do $$
declare
  chk bigint;
begin
  insert into auth."role"("name")
  values('Роль')
  returning id
  into chk;
  
  if chk!=1 then
  	raise exception 'Скрипт необходимо накатывать на чистую БД';
  end if;
  
  update auth."role" set 
  	parent_id = 1
  where id = 1;
  
  alter table auth."role" alter column parent_id set not null;
end $$;

comment on table auth.role is 'дерево ролей. корень с id=1 нельзя удалять';
comment on column  auth.role.parent_id is 'родительская роль';
comment on column  auth.role.name is 'имя роли';

create table auth.user_role(
  user_id bigint not null references auth.user(id),
  role_id bigint not null references auth.role(id),
  constraint user_role_pk primary key (user_id, role_id)
);

comment on table auth.role is 'обеспечивает назначение ролей пользователям';