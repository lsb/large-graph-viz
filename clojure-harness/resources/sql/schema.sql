-- name: create-vertices!
create table if not exists vertices (id integer primary key, name text)

-- name: create-vcollapse!
create table if not exists vcollapse (oldv integer, newv integer, level smallint)

-- name: create-edges!
create table if not exists edges (v1 integer, v2 integer, level smallint, primary key (level, v1, v2))

-- name: create-positions!
create table if not exists positions (v integer, level smallint, x float, y float, primary key (level, v))

-- name: create-boolean-choice!
create temp table boolean_choice as select cast(0 as integer) as b union all select 1

-- name: create-inflight-positions!
create temp table inflight_positions (v integer primary key, x float, y float, unique (x,y))

-- name: create-quadtree!
create temp table quadtree (box_id integer primary key, x_min float, y_min float, x_max float, y_max float, pop int, x_center float, y_center float)

-- name: create-repulsions!
create temp table repulsions (v integer primary key, x_vec float, y_vec float)

-- name: create-attractions!
create temp table attractions (v integer primary key, x_vec float, y_vec float)

-- name: create-forces!
create temp table forces (v integer primary key, x_vec float, y_vec float)
