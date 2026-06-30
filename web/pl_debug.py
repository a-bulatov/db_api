from datetime import datetime
from ab_engine.env import DB_ENV
from ab_engine.db.option import *

class PlDebuger:

    workers = set()

    @classmethod
    def worker(cls, id):
        for wk in cls.workers:
            if wk.id == int(id):
                return wk
        return None

    def __init__(self, proc_oid:int):
        self.created_at=datetime.now()
        self._oid =proc_oid

    @property
    def id(self):
        return int(id(self))

    async def param_list(self):
        async with DB_ENV() as env:
            params = await env.sql("""select p[1] "name", p[2] "type", t.typcategory
                from (
                select string_to_array(trim(x),' ') p, row_number() over() npp from unnest(string_to_array(
                    pg_get_function_arguments($1)
                ,',')) x) x
                left join (
                select unnest "oid", row_number() over() npp from unnest((
                select p.proargtypes from pg_catalog.pg_proc p where p.oid = $1
                ))) t_id on t_id.npp = x.npp
                inner join pg_catalog.pg_type t on t.oid = t_id.oid""", self._oid, OBJECT)
        return params