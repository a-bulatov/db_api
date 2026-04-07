from ab_engine import Config
from ab_engine.env import DB_ENV
from ab_engine.db import RAW
from asyncio import run


def get_sql(file_name):
    with open(file_name, "r") as f:
        script = f.readlines()
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


async def process(query_list):
    async with DB_ENV() as env:
        while query_list:
            qry = query_list.pop(0)
            await env.sql(qry, RAW)


if __name__=="__main__" :
    qry = get_sql(Config("config.yaml").defaults["script"])
    run(process(qry))