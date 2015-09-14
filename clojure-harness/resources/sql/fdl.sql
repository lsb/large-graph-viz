-- name: raw-edges-to-degree-ordered-vertices!
insert into vertices (name)
  select name from (select v1 as name from raw_edges union all select v2 as name from raw_edges)
    group by name order by count(*) desc

-- name: raw-edges-to-edges!
insert into edges
  select case when v1.id < v2.id then v1.id else v2.id end,
         case when v1.id < v2.id then v2.id else v1.id end,
         0
    from raw_edges e join vertices v1 on e.v1 = v1.name join vertices v2 on e.v2 = v2.name group by e.v1, e.v2;

-- name: vcollapse!
with recursive
  degrees (id, degree) as
    (select id, count(*)
      from (select v1 as id from edges where level = :level union all select v2 as id from edges where level = :level)
      group by id),
  vcollapse1 (oldv, newv) as
    (select e.v2, e.v1
       from edges e join degrees d1 on d1.id = e.v2 join degrees d2 on d2.id = e.v2
       where e.level = :level
       order by d1.degree * 1.0 / d2.degree
       limit (select ceil(cast(count(*) as real) / :m) - 1 from edges where level = :level)),
  collapsepaths (oldv, newv) as
    (select oldv, newv from vcollapse1
       union all
     select older.oldv, newer.newv from vcollapse1 older join collapsepaths newer on newer.oldv = older.newv)
insert into vcollapse
  select oldv, min(newv), :level from collapsepaths group by oldv

-- name: should-collapse-more
select count(*) > :m collapse_more from (select * from edges where level = :level limit :m + 1)

-- name: collapse-edges!
insert into edges
  select coalesce(v1.newv, e.v1) newv1, coalesce(v2.newv, e.v2) newv2, :level + 1
    from edges e left join vcollapse v1 on e.level = v1.level and v1.oldv = e.v1
                 left join vcollapse v2 on e.level = v2.level and v2.oldv = e.v2
    where e.level = :level and newv1 != newv2
    group by newv1, newv2

-- name: randomize-nodes!
insert into inflight_positions select v, random()/power(2,64), random()/power(2,64)
  from (select v1 as v from edges where level = :level union select v2 as v from edges where level = :level)

-- name: rerandomize-inflight-positions!
update inflight_positions set x = random()/power(2,64), y = random()/power(2,64) where v in (select v from inflight_positions order by random() limit 1)

-- name: make-quadtree!
-- SQLite can do neither aggregates on recursive CTEs nor (as of 3.8.11.1) arrays/hash maps,
-- so we trudge through three sub-selects (for now) instead of some ad-hoc heinous text format
with recursive
  boxes (box_id, x_min, y_min, x_max, y_max, pop, x_center, y_center) as
   (select -1, min(x), min(y), max(x) + 1, max(y) + 1, count(*), avg(x), avg(y) from inflight_positions
    union all
    select (box_id + 1) * 4 + is_top.b * 2 + is_right.b,
           case is_right.b when 0 then x_min else (x_min + x_max) / 2 end as new_x_min,
           case is_top.b   when 0 then y_min else (y_min + y_max) / 2 end as new_y_min,
           case is_right.b when 1 then x_max else (x_min + x_max) / 2 end as new_x_max,
           case is_top.b   when 1 then y_max else (y_min + y_max) / 2 end as new_y_max,
           (select count(*) from inflight_positions
             where x between case is_right.b when 0 then x_min else (x_min + x_max) / 2 end
                         and case is_right.b when 1 then x_max else (x_min + x_max) / 2 end
               and y between case is_top.b   when 0 then y_min else (y_min + y_max) / 2 end
                         and case is_top.b   when 1 then y_max else (y_min + y_max) / 2 end),
           (select avg(x) from inflight_positions
             where x between case is_right.b when 0 then x_min else (x_min + x_max) / 2 end
                         and case is_right.b when 1 then x_max else (x_min + x_max) / 2 end
               and y between case is_top.b   when 0 then y_min else (y_min + y_max) / 2 end
                         and case is_top.b   when 1 then y_max else (y_min + y_max) / 2 end),
           (select avg(y) from inflight_positions
             where x between case is_right.b when 0 then x_min else (x_min + x_max) / 2 end
                         and case is_right.b when 1 then x_max else (x_min + x_max) / 2 end
               and y between case is_top.b   when 0 then y_min else (y_min + y_max) / 2 end
                         and case is_top.b   when 1 then y_max else (y_min + y_max) / 2 end)
      from boxes join boolean_choice is_top join boolean_choice is_right where pop > 1)
insert into quadtree select * from boxes where box_id >= 0 and pop > 0

-- name: make-repulsions!
with recursive
  box_repulsions (v, box_id, x_vec, y_vec, is_terminal) as
   (select v, -1, null, null, 0 = 1 from inflight_positions
    union all
    select br_parent.v,
           q.box_id,
           -q.pop * :c * :k * :k / (power(ifp.x - q.x_center, 2) + power(ifp.y - q.y_center, 2)) * (q.x_center - ifp.x),
           -q.pop * :c * :k * :k / (power(ifp.x - q.x_center, 2) + power(ifp.y - q.y_center, 2)) * (q.y_center - ifp.y),
           q.pop = 1 or (q.x_max - q.x_min) / sqrt(power(ifp.x - q.x_center, 2) + power(ifp.y - q.y_center, 2)) > :Ө
      from box_repulsions br_parent
        join quadtree q on not br_parent.is_terminal and q.box_id between (br_parent.box_id + 1) * 4 and (br_parent.box_id + 1) * 4 + 3
        join inflight_positions ifp on br_parent.v = ifp.v and not (q.x_center = ifp.x and q.y_center = ifp.y))
insert into repulsions select v, sum(x_vec), sum(y_vec) from box_repulsions where is_terminal group by v

-- name: make-attractions!
insert into attractions
  select p1.v,
         sum(sqrt(power(p1.x - p2.x, 2) + power(p1.y - p2.y, 2)) / :k * (p2.x - p1.x)),
         sum(sqrt(power(p1.x - p2.x, 2) + power(p1.y - p2.y, 2)) / :k * (p2.y - p1.y))
    from inflight_positions p1 join inflight_positions p2 join edges e
    where e.level = :level and ((e.v1 = p1.v and e.v2 = p2.v) or (e.v1 = p2.v and e.v2 = p1.v))
    group by p1.v

-- name: make-forces!
insert into forces select v, a.x_vec + r.x_vec, a.y_vec + r.y_vec from attractions a join repulsions r using (v)

-- name: graph-energy
select sum(x_vec * x_vec + y_vec * y_vec) as graph_energy from forces

-- name: is-converged
select sum(:step * sqrt(x_vec * x_vec + y_vec * y_vec)) < :k * :tol as is_converged from forces

-- name: replace-inflight-positions!
replace into inflight_positions
  select v, x + x_vec * :step, y + y_vec * :step from inflight_positions join forces using (v)

-- name: land-positions!
insert into positions select v, :level, x, y from inflight_positions

-- name: add-next-positions!
insert into inflight_positions
  select oldv, x_min + random()/power(2,64) * (x_max - x_min), y_min + random()/power(2,64) * (y_max - y_min)
    from vcollapse c join inflight_positions p join quadtree q
    where c.newv = p.v and q.pop = 1 and q.x_center = x and q.y_center = y and c.level = :level

-- name: delete-repulsions!
delete from repulsions

-- name: delete-attractions!
delete from attractions

-- name: delete-forces!
delete from forces

-- name: delete-quadtree!
delete from quadtree

-- name: svg-bounding-box-at-level
select ('<svg width="100%" height="100%" viewBox="' || min(x) || ' ' || min(y) || ' ' || (max(x)-min(x)) || ' ' || (max(y)-min(y)) || '">') as svg
  from positions where level = :level

-- name: svg-nodes-at-level
select '<circle r="0.1%" cx="' || x || '" cy="' || y || '"><title>' ||
  replace(replace(replace(name,'&','&amp;'),'<','&lt;'),'>','&gt;') || '</title></circle>' as circle
  from positions join vertices on positions.v = vertices.id where level = :level

-- name: svg-edges-at-level
select '<line x1="' || p1.x || '" y1="' || p1.y || '" x2="' || p2.x || '" y2="' || p2.y || '" style="stroke: grey; stroke-width: 0.1%; stroke-opacity: 25%"/>' as line
  from positions p1 join positions p2 using (level) join edges e using (level) where e.v1 = p1.v and e.v2 = p2.v and level = :level
