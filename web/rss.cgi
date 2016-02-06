#!/usr/bin/perl
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
# $Id: rss.cgi,v 1.4 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

#use CGI::Carp qw(fatalsToBrowser);

use DBI;
use CGI;
use DateTime;

use XML::RSS;
use CGI::Cache;

use Portscout::Const;
use Portscout::Util;
use Portscout::Config;
use Portscout::SQL;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Extra config options for this script
#------------------------------------------------------------------------------

$settings{rss_url_base} ||= '/portscout/';


#------------------------------------------------------------------------------
# Begin code
#------------------------------------------------------------------------------

main();


#------------------------------------------------------------------------------
# Pseudo script entry point.
#------------------------------------------------------------------------------

sub main
{
	my ($dbh, $sth, $rss, $query);
	my (@maintainers, @time);

	my $q = new CGI;

	my $recentonly;

	CGI::Cache::setup({
		cache_options => {
			cache_root         => 'cache',
			namespace          => 'rss_cgi',
			directory_umask    => 077,
			default_expires_in => '1 hour',
		}
	});

	# Check for r ("range") param

	$recentonly = defined $q->param('r');

	# Accept a comma-separated list of maintainers

	@maintainers = sort(split /,/, lc $q->param('m'))
		if ($q->param('m'));

	if (@maintainers) {
		if ($recentonly) {
			CGI::Cache::set_key(@maintainers, '_recentonly');
		} else {
			CGI::Cache::set_key(@maintainers);
		}
	} else {
		CGI::Cache::set_key($recentonly ? '_recentonly' : '_default');
	}

	# Return cached page if it exists

	CGI::Cache::start() or exit;

	# Database stuff

	if (1) {
		my $dbengine = $settings{db_connstr};
		$dbengine =~ s/^\s*DBI:([A-Za-z0-9]+):?.*$/$1/;

		Portscout::SQL->Load($dbengine)
			or die 'Failed to load queries for DBI engine "' . $dbengine . '"';
	}

	$dbh = connect_db();

	# Construct an SQL query

	$query =
		q(SELECT name, cat, ver, newver, newurl, discovered,
		         checked, updated, maintainer
		    FROM portdata
		   WHERE 1 = 1);

	# XXX: this is slow - need something better

	if (@maintainers) {
		$query .= ' AND ( lower(maintainer) = ? ';
		$query .= ' OR lower(maintainer) = ? ' x (@maintainers - 1);
		$query .= ' ) ';
	}

	if ($recentonly) {
		$query .= q( AND age(discovered) <= '7 days' );
	}

	$query .=
		q(   AND ver != newver
		     AND discovered IS NOT NULL
		ORDER BY discovered DESC);

	$sth = $dbh->prepare($query);
	$sth->execute(@maintainers);

	$rss = XML::RSS->new(version => '2.0');

	# Global RSS bits

	$rss->channel(
		title         => 'Portscout Port Updates',
		description   => 'New distfiles found via the portscout scanner',
		category      => [ @maintainers ? @maintainers : '*' ],
		lastBuildDate => rssdate(),
		generator     => APPNAME.' v'.APPVER.', by '.AUTHOR,
		link          => $settings{rss_url_base}
	);

	$rss->add_module(prefix => 'port', uri => '/dev/null');

	# Construct an <item /> block for each new port update

	while (my $port = $sth->fetchrow_hashref) {
		$port->{updated}    = rssdate($port->{updated});
		$port->{checked}    = rssdate($port->{checked});
		$port->{discovered} = rssdate($port->{discovered});

		$port->{$_} ||= '' foreach (keys %$port);

		$rss->add_item(
			title       => "$port->{cat}/$port->{name}: $port->{ver} -> $port->{newver}",
			description => "Update found for port $port->{cat}/$port->{name}: version $port->{ver} to $port->{newver}",
			link        => "$settings{rss_url_base}" . lc($port->{maintainer}) . '.html',
			guid        => "$port->{cat}/$port->{name}/$port->{ver}/$port->{newver}",
			pubDate     => $port->{discovered},
			category    => lc $port->{maintainer},

			port => {
				freshports  => "http://www.freshports.org/$port->{cat}/$port->{name}/",
				openprs     => "http://www.freebsd.org/cgi/query-pr-summary.cgi?category=ports"
				               . "&text=$port->{cat}%2F$port->{name}",
				version     => $port->{ver},
				newversion  => $port->{newver},
				newurl      => $port->{newurl},
				updated     => $port->{updated},
				checked     => $port->{checked},
				portname    => $port->{name},
				portcat     => $port->{cat}
			}
		);
	}

	print $rss->as_string;

	CGI::Cache::stop();
}


#------------------------------------------------------------------------------
# Func: rssdate()
# Desc: Format a date into RSS (RFC 2822) format.
#
# Args: $string  - A date in database format; "now" if unset.
#
# Retn: $datestr - Valid date string.
#------------------------------------------------------------------------------

sub rssdate
{
	my ($string) = @_;

	my $dt;

	if ($string) {
		my ($year, $month, $day, $hours, $mins, $secs);

		if ($string =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/) {
			$year = $1; $month = $2; $day = $3;
			$hours = $4; $mins = $5; $secs = $6;
		}

		$dt = DateTime->new(
			year => $year, month => $month, day => $day,
			hour => $hours, minute => $mins, second => $secs
		);
	} else {
		$dt = DateTime->now;
	}

	return DateTime::Format::Mail->format_datetime($dt);
}
