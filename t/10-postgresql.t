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

my (%sths, $dbh, $dbuser, $dbname, $ret);

$dbname = 'ps_test_' . randstr(8);
$dbuser = $dbname;

# Create database

qx(createuser -D -A -U pgsql "$dbuser");
die if $?;
qx(createdb -U pgsql -E UNICODE "$dbname");
die if $?;

qx(psql $dbuser $dbname < sql/pgsql_init.sql);
$ret = $?;

ok(!$ret);
die unless (!$ret);

# Connect

$settings{db_user} = $dbuser;
$settings{db_pass} = '';
$settings{db_connstr} = "DBI:Pg:dbname=$dbname";

Portscout::SQL->Load('Pg');

$dbh = connect_db();

# Prepare all SQL statements

eval {
	prepare_sql($dbh, \%sths, keys %Portscout::SQL::sql);
};

ok(!$@);

END {
	if ($dbh) {
		finish_sql($dbh, \%sths);
		$dbh->disconnect;
	}
	if ($dbname) { qx(dropdb -U pgsql "$dbname"); }
	if ($dbuser) { qx(dropuser -U pgsql "$dbuser"); }
}
