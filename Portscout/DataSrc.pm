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
# $Id: DataSrc.pm,v 1.1 2010/05/05 01:54:16 samott Exp $
#------------------------------------------------------------------------------

package Portscout::DataSrc;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# API Method Stubs.
#------------------------------------------------------------------------------

sub Init    { 1; }
sub Build   { 1; }
sub Rebuild { 1; }
sub Count   { -1; }

sub bad_versions { []; }


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

	my ($src, $options) = @_;

	my $self = {
		opts => $options ? ParseOptions($options) : {}
	};

	# Little shortcut
	$src = "Portscout::DataSrc$src"
		if ($src =~ /^::/);

	eval "use $src";
	die $@ if $@;

	bless ($self, $src || $class);

	$self->Init();

	return $self;
}


#------------------------------------------------------------------------------
# Func: ParseOptions()
# Desc: Parse DataSrc options into a hash.
#
# Args: $opts - Options in flat config file form (basically: space-separated,
#               comma-delimited tuples).
#
# Retn: \%res - Hash of options.
#------------------------------------------------------------------------------

sub ParseOptions
{
	my ($opts) = @_;

	my (%res, $key, $val, $insquote, $indquote, $gotkey);

	$insquote = 0;
	$indquote = 0;
	$key = '';
	$val = '';

	foreach my $c (split //, $opts) {
		if ($c eq "'" && !$indquote) {
			$insquote = !$insquote;
			next;
		}

		if ($c eq '"' && !$insquote) {
			$indquote = !$indquote;
			next;
		}

		if (!$insquote && !$indquote) {
			if ($c eq ':') {
				$gotkey = 1;
				next;
			}

			if ($c eq ' ' or $c eq "\t") {
				$res{$key} = $val if ($key);
				$key = $val = '';
				$gotkey = 0;
				next;
			}
		}

		if ($gotkey) {
			$val .= $c;
		} else {
			$key .= $c;
		}
	}

	$res{$key} = $val if ($key);

	return \%res;
}


1;
