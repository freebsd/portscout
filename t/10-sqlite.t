# Check that the various SQL statements work.

use Test;

BEGIN { plan tests => 2; }

use DBI;
use File::Temp qw(tempfile tempdir);

use strict;
use warnings;

use Portscout::Util;
use Portscout::Config;
use Portscout::SQL;

my (%sths, $dbh, $dir, $dbfile, $ret);

$dir = tempdir(CLEANUP => 1);
(undef, $dbfile) = tempfile(DIR => $dir);

# Create database

qx(sqlite3 $dbfile < sql/sqlite_init.sql);
$ret = $?;

ok(!$ret);
die unless (!$ret);

# Connect

$settings{db_connstr} = "DBI:SQLite:dbname=$dbfile";

Portscout::SQL->Load('SQLite');

$dbh = connect_db();

# Prepare all SQL statements

eval {
	prepare_sql($dbh, \%sths, keys %Portscout::SQL::sql);
};

ok(!$@);
