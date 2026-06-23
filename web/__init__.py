from starlette.responses import  HTMLResponse, Response, JSONResponse
from starlette.routing import Route
from mimetypes import guess_type
import zipfile
import base64
import json
import socket
from ab_engine.env import DB_ENV
from ab_engine.db.option import *
from ab_engine import register_rpc, Config
from .db_api import DbAPI
from .multi_sql import get_sql, MultiQuery
from sse_starlette import EventSourceResponse


_PREFIX = ""  # префикс URL
_DB = ""      # название базы данных с которой работает админка
_FN_SAVE = "" # код кнопки сохранения функции в файл
_FL_MENU = "" # код меню для скрипта БД

def page_replaces(content):
    content=content.replace("{{DB_NAME}}",_DB)
    content=content.replace("{{PREFIX}}",_PREFIX)
    content=content.replace("{{FN_SAVE}}",_FN_SAVE)
    content=content.replace("{{FL_MENU}}",_FL_MENU)
    return content


def check_json(text: str) -> str | None:
    """
    Проверяет синтаксис JSON.
    Возвращает None если ошибок нет, иначе — описание ошибки на русском.
    """
    try:
        json.loads(text)
        return None
    except json.JSONDecodeError as e:
        line = e.lineno
        col = e.colno
        pos = e.pos

        lines = text.split("\n")
        context = ""
        if 0 <= line - 1 < len(lines):
            problem_line = lines[line - 1]
            context = f'\n  {problem_line}'
            if col and col <= len(problem_line) + 1:
                context += f'\n  {" " * (col - 1)}^'

        msg = {
            "Expecting property name enclosed in double quotes":
                "ожидается имя свойства в двойных кавычках, либо лишняя запятая после значения",
            "Expecting value":
                "ожидается значение",
            "Extra data":
                "лишние данные после завершения JSON",
            "Expecting ':' delimiter":
                "ожидается двоеточие после имени свойства",
            "Expecting ',' delimiter":
                "ожидается запятая между элементами",
            "Unterminated string":
                "незакрытая строка",
            "Invalid control character":
                "недопустимый управляющий символ в строке",
            "Invalid \\escape":
                "недопустимая escape-последовательность",
            "Expecting property name":
                "ожидается имя свойства",
            "Expecting object or value":
                "ожидается объект или значение",
            "Expecting object or array":
                "ожидается объект или массив",
        }.get(e.msg, None)

        if msg is not None:
            return f"Строка {line}, позиция {col}: {msg}{context}"

        return f"Строка {line}, позиция {col}: ошибка синтаксиса JSON{context}"


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
                    content = f.read()
                    content = page_replaces(content)
            response = Response(content, media_type=mime)
            await response(scope, receive, send)
        except (KeyError, FileNotFoundError):
            response = Response("Not Found", status_code=404)
            await response(scope, receive, send)

def html(file_name):
    with open(file_name) as f:
        page = f.read()
    return page_replaces(page)

async def home_page(request):
    x = html("web/api.html")
    return HTMLResponse(x)

async def test_page(request):
    x = html("web/merm.html")
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

    global _DB
    if not _DB:
        async with DB_ENV() as env:
            _DB = await env.sql("select current_database()", ONE)
            _DB = socket.gethostname() + " : " + _DB
    if x:=request.query_params.get('sql'):
        x = MultiQuery.worker(x)
        if x:
            return EventSourceResponse(x())
    x = html("web/db.html")
    return HTMLResponse(x)


def json_syntax_check(text="", text_b64=""):
    """
    проверяет текст Json на ошибку
    {
       "text": "текст Json",
       "text_b64": "текст Json в base64 должен быть передан либо этот параметр, либо text"
    }
    """
    if text_b64!="":
        text = base64.b64decode(text_b64).decode("utf-8")
    return check_json(text)


def admin_routes(url_prefix:str="", use_db=True) -> list[Route]:
    global _PREFIX
    _PREFIX=url_prefix
    register_rpc(json_syntax_check)
    ret = [
        Route(url_prefix+"/", endpoint=home_page),
        Route(url_prefix+"/test", endpoint=test_page),
        Route(url_prefix+"/codemirror/{path:path}", endpoint=StaticFiles("web/lib/codemirror.zip")),
        Route(url_prefix+"/mermaid/{path:path}", endpoint=StaticFiles("web/lib/mermaid.zip")),
        Route(url_prefix+"/web_ui/{path:path}", endpoint=StaticFiles("web/lib/web2ui.zip")),
        Route(url_prefix+"/js/{path:path}",  endpoint=StaticFiles("web/js")),
    ]
    if use_db:
        ret+=[
            Route(url_prefix+"/db", endpoint=db_page, methods=["GET","POST"]),
            Route(url_prefix+"/fontawesome/{path:path}", endpoint=StaticFiles("web/lib/fontawesome.zip"))
            ]
        if Config().hasattr("defaults"):
            x = Config().defaults.get("script")
            if x:
                global _FN_SAVE, _FL_MENU
                _FN_SAVE = '<button id="fn-saver" class="w2ui-btn action" onclick="saveFunction()" title="Сохранить"><i class="fas fa-save"></i></button>'
                _FL_MENU = """{ id: 'init.load', text: 'Загрузить скрипт', icon: 'fa fa-folder-open' },
                 { id: 'init.save', text: 'Cохранить скрипт', icon: 'fa fa-save' },
                 { text: '--' },"""
    return ret
