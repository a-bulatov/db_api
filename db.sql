drop schema if exists meta cascade;
drop schema if exists data cascade;

create extension if not exists "uuid-ossp";

create schema "meta"; -----------------------------------------------------------------------------------------

create table meta."enum" (
	id serial not null primary key,
	parent_id integer null references meta."enum"(id) on delete cascade,
	"key" varchar(100) not null,
	"name" varchar(250) null,
	dd timestamp null
);
create unique index meta_enum_uk on meta.enum using btree (coalesce(parent_id, (0)::bigint), key);
comment on table meta."enum" is 'хранилище перечислений';

create function meta.enum_id(enum_key character varying)
 returns bigint
 language sql
 stable
as
$$
select id from meta.enum where parent_id is null and key = enum_key;
$$;

insert into meta.enum("key", "name") values ('data_type', 'Типы данных');

create table meta.data_type ( like meta."enum" including indexes, check(parent_id =  meta.enum_id('data_type')) ) inherits (meta."enum");
alter table meta.data_type add column eav_field char(1) not null;
comment on column meta.data_type.eav_field is 'имя поля в таблице eav, где лежат данные этого типа';

insert into meta.data_type("key","name","eav_field")
values ('R','Ссылка','r'),
       ('I','Целое','i'),
       ('F','Дробное число','f'),
       ('S','Строка','s'),
       ('T','Дата/Время','t'),
       ('B','Логическое значение','i'),
       ('E','Список значений из справочника','s');

create table meta.entity (
	id bigserial not null primary key,
	guid uuid unique default uuid_generate_v4() not null,
	title varchar(250) null
);
comment on table meta.entity is 'список таблиц';
comment on column meta.entity.guid is 'глобальный идентификатор таблицы';
comment on column meta.entity.title is 'наименование таблицы для отображения';

create table meta."version" (
	id bigserial not null primary key,
	guid uuid unique default uuid_generate_v4() not null,
	entity_id integer not null,
	parent_id integer null,
	dt timestamp default now() not null,
	npp smallint null,
	dt_lock timestamp,
	constraint unique_npp unique (entity_id, npp),
	constraint version_npp_check check (npp > 0)
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
	constraint attribute_name_unique unique(entity_id,"name")
);


create function meta.sheet_set(f_params jsonb)
 returns jsonb
 language plpgsql
as $$
declare
    v_sheet record;
    v_column record;
    ret json;
begin
    if coalesce(f_params::varchar,'{}')='{}' then
        return jsonb_build_object('error', 'структура таблицы не задана');
    end if;

    select
        e.id,
        (e.id is null) is_new,
        coalesce((f_params->>'guid')::uuid, e.guid, uuid_generate_v4()) guid,
        coalesce(f_params->>'title', e.title) title,
        coalesce(v.id, e.version_id) from_version_id,
        (e.id is null) or (coalesce((f_params->>'up_version')='true', false)) up_version,
        e.version_id
    into v_sheet
    from (select 1) fake
    left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
    left join meta.entity e on e.version_id = v.id or (v.id is null and e.guid = (f_params->>'guid')::uuid);

    if v_sheet.id is null then
        insert into meta.entity(guid, title)
        values (v_sheet.guid, v_sheet.title)
        returning id into v_sheet.id;
    else
        update meta.entity set
         title = v_sheet.title
        where id = v_sheet.id;
    end if;

    if v_sheet.up_version then
        ret = data.sheet_set(jsonb_build_object('guid', v_sheet.guid, 'version_guid', (f_params->>'version_guid'), 'up_version', true));
        if (ret->>'error') is not null then
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
            (attr.value ->>'reference_guid') ref_guid,
            (('{'||replace(replace(coalesce(attr.value ->>'reference_name', attr.value ->>'reference_names'), '[', ''), ']', '')||'}')::varchar[])[1] ref_names,
            null::bigint ref_attribute_id,
            t.key type_key
        from jsonb_array_elements(f_params->'columns') attr
        left join meta.attribute a on a.entity_id = v_sheet.id and a.name = attr.value ->> 'name'
        left join meta.data_type t on t.key = attr.value ->> 'type'
    loop
        if v_column.type_key = 'R' then
             select a.id into v_column.ref_attribute_id
             from meta.attribute a
             inner join meta.entity e on e.guid = v_column.ref_guid::uuid and  a.entity_id = e.id and a.name = v_column.ref_names;

             if v_column.ref_attribute is null then
                return jsonb_build_object('error', format('Не найден ссылочный атрибут %s для поля %s', v_column.ref_names, v_column.name));
             end if;
        elseif v_column.type_key = 'E' then
             if not exists(select 1 from meta.enum where parent_id is null and "key"=v_column.ref_guid) then
                return jsonb_build_object('error',format('Не найден перечислимый тип %s', v_column.ref_guid));
             end if;
        end if;

        if v_column.id is null then
            insert into meta.attribute(entity_id, name, title, type_id, ref_attribute_id, ref_enum_key)
            values (v_sheet.id, v_column.name, coalesce(v_column.title, v_column.name),
                    v_column.type_id, v_column.ref_attribute_id, v_column.ref_guid);
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


create schema "data"; -----------------------------------------------------------------------------------------

create table "data"."row" (
	id bigserial  primary key,
	entity_id integer not null references meta.entity(id) on delete cascade,
	guid uuid unique default uuid_generate_v4() not null
);

create table "data".eav (
	id bigint not null,
	version_id bigint not null,
	attribute_id bigint not null,
	s text null,
	i bigint null,
	f float8 null,
	t timestamp null,
	r bigint references data.row(id),
	constraint eav_pk primary key (id, version_id, attribute_id)
);

-- триггеры для партиций
create function data.eav_insert()
 returns trigger
 language plpgsql
 security definer
as $$
begin
  execute 'insert into data.eav_' || new.version_id ||' values ($1.*)'
  using new;
  return null;
end
$$;

create function data.eav_update()
 returns trigger
 language plpgsql
 security definer
as $$
begin
  execute 'update data.eav_' || new.version_id ||' set'||
      ' s='||case when new.s is null then 'null' else quote_literal(new.s) end||
      ' i='||case when new.i is null then 'null' else new.i::varchar end||
      ' f='||case when new.f is null then 'null' else new.f::varchar end||
      ' r='||case when new.r is null then 'null' else new.r::varchar end||
      ' t='||case when new.t is null then 'null' else quote_literal(new.t::varchar) end||
      ' where id='||new.id::varchar||' and attribute_id='||new.attribute_id::varchar;
  return null;
end
$$;

create trigger eav_insert_trigger before
insert
    on
    data.eav for each row execute function data.eav_insert();

create trigger eav_update_trigger before
update
    on
    data.eav for each row execute function data.eav_update();


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
       (v.id is not null) version_exists,
       coalesce(e.guid, uuid_generate_v4()) guid,
       coalesce(v.guid, uuid_generate_v4()) version_guid,
       coalesce(f_params->>'title', e.title) title
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on e.version_id = v.id or (v.id is null and e.guid = (f_params->>'guid')::uuid)
   left join meta.version v1 on v1.entity_id = e.id and v1.id = coalesce(v.id, e.version_id);

   if v_sheet.id is Null then
        return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   end if;

   if v_sheet.version_id is Null or coalesce((f_params->>'up_version')='true', false) then
        insert into meta.version(guid, entity_id, parent_id) values (v_sheet.version_guid, v_sheet.id, v_sheet.version_id)
        returning id into v_sheet.version_id;

        -- создание партиции
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
            (dea.id is NUll) new_attr
        from (
            select coalesce((x.value->>'guid')::uuid, uuid_generate_v4()) guid,
                   (x.value->'data') "data",
                   (x.value->>'delete')::boolean to_delete
            from jsonb_array_elements(f_params->'rows') x
        ) rows
        left join jsonb_each_text(rows.data) dat on true
        left join data.row db_rows on db_rows.guid = rows.guid and db_rows.entity_id = v_sheet.id
        left join meta.attribute col on col.entity_id = v_sheet.id and col.name = dat.key
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

        v_row.value = case
            when v_row.type_code = 'B' then case when upper(v_row.value) in ('TRUE','ДА','YES','Y','1','T','Д') then '1' else '0' end
            else v_row.value
        end;

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


create function data.sheet_get(f_params jsonb)
returns jsonb
language plpgsql
as $$
declare
   v_sheet record;
   v_ret jsonb;
begin
   select
       coalesce(v1.entity_id, e.id) id,
       v1.id version_id
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on  e.guid = (f_params->>'guid')::uuid
   left join meta.version v1 on v1.id = coalesce(v.id, e.version_id);

   if v_sheet.id is Null then
       return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   end if;
/*
   with refs as (
        select a.id
        from meta.attribute a
        inner join meta.data_type td on td.id = a.type_id and td."key"='R'
        inner join meta.attribute ato on ato.id = a.ref_attribute_id
        inner join meta.version vto on vto.entity_id = ato.entity_id
        where a.entity_id = v_sheet.id
   )

 */
   return v_ret;
end
$$;
