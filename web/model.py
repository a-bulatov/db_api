from ab_engine.env import DB_ENV
from ab_engine.db.option import ONE, JSON

async def db_model(area):
    async with DB_ENV() as env:
        if area == "db":
            shemas = await env.sql("select array_agg(ns.oid) from pg_catalog.pg_namespace ns where ns.nspname !~ '^pg_' and ns.nspname <> 'information_schema'", ONE)
        else:
            shemas = area.split(".")
            del shemas[0]
        shemas = await env.sql("""with tables as (
          select c.oid, ns.nspname||'.'||c.relname table_name,
            (select array_to_json(array_agg(row_to_json(fld))) from (
               select a.attname as "name",
                    format_type(a.atttypid, a.atttypmod) as "type",
                    a.attnotnull not_null,
                    (select array_agg(distinct f.f) from (
                     select distinct case
                        when idx.indisprimary then 'K'
                        when idx.indisunique then 'U'
                        else null::varchar(1)
                     end f
                     from pg_catalog.pg_index idx
                     where idx.indrelid = c.oid and a.attnum = any(idx.indkey)
                     union all
                     select 'F' f
                     from pg_catalog.pg_constraint cn 
                     where cn.contype = 'f' and a.attnum = any(cn.conkey) and cn.conrelid = c.oid
                    ) f where f.f is not null) idx_flag
               from pg_catalog.pg_attribute a
               where a.attnum > 0 and a.attrelid = c.oid and a.attstattarget!=0
               order by a.attnum
            ) fld ) fields
          from pg_catalog.pg_namespace ns
          inner join pg_catalog.pg_class c on c.relnamespace = ns.oid and c.relkind='r'
          where ns.oid = any($1::oid[])
          order by 1
        ),

        links as (
          select distinct x.table_from, x.table_to, x.col
            from(
            select  t1.table_name table_from, t2.table_name table_to , t1.fields->(cons.conkey[1]-1)->>'name' col
                      from pg_catalog.pg_constraint cons
                      inner join tables t1 on t1.oid = cons.conrelid
                      inner join tables t2 on t2.oid = cons.confrelid
            ) x
        )
        
        select jsonb_build_object(
            'tables',(select jsonb_agg(jsonb_build_object('table', table_name,'fields', fields)) from tables),
            'links',(select jsonb_agg(jsonb_build_object('from', table_from, 'to', table_to, 'col', col)) from links)
        )""", shemas, JSON)

    mermaid = """erDiagram    
    INF.CUSTOMER {
        string name
        string custNumber
        string sector
    }    
    INF.ORDER {
        int orderNumber
        int customer FK
        string deliveryAddress
    }
    INF.LINE-ITEM {
        string productCode
        int quantity
        float pricePerUnit
    }
    INF.CUSTOMER ||--o{ INF.ORDER : places
    INF.ORDER ||--|{ INF.LINE-ITEM : contains"""
    mermaid = "erDiagram\n"

    for x in shemas["tables"]:
        mermaid += f"\n    {x['table']} {{\n"
        for f in x["fields"]:
            t = f["type"]
            t = t.replace("character varying", "varchar").replace("timestamp without time zone","timestamp_wotz").replace("timestamp with time zone","timestamp_wtz")
            t = t.replace("double precision","float")
            t = f["name"].replace(" ","_") + " " + t
            if f["idx_flag"]:
                t += " "
                if "K" in f["idx_flag"]:
                    t += "PK"
                elif "U" in f["idx_flag"]:
                    t += " UK"
                if "F" in f["idx_flag"]:
                    if "K" in f["idx_flag"] or "U" in f["idx_flag"]:
                        t += ","
                    t += "FK"
            mermaid += f'        {t}\n'
        mermaid += "\n    }\n"
    for x in shemas["links"]:
        mermaid += f'    {x["from"]} }}o--o| {x["to"]}:{x["col"]}\n'
    return f"""<html>
  <body>
    <pre class="mermaid">{ mermaid }
    </pre>

    <script type="module">
      import mermaid from '{{{{PREFIX}}}}/mermaid/mermaid.esm.min.mjs';
      mermaid.initialize({{ startOnLoad: true }});
    </script>
  </body>
</html>"""
