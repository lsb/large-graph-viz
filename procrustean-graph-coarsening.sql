-- ∃ M, ratio of edges to merge

create table raw_edges (v1 text, v2 text);
create table vertices (id integer primary key, name text);
create table vcollapse (oldv integer, newv integer, level smallint); -- primary key (oldv, level); clustering idx newv;
create table edges (v1 integer, v2 integer, level smallint, primary key (level, v1, v2));
create table degrees(id integer, degree integer, level smallint, primary key (level, id));

256.times {|LEVEL|

insert into degrees
  select id, count(*), LEVEL from
    (select v1 as id from edges where level = LEVEL union all select v2 as id from edges where level = LEVEL)
    group by id;

create temporary table vcollapse1 (oldv integer primary key, newv integer); create index vc1_n on vcollapse1 (newv);

insert into vcollapse1
  select e.v2, e.v1 from
    edges e
    join degrees d1 on e.level = d1.level and d1.id = e.v1
    join degrees d2 on e.level = d2.level and d2.id = e.v2
    where e.level = LEVEL
    order by d1.degree * 1.0 / d2.degree -- * (U(0,1) + N) -- if non-determinism is desired
    limit ceil(select count(*)/ <<<M>>> from edges where level = LEVEL) - 1;

cluster vcollapse1 on vc1_n;

with recursive collapsepaths as
  (select oldv, newv from vcollapse1
    union all
    select older.oldv, newer.newv from vcollapse1 older join collapsepaths newer on newer.oldv = older.newv)
insert into vcollapse
  select oldv, min(newv), LEVEL group by oldv;
insert into edges
  select coalesce(v1.newv, e.v1) newv1, coalesce(v2.newv, e.v2) newv2, LEVEL + 1 from
    edges e
    left join vcollapse v1 on e.level = v1.level and v1.oldv = e.v1
    left join vcollapse v2 on e.level = v2.level and v2.oldv = e.v2
    where e.level = LEVEL and newv1 != newv2
    group by newv1, newv2;

drop table vcollapse1;

}
