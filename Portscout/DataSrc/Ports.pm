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
# $Id: Ports.pm,v 1.17 2011/04/09 17:19:03 samott Exp $
#------------------------------------------------------------------------------

package Portscout::DataSrc::Ports;

use base qw(Portscout::DataSrc);

use File::stat;

use URI;

use Portscout::Const;
use Portscout::Config;
use Portscout::API;
use Portscout::Util;
use Portscout::Make;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

our %settings;


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
	my $class = shift;

	my $self = {};

	bless ($self, $class);

	return $self;
}


#------------------------------------------------------------------------------
# Func: Init()
# Desc: Initialise.
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub Init
{
	my $self = shift;

	$self->{opts}->{type} = $self->{opts}->{type}
		? lc $self->{opts}->{type}
		: 'freebsd';

	Portscout::Make->Root($settings{ports_dir});
	Portscout::Make->Debug($settings{debug});

	Portscout::Make->Type($self->{opts}->{type})
		if ($self->{opts}->{type});

	Portscout::Make->Wanted(
		qw(DISTNAME DISTFILES EXTRACT_SUFX MASTER_SITES MASTER_SITE_SUBDIR
		   DISTVERSION SLAVE_PORT MASTER_PORT PORTSCOUT MAINTAINER COMMENT)
	);

	if ($self->{opts}->{type} eq 'freebsd') {
		Portscout::Make->InitCache(
			qw(OSVERSION OSREL PORTOBJCFORMAT ARCH OPSYS UID
			   PKGINSTALLVER CONFIGURE_MAX_CMD_LEN)
		);
	}
}


#------------------------------------------------------------------------------
# Func: Build()
# Desc: Perform a full database build.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub Build
{
	my $self = shift;

	return $self->BuildDB();
}


#------------------------------------------------------------------------------
# Func: Rebuild()
# Desc: Perform a partial (incremental) database build.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub Rebuild
{
	my $self = shift;

	return $self->BuildDB(1);
}


#------------------------------------------------------------------------------
# Func: Count()
# Desc: Quick 'n' dirty ports count.
#
# Args: n/a
#
# Retn: $num_ports - Number of ports in tree.
#------------------------------------------------------------------------------

sub Count
{
	my $self = shift;

	my $num_ports = 0;

	opendir my $pd, $settings{ports_dir}
		or return -1;

	while (my $cat = readdir $pd) {
		next if ($cat =~ /^[A-Z.]/ or $cat eq 'distfiles');

		open my $mf, "$settings{ports_dir}/$cat/Makefile"
			or next;

		while (<$mf>) {
			$num_ports++ if /^\s*SUBDIR\s*\+=\s*/;
		}
	}

	return $num_ports;
}


#------------------------------------------------------------------------------
# Func: BuildDB()
# Desc: Build database.
#
# Args: $incremental - true if we're just doing a partial update.
#
# Retn: $success     - true/false
#------------------------------------------------------------------------------

sub BuildDB
{
	my $self = shift;

	my ($incremental) = @_;

	my (%sths, $dbh, @cats, %portsmaintok, $mfi, $move_ports,
		$num_ports, $got_ports, $buildtime);

	my @ports;

	my $ps = Portscout::API->new;

	my $lastbuild = getstat('buildtime', TYPE_INT);

	print "Looking for updated ports...\n\n"
		if ($incremental);

	$got_ports = 0;
	$num_ports = 0;
	$buildtime = time;

	$dbh = connect_db();

	prepare_sql($dbh, \%sths,
		qw(portdata_masterport_str2id portdata_masterport_enslave
		   portdata_findslaves)
	);

	@cats = split /\s+/, Portscout::Make->Make($settings{ports_dir}, 'SUBDIR');

	$mfi = stat $settings{ports_dir} . '/MOVED'
		or die "Couldn't stat MOVED file";

	$move_ports = 1 if ($mfi->mtime > $lastbuild);

	# If the user has specified a maintainer restriction
	# list, try to get to get the list of desired ports
	# from the INDEX file.

	if ($settings{restrict_maintainer} && $settings{indexfile_enable}) {
		print "Querying INDEX for maintainer associations...\n";

		my %maintainers = map +($_, 1),
			split /,/, lc $settings{restrict_maintainer};

		my $index_file =
			$settings{ports_dir}.'/'.
			Portscout::Make->Make($settings{ports_dir}, 'INDEXFILE');

		open my $if, "<$index_file"
			or die 'Unable to open INDEX file';

		while (<$if>) {
			my (@fields, $maintainer, $port);

			@fields = split /\|/;
			$maintainer = $fields[5];
			$port = $fields[1];
			$port =~ s/^(?:.*\/)?([^\/]+)\/([^\/]+)$/$1\/$2/;

			$portsmaintok{$port} = $maintainer
				if ($maintainers{$maintainer});
		}

		close $if;
	}

	# Iterate over ports directories

	while (my $cat = shift @cats) {
		next if (! -d $settings{ports_dir}."/$cat");

		# Skip category if user doesn't want it.
		wantport(undef, $cat) or next;

		opendir my $catdir, $settings{ports_dir}."/$cat";

		print "Scanning $cat...\n"
			unless ($settings{quiet});

		while (my $name = readdir $catdir) {
			next if ($name =~ /^\./);
			next if ($name =~ /^CVS$/);
			next if (! -d $settings{ports_dir}."/$cat/$name");

			# If we're doing an incremental build, check the
			# port directory's mtime; skip if not updated.
			if ($incremental) {
				my ($updated);

				opendir my $portdir, $settings{ports_dir}."/$cat/$name";

				while (my $subfile = readdir $portdir) {
					my ($subfile_path, $fi);

					$subfile_path = $settings{ports_dir}."/$cat/$name/$subfile";
					next if (! -f $subfile_path);

					$fi = stat $subfile_path
						or die "Couldn't stat $subfile_path: $!";

					if ($fi->mtime > $lastbuild) {
						$updated = 1;
						last;
					}
				}

				next if (!$updated);
			}

			# Check this port is wanted by user
			wantport($name, $cat) or next;

			# Check maintainer if we were able to ascertain
			# it from the INDEX file (otherwise, we've got to
			# wait until make(1) has been queried.
			if ($settings{restrict_maintainer}
					&& $settings{indexfile_enable}) {
				next if (!$portsmaintok{"$cat/$name"});
			}

			push @ports, "$cat/$name";
		}
	}

	# Find slave ports, which might not have been
	# directly modified.

	if ($incremental) {
		foreach (@ports) {
			if (/^(.*)\/(.*)$/) {
				my ($name, $cat) = ($2, $1);

				print "findslaves -> $cat/$name\n"
					if ($settings{debug});
				$sths{portdata_findslaves}->execute($name, $cat);
				while (my $port = $sths{portdata_findslaves}->fetchrow_hashref) {
					wantport($name, $cat) or next;

					push @ports, "$port->{cat}/$port->{name}"
						unless (arrexists(\@ports, "$port->{cat}/$port->{name}"));
				}
			}
		}
	}

	$num_ports = $#ports + 1;

	print "\n" unless (!$num_ports or $settings{quiet});

	print $num_ports
		? "Building...\n\n"
		: "None found!\n";

	# Build the ports we found

	while (my $port = shift @ports) {
		my ($cat, $name);

		($cat, $name) = ($1, $2) if $port =~ /^(.*)\/(.*)$/;

		$got_ports++;

		print '[' . strchop($cat, 15) . '] ' unless ($settings{quiet});
		info($name, "(got $got_ports out of $num_ports)");

		BuildPort($ps, $dbh, \%sths, $name, $cat);
	}

	# Go through and convert all masterport cat/name strings
	# into numerical ID values

	if ($num_ports) {
		print "\n" unless ($settings{quiet});
		print "Cross-referencing master/slave ports...\n";

		unless ($settings{precious_data}) {
			$sths{portdata_masterport_str2id}->execute;
			$sths{portdata_masterport_enslave}->execute;
		}
	}

	setstat('buildtime', $buildtime);

	finish_sql(\$dbh, \%sths);

	if ($move_ports && $self->{opts}->{type} eq 'freebsd') {
		if (!MovePorts($incremental ? 0 : 1)) {
			#$dbh->disconnect;
			return 0;
		}
	}

	#$dbh->disconnect;
	return 1;
}


#------------------------------------------------------------------------------
# Func: BuildPort()
# Desc: Compile data for one port, and add to the database.
#
# Args: $ps      - Portscout::API ref.
#       $dbh     - Database handle.
#       \%sths   - Statement handles.
#       $name    - Port name.
#       $cat     - Port category.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub BuildPort
{
	my ($ps, $dbh, $sths, $name, $cat) = @_;

	my (@sites, @distfiles, %pcfg);
	my ($ver, $distname, $distfiles, $sufx, $subdir,
	    $distver, $masterport, $maintainer, $comment);
	my ($mv);

	# Query make for variables -- this is a huge bottleneck

	if ($settings{quickmake_enable}) {
		#$mv = Portscout::Make->QuickMake("$cat/$port");
		die 'quickmake not yet (fully) implemented';
	} else {
		$mv = Portscout::Make->Make("$settings{ports_dir}/$cat/$name");
	}

	defined $mv or return 0;

	$maintainer = $mv->{MAINTAINER}         || '';
	$distname   = $mv->{DISTNAME}           || '';
	$sufx       = $mv->{EXTRACT_SUFX}       || '';
	$subdir     = $mv->{MASTER_SITE_SUBDIR} || '';
	$distver    = $mv->{DISTVERSION}        || '';
	$comment    = $mv->{COMMENT}            || '';

	$mv->{$_} =~ s/\s+/ /g foreach (keys %$mv);

	# Never allow spaces in SUBDIR
	$subdir =~ s/\s+.*$//;

	# Now we can check the maintainer restriction (if any)
	wantport(undef, undef, $maintainer) or return 0;

	$masterport = (lc $mv->{SLAVE_PORT} eq 'yes') ? $mv->{MASTER_PORT} : '';

	$masterport = $1 if ($masterport =~ /^\Q$settings{ports_dir}\E\/(.*)\/$/);

	# Get rid of unexpanded placeholders

	foreach my $site (split /\s+/, $mv->{MASTER_SITES}) {
		$site =~ s/\%SUBDIR\%/$subdir/g;
		$site =~ s/\/+$/\//;
		$site =~ s/:[A-Za-z0-9][A-Za-z0-9\,]*$//g; # site group spec.

		$site = URI->new($site)->canonical;
		next if (length $site->host == 0);

		push @sites, $site;
	}

	foreach my $file (split /\s+/, $mv->{DISTFILES}) {
		$file =~ s/:[A-Za-z0-9][A-Za-z0-9\,]*$//g;
		push @distfiles, $file;
	}

	# Remove ports-system "site group" specifiers

	$distname =~ s/:[A-Za-z0-9][A-Za-z0-9\,]*$//g;

	# Attempt to extract real version from
	# distname (this needs refining)

	if ($distver)
	{
		$ver = $distver;
	}
	elsif ($distname =~ /\d/)
	{
		my $name_q;
		$ver = $distname;
		$name_q = quotemeta $name;

		$name_q =~ s/^(p5|mod|py|ruby|hs)(?:[\-\_])/($1\[\\-\\_\])?/;

		# XXX: fix me

		my $chop =
			'sources?|bin|src|snapshot|freebsd\d*|freebsd-?\d\.\d{1,2}|'
			. 'linux|unstable|elf|i\d86|x86|sparc|mips|linux-i\d86|html|'
			. 'en|en_GB|en_US|full-src|orig|setup|install|export|'
			. 'fbsd[7654]\d{1,2}|export|V(?=\d)';

		foreach (split '\|', $chop) {
			unless ($name =~ /($_)/i) {
				$ver =~ s/[\.\-\_]?($chop)$//gi;
				$ver =~ s/^($chop)[\.\-\_]?//gi;
			}
		}

		unless ($ver =~ s/.*$name_q[-_\.]//i) {
			# Resort to plan B
			if ($ver =~ /^(.*)-(.*)$/) {
				$ver = $2;
			} elsif ($name !~ /\d/) {
				$ver =~ s/^\D*(\d.*)$/$1/;
			}
		}

		$ver = '' if ($ver eq $name);
	}

	# Create options hash

	foreach (split /\s+/, $mv->{PORTSCOUT}) {
		if (/^([A-Za-z]+):(.*)$/i) {
			$pcfg{lc $1} = $2;
		}
	}

	# Store port data

	$ps->AddPort({
		'name'       => $name,
		'category'   => $cat,
		'version'    => $ver,
		'maintainer' => $maintainer,
		'comment'    => $comment,
		'distname'   => $distname,
		'suffix'     => $sufx,
		'masterport' => $masterport,
		'distfiles'  => \@distfiles,
		'sites'      => \@sites,
		'options'    => \%pcfg
	});

	return 1;
}


#------------------------------------------------------------------------------
# Func: MovePorts()
# Desc: Handle any ports which have been moved.
#
# Args: $addonly - Should we just record the entries, or start moving
#                  ports around? (true = the former)
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub MovePorts
{
	my ($addonly) = @_;

	my (%sths, $dbh);

	my $error = 0;

	my $moved_file = $settings{ports_dir}.'/MOVED';

	print "Processing MOVED entries...\n";

	return 0 unless (-f $moved_file);

	$dbh = connect_db();

	prepare_sql($dbh, \%sths,
		qw(moveddata_exists portdata_setmoved portdata_removestale
		   moveddata_insert)
	);

	open my $mf, "<$moved_file" or $error = 1;

	while (<$mf>)
	{
		my $exists;

		next if /^#/;

		my ($port_from, $port_to, $date, $reason) = split /\|/;

		my ($port_fromcat, $port_fromname, $port_tocat, $port_toname);

		next unless ($port_from);

		$sths{moveddata_exists}->execute($port_from, $port_to, $date);
		($exists) = $sths{moveddata_exists}->fetchrow_array;
		next if ($exists);

		if ($addonly) {
			info($port_from, 'Record MOVED entry: date ' . $date);
			$sths{moveddata_insert}->execute($port_from, $port_to, $date, $reason)
				unless ($settings{precious_data});
			next;
		}

		info($port_from, ($port_to ? 'Moving to ' . $port_to
		                           : 'Deleting'));

		if ($port_from)
		{
			($port_fromcat, $port_fromname) = ($1, $2)
				if ($port_from =~ /^(.*)\/(.*)/);

			($port_tocat, $port_toname) = ($1, $2)
				if ($port_to =~ /^(.*)\/(.*)/);

			# Mark for removal
			$sths{portdata_setmoved}->execute($port_fromname, $port_fromcat)
				unless ($settings{precious_data});
		}

		# Record entry
		$sths{moveddata_insert}->execute($port_from, $port_to, $date, $reason)
			unless ($settings{precious_data});
	}

	print "Finalising pending MOVED terminations...\n";

	# Remove ports that were ear-marked
	$sths{portdata_removestale}->execute
		unless ($addonly || $settings{precious_data});

	close $mf;

	finish_sql(\$dbh, \%sths);

	return ($error ? 0 : 1);
}


1;
