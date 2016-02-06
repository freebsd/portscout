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
# $Id: Template.pm,v 1.5 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

package Portscout::Template;

use URI::Escape;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

my $templatedir;
my $outputdir;

my $clearempty = 1;


#------------------------------------------------------------------------------
# Func: new()
# Desc: Constructor - load template into class.
#
# Args: $name - Template (file)name
#
# Retn: $self
#------------------------------------------------------------------------------

sub new
{
	my $file;

	my $self      = {};
	my $class     = shift;

	$self->{name} = shift;

	$self->{header}          = [];
	$self->{repeat}          = [];
	$self->{footer}          = [];

	$self->{rows}            = [];

	$self->{template_header} = [];
	$self->{template_repeat} = [];
	$self->{template_footer} = [];

	if ($templatedir) {
		$file = "$templatedir/$self->{name}";
	} else {
		$file = $self->{name};
	}

	open my $fh, "<$file" or return undef;

	while (<$fh>)
	{
		if (s/^%%://) {
			push @{$self->{template_repeat}}, $_;
		} else {
			if (@{$self->{template_repeat}}) {
				push @{$self->{template_footer}}, $_;
			} else {
				push @{$self->{template_header}}, $_;
			}
		}
	}

	close $fh;

	bless ($self, $class);
	return $self;
}


#------------------------------------------------------------------------------
# Accessor functions
#------------------------------------------------------------------------------

sub templatedir
{
	my $self = shift;

	if (@_) {
		$templatedir = shift;
		$templatedir =~ s/^(.+)\/$/$1/;
	}

	return $templatedir;
}

sub outputdir
{
	my $self = shift;

	if (@_) {
		$outputdir = shift;
		$outputdir =~ s/^(.+)\/$/$1/;
	}

	return $outputdir;
}

sub clearempty
{
	my $self = shift;

	if (@_) {
		my $ce = shift;
		$clearempty = ($ce ? 1 : 0);
	}

	return $clearempty;
}


#------------------------------------------------------------------------------
# Func: applyglobal()
# Desc: Interpolate global data into the template.
#
# Args: \%data - Data to merge
#
# Retn: n/a
#------------------------------------------------------------------------------

sub applyglobal
{
	my $self = shift;
	my $data = shift;

	foreach my $var ('header', 'repeat', 'footer') {
		@{$self->{$var}} = undef;

		foreach (@{$self->{"template_$var"}}) {
			my $val = $_;
			$val =~ s/\%\%\((.+?)(?::(.*?))?\)/
				if (exists $data->{$1}) {
					_format_var($data->{$1}, $2);
				} else {
					$2 ? "\%\%($1:$2)" : "\%\%($1)";
				}
			/ge;
			push @{$self->{$var}}, $val;
		}
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: pushrow()
# Desc: Interpolate data into the template's "repeat" section, and add the
#       result as a new row.
#
# Args: \%data - Data to merge
#
# Retn: n/a
#------------------------------------------------------------------------------

sub pushrow
{
	my $self = shift;
	my $data = shift;

	my $var;

	if (@{$self->{repeat}}) {
		$var = 'repeat';
	} else {
		$var = 'template_repeat';
	}

	foreach (@{$self->{$var}}) {
		my $val = $_;
		$val =~ s/\%\%\((.+?)(?::(.*?))?\)/
			if (exists $data->{$1}) {
				_format_var($data->{$1}, $2);
			} else {
				$2 ? "\%\%($1:$2)" : "\%\%($1)";
			}
		/ge;
		push @{$self->{rows}}, $val;
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: output()
# Desc: Output interpolated template into $file (otherwise STDOUT).
#
# Args: $file    - File to dump output into
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub output
{
	my ($self, $file, $fh);

	$self = shift;
	$file = shift;

	if ($file) {
		$file = "$outputdir/$file" if ($outputdir);
		open $fh, ">$file" or return 0;
	} else {
		$fh = \*main::STDOUT;
	}

	$self->_clear_empty if ($clearempty);

	print $fh $_ foreach (@{$self->{header}});

	foreach (@{$self->{rows}}) {
		print $fh $_;
	}

	print $fh $_ foreach (@{$self->{footer}});

	close $fh if ($file);

	return 1;
}


#------------------------------------------------------------------------------
# Func: string()
# Desc: Return the completed template stuffed into a scalar.
#
# Args: n/a
#
# Retn: $string - output
#------------------------------------------------------------------------------

sub string
{
	my ($self, $string);

	$self = shift;

	$self->_clear_empty if ($clearempty);

	foreach my $var ('header', 'rows', 'footer') {
		foreach (@{$self->{$var}}) {
			$string .= $_;
		}
	}

	return $string;
}


#------------------------------------------------------------------------------
# Func: reset()
# Desc: Reset template to its state prior to interpolation.
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub reset
{
	my ($self);

	$self = shift;

	foreach my $var ('header', 'repeat', 'footer', 'rows') {
		$self->{$var} = [];
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: _clear_empty()
# Desc: Clear any unexpanded placeholders
#
# Args: n/a
#
# Retn: n/a
#------------------------------------------------------------------------------

sub _clear_empty
{
	my ($self);

	$self = shift;

	foreach my $var ('header', 'repeat', 'footer', 'rows') {
		s/\%\%\(.*?\)//g foreach (@{$self->{$var}});
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: _format_var()
# Desc: Apply formatting (currently just padding and alignment) to the given
#       variable, and return it.
#
# Args: $string
#       $format
#
# Retn: $result
#------------------------------------------------------------------------------

sub _format_var
{
	my ($string, $format) = @_;

	$format or return $string;

	if ($format =~ /^([0-9]+)([LR])?$/i) {
		my $pad = ' ' x ($1 - length $string);
		if ($2 and lc($2) eq 'R') {
			$string = $pad.$string;
		} else {
			$string = $string.$pad;
		}
	} elsif ($format =~ /^X$/i) {
		$string = uri_escape($string);
	}

	return $string;
}


1;
