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
{"data":{"id":3,"name":"ccc", "flag":false}}
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
    {"name": "ref","type": "R", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"name"}
]}')



select r.guid,
  (SELECT (
  SELECT jsonb_object_agg(e.key, e.value)
  FROM jsonb_array_elements(jsonb_agg(
  case
    when dt.eav_field='s' then json_build_object(atr.name, eav.s)
    when dt.key ='B' then json_build_object(atr.name, eav.i=1)
    when dt.eav_field='i' then json_build_object(atr.name, eav.i)
    when dt.eav_field='f' then json_build_object(atr.name, eav.f)
    when dt.eav_field='t' then json_build_object(atr.name, eav.t)
  end
  )) arr
  CROSS JOIN LATERAL jsonb_each(arr) e)) data
from meta.version v
inner join meta.attribute atr on atr.entity_id = v.entity_id
inner join meta.data_type dt on dt.id = atr.type_id
inner join data.row r on r.entity_id = v.entity_id
left join  data.eav eav on eav.attribute_id = atr.id and eav.id = r.id and eav.version_id = v.id
left join data.row rt on rt.entity_id = v.entity_id
where v.id = 1
group by r.guid