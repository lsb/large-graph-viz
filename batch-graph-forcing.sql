-- ∃ K, natural spring length
-- ∃ STEP, fraction of total movement to update
-- ∃ C, relative strength of repulsive force
-- ∃ Ө, distance vs width of cluster in the quadtree
-- ∃ TOL, multiple of spring length less than which the energy of the graph need not descend

-- This differs from Hu because we create every boxm instead of stopping after a fixed number of levels,
-- we move every node simultaneously (this is easier to parallelize on independent cores), and
-- we choose against scaling the coordinates by the (pseudo)diameter γ, and instead scale K by a constant.
-- Also we place the uncollapsed nodes randomly in the box at the leaf of the quadtree
-- corresponding to the node they collapse into, versus at that node's position exactly.

create temp table inflight_positions (v integer primary key, x float, y float);
create index ipxy on inflight_positions (x, y);
create temp table quadtree (box_id integer primary key, parent_id int, pop int,
                            x_min real, y_min real, x_max real, y_max real, x_center real, y_center real);
create temp table forces (v integer primary key, x_vec float, y_vec float);

insert into inflight_positions select v, 256, random()/power(2,64), random()/power(2,64)
    from (select v1 as v from edges where level = 256
            union
          select v2 as v from edges where level = 256);

(256 down to 0).each {|LEVEL|

do {

with recursive
  boxes (box_id, parent_id, pop, x_min, y_min, x_max, y_max, x_center, y_center) as
  (select -1, null, count(*), min(x), min(y),
          1.1 * max(x) - 0.1 * min(x), 1.1 * max(y) - 0.1 * min(y), avg(x), avg(y)
     from positions where level = LEVEL
     union all
   select max(box_id,0)*4 + is_top.b * 2 + is_right.b,
          box_id,
          count(*) as new_pop,
          case is_right.b when 0 then x_min else x_min + (x_max - x_min) / 2 end as new_x_min,
          case is_top.b   when 0 then y_min else y_min + (y_max - y_min) / 2 end as new_y_min,
          case is_right.b when 1 then x_max else x_min + (x_max - x_min) / 2 end as new_x_max,
          case is_top.b   when 1 then y_max else y_min + (y_max - y_min) / 2 end as new_y_max,
          avg(p.x) as x_center,
          avg(p.y) as y_center
     from boxes join boolean_choice as is_top join boolean_choice as is_right join inflight_positions p
     where boxes.pop > 1 and p.x between new_x_min and new_x_max and p.y between new_y_min and new_y_max -- and box_id < 8k...
     group by box_id, is_top.b, is_right.b)
insert into quadtree select * from boxes where box_id >= 0 and pop > 0;

with recursive
  box_repulsions (v, box_id, x_vec, y_vec, is_terminal) as
    (select v, -1, null, null, 0=1 from inflight_positions
       union all
     select br_parent.v,
            q.box_id,
            -q.pop * C * K * K / (power(ifp.x - q.x_center,2) + power(ifp.y - q.y_center,2)) * (q.x_center - ifp.x),
            -q.pop * C * K * K / (power(ifp.x - q.x_center,2) + power(ifp.y - q.y_center,2)) * (q.y_center - ifp.y),
            q.pop = 1 || (q.x_max - q.x_min) / sqrt(power(ifp.x - q.x_center,2) + power(ifp.y - q.y_center,2)) > Ө
       from box_repulsions br_parent join quadtree q on br_parent.box_id = q.parent_id
                                     join inflight_positions ifp on br_parent.v = ifp.v and not (q.x_center = ifp.x and q.y_center = ifp.y))
  terminal_box_repulsions (v, x_vec, y_vec) as
    (select v, sum(x_vec), sum(y_vec) from box_repulsions where is_terminal group by v)
  vertex_attractions (v, x_vec, y_vec) as
    (select ifp.v, sum(sqrt(power(ifp.x - n.x,2) + power(ifp.y - n.y,2)) / K * (n.x - ifp.x)),
                   sum(sqrt(power(ifp.x - n.x,2) + power(ifp.y - n.y,2)) / K * (n.y - ifp.y))
       from inflight_positions ifp join inflight_positions n join edges e
         where e.level = LEVEL and (e.v1 = ifp.v and e.v2 = n.v || e.v1 = n.v and e.v2 = ifp.v)
         group by ifp.v)
insert into forces select v, a.x_vec + r.x_vec, a.y_vec + r.y_vec from vertex_attractions a join terminal_box_repulsions r using (v);

select sum(power(x_vec,2) + power(y_vec,2)) as energy from forces; -- if we need it?
select sum(STEP * sqrt(x_vec * x_vec + y_vec * y_vec)) < K * TOL as converged from forces; -- if we need it

replace into inflight_positions
  select v, x + (x_vec * STEP / sqrt(x_vec * x_vec + y_vec * y_vec)), y + (y_vec * STEP / sqrt(x_vec * x_vec + y_vec * y_vec))
    from inflight_positions join forces using (v);

select * from inflight_positions; -- iterative display during debugging?

STEP <- STEP * 0.9

} until $converged

insert into positions select v, LEVEL, x, y from inflight_positions;

insert into inflight_positions -- just keep adding, because all those coarse nodes are there at the finer level too
  select oldv, x_min + random()/power(2,64) * (x_max - x_min), y_min + random()/power(2,64) * (y_max - y_min)
    from vcollapse c join inflight_positions p join quadtree q
    where c.newv = p.v and q.pop = 1 and q.x_center = x and q.y_center = y and c.level = LEVEL;

K <- K / √(7/4) -- K <- K / 1.3229

delete from forces;
delete from quadtree; -- pity to waste it, though

}
