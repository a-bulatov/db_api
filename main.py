from ab_engine import Config, register_rpc, call_json, register_rpc_list
from ab_engine.rpc.fnc import Fnc
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from json5 import loads
from web import admin_routes
from os import environ as ENV


def api_help(method=None, **kwarggs):
    """
    Возвращает список методов ecли вызвана без параметров
    Либо информацию о методе, если его имя передано в параметр method
    """
    if method:
        f = Fnc.registry[method]
        return f.help
    lst = [x for x in Fnc.registry]
    return lst


async def do_call(request):
    """
    Вызов метода API
    :param request: параметры JsonRPC
    :return:
    """
    x = await request.body()
    x = x.decode("utf-8")
    x = loads(x)
    x = await call_json(x)
    return JSONResponse(x)


def init_app():
    """
    Инициализация приложения
    настройка API. API может лежать в инклуде
    """
    cfg_file = ENV.get("API_CONFIG", "config.yaml")
    cfg = Config(cfg_file, can_include=["API"], env_map={"DB":"database"})
    register_rpc_list(cfg.API)
    return Starlette(debug=True, routes=[Route("/api", endpoint=do_call, methods=['POST']),]+admin_routes())


app = init_app()


if __name__=="__main__":
    import uvicorn
    uvicorn.run(app, port=5000, host="0.0.0.0")