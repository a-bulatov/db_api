from ab_engine import Config, register_rpc, call_json
from ab_engine.rpc.fnc import Fnc
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from sys import modules
from json5 import loads


async def homepage(request):
    return JSONResponse({'hello': 'world'})


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
    x = loads(x.decode())
    x = await call_json(x)
    return JSONResponse(x)


def init_app(cfg_file):
    """
    Инициализация приложения
    настройка API. API может лежать в инклуде
    """
    cfg = Config(cfg_file, can_include=["API"])
    for x in cfg.API.keys():
        fnc = cfg.API[x]
        match fnc.get("type", "db"):
            case "db":
                register_rpc(x, f"\JSON {fnc['function']}(JSONB)", help=fnc.get('help'))
            case "self":
                mdl = modules[__name__]
                fn = getattr(mdl, fnc['function'])
                register_rpc(x, fn, help = fnc.get('help') )
            case _:
                register_rpc(x, fnc["function"], help = fnc.get('help'))

    return Starlette(debug=True, routes=[
        Route("/", endpoint=homepage),
        Route("/api", endpoint=do_call, methods=['POST'])
    ])


app = init_app("config.yaml")


if __name__=="__main__":
    import uvicorn
    uvicorn.run(app, port=5000, host="0.0.0.0")