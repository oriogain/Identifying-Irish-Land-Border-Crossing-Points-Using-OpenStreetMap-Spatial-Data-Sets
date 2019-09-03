-- Set the default schema (test); the public schema must also be included to access the PostGIS functions

set search_path to brexit, public;

-- Create the crossing points by finding where the OSM road linestrings intersect with the boundary (border) linestring.

drop table if exists brexit_border_crossing_points cascade;

create table brexit_border_crossing_points
as (
SELECT distinct (ST_Dump(ST_Intersection(b.geom,r.geom))).geom AS geom, r.code, r.fclass, r.name, r.ref
FROM gis_osm_roads_free_1 r, "Ireland_AL2_Boundary" b
WHERE ST_Intersects(r.geom,b.geom)
);

-- Add a unique identifier column (id)

alter table brexit_border_crossing_points drop column if exists id cascade;

alter table brexit_border_crossing_points add column id serial primary key;

-- Create an index on the geom column

DROP INDEX if exists sidx_brexit_border_crossing_points_geom;

CREATE INDEX sidx_brexit_border_crossing_points_geom
  ON brexit_border_crossing_points
  USING gist
  (geom);

-- Count the total border crossing points

select count(*) as count
from brexit_border_crossing_points;

-- Display the problematic (linestring) border crossing points

select *
from brexit_border_crossing_points
where char_length(geom) > 50;

-- Delete rows with linestring geom values

delete from brexit_border_crossing_points
where id in
(
select id
from brexit_border_crossing_points
where char_length(geom) > 50
);

-- Display the crossing points with duplicate geom values

select b.geom, b.code, b.fclass, b.name, b.ref, b.id
from brexit_border_crossing_points b
inner join (
select geom, count(*) as count
from brexit_border_crossing_points
group by geom
having count(*) > 1
) D on D.geom = b.geom
order by b.geom;

-- Retain only the first crossing point in each group of duplicates

delete from brexit_border_crossing_points
where id in
(
	select b.id
	from brexit_border_crossing_points b
	inner join (
		select geom, count(*) as count
		from brexit_border_crossing_points
		group by geom
		having count(*) > 1
		) D on D.geom = b.geom
	where b.id not in
	(
		select X.min_id
		from (
			select c.geom, min(c.id) as min_id
			from brexit_border_crossing_points c
			inner join (
				select geom, count(*) as count
				from brexit_border_crossing_points
				group by geom
				having count(*) > 1
				) D on D.geom = c.geom
			group by c.geom
			order by c.geom
		) X
	)
	order by b.geom
);

-- Display duplicate crossing points on A1 dual carriageway

select *
from brexit_border_crossing_points
where ref = 'A1';

-- Delete the first of the duplicate crossing points on A1 dual carriageway

delete from brexit_border_crossing_points
where geom = '0101000020110F0000C4363AF6609F25C1BDC6D7BA306F5B41';

-- Display rows for invalid crossing points (Fitzpatrick Hardware site boundary misinterpreted as roads)

select * 
from brexit_border_crossing_points
where geom in('0101000020110F0000BD56342E85A628C11CAA228AF77D5B41', '0101000020110F00008A95D9A04EA728C1120CE8A8EC7D5B41');

-- Delete rows for invalid crossing points (Fitzpatrick Hardware site boundary misinterpreted as roads)

delete from brexit_border_crossing_points
where geom in('0101000020110F0000BD56342E85A628C11CAA228AF77D5B41', '0101000020110F00008A95D9A04EA728C1120CE8A8EC7D5B41');

-- Count the remaining (valid) border crossing points

select count(*) as count_valid
from brexit_border_crossing_points;

-- Summarise the border crossing points by road class

select code, fclass, count(*) as count
from brexit_border_crossing_points
group by code, fclass
order by code;

-- Highlight the main border crossings (i.e. trunk, primary, secondary, tertiary roads etc.)

drop view if exists brexit_border_crossing_points_main;

create or replace view brexit_border_crossing_points_main
as
select *
from brexit_border_crossing_points
where id not in
(
	select id
	from brexit_border_crossing_points
	where code >= 5141
	  and id not in(204,       	-- Force novelty near Fitzpatrick Hardware
			205, 269, 299,  -- Force pairing with nearby Irish Times crossing (disabling their novelty)
			400, 401)  	-- Retain these 2 service road crossings on Lough Shore Road, Belleek.
)
   and id not in(301, 323, 356, 427)	-- Force treatment as minor crossings (for varous reasons)
order by id;

-- Create a database view which identifies the 'Brexit' Novelties

drop view if exists brexit_border_crossing_points_novelties;

create or replace view brexit_border_crossing_points_novelties
as
select *
from brexit_border_crossing_points_main
where id not in
(
	select b.id
	from brexit_border_crossing_points_main b, "IrishTimesBorderCrossings" i
	where ST_Dwithin(ST_Transform(b.geom, 32629), ST_Transform(i.geom, 32629), 40)
)
   and id <> 200	-- Override novelty status for this crossing
order by id;

-- Create a database view which identifies the Irish Times Novelties

drop view if exists "IrishTimesBorderCrossingsNovelties";

create or replace view "IrishTimesBorderCrossingsNovelties"
as
select *
from "IrishTimesBorderCrossings"
where id not in
(
	select i.id
	from brexit_border_crossing_points_main b, "IrishTimesBorderCrossings" i
	where ST_Dwithin(ST_Transform(b.geom, 32629), ST_Transform(i.geom, 32629), 70)
)
order by id;

-- Count the Irish Times border crossing points

select count(*) as count
from "IrishTimesBorderCrossings";

-- Review the Irish Times Novelties

select id, geom, name, r_county, today
from "IrishTimesBorderCrossingsNovelties"
order by id;

-- Count the main border crossing points identified by this project

select count(*) as count
from brexit_border_crossing_points_main;

-- Review the 'Brexit' Novelties

select *
from brexit_border_crossing_points_novelties
order by id;