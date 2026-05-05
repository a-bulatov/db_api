from ab_engine import Config
from ab_engine.env import DB_ENV
from ab_engine.db import RAW, ONE
from asyncio import run
from web import get_sql


async def main():
    with open(Config("config.yaml").defaults["script"], "r") as f:
        qry = f.readlines()
    async with DB_ENV() as env:
        ver = await env.sql(f"select version()", ONE)
        ver = ver.split(" ", 2)[1].strip().split(".",2)
        ver = f"{ver[0]}.{ver[1]}"
        qry = get_sql(qry, ver)
        while qry:
            q = qry.pop(0)
            await env.sql(q, RAW)
    Config().log("БД инициализирована!")


if __name__=="__main__" :
    run(main())