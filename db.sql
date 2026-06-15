drop schema if exists meta cascade;
drop schema if exists data cascade;

create extension if not exists "uuid-ossp";
create schema "meta";
create schema "data";
-- МЕТАДАННЫЕ ---------------------------------------------------------------------------------------


create table meta."enum" (
	id serial not null primary key,
	parent_id integer null references meta."enum"(id) on delete cascade,
	"key" varchar(100) not null,
	"name" varchar(250) null,
	dd timestamp null
);
create unique index meta_enum_uk on meta.enum using btree (coalesce(parent_id, (0)::bigint), key);
comment on table meta."enum" is 'хранилище перечислений';

--- функции для работы с enum
create function meta.enum_id(enum_key varchar(100))
 returns integer
 language sql
 stable
as
$$
select id from meta.enum where parent_id is null and key = enum_key;
$$;
comment on function meta.enum_id(varchar) is 'Возвращает ID перечисления по ключу';


create function meta.enum_keys_to_ids(p_enum varchar(250), p_keys varchar(250)[])
returns integer[]
language sql
stable
as $$
select array_agg(v.id)
from meta.enum v
inner join meta.enum t on v.parent_id=t.id and t.parent_id is null and t."key"=p_enum
  and v.key = any(p_keys)
$$;
comment on function meta.enum_keys_to_ids(varchar(250), varchar(250)[]) is 'Преобразует массив ключей enum к массиву id в meta.enum';


create function meta.enmum_ids_to_keys(p_enum varchar(250), p_ids integer[])
returns varchar(250)[]
language sql
stable
as $$
select array_agg(v.key)
from meta.enum v
inner join meta.enum t on v.parent_id=t.id and t.parent_id is null and t."key"=p_enum
 and v.id=any(p_ids);
$$;
comment on function meta.enmum_ids_to_keys(varchar(250), integer[]) is 'Преобразует массив id enum к массиву ключей';


create function meta.enmum_ids_check(p_enum varchar(250), p_key varchar(250), p_ids integer[])
returns boolean
language plpgsql
as $$
begin
return exists(
     select 1
     from meta.enum v
     inner join meta.enum t on v.parent_id=t.id and t.parent_id is null and t."key" = p_enum
     and v.key=p_key
);
end
$$;
comment on function meta.enmum_ids_check(varchar(250), varchar(250), integer[]) is 'Проверяет есть ли в списке идентификатор указанного ключа';


create function meta.enmum_ids_set(p_enum varchar(250), p_key varchar(250), p_state boolean default true, p_ids integer[] default null)
returns integer[]
language plpgsql
as $$
declare
    p_key_id integer;
begin
    if p_ids is null then
        p_ids = '{}'::integer[];
    end if;

    select v.id into p_key_id
    from meta.enum v
    inner join meta.enum t on v.parent_id=t.id and t.parent_id is null and t."key" = p_enum and v.key = p_key;

    if p_state then
        p_ids = array_append(p_ids,p_key_id);
    elseif p_state = false and not(p_key_id = any(p_ids)) then
        p_ids = array_remove(p_ids, p_key_id);
    end if;

    return p_ids;
end
$$;
comment on function meta.enmum_ids_set(varchar(250), varchar(250), boolean, integer[]) is 'Добавляет или удаляет из списка идентификатор указанного ключа';


create function meta.enum_keys(p_enum varchar(250))
 returns varchar(250)[]
 language sql
 stable
as
$$
select array_agg(v.key order by v.key asc)
from meta.enum t
inner join meta.enum v on v.parent_id=t.id
where t.parent_id is null and t.key = p_enum;
$$;
comment on function meta.enum_keys(varchar) is 'Возврашает массив со всеми ключами перечисления';


insert into meta.enum("key", "name")
values
('data_type', 'Типы данных'),
('version_status','Статусы версии'),
('entity_type','Типы таблиц'),
('attr_flags','Флаги атрибутов')
;

create table meta.data_type ( like meta."enum" including indexes, check(parent_id =  meta.enum_id('data_type')) ) inherits (meta."enum");
alter table meta.data_type add column eav_field char(1) not null;
comment on column meta.data_type.eav_field is 'имя поля в таблице eav, где лежат данные этого типа';
alter table meta.data_type alter column parent_id set default meta.enum_id('data_type');

insert into meta.data_type("key","name","eav_field")
values
   ('R','Ссылка','r'),
   ('r','Связанная сылка','s'),
   ('M','Множество ссылок','s'),
   ('I','Целое','i'),
   ('F','Дробное число','f'),
   ('S','Строка','s'),
   ('G','Уникальный идентификатор','s'),
   ('T','Дата/Время','t'),
   ('B','Логическое значение','i'),
   ('E','Перечисление','s'),
   ('J','Json','s')
 ;


insert into meta.enum(key, name, parent_id)
select x.column1, x.column2, meta.enum_id('version_status')
from (values
  ('D', 'Черновик', 1),
  ('P', 'Опубликовано', 2),
  ('A', 'Актуально', 3),
  ('R', 'Архив', 4),
  ('L', 'Заблокировано', 5),
  ('C', 'Отклонено', 6)
) x
order by x.column3;


insert into meta.enum(key, name, parent_id)
select x.column1, x.column2, meta.enum_id('entity_type')
from (values
  ('EAV', 'Логическая таблица'),
  ('SYS', 'Системная таблица'), -- системные таблицы на которые нельзя ссылаться
  ('RSYS', 'Системная таблица со связями'), -- системные таблицы на которые можно ссылаться
  ('RVT', 'Таблица с версионированием каждой строки'),
  ('PGT', 'Таблица postgresql')
) x;


insert into meta.enum(key, name, parent_id)
select x.column1, x.column2, meta.enum_id('attr_flags')
from (values
  ('UQ', 'Уникальный'),
  ('NN', 'Не NULL'),
  ('RO', 'Только чтение')
) x;


create table meta.entity (
	id bigint not null primary key,
	guid uuid unique default uuid_generate_v4() not null,
	title varchar(250) null,
	f_read varchar(100),
	f_write varchar(100),
	entity_type varchar(5) not null default 'EAV'::char(3),
	constraint entity_type_check check(entity_type = any(meta.enum_keys('entity_type')))
);
comment on table meta.entity is 'список таблиц';
comment on column meta.entity.guid is 'глобальный идентификатор таблицы';
comment on column meta.entity.title is 'наименование таблицы для отображения';
comment on column meta.entity.f_read is 'метод чтения. если задан то нельзя менять структуру таблицы';
comment on column meta.entity.f_write is 'метод записи. Если пусто, но задан метод чтения, значит можно только читать данные';
comment on column meta.entity.entity_type is 'тип таблицы из enum entity_type';

create table meta.class (
    id bigserial not null primary key,
    parent_id bigint references meta.class,
    guid uuid unique default uuid_generate_v4() not null,
    title varchar(250) unique not null,
    store_entity_id bigint not null references meta.entity(id)
);
comment on table meta.class is 'классы (онтологии)';
comment on column meta.class.parent_id is 'ссылка на родительский класс ';
comment on column meta.class.guid is 'глобальный идентификатор класса';
comment on column meta.class.title is 'наименование класса для отображения';
comment on column meta.class.store_entity_id is 'таблица, в которой лежат данные класса (одна на всю иерархию)';

create table meta."version" (
	id bigserial not null primary key,
	guid uuid unique default uuid_generate_v4() not null,
	entity_id integer not null,
	parent_id integer null,
	dt timestamp default now() not null,
	npp smallint null,
	status char(1) not null default 'D'::char(1),
	constraint unique_npp unique (entity_id, npp),
	constraint version_npp_check check (npp > 0),
	constraint status_in_list check(status = any(meta.enum_keys('version_status')))
);
comment on table meta."version" is 'список версий таблиц';

comment on column meta."version".guid is 'глобальный идентификатор версии';
comment on column meta."version".dt is 'дата создания версии';
comment on column meta."version".npp is 'номер версии';

alter table meta.entity add column version_id bigint references meta.version(id) on delete set NULL;

create table meta."attribute" (
	id bigserial primary key,
	entity_id integer not null references meta.entity(id) on delete cascade,
	"name" varchar(100) not null,
	title varchar(250) not null,
	type_id integer null references meta.data_type(id),
	ref_attribute_id bigint references meta.attribute(id) on delete cascade,
	ref_enum_key varchar(100),
	flags integer[],
	constraint attribute_name_unique unique(entity_id,"name")
);


create table "data"."row" (
	id bigserial  primary key,
	entity_id integer references meta.entity(id) on delete cascade,
	guid uuid unique default uuid_generate_v4() not null,
	version_id bigint references meta.version(id) on delete cascade,
	class_id bigint references meta.class(id) on delete cascade
);


create function meta.field_list(f_params jsonb)
  returns jsonb
  language plpgsql
as $$
declare
 v_sheet record;
begin
/*
возвращает соотиветствующий заданным параметрам список полей и их свойств
на входе достаточно любого из следующих параметров:
{
  "guid": "идентификатор таблицы",
  "version_guid": "идентификатор версии",
  "сlass_guid": "идентификатор класса",
}
*/

   select
       e.id,
       coalesce(v.id, v1.id) as version_id,
       cl.id as class_id,
	   e.entity_type
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.class cl on cl.guid = (f_params->>'сlass_guid')::uuid
   left join meta.entity e on e.version_id = v.id
   			or (v.id is null and e.id = cl.store_entity_id)
   			or (v.id is null and cl.id is null and e.guid = (f_params->>'guid')::uuid)
   left join meta.version v1 on v1.entity_id = e.id and v1.id = coalesce(v.id, e.version_id);

   return jsonb_build_object('columns',(
	 select array_to_json(array_agg(row_to_json(x))) from (
	   select * from meta.attribute a where a.entity_id = v_sheet.id
	 ) x),
	 'has_refs', exists(select 1 from meta.attribute a
					   inner join meta.data_type t on t.id = a.type_id and t.key in ('R','M','E')
					   where a.entity_id=v_sheet.id)
   );

end
$$;


create function meta.enum_get(f_params jsonb)
 returns jsonb
 language plpgsql
as $$
declare
    p_id integer;
begin
    if f_params ? 'key' then
        select e.id into p_id
        from meta.enum e
        where e.key=f_params ->> 'key' and e.parent_id is null and e.dd is Null;
        if p_id is Null then
            return jsonb_build_object('error',format('Не найдено перечисление %s',(f_params ->> 'key')));
        end if;

        return (select array_to_json(array_agg(row_to_json(x)))::jsonb from (
          select e."key", e."name" from meta.enum e where e.parent_id = p_id and e.dd is Null
        ) x);
    end if;

    return (select array_to_json(array_agg(row_to_json(x)))::jsonb from (
      select e."key", e."name" from meta.enum e where e.parent_id is Null and e.dd is Null
    ) x);
end
$$;

create function meta.sheet_set(f_params jsonb)
 returns jsonb
 language plpgsql
as $$
declare
    v_sheet record;
    v_column record;
    v_ret json;
    v_force boolean;
begin
    if coalesce(f_params::varchar,'{}')='{}' then
        return jsonb_build_object('error', 'структура таблицы не задана');
    end if;

    v_force = coalesce((f_params ->> 'force')::boolean,false);

    select
        e.id,
        (e.id is null) is_new,
        coalesce((f_params->>'guid')::uuid, e.guid, uuid_generate_v4()) guid,
        coalesce(f_params->>'title', e.title, '') title,
        coalesce(v.id, e.version_id) from_version_id,
        (e.id is null) or (coalesce((f_params->>'up_version')='true', false)) up_version,
        case when f_params ? 'read_method'  and v_force then f_params->>'read_method' else e.f_read end f_read,
        case when f_params ? 'write_method' and v_force then f_params->>'write_method' else e.f_write end f_write,
        e.version_id,
        e.f_read is not null custom_read,
        coalesce(e.entity_type, f_params->>'entity_type', 'EAV') entity_type
    into v_sheet
    from (select 1) fake
    left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
    left join meta.entity e on e.version_id = v.id or (v.id is null and e.guid = (f_params->>'guid')::uuid);

    if v_sheet.id is null then
        insert into data."row"(guid, entity_id)
        values (v_sheet.guid, (select id
        from meta.entity where guid = uuid_nil()))
        returning id into v_sheet.id;

        insert into meta.entity(id, guid, title, f_read, f_write, entity_type)
        values (v_sheet.id, v_sheet.guid, v_sheet.title, v_sheet.f_read, v_sheet.f_write, v_sheet.entity_type);
    else
        update meta.entity set
         title = v_sheet.title,
         f_read= v_sheet.f_read,
         f_write=v_sheet.f_write,
         entity_type = v_sheet.entity_type
        where id = v_sheet.id;
    end if;

    if v_sheet.custom_read and (f_params->>'columns') is not Null and not v_force then
         return jsonb_buildobject('error',format('Запрещены изменения структуры таблицы %s', e.title));
    end if;

    if v_sheet.up_version and v_sheet.entity_type in ('SYS','PGT','RSYS') then
        insert into meta.version(guid, entity_id)
        values (uuid_generate_v4(), v_sheet.id)
        returning id into v_sheet.version_id;

        update meta.entity
        set version_id = v_sheet.version_id
        where id = v_sheet.id;

    elsif v_sheet.is_new and v_sheet.entity_type='RVT' then
        execute 'create table data.rvt_'||v_sheet.id::varchar||' ( like data.rvt including indexes, check(entity_id = '||
                    v_sheet.id::varchar||') ) inherits (data.rvt)';
    elseif v_sheet.up_version then
        v_ret = data.sheet_set(jsonb_build_object(
          'guid', v_sheet.guid,
          'version_guid', (f_params->>'version_guid'),
          'up_version', true)
        );
        if (v_ret->>'error') is not null then
            return ret;
        end if;
        select version_id
        into v_sheet.version_id
        from meta.entity where id = v_sheet.id;
    end if;

    for v_column in
        select
            a.id,
            coalesce(attr->>'name', a.name) "name",
            coalesce(t.id, a.type_id) type_id,
            coalesce(attr->>'title', a.title) title,
            coalesce(attr.value ->>'reference', (attr.value ->>'reference_guid')::uuid::varchar) ref_guid,
            coalesce(attr.value ->>'reference_column', (('{'||replace(replace(attr.value ->>'reference_names', '[', ''), ']', '')||'}')::varchar[])[1]) ref_names,
            null::bigint ref_attribute_id,
            t.key type_key,
            attr.value defs,
            a.flags
        from jsonb_array_elements(f_params->'columns') attr
        left join meta.attribute a on a.entity_id = v_sheet.id and a.name = attr.value ->> 'name'
        left join meta.data_type t on t.key = attr.value ->> 'type'
    loop
        if v_column.type_key in ('R','M') then
             select a.id into v_column.ref_attribute_id
             from meta.attribute a
             inner join meta.entity e on e.guid = v_column.ref_guid::uuid and  a.entity_id = e.id and a.name = v_column.ref_names;

             if v_column.ref_attribute_id is null then
                return jsonb_build_object('error', format('Не найден ссылочный атрибут %s для поля %s', v_column.ref_names, v_column.name));
             end if;
        elseif v_column.type_key = 'r' then
             select a.id into v_column.ref_attribute_id
             from meta.attribute a
             where a.entity_id = v_sheet.id and a.name = v_column.ref_guid;

             if v_column.ref_attribute_id is null then
                return jsonb_build_object('error', format('В таблице нет ссылочного атрибута %s', v_column.ref_guid));
             end if;

             if not exists(select 1
                  from meta.attribute st
                  inner join meta.attribute et on et.id = st.ref_attribute_id
                  inner join meta.attribute tt on tt.entity_id = et.entity_id
                  where st.id = v_column.ref_attribute_id and tt.name = v_column.ref_names)
             then
                  return jsonb_build_object('error', format('В таблице по ссылке нет атрибута %s', v_column.ref_names));
             end if;

             v_column.ref_guid = v_column.ref_names;
        elseif v_column.type_key = 'E' then
             if not exists(select 1 from meta.enum where parent_id is null and "key"=v_column.ref_guid) then
                return jsonb_build_object('error',format('Не найден перечислимый тип %s', v_column.ref_guid));
             end if;
        end if;

        v_column.flags = meta.enmum_ids_set('attr_flags','UQ', (v_column.defs->>'is_unique')::boolean,
                         meta.enmum_ids_set('attr_flags','NN', not((v_column.defs->>'is_nullable')::boolean),
                         meta.enmum_ids_set('attr_flags','RO', not((v_column.defs->>'is_editable')::boolean),
        v_column.flags)));

        if v_column.id is null then
            insert into meta.attribute(entity_id, name, title, type_id, ref_attribute_id, ref_enum_key, flags)
            values (v_sheet.id, v_column.name, coalesce(v_column.title, v_column.name),
                    v_column.type_id, v_column.ref_attribute_id, v_column.ref_guid, v_column.flags);
        else
            update meta.attribute set
                title = v_column.title
            where id = v_column.id;
        end if;
    end loop;

    return (
        select jsonb_build_object(
           'guid', e.guid,
           'version_guid', v.guid
        )
        from meta.entity e
        left join meta.version v on v.id = v_sheet.version_id
        where e.id = v_sheet.id
    );
end;
$$;


create function meta.sheet_get(f_params jsonb)
 returns jsonb
 language plpgsql
as $$
declare
   v_sheet record;
   v_ret jsonb;
begin
   select
       coalesce(v1.entity_id, e.id) id,
       v1.id version_id,
       v1.status
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on  e.guid = (f_params->>'guid')::uuid
   left join meta.version v1 on v1.id = coalesce(v.id, e.version_id);

   if v_sheet.id is Null then
      return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   end if;

   return (select jsonb_build_object(
            'guid', e.guid,
            'title', e.title,
            'columns', (select jsonb_agg(x.defs) from (
                 select jsonb_build_object(
                      'name', c."name",
                      'title',c.title,
                      'type', t.key
                 )||case when t.key in ('E','R','M')
				 	then jsonb_build_object(
				 	    'reference',c.ref_enum_key,
				 	    'reference_guid',c.ref_enum_key -- старый вариант. удалить !!
				 	)
					else jsonb_build_object()
				 end||case when t.key in ('R','M')
				 	then jsonb_build_object(
				 	    'reference_column',a.name,
				 	    'reference_names',a.name -- старый вариант. удалить !!
				 	)
					else jsonb_build_object()
				 end||case when t.key = 'r'
                    then jsonb_build_object(
                        'reference',a.name,
                        'reference_column', c.ref_enum_key
                    )
                    else jsonb_build_object()
                 end
				 defs
                 from meta.attribute c
                 inner join meta.data_type t on t.id = c.type_id
				 left join meta.attribute a on a.id = c.ref_attribute_id
                 where c.entity_id=e.id
                 ) x)
        )
        from meta.entity e
        where e.id = v_sheet.id
   );
end;
$$;


create function meta.sheet_list(f_params jsonb default null)
 returns jsonb
 language plpgsql
as $$
begin
 return jsonb_build_object('guid', uuid_nil(), 'rows',
    (select array_to_json(array_agg(
        jsonb_build_object(
             'guid',x.guid,
             'data', jsonb_build_object(
                  'name', x."name",
                  'version_guid', x.version_guid,
                  'create_date', x.create_date,
                  'last_date', x.last_date
             )
        )
    ))::jsonb from (
        select
          e.guid,
          v.guid version_guid,
          e.title "name",
          ver.create_date,
          ver.last_date
        from meta.entity e
        inner join (
          select v.entity_id id, min(v.dt) create_date, max(v.dt) last_date
          from meta.version v
          group by v.entity_id
        ) ver on ver.id = e.id
        left join meta.version v on v.id = e.version_id
    ) x));
end
$$;

select meta.sheet_set('
{
    "guid": "00000000-0000-0000-0000-000000000000",
    "title": "Таблицы",
    "force": true,
    "entity_type": "RSYS",
    "read_method": "meta.sheet_list",
    "columns": [
      {
        "name": "name",
        "is_editable":false,
        "title":"Наименование таблицы",
        "type": "S"
      },
      {
        "name": "version_guid",
        "is_editable":false,
        "title":"Идентипфикатор версии",
        "type": "G"
      },
      {
        "name": "create_date",
        "is_editable":false,
        "title":"Дата создания",
        "type": "T"
      },
      {
        "name": "last_date",
        "is_editable":false,
        "title":"Дата модификации",
        "type": "T"
      }
    ]
}
');

update data."row" as r set
    entity_id=m.id
    --,version_id=m.verson_id
from meta.entity m
where m.guid=uuid_nil() and r.guid = uuid_nil();

alter table data."row" alter column entity_id set NOT NUll;

-- ДАННЫЕ -----------------------------------------------------------------------------------------

create table "data".eav (
	id bigint not null references data.row(id) on delete cascade,
	version_id bigint not null references meta.version(id),
	attribute_id bigint not null references meta.attribute(id) on delete cascade,
	s text null,
	i bigint null,
	f double precision null,
	t timestamp null,
	r bigint references data.row(id) on delete cascade,
	constraint eav_pk primary key (id, version_id, attribute_id)
);
comment on table data.eav is 'базовая таблица EAV';

-- триггеры для партиций eav
create function data.eav_insert()
 returns trigger
 language plpgsql
 security definer
as $$
begin
    execute format(
      'insert into data.eav_%s values ($1.*)',
      new.version_id
    ) using new;
    return null;
end
$$;

create function data.eav_update()
 returns trigger
 language plpgsql
 security definer
as $$
begin
    execute format(
      $q$update data.eav_%I set s=%L, i=%L::bigint, f=%L::double precision, r=%L::bigint, t=%L::timestamp where id=%I and attribute_id=%I$q$,
      new.version_id,
      new.s, new.i, new.f, new.r, new.t,
      new.id, new.attribute_id
    );
    return null;
end
$$;

create trigger eav_insert_trigger before
insert on data.eav for each row execute
!!..9.6!! procedure data.eav_insert();
!!10..!!  function data.eav_insert();

create trigger eav_update_trigger before
update on data.eav for each row execute
!!..9.6!! procedure data.eav_update();
!!10..!!  function data.eav_update();


create table data.rvt(
  id bigint not null references data.row(id),
  entity_id bigint not null references meta.entity(id),
  version_id bigint not null references meta.version(id) on delete cascade,
  row_data jsonb,
  refs jsonb,
  constraint rvt_pk primary key (id, entity_id, version_id)
);
comment on table data.rvt is 'базовая таблица с версионированием каждой строки';

-- триггеры для партиций rvt
create function data.rvt_insert()
 returns trigger
 language plpgsql
 security definer
as $$
begin
    execute format(
      'insert into data.rvt_%s values ($1.*)',
      new.entity_id
    ) using new;
    return null;
end
$$;

create function data.rvt_update()
 returns trigger
 language plpgsql
 security definer
as $$
begin
    execute format(
      $q$update data.rvt_%I set row_data=%L::jsonb, refs=%L::jsonb where id=%I and version_id=%I$q$,
      new.entity_id,
      new.row_data,
      new.refs,
      new.id,
      new.verion_id
    );
    return null;
end
$$;

create trigger rvt_insert_trigger before
insert on data.rvt for each row execute
!!..9.6!! procedure data.rvt_insert();
!!10..!!  function data.rvt_insert();

create trigger rvt_update_trigger before
update on data.rvt for each row execute
!!..9.6!! procedure data.rvt_update();
!!10..!!  function data.rvt_update();

---------------------------------------------------------------------------

create or replace function data.value_check(f_params jsonb)
returns jsonb
language plpgsql
as $$
declare
 fld_def record;
 tmp_rec record;
 ret jsonb;
begin
 /*
  Проверка значения атрибута
  на вход:
  {
  	"guid": "идентификатор таблицы",
	"column_name": "имя поля",
	"column_id": "идентификатор поля (для проверки на уникальность нужно передать column_id или guid+column_name)",

	"value": "значение",

	"type": "тип значения. если задан этот атрибут или атрибуты ниже, то свойства полшя беруться из них",
	"referencе": "guid таблицы для типов R, M или имя enum для типа Е",
	"is_unique": "если True - проверить на уникальность. По умолчанию:False",
	"is_nullable": "если True - проверить что не Null"
  }

  на выходе:
  {
  	  "type": "тип значения",
	  "value": "преобразованое значение",
	  "error":"текст ошибки при проверке либо атрибут отсутствует при успешном завершении"
  }
  */

  if coalesce(f_params->>'type', f_params->>'referencе', f_params->>'is_unique', f_params->>'is_nullable') is not null then
  	select null::bigint id,
		'' "name",
		coalesce((f_params->>'is_unique')::boolean, false) is_unique,
		coalesce((f_params->>'is_nullable')::boolean, true) is_nullable,
		(f_params->>'type') "type",
		(f_params->>'referencе') "referencе",
		null::bigint referencе_id
	into fld_def;
  elseif ((f_params->>'column_id') is not null)or((f_params->>'guid') is not null and (f_params->>'column_name') is not null) then
  	select a.id,
		a."name",
		meta.enmum_ids_check('attr_flags', 'UQ', a.flags) is_unique,
		not meta.enmum_ids_check('attr_flags', 'NN', a.flags) is_nullable,
		t.key "type",
		case
			when t.key in ('R', 'M') then er.guid::varchar
			when t.key = 'E' then a.ref_enum_key
			else null
		end "referencе",
		case
			when t.key in ('R', 'M') then er.id
			else null
		end "referencе_id"
	into fld_def
	from meta.attribute a
	inner join meta.entity e on e.id = a.entity_id
	inner join meta.data_type t on t.id = a.type_id
	left join meta.attribute r on r.id = a.ref_attribute_id
	left join meta.entity er on er.id = r.entity_id
	where a.id = (f_params->>'column_id')::bigint or (
	  (f_params->>'column_id') is null and
	  e.guid = (f_params->>'guid')::uuid and
	  a.name = (f_params->>'column_name')
	);
  else
  	return jsonb_build_object('error', 'Атрибут не определен [при проверке значения]');
  end if;

  /*if fld_def."type" is null then
  	return jsonb_build_object('error', format('Тип атрибута %s не определен [при проверке значения]',fld_def.name));
  end if;*/

  if (f_params->>'value') is null then
    if fld_def.is_nullable then
  		return jsonb_build_object('value', null, 'type', fld_def."type");
	else
		return jsonb_build_object('error', format('Значение атрибута %s не может быть NULL [при проверке значения]',fld_def.name));
	end if;
  end if;

  if fld_def."type" = 'R' then
	select r.id::varchar as id into tmp_rec
	from data.row r
	inner join meta.entity t on t.id = r.entity_id and t.guid = (f_params->>'referencе')::uuid
	where r.entity_id=v_row.ref_entity_id and r.guid = (f_params->>'value')::uuid;
	if tmp_rec.id is Null then
		return jsonb_build_object('error', format('Для поля %s не найдена строка по ссылке %s', fld_def.name, (f_params->>'value')));
	end if;
	return jsonb_build_object('value', f_params->>'value', 'reference_id', tmp_rec.id, 'type', fld_def."type");
  elseif fld_def."type" = 'M' then
    select count(*) cnt, sum(case when x.value is null then 0 else 1 end) chk, array_agg(r.guid)::varchar val, array_agg(r.id) ids
	into tmp_rec
	from jsonb_array_elements_text(f_params->'value') x
	inner join meta.entity t on t.guid = (f_params->>'referencе')::uuid
	left join data.row r on r.guid=x.value::uuid and t.id = r.entity_id;
	if coalesce(tmp_rec.cnt,0::bigint)!=coalesce(tmp_rec.chk,0::bigint) then
		return jsonb_build_object('error', format('Для поля %s не удалось найти все записи из %s', fld_def.name, (f_params->>'value')));
	end if;
	if tmp_rec.cnt = 0 then
		return jsonb_build_object('value',NULL, 'type', fld_def."type");
	else
		return jsonb_build_object('value',tmp_rec.val, 'reference_ids', tmp_rec.ids, 'type', fld_def."type");
	end if;
  elseif fld_def."type" = 'E' then
    select e.id, e.key val into tmp_rec
	from meta.enum t
	inner join meta.enum e on e.parent_id = t.id and t.parent_id is null and t.key=(f_params->>'referencе') and e.key=(f_params->>'value');
	if tmp_rec.id is null then
		return jsonb_build_object('error', format('Для поля %s не найдено значение %s перечисления %s', fld_def.name, (f_params->>'value'), (f_params->>'referencе')));
	end if;
	return jsonb_build_object('value',tmp_rec.val, 'reference_id', tmp_rec.id, 'type', fld_def."type");
  else begin
	ret = case
	  when (f_params->>'value') is null then null
	  when fld_def."type" = 'I' then jsonb_build_object('value', (f_params->>'value')::bigint)
	  when fld_def."type" = 'F' then jsonb_build_object('value', (f_params->>'value')::double precision)
	  when fld_def."type" = 'S' then jsonb_build_object('value', f_params->>'value')
	  when fld_def."type" = 'B' and upper(f_params->>'value') in ('TRUE','ДА','YES','Y','1','T','Д') then jsonb_build_object('value',1)
	  when fld_def."type" = 'B' then jsonb_build_object('value',0)
	  when fld_def."type" = 'G' then jsonb_build_object('value', (f_params->>'value')::uuid)
	  else jsonb_build_object()
	end;
  exception
  	when others then
		return jsonb_build_object('error', format('Ошибка проеобразования типа атрибута %s для значения %s [при проверке значения]',fld_def.name, f_params->>'value'));
  end; end if;

  return ret||jsonb_build_object('type', fld_def."type");
end
$$;

create function data.sheet_set(f_params jsonb)
  returns jsonb
  language plpgsql
as $$
declare
   v_sheet record;
   v_counters record;
   v_row record;
   tmp_row_guid varchar = '';
   tmp_row_id bigint;
   tmp_value varchar;
   tmp_rec record;
begin
   select
       0::bigint "input",
       0::bigint "deleted",
       0::bigint "updated",
       0::bigint "inserted"
   into v_counters;

   select
       e.id,
       coalesce(v.id, v1.id) as version_id,
       coalesce(v.id, v1.id) as from_version_id,
       coalesce(v.status, v1.status) as version_staus,
       (v.id is not null) version_exists,
       coalesce(e.guid, uuid_generate_v4()) guid,
       coalesce(v.guid, uuid_generate_v4()) version_guid,
       coalesce(f_params->>'title', e.title) title,
       e.entity_type
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on e.version_id = v.id or (v.id is null and e.guid = (f_params->>'guid')::uuid)
   left join meta.version v1 on v1.entity_id = e.id and v1.id = coalesce(v.id, e.version_id);

   if v_sheet.id is Null then
        return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   end if;

   if v_sheet.entity_type='RVT' then
        f_params = f_params || jsonb_build_object('_SYS_INFO_', row_to_json(v_sheet));
        return data.sheet_set_rvt(f_params);
   end if;

   if v_sheet.version_id is Null or coalesce((f_params->>'up_version')='true', false) or v_sheet.version_staus != 'D' then
        insert into meta.version(guid, entity_id, parent_id) values (v_sheet.version_guid, v_sheet.id, v_sheet.version_id)
        returning id into v_sheet.version_id;

        execute 'create table data.eav_'||v_sheet.version_id::varchar||' ( like data.eav including indexes, check(version_id = '||
            v_sheet.version_id::varchar||') ) inherits (data.eav)';

        if v_sheet.version_exists then
            insert into data.eav(id, version_id, attribute_id, s, i, f, t)
            select  d.id, v_sheet.version_id, d.attribute_id, d.s, d.i, d.f, d.t
            from data.eav d
            where d.version_id = v_sheet.from_version_id;
        end if;

        update meta.entity set version_id = v_sheet.version_id where id = v_sheet.id;
   end if;

   for v_row in
        select
            rows.guid::varchar guid,   -- guid строки
            db_rows.id,  -- id строки, если она уже есть
            rows.to_delete, -- признак удаления строки
            col.id attribute_id,-- идентификатор поля
            col.name,  -- имя поля
            dt.key type_code,   -- тип поля
            dt.eav_field,  -- поле где данное значение лежит в eav
            dat.value,
            (dea.id is NUll) new_attr,
            col.ref_attribute_id,
            ra_col.entity_id ref_entity_id
        from (
            select coalesce((x.value->>'guid')::uuid, uuid_generate_v4()) guid,
                   (x.value->'data') "data",
                   (x.value->>'delete')::boolean to_delete
            from jsonb_array_elements(f_params->'rows') x
        ) rows
        left join jsonb_each_text(rows.data) dat on true
        left join data.row db_rows on db_rows.guid = rows.guid and db_rows.entity_id = v_sheet.id
        left join meta.attribute col on col.entity_id = v_sheet.id and col.name = dat.key
        left join meta.attribute ra_col on ra_col.id = col.ref_attribute_Id
        left join meta.data_type dt on dt.id = col.type_id
        left join data.eav dea on dea.version_id=v_sheet.version_id and dea.id=db_rows.id and dea.attribute_id=col.id
   loop
        if v_row.guid != tmp_row_guid then
            tmp_row_guid = v_row.guid;
            v_counters.input=v_counters.input + 1;
            if v_row.to_delete then
                delete from data.eav where version_id=v_sheet.version_id and id=v_row.id;
                v_counters.deleted = v_counters.deleted + 1;
                continue;
            elseif v_row.id is null then
                insert into data.row(entity_id, guid)
                values (v_sheet.id, v_row.guid::uuid)
                returning id into tmp_row_id;
                v_counters.inserted=v_counters.inserted + 1;
            else
                tmp_row_id = v_row.id;
                v_counters.updated=v_counters.updated + 1;
            end if;
        elseif v_row.to_delete then
            continue;
        end if;

        if v_row.type_code = 'B' then
            v_row.value = case when upper(v_row.value) in ('TRUE','ДА','YES','Y','1','T','Д') then '1' else '0' end;
        elseif v_row.type_code = 'G' then
            v_row.value = (v_row.value::uuid)::varchar;
        elseif v_row.type_code = 'R' then
            tmp_value = null;
            select r.id::varchar into tmp_value
            from data.row r
            where r.entity_id=v_row.ref_entity_id and r.guid = v_row.value::uuid;
            if tmp_value is Null then
               return jsonb_build_object('error', format('Для поля %s не найдена строка по ссылке %s', v_row.name, v_row.value));
            end if;
            v_row.value = tmp_value;
        elseif v_row.type_code = 'M' then
            select count(*) cnt, sum(case when x.value is null then 0 else 1 end) chk, array_agg(r.guid)::varchar val
            into tmp_rec
            from jsonb_array_elements_text(v_row.value::jsonb) x
            left join data.row r on r.guid=x.value::uuid;
            if coalesce(tmp_rec.cnt,0::bigint)!=coalesce(tmp_rec.chk,0::bigint) then
                return jsonb_build_object('error', format('Для поля %s не удалось найти все записи из %s', v_row.name, v_row.value));
            end if;
            if tmp_rec.cnt = 0 then
                v_row.value = NULL;
            else
                v_row.value = tmp_rec.val;
            end if;
        elseif v_row.type_code = 'r' then
            --return jsonb_build_object('error', format('Запись в составные ссылочные поля запрещена (%s)', v_row.name));
            continue;
        end if;

        if v_row.new_attr then
             insert into data.eav(id, version_id, attribute_id, s, i, f, r, t)
             values(
                 tmp_row_id,
                 v_sheet.version_id,
                 v_row.attribute_id,
                 case when v_row.value is NULL or v_row.eav_field!='s' then NULL else v_row.value::text end,
                 case when v_row.value is NULL or v_row.eav_field!='i' then NULL else v_row.value::bigint end,
                 case when v_row.value is NULL or v_row.eav_field!='f' then NULL else v_row.value::double precision end,
                 case when v_row.value is NULL or v_row.eav_field!='r' then NULL else v_row.value::bigint end,
                 case when v_row.value is NULL or v_row.eav_field!='t' then NULL else v_row.value::timestamp end
             );
        else
             update data.eav set
                s = case when v_row.value is NULL or v_row.eav_field!='s' then NULL else v_row.value::text end,
                i = case when v_row.value is NULL or v_row.eav_field!='i' then NULL else v_row.value::bigint end,
                f = case when v_row.value is NULL or v_row.eav_field!='f' then NULL else v_row.value::double precision end,
                r = case when v_row.value is NULL or v_row.eav_field!='r' then NULL else v_row.value::bigint end,
                t = case when v_row.value is NULL or v_row.eav_field!='t' then NULL else v_row.value::timestamp end
             where
                version_id = v_sheet.version_id and
                id = tmp_row_id and
                attribute_id = v_row.attribute_id;
        end if;
   end loop;

   return row_to_json(v_counters)::jsonb;
end;
$$;


create function data.sheet_set_rvt(f_params jsonb)
returns jsonb
language plpgsql
as $$
declare
   v_row record;
   v_sheet record;
   v_counters record;
   v_cols jsonb;
   v_def record;
   v_changed bool;
   v_val jsonb;
begin
    if f_params->>'_SYS_INFO_' is null then
        return jsonb_build_object('Функция sheet_set_rvt не предназначена для самостоятельного вызова');
    end if;
    select
         (f_params->'_SYS_INFO_'->>'id')::bigint id,
         (f_params->'_SYS_INFO_'->>'version_id')::bigint version_id,
         (f_params->'_SYS_INFO_'->>'version_staus') version_staus,
         (f_params->'_SYS_INFO_'->>'version_exists')::boolean version_exists,
         (f_params->'_SYS_INFO_'->>'guid')::uuid guid,
         (f_params->'_SYS_INFO_'->>'version_guid')::uuid version_guid,
         (f_params->'_SYS_INFO_'->>'title') title,
         (f_params->'_SYS_INFO_'->>'entity_type') entity_type
    into v_sheet;

	select
       0::bigint "input",
       0::bigint "deleted",
       0::bigint "updated",
       0::bigint "inserted"
    into v_counters;

	v_cols = meta.field_list(jsonb_build_object('guid', v_sheet.guid));

	for v_row in
		select
			coalesce(j.guid, uuid_generate_v4()) guid,
			r.id,
			rv.guid version_guid,
			rv.id version_id,
			coalesce(rv.status,'--') status,
			coalesce(
			  (v.id = r.version_id),
			  (v.entity_id = r.entity_id and v.entity_id = v_sheet.id), (v.entity_id = v_sheet.id), true
			) ver_is_correct,
			j.to_delete,
			cl.guid class_guid,
			cl.id class_id,
			(lv.id is not NULL) is_locked,
			coalesce(rvt.row_data, jsonb_build_object()) row_data,
			j."data" new_data
		from (
		  select
		     (x.value->>'guid')::uuid guid,
		     (x.value->>'class_guid')::uuid class_guid,
			 (x.value->>'version_guid')::uuid version_guid,
			 (x.value->'data') "data",
			 coalesce((x.value->>'delete')::boolean, false) to_delete
		  from jsonb_array_elements(f_params->'rows') x
		) j
		left join meta.version v on v.guid = j.version_guid
		left join data.row r on r.entity_id = v_sheet.id and (r.version_id=v.id or (v.id is null and r.guid = j.guid))
		left join meta.class cl on cl.id = r.class_id or (r.id is null and cl.guid = j.class_guid)
		left join meta.version rv on rv.id = coalesce(v.id, r.version_id)
		left join meta.version lv on lv.id = r.id and lv.status in ('L','C')
		left join data.rvt rvt on rvt.id = r.id and rvt.entity_id = v_sheet.id and rvt.version_id = rv.id
    loop
        v_counters.input = v_counters.input + 1;
		if not v_row.ver_is_correct then
			return jsonb_build_object('error', format('Версия %s не соответствует строке %s', v_row.version_guid, v_row.guid));
		end if;
		if v_row.is_locked then
			return jsonb_build_object('error', format('Строка %s заблокирована на запись', v_row.guid));
		end if;
		if v_row.class_guid is not null then
			v_cols = meta.field_list(jsonb_build_object('class_guid', v_row.class_guid));
		end if;

	    v_changed = false;
		for v_def in
			select v.value->>'name' fld_name, t.key type_key, d.value, a.ref_enum_key
            from jsonb_array_elements(v_cols->'columns') v
            inner join meta.data_type t on t.id = (v.value->'type_id')::bigint
            inner join jsonb_each_text(v_row.new_data) d on d.key = v.value->>'name'
			left join meta.attribute a on a.entity_id = v_sheet.id and a."name"=d.key

		loop
            v_changed = true;

            v_val = data.value_check(jsonb_build_object(
              'type', v_def.type_key,
              'value', v_def.value,
              'referencе', v_def.ref_enum_key,
              'is_unique', coalesce((f_params->>'is_unique')::boolean, false),
              'is_nullable', coalesce((f_params->>'is_nullable')::boolean, true),
              'guid', v_sheet.guid,
              'column_id', a.id
            ));

            if (v_val->>'error') is not null then
                return jsonb_build_object('error', v_val->>'error');
            end if;

            v_row.row_data = v_row.row_data||jsonb_build_object(v_def.fld_name, v_val->'value');
		end loop;

		if v_changed then
		    if status = 'D' then
		        v_counters.updated = v_counters.updated + 1;
		        update data.rvt
		        set row_data=v_row.row_data
		        where id = v_row.id and versioin_id=v_row.vesion_id and entity_id=v_sheet.id;
		    else
		        v_counters.inserted = v_counters.inserted+1;
		        insert into meta.version(entity_id, parent_id)
		        values(v_sheet.id, v_sheet.version_id)
		        returning id into v_row.version_id;

		        insert into data.row(class_id, entity_id, guud, version_id)
		        select v_row.class_id,v_sheet.id, v_row.guud, v_row.version_id
		        returning id into v_row.id;

		        insert into data.rvt(id, entity_id, version_id,row_data)
		        values(v_row.id, v_sheet.id, v_row.version_id, v_row.row_data);
		    end if;
		end if;
	end loop;

    return row_to_json(v_counters)::jsonb;
end
$$;


create function data.filter(f_version_id bigint, f_params jsonb)
returns table(id bigint, npp integer)
language plpgsql
as $$
declare
   v_query text = '';
   v_limits text;
   v_version record;
begin
   select v.id, v.entity_id
   into v_version
   from meta.version v
   where v.id = f_version_id;

   v_limits = case
      when (f_params->>'limit') is null
      then ''
      else ' limit '||((f_params->>'limit')::int)::varchar
   end || case
      when (f_params->>'offset') is null
      then ''
      else ' offset '||((f_params->>'offset')::int)::varchar
   end;

   if (f_params->>'filter') is null and (f_params->>'order') is null then
        --- без фильтра и сортировки, только limit и offest
        v_query = format($q$select x.id, row_number() over (order by x.id)::integer npp
             from (select t.id from data.eav_%s t group by id order by t.id
             %s) x$q$, v_version.id, v_limits);
   elseif (f_params->>'filter') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        --- выбор одной строки. limit и offest игнорируем
        v_query = format($q$select x.id, 1::integer npp from data.row x where x.guid=%L::uuid$q$, f_params->>'filter');
   end if;

   return query execute v_query;
end
$$;


create function data.ref_vals(f_version_id bigint)
returns table(row_id bigint, attr_id bigint, "value" jsonb)
language plpgsql
as $$
declare
    v_query text = 'select null::bigint row_id, null::bigint attr_id, null::jsonb "value" where 1<>1';
    v_attr record;
begin
   /*
   Из таблицы, заданной версией f_version_id берем все параметры типа r
   и строим для них запрос на извлечение данных из связанной таблицы
   в конце выполняем получившийся запрос
   */
   for v_attr in
      select r.id out_attr_id, r.ref_enum_key attr_name, e.guid, a.id sel_attr_id
        from meta.version v
        inner join meta.attribute r on r.entity_id = v.entity_id
        inner join meta.data_type t on t.key = 'r' and t.id = r.type_id
        inner join meta.attribute a on a.id = r.ref_attribute_id
        inner join meta.attribute ea on ea.id = a.ref_attribute_id
        inner join meta.entity e on e.id = ea.entity_id
        where v.id = f_version_id
   loop
      v_query = format($q$%s union all
        select ev.id row_id, %s attr_id, v.value->'data'->'%s' "value"
        from jsonb_array_elements(data.sheet_get('{"guid":"%s","fields":["%s"]}')->'rows') v
        inner join data.row w on w.guid = (v.value->>'guid')::uuid
        inner join data.eav_%s ev on ev.r = w.id and ev.attribute_id = %s
      $q$, v_query, v_attr.out_attr_id, v_attr.attr_name, v_attr.guid, v_attr.attr_name, f_version_id, v_attr.sel_attr_id);
   end loop;

   return query execute v_query;
end
$$;


create function data.sheet_get(f_params jsonb)
returns jsonb
language plpgsql
as $$
declare
   v_sheet record;
   v_ret jsonb;
   t_tmp text;
   v_fields varchar(100)[];
begin
   if f_params is null or f_params::varchar='{}'  then
      f_params = jsonb_build_object('guid', uuid_nil());
   end if;

   select
       e1.id,
       e1.guid,
       v1.id version_id,
       v1.guid version_guid,
       v1.status,
       e1.f_read,
	   e1.entity_type
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on  e.guid = (f_params->>'guid')::uuid
   left join meta.version v1 on v1.id = coalesce(v.id, e.version_id)
   left join meta.entity e1 on e1.id=coalesce(v1.entity_id, e.id);


   if v_sheet.id is Null then
        -- таблица не найдена
        return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   elseif v_sheet.f_read is not Null then
   		-- для таблицы задана функция чтения
        t_tmp = format($q$select %s('%s')$q$, v_sheet.f_read,f_params);
        execute t_tmp into v_ret;
   elseif v_sheet.entity_type='EAV' then
   	   	-- это EAV таблица
	   	if (f_params->>'fields') is not null then
		  select array_agg(elem::varchar)
		  into v_fields
		  from jsonb_array_elements_text(f_params->'fields') AS elem;
	   	end if;

	   	with refs as (
		   select a.id, (array_agg(vto.id order by e.id))[1] version_id, dto.eav_field, dto."key"
			   from meta.attribute a
			   inner join meta.data_type dt on a.type_id = dt.id and dt.key in ('R', 'M')
			   inner join meta.attribute ato on ato.id = a.ref_attribute_id
			   inner join meta.data_type dto on dto.id = ato.type_id
			   inner join meta.entity eto on eto.id=ato.entity_id
			   inner join meta.version vto on vto.entity_id = eto.id and (v_sheet.status != 'D' or eto.version_id is null or vto.id = eto.version_id)
			   inner join meta.enum e on  e.key = vto.status
			   where e.parent_id = meta.enum_id('version_status') and a.entity_id = v_sheet.id
			   group by a.id, dto.eav_field, dto."key"
		   union all
		   select a.id, e.id version_id, null, null
			   from meta.attribute a
			   inner join meta.data_type dt on a.type_id = dt.id and dt.key = 'E'
			   inner join meta.enum e on e.parent_id is null and e.key = a.ref_enum_key
	   	)

		 select jsonb_agg(jsonb_strip_nulls(
		   jsonb_build_object('guid', x.guid, 'data', x.data, 'references', x.refs, 'class', x.class_guid)
		 ))
		 into v_ret
		 from (
		 select r.guid,
		   jsonb_object_agg(atr.name,
		   case
			   when dt.key='E' then to_jsonb(enm.name)
			   when dt.key='B' then to_jsonb(eav.i=1)
			   when dt.eav_field='i' then to_jsonb(eav.i)
			   when dt.eav_field='f' then to_jsonb(eav.f)
			   when dt.eav_field='t' then to_jsonb(eav.t)
			   when dt.key ='R' and refs.eav_field='s' then to_jsonb(reav.s)
			   when dt.key ='R' and refs.key='B' then to_jsonb(reav.i=1)
			   when dt.key ='R' and refs.eav_field='i' then to_jsonb(reav.i)
			   when dt.key ='R' and refs.eav_field='f' then to_jsonb(reav.f)
			   when dt.key ='R' and refs.eav_field='t' then to_jsonb(reav.t)
			   when dt.key ='M' then to_jsonb((
				   select array_agg(
					   case
						 when refs.eav_field='s' then me.s
						 when refs.eav_field='i' then me.i::text
						 when refs.eav_field='f' then me.f::text
						 when refs.eav_field='t' then me.t::text
					   end
				   )
				   from data.row mr
				   inner join data.eav me on me.id=mr.id
					   and me.version_id = refs.version_id
					   and me.attribute_id = atr.ref_attribute_id
				   where mr.guid = any(eav.s::uuid[])
			   )) -- M
			   when dt.key ='r' then rv.value
			   else to_jsonb(eav.s)
		   end
		   ) "data",
		   nullif(jsonb_strip_nulls(jsonb_object_agg(atr.name,
		   case
			 when dt.key ='R' then to_jsonb(geav.guid)
			 when dt.key ='E' then to_jsonb(enm.key)
			 when dt.key ='M' then to_jsonb(array_to_json(eav.s::uuid[]))
		   end
		   )), '{}'::jsonb) refs,
		   cla.guid class_guid
		  from meta.version v
		  inner join meta.attribute atr on atr.entity_id = v.entity_id
		  inner join meta.data_type dt on dt.id = atr.type_id
		  inner join data.row r on r.entity_id = v.entity_id
		  inner join data.filter(v.id, f_params) fltr on fltr.id = r.id
		  left join  data.eav eav on eav.attribute_id = atr.id and eav.id = r.id and eav.version_id = v.id
		  left join  data.ref_vals(v.id) rv on dt.key ='r' and rv.row_id = r.id and rv.attr_id = atr.id
		  left join  refs on refs.id = atr.id
		  left join  data.eav reav on dt.key in ('R','M') and reav.version_id = refs.version_id and reav.attribute_id=atr.ref_attribute_id and reav.id = eav.r
		  left join  data.row geav on geav.id = reav.id
		  left join  meta.enum enm on dt.key = 'E' and enm.parent_id = refs.version_id and enm.key = eav.s
		  left join  meta.class cla on cla.id = r.class_id
		  where v.id = v_sheet.version_id and (v_fields is null or atr."name" = any(v_fields))
		  group by r.guid, fltr.npp
		  order by fltr.npp
		 ) x;
   elseif v_sheet.entity_type='RVT' then
   		-- это таблица с отдельным версионированием строк
		select jsonb_agg(jsonb_strip_nulls(
		  	jsonb_build_object('guid', r.guid, 'class', cla.guid, 'version', v.guid, 'data', rvt.row_data)
		))
		into v_ret
		from data.row r
		inner join data.rvt rvt on rvt.entity_id = v_sheet.id and rvt.id = r.id
		inner join (
		  select max(rv.version_id) version_id, rv.id
		  from data.rvt rv
		  where rv.entity_id = v_sheet.id and (v_sheet.version_id is null or rv.version_id <= v_sheet.version_id)
		  group by rv.id
		) ver on rvt.version_id = ver.version_id and ver.id = r.id
		inner join meta.version v on v.id = ver.version_id
		left join  meta.class cla on cla.id = r.class_id
		where r.entity_id = v_sheet.id;
   else
   		return jsonb_build_object('error','Неподдерживаемый тип таблицы');
   end if;

   return jsonb_build_object('guid', v_sheet.guid, 'version_guid', v_sheet.version_guid, 'rows', v_ret);
end
$$;

