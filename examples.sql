select meta.sheet_set('{"title":"test",
"guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7",
"columns":[
    {"name": "id", 	"type": "I", "is_unique": true},
    {"name": "name","type": "S", "is_unique": true},
    {"name": "flag","type": "B"}
]}')

select meta.sheet_set('{"title":"refs",
"guid":"631d0a40-3d8d-407e-bd43-d0675fede9fb",
"columns":[
    {"name": "id", 	"type": "I"},
    {"name": "ref","type": "R", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"name"},
    {"name": "data_type","type": "E", "reference":"data_type"}
]}')

select meta.sheet_set('{"title":"multi refs",
"guid":"6ed9a6ea-af93-47ee-bf43-937304e2f663",
"columns":[
    {"name": "id", 	"type": "I"},
    {"name": "ref","type": "M", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"name"}
]}')

select meta.sheet_set('{"title":"Сопроводительная документация",
"guid":"00000000-0000-0000-0000-000000000005",
"entity_type":"RVT",
"columns":[
    {"name": "title_short", "type": "S", "title":"Краткое наименование", "is_unique": true},
    {"name": "title", "type": "S", "title":"Наименование"},
    {"name": "ref_id","type": "R", "reference_guid":"16fd4cba-a57f-4637-bfc8-1a17e0936fe7", "reference_names":"name"}
]}')



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

select data.sheet_set('{"guid":"631d0a40-3d8d-407e-bd43-d0675fede9fb",
"rows":[
{"data":{"id":1,"ref":"75e8989f-8d03-429e-9233-0e6117880715"}},
{"data":{"id":2,"ref":"30fa5076-de4d-4bab-9bfa-550d2ff1f6dd", "data_type":"S"}}
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

select data.sheet_set('{
"guid":"00000000-0000-0000-0000-000000000005",
"rows":[
{"guid":"41aa5e88-09a4-4a93-a159-4e4faf48f3db","data":{"title_short":"Краткое","title":"Полное"}},
{"guid":"21beb85f-120c-48b0-a5e9-a52580757b54","data":{"title_short":"док2","title":"Второй документ","ref_id":"75e8989f-8d03-429e-9233-0e6117880715"}}
]}')


drop schema  if exists demo cascade;

create schema demo;

-- Создание таблицы пользователей
CREATE TABLE demo.users (
   user_id SERIAL PRIMARY KEY,
   username VARCHAR(50) NOT NULL UNIQUE,
   email VARCHAR(100) NOT NULL UNIQUE,
   created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Создание таблицы товаров
CREATE TABLE demo.products (
   product_id SERIAL PRIMARY KEY,
   name VARCHAR(100) NOT NULL,
   price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
   stock_quantity INTEGER NOT NULL DEFAULT 0
);

-- Создание таблицы заказов
CREATE TABLE demo.orders (
   order_id SERIAL PRIMARY KEY,
   user_id INTEGER REFERENCES demo.users(user_id) ON DELETE CASCADE,
   order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
   total_amount NUMERIC(10, 2) DEFAULT 0.00
);

-- Создание таблицы связи "многие ко многим" (товары в заказе)
CREATE TABLE demo.order_items (
   order_item_id SERIAL PRIMARY KEY,
   order_id INTEGER REFERENCES demo.orders(order_id) ON DELETE CASCADE,
   product_id INTEGER REFERENCES demo.products(product_id) ON DELETE RESTRICT,
   quantity INTEGER NOT NULL CHECK (quantity > 0),
   price_at_moment NUMERIC(10, 2) NOT NULL
);

CREATE TABLE demo.rank(
    rank_id uuid primary key default uuid_generate_v4(),
    rank_name varchar(100) not null
);

INSERT INTO demo.rank(rank_id, rank_name)
values('4bc08df4-6b47-497b-b9f7-be8ef4b32366','начдив'),
('54c54dfe-df08-44e4-9824-3069c5ff2c03','ординарец'),
('797b4e81-cccd-4fda-9268-0c35435b239b', 'красноармеец');

insert into demo.users(username, email)
values('Василий Чапаев','chapay@mail.ru'),
('Петька Исаев','petka@mail.ru'),
('Анка Попова','anka@mail.ru');

insert into demo.products(name, price, stock_quantity)
values('пулемет Максим', 370.52,5),
      ('тачанка', 1500.75, 1),
      ('буденовка', 3.50, 99);

with op as (
        select u.user_id, now() d, p.price, p.product_id
        from demo.users u
        inner join demo.products p on p.name = 'буденовка'
        where u.username = 'Петька Исаев'
),
ps as (
    insert into demo.orders(user_id, order_date, total_amount)
    select user_id, d, price from op
    returning demo.orders.order_id
)
insert into demo.order_items(order_id, product_id, quantity, price_at_moment)
select ps.order_id, op.product_id, 1, op.price
from op
inner join ps on true;


--------------------------------
select meta.sheet_set('{
  "title": "ссылка на физику",
  "guid": "3878ff67-2d88-420b-9a5a-329156141f24",
  "columns":[
    {
      "name": "title",
      "type": "S"
    },
    {
      "name": "user_ref",
      "type": "R",
      "reference_column":"username",
      "reference": "0000a1d1-6442-4321-ab8d-0018a2000000"
    },
    {
        "name": "user_dream",
        "type": "R",
        "title": "мечта",
        "reference": "0000a1d1-6442-4321-ab36-08af0f000000",
        "reference_column": "name"
    },
    {
        "name": "rank",
        "type": "R",
        "title": "Звание",
        "reference": "0000a1d1-6442-4321-abde-fef732000000",
        "reference_column": "rank_name"
    }
  ]
}');

select data.sheet_set('{
 "guid": "3878ff67-2d88-420b-9a5a-329156141f24",
 "rows":[{
   "data":{
     "title":"Чапай",
     "user_ref":"00000000-dcba-1001-abcd-000000000001"
   },
   "guid": "82e86b77-6d47-45ee-a10c-9eff7e134314"
 }]
}')