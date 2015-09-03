-- name: create-raw-edges!
create table raw_edges (v1 text, v2 text)

-- name: create-a-ring!
with recursive million (i) as (select 1 union all select i + 1 from million where i < :max)
insert into raw_edges
  select printf('%09i', :max + 1) e1, printf('%09i', 1) e2
    union all
  select printf('%09i',i), printf('%09i',i+1) from million

-- name: angle-stdev
select stdev(current_angle) as stdev from
  (select v,
          degrees(2 * asin(0.5 * sqrt(power(xcur - xprev,2) + power(ycur - yprev,2)) /
                           sqrt(power(xcur - centerx,2) + power(ycur - centery,2)))) as current_angle from
    (select spoke.v,
            spoke.x as xcur, spoke.y as ycur,
            pprev.x xprev, pprev.y yprev,
            avg(hub.x) centerx, avg(hub.y) centery
     from positions hub join positions spoke using (level) join positions pprev using (level)
     where level = :level and spoke.v = (pprev.v % :max) + 1 group by spoke.v))