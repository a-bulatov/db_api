from datetime import datetime
from ab_engine.env import DB_ENV
from ab_engine.db.option import RAW, ONE
from asyncio import sleep
import asyncio, json


def get_sql(script:list | str, version=None):
    if isinstance (script, str):
        script = script.split("\n")
        for i, x in enumerate(script):
            script[i] = f"{x}\n"
    line, query, status, buf = "", [], "", ""
    if version is not None:
        version = float(version)

    def get_ch():
        nonlocal buf, script, line
        if buf == "":
            if len(script) == 0:
                return ""
            buf = script[0]
            script = script[1:]
            bs = buf.strip()
            if bs.startswith("--") or buf == "":
                buf = ""
                return get_ch()
            elif bs.startswith("!!"):
                if version is None:
                    buf = ""
                    return get_ch()
                bs, buf = bs[2:].split("!!", 1)
                bs = bs.strip()
                while "..." in bs:
                    bs = bs.replace("...","..")
                bs =bs.split("..")
                if len(bs)==3:
                    bs = float(bs[0].strip())<=version<=float(bs[1].strip())
                elif len(bs)==2 and bs[0]=="":
                    bs = version <= float(bs[1])
                elif len(bs)==2 and bs[1]=="":
                    bs = version >= float(bs[0])
                else:
                    bs = False
                if not bs:
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
    while query[-1].strip() in ("", ";"):
        query.pop()
    return query


def hdr_data(ret:list)->dict:
    perc = f"{100 // len(ret[0])}%"
    hdr = []
    for x in ret[0]:
        hdr.append({ "field": x, "text": x, "size": perc, "sortable": True, "searchable": True })
    for n, x in enumerate(ret):
        for a in x:
            if isinstance(x[a],(dict,list)):
                x[a] = json.dumps(x[a], ensure_ascii=False)
        x = json.dumps(x, ensure_ascii=False, default=str)
        x = json.loads(x)
        x["recid"] = n
        ret[n] = x
    ret = {"records": ret, "columns": hdr}
    return ret


class MultiQuery:

    workers = set()

    @classmethod
    def worker(cls, id):
        for wk in cls.workers:
            if wk.id == int(id):
                return wk
        return None

    def __init__(self, queryes):
        MultiQuery.workers.add(self)
        if isinstance(queryes,str):
            queryes = get_sql(queryes)
        self.queryes = queryes
        self.created_at=datetime.now()

    @property
    def id(self):
        return int(id(self))

    async def __call__(self,*args,**kwargs):
        notify, ret = [], None
        try:
            async with DB_ENV(notify=notify) as env:
                while self.queryes:
                    q = self.queryes.pop(0)
                    st = q.split("\n")[:3]
                    if len(st)>2:
                        st[2] = "...."
                    elif st[-1].endswith(";"):
                        st[-1] = st[-1][:-1]

                    st = "<br>".join(st)
                    yield {"data": json.dumps({"type":"query", "val":st})}
                    notify.clear()
                    ret = await env.sql(q, RAW)
                    st = '<br>'.join(notify)
                    if st:
                        yield {"data":json.dumps({'type': 'notify', 'val':st}) }
                    if isinstance(ret, list) and len(ret)==1 and len(ret[0]):
                        ret = ret[0]
                        st = str(ret[tuple(ret.keys())[0]])
                    else:
                        st = ""
                    yield {"data":  json.dumps({"type":"ok", "val":st})}
                if isinstance(ret, list):
                    ret = hdr_data(ret)
                    yield {"data": json.dumps({"type":"ret", "val":ret})}
        except asyncio.CancelledError:
            return
        except Exception as e:
            yield {"data": json.dumps({"type":"error", "val":str(e)})}
        finally:
            yield {"data":json.dumps({"type": "end", "val":""}) }
            await sleep(1)
            MultiQuery.workers.remove(self)
