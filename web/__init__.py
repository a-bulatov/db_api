from starlette.responses import  HTMLResponse, Response, JSONResponse
from starlette.routing import Route
from mimetypes import guess_type
import zipfile
import base64
import json
from ab_engine.env import DB_ENV
from ab_engine.db.option import *
from inspect import iscoroutinefunction
from datetime import datetime

def get_sql(script):
    line, query, status, buf = "", [], "", ""

    def get_ch():
        nonlocal buf, script, line
        if buf == "":
            if len(script) == 0:
                return ""
            buf = script[0]
            script = script[1:]
            if buf.strip().startswith("--") or buf == "":
                buf = ""
                return get_ch()
        ch = buf[0]
        buf = buf[1:]
        line += ch
        return ch

    while script:
        ch = get_ch()
        if status:
            if line.endswith(status):
                status = ""
        elif ch == ";":
            line = line.strip()
            query.append(line)
            line = ""
        elif ch == "$":
            status = "$"
            while script:
                status += get_ch()
                if status.endswith("$"):
                    break
        elif line.endswith("/*"):
            status = "*/"
        elif line.endswith("--"):
            status = "\n"
    if line:
        query.append((line + buf).strip())
    return query


class StaticFiles:
    def __init__(self, zip_path: str):
        self._zip_path = zip_path

    async def __call__(self, scope, receive, send):
        path = scope['path'].lstrip('/').split('/',1)[1]
        mime = guess_type(path)[0] or "text/plain"
        try:
            if self._zip_path.endswith(".zip"):
                with zipfile.ZipFile(self._zip_path, 'r') as z:
                    with z.open(path) as f:
                        content = f.read()
            else:
                with open(f"{self._zip_path}/{path}")as f:
                    content=f.read()
            response = Response(content, media_type=mime)
            await response(scope, receive, send)
        except (KeyError, FileNotFoundError):
            response = Response("Not Found", status_code=404)
            await response(scope, receive, send)

class DbAPI:
    """
    обработка команд для работы с БД
    """
    _instance = None

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
        if iscoroutinefunction(f):
            x =await f(env,**kwargs)
        else:
            x = f(env,**kwargs)
        return x

    async def do_get_db_objects(self, env, **kwargs):
        x = await env.sql("""select 'sh.'||(ns.oid::varchar) id, ns.nspname "text", 'fa fa-table-list' "icon",
          (select array_to_json(
            ARRAY[json_build_object('id','functions.'||(ns.oid::varchar),'text','Функции', 'icon','fa fa-computer','nodes',(
                select array_to_json(array_agg(row_to_json(fnc))) from (
                    select 'fn.'||(p.oid::varchar) id, p.proname "text", 'fa fa-minus' "icon"
                    from pg_catalog.pg_proc p
                    where p.pronamespace = ns.oid
                ) fnc
            ))]||  
            (select array_agg(row_to_json(x)) from(
              select case 
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
              (select array_to_json(array_agg(row_to_json(fld))) from (
                 select 'atr.'||(c.oid::varchar)||'.'||(a.attnum::varchar) id, a.attname as "text", 'fa fa-minus' "icon"
                 from pg_catalog.pg_attribute a
                 where a.attnum > 0 and a.attrelid = c.oid
                 order by a.attnum
              ) fld ) nodes
              from pg_catalog.pg_class c
              left join pg_catalog.pg_inherits inh on inh.inhrelid = c.oid
              left join pg_catalog.pg_class prnt on prnt.oid=inh.inhparent and inh.inhseqno = 1
              left join pg_catalog.pg_namespace prns on prns.oid=prnt.relnamespace
              where c.relnamespace = ns.oid and c.relkind in ('r','v','m')
              order by c.relname
            ) x)	
          )) "nodes"
        from pg_catalog.pg_namespace ns
        -- where ns.nspname !~ '^pg_' and ns.nspname <> 'information_schema'
        where ns.nspname not in ('pg_catalog', 'information_schema')
        order by ns.nspname""")
        return x

    async def do_get_info(self, env, id, **kwargs):
        id =list(id.split('.', 1))
        id[1] = int(id[1])
        match(id[0]):
            case "sh": return await self.schema_info(env, id[1])
            case "functions": return await self.functions_info(env, id[1])
            case "fn": return await self.function_info(env, id[1])
            case "tbl": return await self.table_info(env, id[1])
            case "v": return await self.view_info(env, id[1], False)
            case "mv": return await self.view_info(env, id[1], True)
            case "atr": return await self.attribute_info(env, id[1])
        return "????"

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
        select p.proname ||' (' || pg_get_function_arguments(p.oid) ||') -> '||t.typname||
            case when  d.description is null then '' else ' -- '||(string_to_array(d.description, chr(10))::varchar[])[1] end defs,
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
            ret +=f"        like {t['p']} including all /* indexes, constraints, defaults, comments */\n) inherits ({t['p']});\n"
        else:
            attrs = await env.sql("""select
                a.attname "name",
                pg_catalog.format_type(a.atttypid, a.atttypmod) "type",
                pg_catalog.col_description(a.attrelid, a.attnum) "description",
                a.attnotnull not_null,
                pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) "default"
            from pg_catalog.pg_attribute a
            left join pg_attrdef ad on a.attrelid = ad.adrelid and a.attnum = ad.adnum
            where a.attnum>0 and a.attrelid = $1
            order by a.attnum""", id, OBJECT)
            for x in attrs:
                ret+=f"    {x.name} {x.type}"
                if x.not_null:
                    ret += " not null"
                if x.default:
                    ret += f" {x.default}"
                ret += ",\n"
            ret = ret[:-2]+"\n); \n"
        return ret


    async def view_info(self, env, id, materialized):
        if materialized:
            return f"-- мат. представление { id }"
        return f"-- представление { id }"

    async def attribute_info(self, env, id):
        return f"-- aтрибут { id }"

    async def do_sql(self, env, sql_b64="", sql="", **kwargs):
        env.rollback()
        sql = sql if sql else base64.b64decode(sql_b64).decode("utf-8")
        sql = get_sql(sql)
        notify = []
        try:
            async with DB_ENV(notify=notify) as env:
                t = datetime.now()
                for x in sql:
                    ret = await env.sql(x, RAW)
                t = datetime.now() - t
        except Exception as e:
            ret = None
            notify.append(f"\nОШИБКА !!!\n{e}")
        notify.insert(0,f"Время выполнения {t}")
        if len(sql) == 1 and isinstance(ret, list) and len(ret):
            perc = f"{100 // len(ret[0])}%"
            hdr = []
            for x in ret[0]:
                hdr.append({ "field": x, "text": x, "size": perc, "sortable": True, "searchable": True })
            for n, x in enumerate(ret):
                x = json.dumps(x, ensure_ascii=False, default=str)
                x = json.loads(x)
                x["recid"] = n
                ret[n] = x
            ret = {"records": ret, "columns": hdr, "notice": notify}
        elif len(sql) == 1:
            if isinstance(ret, int) and ret > 0:
                notify.append(f"Обработано {ret} строк")
            ret = {"notice": notify}
        else:
            ret = {"notice": notify}
        ret["notice"] = "\n".join(ret["notice"])
        return ret

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

_PREFIX = "" # префикс URL

def html(file_name):
    with open(file_name) as f:
        page = f.read()
    return page

async def home_page(request):
    x = html("web/api.html")
    return HTMLResponse(x)

async def db_page(request):
    if request.method=="POST": # запрос на выполнение команды в базе данных
        x = await request.json()
        if x.get("method","") != "db":
            return {"error": "Bad method"}
        async with DB_ENV() as env:
            try:
                x = await DbAPI()(env, **x["params"])
                x = {"result": x}
            except Exception as e:
                if env.in_transaction:
                    await env.rollback()
                x = {"error": str(e)}
        return JSONResponse(x)
    x = html("web/db.html")
    async with DB_ENV() as env:
        db = await env.sql("select current_database()", ONE)
    x=x.replace("{{DB_NAME}}",db)
    return HTMLResponse(x)

def admin_routes(url_prefix:str="", use_db=True) -> list[Route]:
    global _PREFIX
    _PREFIX=url_prefix
    ret = [
        Route(url_prefix+"/", endpoint=home_page),
        Route(url_prefix+"/codemirror/{path:path}", endpoint=StaticFiles("web/lib/codemirror.zip")),
        Route(url_prefix+"/web_ui/{path:path}", endpoint=StaticFiles("web/lib/web2ui.zip")),
        Route(url_prefix+"/js/{path:path}",  endpoint=StaticFiles("web/js")),
    ]
    if use_db:
        ret+=[
            Route(url_prefix+"/db", endpoint=db_page, methods=["GET","POST"]),
            Route(url_prefix+"/fontawesome/{path:path}", endpoint=StaticFiles("web/lib/fontawesome.zip"))
            ]
    return ret
