#------------------------------------------------------------------------------
# Copyright (C) 2011, Shaun Amott <shaun@inerd.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $Id: SQL.pm,v 1.20 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

package Portscout::SQL;

require Exporter;

use strict;

require 5.006;

our @ISA = qw(Exporter);


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

our %sql;


#------------------------------------------------------------------------------
# SQL that is common to all supported database engines.
#------------------------------------------------------------------------------

$sql{portdata_exists} =
	q(SELECT 1
	    FROM portdata
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true
	   LIMIT 1);

$sql{portdata_getver} =
	q(SELECT ver
	    FROM portdata
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

$sql{portdata_getnewver} =
	q(SELECT newver
	    FROM portdata
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

$sql{portdata_clearnewver} =
	q(UPDATE portdata
	     SET newver = NULL, method = NULL
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

$sql{portdata_update} =
	q(UPDATE portdata
	     SET ver = ?,  comment = ?, cat = ?, distfiles = ?, distname = ?,
	         sufx = ?, mastersites = ?, maintainer = ?,  masterport = ?,
	         updated = CURRENT_TIMESTAMP
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

$sql{portdata_insert} =
	q(INSERT
	    INTO portdata (name, cat, distname, ver, comment,
	         distfiles, sufx, mastersites, maintainer,
	         method, masterport)
	  VALUES (?,?,?,?,?,?,?,?,?,0,?));

$sql{portdata_masterport_str2id} =
	q(UPDATE portdata
	     SET masterport_id = (SELECT id
	                            FROM portdata
	                              AS master
	                           WHERE master.cat  = split_part(portdata.masterport, '/', 1)
	                             AND master.name = split_part(portdata.masterport, '/', 2)
	                           LIMIT 1)
	   WHERE masterport is not NULL
	     AND masterport != ''
	     AND moved != true);

# Note: enslaved only meaningful when masterport_id != 0
$sql{portdata_masterport_enslave} =
	q(UPDATE portdata
	     SET enslaved = (1 IN (SELECT 1
	                             FROM portdata
	                               AS master
	                            WHERE master.id = portdata.masterport_id
	                              AND master.ver = portdata.ver
	                              AND master.distfiles = portdata.distfiles
	                              AND master.mastersites = portdata.mastersites))
	   WHERE masterport_id != 0
	     AND masterport_id is not NULL
	     AND moved != true);

$sql{portconfig_update} =
	q(UPDATE portdata
	     SET indexsite = ?, limitver = ?,     limiteven = ?,
	         skipbeta = ?,  skipversions = ?, limitwhich = ?,
	         ignore = ?
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

$sql{portconfig_isstatic} =
	q(SELECT pcfg_static
	    FROM portdata
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

# BuildPortsDBFast

$sql{portdata_findslaves} =
	q(SELECT name, cat
	    FROM portdata
	   WHERE masterport_id = (SELECT id
	                            FROM portdata
	                           WHERE name = ?
	                             AND cat = ?
	                           LIMIT 1)
	     AND moved != true);

# CheckPortsDB

$sql{portdata_select} =
	q(SELECT *
	    FROM portdata
	   WHERE ( (masterport_id = 0 OR masterport_id is NULL) OR (enslaved != true) )
	     AND ( systemid = (SELECT id
	                         FROM systemdata
	                        WHERE host = ?
	                        LIMIT 1)
	           OR systemid is NULL )
	     AND moved != true
	     AND ignore != true
	ORDER BY random());

$sql{portdata_count} = $sql{portdata_select};
$sql{portdata_count} =~ s/^SELECT \*/SELECT COUNT (*)/i;
$sql{portdata_count} =~ s/ORDER BY.*$/LIMIT 1/i;

$sql{portdata_setchecked} =
	q(UPDATE portdata
	     SET checked = CURRENT_TIMESTAMP
	   WHERE id = ?
	      OR (masterport_id = ? AND enslaved = true));

$sql{portdata_setnewver} =
	q(UPDATE portdata
	     SET newver = ?, method = ?, newurl = ?,
	         discovered = CURRENT_TIMESTAMP
	   WHERE id = ?
	      OR (masterport_id = ? AND enslaved = true));

$sql{sitedata_exists} =
	q(SELECT COUNT(*)
	    FROM sitedata
	   WHERE host = ?);

$sql{sitedata_select} =
	q(SELECT host, robots, robots_paths, liecount,
	         (CURRENT_TIMESTAMP >= robots_nextcheck) AS robots_outofdate,
	         abs(successes + (5*failures)) AS _w
	    FROM sitedata
	   WHERE position(host in ?) > 0
	     AND ignore is not true
	ORDER BY _w ASC);

$sql{sitedata_failure} =
	q(UPDATE sitedata
	     SET failures = failures + 1
	   WHERE host = ?);

$sql{sitedata_success} =
	q(UPDATE sitedata
	     SET successes = successes + 1
	   WHERE host = ?);

$sql{sitedata_insert} =
	q(INSERT
	    INTO sitedata (type, host)
	  VALUES (?,?));

$sql{sitedata_initliecount} =
	q(UPDATE sitedata
	     SET liecount = 8
	   WHERE host = ?);

$sql{sitedata_decliecount} =
	q(UPDATE sitedata
	     SET liecount = liecount - 1
	   WHERE host = ?);

#$sql{sitedata_setrobots}

# UncheckPortsDB

$sql{portdata_uncheck} =
	q(UPDATE portdata
	     SET checked = NULL, newver = NULL, status = NULL,
	         newurl = NULL,  method = NULL);

# GenerateHTML

#$sql{portdata_genresults}

$sql{portdata_selectall} =
	q(SELECT *
	    FROM portdata
	   WHERE lower(maintainer) = lower(?)
	     AND moved != true
	ORDER BY cat,name);

$sql{portdata_selectall_limited} =
	q(SELECT name, cat, limitver, limiteven, limitwhich, indexsite, skipversions,
	         skipbeta
	    FROM portdata
	   WHERE ( limitver     is not NULL )
	      OR ( limitwhich   is not NULL )
	      OR ( indexsite    is not NULL )
	      OR ( skipversions is not NULL )
	     AND moved != true
	ORDER BY cat,name);

# ShowUpdates

$sql{portdata_selectupdated} =
	q(SELECT lower(maintainer) AS maintainer,
	         cat, name, ver, newver
	    FROM portdata
	   WHERE ver != newver
	ORDER BY lower(maintainer));


# MovePorts

$sql{moveddata_exists} =
	q(SELECT 1
	    FROM moveddata
	   WHERE fromport = ?
	     AND toport = ?
	     AND date = ?
	   LIMIT 1);

$sql{moveddata_insert} =
	q(INSERT
	    INTO moveddata (fromport, toport, date, reason)
	  VALUES (?,?,?,?));

$sql{portdata_move} =
	q(UPDATE portdata
	     SET cat = ?, name = ?
	   WHERE cat = ?
	     AND name = ?
	     AND moved != true);

$sql{portdata_setmoved} =
	q(UPDATE portdata
	     SET moved = true
	   WHERE name = ?
	     AND cat = ?);

$sql{portdata_removestale} =
	q(DELETE
	    FROM portdata
	   WHERE moved = true
	     AND pcfg_static != true);

$sql{portdata_exists} =
	q(SELECT 1
	    FROM portdata
	   WHERE name = ?
	     AND cat = ?
	   LIMIT 1);

# MailMaintainers

$sql{maildata_select} =
	q(SELECT address
	    FROM maildata);

$sql{portdata_findnewnew} =
	q(SELECT name,cat,ver,newver
	    FROM portdata
	   WHERE lower(maintainer) = lower(?)
	     AND newver != ver
	     AND newver is not NULL
	     AND moved != true
	     AND ignore != true
	     AND (( mailed != ver AND mailed != newver )
	            OR mailed is NULL )
	ORDER BY cat,name ASC);

$sql{portdata_setmailed} =
	q(UPDATE portdata
	     SET mailed = ?
	   WHERE name = ?
	     AND cat = ?
	     AND moved != true);

# AddMailAddrs

$sql{maildata_exists} =
	q(SELECT 1
	    FROM maildata
	   WHERE lower(address) = lower(?)
	   LIMIT 1);

$sql{maildata_insert} =
	q(INSERT
	    INTO maildata (address)
	  VALUES (?));

# RemoveMailAddrs

$sql{maildata_delete} =
	q(DELETE
	    FROM maildata
	   WHERE lower(address) = lower(?));

# AllocatePorts

$sql{portdata_countleft} =
	q(SELECT COUNT(*)
	    FROM portdata
	   WHERE moved != true
	     AND systemid is NULL);

$sql{portdata_deallocate} =
	q(UPDATE portdata
	     SET systemid = NULL);

$sql{allocators_count} =
	q(SELECT COUNT(*)
	    FROM allocators
	   LIMIT 1);

$sql{allocators_select} =
	q(SELECT *
	    FROM allocators
	ORDER BY seq ASC, allocator);

# Misc.

$sql{portscout_version} =
	q(SELECT dbver
	    FROM portscout
	ORDER BY dbver DESC
	   LIMIT 1);

$sql{portscout_getstat} =
	q(SELECT val
	    FROM stats
	   WHERE key = ?
	   LIMIT 1);

$sql{portscout_setstat} =
	q(UPDATE stats
	     SET val = ?
	   WHERE key = ?);


#------------------------------------------------------------------------------
# Func: new()
# Desc: Constructor.
#
# Args: n/a
#
# Retn: $self
#------------------------------------------------------------------------------

sub new
{
	my $self  = {};
	my $class = shift;

	bless ($self, $class);
	return $self;
}


#------------------------------------------------------------------------------
# Func: Load()
# Desc: Initialise; load the SQL from the required module.
#
# Args: $db      - DBI engine name.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub Load
{
	my $self = shift;

	my ($db) = @_;

	return 0 if (!$db);

	eval 'use Portscout::SQL::' . $db . ' qw(RegisterHacks);';

	if ($@) {
		warn $@;
		return 0;
	}

	return 1;
}


1;
