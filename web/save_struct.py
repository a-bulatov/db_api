# Пример строки параметров:
# "postgresql://1pi-vector03.dev.aorti.tech:5432/vector?user=postgres&password=postgres" test.yaml [views]

from psycopg import connect as pg_connect
from psycopg.rows import dict_row
from yaml import safe_dump as yaml_dump, safe_load as yaml_load
from collections import OrderedDict


class DB_Saver:

    def __init__(self, connection_string: str):
        self._conn_str = connection_string
        self._conn = None
        self._schema = None  # список схем для подрезки объектов БД формируется при вызове self.schema

    def sql(self, query: str, roll_auto=True, *args, **kwargs):
        if self._conn is None:
            self._conn = pg_connect(self._conn_str)
        if len(kwargs) > 0:
            args = kwargs
        elif len(args) == 0:
            args = None
        try:
            cur = self._conn.cursor()
            cur.row_factory = dict_row
            cur.execute(query, args)
            if cur.description:
                cur = cur.fetchall()
                return cur
        except Exception as e:
            if roll_auto:
                self.rollback()
            raise e

    def commit(self):
        if self._conn:
            self._conn.commit()
            self.rollback()

    def rollback(self):
        try:
            if self._conn:
                self._conn.close()
        finally:
            self._conn = None

    def language(self):
        return self.sql("""select lanname as "name" from pg_catalog.pg_language
                           where not lanname=any('{internal,c,sql,plpgsql}')""")

    def extension(self):
        return self.sql("""select extname as "name", extversion as "version" 
                           from pg_catalog.pg_extension
                           where extname!='plpgsql'""")

    def schema(self, with_public=False, schema=[]):
        q = """select quote_ident(n.nspname) "name", pg_catalog.obj_description(n.oid, 'pg_namespace') "description"
        from pg_catalog.pg_namespace n
        where n.nspname !~ '^pg_' and n.nspname <> 'information_schema'"""
        if not with_public:
            q += " and n.nspname <> 'public'"
        q = clear_nulls(self.sql(q), ["description"])
        self._schema = tuple(x["name"] for x in q if schema == [] or x["name"] in schema)
        return q

    def table(self, schema=[]):
        if not schema:
            schema = self._schema
        tables = self.sql(f"""select 
                quote_ident(ns.nspname) "schema",
            quote_ident(cl.relname) "name",
            pg_catalog.obj_description(cl.oid, 'pg_class') "description",
            (select array_to_json(array_agg(row_to_json(x)))::jsonb from (
                select
                  a.attname "name",
                  pg_catalog.format_type(a.atttypid, a.atttypmod) "type",
                  pg_catalog.col_description(a.attrelid, a.attnum) "description",
                  a.attnotnull not_null,
                  pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) "default"
                from pg_catalog.pg_attribute a
                left join pg_attrdef ad on a.attrelid = ad.adrelid and a.attnum = ad.adnum
                where a.attnum>0 and a.attrelid = cl.OID
                order by a.attnum
            ) x) "columns",
            case when prns.oid is null then null else
                jsonb_build_object('schema', prns.nspname, 'name', prnt.relname)
            end parent
        from pg_catalog.pg_class cl
        inner join pg_catalog.pg_namespace ns on cl.relnamespace = ns.oid
        left join pg_catalog.pg_inherits inh on inh.inhrelid = cl.oid
        left join pg_catalog.pg_class prnt on prnt.oid = inh.inhparent
        left join pg_catalog.pg_namespace prns on prns.oid = prnt.relnamespace
        where cl.relkind = 'r' and ns.nspname = any('{{{','.join(schema)}}}')
        order by  ns.nspname, cl.relname""")

        for n, x in enumerate(tables):
            tables[n] = fmt_table(tables[n])

        return tables

    def function(self, schema=[]):
        if not schema:
            schema = self._schema
        functions = self.sql(f"""select quote_ident(ns.nspname) "schema",
               quote_ident(p.proname) "name",
               pg_catalog.pg_get_functiondef(p.oid) "body",
               d.description
        from pg_catalog.pg_proc p inner join pg_namespace ns on (p.pronamespace = ns.oid)
        left join pg_catalog.pg_description d on d.objoid = p.oid
        where ns.nspname = any('{{{','.join(schema)}}}')""")

        for fnc in functions:
            prepare_function(fnc)

        return functions

    def view(self, schema=[]):
        if not schema:
            schema = self._schema
        ret = self.sql(f"""select n.nspname as "schema",
           c.relname as "name",
           pg_catalog.obj_description(c.oid, 'pg_class') as "description",
           pg_catalog.pg_get_viewdef(c.oid) as "query",
           c.relkind = 'm' as is_material
        from pg_catalog.pg_class c
        left join pg_catalog.pg_namespace n on n.oid = c.relnamespace
        where c.relkind in ('v','m') and n.nspname = any('{{{','.join(schema)}}}')""")
        for x in ret:
            if x["query"][-1]:
                x["query"] = x["query"][:-1]
            x["query"] = x["query"].strip()
        return ret

    def trigger(self, schema=[]):
        if not schema:
            schema = self._schema
        return self.sql(f"""select x.name, x.call, x.event, x.type,
                   jsonb_build_object('schema', x.action_statement[1], 'name', x.table) as "table",
                   jsonb_build_object('schema', x.schema, 'name', replace(x.action_statement[2],'()','')) as "function"
            from (SELECT c.relname::information_schema.sql_identifier      AS "table",
                         n.nspname::information_schema.sql_identifier      AS "schema",
                         t.tgname::information_schema.sql_identifier       AS "name",
                         CASE t.tgtype::integer & 66
                             WHEN 2 THEN 'BEFORE'::text
                             WHEN 64 THEN 'INSTEAD OF'::text
                             ELSE 'AFTER'::text
                             END::information_schema.character_data       AS "call",
                         em.text::information_schema.character_data       AS "event",
                         CASE t.tgtype::integer & 1
                             WHEN 1 THEN 'ROW'::text
                             ELSE 'STATEMENT'::text
                             END::information_schema.character_data        AS "type",
                         string_to_array(replace("substring"(pg_get_triggerdef(t.oid),
                                             "position"("substring"(pg_get_triggerdef(t.oid), 48), 'EXECUTE PROCEDURE'::text) + 47),
                                 'EXECUTE PROCEDURE ',
                                 '')       , '.')                           AS action_statement,
                         rank()
                         OVER (PARTITION BY (n.nspname::information_schema.sql_identifier), (c.relname::information_schema.sql_identifier),
                             em.num, (t.tgtype::integer & 1), (t.tgtype::integer & 66) ORDER BY t.tgname)::information_schema.cardinal_number AS action_order
                  FROM pg_namespace n,
                       pg_class c,
                       pg_trigger t,
                       (VALUES (4, 'INSERT'::text), (8, 'DELETE'::text), (16, 'UPDATE'::text)) em(num, text)
                  WHERE n.oid = c.relnamespace
                    AND c.oid = t.tgrelid
                    AND (t.tgtype::integer & em.num) <> 0
                    AND NOT t.tgisinternal
                    AND NOT pg_is_other_temp_schema(n.oid)
                    AND (pg_has_role(c.relowner, 'USAGE'::text) OR
                         has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'::text) OR
                         has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'::text))
                    and n.nspname = any('{{{','.join(schema)}}}')
            ) x order by x.action_order""")

    def constraint(self, schema=[]):
        if not schema:
            schema = self._schema
        ret = self.sql(f"""select jsonb_build_object(
                'schema', ns.nspname,
                'table', tbl.relname,
                'name', cons.conname,
                'type', case cons.contype
                    when 'c' then 'CHECK'
                    when 'f' then 'FOREIGN KEY'
                    when 'p' then 'PRIMARY KEY'
                    when 'u' then 'UNIQUE'
                    when 't' then 'TRIGGER'
                    when 'x' then 'EXCLUSION'
                    else cons.contype::varchar || '??'
                end
            )
            || case
                when cons.contype = 'c'
                    then jsonb_build_object()
                    else jsonb_build_object('columns', (
                        select array_agg(x.attname) from(
                            select fa.attname from (
                            select row_number() over () n, unnest v
                            from unnest(cons.conkey)
                            ) x
                            inner join pg_catalog.pg_attribute fa on fa.attnum = x.v and fa.attrelid=tbl.oid
                            order by x.n
                        ) x
                    ))
               end
            || case cons.contype
                when 'f' then jsonb_build_object('references',
                    (select jsonb_build_object('schema', tons.nspname, 'table', tot.relname,
                        'columns', (
                            select array_agg(x.attname) from(
                                select fa.attname from (
                                select row_number() over () n, unnest v
                                from unnest(cons.confkey)
                                ) x
                                inner join pg_catalog.pg_attribute fa on fa.attnum = x.v and fa.attrelid=cons.confrelid
                                order by x.n
                            ) x
                        )
                    )
                    from pg_catalog.pg_class tot
                    inner join pg_catalog.pg_namespace tons on tons.oid = tot.relnamespace
                    where tot.oid = cons.confrelid)
                )
                when 'c' then jsonb_build_object('expression', pg_catalog.pg_get_constraintdef(cons.oid, true))
                else jsonb_build_object()
            end as "value"
        from pg_catalog.pg_constraint cons
        inner join pg_catalog.pg_namespace ns on cons.connamespace = ns.oid
        inner join pg_catalog.pg_class tbl on cons.conrelid = tbl.oid
        where ns.nspname = any('{{{','.join(schema)}}}')""")

        def fmt(params):
            if params["type"] == "CHECK":
                params["expression"] = params["expression"][7:-1]
            return params

        ret = [fmt(x["value"]) for x in ret]
        return ret

    def types(self, schema=[]):
        lst = f"""select
            e.id::bigint,
            n.nspname "schema",
            t.typname "name"
        from (
            select e.enumtypid id
            from pg_catalog.pg_enum e
            group by e.enumtypid) e
        inner join pg_catalog.pg_type t on t.oid = e.id
        inner join pg_catalog.pg_namespace n ON n.oid = t.typnamespace """
        if schema:
            lst += "where n.nspname = any('{{{','.join(schema)}}}')"
        lst = self.sql(lst)

        types = []
        for x in lst:
            vals = self.sql(f"select  e.enumlabel from pg_catalog.pg_enum e where e.enumtypid = {x['id']}")
            vals = [v["enumlabel"] for v in vals]
            types.append({
                "name": x["name"],
                "schema": x["schema"],
                "type": "enum",
                "defs": vals
            })
        return types

    def __call__(self, with_public=False, schema=[]):
        data = OrderedDict()
        if x := self.language():
            data["language"] = x
        if x := self.extension():
            data["extension"] = x
        if x := self.schema(with_public, schema):
            data["schema"] = x
        if x := self.types(schema):
            data["type"] = x
        if x := self.table(schema):
            data["table"] = x
        if x := self.function(schema):
            data["function"] = x
        if x := self.view(schema):
            data["view"] = x
        if x := self.trigger(schema):
            data["trigger"] = x
        if x := self.constraint(schema):
            data["constraint"] = x
        return data


def clear_nulls(data: list, names: list):
    for n, item in enumerate(data):
        lst = [x for x in item if x in names and item[x] is None]
        if lst:
            for x in lst:
                del item[x]
            data[n] = item
    return data


def fmt_table(table: dict) -> dict:
    if not table.get("parent"):
        del table["parent"]
    if not table.get("description"):
        del table["description"]
    for n, col in enumerate(table["columns"]):
        if col["type"] in ("smallint", "integer", "bigint") and str(col["default"]).startswith("nextval("):
            col["type"] = {
                "smallint": "smallserial",
                "integer": "serial",
                "bigint": "bigserial",
            }[col["type"]]
            del col["default"]
        elif not col["default"]:
            del col["default"]
        if not col["description"]:
            del col["description"]
        if "(" in col["type"]:
            tp = col["type"].split("(", 1)
            if tp[0] in ("character varying", "character", "text", "numeric"):
                x = tp[1].split(")", 1)
                col["type"] = f"{tp[0]}{x[1]}"
                x = x[0].replace(",", ".")
                col["size"] = float(x) if "." in x else int(x)
        table["columns"][n] = col
    return table


def prepare_function(fnc):
    body = fnc["body"]
    del fnc["body"]
    x = f"{fnc['schema']}.{fnc['name']}"
    body = body.split(x, 1)[1]
    x, body = body.split(")", 1)
    x += ")"
    fnc["parameters"] = function_parameters(x.strip()[1:-1])
    x, body = body.split(" LANGUAGE ", 1)
    x = x.strip()
    if x == "":
        x = "void"
    else:
        x = x[8:]  # -RETURNS
    if x.startswith("TABLE("):
        tbl = []
        for x in x[6:-1].split(","):
            n, x = x.strip().split(" ", 1)
            tbl.append({"name": n, "type": x})
        fnc["returns table"] = tbl
    else:
        fnc["returns"] = x
    x, body = body.split("AS $", 1)
    x = x.split("\n")
    fnc["language"] = x[0]
    if len(x) > 1:
        del x[0]
        x = ','.join(x)
        if x.endswith(","):
            x = x[:-1]
        if x:
            fnc["options"] = x
    x, body = body.split("$", 1)
    if x:
        if x == "procedure" and fnc["returns"] == "void":
            fnc["returns"] = "is procedure"
        body, x = body.rsplit(f"${x}$", 1)
    else:
        body = body.strip()[:-2]
    fnc["as"] = body.strip()


def function_parameters(param_str):
    def part():
        nonlocal param_str
        p = ""
        q = False
        while param_str != "":
            ch = param_str[0]
            param_str = param_str[1:]
            if ch == "'":
                q = not q
                p += ch
                continue
            elif ch == "," and q:
                p += ch
            elif ch == ",":
                break
            else:
                p += ch
        return p

    ret = []
    while param_str != "":
        param = {}
        x = part()
        param["name"], x = x.strip().split(" ", 1)
        if " DEFAULT " in x:
            param["type"], x = x.split(" DEFAULT ", 1)
            param["default"] = x.split("::")[0].strip()
        else:
            param["type"] = x
        ret.append(param)
    return ret


def get_params(help_text: str) -> dict:
    from sys import argv

    conf = "../config.yaml"
    db = fl = sh = x = None
    opts = []
    for x in argv[1:]:
        if x == "--help":
            print(help_text)
            return None
        elif x.startswith("postgresql://"):
            db = x
        elif x.startswith("["):
            sh = [s.strip() for s in x.replace("[", "").replace("]", "").split(",")]
        elif x.endswith("/config.yaml") or x == "config.yaml":
            conf = x
        elif x.startswith("--"):
            opts.append(x[2:])
        else:
            fl = x
    if not db:
        try:
            with open(conf) as f:
                conf = yaml_load(f)
            conf = conf["database"]
        except Exception as e:
            help()
            print("-------------------------------------")
            print("Не удалось считать конфигурационный файл")
            return None
        from os import environ as ENV

        try:
            conf["host"] = ENV.get("DB_HOST", conf["host"])
            conf["name"] = ENV.get("DB_NAME", conf["name"])
            conf["port"] = str(ENV.get("DB_PORT", conf.get("port", 5432)))
            conf["user"] = ENV.get("DB_USER", conf["user"])
            conf["password"] = ENV.get("DB_HOST", conf["password"])
            db = f'postgresql://{conf["host"]}:{conf["port"]}/{conf["name"]}?user={conf["user"]}&password={conf["password"]}'
        except Exception as e:
            help()
            print("-------------------------------------")
            print("Не удалось получить строку соединения с БД")
            return None

    x = {
        "schema": sh if sh else [],
        "database": db,
        "file": fl
    }
    if opts:
        x["options"] = opts
    return x


if __name__ == '__main__':
    from io import StringIO

    params = get_params("""Программа для сохранения модели БД Postgresql.
Если программе не переданы параметры, то соединение будет взято из ../config.yaml, а результат будет выведен на экран
с помощью параметров можно уточнить что и куда должна сохранять программа
    - соединение с БД:
      postgresql://имя_хоста:порт/имя_БД?user=пользователь&password=пароль
    - cписок схем, которые должны быть сохранены:
      [имя_схемы, ... имя_схемы]
    - имя файла, куда сохранять модель
Пример:
python3 save_struct.py "postgresql://1pi-vector03.dev.aorti.tech:5432/vector?user=postgres&password=postgres" test.yaml [views]
""")

    if params:
        saver = DB_Saver(params["database"])
        db = saver(schema=params["schema"])
        if x := params["file"]:
            with open(x, "w") as f:
                yaml_dump(dict(db), f, encoding=False, allow_unicode=True, sort_keys=False)
        else:
            with StringIO() as f:
                yaml_dump(dict(db), f, encoding=False, allow_unicode=True, sort_keys=False)
                db = f.getvalue()
            print(db)
