try:
    from .save_struct import DB_Saver, get_params
except:
    from save_struct import DB_Saver, get_params
from yaml import safe_load as yaml_load
from psycopg.errors import UndefinedTable

def quote_ident(identifier: str) -> str:
    """
    Эмулирует поведение PostgreSQL функции quote_ident().
    """
    if identifier is None:
        return "NULL"
    if identifier.startswith('"'):
        return identifier
    # Проверяем, является ли строка валидным идентификатором
    if identifier[0].isalpha():
        lw = identifier.lower()
        if lw in ('abort', 'abs', 'absent', 'absolute', 'access', 'according', 'action', 'ada', 'add', 'admin', 'after',
                  'aggregate', 'all', 'allocate', 'also', 'alter', 'always', 'analyse', 'analyze', 'and', 'any', 'are',
                  'array', 'array_agg', 'array_max_cardinality', 'as', 'asc', 'asensitive', 'assertion', 'assignment',
                  'asymmetric', 'at', 'atomic', 'attribute', 'attributes', 'authorization', 'avg', 'backward', 'base64',
                  'before', 'begin', 'begin_frame', 'begin_partition', 'bernoulli', 'between', 'bigint', 'binary',
                  'bit', 'bit_length', 'blob', 'blocked', 'bom', 'boolean', 'both', 'breadth', 'by', 'cache', 'call',
                  'called', 'cardinality', 'cascade', 'cascaded', 'case', 'cast', 'catalog', 'catalog_name', 'ceil',
                  'ceiling', 'chain', 'char', 'character', 'characteristics', 'characters', 'character_length',
                  'character_set_catalog', 'character_set_name', 'character_set_schema', 'char_length', 'check',
                  'checkpoint', 'class', 'class_origin', 'clob', 'close', 'cluster', 'coalesce', 'cobol', 'collate',
                  'collation', 'collation_catalog', 'collation_name', 'collation_schema', 'collect', 'column',
                  'columns', 'column_name', 'command_function', 'command_function_code', 'comment', 'comments',
                  'commit', 'committed', 'concurrently', 'condition', 'condition_number', 'configuration', 'connect',
                  'connection', 'connection_name', 'constraint', 'constraints', 'constraint_catalog', 'constraint_name',
                  'constraint_schema', 'constructor', 'contains', 'content', 'continue', 'control', 'conversion',
                  'convert', 'copy', 'corr', 'corresponding', 'cost', 'count', 'covar_pop', 'covar_samp', 'create',
                  'cross', 'csv', 'cube', 'cume_dist', 'current', 'current_catalog', 'current_date',
                  'current_default_transform_group', 'current_path', 'current_role', 'current_row', 'current_schema',
                  'current_time', 'current_timestamp', 'current_transform_group_for_type', 'current_user', 'cursor',
                  'cursor_name', 'cycle', 'data', 'database', 'datalink', 'date', 'datetime_interval_code',
                  'datetime_interval_precision', 'day', 'db', 'deallocate', 'dec', 'decimal', 'declare', 'default',
                  'defaults', 'deferrable', 'deferred', 'defined', 'definer', 'degree', 'delete', 'delimiter',
                  'delimiters', 'dense_rank', 'depth', 'deref', 'derived', 'desc', 'describe', 'descriptor',
                  'deterministic', 'diagnostics', 'dictionary', 'disable', 'discard', 'disconnect', 'dispatch',
                  'distinct', 'dlnewcopy', 'dlpreviouscopy', 'dlurlcomplete', 'dlurlcompleteonly', 'dlurlcompletewrite',
                  'dlurlpath', 'dlurlpathonly', 'dlurlpathwrite', 'dlurlscheme', 'dlurlserver', 'dlvalue', 'do',
                  'document', 'domain', 'double', 'drop', 'dynamic', 'dynamic_function', 'dynamic_function_code',
                  'each', 'element', 'else', 'empty', 'enable', 'encoding', 'encrypted', 'end', 'end-exec', 'end_frame',
                  'end_partition', 'enforced', 'enum', 'equals', 'escape', 'event', 'every', 'except', 'exception',
                  'exclude', 'excluding', 'exclusive', 'exec', 'execute', 'exists', 'exp', 'explain', 'expression',
                  'extension', 'external', 'extract', 'false', 'family', 'fetch', 'file', 'filter', 'final', 'first',
                  'first_value', 'flag', 'float', 'floor', 'following', 'for', 'force', 'foreign', 'fortran', 'forward',
                  'found', 'frame_row', 'free', 'freeze', 'from', 'fs', 'full', 'function', 'functions', 'fusion',
                  'general', 'generated', 'get', 'global', 'go', 'goto', 'grant', 'granted', 'greatest', 'group',
                  'grouping', 'groups', 'handler', 'having', 'header', 'hex', 'hierarchy', 'hold', 'hour', 'id',
                  'identity', 'if', 'ignore', 'ilike', 'immediate', 'immediately', 'immutable', 'implementation',
                  'implicit', 'import', 'in', 'including', 'increment', 'indent', 'index', 'indexes', 'indicator',
                  'inherit', 'inherits', 'initially', 'inline', 'inner', 'inout', 'input', 'insensitive', 'insert',
                  'instance', 'instantiable', 'instead', 'int', 'integer', 'integrity', 'intersect', 'intersection',
                  'interval', 'into', 'invoker', 'is', 'isnull', 'isolation', 'join', 'key', 'key_member', 'key_type',
                  'label', 'lag', 'language', 'large', 'last', 'last_value', 'lateral', 'lc_collate', 'lc_ctype',
                  'lead', 'leading', 'leakproof', 'least', 'left', 'length', 'level', 'library', 'like', 'like_regex',
                  'limit', 'link', 'listen', 'ln', 'load', 'local', 'localtime', 'localtimestamp', 'location',
                  'locator', 'lock', 'lower', 'map', 'mapping', 'match', 'matched', 'materialized', 'max', 'maxvalue',
                  'max_cardinality', 'member', 'merge', 'message_length', 'message_octet_length', 'message_text',
                  'method', 'min', 'minute', 'minvalue', 'mod', 'mode', 'modifies', 'module', 'month', 'more', 'move',
                  'multiset', 'mumps', 'name', 'names', 'namespace', 'national', 'natural', 'nchar', 'nclob', 'nesting',
                  'new', 'next', 'nfc', 'nfd', 'nfkc', 'nfkd', 'nil', 'no', 'none', 'normalize', 'normalized', 'not',
                  'nothing', 'notify', 'notnull', 'nowait', 'nth_value', 'ntile', 'null', 'nullable', 'nullif', 'nulls',
                  'number', 'numeric', 'object', 'occurrences_regex', 'octets', 'octet_length', 'of', 'off', 'offset',
                  'oids', 'old', 'on', 'only', 'open', 'operator', 'option', 'options', 'or', 'order', 'ordering',
                  'ordinality', 'others', 'out', 'outer', 'output', 'over', 'overlaps', 'overlay', 'overriding',
                  'owned', 'owner', 'pad', 'parameter', 'parameter_mode', 'parameter_name',
                  'parameter_ordinal_position', 'parameter_specific_catalog', 'parameter_specific_name',
                  'parameter_specific_schema', 'parser', 'partial', 'partition', 'pascal', 'passing', 'passthrough',
                  'password', 'path', 'percent', 'percentile_cont', 'percentile_disc', 'percent_rank', 'period',
                  'permission', 'placing', 'plans', 'pli', 'portion', 'position', 'position_regex', 'power', 'precedes',
                  'preceding', 'precision', 'prepare', 'prepared', 'preserve', 'primary', 'prior', 'privileges',
                  'procedural', 'procedure', 'program', 'public', 'quote', 'range', 'rank', 'read', 'reads', 'real',
                  'reassign', 'recheck', 'recovery', 'recursive', 'ref', 'references', 'referencing', 'refresh',
                  'regr_avgx', 'regr_avgy', 'regr_count', 'regr_intercept', 'regr_r2', 'regr_slope', 'regr_sxx',
                  'regr_sxy', 'regr_syy', 'reindex', 'relative', 'release', 'rename', 'repeatable', 'replace',
                  'replica', 'requiring', 'reset', 'respect', 'restart', 'restore', 'restrict', 'result', 'return',
                  'returned_cardinality', 'returned_length', 'returned_octet_length', 'returned_sqlstate', 'returning',
                  'returns', 'revoke', 'right', 'role', 'rollback', 'rollup', 'routine', 'routine_catalog',
                  'routine_name', 'routine_schema', 'row', 'rows', 'row_count', 'row_number', 'rule', 'savepoint',
                  'scale', 'schema', 'schema_name', 'scope', 'scope_catalog', 'scope_name', 'scope_schema', 'scroll',
                  'search', 'second', 'section', 'security', 'select', 'selective', 'self', 'sensitive', 'sequence',
                  'sequences', 'serializable', 'server', 'server_name', 'session', 'session_user', 'set', 'setof',
                  'sets', 'share', 'show', 'similar', 'simple', 'size', 'smallint', 'snapshot', 'some', 'source',
                  'space', 'specific', 'specifictype', 'specific_name', 'sql', 'sqlcode', 'sqlerror', 'sqlexception',
                  'sqlstate', 'sqlwarning', 'sqrt', 'stable', 'standalone', 'start', 'state', 'statement', 'static',
                  'statistics', 'stddev_pop', 'stddev_samp', 'stdin', 'stdout', 'storage', 'strict', 'strip',
                  'structure', 'style', 'subclass_origin', 'submultiset', 'substring', 'substring_regex', 'succeeds',
                  'sum', 'symmetric', 'sysid', 'system', 'system_time', 'system_user', 'table', 'tables', 'tablesample',
                  'tablespace', 'table_name', 'temp', 'template', 'temporary', 'text', 'then', 'ties', 'time',
                  'timestamp', 'timezone_hour', 'timezone_minute', 'to', 'token', 'top_level_count', 'trailing',
                  'transaction', 'transactions_committed', 'transactions_rolled_back', 'transaction_active',
                  'transform', 'transforms', 'translate', 'translate_regex', 'translation', 'treat', 'trigger',
                  'trigger_catalog', 'trigger_name', 'trigger_schema', 'trim', 'trim_array', 'true', 'truncate',
                  'trusted', 'type', 'types', 'uescape', 'unbounded', 'uncommitted', 'under', 'unencrypted', 'union',
                  'unique', 'unknown', 'unlink', 'unlisten', 'unlogged', 'unnamed', 'unnest', 'until', 'untyped',
                  'update', 'upper', 'uri', 'usage', 'user', 'user_defined_type_catalog', 'user_defined_type_code',
                  'user_defined_type_name', 'user_defined_type_schema', 'using', 'vacuum', 'valid', 'validate',
                  'validator', 'value', 'values', 'value_of', 'varbinary', 'varchar', 'variadic', 'varying', 'var_pop',
                  'var_samp', 'verbose', 'version', 'versioning', 'view', 'views', 'volatile', 'when', 'whenever',
                  'where', 'whitespace', 'width_bucket', 'window', 'with', 'within', 'without', 'work', 'wrapper',
                  'write', 'xml', 'xmlagg', 'xmlattributes', 'xmlbinary', 'xmlcast', 'xmlcomment', 'xmlconcat',
                  'xmldeclaration', 'xmldocument', 'xmlelement', 'xmlexists', 'xmlforest', 'xmliterate',
                  'xmlnamespaces', 'xmlparse', 'xmlpi', 'xmlquery', 'xmlroot', 'xmlschema', 'xmlserialize', 'xmltable',
                  'xmltext', 'xmlvalidate', 'year', 'yes', 'zone'):
            return f'"{identifier}"'

        if (identifier[0] == '_') and all(char.isalnum() or char == '_' for char in identifier) and identifier == lw:
            return identifier

    # Удваиваем существующие двойные кавычки
    escaped = identifier.replace('"', '""')

    # Заключаем в двойные кавычки
    return f'"{escaped}"'


def conv_ident(value) -> str:
    if isinstance(value, (dict, list, set)):
        return ', '.join([str(x) for x in value])
    return quote_ident(str(value))


def quote_literal(value: str) -> str:
    """
    Эмулирует поведение PostgreSQL функции quote_literal().
    """
    if value is None:
        return "NULL"
    value = value.replace("'", "''")
    return f"'{value}'"


def eq(dict1, dict2, *args):
    if len(args) == 0:
        return dict1 == dict2

    def get_val(from_dict, name):
        if name.startswith("#"):
            to_list = True
            name = name[1:]
        else:
            to_list = False
        name = name.split(".", 1)
        val = from_dict.get(name[0])
        if len(name) > 1:
            val = get_val(val, name[1])
        if isinstance(val, str):
            val = val.strip()
        if to_list and not isinstance(val, list):
            val = [val, ]
        return val

    for x in args:
        if get_val(dict1, x) != get_val(dict2, x):
            return False
    return True


class DB_Restore:

    def __init__(self, connection_string: str, silent=False):
        self.db = DB_Saver(connection_string)
        self._db_structure = {}
        self._pattern = {}
        self._query = []
        self._first_constraint = 0
        self._silent = silent

    def find_node(self, part: str, by_node: dict, keys: str | list | tuple, node_list=None):
        """
        поиск в разделе part словаря self._db_structure узла с такими же значениями ключа
        имена полей ключа указаны в keys
        """
        if not node_list:
            if not (node_list := self._db_structure.get(part)):
                return {}
        keys = (keys,) if isinstance(keys, str) else tuple(keys)
        keys = {x: by_node[x] for x in keys}
        for node in node_list:
            eq = True
            for x in keys:
                if keys[x] != node.get(x):
                    eq = False
                    break
            if eq:
                return node
        return {}

    def __call__(self, pattern):
        self._first_constraint = 0
        self._db_structure = self.db()

        self._query = []  # сюда будем добавлять строки запроса
        works = {
            "language": self.language,
            "extension": self.extension,
            "schema": self.schema,
            "type": self.utype,
            "table": self.table,
            "function": self.function,
            "view": self.view,
            "trigger": self.trigger,
            "constraint": self.constraint,
        }
        for x in works:
            if x in pattern:
                if x == "constraint":
                    self._first_constraint = len(self._query)
                f = works[x]
                for item in pattern[x]:
                    f(item)
        return '\n'.join(self._query)

    def __str__(self):
        return "\n\n".join(self._query)

    def language(self, pattern):
        x = self.find_node("language", pattern, "name")
        if not x:
            self._query.append(f"create language {pattern['name']};")

    def extension(self, pattern):
        x = self.find_node("extension", pattern, "name")
        if not x:
            self._query.append(f"create extension {quote_ident(pattern['name'])};")

    def schema(self, pattern):
        x = self.find_node("schema", pattern, "name")
        name = quote_ident(pattern['name'])
        if not x:
            self._query.append(f"create schema {name};")
            x = {"description": None}
        if not eq(pattern, x, "description"):
            self._query.append(f"comment on schema {name} is {quote_literal(pattern.get('description'))};")

    def utype(self,pattern):
        if self.find_node("type", pattern, ("name", "schema")):
            return # чтобы не сломать того что есть в БД - только создание. если что - ручное добавление
        if pattern["type"] == "enum":
            x = ', '.join([quote_literal(x) for x in pattern["defs"]])
            self._query.append(f"create type {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])} as enum ({x});")

    def table(self, pattern):
        if pattern['name']=='"column"':
            ...
        in_db = self.find_node("table", pattern, ("name", "schema"))
        query = ""

        def field_def(item):
            if item["type"].endswith("[]"):
                array = True
                item["type"] = item["type"][:-2]
            else:
                array = False
            txt = f"  {quote_ident(item['name'])} {item['type']}"
            if item.get("size"):
                txt += f"({str(item['size']).replace('.', ',')})"
            if array:
                txt += "[]"
            if item.get("not_null"):
                txt += " not null"
            if item.get("default"):
                txt += f" default {item['default']}"
            return txt

        table = f"table {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}"
        query = ""

        if in_db:
            # дополнение таблицы БД
            for item in pattern["columns"]:
                if item_db := self.find_node("columns", item, "name", in_db["columns"]):
                    tp = item.get("size")
                    if item["type"] != item_db["type"] or tp != item_db.get("size"):
                        tp = f"{item['type']}({str(tp).replace('.', ',')})" if tp else item['type']
                        query += f"alter {table} alter column {quote_ident(item['name'])} set data type {tp};\n"
                    if (tp := item.get("not_null", False)) != item_db.get("not_null", False):
                        tp = "set" if tp else "drop"
                        query += f"alter {table} alter column {quote_ident(item['name'])} {tp} not null;\n"
                    if (tp := item.get("default")) != item_db.get("default"):
                        tp = f"set default {tp}" if tp else "drop default"
                        query += f"alter {table} alter column {quote_ident(item['name'])} {tp};\n"
                else:
                    item_db = {"description": None}
                    query += f"alter {table} add column"
                    query += field_def(item) + ";\n"
                if (tp := item.get("description")) != item_db.get("description"):
                    query += f"comment on column {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}"
                    query += f""".{quote_ident(item['name'])} is '{tp.replace("'","")}';\n"""
        else:
            # создание таблицы БД
            in_db = {"description": None}
            for item in pattern["columns"]:
                if query:
                    query += ",\n"
                query += field_def(item)
            query = f"create {table}(\n{query}\n);\n"
            for item in pattern["columns"]:
                if tp := item.get("description"):
                    query += f"comment on column {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}"
                    query += f""".{quote_ident(item['name'])} is '{tp.replace("'","")}';\n"""

        if (tp := pattern.get("description")) != in_db.get("description"):
            query += f"""comment on {table} is '{tp.replace("'","")}';\n"""
        if query:
            self._query.append(query)

    def function(self, pattern):
        in_db = self.find_node("function", pattern, ("name", "schema"))
        need_drop = False
        if in_db:
            if in_db["language"] != pattern["language"] or in_db.get("options") != pattern.get("options") or len(
                    in_db.get("parameters", [])) != len(pattern.get("parameters", [])):
                need_drop = True
        if in_db and not need_drop:
            # проверка по параметрам
            for p1, p2 in zip(in_db.get("parameters", []), pattern.get("parameters", [])):
                if 'default' in p2 and p2['default'] is None:
                    p2['default'] = 'NULL'
                if p1 != p2:
                    need_drop = True
                    break
        query = ""
        if need_drop:
            for x in in_db.get("parameters", []):
                if query:
                    query += ", "
                query += x["type"]
            query = f"DROP FUNCTION IF EXISTS {quote_ident(in_db['schema'])}.{quote_ident(in_db['name'])}({query});\n"
            self._query.append(query)
        if (not in_db) or need_drop or in_db["language"] != pattern["language"] \
                or in_db["as"] != pattern["as"].strip() \
                or in_db.get("as") != in_db.get("as"):
            query = ""
            for p in pattern.get("parameters", []):
                if query:
                    query += ", "
                query += f"{p['name']} {p['type']}"
                if 'default' in p:
                    p = p['default']
                    query += f" default {p if p else 'NULL'}"
            if pattern.get("returns") == "is procedure":
                is_func = False
                query = f"create or replace procedure {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}({query})\n"
            else:
                is_func = True
                query = f"create or replace function {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}({query})\n"
                if "returns" in pattern:
                    query += f"returns {pattern['returns']}\n"
                elif "returns table" in pattern:
                    ret = ""
                    for x in pattern["returns table"]:
                        if ret:
                            ret += ", "
                        ret += f"{x['name']} {x['type']}"
                    query += f"returns table({ret})\n"
                else:
                    query += f"returns void\n"
            query += f"language {pattern['language']}\n"
            if ret := pattern.get("options"):
                query += ret.replace(",", "\n")
            query += f" as\n$CODE$\n{pattern['as']}\n$CODE$;\n"
        if (p := pattern.get("description")) and (pattern.get("description") != in_db.get("description") or need_drop):
            p2 = ""
            for p1 in pattern["parameters"]:
                if p2:
                    p2 += ", "
                p2 += p1["type"]
            if is_func:
                query += f"comment on function {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}({p2}) is {quote_literal(p)};\n"
            else:
                query += f"comment on procedure {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])}({p2}) is {quote_literal(p)};\n"
        if query:
            self._query.append(query)

    def view(self, pattern):
        in_db = self.find_node("view", pattern, ("name", "schema"))
        if not in_db or pattern["query"].strip() != in_db["query"]:
            m = "material" if pattern.get("is_material") else ""
            query = f"create {m} view {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])} as\n{pattern['query']};\n"
            if in_db:
                m = "material" if in_db.get("is_material") else ""
                query = f"drop {m} view {quote_ident(in_db['schema'])}.{quote_ident(in_db['name'])};\n{query}"
        else:
            query = ""
        d = pattern.get("description")
        if d and d != in_db.get("description"):
            query += f"comment on view {quote_ident(pattern['schema'])}.{quote_ident(pattern['name'])} is {quote_literal(d)};"
        if query:
            self._query.append(query)

    def trigger(self, pattern):
        in_db = self.find_node("trigger", pattern, "name")
        query = ""
        if not in_db or not eq(in_db, pattern, "call", "event", "scope", "function.schema", "function.name",
                               "table.name", "table.schema"):
            if len(in_db) > 0:
                query += f"drop trigger {quote_ident(in_db['name'])} on table {quote_ident(in_db['table']['schema'])}.{quote_ident(in_db['table']['name'])};\n"
            query += f"create trigger {pattern['name']}\n{pattern['call']} {pattern['event']}\n"
            query += f"on {quote_ident(pattern['table']['schema'])}.{quote_ident(pattern['table']['name'])}\n"
            query += f"for each {pattern['type']}\n"
            query += f"execute procedure {quote_ident(pattern['function']['schema'])}.{quote_ident(pattern['function']['name'])}();\n"
        if query:
            self._query.append(query)

    def constraint(self, pattern):
        in_db = self.find_node("constraint", pattern, ("name", "schema"))
        query = f"alter table {quote_ident(in_db['schema'])}.{quote_ident(in_db['table'])} drop constraint {quote_ident(in_db['name'])};\n" if in_db else ""
        query += f"alter table {quote_ident(pattern['schema'])}.{quote_ident(pattern['table'])}\n"
        query += f"add constraint {quote_ident(pattern['name'])}\n"
        q_type = pattern['type'].upper().replace("\n", " ")
        while "  " in q_type:
            q_type = q_type.replace("  ", " ")
        match q_type:
            case "FOREIGN KEY":
                if eq(in_db, pattern, "schema", "table", "columns", "type", "references.schema", "references.table",
                      "references.columns", "on_delete", "on_update"):
                    return
                query += f"foreign key ({conv_ident(pattern['columns'])})\n"
                query += f"references {quote_ident(pattern['references']['schema'])}.{quote_ident(pattern['references']['table'])}"
                query += f"({conv_ident(pattern['references']['columns'])})"
                if x := pattern.get("on_delete"):
                    query += f"\non delete {x}"
                if x := pattern.get("on_update"):
                    query += f"\non update {x}"
                query += ";"
            case "CHECK":
                if eq(in_db, pattern, "schema", "table", "type", "expression"):
                    return
                query += f"check ({pattern['expression']});"
            case _:
                if eq(in_db, pattern, "schema", "table", "#columns", "type"):
                    return
                query += f"{pattern['type']} ({conv_ident(pattern['columns'])});"
        if q_type == "PRIMARY KEY" and self._first_constraint < len(self._query):
            self._query.insert(self._first_constraint, query)
        else:
            self._query.append(query + "\n")

    def call_script(self, script, silent=True):
        line, query, status, buf = "", [], "", ""
        self.db.rollback()

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

        quot = False
        while script:
            ch = get_ch()
            if status:
                if line.endswith(status):
                    status = ""
            else:
                if ch == "'":
                    if len(buf) > 0 and buf[0] == "'":
                        buf = buf[1:]
                        line += "'"
                    else:
                        quot = not quot
                    continue
                elif quot:
                    continue
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
            query.append(line + buf)

        old_len, undefined = 0, []

        while query or undefined:
            if undefined and not query:
                print("\n--- ПОВТОРНАЯ ПОПЫТКА ВЫПОЛНЕНИЯ")
                if old_len and old_len == len(undefined):
                    print("\n\nНЕ УДАЛОСЬ ВЫПОЛНИТЬ ЗАПРОСЫ:\n")
                    for x in undefined:
                        print(x)
                    self.db.rollback()
                    return
                self.db.commit()
                old_len = len(undefined)
                query = undefined
                undefined = []
            q = query.pop(0)
            q = q.strip()
            if q == "":
                continue
            try:
                self.db.sql(q, roll_auto=False)
                if not silent:
                    print(q, flush=True)
                    self.db.commit()
            except UndefinedTable:
                undefined.append(q)
            except Exception as e:
                if q.startswith("comment on ") or q.startswith("create ") or q.startswith("alter "):
                    undefined.append(q)
                else:
                    self.db.rollback()
                    print("\nОШИБКА!!\n")
                    print(f"\n{q}\n")
                    print(e)
                    return
        self.db.commit()
        print("--- OK! ---")


def main(params):
    opts = params.get("options", [])
    generator = DB_Restore(params["database"], "silent" in opts)
    with open(params["file"]) as f:
        pattern = yaml_load(f)
    script = generator(pattern)
    if "run" in opts:
        generator.call_script(script, "silent" in opts)
    elif "silent" not in opts:
        print(script, flush=True)
    elif script:
        "Есть отличия"
    else:
        "Отличий нет"


if __name__ == '__main__':
    params = get_params("""Программа для приведения БД Postgresql к заданной модели.
В параматрах, как минимум должно быть передано имя yaml-файла,
содержащего описание эталонной модели, в этом случае параметры 
соединяния будут взяты из файла ../config.yaml, а результат будет выведен на экран.
    --run - не только вывести скрипт, но и сразу выполнить его
    --silent - не выводить скрипт
Пример:
python3 restore_struct.py "postgresql://1pi-vector03.dev.aorti.tech:5432/deploy?user=postgres&password=postgres" test.yaml --run --silent
""")
    if params:
        main(params)
