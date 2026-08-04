from ab_engine import Config
from ab_engine.db.option import *
from ab_engine.env import DB_ENV
from inspect import iscoroutinefunction
from datetime import datetime
from pathlib import Path
from base64 import b64decode, b64encode
import shutil
from .multi_sql import get_sql, MultiQuery, hdr_data
from .save_struct import DB_Saver
from .restore_struct import DB_Restore
from yaml import safe_dump as yaml_dump, safe_load as yaml_load
from io import StringIO
from re import search
from .pl_debug import PlDebuger

F_CHK = "noitcnuf e"
_VER = None

class DbAPI:
    """
    обработка команд для работы с БД
    """
    _instance = None
    _pg_catalog = None

    def __new__(cls, *args, **kwargs):
        if not DbAPI._instance:
            DbAPI._instance = super().__new__(cls)
        return DbAPI._instance

    async def __call__(self, env, do=None, **kwargs):
        if do is None:
            raise ValueError("Не указан параметр do")
        f = getattr(self,"do_"+do, None)
        if f is None:
            raise NotImplementedError(f"Не реализовано {do}")
        try:
            if iscoroutinefunction(f):
                x =await f(env,**kwargs)
            else:
                x = f(**kwargs)
        except Exception as e:
            Config().log(e)
        return x

    async def do_get_db_objects(self, env, **kwargs):
        nodes = await env.sql("""select 'sh.'||(ns.oid::varchar) id, ns.nspname "text", 'fa fa-table-list' "icon",
(select count(*) from pg_catalog.pg_class c where c.relkind in ('r','v','m') and c.relnamespace=ns.oid) "count",
(select array_agg(row_to_json(x)::jsonb-'nnn') from(
    select 1 nnn, 'functions.'||(ns.oid::varchar) "id", 'Функции' "text",'fa fa-computer' "icon", null "tooltip",
	(select count(*) from pg_catalog.pg_proc p where p.pronamespace = ns.oid) "count",
	(
		select array_to_json(array_agg(row_to_json(fnc))) from (
			select 'fn.'||(p.oid::varchar) id, p.proname "text", 'fa fa-caret-right' "icon",
				(string_to_array(d.description,chr(10)))[1] tooltip
			from pg_catalog.pg_proc p
			left join pg_catalog.pg_description d on p.oid=d.objoid
			where p.pronamespace = ns.oid
			order by 2
		) fnc
	) "nodes"
    union all
    select 3, case 
        when c.relkind='r' then 'tbl.'||(c.oid::varchar)
        when c.relkind='v' then 'v.'||(c.oid::varchar)
        when c.relkind='m' then 'mv.'||(c.oid::varchar)
      end id,
      c.relname||case when inh.inhparent is null then '' 
        when prns.oid = c.relnamespace then ' ('||prnt.relname||')'
        else ' ('||prns.nspname||'.'||prnt.relname||')'
      end "text",
      case 
        when c.relkind='r' then 'fa fa-table'
        when c.relkind='v' then 'fa fa-table-columns'
        when c.relkind='m' then 'fa fa-table-cells-column-lock'
      end "icon",
      (string_to_array(obj_description(c.oid),chr(10)))[1] tooltip,
      (select count(*) from pg_catalog.pg_attribute a where a.attnum > 0 and a.attrelid = c.oid) "count",
      (select array_to_json(array_agg(row_to_json(fld))) from (
         select 'atr.'||(c.oid::varchar)||'.'||(a.attnum::varchar) id, a.attname as "text", 'fa fa-caret-right' "icon",
            (string_to_array(col_description(c.oid, a.attnum),chr(10)))[1] tooltip
         from pg_catalog.pg_attribute a
         where a.attnum > 0 and a.attrelid = c.oid and a.attstattarget!=0 and a.attstattarget!=0
         order by a.attnum
      ) fld ) nodes
      from pg_catalog.pg_class c
      left join pg_catalog.pg_inherits inh on inh.inhrelid = c.oid
      left join pg_catalog.pg_class prnt on prnt.oid=inh.inhparent and inh.inhseqno = 1
      left join pg_catalog.pg_namespace prns on prns.oid=prnt.relnamespace
      where c.relnamespace = ns.oid and c.relkind in ('r','v','m')
      order by 1, 3
      ) x  
    ) "nodes"
from pg_catalog.pg_namespace ns
where ns.nspname !~ '^pg_' and ns.nspname <> 'information_schema'
-- where ns.nspname not in ('pg_catalog', 'information_schema')
order by ns.nspname""")
        tables = await self.pg_catalog(env)

        for schema in nodes:
            if not schema["nodes"]: continue
            for table in schema["nodes"]:
                if table["icon"] not in ("fa fa-table", "fa-table-columns", "fa fa-table-cells-column-lock"): continue
                tables[f'{schema["text"]}.{table["text"].rsplit("(",1)[0].strip()}'] = [x["text"] for x in table["nodes"]]


        schema = await env.sql("select current_database()", ONE)

        exts = await env.sql("""select 'ext.'||e.oid::varchar id, e.extname "text", 'fa fa-cogs' icon from pg_catalog.pg_extension e""")

        usr = await env.sql("""select 'u.'||usesysid::varchar id, usename "text", 'fa fa-user' icon from pg_catalog.pg_user""")

        nodes.insert(0, {"id":"db",
            "text": schema,
            "icon": "fa fa-database",
            "nodes": [
                {"id":"ext", "text":"Расширения", "icon":"fa fa-cog", "nodes":exts},
                {"id":"usr", "text":"Пользователи", "icon":"fa fa-users", "nodes":usr},
            ]
        })

        return {"sidebar": nodes, "tables": tables}

    async def pg_catalog(self, env):
        if DbAPI._pg_catalog is not None:
            return DbAPI._pg_catalog
        d = await env.sql("""select 'pg_catalog.'||c.relname tbl,
         (select array_to_json(array_agg(sa.attname))
          from (
            select a.attname
            from pg_catalog.pg_attribute a
            where a.attnum > 0 and a.attrelid = c.oid and a.attstattarget!=0
            order by a.attnum
          ) sa
         ) flds
        from pg_catalog.pg_namespace n
        inner join pg_catalog.pg_class c on c.relnamespace = n.oid
        where n.nspname = 'pg_catalog' and c.relkind in ('r','v','m')""")

        DbAPI._pg_catalog = {x['tbl']:x['flds'] for x in d}

        return DbAPI._pg_catalog

    async def do_get_info(self, env, id, **kwargs):
        if '.'  in id:
            id =list(id.split('.', 1))
            if '.' not in id[1]:
                id[1] = int(id[1])
        else:
            id =(id,)
        match(id[0]):
            case "sh": return await self.schema_info(env, id[1])
            case "functions": return await self.functions_info(env, id[1])
            case "fn": return await self.function_info(env, id[1])
            case "tbl": return await self.table_info(env, id[1])
            case "v": return await self.view_info(env, id[1])
            case "mv": return await self.view_info(env, id[1])
            case "atr": return await self.attribute_info(env, id[1])
            case "db":  return await self.database_info(env)
            case "ext":  return await self.ext_info(env)
        return "????"

    async def ext_info(self, env):
        x = await env.sql("select array_agg(e.extname) from pg_catalog.pg_extension e", ONE)
        ret = """/*
    Зарегистрированы расшиерния:
"""
        for y in x:
            ret += "        "  +y + "\n"
        ret += "*/"
        return ret

    async def schema_info(self, env, id):
        inf = await env.sql("""select n.nspname "name",
        (select pg_size_pretty(SUM(pg_total_relation_size(c.oid)))
        from pg_catalog.pg_class c
        where  c.relnamespace = n.oid) "size",
        obj_description(n.oid, 'pg_namespace') "comment",
        r.rolname "owner"
        from pg_catalog.pg_namespace n
        inner join pg_catalog.pg_roles r on n.nspowner = r.oid
        where n.oid = $1""", id, ROW, OBJECT)

        ret = f"""-- Схема: {inf.name} владелец: {inf.owner} oid: {id}  занимает: {inf.size}

create schema /*if not exists*/ "{inf.name}";

comment on schema "{inf.name}" is {"NULL" if inf.comment is None else "'"+inf.comment+"'"};

/*

drop schema if exist "{inf.name}" cascade; -- удалить  схему и связанные объекты в других схемах

grant usage on schema "{inf.name}" to <пользователь>; -- дать права на использование схемы
grant create on schema "{inf.name}" to <пользователь>; -- дать права на создание объектов в схеме
grant all on schema "{inf.name}" to <пользователь>; -- дать все права на объекты в схеме

revoke usage on schema "{inf.name}" to <пользователь>; -- отозвать права на использование схемы
revoke create on schema "{inf.name}" to <пользователь>; -- отозвать права на создание объектов в схеме
revoke all on schema "{inf.name}" to <пользователь>; -- отозвать все права на объекты в схеме
"""
        try:
            usr = await env.sql("""select x.rolname, x.create, x.usage
            from (
            select rolname,
              pg_catalog.has_schema_privilege(rolname, $1, 'CREATE') AS "create",
              pg_catalog.has_schema_privilege(rolname, $1, 'USAGE') AS "usage"
            from pg_catalog.pg_roles
            ) x
            where x.create or x.usage""", inf.name, OBJECT)
            ret +="\nПрава на создание объектов:\n" + ", ".join([x.rolname for x in usr if x.create])
            ret +="\n\nПрава на использование объектов:\n" + ", ".join([x.rolname for x in usr if x.usage])
        except  Exception as err:
            ...
        return ret + "\n\n*/"

    async def functions_info(self, env, id):
        ret = await env.sql("""select x.nspname "schema", array_to_json(array_agg(x.defs)) "defs"
        from (
        select '   [ '||p.oid::varchar||' ]  '||p.proname ||' (' || pg_get_function_arguments(p.oid) ||') -> '||t.typname||
            case when  d.description is null then '' else ' -- '||(string_to_array(d.description, chr(10))::varchar[])[1] end
             defs,
            n.nspname 
        from pg_catalog.pg_proc p
        inner join pg_catalog.pg_namespace n on p.pronamespace = n.oid
        inner join pg_catalog.pg_type t on p.prorettype = t.oid
        left join pg_catalog.pg_description d on p.oid = d.objoid
        where p.prokind in ('f', 'p', 'a') and n.oid  = $1 
        order by p.proname) x group by x.nspname""", id,  ROW, OBJECT)
        ret = f"/*\nФункции схемы { ret.schema}:\n\n " + "\n ".join(ret.defs) + "\n\n*/"
        return ret

    async def function_info(self, env, id):
        ret = await env.sql("select pg_get_functiondef($1)",id,ONE)
        return ret

    async def create_table_scripts(self, env, id)->str:
        ret = ""
        defs = await env.sql("""select
                a.attname "name",
                pg_catalog.format_type(a.atttypid, a.atttypmod) "type",
                pg_catalog.col_description(a.attrelid, a.attnum) "description",
                a.attnotnull not_null,
                pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) "default"
            from pg_catalog.pg_attribute a
            left join pg_attrdef ad on a.attrelid = ad.adrelid and a.attnum = ad.adnum
            where a.attnum>0 and a.attrelid = $1 and a.attstattarget!=0
            order by a.attnum""", id, OBJECT)
        for x in defs:
            add_def = True
            if str(x.default).startswith("nextval('"):
                add_def =False
                match x.type:
                    case 'bigint':  ret+=f"    {x.name} bigserial"
                    case 'int':  ret+=f"    {x.name} serial"
                    case 'integer':  ret+=f"    {x.name} serial"
                    case 'smallint':  ret+=f"    {x.name} smallserial"
            else:
                ret+=f"    {x.name} {x.type}"
            if x.not_null:
                ret += " not null"
            if x.default and add_def:
                ret += f" {x.default}"
            ret += ",\n"
        ret = ret[:-2]+"\n); \n"
        defs = await env.sql("""select jsonb_build_object(
            'schema', quote_ident(ns.nspname),
            'table', quote_ident(tbl.relname),
            'name', cons.conname,
            'type', case cons.contype
                when 'c' then 'CHECK'
                when 'f' then 'FOREIGN KEY'
                when 'p' then 'PRIMARY KEY'
                when 'u' then 'UNIQUE'
                when 't' then 'TRIGGER'
                when 'x' then 'EXCLUSION'
                else cons.contype::varchar || '??'
            end
        )
        || case
            when cons.contype = 'c'
                then jsonb_build_object()
                else jsonb_build_object('columns', (
                    select array_agg(quote_ident(x.attname)) from(
                        select fa.attname from (
                        select row_number() over () n, unnest v
                        from unnest(cons.conkey)
                        ) x
                        inner join pg_catalog.pg_attribute fa on fa.attnum = x.v and fa.attrelid=tbl.oid and fa.attstattarget!=0
                        order by x.n
                    ) x
                ))
            end
        || case cons.contype
            when 'f' then jsonb_build_object('references',
                (select jsonb_build_object('schema', quote_ident(tons.nspname), 'table', quote_ident(tot.relname),
                    'columns', (
                        select array_agg(quote_ident(x.attname)) from(
                            select fa.attname from (
                            select row_number() over () n, unnest v
                            from unnest(cons.confkey)
                            ) x
                            inner join pg_catalog.pg_attribute fa on fa.attnum = x.v and fa.attrelid=cons.confrelid and fa.attstattarget!=0
                            order by x.n
                        ) x
                    )
                )
                from pg_catalog.pg_class tot
                inner join pg_catalog.pg_namespace tons on tons.oid = tot.relnamespace
                where tot.oid = cons.confrelid)
            )
            when 'c' then jsonb_build_object('expression', pg_catalog.pg_get_constraintdef(cons.oid, true))
            else jsonb_build_object()
        end as "value"
        from pg_catalog.pg_constraint cons
        inner join pg_catalog.pg_namespace ns on cons.connamespace = ns.oid
        inner join pg_catalog.pg_class tbl on cons.conrelid = tbl.oid
        where TBL.OID = $1""", id)
        for x in defs:
            x = x['value']
            if cl := x.get("columns"):
                x["columns"]=', '.join(cl)
            if x.get("references"):
                x["references"]['columns'] = ', '.join(x["references"]['columns'])
            ret += f"\nalter table {x['schema']}.{x['table']} add constraint {x['name']} "
            match x['type']:
                case "FOREIGN KEY":
                    ret += f"foreign key({x['columns']}) references {x['references']['schema']}.{x['references']['table']}({x['references']['columns']}"
                case "CHECK":
                    ret += f"check ({x['expression']}"
                case _:
                    ret += f" {x['type'].lower()} ({x['columns']}"
            ret+=");\n"
        return ret

    async def table_info(self, env, id):
        t = await env.sql("""select 
          quote_ident(n.nspname)||'.'||quote_ident(r.relname) t,
          quote_ident(pns.nspname)||'.'||quote_ident(pn.relname) p,
          rl.rolname own,
          r.reltuples cnt,
          pg_size_pretty(pg_total_relation_size(r.oid)) sz
        from pg_catalog.pg_class r
        inner join pg_catalog.pg_namespace n on n.oid = r.relnamespace
        inner join pg_roles rl on r.relowner = rl.oid
        left join pg_catalog.pg_inherits inh on inh.inhseqno = 1 and inh.inhrelid = r.oid
        left join pg_catalog.pg_class pn on pn.oid = inh.inhparent
        left join pg_catalog.pg_namespace pns on pns.oid = pn.relnamespace
        where r.oid = $1""", id, ROW)
        if t['cnt'] < 0:
            t['cnt'] = await env.sql(f"select count(*) from only {t['t']}", ONE)
            t['acc'] = ""
        else:
            t['acc'] = "примерно "
        ret = f"-- Таблица: {t['t']} владелец: {t['own']} oid: {id}\n-- {t['acc']}{t['cnt']} строк. занимает: {t['sz']}\n\n"
        ret += f"create table {t['t']} (\n"
        if t['p'] is not None:
            # Унаследованная таблица
            ret +=f"        like {t['p']} including all /* indexes, constraints, defaults, comments */\n) inherits ({t['p']});\n"
        else:
            # Обычные таблицы
            ret += await self.create_table_scripts(env, id)
        ret+=f"""\n/*
drop table {t['t']} cascade; -- для удаленния таблицы со всеми зависимостями\n
truncate table {t['t']} cascade; -- для очистки данных таблицы со всеми зависимостями\n"""

        d = await env.sql("""select array_agg('    '||ns.nspname||'.'||cl1.relname)
        from pg_catalog.pg_constraint co
        inner join pg_catalog.pg_class cl1 on co.conrelid = cl1.oid
        inner join pg_catalog.pg_namespace ns on ns.oid = cl1.relnamespace
        inner join pg_catalog.pg_class cl2 on co.confrelid = cl2.oid
        where co.contype = 'f' and cl2.oid = $1""", id, ONE)

        if d:
            ret += f"\nНа таблицу {t['t']}  ссылаются следующие другие таблицы:\n"+"\n".join(d)+"\n"

        d = await env.sql("""select  array_agg(ns.nspname||'.'||dependent_view)
        from pg_catalog.pg_depend d
        inner join pg_catalog.pg_rewrite r on d.objid = r.oid
        inner join pg_catalog.pg_class dependent_view on d.refobjid = dependent_view.oid
        inner join pg_catalog.pg_namespace ns on ns.oid = dependent_view.relnamespace
        inner join pg_catalog.pg_class source_table on r.ev_class = source_table.oid
        where dependent_view.relkind in ('v', 'm') and d.refobjid = $1""", id, ONE)

        if d:
            ret += f"\nОт таблицы {t['t']} зависят следующие представления:\n"+"\n".join(d)+"\n"

        return ret + "\n*/"

    async def view_info(self, env, id):
        try:
            d = await env.sql("""select v.definition, c.relkind, quote_ident(n.nspname)||'.'||quote_ident(c.relname) as "name"
            from pg_catalog.pg_views v
            inner join pg_catalog.pg_class c on c.relname = v.viewname
            inner join pg_catalog.pg_namespace n on n.oid = c.relnamespace and n.nspname = v.schemaname
            where c.oid = $1""", id, ROW, OBJECT)
        except Exception as e:
            return str(e)
        ret = "материальное " if d.relkind == "m" else ""
        ret = f"-- {ret}представление { id }\ncreate "
        if d.relkind == "m":
            ret += "material "
        ret += f"view {d.name} as(\n{d.definition[:-1]}\n)"

        return ret

    async def attribute_info(self, env, id):
        id, attr = id.split('.')
        attr = await env.sql("""select 
            a.attnum as position,
            quote_ident(a.attname) as attribute_name,
            format_type(a.atttypid, a.atttypmod) as data_type,
            a.attlen as type_length,
            a.attnotnull as is_not_null,
            a.atthasdef as has_default_value,
            col_description(c.oid, a.attnum) as attribute_comment,
            quote_ident(n.nspname)||'.'||quote_ident(c.relname) table_name,
            pg_get_expr(d.adbin, d.adrelid) as column_default
        from pg_catalog.pg_attribute a
        join pg_catalog.pg_class c on a.attrelid = c.oid
        join pg_catalog.pg_namespace n on c.relnamespace = n.oid
        left join  pg_catalog.pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
        where a.attstattarget!=0 and c.oid = $1 and a.attnum = $2 """, id, attr, ROW, OBJECT)
        info = f"""/*
Атрибут {attr.attribute_name} таблицы {attr.table_name}
Тип атрибута: {attr.data_type}
"""
        if attr.type_length>0:
            info +=f"Длина типа атрибута: {attr.type_length}\n"
        if attr.is_not_null:
            info+="Не может быть NULL\n"
        if attr.has_default_value:
            info += f"По умолчанию: {attr.column_default}\n"
        info = f"""{info}*/
        
alter table {attr.table_name} add column {attr.attribute_name} {attr.data_type}"""
        if attr.is_not_null:
            info+=" not null"
        if attr.has_default_value:
            info+=f" default {attr.column_default}"
        info +=";\n"

        if attr.attribute_comment:
            info += f"\ncomment on column {attr.table_name}.{attr.attribute_name} is '{attr.attribute_comment}';\n"
        return info

    async def do_sql(self, env, sql_b64="", sql="", **kwargs):
        await env.rollback()
        sql = sql if sql else b64decode(sql_b64).decode("utf-8")
        global _VER
        if not _VER:
            ver = await env.sql(f"select version()", ONE)
            ver = ver.split(" ", 2)[1].strip().split(".",2)
            _VER = f"{ver[0]}.{ver[1]}"
        sql = get_sql(sql, _VER)
        if len(sql)>1:
            q = MultiQuery(sql)
            return { "id":q.id, "records": None, "columns": None, "notice": None }
        else:
            sql = sql[0]
        notify = []
        err_line = None
        try:
            async with DB_ENV(notify=notify) as env:
                t = datetime.now()
                ret = await env.sql(sql, RAW)
                t = datetime.now() - t
        except Exception as e:
            ret = None
            e = f"\nОШИБКА !!!\n{e}"
            notify.append(e)
            m = search(r'LINE\s+(\d+)', e)
            if m:
                err_line = m.group(1)
        notify.insert(0,f"Время выполнения {t}")
        if isinstance(ret, list) and len(ret):
            ret = hdr_data(ret)
        elif isinstance(ret, int) and ret > 0:
            notify.append(f"Обработано {ret} строк")
            ret = {}
        else:
            ret = {}
        ret["notice"] = "<br>".join(notify)
        ret["id"] = None
        if err_line is not None:
            ret['line'] = err_line
        return ret

    async def database_info(self, env):
        x = await env.sql("""select current_database() "name", pg_size_pretty(pg_database_size(current_database())) "size", version()""",ROW, OBJECT)
        ret = f"""/*
    {x.version}
    
    Текущая база даных: {x.name}
    Размер базы данных: {x.size}
    """
        try:
            x = await env.sql("show config_file", ONE)
            ret += f"\n    Конфигурационный файл: {x}"
            x = await env.sql("show hba_file", ONE)
            ret += f"\n    Настройки сети: {x}"
            x = await env.sql("show data_directory", ONE)
            ret += f"\n    Каталог с данными: {x}"
        except Exception as e:
            ...
        return ret + "\n*/"

    async def do_get_data(self, env, id, **kwargs):
        if not isinstance(id, int):
            id = str(id).split('.')[-1]
            id = int(id)
        query = await env.sql("""select quote_ident(n.nspname)||'.'||quote_ident(r.relname)
        from pg_catalog.pg_namespace n
        inner join pg_catalog.pg_class r on r.relnamespace = n.oid
        where r.oid = $1""", id, ONE)
        query = f"select * from {query} limit 500"
        ret = await self.do_sql(env, sql=query)
        return ret

    def do_save_fn(self, sql_b64:str, **kwargs):
        sql_b64 = b64decode(sql_b64).decode("utf-8").strip()
        if not sql_b64.endswith("$"): return {}
        sql_b64, fname = f'${sql_b64[:-1]}'.rsplit('$', 1)
        fname, sql_b64 = sql_b64[1:].split(f"${fname}$",1)
        fname, fdefs = fname.split("(", 1)
        fl , fname = fname.rsplit(" ", 1) # имя функции без create
        fl = Path(Config().defaults["script"])
        with open(fl, "r") as f:
            data = f.read()
        pos = 0
        while True:
            x = data.find(fname, pos + 1)
            if x < 0:
                pos = None
                break
            pos = x
            x -= 1
            if data[x] not in "\n\r\t ":
                continue
            while data[x] in "\n\r\t ":
                x -= 1
            for c in F_CHK:
                if data[x]==c:
                    x -= 1
                else:
                    break
                if c == "e":
                    x = -1
                    break
            if x < 0:
                break
        if pos is None:
            # функуция не найдена
            left_data = f"{data}\n\ncreate function "
            right_data = ";\n"
        else:
            # в pos начало имени фукнкциии
            left_data = data[:pos]
            data, right_data = data[pos:].split("$", 1)
            data, right_data = right_data.split("$", 1)
            # в data ограничитель строки без $
            data, right_data = right_data.split(f"${data}$", 1)
        # в left_data то что должно быть до имени функции, в right_data то что после функции
        x = f"${fname.replace('.','_')}__{datetime.now().strftime('%Y_%m_%d')}$"
        # !!Доделать!! обработку ситуации, когда у функции есть комментарий
        data = left_data + fname + "(" + fdefs + x + sql_b64 + x + right_data
        self.do_save_script(data=data)
        return {}

    @staticmethod
    def do_save_script(sql_b64=None, data=None, **kwargs):
        if data is None:
            data = b64decode(sql_b64).decode("utf-8").strip()
        fl = Path(Config().defaults["script"])
        shutil.copy(str(fl), str(fl.parent / f"{fl.stem} bak_{datetime.now().strftime('%Y_%m_%d_%H_%M_%S')}{fl.suffix}"))
        with open(fl, "w") as f:
            f.write(data.strip())

    @staticmethod
    def do_load_script(**kwargs):
        fl = Path(Config().defaults["script"])
        with open(fl, "r") as f:
            data = f.read()
        return data

    @staticmethod
    def do_save_struct(**kwargs):
        db = Config().database
        sav = DB_Saver(db)
        db = sav()
        with StringIO() as f:
            yaml_dump(dict(db), f, encoding=False, allow_unicode=True, sort_keys=False)
            db = f.getvalue()
        return db

    @staticmethod
    def do_check_struct(data_64, **kwargs):
        data_64 = b64decode(data_64).decode("utf-8").strip()
        #return data_64
        db = Config().database
        rest = DB_Restore(db, True)
        data_64 = yaml_load(data_64)
        db = rest(data_64)
        if db=="":
            db = "/* Отличий не найдено */"
        return db

    async def do_debug(self, env, fn_id=None, dbg_id=None, op="new", **kwargs):
        if op=="new" and dbg_id is None:
            dbg = PlDebuger(fn_id)
            return dbg.id
        dbg = PlDebuger.worker(dbg_id)
        if dbg is None :
            return {"error":"Сеанс не найдён"}
        match(op.lower()):
            case "params":
                x = await dbg.params()
                return x
            case "stop":
                await dbg.stop()
                return {}
        return {"error":"Неизвестная операция"}