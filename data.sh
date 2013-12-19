#!/bin/bash
set -e -u

echo "setting up..."
TMP=`mktemp -d tmpXXXX`
createdb -U $1 -T template_postgis $TMP
echo "downloading..."
curl -sfo $TMP/qs_adm1.zip http://static.quattroshapes.com/qs_adm1.zip
unzip -q $TMP/qs_adm1.zip -d $TMP
echo "importing..."
ogr2ogr \
	-nlt MULTIPOLYGON \
	-nln import \
	-f "PostgreSQL" PG:"host=localhost user=$1 dbname=$TMP" \
	$TMP/qs_adm1.shp

echo "cleaning..."
echo "
CREATE TABLE data(id SERIAL PRIMARY KEY, name VARCHAR, geometry GEOMETRY(Geometry, 4326), search VARCHAR, qs_adm0 VARCHAR, lon FLOAT, lat FLOAT, bounds VARCHAR, area FLOAT);
INSERT INTO data (id, geometry, name, qs_adm0, search)
	SELECT ogc_fid, st_setsrid(wkb_geometry,4326), qs_a1 AS name, qs_adm0, coalesce(qs_a1||','||qs_a1_alt, qs_a1) AS search FROM import;
UPDATE data SET
    lon = st_x(st_pointonsurface(geometry)),
    lat = st_y(st_pointonsurface(geometry)),
    bounds = st_xmin(geometry)||','||st_ymin(geometry)||','||st_xmax(geometry)||','||st_ymax(geometry);
UPDATE data SET area = 0;
UPDATE data SET area = st_area(st_geogfromwkb(geometry)) where st_within(geometry,st_geomfromtext('POLYGON((-180 -90, -180 90, 180 90, 180 -90, -180 -90))',4326));
" | psql -U $1 $TMP

echo "exporting..."
ogr2ogr \
	-skipfailures \
	-f "SQLite" \
	-nln data \
	qs-adm1.sqlite \
	PG:"host=localhost user=$1 dbname=$TMP" data
echo "cleaning up..."
dropdb -U $1 $TMP
rm -rf $TMP

echo "Written to qs-adm1.sqlite."