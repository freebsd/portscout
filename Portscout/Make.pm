#------------------------------------------------------------------------------
# Copyright (C) 2006-2011, Shaun Amott <shaun@inerd.com>
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
# $Id: Make.pm,v 1.14 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

package Portscout::Make;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

my $root_dir;
my $make_cache;

my $maketype = 'freebsd';

my $debug = 0;

my %wanted = ();

my $qfail = 0;


#------------------------------------------------------------------------------
# Func: new()
# Desc: Constructor - does nothing useful.
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
# Accessor functions
#------------------------------------------------------------------------------

sub Root
{
	my $self = shift;

	if (@_) {
		$root_dir = shift;
		$root_dir =~ s/^(.+)\/$/$1/;
	}

	return $root_dir;
}

sub Wanted
{
	my $self = shift;

	%wanted = ();

	while (my $k = shift) {
		$wanted{$k} = 1
	}
}

sub Type
{
	my $self = shift;

	$maketype = lc shift if (@_);

	return $maketype;
}

sub Debug
{
	my $self = shift;

	$debug = shift if (@_);

	return $debug;
}


#------------------------------------------------------------------------------
# Func: Make()
# Desc: Ask make(1) to expand and return values for specified variables
#
# Args: $dir      - Directory to execute make in. Appends $root_dir
#                   if there's no leading slash.
#       @vars     - List of variables. (optional)
#
# Retn: [results] - Ref. to hash of results - unless there was only
#                   one variable, in which case return a string.
#------------------------------------------------------------------------------

sub Make
{
	my $self = shift;

	my ($dir, @vars) = @_;

	my (%results, @outp, $list, $cache, $lb);

	$cache = $make_cache ? $make_cache : '';

	$dir = "$root_dir/$dir" if ($dir !~ /^\//);

	@vars = keys %wanted if (scalar @vars == 0);

	if ($maketype eq 'freebsd') {
		$list = join(' -V ', @vars);
	} else {
		$list = join(' -V ',
			map {
				my $v = $_;
				$v =~ s/^(.*)$/'\${$1}'/;
				$v
			} @vars
		);
	}

	# Ensure we aren't affected by locally installed stuff
	$lb = 'LOCALBASE=/nonexistent';

	@outp = split /\n/, qx(make -C $dir -V $list $cache $lb 2>/dev/null);

	if ($?) {
		warn "make failed for $dir";
		return;
	}

	if ($#vars == 0) {
		return $outp[0];
	}

	foreach (@vars) {
		$results{$_} = shift @outp;
	}

	return \%results;
}


#------------------------------------------------------------------------------
# Func: InitCache()
# Desc: Prepare a cache of make(1) variables for Make(). This essentially
#       saves a dozen forks each time make is invoked, saving us precious
#       time while populating the database.
#
# Args: @vars    - List of variables to cache.
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub InitCache
{
	my $self = shift;

	my (@vars) = @_;

	my ($mv, $list);

	$make_cache = '';

	return 0 if (!$root_dir || !@vars);

	$mv = $self->Make($root_dir, @vars);

	if ($#vars == 0) {
		$make_cache = "$vars[0]=$mv";
		return 1;
	}

	$make_cache .= "$_=". ($mv->{$_} || '')
		foreach (keys %$mv);

	return 1;
}


#------------------------------------------------------------------------------
# Func: QuickMake()
# Desc: Attempt to retrieve the information we require without using make(1)
#       at all. At the first sign of trouble, bail out and just use make.
#
# Args: $port     - Port name (dir/port).
#
# Retn: \%results - Ref. to hash of results.
#------------------------------------------------------------------------------

sub QuickMake
{
	my $self = shift;

	my ($port) = @_;

	my %defaultvars = (
		PORTSDIR     => $root_dir,
		PREFIX       => '/usr/local',
		DATADIR      => '${PREFIX}/share/${PORTNAME}',
		WRKDIR       => '${WRKDIRPREFIX}${.CURDIR}/work',
		WRKDIRPREFIX => '',
		'.CURDIR'    => "$root_dir/$port",
		MACHINE_ARCH => 'i386',

		DISTNAME     => '${PORTNAME}-${DISTVERSIONPREFIX}${DISTVERSION:C/:(.)/\1/g}${DISTVERSIONSUFFIX}',
		DISTFILES    => '${DISTNAME}${EXTRACT_SUFX}',
		DISTVERSION  => '${PORTVERSION:S/:/::/g}',
		DISTVERSIONSUFFIX => '',
		DISTVERSIONPREFIX => '',

		MASTER_SITE_SUBDIR => ''
	);

	my %vars = ();

	open my $mf, "<$root_dir/$port/Makefile"
		or die "Unable to open Makefile for $port";

	my $multifrag = '';

	while (my $line = <$mf>) {
		my $ismultiline;

	##	$line =~ s/(?<!\\)#.*$//; # XXX - quoted comments

	## XXX: handle $$

		$ismultiline = ($line =~ s/\\\s*$//);

		if ($ismultiline) {
			$multifrag .= ' ' if ($multifrag);
			$multifrag .= $line;
			next;
		} else {
			$line = $multifrag.$line if ($multifrag);
			$multifrag = '';
		}

		# The '+=' operator is not supported because we can't
		# be sure if the statement is in a conditional (e.g.
		# .if) block (hence why we also bail out on multiple
		# '=' definitions).

		if ($line =~ /^([A-Z_.][A-Z0-9_]*)=\s*(.*)$/i) {
			my ($var, $val);

			$var = $1;
			$val = $2;

			$val =~ s/^\s*//;
			$val =~ s/\s*$//;

			if (exists $vars{$var}) {
				warn "$port:$var: Variable defined twice. Bailing out."
					if ($debug);
				$qfail = 1;
				last;
			}

			if ($val =~ /\$\{?$var\}?/) {
				warn "$port:$var: Recursive variable. Bailing out."
					if ($debug);
				$qfail = 1;
				last;
			}

			$vars{$var} = $val;
		} elsif ($line =~ /^\.\s*include\s*(.*)\s*/) {
			my $incfile = $1;
			unless ($incfile =~ /^</ or $incfile =~ /^"?\$\{?PORTSDIR\}?\/Mk\//) {
				warn "$port: Non-standard include file found. Bailing out"
					if ($debug);
				$qfail = 1;
				last;
			}
		}
	}

	if ($qfail) {
		$qfail = 0;
		return $self->Make($port);
	}

	# Merge in default vars
	foreach (keys %defaultvars) {
		$vars{$_} = $defaultvars{$_}
			if (!exists $vars{$_});
	}

	# Manually determine suffix.
	if (!$vars{'EXTRACT_SUFX'}) {
		if (exists $vars{'USE_BZIP2'}) {
			$vars{'EXTRACT_SUFX'} = '.tar.bz2';
		} elsif (exists $vars{'USE_ZIP'}) {
			$vars{'EXTRACT_SUFX'} = '.zip';
		} elsif (exists $vars{'USE_MAKESELF'}) {
			$vars{'EXTRACT_SUFX'} = '.run';
		} else {
			$vars{'EXTRACT_SUFX'} = '.tar.gz';
		}
	}

	$qfail = 0;

	foreach (keys %vars) {
		while (_resolvevars(\%vars, $_)) {
			if ($qfail) {
				$qfail = 0;
				return $self->Make($port);
			}
		}

		$vars{$_} =~ s/\$\{000(.*?)000\}/\$\{$1\}/g;
	}

	# Manually do complex DISTVERSION->PORTVERSION conversion
	if (!$vars{'PORTVERSION'} && $vars{'DISTVERSION'}) {
		my $portversion = '';
		foreach (split(/\s+/, lc $vars{'DISTVERSION'})) {
			my $word = $_;
			$word =~ s/([a-z])[a-z]+/$1/g;
			$word =~ s/([0-9])([a-z])/$1.$2/g;
			$word =~ s/:(.)/$1/g;
			$word =~ s/[^a-z0-9+]+/./g;
			$portversion .= ' ' if ($portversion);
			$portversion .= $word;
		}
		$vars{'PORTVERSION'} = $portversion;
	}

	# We need to resolve MASTER_SITES using bsd.sites.mk and
	# the additional layer of macros. We can just use this
	# file (rather than the whole ports framework), so the
	# overhead is fairly small.
	if ($vars{'MASTER_SITES'} && exists $wanted{'MASTER_SITES'}) {
		my $results;
		my $args = '';

		$args .= '$_="' . quotemeta($vars{$_}) . '" '
			foreach (keys %vars);

		$results = qx(make -f bsd.sites.mk -C $root_dir/Mk/ $args -V MASTER_SITES);
		$results = '' if (!$results);
		chomp $results;

		#$results =~ s/%SUBDIR%/$vars{'MASTER_SITE_SUBDIR'}/g;

		$vars{'MASTER_SITES'} = $results;
	}

	foreach (keys %vars) {
		delete $vars{$_}
			if (!exists $wanted{$_});
	}

	return \%vars;
}


#------------------------------------------------------------------------------
# Func: _resolvevars()
# Desc: Attempt to "resolve" variables -- substituting values from elsewhere
#       and performing the basic transformations supported by make(1).
#
# Args: \%vars - Existing variables hash.
#       $key   - Variable to resolve.
#
# Retn: $done  - Was a transformation performed?
#------------------------------------------------------------------------------

sub _resolvevars
{
	my ($vars, $key) = @_;

	my $varmatch = qr/\$\{([A-Z_.][A-Z0-9_]*)(:[ULRE]|:[SC](.).*?\3.*?\3[1]?[g]?)*\}/;

	$vars->{$key} =~
	s/$varmatch/            # XXX: chained ops
		my $var   = $1;
		my $op    = $2;
		my $delim = $3;

		_resolvevars($vars, $var)
			if ($vars->{$var} && $vars->{$var} =~ $varmatch);

		(!$qfail)
			? _resolver($vars, $var, $op, $delim)
			: '';
	/ge;

	# High probability of failure...
	#$qfail = 1 if ($vars->{$key} =~ /\$/);
}


#------------------------------------------------------------------------------
# Func: _resolver()
# Desc: Second-level resolver.
#
# Args: \%vars - Existing variables hash.
#       $var   - Variable name.
#       $op    - Operation that we hope to emulate.
#       $delim - Delimiter used (in the case of replacement ops.)
#
# Retn: $rvar  - Resolved variable.
#------------------------------------------------------------------------------

sub _resolver
{
	my ($vars, $var, $op, $delim) = @_;

	my $saveforlater = qr/^MASTER_SITE_/;

	if (exists $vars->{$var}) {
		if ($op and $op eq ':U') {
			return uc $vars->{$var};
		} elsif ($op and $op eq ':L') {
			return lc $vars->{$var};
		} elsif ($op and ($op eq ':R' or $op eq ':E')) {
			my $opvar = '';
			foreach my $word (split /\s+/, $vars->{$var}) {
				my ($rest, $sufx);
				if ($word =~ /^(.*)\.(.*?)$/) {
					$rest = $1;
					$sufx = $2;
				} else {
					$rest = $word;
					$sufx = '';
				}

				if ($op eq ':R') {
					$word = $rest; # Remove suffix
				} else {
					$word = $sufx; # Leave just suffix
				}

				$opvar .= ' ' if ($opvar);
				$opvar .= $word;
			}
			return $opvar;
		} elsif ($op and $op =~ m/^:S/) {
			my (@bits, $opvar, $flag_g, $caret, $dollar);
			@bits = split /(?<!\\\\)$delim/, $op;
			$flag_g = ($bits[3] =~ /g/);
			$opvar = '';

			if ($bits[1] =~ s/^\^//) {
				# We'll re-add before regex quotemeta
				$caret = '^';
			} else {
				$caret = '';
			}

			if ($bits[1] =~ s/\\\$$/\$/) {
				# (anchor de-escaped)
				$dollar = '';
			} elsif ($bits[1] =~ s/\$$//) {
				# We'll re-add after regex quotemeta
				$dollar = '$';
			} else {
				$dollar = '';
			}

			# Apply replacement to each "word"
			foreach my $word (split /\s+/, $vars->{$var}) {
				if ($flag_g) {
					$word =~ s/$caret\Q$bits[1]\E$dollar/$bits[2]/g;
				} else {
					$word =~ s/$caret\Q$bits[1]\E$dollar/$bits[2]/;
				}
				$opvar .= ' ' if ($opvar);
				$opvar .= $word;
			}
			return $opvar;
		} elsif ($op and $op =~ m/^:C/) {
			my (@bits, $opvar, $first, $flag_g, $flag_1);
			@bits = split /(?<!\\\\)$delim/, $op;
			$flag_g = ($bits[3] =~ /g/);
			$flag_1 = ($bits[3] =~ /1/);
			$opvar = '';
			$first = 0;

			$bits[2] =~ s/\\([0-9+])/\$$1/g;

			# Apply replacement to each "word"
			foreach my $word (split /\s+/, $vars->{$var}) {
				unless ($flag_1 && !$first) {
					if ($flag_g) {
						$word =~ s/$bits[1]/$bits[2]/g;
					} else {
						$word =~ s/$bits[1]/$bits[2]/;
					}
					$first = 1;
				}
				$opvar .= ' ' if ($opvar);
				$opvar .= $word;
			}
			return $opvar;
		} elsif ($op) {
			unless (!exists $wanted{$_} or $var =~ $saveforlater) {
				warn "Unresolvable variable ($var) found. Unknown operator. Bailing out."
					if ($debug);
				$qfail = 1;
			}
		} else {
			return $vars->{$var};
		}
	} else {
		unless (!exists $wanted{$_} or $var =~ $saveforlater) {
			warn "Unresolvable variable ($var) found. Bailing out."
				if ($debug);
			$qfail = 1;
		} else {
			return "\${000${var}000}";
		}
	}
}


1;
