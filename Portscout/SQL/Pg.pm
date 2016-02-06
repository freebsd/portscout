#------------------------------------------------------------------------------
# Copyright (C) 2010, Shaun Amott <shaun@inerd.com>
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
# $Id: Pg.pm,v 1.6 2010/05/15 20:19:55 samott Exp $
#------------------------------------------------------------------------------

package Portscout::SQL::Pg;

require Exporter;

use strict;

require 5.006;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(RegisterHacks);


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

my $sql = \%Portscout::SQL::sql;


#------------------------------------------------------------------------------
# SQL that is different for this database engine.
#------------------------------------------------------------------------------

# CheckPortsDB

$$sql{sitedata_setrobots} =
	q(UPDATE sitedata
	     SET robots = ?,
	         robots_paths = ?,
	         robots_nextcheck = CURRENT_TIMESTAMP + INTERVAL '2 weeks'
	   WHERE host = ?);

# GenerateHTML

$$sql{portdata_genresults} =
	q(SELECT maintainer,
	         total,
	         COALESCE(withnewdistfile, 0) AS withnewdistfile,
	         CAST (100*(COALESCE(withnewdistfile, 0)*1.0/total*1.0) AS FLOAT)
	           AS percentage
	    INTO TEMP results
	
	    FROM (
	  SELECT lower(maintainer) AS maintainer,
	         COUNT(maintainer) AS total,
	         COUNT(newver != ver) AS withnewdistfile
	    FROM portdata
	   WHERE moved != true
	GROUP BY lower(maintainer)
	)
	      AS pd1
	);

_transformsql();


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
	my $self      = {};
	my $class     = shift;

	bless ($self, $class);
	return $self;
}


#------------------------------------------------------------------------------
# Func: RegisterHacks()
# Desc: Implement any missing database functions. This minimises the number of
#       different versions of queries we have to maintain. Needs to be called
#       after each new database connection.
#
# Args: \$dbh - Database handle, already connected.
#
# Retn: n/a
#------------------------------------------------------------------------------

sub RegisterHacks
{
	my ($self) = shift;

	return;
}


#------------------------------------------------------------------------------
# Func: _transformsql()
# Desc: Transform the SQL queries into a form that works with this database.
#       This is so we can share as many of the SQL queries as possible, rather
#       than duplicating them for minor changes.
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub _transformsql
{
	return;
}


1;
