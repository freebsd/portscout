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
# $Id: Util.pm,v 1.12 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

package Portscout::Util;

use Portscout::Const;
use Portscout::Config;

require Exporter;

use strict;

require 5.006;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	$date_regex
	$beta_regex
	$month_regex
	$ext_regex

	&strchop
	&emptydir
	&isbeta
	&chopbeta
	&verguess
	&vercompare
	&betacompare
	&checkevenodd
	&extractfilenames
	&extractdirectories
	&info
	&randstr
	&arrexists
	&wantport
	&uri_filename
	&uri_lastdir
	&getdbver
	&getstat
	&setstat
	&prepare_sql
	&finish_sql
	&connect_db
);


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

our %settings;

our (@months, $date_regex, $beta_regex, $month_regex, $ext_regex);

my %beta_types;

my %want_regex = (
	port       => restrict2regex($settings{restrict_port}),
	category   => restrict2regex($settings{restrict_category}),
	maintainer => restrict2regex($settings{restrict_maintainer})
);

@months = (
	qr/Jan(?:uary)?/, qr/Feb(?:ruary)?/, qr/Mar(?:ch)?/, qr/Apr(?:il)?/,
	qr/May/, qr/Jun(?:e)?/, qr/Jul(?:y)?/, qr/Aug(?:ust)?/, qr/Sep(?:tember)?/,
	qr/Oct(?:ober)?/, qr/Nov(?:ember)?/, qr/Dec(?:ember)?/
);

$month_regex = 'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec';
$date_regex  = '(?<!\d)\d{4}([\-\.]?)(?:\d{2}|'.$month_regex.')\1\d{2}(?!\d)';

%beta_types = (
	snapshot   => { re => 'svn|cvs|snap(?:shot)?', rank => 1 },
	unstable   => { re => 'unstable|dev|test',     rank => 2 },
	alpha      => { re => 'alpha|a(?=\d+|$)',      rank => 3 },
	beta       => { re => 'beta|b(?=\d+|$)',       rank => 4 },
	prerelease => { re => 'pre.*?|p(?=\d+|$)',     rank => 5 },
	relcand    => { re => 'rc|r(?=\d+|$)',         rank => 6 }
);

$beta_regex = join '|', map +($beta_types{$_}->{re}), keys %beta_types;

$ext_regex   = '\.tar\.gz|\.tar\.bz2|\.tgz\|\.zip';


#------------------------------------------------------------------------------
# Func: strchop()
# Desc: Chop or pad string to $limit characters, using ellipses to contract.
#
# Args: $str   - String to manipulate.
#       $limit - Length of new string.
#
# Retn: $str   - Modified string.
#------------------------------------------------------------------------------

sub strchop
{
	my ($str, $limit) = @_;

	my $slen = int ($limit / 2) - 3;
	my $elen = ($limit - 3) - $slen;

	return '' if (!$str or !$limit);

	if (length $str > $limit)
	{
		return $str if ($str =~ s/^(.{$slen}).*(.{$elen})$/$1...$2/);
	}
	elsif (length $str < $limit)
	{
		return $str if $str .= ' ' x ($limit - length $str);
	}

	return $str;
}


#------------------------------------------------------------------------------
# Func: emptydir()
# Desc: Remove all files from a given directory, or create an empty directory
#       if it doesn't already exist.
#
# Args: $dir     - Directory to clear
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub emptydir
{
	my ($dir) = @_;

	return 0 if (!$dir);

	if (-d $dir) {
		opendir my $dh, "$dir";
		unlink "$dir/$_" foreach readdir($dh);
		closedir $dh;
	} else {
		mkdir $dir;
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: isbeta()
# Desc: Determine if a version (or filename) looks like a beta/alpha/dev't
#       version.
#
# Args: $version - Version or full filename.
#
# Retn: $isbeta  - Looks like beta?
#------------------------------------------------------------------------------

sub isbeta
{
	my ($version) = @_;

	return (
		$version =~ /^(.*)[-_.](?:$beta_regex).*$/gi
			or $version =~ /^(.*)(?<=\d)(?:$beta_regex).*$/gi
	);
}


#------------------------------------------------------------------------------
# Func: chopbeta()
# Desc: As above, but remove the beta extension from the string.
#
# Args: \$version - Version string.
#
# Retn: $isbeta   - Looks like beta (and therefore, $version modified)?
#------------------------------------------------------------------------------

sub chopbeta
{
	my ($version) = @_;

	$version = \$version if (!ref $version);

	return (
		$$version =~ s/^(.*)[-_.](?:$beta_regex)\d*(?:\.\d+)*(.*)$/$1$2/gi
			or $$version =~ s/^(.*)(?<=\d)(?:$beta_regex)\d*(?:\.\d+)*(.*)$/$1$2/gi
	);
}


#------------------------------------------------------------------------------
# Func: verguess()
# Desc: Guess possible "next version" values from given string.
#       For example: 1.4.2 -> (2.0.0, 1.5.0, 1.4.3)
#
# Args: $ver         - Current version string
#       $evenoddpart - Incremement nth component by TWO to keep even/odd
#
# Retn: @ver         - List of possible new versions
#------------------------------------------------------------------------------

sub verguess
{
	my ($ver, $evenoddpart) = @_;
	my @ver_guesses;

	return if (!$ver);

	my @vparts = split /(\D+)/, $ver;

	my $i = 0;
	for (0 .. $#vparts) {
		my $guess;

		my $v = $vparts[$i];

		if ($v =~ /^\d+$/) {
			if (defined $evenoddpart and $evenoddpart == $i/2) {
				$v+=2;
			} else {
				$v++;
			}
		} else {
			$i++;
			next;
		}

		$guess .= $vparts[$_] for (0 .. ($i - 1));
		$guess .= $v;

		for (++$i .. $#vparts) {
			if ($vparts[$_] =~ /^\d+$/) {
				$guess .= '0' x length $vparts[$_];
			} elsif ($vparts[$_] =~ /^-?[A-Z]+-?$/i) {
				last;
			} else {
				$guess .= $vparts[$_];
			}
		}

		push @ver_guesses, $guess;
	}

	return @ver_guesses;
}


#------------------------------------------------------------------------------
# Func: vercompare()
# Desc: Compare two version strings and return true if $new is greater than
#       $old; otherwise return false.
#
# Args: $ver    - New version string
#       $old    - Old version string
#
# Retn: $result - Is $new greater than $old? Returns -1 for "Maybe"
#------------------------------------------------------------------------------

sub vercompare
{
	my ($new, $old) = @_;

	if ($settings{version_compare} eq 'pkg_version') {
		my $res;

		$new = quotemeta $new;
		$old = quotemeta $old;

		$res = qx(pkg_version -t "$new" "$old");

		return (($res eq '>') ? 1 : 0);
	}

	# Attempt to stop false positives on versions that
	# look newer - e.g. 2.5 is newer than 2.5-prerelease3

	if (1) {
		my $_new = $new;
		my $_old = $old;

		my ($newbeta, $oldbeta, $newdots, $olddots);

		if (chopbeta(\$_new)) {
			# $new and $old equal except for beta bit
			# Therefore, $old (a final release) is newer
			return 0 if ($_new eq $old);

			$newbeta = 1;
		}

		if (chopbeta(\$_old)) {
			# $new and $old equal except for beta bit
			# Therefore, $new (a final release) is newer
			return 1 if ($_old eq $new);

			$oldbeta = 1;
		}

		$olddots = $_old;
		$olddots =~ s/[^.]//g;
		$olddots = length $olddots;

		$newdots = $_new;
		$newdots =~ s/[^.]//g;
		$newdots = length $newdots;

		if ($newbeta && $oldbeta && $newdots == $olddots) {
			# Both had beta bits; non-beta bits
			# have same number of components
			# Therefore, don't remove beta bits.

			# ... if just the non-beta bits
			# differ, compare them.
			return (betacompare($new, $old))
				if ($_new eq $_old);
		} else {
			# Remove beta bits, as non-beta bits
			# differ and can be compared.
			$new = $_new;
			$old = $_old;
		}
	}

	# If both version strings contain a date AND other
	# numbers, take care to split them and compare
	# individually.

	unless ($new =~ /^$date_regex$/i && $old =~ /^$date_regex$/i)
	{
		my $date_regex = $date_regex;
		$date_regex =~ s/\\1/\\3/g;		# Bump internal backreference (evil)

		if ($new =~ /^(.*?)[\-\.]?($date_regex)[\-\.]?(.*)$/i) {
			my ($new_1, $new_2, $new_3) = ($1, $2, $4);

			if ($old =~ /^(.*?)[\-\.]?($date_regex)[\-\.]?(.*)$/i) {
				my ($old_1, $old_2, $old_3) = ($1, $2, $4);

				if ($new_1 and $old_1) {
					return vercompare($new_1, $old_1) unless ($new_1 eq $old_1);
				}

				if ($new_2 and $old_2) {
					return vercompare($new_2, $old_2) unless ($new_2 eq $old_2);
				}

				if ($new_3 and $old_3) {
					return vercompare($new_3, $old_3) unless ($new_3 eq $old_3);
				} elsif ($new_3) {
					return 1;
				} else {
					return 0;
				}
			}
		}
	}

	# Give month names a numerical value

	if ($new =~ /$month_regex/i) {
		my $i = 1;
		foreach my $m (@months) {
			$new =~ s/$m/sprintf "%02d", $i/gie;
			$i++;
		}
	}

	if ($old =~ /$month_regex/i) {
		my $i = 1;
		foreach my $m (@months) {
			$old =~ s/$m/sprintf "%02d", $i/gie;
			$i++;
		}
	}

	my @nums_new = split /\D+/, $new;
	my @nums_old = split /\D+/, $old;

	foreach my $n (0 .. $#nums_new) {
		# New version component; all preceding
		# components are equal, so assume newer.
		return 1 if (!defined($nums_old[$n]));

		# Attempt to handle cases where version
		# component lengths vary.
		if (($n == $#nums_new) && (length $nums_new[$n] != length $nums_old[$n]))
		{
			my $lendiff_thresh;

			$lendiff_thresh =
				($nums_new[$n] =~ /^0/ && $nums_old[$n] =~ /^0/)
				? 1
				: 2;

			$nums_new[$n] = $nums_new[$n] . ('0' x length $1) if ($nums_old[$n] =~ /^(0+)/);
			$nums_old[$n] = $nums_old[$n] . ('0' x length $1) if ($nums_new[$n] =~ /^(0+)/);

			# Experimental code to catch (some) "backwards" version numbers

			my ($lendiff, $first_old, $first_new);

			$lendiff   = length($nums_new[$n]) - length($nums_old[$n]);
			$first_new = substr($nums_new[$n], 0, 1);
			$first_old = substr($nums_old[$n], 0, 1);

			if ($lendiff >= $lendiff_thresh) {
				if ($first_new > $first_old) {
					return -1;
				} elsif ($first_new == $first_old) {
					$nums_old[$n] .= ('0' x $lendiff);
					return ($nums_new[$n] > $nums_old[$n]) ? -1 : 0;
				} else {
					return 0;
				}
			} elsif ($lendiff <= -$lendiff_thresh) {
				if ($first_new < $first_old) {
					return 0;
				} elsif ($first_new == $first_old) {
					$nums_new[$n] .= ('0' x abs $lendiff);
					return ($nums_new[$n] < $nums_old[$n]) ? 0 : -1;
				} else {
					return -1;
				}
			}
		}

		# Otherwise, compare values numerically
		return 1 if (0+$nums_new[$n] > 0+$nums_old[$n]);
		return 0 if (0+$nums_new[$n] < 0+$nums_old[$n]);
	}

	# Fall back to string compare

	return (($new cmp $old) == 1) ? 1 : 0;
}


#------------------------------------------------------------------------------
# Func: betacompare()
# Desc: Compare beta bits of two versions strings and return true if $new is
#       greater than $old; otherwise return false.
#
#       Result is undefined if either string doesn't contain a beta portion.
#
# Args: $ver    - New version string
#       $old    - Old version string
#
# Retn: $result - Is $new greater than $old? Returns -1 for "Maybe"
#------------------------------------------------------------------------------

sub betacompare
{
	my ($new, $old) = @_;

	my $newrank = 0;
	my $oldrank = 0;
	my $newnums = 0;
	my $oldnums = 0;

	foreach my $bt (keys %beta_types) {
		my $re   = $beta_types{$bt}->{re};
		my $rank = $beta_types{$bt}->{rank};

		if ($new =~ /[-_.](?:$re)(\d*(?:\.\d+)*)/i
				or $new =~ /(?<=\d)(?:$re)(\d*(?:\.\d+)*)/i) {
			$newrank = $rank;
			$newnums = $1 if $1;
		}

		if ($old =~ /[-_.](?:$re)(\d*(?:\.\d+)*)/i
				or $old =~ /(?<=\d)(?:$re)(\d*(?:\.\d+)*)/i) {
			$oldrank = $rank;
			$oldnums = $1 if $1;
		}
	}

	if ($oldrank == $newrank) {
		my @nums_new = split /\D+/, $newnums;
		my @nums_old = split /\D+/, $oldnums;

		foreach my $n (0 .. $#nums_new) {
			# New version component; all preceding
			# components are equal, so assume newer.
			return 1 if (!defined($nums_old[$n]));

			return 1 if (0+$nums_new[$n] > 0+$nums_old[$n]);
			return 0 if (0+$nums_new[$n] < 0+$nums_old[$n]);
		}

		# All numbers equal
		return 0;
	}

	return ($newrank > $oldrank ? 1 : 0);
}


#------------------------------------------------------------------------------
# Func: checkevenodd()
# Desc: Check that a version component is either even or odd.
#
# Args: $version   - Version string to check
#       $evenodd   - True = force even; false = force false
#       $component - Zero-based component number to check
#
# Retn: $result    - true/false
#------------------------------------------------------------------------------

sub checkevenodd
{
	my ($version, $evenodd, $component) = @_;

	my @bits = split /\D+/, $version;

	return 0 if $#bits < $component;

	if ($bits[$component] % 2) {
		return !$evenodd;
	} else {
		return $evenodd;
	}
}


#------------------------------------------------------------------------------
# Func: extractfilenames()
# Desc: Extract filenames (and dates, where possible) from a mastersite index
#
# Args: $data    - Data from master site request.
#       $sufx    - Distfile suffix (e.g. ".tar.gz")
#       \$files  - Where to put filenames found.
#       \$dates  - Where to put dates found.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub extractfilenames
{
	my ($data, $sufx, $files, $dates) = @_;

	my $got_index = 0;

	$sufx = quotemeta $sufx;

	my $date_regex =
		'(?<!\d)(\d{2}(?:\d{2})?([\-\. ]?)(\d{2}|'
		. $month_regex . ')\4\d{2}(?:\d{2})?)(?!\d)'
		. '(?:\s*(?:(\d{2}):(\d{2}))?)?';

	# XXX: Work-in-Progress
	# XXX: @dates will contain garbage

	foreach (split "\n", $data) {
		while (/<a href=(['"])([^<>]*?$sufx)\1.*?<\/a>/gi) {
			push @$files, $2;
		}

		$got_index = /<title>\s*index of.*?<\/title>/i if (!$got_index);
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: extractdirectories()
# Desc: Extract directories from a mastersite index
#
# Args: $data    - Data from master site request.
#       \$dirs   - Where to put directories found.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub extractdirectories
{
	my ($data, $dirs) = @_;

	foreach (split "\n", $data) {
		while (/<a href=(['"])(.*?)\/\1.*?>\2(?:\/<\/a>|<\/a>\/)(?:.*?)/gi) {
			push @$dirs, $2;
		}
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: info()
# Desc: Format arguments into message and print.
#
# Args: @str - Array of message parts to chop and format.
#       $msg - Message to print unformatted after other parts.
#
# Retn: n/a
#------------------------------------------------------------------------------

sub info
{
	my @items = (@_);
	my ($str, $msg);

	return if ($settings{quiet});

	$msg = pop (@items);

	foreach (@items) {
		$str .= ' ' if ($str);
		$str .= '[' . strchop($_, 30) . ']';
	}

	print "$str $msg\n";
}


#------------------------------------------------------------------------------
# Func: randstr()
# Desc: Generate string of random characters
#
# Args: $len - Length of string to generate.
#
# Retn: $str - Random string.
#------------------------------------------------------------------------------

sub randstr
{
	my ($len) = @_;

	my @chars = ('a'..'z','A'..'Z','0'..'9');

	my $str;
	$str .= $chars[rand @chars] foreach (1 .. $len);

	return $str;
}


#------------------------------------------------------------------------------
# Func: arrexists()
# Desc: 'exists' for array values.
#
# Args: \@array - Array to search.
#       $value  - Value to check for.
#
# Retn: $exists - Does the value exist?
#------------------------------------------------------------------------------

sub arrexists
{
	my ($array, $value) = @_;

	foreach (@{$array}) {
		return 1 if ($_ eq $value);
	}

	return 0;
}


#------------------------------------------------------------------------------
# Func: wantport()
# Desc: Check the restriction lists are either empty or contain the specified
#       values.
#
# Args: $port       - Port name  (undef to skip)
#       $category   - Category   (undef to skip)
#       $maintainer - Maintainer (undef to skip)
#
# Retn: $result     - true = all values falls within constraints
#------------------------------------------------------------------------------

sub wantport
{
	my ($port, $category, $maintainer) = @_;

	my ($needed, $matched);

	$needed = 0;
	$matched = 0;

	if ($want_regex{maintainer} && defined $maintainer) {
		$needed++;

		$maintainer =~ $want_regex{maintainer}
			and $matched++;

		return 0 if ($matched != $needed);
	}

	if ($want_regex{category} && defined $category) {
		$needed++;

		$category =~ $want_regex{category}
			and $matched++;

		return 0 if ($matched != $needed);
	}

	if ($want_regex{port} && defined $port) {
		$needed++;

		if ($port =~ $want_regex{port}) {
			$matched++;
		} elsif (defined $category
				and "$category/$port" =~ $want_regex{port}) {
			$matched++;
		}

		return 0 if ($matched != $needed);
	}

	return ($matched == $needed);
}


#------------------------------------------------------------------------------
# Func: uri_filename()
# Desc: Given a URI object, set or return the filename component. We define
#       the filename to be everything after the last slash.
#
# Args: $uri      - URI object.
#       $filename - New filename (optional).
#
# Retn: $filename - Filename component.
#------------------------------------------------------------------------------

sub uri_filename
{
	my $uri = shift;
	my @segs = $uri->path_segments;
	my $curr = $segs[$#segs];

	if (scalar @_) {
		splice(@segs, -1, 1);
		$uri->path_segments(@segs, $_[0] || '');
	}

	return $curr;
}


#------------------------------------------------------------------------------
# Func: uri_lastdir()
# Desc: Given a URI object, set or return the last directory. We define this
#       to be the everything after the last slash, unless the slash is the
#       last character, in which case, return the previous component.
#
# Args: $uri     - URI object.
#       $lastdir - New directory (optional).
#
# Retn: $lastdir - Last directory component.
#------------------------------------------------------------------------------

sub uri_lastdir
{
	my $uri = shift;
	my @segs = $uri->path_segments;

	my $offs = $segs[$#segs] ? 0 : 1;
	my $curr = $segs[$#segs-$offs];

	if (scalar @_) {
		splice(@segs, -1-$offs, 1+$offs);
		if ($offs && $_[0]) {
			$uri->path_segments(@segs, $_[0], '');
		} else {
			$uri->path_segments(@segs, $_[0] || '');
		}
	}

	return $curr;
}


#------------------------------------------------------------------------------
# Func: restrict2regex()
# Desc: Convert a comma-separated list of values into a restriction regex for
#       use by wantport().
#
# Args: $csv - Comma-separated string; values may contain * and ? wildcards.
#
# Retn: $re  - Compiled regex.
#------------------------------------------------------------------------------

sub restrict2regex
{
	my ($csv) = @_;

	my @items = split /,/, $csv;

	foreach my $item (@items) {
		# Clean up
		$item =~ s/\s+$//;
		$item =~ s/^\s+//;
		$item = lc $item;

		# Quote literal stuff
		$item =~ s/([^*?]+)/\Q$1\E/g;

		# Transform wildcards to regex
		$item =~ s/\*+/.*/g;
		$item =~ s/\?/./g;
	}

	if (scalar @items) {
		my $list = join '|', @items;
		return qr/^(?:$list)$/i;
	} else {
		return undef;
	}
}


#------------------------------------------------------------------------------
# Func: getdbver()
# Desc: Return the current database schema version.
#
# Args: n/a
#
# Retn: $version - database version.
#------------------------------------------------------------------------------

sub getdbver
{
	my ($dbh, $sth, $ver);

	$dbh = connect_db();

	$sth = $dbh->prepare($Portscout::SQL::sql{portscout_version})
		or die DBI->errstr;
	$sth->execute;

	($ver) = $sth->fetchrow_array;

	$sth->finish;

	return $ver;
}


#------------------------------------------------------------------------------
# Func: getstat()
# Desc: Retrieve a value from the "stats" table.
#
# Args: $key  - Statistic name.
#       $type - Datum type (default: TYPE_STRING).
#
# Retn: $val  - Value from database.
#------------------------------------------------------------------------------

sub getstat
{
	my ($key, $type) = @_;

	my ($dbh, $sth, $val);

	$dbh = connect_db();

	$sth = $dbh->prepare($Portscout::SQL::sql{portscout_getstat})
		or die DBI->errstr;
	$sth->execute($key);

	($val) = $sth->fetchrow_array;

	$sth->finish;

	if ($type == TYPE_INT || $type == TYPE_BOOL) {
		$val = 0 + $val;
	}

	return $val;
}


#------------------------------------------------------------------------------
# Func: setstat()
# Desc: Set a value in the "stats" table.
#
# Args: $key - Statistic name.
#       $val - New value.
#
# Retn: n/a
#------------------------------------------------------------------------------

sub setstat
{
	my ($key, $val) = @_;

	my ($dbh, $sth);

	return if $settings{precious_data};

	$val = '' if !defined $val;

	$dbh = connect_db();

	$sth = $dbh->prepare($Portscout::SQL::sql{portscout_setstat})
		or die DBI->errstr;
	$sth->execute($val, $key);

	$sth->finish;

	return;
}


#------------------------------------------------------------------------------
# Func: prepare_sql()
# Desc: Prepare the named SQL statements.
#
# Args: $dbh     - Database handle, already connected.
#       \%sths   - Somewhere to put prepared statement handles
#       @queries - Names of queries to prepare -- from %sql hash.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub prepare_sql
{
	my ($dbh, $sths, @queries) = @_;

	foreach (@queries) {
		if (exists $Portscout::SQL::sql{$_}) {
			$$sths{$_} = $dbh->prepare($Portscout::SQL::sql{$_})
				or die DBI->errstr . "; statement \"$_\"";
		} else {
			print STDERR "Attempted to prepare non-existent SQL query ($_).\n";
			return 0;
		}
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: finish_sql()
# Desc: Finish specified SQL statements.
#
# Args: \$dbh    - Database handle, already connected.
#       \%sths   - The hash of prepared statement handles.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub finish_sql
{
	my ($dbh, $sths) = @_;

	$$sths{$_}->finish
		foreach (keys %$sths);

	return 1;
}


#------------------------------------------------------------------------------
# Func: connect_db()
# Desc: Connect to database.
#
# Args: $nocache - If set, force new connection.
#
# Retn: $dbh     - Database handle.
#------------------------------------------------------------------------------

my $g_dbh;

sub connect_db
{
	my ($nocache) = @_;

	my ($dbh);

	if ($nocache) {
		$dbh = DBI->connect(
			$settings{db_connstr},
			$settings{db_user},
			$settings{db_pass}
		) or die DBI->errstr;
	} else {
		$dbh = DBI->connect_cached(
			$settings{db_connstr},
			$settings{db_user},
			$settings{db_pass}
		) or die DBI->errstr;

		$g_dbh = $dbh; # Keep handle alive
	}

	Portscout::SQL->RegisterHacks($dbh);

	return $dbh;
}


1;
