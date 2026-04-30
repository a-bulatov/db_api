from ab_engine import Config
from ab_engine.env import DB_ENV
from ab_engine.db import RAW
from asyncio import run
from web import get_sql



async def process(query_list):
    async with DB_ENV() as env:
        while query_list:
            qry = query_list.pop(0)
            await env.sql(qry, RAW)


if __name__=="__main__" :
    with open(Config("config.yaml").defaults["script"], "r") as f:
        qry = f.readlines()
    qry = get_sql(qry)
    run(process(qry))