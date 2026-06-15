select meta.sheet_set('{"title":"test",
"guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7",
"columns":[
    {"name": "id", 	"type": "I"},
    {"name": "name","type": "S"},
    {"name": "flag","type": "B"}
]}')

-- {"guid": "16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "version_guid": "4903f726-e23a-4b50-9899-f20528857162"}

select data.sheet_set('{"guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7",
"rows":[
{"data":{"id":1,"name":"aaa", "flag":true}, "guid":"75e8989f-8d03-429e-9233-0e6117880715"},
{"data":{"id":2,"name":"bbb"}, "guid":"3fa7d460-baf9-446b-bc66-f3a8a9db5470"},
{"data":{"id":3,"name":"ccc", "flag":false}, "guid":"30fa5076-de4d-4bab-9bfa-550d2ff1f6dd"}
]}')

select data.sheet_set('{"guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7",
"rows":[
{"data":{"id":1,"name":"aaa-zzz"}, "guid":"75e8989f-8d03-429e-9233-0e6117880715"},
{"data":{"id":2,"name":"bbb"}, "guid":"3fa7d460-baf9-446b-bc66-f3a8a9db5470"}
]}')


select meta.sheet_set('{"title":"refs",
"guid":"631d0a40-3d8d-407e-bd43-d0675fede9fb",
"columns":[
    {"name": "id", 	"type": "I"},
    {"name": "ref","type": "R", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"name"},
    {"name": "data_type","type": "E", "reference":"data_type"}
]}')


select data.sheet_set('{"guid":"631d0a40-3d8d-407e-bd43-d0675fede9fb",
"rows":[
{"data":{"id":1,"ref":"75e8989f-8d03-429e-9233-0e6117880715"}},
{"data":{"id":2,"ref":"30fa5076-de4d-4bab-9bfa-550d2ff1f6dd", "data_type":"S"}}
]}')

select meta.sheet_set('{"title":"multi refs",
"guid":"6ed9a6ea-af93-47ee-bf43-937304e2f663",
"columns":[
    {"name": "id", 	"type": "I"},
    {"name": "ref","type": "M", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"name"}
]}')

select data.sheet_set('{
"guid":"6ed9a6ea-af93-47ee-bf43-937304e2f663",
"rows":[
{"data":{"id":1,"ref":["3fa7d460-baf9-446b-bc66-f3a8a9db5470", "75e8989f-8d03-429e-9233-0e6117880715"]}}
]}')

select meta.sheet_set('{"title":"ext refs",
"guid":"51d4f522-7741-4d18-8b6b-419e07f0368b",
"columns":[
    {"name": "id", 	"type": "I"},
    {"name": "ref_id","type": "R", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"id"},
    {"name": "ref_name","type": "r", "reference":"ref_id", "reference_column":"name"}
]}')

select data.sheet_set('{
"guid":"51d4f522-7741-4d18-8b6b-419e07f0368b",
"rows":[
{"data":{"id":1,"ref_id":"75e8989f-8d03-429e-9233-0e6117880715"}}
]}')


select meta.sheet_set('{"title":"Сопроводительная документация",
"guid":"00000000-0000-0000-0000-000000000005",
"entity_type":"RVT",
"columns":[
    {"name": "title_short", 	"type": "S", "title":"Краткое наименование"},
    {"name": "title", 	"type": "S", "title":"Наименование"}
]}')

select data.sheet_set('{
"guid":"00000000-0000-0000-0000-000000000005",
"rows":[
{"data":{"title_short":"Краткое","title":"Полное"}},
{"data":{"title_short":"док2","title":"Второй документ"}}
]}')