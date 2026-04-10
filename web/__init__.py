from starlette.responses import  FileResponse, Response
from starlette.routing import Route
from mimetypes import guess_type
import zipfile

class ZipStaticFiles:
    def __init__(self, zip_path: str, prefix:str=""):
        self._zip_path = zip_path
        self._prefix = prefix

    async def __call__(self, scope, receive, send):
        # Extract filename from URL path
        path = scope['path'].lstrip('/')
        if path.startswith(self._prefix):
            path = path[len(self._prefix):]
        try:
            with zipfile.ZipFile(self._zip_path, 'r') as z:
                with z.open(path) as f:
                    content = f.read()
                    # Determine media type based on extension if needed
                    response = Response(content, media_type=guess_type(path)[0] or "text/plain")
                    await response(scope, receive, send)
        except (KeyError, FileNotFoundError):
            response = Response("Not Found", status_code=404)
            await response(scope, receive, send)

async def homepage(request):
    return FileResponse(path="web/index.html")

def admin_routes(url_prefix:str="") -> list[Route]:
    return [
        Route(url_prefix+"/", endpoint=homepage),
        Route(url_prefix+"/codemirror/{path:path}", endpoint=ZipStaticFiles("web/codemirror.zip","codemirror/"))
    ]
