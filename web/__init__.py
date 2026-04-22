from starlette.responses import  HTMLResponse, Response
from starlette.routing import Route
from mimetypes import guess_type
import zipfile
from ab_engine import register_rpc
from ab_engine.env import DB_ENV
from ab_engine.db.option import *
from inspect import iscoroutinefunction

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
              c.relname||case when inh.inhparent is null then '' else
                ' ('||prns.nspname||'.'||prnt.relname||')'
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
              left join pg_catalog.pg_class prnt on prnt.oid=inh.inhparent
              left join pg_catalog.pg_namespace prns on prns.oid=prnt.relnamespace
              where c.relnamespace = ns.oid and c.relkind in ('r','v','m')
              order by c.relname
            ) x)	
          )) "nodes"
        from pg_catalog.pg_namespace ns
        where ns.nspname !~ '^pg_' and ns.nspname <> 'information_schema'
        order by ns.nspname""")
        return x

    async def do_get_info(self, env, id, **kwargs):
        id =id.split('.', 1)
        match(id[0]):
            case "sh": return await self.schema_info(env, id[1])
            case "functions": return await self.functions_info(env, id[1])
            case "fn": return await self.function_info(env, id[1])
            case "tbl": return await self.table_info(env, id[1])
            case "v": return await self.table_info(env, id[1])
            case "atr": return await self.attribute_info(env, id[1])
        return "????"

    async def schema_info(self, env, id):
        return f"-- схема { id }"

    async def functions_info(self, env, id):
        return f"-- функции { id }"

    async def function_info(self, env, id):
        return f"-- функция { id }"

    async def table_info(self, env, id):
        return f"-- таблица { id }"

    async def view_info(self, env, id):
        return f"-- представление { id }"

    async def mat_view_info(self, env, id):
        return f"-- мат. представление { id }"

    async def attribute_info(self, env, id):
        return f"-- aтрибут { id }"

_PREFIX = ""

def html(file_name):
    with open(file_name) as f:
        page = f.read()
    return page

async def home_page(request):
    x = html("web/api.html")
    return HTMLResponse(x)

async def db_page(request):
    x = html("web/db.html")
    #x = html("web/example1.html")
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
        register_rpc('db', DbAPI)
        ret+=[
            Route(url_prefix+"/db", endpoint=db_page),
            Route(url_prefix+"/fontawesome/{path:path}", endpoint=StaticFiles("web/lib/fontawesome.zip"))
            ]
    return ret
