-- ∃ M, ratio of edges to merge

-- This differs from Hu because we only use Edge Collapse,
-- and because we collapse a fixed number of edges per level regardless of topology.

create table raw_edges (v1 text, v2 text);
create table vertices (id integer primary key autoincrement, name text);
create table vcollapse (oldv integer, newv integer, level smallint); -- pk (oldv, level); clustering idx newv;
create table edges (v1 integer, v2 integer, level smallint, primary key (level, v1, v2));

create table positions (v integer, level smallint, x float, y float, primary key (level, v));
create table boolean_choice as select 0 as b union all select 1 as b;

---

insert into vertices (name)
  select name from (select v1 as name from raw_edges union all select v2 as name from raw_edges)
              group by name order by count(*) desc;

insert into edges
  select case when v1.id < v2.id then v1.id else v2.id end,
         case when v1.id < v2.id then v2.id else v1.id end, -- invariant: v2 is not higher degree than v1
         0
         from raw_edges e join vertices v1 on e.v1 = v1.name join vertices v2 on e.v2 = v2.name group by e.v1, e.v2;

256.times {|LEVEL|

with recursive
  degrees (id, degree) as
    (select id, count(*)
      from (select v1 as id from edges where level = LEVEL union all select v2 as id from edges where level = LEVEL)
      group by id),
  vcollapse1 (oldv, newv) as
    (select e.v2, e.v1         -- easier order due to aforementioned invariant
       from edges e join degrees d1 on d1.id = e.v1 join degrees d2 on d2.id = e.v2
       where e.level = LEVEL
       order by d1.degree * 1.0 / d2.degree -- * (U(0,1) + N) -- if non-determinism is desired
       limit (select ceil(cast(count(*) as real) / M) - 1 from edges where level = LEVEL)),
  collapsepaths (oldv, newv) as
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

}
