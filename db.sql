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


create function meta.enmum_ids_check(p_enum character varying, p_key character varying, p_ids integer[])
 RETURNS boolean
 LANGUAGE plpgsql
AS $meta_enmum_ids_check__2026_07_07$
begin
return exists(
     select 1
     from meta.enum v
     inner join meta.enum t on v.parent_id=t.id and t.parent_id is null and t."key" = p_enum
     and v.key=p_key and v.id = any(p_ids)
);
end
$meta_enmum_ids_check__2026_07_07$;
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
   ('H','Версионированная ссылка','s'),
   --('h','Версионированная связанная сылка','s'),
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
  ('VER', 'Логическая таблица c версионированием'),
  ('EAV', 'Логическая таблица без версионирования'),
  ('SYS', 'Системная таблица'), --нельзя ссылаться -/- любаая системная таблица имеет свои методы для чтения/записи
  ('RSYS', 'Системная таблица со связями'),   -----/   как минимум для чтения. если таблица со связями, то онра должна иметь запись в data.row
  ('RVT', 'Таблица с версионированием каждой строки'),
  ('PHYS', 'Таблица postgresql')
) x;


insert into meta.enum(key, name, parent_id)
select x.column1, x.column2, meta.enum_id('attr_flags')
from (values
  ('UQ', 'Уникальный'),
  ('NN', 'Не NULL'),
  ('RO', 'Только чтение'),
  ('PK', 'Ключ физ.таблицы')
) x;


create table meta.entity (
	id bigint not null primary key,
	guid uuid unique default uuid_generate_v4() not null,
	title varchar(250) null,
	f_read varchar(100),
	f_write varchar(100),
	entity_type varchar(5) not null default 'VER'::char(3),
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
    entity_id bigint not null references meta.entity(id)
);
comment on table meta.class is 'классы (онтологии)';
comment on column meta.class.parent_id is 'ссылка на родительский класс ';
comment on column meta.class.guid is 'глобальный идентификатор класса';
comment on column meta.class.title is 'наименование класса для отображения';
comment on column meta.class.entity_id is 'таблица, в которой лежат данные класса (одна на всю иерархию)';

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
	npp integer,
	"name" varchar(100) not null,
	title varchar(250) not null,
	type_id integer null references meta.data_type(id),
	ref_attribute_id bigint references meta.attribute(id) on delete cascade,
	ref_enum_key varchar(100),
	flags integer[],
	constraint attribute_name_unique unique(entity_id,"name")
);
comment on column meta."attribute".entity_id is 'ссылка на таблицу к которой относится атрибут';
comment on column meta."attribute".npp is 'порядковый номер в таблице. если не задан, то определяется по id';
comment on column meta."attribute"."name" is 'имя атрибута, уникальное в пределах таблицы';

create table "data"."row" (
	id bigserial  primary key,
	entity_id integer references meta.entity(id) on delete cascade,
	guid uuid unique default uuid_generate_v4() not null,
	version_id bigint references meta.version(id) on delete cascade,
	class_id bigint references meta.class(id) on delete cascade
);


create view meta.pg_table as (
    with pt as (
      select x.oid, x.t_name "name", (left(x.h1,8)||'-'||right(h1,4)||'-4321-ab'||left(x.h2,2)||'-'||right(x.h2,12))::uuid guid
      from (
      select c.oid::bigint, n.nspname||'.'||c.relname t_name, lpad(to_hex(hashtext(n.nspname::varchar)),12,'0') h1, rpad(to_hex(hashtext(c.relname)),14,'0') h2
      from pg_catalog.pg_class c
      inner join pg_catalog.pg_namespace n on c.relnamespace = n.oid
      where relkind='r'
      ) x
    )

    select pt.guid, pt.oid, pt.name, r.id, a.name key_name, ta."key" "key_type"
    from pt
    inner join meta.entity t on t.guid = uuid_nil()
    inner join meta.enum epkt on epkt.parent_id is null and epkt.key = 'attr_flags'
    inner join meta.enum epk on epk.parent_id = epkt.id and epk.key = 'PK'
    left join data.row r on r.entity_id = t.id and r.guid = pt.guid
    left join meta.attribute a on a.entity_id = r.id and epk.id =any(a.flags)
    left join meta.data_type ta on ta.id = a.type_id
    order by pt.name
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
   			or (v.id is null and e.id = cl.entity_id)
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
 RETURNS jsonb
 LANGUAGE plpgsql
AS $meta_sheet_set__2026_07_16$
declare
    v_sheet record;
    v_column record;
    v_ret json;
    v_force boolean;
	v_tmp varchar;
begin
    if coalesce(f_params::varchar,'{}')='{}' then
        return jsonb_build_object('error', 'структура таблицы не задана');
    end if;

    v_force = coalesce((f_params ->> 'force')::boolean,false);

	if exists(select 1 from meta.pg_table t where t.guid = (f_params->>'guid')::uuid) then
		f_params = f_params || jsonb_build_object('entity_type', 'PHYS');
	end if;

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
        coalesce(e.entity_type, f_params->>'entity_type', 'VER') entity_type
    into v_sheet
    from (select 1) fake
    left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
    left join meta.entity e on e.version_id = v.id or (v.id is null and e.guid = (f_params->>'guid')::uuid);

    if v_sheet.custom_read and (f_params->>'columns') is not Null and not v_force then
         return jsonb_build_object('error',format('Запрещены изменения структуры таблицы %s', e.title));
    end if;

	if coalesce((f_params->>'delete')::boolean, false) then
		if not v_force then
			v_force = exists(
			  	select 1
				from meta.attribute a1
				inner join meta.attribute a2 on a1.ref_attribute_id = a2.id and a2.entity_id = v_sheet.id
			);
			/*
			сюда добавить проверку наличия ссылки на таблицу внутри другой таблицы, в том числе RVT (паспорта)
			*/
			if v_force then
				return jsonb_build_object('error', 'Таблица не может быть удалена т.к. на неё есть ссылки');
			end if;
		end if;
		if v_sheet.entity_type = 'RVT' then
			v_tmp = format('drop table data.rvt_%s', v_sheet.id);
			execute v_tmp;
		elseif v_sheet.entity_type in ('VER', 'EAV') then
			for v_tmp in
				select format('drop table if exists data.eav_%s',v.id)
				from meta.version v
				where v.entity_id = v_sheet.id
			loop
				execute v_tmp;
			end loop;
		elseif v_sheet.entity_type = 'PHYS' then
			v_sheet.entity_type = 'PHYS';
		else
			select e.name
			into v_tmp
			from meta.enum t
			inner join meta.enum e on t.parent_id is null and t.key='entity_type' and e.key=v_sheet.entity_type;
			return jsonb_build_object('error', format('Нельзя удалять %s', v_tmp));
		end if;
		delete from meta.entity where id = v_sheet.id;
		delete from data."row" where guid =v_sheet.guid;
		return jsonb_build_object();
	end if;

	if v_sheet.entity_type='PHYS' then
		return meta.sheet_set_pg(f_params);
	end if;

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

    if (v_sheet.up_version and v_sheet.entity_type in ('SYS','PGT','RSYS'))or(v_sheet.is_new and v_sheet.entity_type='RVT') then
        insert into meta.version(guid, entity_id)
        values (uuid_generate_v4(), v_sheet.id)
        returning id into v_sheet.version_id;

        update meta.entity
        set version_id = v_sheet.version_id
        where id = v_sheet.id;

    	if v_sheet.entity_type='RVT' then
		  execute 'create table data.rvt_'||v_sheet.id::varchar||' ( like data.rvt including indexes, check(entity_id = '||
					  v_sheet.id::varchar||') ) inherits (data.rvt)';
		end if;
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
            attr.name,
            coalesce(t.id, a.type_id) type_id,
            coalesce(attr.title, a.title) title,
            coalesce(attr.reference, (attr.defs ->>'reference_guid')::uuid::varchar) ref_guid,
            coalesce(attr.reference_column, (('{'||replace(replace(attr.defs ->>'reference_names', '[', ''), ']', '')||'}')::varchar[])[1]) ref_names,
            null::bigint ref_attribute_id,
            t.key type_key,
            attr.defs,
            a.flags
        from (
		  select row_number() over() npp,
		  	(x.value->>'name') "name",
		    (x.value->>'type') "type",
		    (x.value->>'title') "title",
		    (x.value->>'reference') "reference",
		    (x.value->>'reference_column') "reference_column",
		     x.value defs
		  from
		  jsonb_array_elements(f_params->'columns') x
		) attr
        left join meta.attribute a on a.entity_id = v_sheet.id and a.name = attr.name
        left join meta.data_type t on t.key = attr.type
		order by attr.npp
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
$meta_sheet_set__2026_07_16$;


create function meta.sheet_get(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $meta_sheet_get__2026_08_07$
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
	 		'entity_type', e.entity_type,
            'columns', (select jsonb_agg(x.defs) from (
                 select jsonb_build_object(
                      'name', c."name",
                      'title',c.title,
                      'type', t.key,
				      'is_nullable', (nn.id is null) and (pk.id is null),
			  		  'is_unique', (uk.id is not null) or (pk.id is not null)
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
                 end||
			  	 case
			  		when t.key = 'r' or ro.id is not null then jsonb_build_object('editable',false)
			  		else jsonb_build_object()
                 end
				 defs
                 from meta.attribute c
                 inner join meta.data_type t on t.id = c.type_id
			  	 inner join meta.enum flg on flg.parent_id is null and flg.key='attr_flags'
				 left join meta.attribute a on a.id = c.ref_attribute_id
			  	 left join meta.enum nn on nn.parent_id = flg.id and nn.id = any(c.flags) and nn.key = 'NN'
				 left join meta.enum uk on uk.parent_id = flg.id and uk.id = any(c.flags) and uk.key = 'UQ'
			  	 left join meta.enum ro on ro.parent_id = flg.id and ro.id = any(c.flags) and ro.key = 'RO'
			     left join meta.enum pk on pk.parent_id = flg.id and pk.id = any(c.flags) and pk.key = 'PK'
                 where c.entity_id=e.id
			     order by c.id
                 ) x)
        )||case
		   when e.entity_type = 'PHYS' then jsonb_build_object('table_name', (select "name" from meta.pg_table where id = e.id))
		   else jsonb_build_object()
		end
        from meta.entity e
        where e.id = v_sheet.id
   );
end;
$meta_sheet_get__2026_08_07$;


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
        "title":"Идентификатор версии",
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
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $data_eav_insert__2026_06_20$
begin
    execute format(
      'insert into data.eav_%s values ($1.*)',
      new.version_id
    ) using new;
    return null;
end
$data_eav_insert__2026_06_20$;

create function data.eav_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $data_eav_update__2026_06_19$
begin
    execute format(
      $q$update data.eav_%I set s=%L, i=%L::bigint, f=%L::double precision, r=%L::bigint, t=%L::timestamp where id=%I and attribute_id=%I$q$,
      new.version_id,
      new.s, new.i, new.f, new.r, new.t,
      new.id, new.attribute_id
    );
    return null;
end
$data_eav_update__2026_06_19$;

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
  version_id bigint not null unique references meta.version(id) on delete cascade,
  row_data jsonb,
  refs jsonb,
  constraint rvt_pk primary key (id, entity_id, version_id)
);
comment on table data.rvt is 'базовая таблица с версионированием каждой строки';
comment on column data.rvt.row_data is 'значения всех атрибутов в json';
comment on column data.rvt.refs is 'идентификаторы для ссылочных атрибутов';


create table data.uk_entity(
  row_id bigint not null references data.row(id) on delete cascade,
  atr_id bigint not null references meta.attribute(id) on delete cascade,
  "value" varchar not null,
  constraint pk_uk_entity primary key (row_id, atr_id),
  constraint uk_uk_entity unique (atr_id, "value")
);

comment on table data.uk_entity is 'таблица для проверки уникальности в рамках таблицы';

create table data.uk_version(
  version_id bigint not null references meta.version(id) on delete cascade,
  row_id bigint not null references data.row(id) on delete cascade,
  atr_id bigint not null references meta.attribute(id) on delete cascade,
  "value" varchar not null,
  constraint pk_uk_version primary key (version_id, row_id, atr_id),
  constraint uk_uk_version unique (version_id, atr_id, "value")
);

comment on table data.uk_version is 'таблица для проверки уникальности в рамках версии';


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
create function data.version_get_value(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_version_get_value__2026_06_26$
declare
 v_sheet record;
 v_cnt integer;
begin
/*
Возвращает значения заданного атрибута по заданному guid таблицы, версии и/или идентификаторам строк.
Выходная структура аналогична входной, но в row значения полей, а не идентификаторы
{
	"version_guid": "идентификатор версии. если не задан то будет найден автоматически",
	"guid": "идентификатор таблицы. версия будет найдена автоматически",
	"column": "поле откуда тянуть значения, если не задано, то только поиск таблицы/версии"
	"value": "guid или список guid-ов строк. если не задан, то только поиск таблицы/версии"
}
*/
	if (f_params->>'version_guid') is not null then
		select e.id, e.guid, e.entity_type, v.id version_id, v.guid version_guid, null::jsonb "rows", null::bigint attr_id, e.f_read is not null calc
		into v_sheet
		from meta.entity e
		inner join meta.version v on v.entity_id = e.id and v.guid = (f_params->>'version_guid')::uuid;
	elseif (f_params->>'guid') is not null then
		select e.id, e.guid, e.entity_type, null::bigint version_id, null::uuid version_guid, null::jsonb "rows", null::bigint attr_id, e.f_read is not null calc
		into v_sheet
		from meta.entity e
		where e.guid = (f_params->>'guid')::uuid;
	elseif (f_params->>'version_guid') is null and jsonb_typeof(f_params->'value')='string' then
		select e.id, e.guid, e.entity_type, null::bigint version_id, null::uuid version_guid, null::jsonb "rows", null::bigint attr_id, e.f_read is not null calc
		into v_sheet
		from meta.entity e
		inner join data.row r on r.guid = (f_params->>'value')::uuid and r.entity_id = e.id;
	elseif (f_params->>'version_guid') is null and jsonb_typeof(f_params->'value')='array' then
		select e.id, e.guid, e.entity_type, null::bigint version_id, null::uuid version_guid, null::jsonb "rows", null::bigint attr_id, e.f_read is not null calc
		into v_sheet
		from meta.entity e
		inner join data.row r on r.guid = (f_params->'value'->>0)::uuid and r.entity_id = e.id;
	else
		select null::bigint id into v_sheet;
	end if;

	if v_sheet.id is null then
		return jsonb_build_object('error','Не найдена таблица с данными по ссылке');
	end if;

	if v_sheet.version_id is null then
		select v_sheet.id, v_sheet.guid, v_sheet.entity_type, x.id version_id, v.guid version_guid, v_sheet."rows", v_sheet.attr_id, v_sheet.calc
		into v_sheet
		from (
		  select case
		   when v.status='A' then 0
		   when v.status='P' then 1
		   when v.status='R' then 2
		   when v.status='D' then 3
		   else 4
		  end, max(v.id) id
		  from meta.version v
		  where v.entity_id = v_sheet.id
		  group by 1
		  order by 1
		  limit 1
		) x
		inner join meta.version v on v.id = x.id
		limit 1;
	end if;

	if (f_params->>'column') is not null then
		select a.id into v_sheet.attr_id
		from meta.attribute a
		where a.entity_id = v_sheet.id and (
		  (jsonb_typeof(f_params->'column')='number' and a.id = (f_params->>'column')::bigint) or
		  (jsonb_typeof(f_params->'column')='string' and a.name = (f_params->>'column')));

		if v_sheet.attr_id is null then
			return jsonb_build_object('error',format('Атрибут %s не найден', f_params->>'column'));
		end if;

		if jsonb_typeof(f_params->'value')='string' then
			select array_to_json(array[f_params->>'value'])::jsonb
			into v_sheet."rows";
		else
			v_sheet."rows" = f_params->'value';
		end if;

		v_cnt = jsonb_array_length(v_sheet."rows");

		if v_cnt = 0 then
			return jsonb_strip_nulls(jsonb_build_object(
			  'version_guid', v_sheet.version_guid,
			  'guid', v_sheet.guid,
			  'not_exists', 0,
			  'column', (f_params->>'column')
			));
		end if;

		if not v_sheet.calc and v_sheet.entity_type in ('EAV', 'VER') then
			select jsonb_agg(
			  case
			    when t.eav_field = 's' then d.s
			    when t.eav_field = 'i' then d.i::text
			    when t.eav_field = 'f' then d.f::text
			    when t.eav_field = 't' then d.t::text
			    else '...'::text
			  end
			)
			into v_sheet."rows"
			from jsonb_array_elements_text(v_sheet."rows") qr
			inner join data.row r on r.guid = qr.value::uuid and r.entity_id = v_sheet.id
			inner join data.eav d on d.attribute_id = v_sheet.attr_id and d.version_id = v_sheet.version_id and d.id = r.id
			inner join meta.attribute a on a.id = v_sheet.attr_id
			inner join meta.data_type t on t.id = a.type_id;
		else
			select array_to_json(array_agg(d.value->'value'->(f_params->>'column')))
			into v_sheet."rows"
			from jsonb_array_elements(
			  data.sheet_get(jsonb_build_object(
				'version_guid', v_sheet.version_guid,
				'fields', array_to_json(ARRAY[version_guid]),
				'filter', v_sheet."rows"
			  ))->'rows'
			) d;
		end if;
	else
		return jsonb_strip_nulls(jsonb_build_object(
          'version_guid', v_sheet.version_guid,
          'guid', v_sheet.guid
        ));
	end if;

	return jsonb_strip_nulls(jsonb_build_object(
	  'version_guid', v_sheet.version_guid,
	  'guid', v_sheet.guid,
	  'value', case
	  			when jsonb_typeof(f_params->'value')='string' then v_sheet."rows"->0
	  			else v_sheet."rows"
	  		  end,
	  'not_exists', v_cnt - coalesce(jsonb_array_length(v_sheet."rows"),0),
	  'column', (f_params->>'column')
	));
end
$data_version_get_value__2026_06_26$;


create or replace function data.value_check(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_value_check__2026_08_06$
declare
 fld_def record;
 tmp_rec record;
 ret jsonb;
begin
 /*
  Проверка значения атрибута
  на вход:
  {
  	"value": "значение",
	"guid": "идентификатор таблицы",
	"type": "тип значения. если задан этот атрибут или атрибуты ниже, то свойства полшя беруться из них",
  	"referencе": "guid таблицы для типов R, M или имя enum для типа Е",
	"ref_attribute": "имя атрибута, данные которого тянуть по ссылке (необязательно)",
	"row_id": "идентификатор строки. необходим для проверок на уникальность",
	"is_unique": "если True - проверить на уникальность. По умолчанию:False",
	"is_nullable": "если True - проверить что не Null",

	"column_id": "числовой идентификатор столбца",
	"column_name": "для вывода ошибок",
	"entity_id": "числовой идентификатор таблицы",
  }

  на выходе:
  {
  	  "type": "тип значения",
	  "value": "преобразованое значение",
	  "error":"текст ошибки при проверке либо атрибут отсутствует при успешном завершении",
	  "referencе": "ссылки"
  }
  */

  select
  		(f_params->>'value') "value",
  		(f_params->>'column_id')::bigint id,
		coalesce((f_params->>'name'),'') "name",
		coalesce((f_params->>'is_unique')::boolean, false) is_unique,
		coalesce((f_params->>'is_nullable')::boolean, true) is_nullable,
		(f_params->>'row_id')::bigint row_id,
		(f_params->>'type') "type",
		(f_params->>'referencе') as ref,
		(f_params->>'ref_attribute') "ref_attribute",
		(f_params->>'entity_id')::bigint entity_id,
		(f_params->>'version_id')::bigint version_id,
		(f_params->>'entity_type') entity_type
  into fld_def;


  /*if fld_def."type" is null then
  	return jsonb_build_object('error', format('Тип атрибута %s не определен [при проверке значения]',fld_def.name));
  end if;*/

  if fld_def.value is null then
    if fld_def.is_nullable then
  		return jsonb_build_object('value', null, 'type', fld_def.type);
	else
		return jsonb_build_object('error', format('Значение атрибута %s не может быть NULL [при проверке значения]',fld_def.name));
	end if;
  end if;

  if fld_def.is_unique and fld_def.id is null then
	 return jsonb_build_object('error', 'Не определен Id атрибута [при проверке значения]');
  end if;

  begin
	if fld_def.is_unique and fld_def.row_id is not null and fld_def.entity_type='RVT' then
		insert into data.uk_entity (
			row_id,
			atr_id,
			"value"
		) values (
			fld_def.row_id,
			fld_def.id,
			fld_def.value
		)
		on conflict(row_id, atr_id) do
		update set value = excluded.value;
	elseif fld_def.is_unique and fld_def.row_id is not null and fld_def.entity_type in ('VER','EAV') then
		insert into data.uk_version(
		  	version_id,
			row_id,
			atr_id,
			"value"
		) values (
		  	fld_def.version_id,
			fld_def.row_id,
			fld_def.id,
			fld_def.value
		)
		on conflict(version_id, row_id, atr_id) do
		update set value = excluded.value;
	end if;
  exception
  when others then
	  return jsonb_build_object('error', format('Значение %s нарушает уникальность значений атрибута %s [при проверке значения]', fld_def.value, fld_def.name));
  end;

  if fld_def.type in ('R','M','r','H') then
  	if fld_def.type = 'M' and jsonb_typeof(f_params->'value')!='array' then
		return jsonb_build_object('error', format('Значение множественной ссылки %s должно быть задано массивом [при проверке значения]',fld_def.name));
	end if;
	ret = jsonb_build_object(
	  'guid',   fld_def.ref::uuid,
	  'column', fld_def.ref_attribute,
	  'value', f_params->'value'
	);
	ret = data.version_get_value(ret);

	if ret ? 'error' then
		return jsonb_build_object('error', format('%s. Ссылка %s [при проверке значения]', ret->>'error', fld_def.name));
	end if;
	if coalesce((ret->>'not_exists')::integer, 0) > 0 then
		return jsonb_build_object('error', format('Не найдено одно или несколько значений по ссылке %s [при проверке значения]', fld_def.name));
	end if;
	return jsonb_build_object('value', ret->'value', 'reference', (f_params->>'value'), 'type', fld_def.type);
  elseif fld_def.type = 'E' then
    select e.id, e.key val into tmp_rec
	from meta.enum t
	inner join meta.enum e on e.parent_id = t.id and t.parent_id is null and t.key=fld_def.ref and e.key=fld_def.value;
	if tmp_rec.id is null then
		return jsonb_build_object('error', format('Для поля %s не найдено значение %s перечисления %s', fld_def.name, fld_def.value, fld_def.refid));
	end if;
	return jsonb_build_object('value',tmp_rec.val, 'reference', (f_params->>'value'), 'type', fld_def."type");
  else begin
	ret = case
	  when fld_def.value is null then null
	  when fld_def.type = 'I' then jsonb_build_object('value', fld_def.value::bigint)
	  when fld_def.type = 'F' then jsonb_build_object('value', fld_def.value::double precision)
	  when fld_def.type = 'S' then jsonb_build_object('value', fld_def.value)
	  when fld_def.type = 'B' and upper(fld_def.value) in ('TRUE','ДА','YES','Y','1','T','Д') then jsonb_build_object('value',1)
	  when fld_def.type = 'B' then jsonb_build_object('value',0)
	  when fld_def.type = 'G' then jsonb_build_object('value', fld_def.value::uuid)
	  else jsonb_build_object()
	end;
  exception
  	when others then
		return jsonb_build_object('error', format('Ошибка преобразования типа атрибута %s для значения %s [при проверке значения]',fld_def.name, f_params->>'value'));
  end; end if;

  return ret||jsonb_build_object('type', fld_def.type);
end
$data_value_check__2026_08_06$;

create function data.sheet_set(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_sheet_set__2026_08_07$
declare
   v_sheet record;
   v_counters record;
   v_row record;
   tmp_row_guid varchar = '';
   tmp_row_id bigint;
   tmp_value varchar;
   tmp_rec record;
   tmp_ret jsonb;
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
   
   f_params = f_params || jsonb_build_object('_SYS_INFO_', row_to_json(v_sheet));

   if v_sheet.entity_type='RVT' then      
	  return data.sheet_set_rvt(f_params);
   elseif v_sheet.entity_type='PHYS' then
      return data.sheet_set_pg(f_params);
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
			col.name col_name,
            ra_col.entity_id ref_entity_id,
			ra_col.name ref_attribute,
			case when dt.key='E'
				then col.ref_enum_key
				else re.guid::varchar
			end reference,
			nn.id is null as is_nullable,
			uk.id is not null as is_unique
        from (
            select coalesce((x.value->>'guid')::uuid, uuid_generate_v4()) guid,
                   (x.value->'data') "data",
                   (x.value->>'delete')::boolean to_delete
            from jsonb_array_elements(f_params->'rows') x
        ) rows
		inner join meta.enum flg on flg.parent_id is null and flg.key='attr_flags'
        left join jsonb_each_text(rows.data) dat on true
        left join data.row db_rows on db_rows.guid = rows.guid and db_rows.entity_id = v_sheet.id
        left join meta.attribute col on col.entity_id = v_sheet.id and col.name = dat.key
        left join meta.attribute ra_col on ra_col.id = col.ref_attribute_Id
		left join meta.entity re on re.id = ra_col.entity_id
        left join meta.data_type dt on dt.id = col.type_id
        left join data.eav dea on dea.version_id=v_sheet.version_id and dea.id=db_rows.id and dea.attribute_id=col.id
		left join meta.enum nn on nn.parent_id = flg.id and nn.id = any(col.flags) and nn.key = 'NN'
		left join meta.enum uk on uk.parent_id = flg.id and uk.id = any(col.flags) and uk.key = 'UQ'
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

		if v_row.type_code = 'r' then
			continue;
        elseif v_row.type_code = ('R') then
            tmp_value = null;
            select r.id::varchar into tmp_value
            from data.row r
            where r.entity_id=v_row.ref_entity_id and r.guid = v_row.value::uuid;
            if tmp_value is Null then
               return jsonb_build_object('error', format('Для поля %s не найдена строка по ссылке %s', v_row.name, v_row.value));
            end if;
            v_row.value = tmp_value::text;
		elseif v_row.type_code = ('H') then
			select r.id, d.eav_field, e.guid, a.name att_name
			into tmp_rec
            from data.row r
			inner join meta.attribute a on a.entity_id = r.entity_id and a.id = v_row.ref_attribute_id
			inner join meta.entity e on e.id = a.entity_id
			inner join meta.data_type d on d.id = a.type_id
            where r.entity_id=v_row.ref_entity_id and r.guid = v_row.value::uuid;
			if tmp_rec.id is Null then
               return jsonb_build_object('error', format('Для поля %s не найдена строка по ссылке %s', v_row.name, v_row.value));
            end if;
			tmp_ret = data.version_get_value(jsonb_build_object(
				'guid', tmp_rec.guid,
			  	'column', tmp_rec.att_name,
			    'value', v_row.value
			));
			if (tmp_ret ->> 'error') is not null then
				return jsonb_build_object('error', tmp_ret->>'error');
			end if;
			v_row.value = tmp_ret->>'value';
			v_row.eav_field = tmp_rec.eav_field;
        elseif v_row.type_code = 'M' then
            select count(*) cnt, sum(case when x.value is null then 0 else 1 end) chk, array_agg(r.guid)::varchar val, 'M' as t
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
        else
			tmp_ret = data.value_check(jsonb_build_object(
              'type', v_row.type_code,
              'value', v_row.value,
              'referencе', v_row.reference,
			  'ref_attribute', v_row.ref_attribute,
              'is_unique', v_row.is_unique,
              'is_nullable', v_row.is_nullable,
              'guid', v_sheet.guid,
              'column_id', v_row.attribute_id,
			  'name', v_row.col_name,
			  'entity_id', v_sheet.id,
			  'entity_type', v_sheet.entity_type,
			  'row_id', tmp_row_id,
			  'version_id', v_sheet.version_id
            ));

            if (tmp_ret->>'error') is not null then
                return jsonb_build_object('error', tmp_ret->>'error');
			else
				v_row.value = tmp_ret->>'value';
            end if;
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

		if v_row.type_code = 'H' then
			update data.eav
			set r = tmo_rec.id
			where
                version_id = v_sheet.version_id and
                id = tmp_row_id and
                attribute_id = v_row.attribute_id;
		end if;
   end loop;

   return row_to_json(v_counters)::jsonb||jsonb_build_object('version_guid',v_sheet.version_guid, 'guid', v_sheet.guid);
end;
$data_sheet_set__2026_08_07$;


create function data.sheet_set_rvt(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_sheet_set_rvt__2026_08_06$
declare
   v_row record;
   v_sheet record;
   v_counters record;
   v_cols jsonb;
   v_def record;
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
			coalesce(rvt.refs, jsonb_build_object()) refs,
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

		if v_row.id is null then
			v_counters.inserted = v_counters.inserted+1;
			insert into meta.version(entity_id, parent_id)
			values(v_sheet.id, v_sheet.version_id)
			returning id, guid into v_row.version_id, v_sheet.version_guid;

			insert into data.row(class_id, entity_id, guid, version_id)
			select v_row.class_id, v_sheet.id, v_row.guid, v_row.version_id
			returning id into v_row.id;

			update meta.entity set version_id = v_row.version_id where id = v_sheet.id;

			insert into data.rvt(id, entity_id, version_id)
			values(v_row.id, v_sheet.id, v_row.version_id);

			v_row.status = 'D';
			v_counters.updated = v_counters.updated - 1;
		end if;

		for v_def in
			select v.value->>'name' fld_name, t.key type_key,
			  v_row.new_data->>(v.value->>'name') "value",
			  a.ref_enum_key, 
			  a.id, 
			  a.name col_name,
			  ra.name ref_attribute,
			  nn.id is null as is_nullable,
			  uk.id is not null as is_unique
            from jsonb_array_elements(v_cols->'columns') v
            inner join meta.data_type t on t.id = (v.value->>'type_id')::bigint
			inner join meta.enum flg on flg.parent_id is null and flg.key='attr_flags'
			left join meta.attribute a on a.entity_id = v_sheet.id and a."name"=(v.value->>'name')
			left join meta.enum nn on nn.parent_id = flg.id and nn.id = any(a.flags) and nn.key = 'NN'
			left join meta.enum uk on uk.parent_id = flg.id and uk.id = any(a.flags) and uk.key = 'UQ'
			left join meta.attribute ra on ra.id = a.ref_attribute_id
			where v_row.new_data ? (v.value->>'name')
			order by a.id
		loop
			v_val = jsonb_build_object(
              'type', v_def.type_key,
              'value', v_def.value,
              'referencе', v_def.ref_enum_key,
			  'ref_attribute', v_def.ref_attribute,
              'is_unique', v_def.is_unique,
              'is_nullable', v_def.is_nullable,
              'guid', v_sheet.guid,
              'column_id', v_def.id,
			  'name', v_def.col_name,
			  'entity_id', v_sheet.id,
			  'entity_type', v_sheet.entity_type,
			  'row_id', v_row.id
            );
			raise notice 'CHK %', v_val;
            v_val = data.value_check(v_val);
			raise notice 'RET %', v_val;

            if (v_val->>'error') is not null then
                return jsonb_build_object('error', v_val->>'error');
            end if;
            v_row.row_data = v_row.row_data||jsonb_build_object(v_def.fld_name, v_val->'value');
			if v_def.type_key in ('R','r','M','E','H') then
				v_row.refs = v_row.refs - v_def.fld_name;
				v_row.refs = v_row.refs||jsonb_build_object(v_def.fld_name, v_val->'reference');
			end if;
		end loop;

		if v_row.status = 'D' then
			v_counters.updated = v_counters.updated + 1;
			update data.rvt set
			  row_data=v_row.row_data,
			  refs = v_row.refs
			where id = v_row.id and version_id=v_row.version_id and entity_id=v_sheet.id;
		else
			v_counters.inserted = v_counters.inserted+1;
			insert into meta.version(entity_id, parent_id)
			values(v_sheet.id, v_sheet.version_id)
			returning id, guid into v_row.version_id, v_sheet.version_guid;

			update meta.entity set version_id = v_row.version_id where id = v_sheet.id;

			insert into data.rvt(id, entity_id, version_id, row_data, refs)
			values(v_row.id, v_sheet.id, v_row.version_id, v_row.row_data, v_row.refs);
		end if;
	end loop;

    return row_to_json(v_counters)::jsonb||jsonb_build_object('version_guid',v_sheet.version_guid, 'guid', v_sheet.guid);
end
$data_sheet_set_rvt__2026_08_06$;


create function data.filter(f_version_id bigint, f_params jsonb)
 RETURNS TABLE(id bigint, npp integer, "mac" smallint[])
 LANGUAGE plpgsql
AS $data_filter__2026_08_05$
declare
   v_query text = '';
   v_limits text;
   v_version record;
   chk_mac text = 'true';
   v_js jsonb;
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

   if coalesce((f_params->>'current_mac_only')::boolean, false) then
   		begin
   			chk_mac = 't.maclabel::varchar = '''||(select current_setting('ac_session_maclabel')::varchar)||'''';
		exception when others then
			chk_mac = 'true';
		end;
   end if;

   if (f_params->>'filter') is null and (f_params->>'order') is null then
        v_query = format($q$
			select x.id, row_number() over (order by x.id)::integer npp, null::smallint[] "mac"
            from (
			  select t.id
			  from data.eav_%s t
			  where %s
			  group by id
			  order by t.id
        %s) x$q$, v_version.id, chk_mac, v_limits);
   elseif (f_params->>'filter') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        v_query = format($q$
			select t.id, 1::integer npp, null::smallint[] "mac"
			from data.row t
			where %s and x.guid=%L::uuid
		$q$, chk_mac, f_params->>'filter');
   elseif jsonb_typeof(f_params->'filter') = 'array' and (f_params->'filter'->>0)~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
   		v_query = format($q$
			select t.id, x.npp::integer, null::smallint[] "mac"
			from (
			  select x.value::uuid guid, row_number() over () as npp
			  from jsonb_array_elements_text(%L::jsonb) x
			) x
			inner join data.row t on t.guid = x.guid
			where %s
		$q$, (f_params->>'filter'), chk_mac);
   else
   		v_js = data.filter_query_get(f_params);
		if v_js ? 'error' then
			raise exception '%', v_query ->> 'error';
		end if;
		v_query = v_js->>'query';
		v_query = format($q$select r.id, x.npp::integer, null::smallint[] "mac"
		from(%s) x
		inner join data.row r on r.guid = x."PK_GUID"
		$q$, v_query);
   end if;

   return query execute v_query;
end
$data_filter__2026_08_05$;


create function data.filter_rvt(f_version_id bigint, f_params jsonb)
 RETURNS TABLE(id bigint, npp integer, mac smallint[])
 LANGUAGE plpgsql
AS $data_filter_rvt__2026_07_07$
declare
   v_query text = '';
   v_limits text;
   v_version record;
   v_js jsonb;
   chk_mac text = 'true';
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

   if coalesce((f_params->>'current_mac_only')::boolean, false) then
   		begin
   			chk_mac = 't.maclabel::varchar = '''||(select current_setting('ac_session_maclabel')::varchar)||'''';
		exception when others then
			chk_mac = 'true';
		end;
   end if;

   if (f_params->>'filter') is null and (f_params->>'order') is null then
        v_query = format($q$
			select x.id, row_number() over (order by x.id)::integer npp, null::smallint[] "mac"
             from (
			   select t.id
			   from data.rvt_%s t
			   where t.version_id <= %s
			   group by id
			   order by t.id
             %s) x
		$q$, v_version.entity_id, v_version.id, v_limits);
   elseif (f_params->>'filter') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        v_query = format($q$
			select r.id, 1::integer npp, null::smallint[] "mac"
			from data.row r where r.guid=%L::uuid
		$q$, f_params->>'filter');
   elseif jsonb_typeof(f_params->'filter') = 'array' and (f_params->'filter'->>0)~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
		v_query = format($q$
			select r.id, x.npp::integer, null::smallint[] "mac"
			from (
			  select x.value::uuid guid, row_number() over () as npp
			  from jsonb_array_elements_text(%L::jsonb) x
			) x
			inner join data.row r on r.guid = x.guid
			where %s
			$q$, (f_params->>'filter'), chk_mac);
   else
   		v_js = data.filter_query_get(f_params-'version_guid');
		if v_js ? 'error' then
			raise exception '%', v_query ->> 'error';
		end if;
		v_query = v_js->>'query';
		v_query = format($q$select r.id, x.npp::integer, null::smallint[] "mac"
		from(%s) x
		inner join data.row r on r.guid = x."PK_GUID"
		$q$, v_query);
   end if;

   return query execute v_query;
end
$data_filter_rvt__2026_07_07$;


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
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_sheet_get__2026_08_04$
declare
   v_sheet record;
   v_ret jsonb;
   t_tmp text;
   tmp_rec record;
   v_ver_in_params boolean = true;
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
	   e1.entity_type,
	   (select array_agg(a."name")
		from meta.attribute a
		left join jsonb_array_elements_text(f_params->'fields') AS elem on a."name" = elem::varchar
		where a.entity_id = e1.id and ((f_params->'fields') is null or elem is not null)
	   ) fields
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on  e.guid = (f_params->>'guid')::uuid
   left join meta.version v1 on v1.id = coalesce(v.id, e.version_id)
   left join meta.entity e1 on e1.id=coalesce(v1.entity_id, e.id);

   if not(f_params ? 'guid') and v_sheet.guid is not null then
   		f_params = f_params||jsonb_build_object('guid', v_sheet.guid);
   end if;

   if not(f_params ? 'fields') is not null then
   		f_params = f_params||jsonb_build_object('fields', (array_to_json(v_sheet.fields)::jsonb));
   end if;

   if not(f_params ? 'version_guid') then
   		v_ver_in_params = false;
   		if v_sheet.version_guid is not Null then
   			f_params = f_params||jsonb_build_object('version_guid', v_sheet.version_guid);
		end if;
   end if;

   if v_sheet.id is Null then
        return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   elseif coalesce((f_params->>'debug')::boolean, false) and v_sheet.entity_type!='PHYS' then
   		/* получить  запрос для возврата данных в виде обычной таблицы */
		f_params = f_params - 'debug';
		t_tmp = 'select (tbl.value->>''guid'')::uuid "PK_GUID", (tbl.value->>''npp'')::bigint "ROW_NUMBER" ';
		for tmp_rec in
			select a."name", t."key" tp_key, t.eav_field
			from meta.attribute a
			inner join meta.data_type t on t.id = a.type_id
			where a.entity_id = v_sheet.id and a.name = any(v_sheet.fields)
		loop
			t_tmp = t_tmp||','||case
  				when tmp_rec.tp_key = 'I' then format($q$(tbl.value->'data'->>'%s')::bigint$q$, tmp_rec."name")
				when tmp_rec.tp_key = 'G' then format($q$(tbl.value->'data'->>'%s')::uuid$q$, tmp_rec."name")
				when tmp_rec.tp_key = 'D' then format($q$(tbl.value->'data'->>'%s')::double precision$q$, tmp_rec."name")
				when tmp_rec.tp_key = 'T' then format($q$(tbl.value->'data'->>'%s')::timestamp$q$, tmp_rec."name")
				when tmp_rec.tp_key in ('M','R') then format($q$(tbl.value->'references'->>'%s')::uuid$q$, tmp_rec."name")
  				else format($q$(tbl.value->'data'->>'%s')$q$, tmp_rec."name")
  			end||' as '||quote_ident(tmp_rec."name");
		end loop;
		t_tmp = format($q$%s
from jsonb_array_elements(data.sheet_get('%s')->'rows') tbl$q$, t_tmp, f_params);
		return jsonb_build_object('query', t_tmp);
   elseif v_sheet.f_read is not Null then
   		/* если задана кастомная функция для получения данных - вызываем её */
        t_tmp = format($q$select %s('%s')$q$, v_sheet.f_read,f_params);
        execute t_tmp into v_ret;
   elseif v_sheet.fields is null and v_sheet.entity_type in ('EAV', 'VER') then
   		/* возврат только гуидов EAV - поля не запросили */
   		select array_to_json(array_agg(
		   jsonb_strip_nulls(jsonb_build_object('guid', x.guid, 'class', x.class_guid))
	    ))
	    into v_ret
		from (
		  select r.guid,  c.guid class_guid
		  from data.filter(v_sheet.version_id, f_params) ff
		  inner join data.row r on r.id = ff.id
		  left join meta.class c on r.class_id = c.id
		  order by ff.npp
		) x;
   elseif v_sheet.fields is null and v_sheet.entity_type='RVT' then
   		/* возврат только гуидов RVT - поля не запросили */
   		select array_to_json(array_agg(
		   jsonb_strip_nulls(jsonb_build_object('guid', x.guid, 'class', x.class_guid))
	    ))
	    into v_ret
		from (
		  select r.guid,  c.guid class_guid
		  from data.filter_rvt(v_sheet.version_id, f_params) ff
		  inner join data.row r on r.id = ff.id
		  left join meta.class c on r.class_id = c.id
		  order by ff.npp
		) x;
   elseif v_sheet.entity_type in ('EAV','VER') then
        /* возврат - чтение данных EAV */
	   	with refs as (
		   select a.id, (array_agg(vto.id order by e.id))[1] version_id, dto.eav_field, dto."key"
			   from meta.attribute a
			   inner join meta.data_type dt on a.type_id = dt.id and dt.key in ('R', 'M', 'H')
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
		   jsonb_build_object('guid', x.guid, 'data', x.data, 'references', x.refs, 'class', x.class_guid, 'npp', x.npp)
		 ))
		 into v_ret
		 from (
		 select r.guid, row_number() over(order by r.id) npp,
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

			   when dt.key in ('H','h') and refs.key='B' then to_jsonb(eav.i=1)
			   when dt.key in ('H','h') and refs.eav_field='i' then to_jsonb(eav.i)
			   when dt.key in ('H','h') and refs.eav_field='f' then to_jsonb(eav.f)
			   when dt.key in ('H','h') and refs.eav_field='t' then to_jsonb(eav.t)

			   when refs.key ='M' then to_jsonb((
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
			   )) --
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
		  where v.id = v_sheet.version_id and atr."name" = any(v_sheet.fields)
		  group by r.guid, fltr.npp, cla.guid, r.id
		  order by fltr.npp
		 ) x;
   elseif v_sheet.entity_type='RVT' then
   		/* возврат - чтение данных RVT */
		select jsonb_agg(x.val)
		into v_ret
		from (select jsonb_strip_nulls(
		  	    jsonb_build_object(
				    'npp', row_number() over(order by r.id),
                    'guid', r.guid,
                    'class', cla.guid,
                    'version_guid', v.guid,
                    'data', rvt.row_data,
                    'references', case when rvt.refs = '{}'::jsonb then null else rvt.refs end
		  	    )
		    ) val
		from data.row r
		inner join data.rvt rvt on rvt.entity_id = v_sheet.id and rvt.id = r.id
		inner join meta.version v on v.id = v_sheet.version_id
        inner join data.filter_rvt(v.id, f_params) fltr on fltr.id = r.id
        left join  meta.class cla on cla.id = r.class_id
        where r.entity_id = v_sheet.id and (not v_ver_in_params or rvt.version_id = v_sheet.version_id)
        order by fltr.npp
			 ) x;
   elseif v_sheet.entity_type='PHYS' then
   		f_params = f_params||jsonb_build_object('guid', v_sheet.guid);
   		return data.sheet_get_pg(f_params);
   else
   		return jsonb_build_object('error','Неподдерживаемый тип таблицы');
   end if;

   if v_ret is null then
   		v_ret = '[]'::jsonb;
   end if;

   if jsonb_typeof(v_ret)='null' then
   		v_ret = '[]'::jsonb;
   end if;

   return jsonb_build_object('guid', v_sheet.guid, 'version_guid', v_sheet.version_guid, 'rows', v_ret);
end
$data_sheet_get__2026_08_04$;


create function data.filter_query_get(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_filter_query_get__2026_08_04$
declare
  	v_query text;
	v_where text='';
	v_order text='';
  	v_sheet record;
	v_tmp text;
	n_tmp text;
	v_q jsonb;
	v_cnt bigint;
begin
  	select e.id, e.entity_type,
	(select array_to_json(array_agg(jsonb_build_object(
	  		'name', a."name",
	  		'type', t.key,
	  		'reference', case when t.key = 'E' then a.ref_enum_key else r.guid::varchar end
		)))::jsonb
		from meta.attribute a
	 	inner join meta.data_type t on a.type_id = t.id and a.entity_id = e.id
	 	left join  meta.attribute a1 on a1.id = a.ref_attribute_id
	    left join  meta.attribute a2 on a2.id = a1.ref_attribute_id
	 	left join  meta.entity r on r.id = case when t.key = 'r' then a2.entity_id else a1.entity_id end
	 ) fields
	into v_sheet
  	from meta.entity e
	where e.guid = (f_params->>'guid')::uuid;

	if v_sheet.id is null then
		return jsonb_build_object('error', format('Таблица %s не найдена', f_params->>'guid'));
	end if;

	if f_params ? 'order' then
		v_order = $q$
order by $q$;
		for v_tmp, n_tmp in
			select key, value->>key "value"
			  from (
			  select row_number() over () n, (select jsonb_object_keys(x0.value)) as key, x0.value
			  from jsonb_array_elements(f_params->'order') x0) x
			order by x.n
		loop
			if not right(v_order, 6)='er by ' then
				v_order = v_order||', ';
			end if;
			v_order = v_order||quote_ident(v_tmp);
			if upper(trim(n_tmp))='DESC' then
				v_order = v_order||' desc';
			end if;
		end loop;
	elseif (f_params->>'offset')::bigint > 0 or (f_params->>'limit')::bigint >= 0 then
		v_order = v_order||' order by t."ROW_NUMBER"';
	else
		v_order = '';
	end if;

	v_query = data.sheet_get(((f_params - 'filter')-'order'-'limit'-'offset')||jsonb_build_object('debug','true'))->>'query';

	v_query = format($q$select t."PK_GUID", row_number() over(%s) npp
	from (%s) t
$q$, v_order, v_query);

	if jsonb_typeof(f_params->'filter')='object' and (f_params->'filter') ? '' then
		/* старый вариант со знаком операции в отдельном поле (для совместимости)*/
		select x.key
		into n_tmp
		from jsonb_each_text(f_params->'filter') x
		where x.key!='';

		v_q = (select x.value
		 from jsonb_array_elements(v_sheet.fields) x
		 where (x.value->>'name') = n_tmp)||jsonb_build_object(
		  'value', (f_params->'filter'->>'')||(f_params->'filter'->>n_tmp)
		 );
		 v_q = data.filter_part_get(v_q);
		 if v_q ? 'error' then
		 	return v_q;
		 end if;
		v_where = v_where||' and '||(v_q->>'expr');

	elseif jsonb_typeof(f_params->'filter')='object' then
		/* фильтр, где ключ - поле, а значение знак операции и значение для сравнения. связь and */
		for n_tmp, v_tmp in
			select x.key, x.value from jsonb_each_text(f_params->'filter') x
		loop
		   v_q = (select x.value
			 from jsonb_array_elements(v_sheet.fields) x
			 where (x.value->>'name') = n_tmp)||jsonb_build_object(
			  'value', v_tmp
			 );
		   v_q = data.filter_part_get(v_q);
		   if v_q ? 'error' then
			  return v_q;
		   end if;
		   v_where = v_where||' and '||(v_q->>'expr');
		end loop;
	elseif jsonb_typeof(f_params->'filter')='array' then
		/* массив из объектов как выше, связанных по or  */
		v_where = v_where||'and (';
		for v_q in
			select jsonb_array_elements(f_params->'filter')
		loop
		   if right(v_where, 2)!=' (' then
				v_where = v_where||' or';
		   end if;
		   if v_q ? '' then
		   		v_tmp = v_q ->> '';

				select x.key
				into n_tmp
				from jsonb_each_text(v_q) x
				where x.key!='';

				v_q = (select x.value
				 from jsonb_array_elements(v_sheet.fields) x
				 where (x.value->>'name') = n_tmp)||jsonb_build_object(
				  'value', v_tmp||(v_q->>n_tmp)
				 );
				v_q = data.filter_part_get(v_q);
			   	if v_q ? 'error' then
				  return v_q;
			   	end if;
				if right(v_where, 2)!=' (' then
					v_where = v_where||' or ';
				end if;
				v_where = v_where||(v_q->>'expr');
		   else
				/* пробег по объекту со связкой and */
				v_where = v_where||' (';
				for n_tmp, v_tmp in
					select x.key, x.value from jsonb_each_text(v_q) x
				loop
				   v_q = (select x.value
					 from jsonb_array_elements(v_sheet.fields) x
					 where (x.value->>'name') = n_tmp)||jsonb_build_object(
					  'value', v_tmp
					 );
				   v_q = data.filter_part_get(v_q);
				   if v_q ? 'error' then
					return v_q;
				   end if;
				   if right(v_where, 2)!=' (' then
					  v_where = v_where||' and ';
				   end if;
				   v_where = v_where||(v_q->>'expr');
				end loop;
				v_where= v_where||')';
		   end if;
		end loop;
		v_where = v_where||')';
	elseif f_params ? 'filter' then
		v_where = v_where||format($q$and PK_GUID='%s'::uuid$q$, f_params->'filter');
	end if;

	if v_where!='' then
	   v_where = right(v_where, length(v_where)	- 4);
	   v_query = v_query||'where'||v_where;
	end if;

	if f_params ? 'offset' or f_params ? 'limit' then
		v_query = v_query||v_order||' ';
	end if;

	if (f_params->>'offset')::bigint < 0 then
		v_tmp = $q$select count(*) from (
		$q$||v_query||') x';
		execute v_tmp into v_cnt;
		f_params = f_params||jsonb_build_object('offset', v_cnt + (f_params->>'offset')::bigint);
	end if;

	if (f_params->>'offset')::bigint > 0 then
		v_query = v_query||' offset '||(f_params->>'offset');
	end if;
	if (f_params->>'limit')::bigint >= 0 then
		v_query = v_query||' limit '||(f_params->>'limit');
	end if;
	return jsonb_build_object('query', trim(v_query), 'count', v_cnt, 'where', trim(v_where), 'order', trim(v_order));
end
$data_filter_query_get__2026_08_04$;

create function data.filter_part_get(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_filter_part_get__2026_08_04$
declare
	val varchar;
	up_val varchar;
	op varchar;
	f_name varchar;
begin
	/*
	на входе
	{
		"name": "имя поля",
	  	"type": "тип поля (код)",
		"reference": "гуид таблицы или имя enum, на которйссылка",
		"value": "значение, возможно со знаком операции в начале"
	}
	на выходе:
	{
		"expr": "выражение операции сравнения"
	}
	*/
	f_name = 't.'||quote_ident(f_params->>'name');
	val = f_params->>'value';
	op = left(val, 1);
	if op in ('<','>','=','!','~') then
		val = right(val, length(val) - 1);
		if op = left(val, 1) then
			op = Null;
		elseif op in ('<','>','!') and left(val, 1) = '=' then
			op = op||left(val, 1);
			val = right(val, length(val) - 1);
		end if;
	else
		op = Null;
	end if;

	if length(val)>1 then
		val = trim(val);
	end if;
	up_val = upper(val);
	if up_val='NULL' then
		val = null;
	elseif up_val = $q$'NULL'$q$ then
 		val = substring(val, 2, length(val)-2);
	elseif val like '%''%' then
		while val like '%''''%' loop
			val = replace(val,$q$''$q$,'''');
		end loop;
	end if;

	if op is Null and (f_params->>'type')='S' then
		op = '~';
	elseif op is Null then
		op = '=';
	end if;

	if (f_params->>'type')='M' then
		return jsonb_build_object('error', 'Операторы не поддерживаются для множественных ссылок');
	elseif op in ('!~', '~') and (f_params->>'type') not in ('S','J') then
		return jsonb_build_object('error', 'Оператор применим только к строкам или json');
	elseif op in ('!~', '~') and position('%' in val)=0 and (f_params->>'type') = 'S' then
		val = '%'||val||'%';
	elseif (f_params->>'type')='J' and op in ('<','<=') then
		op = '<@';
	elseif (f_params->>'type')='J' and op in ('>','=>') then
		op = '@>';
	end if;

	if op='~' and (f_params->>'type')='J' then
		return jsonb_build_object('expr', format('%s ? %L ', f_name, val));
	elseif op='!~' and (f_params->>'type')='J' then
		return jsonb_build_object('expr', format('not(%s ? %L) ', f_name, val));
	elseif op='~' then
		return jsonb_build_object('expr', format('%s ilike %L ', f_name, val));
	elseif op='!~' then
		return jsonb_build_object('expr', format('%s not ilike %L ', f_name, val));
	elseif (f_params->>'type') in ('J','S','T') then
		return jsonb_build_object('expr', format('%s %s %L ', f_name, op, val));
	elseif (f_params->>'type') in ('G','R') then
		if op not in ('=', '!=') then
			return jsonb_build_object('error', format('Для %s допустимы только = и != ',f_params->>'name'));
		end if;
		return jsonb_build_object('expr', format('%s %s %L::uuid ', f_name, op, val));
	elseif op is null then
		return jsonb_build_object('expr', format('%s = %s ', f_name, val));
	else
		return jsonb_build_object('expr', format('%s %s %s ', f_name, op, val));
	end if;

end
$data_filter_part_get__2026_08_04$;

create function meta.sheet_set_pg(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $meta_sheet_set_pg__2026_08_07$
declare
  v_sheet record;
  v_attr record;
  v_flags integer[] = '{}'::integer[];
  v_type char(1);
  i_tmp bigint;
begin
  
  select pt.guid, pt.oid, pt.name, pt.id, null::bigint version_id,
  	a.attname as key_field,	a."key_type"
  into v_sheet 
  from meta.pg_table pt
  inner join (
	with pt0 as (
	  select oid
	  from meta.pg_table t
	  where t.guid = (f_params->>'guid')::uuid or ((f_params->>'guid') is null and t.name = (f_params->>'table'))
	)
	select case when t.typcategory='N' then 'N' else 'G' end "key_type",
	  c.oid, a.attname, cn.contype,
	  pg_get_expr(d.adbin, d.adrelid) is not null key_gen
	from pg_catalog.pg_class c 
	join pt0 on pt0.oid = c.oid
	join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attnum>0
	join pg_catalog.pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
	join pg_catalog.pg_type t on t.oid = a.atttypid and (t.typcategory = 'N' or t.typname='uuid') and a.attnotnull
	join pg_catalog.pg_namespace n on c.relnamespace = n.oid
	join pg_catalog.pg_constraint cn on cn.contype in ('p','u') and array_length(cn.conkey,1)=1 and cn.conkey[1]=a.attnum and cn.conrelid = c.oid
	and cn.contype in ('u','p')
	union all
	select null, pt0.oid, null, null, null
	from pt0
	order by 1 nulls last limit 1
  ) a on a.oid = pt.oid;

  if v_sheet.oid is null then
  	return jsonb_build_object('error', format('Таблица %s %s не существует', (f_params->>'guid'), (f_params->>'table')));
  end if;

  if coalesce((f_params->>'delete')::boolean, false) then
  	delete from meta.entity where id = v_sheet.id;
	delete from data.row where id = v_sheet.id;
  end if;

  /* регистрация таблицы, если она еще не зарегистрированиа */
  if v_sheet.id is null then
  	insert into data.row(entity_id, guid, version_id)
	select t.id, v_sheet.guid, t.version_id
	from  meta.entity t
	where t.guid = uuid_nil()
	returning id into v_sheet.id;

	insert into meta.version(entity_id) values (v_sheet.id)
	returning id into v_sheet.version_id;

	update data.row set
		version_id = v_sheet.version_id
	where id = v_sheet.id;

	insert into meta.entity(id, guid, version_id, entity_type, title)
	select r.id, r.guid, r.version_id, 'PHYS', coalesce(f_params->>'title', v_sheet.name)
	from data.row r
	where r.id = v_sheet.id;
  end if;

  /* регистрация атрибутов */
  for v_attr in
  	select
		a.attnum as position,
		quote_ident(a.attname) as attribute_name,
		coalesce(js.title, ma.title, col_description(c.oid, a.attnum), a.attname) as title,
		format_type(a.atttypid, a.atttypmod) as data_type,
		t.typname,
		t.typcategory,
		a.attlen as type_length,
		a.attnotnull as is_not_null,
		(cn.contype = 'u') is_unique,
		a.attname = v_sheet.key_field is_primary_key,
		pg_get_expr(d.adbin, d.adrelid) as "default"
	from pg_catalog.pg_attribute a
	inner join pg_catalog.pg_type t on t.oid = a.atttypid
	join pg_catalog.pg_class c on a.attrelid = c.oid
	join pg_catalog.pg_namespace n on c.relnamespace = n.oid
	left join pg_catalog.pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
	left join pg_catalog.pg_constraint cn on cn.contype in ('p','u') and array_length(cn.conkey,1)=1 and cn.conkey[1]=a.attnum and cn.conrelid = c.oid
	left join (
	 	select (x.value->>'name') "name", (x.value->>'title') "title"
	    from jsonb_array_elements(f_params->'columns') x
	) js on js.name = a.attname
	left join meta.attribute ma on ma.entity_id = v_sheet.id and ma.name = a.attname
	where a.attstattarget!=0 and c.oid = v_sheet.oid
	order by a.attnum
  loop
  	v_type = case
		when v_attr.typcategory = 'N' and v_attr.typname ~ '^[a-z]*[0-9]$' then 'I'
		when v_attr.typcategory = 'N' then 'F'
		when v_attr.typcategory = 'U' and v_attr.typname='uuid' then 'G'
		when v_attr.typcategory = 'D' then 'T'
		when v_attr.typcategory = 'B' then 'B'
		else 'S'
	end;

  	if v_attr.is_not_null then
		v_flags = meta.enmum_ids_set('attr_flags','NN');
	end if;
	if v_attr.is_unique then
		v_flags = meta.enmum_ids_set('attr_flags','UQ', true, v_flags);
	end if;
	if v_attr.is_primary_key and v_type in ('I','G') then
		v_flags = meta.enmum_ids_set('attr_flags','PK', true, v_flags);
	end if;
	if v_sheet.key_field is null or (v_attr.typcategory='N' and v_attr."default" like 'nextval(%') then
		v_flags = meta.enmum_ids_set('attr_flags','RO', true, v_flags);
	end if;

  	insert into meta.attribute(entity_id, npp, "name", title, flags, type_id)
	select v_sheet.id, v_attr.position, v_attr.attribute_name, v_attr.title, v_flags, t.id
	from meta.data_type t where t.key = v_type
	on conflict (entity_id, "name") do update set
	 title = excluded.title
	;
  end loop;

  if not exists(select 1
	from meta.attribute a
	inner join meta.enum flg on flg.parent_id is null and flg.key='attr_flags'
	inner join meta.enum pk on pk.parent_id = flg.id and pk.id = any(a.flags) and pk.key = 'PK'
	where a.entity_id = v_sheet.id)
  then
    /* если первичного ключа нет - ищем подходящий guid*/
  	select a.id
	into i_tmp
	from meta.attribute a
	inner join meta.data_type t on a.type_id = t.id and t.key='G'
	inner join meta.enum flg on flg.parent_id is null and flg.key='attr_flags'
	inner join meta.enum nn on nn.parent_id = flg.id and nn.id = any(a.flags) and nn.key = 'NN'
	inner join meta.enum uk on uk.parent_id = flg.id and uk.id = any(a.flags) and uk.key = 'UQ'
	where a.entity_id = v_sheet.id order by a.id limit 1;

	if i_tmp is not null then
		update meta.attribute set
			flags = meta.enmum_ids_set('attr_flags','PK', true, flags)
		where id = i_tmp;
	else
		update meta.attribute set
			flags = meta.enmum_ids_set('attr_flags','RO', true, flags)
		where entity_id = v_sheet.id;
	end if;
  end if;

  return jsonb_build_object('guid', v_sheet.guid, 'table_name', v_sheet.name);
end
$meta_sheet_set_pg__2026_08_07$;


create function meta.int2guid(x bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
AS $meta_int2guid__2026_08_10$
declare
 s varchar(36);
begin
 s = lpad(to_hex(x), 16, '0');
 s = left(s,4)||'0000-dcba-1001-abcd-'||right(s,12);
 return s::uuid;
end
$meta_int2guid__2026_08_10$;

create function data.sheet_get_pg(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_sheet_get_pg__2026_08_04$
declare
   v_table record;
   v_fld record;
   v_tmp text='';
   v_query text='';
   v_debug boolean;
   v_ret jsonb;
begin
   select quote_ident(n.nspname)||'.'||quote_ident(c.relname) "name", t.oid, t.id, v.guid version_guid, e.guid
   into v_table
   from meta.pg_table t
   inner join pg_catalog.pg_class c on c.oid = t.oid
   inner join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   inner join meta.entity e on e.id = t.id
   inner join meta.version v on v.id = e.version_id
   where e.guid = (f_params->>'guid')::uuid;

   if v_table.id is null then
   	 return jsonb_build_object('error', 'Таблица не найдена');
   end if;

   v_debug = coalesce((f_params->>'debug')::boolean, false);

   for v_fld in
   	 select a.name, t.key as type_code, pk.id = any(a.flags) is_key
	 from meta.attribute a
	 inner join meta.enum pkt on pkt.parent_id is null and pkt.key = 'attr_flags'
	 inner join meta.enum pk on pk.parent_id = pkt.id and pk.key = 'PK'
	 inner join meta.data_type t on t.id = a.type_id
	 left join jsonb_array_elements_text(f_params->'fields') f on f=a.name
	 where a.entity_id = v_table.id and (
	   not(f_params ? 'fields') or
	   (f is not null) or
	   (pk.id = any(a.flags))
	 )
	 order by a.npp
   loop
     if v_fld.is_key and v_fld.type_code = 'I' then
	 	v_tmp = format(' meta.int2guid(t.%s) ', quote_ident(v_fld.name));
	 elseif v_fld.is_key and v_fld.type_code = 'G' then
	 	v_tmp = format(' t.%s ', quote_ident(v_fld.name));
	 end if;
	 if v_query!='' then
	 	v_query = v_query||', ';
	 end if;

	 if v_debug then
	 	v_query = v_query||'t.'||quote_ident(v_fld.name);
	 else
	 	v_query = format($q$%s '%s', t.%s$q$, v_query, v_fld.name, quote_ident(v_fld.name));
	 end if;
   end loop;

   if f_params ? 'filter' or f_params ? 'order' or f_params ? 'limit' or f_params ? 'offset' then
   	  v_ret = data.filter_query_get(f_params);
   else
   	  v_ret = jsonb_build_object();
   end if;

   if v_debug then
   	  if v_tmp!='' then
	  	v_tmp = v_tmp||'as "PK_GUID", ';
	  end if;
   	  v_query = format($q$select %s row_number() over(%s) as "ROW_NUMBER", %s
from %s t $q$, v_tmp, v_ret->>'order', v_query, v_table."name");
   else
      v_query = format($q$select %s as guid, row_number() over(%s) npp, jsonb_build_object(%s) "data"
from %s t $q$, v_tmp, v_ret->>'order', v_query, v_table."name");
   end if;

   if coalesce(v_ret->>'where','')!='' then
   	 v_query = v_query||$q$
where $q$||(v_ret->>'where');
   end if;

   if coalesce(v_ret->>'order','')!='' then
   	 v_query = v_query||$q$
$q$||(v_ret->>'order');
   end if;

   if v_debug then
   	 return jsonb_build_object('query', v_query);
   else
   	 v_query = 'select array_to_json(array_agg(row_to_json(x)))::jsonb from('||v_query||') x';
   	 execute v_query into v_ret;
   end if;

   return jsonb_build_object(
	 'guid', v_table.guid,
	 'version_guid', v_table.version_guid,
	 'rows', v_ret
   );
end
$data_sheet_get_pg__2026_08_04$;

create function data.sheet_set_pg(f_params jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $data_sheet_set_pg__2026_08_11$
declare
   v_sheet record;
   v_row record;
   v_data record;
   v_counters record;
   v_columns jsonb;
   v_query  text = '';
   v_values text = '';
   to_update boolean;
begin
   if f_params->>'_SYS_INFO_' is null then
	 return jsonb_build_object('error','Функция sheet_set_rvt не предназначена для самостоятельного вызова');
   end if;
   select
	 (f_params->'_SYS_INFO_'->>'id')::bigint id,
	 (f_params->'_SYS_INFO_'->>'version_id')::bigint version_id,
	 (f_params->'_SYS_INFO_'->>'version_staus') version_staus,
	 (f_params->'_SYS_INFO_'->>'version_exists')::boolean version_exists,
	 (f_params->'_SYS_INFO_'->>'guid')::uuid guid,
	 (f_params->'_SYS_INFO_'->>'version_guid')::uuid version_guid,
	 quote_ident(pgt.key_name) as key_name,
	 pgt.key_type,
	 quote_ident(n.nspname)||'.'||quote_ident(c.relname) table_name
   from meta.pg_table pgt
   inner join pg_catalog.pg_class c on c.oid = pgt.oid
   inner join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where pgt.guid = (f_params->'_SYS_INFO_'->>'guid')::uuid
   into v_sheet;
   
   if v_sheet.key_name is null then
     return jsonb_build_object('error','Запись в таблицу невозможна т.к. отсутствует допустимый ключ');
   end if;
   
   v_columns = meta.sheet_get(jsonb_build_object('guid', v_sheet.guid))->'columns';
   select
	 0::bigint "input",
	 0::bigint "deleted",
	 0::bigint "updated",
	 0::bigint "inserted"
   into v_counters;
     
   for v_row in
	  select
		 (x.value->>'guid')::uuid guid,
		 (x.value->'data') "data",
		 coalesce((x.value->>'delete')::boolean, false) to_delete,
		 case when v_sheet.key_type='I' 
		 	then ('x'||left((x.value->>'guid'),4)||right((x.value->>'guid'),12))::bit(64)::bigint::varchar
		 	else quote_literal(x.value->>'guid')||'||::uuid'
		 end "id"
	  from jsonb_array_elements(f_params->'rows') x
   loop
   	 v_counters.input = v_counters.input + 1;
	 if v_row.to_delete and v_row.guid is null then
	 	continue;
	 elseif v_row.to_delete then
	 	v_query = format($q$delete from %s where %s = %s$q$, v_sheet.table_name, v_sheet.key_name, v_row.id); 
		execute v_query;
		v_counters.deleted = v_counters.deleted + 1;
	 	continue;
	 end if;
	 
	 if v_row.guid is null then
	 	to_update = false;
	 else
	   v_query = format($q$select exists(select 1 from %s t where t.%s = %s)$q$, v_sheet.table_name, v_sheet.key_name, v_row.id);
	   execute v_query into to_update;
	 end if;  
	   
	 if to_update then
	 	v_query = format($q$update %s set $q$, v_sheet.table_name);
		v_counters.updated = v_counters.updated + 1;
	 else
	 	v_query = '';
		v_counters.inserted = v_counters.inserted + 1;
	 end if;
		 
	 for v_data in
	 	select quote_ident(c.value->>'name') "name",
			c.value->>'type' "type",
			case when (c.value->>'type') in ('S','G','T','J')
				then quote_literal(v.value)
				else v.value
			end "value"
		from jsonb_each_text(v_row.data) v
		inner join jsonb_array_elements(v_columns) c on (c.value->>'name') = v.key
		where coalesce(c.value->>'editable','')!='false'
	 loop
	 	if to_update then
			v_query = format($q$%s
 %s = %s,$q$, v_query, v_data.name, v_data.value);
		else
			v_query = v_query||v_data.name||',';
			v_values = v_values||v_data.value||',';
		end if;
	 end loop;
	 
	 v_query = left(v_query,length(v_query)-1);
	 
	 if to_update then
	 	v_query = format($q$%s
where %s = %s $q$, v_query, v_sheet.key_name, v_row.id);
	 else
	 	v_values = left(v_values,length(v_values)-1);
		v_query = format($q$insert into %s
(%s)
values
(%s)$q$, v_sheet.table_name, v_query, v_values);
	 end if;
	 
	 execute v_query;
   end loop;

   return row_to_json(v_counters)::jsonb||jsonb_build_object('version_guid',v_sheet.version_guid, 'guid', v_sheet.guid);
end
$data_sheet_set_pg__2026_08_11$;