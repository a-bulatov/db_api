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

create function meta.enum_id(enum_key varchar(100))
 returns integer
 language sql
 stable
as
$$
select id from meta.enum where parent_id is null and key = enum_key;
$$;
comment on function meta.enum_id(varchar) is 'Возвращает ID перечисления по ключу';

create function meta.enum_keys(enum_key varchar(100))
 returns varchar[]
 language sql
 stable
as
$$
select array_agg(v.key order by v.key asc)
from meta.enum t
inner join meta.enum v on v.parent_id=t.id
where t.parent_id is null and t.key = enum_key;
$$;
comment on function meta.enum_keys(varchar) is 'Возврашает список ключей перечисления';

insert into meta.enum("key", "name")
values
('data_type', 'Типы данных'),
('version_status','Статусы версии')
;

create table meta.data_type ( like meta."enum" including indexes, check(parent_id =  meta.enum_id('data_type')) ) inherits (meta."enum");
alter table meta.data_type add column eav_field char(1) not null;
comment on column meta.data_type.eav_field is 'имя поля в таблице eav, где лежат данные этого типа';
alter table meta.data_type alter column parent_id set default meta.enum_id('data_type');

insert into meta.data_type("key","name","eav_field")
values ('R','Ссылка','r'),
       ('M','Множество ссылок','s'),
       ('I','Целое','i'),
       ('F','Дробное число','f'),
       ('S','Строка','s'),
       ('T','Дата/Время','t'),
       ('B','Логическое значение','i'),
       ('E','Список значений из справочника','s');

insert into meta.enum(key, name, parent_id)
select x.column1, x.column2, meta.enum_id('version_status')
from (values
  ('A', 'Актуальная', 1),
  ('L', 'Заблокирована', 2),
  ('D', 'Черновик', 3),
  ('C', 'Закрыта и отклонена', 3)
) x
order by x.column3;


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
	constraint attribute_name_unique unique(entity_id,"name")
);


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
        if v_column.type_key in ('R','M') then
             select a.id into v_column.ref_attribute_id
             from meta.attribute a
             inner join meta.entity e on e.guid = v_column.ref_guid::uuid and  a.entity_id = e.id and a.name = v_column.ref_names;

             if v_column.ref_attribute_id is null then
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
				 	then jsonb_build_object('reference_guid',c.ref_enum_key)
					else jsonb_build_object()
				 end||case when t.key in ('R','M')
				 	then jsonb_build_object('reference_names',a.name)
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
    (select array_to_json(array_agg(row_to_json(x)))::jsonb from (
        select
          e.guid,
          v.guid version_guid,
          e.title,
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
	f double precision null,
	t timestamp null,
	r bigint references data.row(id) on delete cascade,
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
insert on data.eav for each row execute
!!..9.6!! procedure data.eav_insert();
!!10..!!  function data.eav_insert();

create trigger eav_update_trigger before
update on data.eav for each row execute
!!..9.6!! procedure data.eav_update();
!!10..!!  function data.eav_update();



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
       coalesce(v.status, v1.status) as version_staus,
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
        elseif v_row.type_code = 'R' then
            tmp_value = null;
            select r.id::varchar into tmp_value
            from data.row r
            where r.entity_id=v_row.ref_entity_id and r.guid = v_row.value::uuid;
            if tmp_value is Null then
               return jsonb_build_object('error', format('Для поля %s не нацдена строка по ссылке %s', v_row.name, v_row.value));
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
     v_query = format($q$select x.id, row_number() over (order by x.id)::integer npp
          from (select t.id from data.eav_%s t group by id order by t.id
          %s) x$q$, v_version.id, v_limits);
   end if;

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
begin
   if ((f_params->>'version_guid') is null and (f_params->>'guid') is null) or ((f_params->>'version_guid')::uuid=uuid_nil()) then
      return meta.sheet_list(f_params);
   end if;

   select
       e1.id,
       e1.guid,
       v1.id version_id,
       v1.guid version_guid,
       v1.status
   into v_sheet
   from (select 1) fake
   left join meta.version v on v.guid = (f_params->>'version_guid')::uuid
   left join meta.entity e on  e.guid = (f_params->>'guid')::uuid
   left join meta.version v1 on v1.id = coalesce(v.id, e.version_id)
   left join meta.entity e1 on e1.id=coalesce(v1.entity_id, e.id);

   if v_sheet.id is Null then
       return jsonb_build_object('error',format( 'Таблица %s не существует или нет указанной версии %s.',f_params->>'guid', f_params->>'version_guid'));
   end if;

   with refs as (
       -- получаем список атрибутов с внешними ключами
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
       -- перечисления
       select a.id, e.id version_id, null, null
           from meta.attribute a
           inner join meta.data_type dt on a.type_id = dt.id and dt.key = 'E'
           inner join meta.enum e on e.parent_id is null and e.key = a.ref_enum_key
   )

   select jsonb_agg(
     jsonb_strip_nulls(jsonb_build_object('guid', x.guid, 'data', x.data, 'references', x.refs))
   )
   into v_ret
   from (
   select r.guid,
     -- значения атрибутов
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
         else to_jsonb(eav.s)
     end
     ) "data",
     -- ссылки
     nullif(jsonb_strip_nulls(jsonb_object_agg(atr.name,
     case
       when dt.key ='R' then to_jsonb(geav.guid)
       when dt.key ='E' then to_jsonb(enm.key)
       when dt.key ='M' then to_jsonb(array_to_json(eav.s::uuid[]))
     end
     )), '{}'::jsonb) refs
    from meta.version v
    inner join meta.attribute atr on atr.entity_id = v.entity_id
    inner join meta.data_type dt on dt.id = atr.type_id
    inner join data.row r on r.entity_id = v.entity_id
    inner join data.filter(v.id, f_params) fltr on fltr.id = r.id
    left join  data.eav eav on eav.attribute_id = atr.id and eav.id = r.id and eav.version_id = v.id
    left join refs on refs.id = atr.id
    left join data.eav reav on dt.key in ('R','M') and reav.version_id = refs.version_id and reav.attribute_id=atr.ref_attribute_id and reav.id = eav.r
    left join data.row geav on geav.id = reav.id
    left join meta.enum enm on dt.key = 'E' and enm.parent_id = refs.version_id and enm.key = eav.s
    where v.id = v_sheet.version_id
    group by r.guid, fltr.npp
    order by fltr.npp
   ) x;

   return jsonb_build_object('guid', v_sheet.guid, 'version_guid', v_sheet.version_guid, 'rows', v_ret);
end
$$;
