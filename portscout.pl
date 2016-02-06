#!/usr/bin/perl
#------------------------------------------------------------------------------
# Project     : portscout
# Author      : Shaun Amott <shaun@inerd.com>
# Start date  : 2006-01-07
# Environment : perl 5.8.x, PostgreSQL 7.4, FreeBSD 6.x
# Download    : http://www.inerd.com/software/portscout/
#
# $Id: portscout.pl,v 1.82 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------
# Copyright (C) 2005-2011, Shaun Amott. All rights reserved.
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
#------------------------------------------------------------------------------

use IO::Handle;
use File::Basename;
use File::Copy;
use Socket;
use POSIX;
use Fcntl;

use Proc::Queue;
use Sys::Hostname;
use LWP::UserAgent;
use MIME::Lite;
use Net::FTP;
use URI;

use DBI;

use Portscout;
use Portscout::Const;
use Portscout::Util;
use Portscout::Config;

use strict;
#use warnings;

require 5.006;


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

my @bad_versions;

my $datasrc;

@bad_versions =
	qw(win32 cygwin linux osx hpux irix hp-ux hp_ux solaris
	   hp-ux irix mac-?os darwin aix macintosh manual docs?
	   examples sunos tru64 rh\d-rpm suse sun4[a-z]? cvs snap
	   win jdk i[3-6]86 theme nolib dyn lin(?:ux)?(?:\d\d)?
	   \.exe$ pkg elf debian html mingw);


#------------------------------------------------------------------------------
# Signal Handlers
#------------------------------------------------------------------------------

sub terminate
{
	local $SIG{INT} = 'IGNORE';
	kill('TERM', -$$);

	print "PID #$$ Terminating...\n";
	exit 1;
}

sub reaper
{
	my $child;
	(1) while (($child = waitpid(-1, WNOHANG)) > 0);
	$SIG{CHLD} = \&reaper;
}

$SIG{INT}  = \&terminate;
$SIG{TERM} = \&terminate;
#$SIG{CHLD} = \&reaper;
$SIG{PIPE} = 'IGNORE';


#------------------------------------------------------------------------------
# Begin Code
#------------------------------------------------------------------------------

main();


#------------------------------------------------------------------------------
# Func: main()
# Desc: Pseudo script entry-point.
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub main
{
	my ($dbengine);

	if ($settings{debug}) {
		print STDERR '-' x 72 . "\n";
		print STDERR "Using settings:\n";
		print STDERR "  Variable: $_ -> $settings{$_}\n"
			foreach (keys %settings);
		print STDERR '-' x 72 . "\n";
	}

	Usage() if (!defined $ARGV[0]);

	if ($ARGV[0] eq 'debug')
	{
		if ($#ARGV == 3 and $ARGV[1] eq 'vercompare')
		{
			my $res;
			print 'vercompare: ';
			if ($ARGV[2] eq $ARGV[3]) {
				$res = '=';
			} elsif (vercompare($ARGV[2], $ARGV[3])) {
				$res = '>';
			} else {
				$res = '<';
			}
			print "$ARGV[2] $res $ARGV[3]\n";

			exit 0;
		} else {
			Usage();
		}
	}

	print APPNAME.' v'.APPVER.', by '.AUTHOR."\n\n";

	SwitchUser();

	# Load stuff specific to the database engine we're using

	$dbengine = $settings{db_connstr};
	$dbengine =~ s/^\s*DBI:([A-Za-z0-9]+):?.*$/$1/;

	Portscout::SQL->Load($dbengine)
		or die 'Failed to load queries for DBI engine "' . $dbengine . '"';

	# Check DB schema version

	if (getdbver() != DB_VERSION) {
		print STDERR "Database schema mismatch; did you forget to upgrade?\n";
		exit 1;
	}

	if ($dbengine eq 'SQLite' && $settings{num_children} > 0) {
		print STDERR "SQLite is currently only supported in non-forking mode!\n"
			. "--> Forcing num_children => 0...\n\n";
		$settings{num_children} = 0;
		sleep 2;
	}

	$datasrc = Portscout::DataSrc->new(
		$settings{datasrc},
		$settings{datasrc_opts}
	);

	exit (ExecArgs($ARGV[0]) ? 0 : 1);
}


#------------------------------------------------------------------------------
# Func: ExecArgs()
# Desc: Initiate primary operation requested by user.
#
# Args: $cmd     - Command to execute
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub ExecArgs
{
	my ($cmd) = @_;

	my $res;

	if ($cmd eq 'build')
	{
		print "-- [ Building ports database ] -----------------------------------------\n\n";
		$res = $datasrc->Build();
	}
	elsif ($cmd eq 'check')
	{
		print "-- [ Checking ports distfiles ] ----------------------------------------\n\n";

		Proc::Queue::size($settings{num_children})
			unless($settings{num_children} == 0);
		$res = Check();
	}
	elsif ($cmd eq 'generate')
	{
		Portscout::Template->templatedir($settings{templates_dir});
		Portscout::Template->outputdir($settings{html_data_dir});

		$res = GenerateHTML();
	}
	elsif ($cmd eq 'rebuild')
	{
		$res = $datasrc->Rebuild();
	}
	elsif ($cmd eq 'mail')
	{
		Portscout::Template->templatedir($settings{templates_dir});

		if ($settings{mail_method} ne 'sendmail') {
			MIME::Lite->send($settings{mail_method}, $settings{mail_host});
		}

		$res = MailMaintainers();
	}
	elsif ($cmd eq 'showupdates')
	{
		$res = ShowUpdates();
	}
	elsif ($cmd eq 'add-mail' or $cmd eq 'remove-mail')
	{
		my (@addrs) = @ARGV; # Should be a list of addrs
		shift @addrs;        # Remove $cmd

		Usage() if (!@addrs);

		$res = ($cmd eq 'add-mail')
			? AddMailAddrs(@addrs)
			: RemoveMailAddrs(@addrs);
	}
	elsif ($cmd eq 'show-mail')
	{
		$res = ShowMailAddrs();
	}
	elsif ($cmd eq 'uncheck')
	{
		$res = Uncheck();
	}
	elsif ($cmd eq 'allocate')
	{
		$res = AllocatePorts();
	}
	else
	{
		Usage();
	}

	return $res;
}


#------------------------------------------------------------------------------
# Func: Check()
# Desc: Using the information found from a run of Build(), attempt to
#       identify ports with possible updated distfiles.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub Check
{
	my (%sths, @workblock, $dbh, $nofork, $num_rows, $i);

	$nofork = ($settings{num_children} == 0);

	$dbh = connect_db();

	prepare_sql($dbh, \%sths, qw(portdata_count portdata_select));

	STDOUT->autoflush(1);

	$sths{portdata_count}->execute(lc hostname());
	($num_rows) = $sths{portdata_count}->fetchrow_array;

	$sths{portdata_select}->execute(lc hostname());

	if ($nofork) {
		prepare_sql($dbh, \%sths,
			qw(portdata_setchecked portdata_setnewver
			   sitedata_select sitedata_failure sitedata_success
			   sitedata_initliecount sitedata_decliecount)
		);
	}

	$i = 0;

	while (my $port = $sths{portdata_select}->fetchrow_hashref)
	{
		my $want = 0;

		$i++;

		$want = wantport($port->{name}, $port->{cat}, $port->{maintainer});

		if ($nofork) {
			# This is all we need if we're not forking.
			VersionCheck($dbh, \%sths, $port) if $want;
			next;
		}

		push @workblock, $port if ($port and $want);

		next if (!$want and $i < $num_rows);

		# Got enough work?
		if ($#workblock > $settings{workqueue_size} or $i == $num_rows)
		{
			my $pid = fork;

			die "Cannot fork: $!" unless (defined $pid);

			if ($pid) {
				# Parent
				my $progress = $num_rows - $i;
				print "Spawned PID #$$ ($progress ports unallocated)\n";
				undef @workblock;
			} else {
				# Child

				my (%sths, $dbh, $time);

				$time = time;

				$dbh = connect_db(1);

				prepare_sql($dbh, \%sths,
					qw(portdata_setchecked portdata_setnewver
					   sitedata_select sitedata_failure sitedata_success
					   sitedata_initliecount sitedata_decliecount)
				);

				while (my $port = pop @workblock) {
					VersionCheck($dbh, \%sths, $port);
				}

				finish_sql($dbh, \%sths);
				$dbh->disconnect;

				$time = (time - $time);
				print "PID #$$ finished work block (took $time seconds)\n";

				exit;
			}

			(1) while (waitpid(-1, WNOHANG) > 0);
		}
	}

	(1) while (wait != -1);

	if ($sths{portdata_select}->rows == 0) {
		print "No ports found.\n";
	} else {
		print !$nofork
			? "Master process finished. All work has been distributed.\n"
			: "Finished.\n";
	}

	finish_sql($dbh, \%sths);

	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: Uncheck()
# Desc: Reset all newver, status, and checked fields in database - equivalent
#       to doing a fresh build.
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub Uncheck
{
	my ($dbh, $sth);

	$dbh = connect_db();

	$sth = $dbh->prepare($Portscout::SQL::sql{portdata_uncheck})
		or die DBI->errstr;

	print "Resetting 'check' data...\n";

	$sth->execute;

	$sth->finish;
	$dbh->disconnect;
}


#------------------------------------------------------------------------------
# Func: VersionCheck()
# Desc: Check for an updated version of one particular port.
#
# Args: $dbh   - Database handle
#       \%sths - Prepared database statements
#       \$port - Port data extracted from database
#
# Retn: n/a
#------------------------------------------------------------------------------

sub VersionCheck
{
	my ($dbh, $sths, $port) = @_;

	my ($k, $i);

	$k = $port->{name};
	$i = 0;

	# Override MASTER_SITES if requested
	$port->{mastersites} = $port->{indexsite} if ($port->{indexsite});

	return if (!$port->{distfiles} || !$port->{mastersites});

	info($k, 'VersionCheck()');

	# Loop through master sites
	$sths->{sitedata_select}->execute($port->{mastersites});

	while (my $sitedata = $sths->{sitedata_select}->fetchrow_hashref)
	{
		my (@files, @dates, $site, $path_ver, $new_found, $old_found);

		$old_found = 0;
		$new_found = 0;

		$site = (grep /:\/\/\Q$sitedata->{host}\E\//, (split ' ', $port->{mastersites}))[0]
			or next;

		$site = URI->new($site)->canonical;

		last if ($i >= $settings{mastersite_limit});

		$i++;

		info($k, 'Checking site: ' . strchop($site, 60));

		# Look to see if the URL contains the distfile version.
		# This will affect our checks and guesses later on.
		if ($port->{ver} =~ /^(?:\d+\.)+\d+$/
				or $port->{ver} =~ /$date_regex/i) {
			my ($lastdir, $majver);

			$lastdir = uri_lastdir($site);

			# Also check version sans last number if >= 3 numbers
			# In other words, the "major" version.
			# This could be emulated for date strings, but it
			# gets a bit messy deciphering that format.
			if ($port->{ver} =~ /^(?:\d+\.){2,}\d+$/) {
				$majver = $port->{ver};
				$majver =~ s/\.\d+$//;
			}

			# Look for a match
			if ($lastdir eq $port->{ver}) {
				# Last directory = current version
				$path_ver = $lastdir;
			} elsif ($majver && $lastdir eq $majver) {
				# Last directory = current major version
				$path_ver = $lastdir;
			}
		}

		# Check for special handler for this site first
		if (my $sh = Portscout::SiteHandler->FindHandler($site))
		{
			info($k, $site, 'Using dedicated site handler for site.');

			if (!$sh->GetFiles($site, $port, \@files)) {
				info($k, $site, 'SiteHandler::GetFiles() failed for ' . $site);
				next;
			}
		}
		elsif ($site->scheme eq 'ftp')
		{
			my $ftp;

			$ftp = Net::FTP->new(
				$site->host,
				Port    => $site->port,
				Timeout => $settings{ftp_timeout},
				Debug   => $settings{debug},
				Passive => $settings{ftp_passive}
			);

			if (!$ftp) {
				info($k, $site, 'FTP connect problem: ' . $@);
				$sths->{sitedata_failure}->execute($site->host)
					unless ($settings{precious_data});
				next;
			}

			my $ftp_failures = 0;
			while ($ftp_failures <= $settings{ftp_retries}) {
				if (!$ftp->login('anonymous')) {
					info($k, $site, 'FTP login error: ' . $ftp->message);

					if ($ftp_failures == 0) {
						$sths->{sitedata_failure}->execute($site->host)
							unless ($settings{precious_data});
					}

					$ftp_failures++;

					if ($ftp->message =~ /\b(?:IP|connections|too many|connected)\b/i) {
						my $rest = 2+(int rand 15);
						info($k, $site,
							"Retrying FTP site in $rest seconds "
							. "(attempt $ftp_failures of "
							. "$settings{ftp_retries})"
						);
						sleep $rest;
						next;
					} else {
						last;
					}
				}

				$ftp_failures = 0;
				last;
			}

			next if ($ftp_failures);

			# This acts as an error check, so we'll cwd to our
			# original directory even if we're not going to look
			# there.
			if (!$ftp->cwd($site->path || '/')) {
				$ftp->quit;
				info($k, $site, 'FTP cwd error: ' . $ftp->message);
				$sths->{sitedata_failure}->execute($site->host)
					unless ($settings{precious_data});
				next;
			}

			@files = $ftp->ls;

			if (!@files) {
				info($k, $site, 'FTP ls error (or no files found): ' . $ftp->message);
				$ftp->quit;
				next;
			}

			# Did we find a version in site path earlier? If so,
			# we'll check the parent directory for other version
			# directories.
			if ($path_ver) {
				my ($path);
				my $site = $site->clone;
				uri_lastdir($site, undef);
				$path = $site->path;

				# Parent directory
				if ($ftp->cwd($site->path)) {
					foreach my $dir ($ftp->ls) {
						# Potential sibling version dirs
						if ($dir =~ /^(?:\d+\.)+\d+$/
								or $dir =~ /$date_regex/i) {
							$site->path("$path$dir");
							if ($ftp->cwd($site->path)) {
								# Potential version files
								push @files, "$path$dir/$_"
									foreach ($ftp->ls);
							}
						}
					}
				}
			}

			$ftp->quit;

			if (!@files) {
				info($k, $site, 'No files found.');
				next;
			}
		}
		else
		{
			my ($ua, $response);

			unless (robotsallowed($dbh, $site, $sitedata)) {
				info($k, $site, 'Ignoring site as per rules in robots.txt.');

				# Don't count 'robots' bans as a failure.
				# (We fetch them from the database so that
				# they can be re-checked every so often.)
				$i--;

				next;
			}

			$ua = LWP::UserAgent->new;
			$ua->agent(USER_AGENT);
			$ua->timeout($settings{http_timeout});

			$response = $ua->get($site);

			# A 404 here ought to imply that the distfile
			# is unavailable, since we expect it to be
			# inside this directory. However, some sites
			# use scripts or rewrite rules disguised as
			# directories.

			if ($response->is_success) {
				extractfilenames($response->content, $port->{sufx},
					\@files, \@dates);

				if (@files && $path_ver) {
					# Directory listing a success: we can
					# investigate $path_ver variations...
					my $site = $site->clone;
					my (@dirs, $path);

					# Visit parent directory

					uri_lastdir($site, undef);
					$path = $site->path;

					$response = $ua->get($site);

					extractdirectories($response->content, \@dirs)
						if ($response->is_success);

					# Investigate sibling version dirs

					foreach my $dir (@dirs) {
						if ($dir =~ /^(?:\d+\.)+\d+$/
								or $dir =~ /$date_regex/i) {
							my @files_tmp;

							$site->path("$path$dir");
							$response = $ua->get($site);

							extractfilenames(
								$response->content,
								$port->{sufx},
								\@files_tmp,
								\@dates
							) if ($response->is_success);

							push @files, "$path$dir/$_"
								foreach (@files_tmp);
						}
					}
				}
			}

			if ($settings{debug}) {
				print STDERR "Files for $port->{cat}/$port->{name} from $site:\n";
				print STDERR "  --> $_\n"
					foreach @files;
			}

			# No files found - try some guesses
			if (!@files && !$port->{indexsite})
			{
				my (%headers, $ua, $response, $url);

				my $bad_mimetypes = 'html|text|css|pdf|jpeg|gif|png|image|mpeg|bitmap';

				$ua = LWP::UserAgent->new;
				$ua->agent(USER_AGENT);
				$ua->timeout($settings{http_timeout});

				$url = $site;
				$url .= '/' unless $url =~ /\/$/;

				# We keep a counter of "lies" from each site, and only
				# re-check every so often.

				if ($sitedata->{liecount} > 0) {
					info($k, $site, 'Not doing any guessing; site has previously lied.');
					$sths->{sitedata_decliecount}->execute($sitedata->{host})
						unless($settings{precious_data});
					next;
				}

				# Verify site gives an error for bad filenames

				$response = $ua->head($url.randstr(8).'_shouldntexist.tar.gz');
				%headers  = %{$response->headers};

				# Got a response which wasn't HTTP 4xx -> bail out
				if ($response->is_success && $response->status_line !~ /^4/) {
					info($k, $site, 'Not doing any guessing; site is lieing to us.');
					$sths->{sitedata_initliecount}->execute($sitedata->{host})
						unless($settings{precious_data});
					next;
				}

				foreach (
					verguess(
						$port->{newver} ? $port->{newver} : $port->{ver},
						$port->{limitwhich}
					)
				) {
					my $guess_v = $_;
					my $old_v   = quotemeta $port->{ver};
					my $s       = quotemeta $port->{sufx};

					# Only change major version if port isn't
					# version-specific

					if ($port->{limitver}) {
						next unless ($guess_v =~ /$port->{limitver}/);
					} elsif ($port->{name} =~ /^(.*\D)(\d{1,3})(?:[-_]\D+)?$/) {
						my $nm_nums = $2;
						my $vr_nums = $guess_v;
						my $vo_nums = $old_v;

						unless (($1.$2) =~ /(?:md5|bz2|bzip2|rc4|rc5|ipv6|mp3|utf8)$/i) {
							my $fullver = "";
							while ($vo_nums =~ s/^(\d+?)[-_\.]?//) {
								$fullver .= $1;
								last if ($fullver eq $nm_nums);
							}

							if ($fullver eq $nm_nums) {
								$vr_nums =~ s/[-_\.]//g;
								next unless ($vr_nums =~ /^$nm_nums/);
							}
						}
					}

					if ($port->{skipversions}) {
						my @skipvers = split /\s+/, $port->{skipversions};
						arrexists(\@skipvers, $guess_v)
							and next;
					}

					info($k, $site, "Guessing version $port->{ver} -> $guess_v");

					foreach my $distfile (split ' ', $port->{distfiles})
					{
						my $site = $site->clone;

						next unless ($distfile =~ s/$old_v/$guess_v/gi);

						if ($path_ver) {
							my ($path);
							uri_lastdir($site, undef);
							$path = $site->path;
							if ($path_ver ne $port->{ver}) {
								# Major ver in site path
								my $guess_maj = $guess_v;
								$guess_maj =~ s/\.\d+$//;
								$site->path("$path$guess_maj/");
							} else {
								# Full ver in site path
								$site->path("$path$guess_v/");
							}
						}

						my $response = $ua->head($url.$distfile);
						my %headers  = %{$response->headers};

						if ($response->is_success && $response->status_line =~ /^2/ &&
								$headers{'content-type'} !~ /($bad_mimetypes)/i) {
							info($k, $site, "UPDATE $port->{ver} -> $guess_v");

							$sths->{portdata_setnewver}->execute(
								$guess_v, METHOD_GUESS, $url.$distfile,
								$port->{id}, $port->{id}
							) unless ($settings{precious_data});

							$new_found = 1;
							last;
						} else {
							info($k, $site, "Guess failed $port->{ver} -> $guess_v");
						}

						last if ($new_found);
					}

					last if ($new_found);
				}
			}

			last if ($new_found);
		}

		# Make note of working site
		$sths->{sitedata_success}->execute($site->host);

		next if (!@files);

		my $file = FindNewestFile($port, $site, \@files);

		$old_found = 1 if $file->{oldfound};

		if ($file && $file->{newfound}) {
			info($k, $site, "UPDATE $port->{ver} -> $file->{version}");
			$sths->{portdata_setnewver}->execute(
				$file->{version},
				METHOD_LIST,
				$file->{url},
				$port->{id},
				$port->{id}
			) unless ($settings{precious_data});

			last;
		}

		last if ($old_found && $settings{oldfound_enable});
	}

	# Update checked timestamp
	$sths->{portdata_setchecked}->execute($port->{id}, $port->{id})
		unless ($settings{precious_data});

	info($k, 'Done');
}


#------------------------------------------------------------------------------
# Func: FindNewestFile()
# Desc: Given an array of files, try to determine if any are newer than our
#       current version, and return the newest, if any.
#
# Args: \%port  - Port hash from database.
#       $site   - Site URL.
#       \@files - Files returned from spidering (+ absolute path or no path).
#
# Retn: \%res   - Hash containing file info:
#                   newfound - True if we found a suitable file.
#                   oldfound - True if we found the "current" file.
#                   version  - Version of file found.
#                   url      - URL of file.
#------------------------------------------------------------------------------

sub FindNewestFile
{
	my ($port, $site, $files) = @_;

	my ($poss_match, $poss_url, $old_found, $new_found);

	foreach my $file (@$files)
	{
		my $poss_path;

		if ($file =~ /^(.*)\/(.*?)$/) {
			# Files from SiteHandlers can come with paths
			# attached; we're only handling absolute paths
			# here though (XXX: future handlers?)
			$poss_path = $1;
			$file = $2;
		} else {
			$poss_path = '';
		}

		foreach my $distfile (split ' ', $port->{distfiles})
		{
			my $v = $port->{ver};
			my $s = $port->{sufx};

			my $old_v = $v;

			my $skip = 0;

			if ($poss_path) {
				# Do a full-URL comparison for $old_found
				# if we're dealing with paths too.
				my ($new_url, $old_url);

				# $site + abs. path
				$new_url = $site->clone;
				$new_url->path($poss_path.'/'.$file);

				# $site + filename
				$old_url = $site->clone;
				uri_filename($old_url, $distfile);

				if (URI::eq($old_url, $new_url)) {
					$old_found = 1;
					next;
				}
			} else {
				if ($file eq $distfile) {
					$old_found = 1;
					next;
				}
			}

			# Skip beta versions if requested

			if ($port->{skipbeta}) {
				if (isbeta($file) && !isbeta($distfile)) {
					next;
				}
			}

			# Weed out some bad matches

			if ($settings{freebsdhacks_enable}) {
				foreach (@bad_versions) {
					if ($file =~ /$_/i && $distfile !~ /$_/i) {
							$skip = 1;
						last;
					}
				}
			}

			next if ($skip);

			# XXX Force number at start - is this reasonable?
			# XXX: multiple occurences of $v in distfile?

			next unless ($distfile =~ s/^(.*?)\Q$v\E(.*)$/\Q$1\E(\\d.*?)\Q$2\E/);

			# Possible candidate - extract version

			if ($file =~ /^($distfile)$/ && $2)
			{
				my $version = $2;
				my $new_v = lc $version;

				# Catch a few missed cases

				$new_v =~ s/(?:$ext_regex)$//;

				# Version is much longer than original - skip it

				next if (length $new_v > (12 + length $old_v));

				# New version is in date format (or contains a date-like
				# string) - old one is not. Probably best to ignore.

				next if (
					$new_v =~ /$date_regex/i &&
					$old_v !~ /$date_regex/i
				);

				# Skip a few strange version format change cases
				# (formatted -> "just a number")

				next if ($new_v !~ /\./ && $old_v =~ /\./);

				# Skip any specific versions if requested

				if ($port->{skipversions}) {
					my $skip = 0;

					foreach (split (/\s+/, $port->{skipversions})) {
						if ($new_v eq $_) {
							$skip = 1;
							last;
						}
					}

					next if ($skip);
				}

				unless ($settings{sillystrings_enable}) {
					if ($new_v =~ /[-_.]([A-Za-z]+[A-Za-z_-]{2,})$/) {
						my $str = $1;
						next if (
							$old_v !~ /[-_.]$str$/
							&& ($str !~ /^($beta_regex)$/i
								|| length $1 < length $str) # short RE match
						);
					}
				}

				# Only allow new major version if port isn't
				# version-specific

				if ($port->{limitver}) {
					next unless ($new_v =~ /$port->{limitver}/);
				} elsif ($port->{name} =~ /^(.*\D)(\d{1,3})(?:[-_]\D+)?$/) {
					my $nm_nums = $2;
					my $vr_nums = $new_v;
					my $vo_nums = $old_v;

					unless (($1.$2) =~ /(?:md5|bz2|bzip2|rc4|rc5|ipv6|mp3|utf8)$/i) {
						my $fullver = '';
						while ($vo_nums =~ s/^(\d+?)[-_\.]?//) {
							$fullver .= $1;
							last if ($fullver eq $nm_nums);
						}

						if ($fullver eq $nm_nums) {
							$vr_nums =~ s/[-_\.]//g;
							next unless ($vr_nums =~ /^$nm_nums/);
						}
					}
				}

				if (defined $port->{limiteven} and $port->{limitwhich} >= 0) {
					next unless checkevenodd(
						$new_v,
						$port->{limiteven},
						$port->{limitwhich}
					);
				}

				# Test our new version string

				if ($new_v eq $old_v)
				{
					$old_found = 1;
				}
				elsif (vercompare($new_v, $old_v))
				{
					$new_found = 1;

					# Keep going until we find the newest version
					if (!defined($poss_match) or vercompare($version, $poss_match)) {
						$poss_match = $version;

						$poss_url = $site->clone;

						if ($poss_path) {
							$poss_url->path($poss_path);
						}

						$poss_url->path($poss_url->path . '/')
							if ($poss_url !~ /\/$/);

						uri_filename($poss_url, $file);

						next;
					}
				}
			}
		}
	}

	# Compare version to previously found new version,
	# if any. Don't bother reporting an older version.
	if ($port->{newver} && !vercompare($poss_match, $port->{newver})) {
		$new_found  = undef;
		$poss_match = undef;
		$poss_url   = undef;
	}

	return {
		'newfound' => $new_found,
		'oldfound' => $old_found,
		'version'  => $poss_match,
		'url'      => $poss_url
	};
}


#------------------------------------------------------------------------------
# Func: robotsallowed()
# Desc: Determine if a given site blocks robots (or us, specifically).
#
# Args: $dbh     - Database handle, connected.
#       $url     - URL we intend to fetch.
#       $site    - Relevant record (hash ref.) from sitedata table.
#
# Retn: $allowed - Are we permitted to spider site?
#------------------------------------------------------------------------------

sub robotsallowed
{
	my ($dbh, $url, $site) = @_;

	my (@paths, $allowed, $sitepath, $pathmatch);

	# Checks enabled?
	if (!$settings{robots_enable}) {
		return 1;
	}

	# Do our records need updating?
	if ($site->{robots_outofdate} || $site->{robots} == ROBOTS_UNKNOWN) {
		my ($ua, $response);

		print STDERR "(Robots) Processing robots.txt for $site->{host}\n"
			if ($settings{debug});

		$ua = LWP::UserAgent->new;
		$ua->agent(USER_AGENT);
		$ua->timeout($settings{http_timeout});

		$response = $ua->get('http://' . $site->{host} . '/robots.txt');

		if ($response->is_success) {
			if ($response->status_line =~ /^4/) {
				# HTTP 404 = no blocks. We can roam free.
				$allowed = ROBOTS_ALLOW;

				print STDERR "(Robots) No robots.txt for $site->{host}\n"
					if ($settings{debug});
			} else {
				# Process rules
				my ($data, $agentmatch);

				$allowed = ROBOTS_ALLOW;

				$data = $response->content;

				foreach (split /[\r\n]+/, $data) {
					my $rule = $_;
					$rule =~ s/^\s*//;
					$rule =~ s/#.*$//;
					$rule =~ s/\s*$//;

					if ($rule =~ s/^User-Agent:\s*//i) {
						my $agent_regex;

						# Build a regex from the wildcard
						# expression. Ignores the possibility
						# of escaped asterisks.
						$agent_regex = '^.*';
						foreach (split /(\*)/, $rule) {
							if ($_ eq '*') {
								$agent_regex .= '.*';
							} else {
								$agent_regex .= quotemeta $_
									unless $_ eq '';
							}
						}
						$agent_regex .= '.*$';

						if (USER_AGENT =~ /$agent_regex/i) {
							my $app_regex = '.*' . quotemeta(APPNAME) . '.*';

							if ($rule =~ /$app_regex/i) {
								$allowed = ROBOTS_SPECIFIC;
							} elsif ($allowed != ROBOTS_SPECIFIC) {
								$allowed = ROBOTS_BLANKET;
							}

							$agentmatch = 1;
						} else {
							$agentmatch = 0;
						}

						print STDERR "(Robots) Rule found for $site->{host} -> $rule "
						             . "(matched: $agentmatch; type: $allowed)\n"
							if ($settings{debug});

						next;
					}

					if ($rule =~ /^(?:Allow|Disallow):/i && !defined $agentmatch) {
						# No User-Agent was specified, so
						# assume '*' is implied.
						$allowed = ROBOTS_BLANKET;
						$agentmatch = 1;
					}

					if ($agentmatch && $rule =~ s/^Disallow:\s*//i) {
						$rule = '/' if ($rule eq '');
						push @paths, $rule;
					}
				}
			}
		} else {
			# Couldn't access server for some reason.
			# Assume we're allowed for now, but it's
			# probable that the site will fail later
			# on anyway.
			return 1;
		}

		if (!$settings{precious_data}) {
			my %sths;
			prepare_sql($dbh, \%sths, 'sitedata_setrobots');
			$sths{sitedata_setrobots}->execute($allowed, join("\n", @paths), $site->{host});
			finish_sql($dbh, \%sths);
		}
	} else {
		$allowed = $site->{robots};
		@paths = split(/\n+/, $site->{robots_paths});
	}

	# See if we're trying to access a banned path.

	$sitepath = $url;
	$sitepath =~ s/^[A-Z0-9]+:\/\///i;
	$sitepath =~ s/^[^\/]*//;

	$pathmatch = 0;

	foreach (@paths) {
		my $pathstart = substr($sitepath, 0, length $_);
		if ($pathstart eq $_) {
			$pathmatch = 1;
			print STDERR "(Robots) Path matched for $site->{host} ($_)\n"
				if ($settings{debug});
			last;
		}
	}

	return 1 if !$pathmatch;

	if ($settings{robots_checking} eq 'strict') {
		# Explicit 'allow' only
		return ($allowed == ROBOTS_ALLOW);
	} else {
		# Ignore blanket bans
		return ($allowed != ROBOTS_SPECIFIC);
	}
}


#------------------------------------------------------------------------------
# Func: GenerateHTML()
# Desc: Build web pages based on database data.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub GenerateHTML
{
	my (%sths, %outdata, @time, $dbh, $sth, $template);

	$dbh = connect_db();

	prepare_sql($dbh, \%sths,
		qw(portdata_genresults portdata_selectall portdata_selectall_limited)
	);

	if ($Portscout::SQL::sql{portdata_genresults_init}) {
		# SQLite needs to create the temp. table
		# in a separate statement.
		$dbh->do($Portscout::SQL::sql{portdata_genresults_init});
	}

	print "Organising results...\n";
	$sths{portdata_genresults}->execute;

	emptydir($settings{html_data_dir});

	# Put together some output data for the templates

	@time = ($settings{local_timezone} eq 'GMT') ? gmtime : localtime;
	$outdata{date} = sprintf('%d-%02d-%02d', $time[5]+1900, ++$time[4], $time[3]);
	$outdata{time} = sprintf('%02d:%02d', $time[2], $time[1]);
	$outdata{appname} = APPNAME;
	$outdata{appver}  = APPVER;
	$outdata{author}  = AUTHOR;

	$template = Portscout::Template->new('index.html')
		or die "index.html template not found!\n";

	# Produce indices, sorted by each header

	foreach my $sortby ('withnewdistfile', 'maintainer', 'total', 'percentage')
	{
		my ($sth, $orderby);

		$orderby = ($sortby eq 'maintainer') ? 'ASC' : 'DESC';

		$template->applyglobal(\%outdata);

		print "Generating index sorted by $sortby...\n";
		$sth = $dbh->prepare("SELECT * FROM results ORDER BY $sortby $orderby")
			or die DBI->errstr;
		$sth->execute;

		while (my $row = $sth->fetchrow_hashref) {
			$row->{percentage} = sprintf('%.2f%', $row->{percentage})
				if ($row->{percentage});
			$template->pushrow($row);
		}

		$sth->finish;

		$template->output("index-$sortby.html");
		$template->reset;
	}

	# Point index.html at the default sorted index

	symlink(
		"index-$settings{default_html_sort}.html",
		"$settings{html_data_dir}/index.html"
	);

	$template = undef;

	# Produce maintainer pages

	print "Creating maintainer pages...\n";

	$template = Portscout::Template->new('maintainer.html')
		or die "maintainer.html template not found!\n";

	$sth = $dbh->prepare('SELECT DISTINCT maintainer FROM results')
		or die DBI->errstr;
	$sth->execute;

	while (my ($addr) = $sth->fetchrow_array)
	{
		$outdata{maintainer} = $addr;
		$template->applyglobal(\%outdata);

		$sths{portdata_selectall}->execute($addr);
		while (my $row = $sths{portdata_selectall}->fetchrow_hashref) {
			if ($row->{ignore}) {
				$row->{method} = 'X';
				$row->{newver} = '';
				$row->{newurl} = '';
			} else {
				if ($row->{method} == METHOD_LIST) {
					$row->{method} = 'L';
				} elsif ($row->{method} == METHOD_GUESS) {
					$row->{method} = 'G';
				} else {
					$row->{method} = '';
				}
			}

			if ($row->{newver} && ($row->{ver} ne $row->{newver})) {
				$row->{newdistfile} = 'updated';
			} else {
				next if ($settings{hide_unchanged});
				$row->{newdistfile} = '';
			}
			$row->{updated} =~ s/:\d\d(?:\.\d+)?$/ $settings{local_timezone}/;
			$row->{checked} =~ s/:\d\d(?:\.\d+)?$/ $settings{local_timezone}/;

			$template->pushrow($row);
		}
		$template->output("$outdata{maintainer}.html");
		$template->reset;

		# We don't want this polluting the data
		# when the next template uses it.
		delete $outdata{maintainer};
	}

	$template = undef;

	print "Creating restricted ports (portconfig) page...\n";

	$template = Portscout::Template->new('restricted-ports.html')
		or die "restricted-ports.html template not found!\n";

	$sths{portdata_selectall_limited}->execute;
	$template->applyglobal(\%outdata);

	while (my $row = $sths{portdata_selectall_limited}->fetchrow_hashref) {
		$row->{limiteven}      = $row->{limiteven}  ? 'EVEN' : 'ODD';
		$row->{limitevenwhich} = $row->{limitwhich} ? ($row->{limitwhich}.':'.$row->{limiteven}) : '';

		$template->pushrow($row);
	}

	$template->output('restricted-ports.html');

	finish_sql($dbh, \%sths);
	$dbh->disconnect;
}


#------------------------------------------------------------------------------
# Func: MailMaintainers()
# Desc: Send a reminder e-mail to interested parties, about their ports.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub MailMaintainers
{
	my (%sths, $dbh, $template);

	if (!$settings{mail_enable}) {
		print "Reminder mails are disabled; taking no action.\n";
		return 1;
	}

	print "Mailing maintainers of out-of-date ports...\n\n";

	$dbh = connect_db();

	prepare_sql($dbh, \%sths,
		qw(maildata_select portdata_findnewnew portdata_setmailed)
	);

	$sths{maildata_select}->execute;

	$template = Portscout::Template->new('reminder.mail')
		or die "reminder.mail template not found!\n";

	while (my ($addr) = $sths{maildata_select}->fetchrow_array) {
		my $msg;
		my $ports = 0;
		$sths{portdata_findnewnew}->execute($addr);
		$template->applyglobal({maintainer => lc $addr});

		while (my $port = $sths{portdata_findnewnew}->fetchrow_hashref) {
			$port->{cat_portname} = "$port->{cat}/$port->{name}";
			$template->pushrow($port);
			$ports++;
		}

		if ($ports == 0) {
			$template->reset;
			next;
		}

		info($addr, "$ports new port(s) out of date");

		$msg = MIME::Lite->new(
			From     => $settings{mail_from} =~ /@/
			                ? $settings{mail_from}
			                : $settings{mail_from}.'@'.hostname(),
			To       => $addr,
			Subject  => $settings{mail_subject},
			Data     => $template->string
		);

		$msg->replace('X-Mailer' => USER_AGENT);

		$msg->send;

		$template->reset;

		# Second pass to mark port newvers as mailed

		if (!$settings{precious_data}) {
			$sths{portdata_findnewnew}->finish;
			$sths{portdata_findnewnew}->execute($addr);

			while (my $port = $sths{portdata_findnewnew}->fetchrow_hashref) {
				$sths{portdata_setmailed}->execute($port->{newver}, $port->{name}, $port->{cat});
			}
		}
	}

	finish_sql($dbh, \%sths);
	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: ShowUpdates()
# Desc: Produce a simple report showing ports with updates.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub ShowUpdates
{
	my (%sths, $dbh);

	$dbh = connect_db();

	prepare_sql($dbh, \%sths, 'portdata_selectupdated');

	$sths{portdata_selectupdated}->execute();

	my $maintainer;

	while (my $port = $sths{portdata_selectupdated}->fetchrow_hashref) {
		if (!$maintainer || lc $maintainer ne lc $port->{maintainer}) {
			print "\n" if ($maintainer);
			$maintainer = $port->{maintainer};
			print "${maintainer}'s ports:\n";
		}
		print "  $port->{cat}/$port->{name} $port->{ver} -> $port->{newver}\n";
	}

	finish_sql($dbh, \%sths);
	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: AddMailAddrs()
# Desc: Add e-mail address(es) to the opt-in results mail database.
#
# Args: @addrs   - List of addresses.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub AddMailAddrs
{
	my (%sths, $dbh);
	my (@addrs) = @_;

	$dbh = connect_db();

	prepare_sql($dbh, \%sths, 'maildata_exists', 'maildata_insert');

	while (my $addr = shift @addrs) {
		my ($exists);

		$addr =~ s/\s+//g;

		print "Adding $addr... ";

		$sths{maildata_exists}->execute($addr);
		($exists) = $sths{maildata_exists}->fetchrow_array;

		$sths{maildata_insert}->execute($addr)
			if (!$exists && !$settings{precious_data});

		print !$exists ? 'OK.' : 'already in database.';

		print "\n";

		$sths{maildata_exists}->finish;
	}

	$sths{maildata_insert}->finish;
	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: RemoveMailAddrs()
# Desc: Remove e-mail address(es) from the opt-in results mail database.
#
# Args: @addrs   - List of addresses.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub RemoveMailAddrs
{
	my (%sths, $dbh);
	my (@addrs) = @_;

	$dbh = connect_db();

	prepare_sql($dbh, \%sths, 'maildata_delete');

	while (my $addr = shift @addrs) {
		my $rows;

		$addr =~ s/\s+//g;

		print "Removing $addr... ";

		if (!$settings{precious_data}) {
			$sths{maildata_delete}->execute($addr);

			$rows = $sths{maildata_delete}->rows;
			print $rows ? 'OK.' : 'not in database.';
		}

		print "\n";
	}

	$sths{maildata_delete}->finish;
	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: ShowMailAddrs()
# Desc: List e-mail address(es) currently in the results mail database.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub ShowMailAddrs
{
	my (%sths, $dbh);

	$dbh = connect_db();

	prepare_sql($dbh, \%sths, 'maildata_select');
	$sths{maildata_select}->execute();

	print "Currently subscribed addresses:\n";

	while (my ($addr) = $sths{maildata_select}->fetchrow_array) {
		print "  $addr\n";
	}

	$sths{maildata_select}->finish;
	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: AllocatePorts()
# Desc: Divide up the ports database and allocate to machines in the portscout
#       cluster -- if there are any.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub AllocatePorts
{
	my (%sths, $dbh, $remaining);

	print "Checking for registered allocators...\n";

	if (!$settings{cluster_enable}) {
		print "Clustering disabled; taking no action.\n";
		return 1;
	}

	$dbh = connect_db();

	prepare_sql($dbh, \%sths,
		qw(portdata_countleft portdata_deallocate allocators_count
		   allocators_select)
	);

	$sths{portdata_deallocate}->execute
		unless ($settings{precious_data} or $settings{system_affinity});

	$sths{allocators_count}->execute;
	($remaining) = $sths{allocators_count}->fetchrow_array;

	if ($remaining <= 0) {
		print "Found none (portscout will run on just this machine)\n";
		return 1;
	} else {
		print "Allocating work using $remaining allocator rule(s)...\n";
	}

	for my $pass (0 .. 2)
	{
		print STDERR "Allocator pass $pass/2\n"
			if ($settings{debug});

		$sths{allocators_select}->execute;

		while (my $allocator = $sths{allocators_select}->fetchrow_hashref)
		{
			my ($query, $unallocated, $i);

			$query = q(UPDATE portdata
			              SET systemid = ?
			            WHERE moved != true
			              AND systemid is NULL);

			$sths{portdata_countleft}->execute;
			($unallocated) = $sths{portdata_countleft}->fetchrow_array;

			$i = ceil($unallocated / $remaining);

			print STDERR "--> Allocator loop ($unallocated, $remaining)\n"
				if ($settings{debug});

			if ($allocator->{allocator} eq 'random') {
				next unless ($pass == 2);

				$query .= " AND id IN (SELECT id FROM portdata LIMIT $i)"
					unless ($remaining == 1);

				$dbh->do($query, undef, $allocator->{systemid})
					unless ($settings{precious_data});
			} elsif ($allocator->{allocator} eq 'presplit') {
				next unless ($pass == 1);

				# XXX: Unimplemented
				print STDERR "Unsupported allocator (presplit) found.\n";
			} else {
				# Fixed constraints - allocate first
				next unless ($pass == 0);

				my (%constraints, $sth);

				foreach (split /,/, $allocator->{allocator}) {
					if (/^(maintainer|cat)=(.*)$/i) {
						$constraints{lc $1} = lc $2;
					} else {
						print STDERR "Unexpected constraint or wrong format ($_).\n";
						next;
					}
				}

				$query .= ' AND (1=0';
				$query .= " OR $_ = ?"
					foreach (keys %constraints);
				$query .= ')';

				$dbh->do($query, undef, $allocator->{systemid}, values %constraints)
					unless ($settings{precious_data});
			}

			$remaining--;
		}
	}

	finish_sql($dbh, \%sths);
	$dbh->disconnect;

	return 1;
}


#------------------------------------------------------------------------------
# Func: SwitchUser()
# Desc: Drop root privileges, switching to another user (if configured to).
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub SwitchUser
{
	if ($settings{group} && getgid() == 0) {
		my $gid = getgrnam($settings{group})
			or die "Couldn't determine GID from name $settings{group}\n";
		setgid($gid)
			or die "Couldn't switch to group $settings{group}";
	}

	if ($settings{user} && getuid() == 0) {
		my $uid = getpwnam($settings{user})
			or die "Couldn't determine UID from name $settings{user}\n";
		setuid($uid)
			or die "Couldn't switch to user $settings{user}";
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: Usage()
# Desc: Print usage message and exit.
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub Usage
{
	my $s = basename($0);

	print STDERR "Usage: \n";
	print STDERR "       $s build\n";
	print STDERR "       $s rebuild\n";
	print STDERR "       $s check\n";
	print STDERR "       $s uncheck\n";
	print STDERR "\n";
	print STDERR "       $s mail\n";
	print STDERR "       $s generate\n";
	print STDERR "       $s showupdates\n";
	print STDERR "\n";
	print STDERR "       $s add-mail user\@host ...\n";
	print STDERR "       $s remove-mail user\@host ...\n";
	print STDERR "       $s show-mail\n";
	exit 1;
}
