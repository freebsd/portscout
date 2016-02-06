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
# $Id: XML.pm,v 1.8 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

package Portscout::DataSrc::XML;

use base qw(Portscout::DataSrc);

use XML::XPath;
use XML::XPath::XMLParser;

use Portscout::API;
use Portscout::Util;

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
# Func: Build()
# Desc: Parse the XML file; store results in the database.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub Build
{
	my $self = shift;

	my ($xpath, $items);

	my (%singlemap, %multimap, %defaults);

	my $got_ports = 0;
	my $num_ports = $self->Count(); # XXX: caching?

	my $ps = Portscout::API->new;

	%singlemap = (
		'name'       => 'name',
		'category'   => 'category',
		'desc'       => 'comment',
		'version'    => 'version',
		'maintainer' => 'maintainer',
		'distname'   => 'distname',
		'suffix'     => 'suffix',
		'master'     => 'masterport'
	);

	%multimap = (
		'distfiles' => {name => 'distfiles', child => 'file', type => 'array'},
		'sites'     => {name => 'sites', child => 'site', type => 'array'},
		'options'   => {name => 'options', child => 'option', type => 'hash'}
	);

	%defaults = (
		'category'  => 'software',
		'suffix'    => '.tar.gz',
		'distname'  => '%(name)-%(version)',
		'distfiles' => [ '%(distname)%(suffix)' ]
	);

	if (!$self->{opts}->{file}) {
		die "No XML source file specified";
	} elsif (! -f $self->{opts}->{file}) {
		die "Can't read XML file";
	}

	$xpath = XML::XPath->new(filename => $self->{opts}->{file});

	$items = $xpath->findnodes('/items/item');

	foreach my $item ($items->get_nodelist) {
		my $data = $xpath->findnodes('*', $item);

		# Some defaults
		my %port;

		# Iterate over <item> elements
		foreach my $datum ($data->get_nodelist) {
			my ($key, $val);

			$key = $datum->getLocalName();
			$val = $datum->string_value();

			$val =~ s/^\s*//;
			$val =~ s/\s*$//;
			$val =~ s/\n//s;

			if ($singlemap{$key}) {
				# Simple string value

				$port{$singlemap{$key}} = $val;
				next;
			} elsif ($multimap{$key}) {
				# Array of values in child nodes

				my ($name, $type, $child, $nodes);

				$name  = $multimap{$key}->{name};
				$type  = $multimap{$key}->{type};
				$child = $multimap{$key}->{child};

				if (!exists $port{$name}) {
					$port{$name} = ($type eq 'array') ? [] : {};
				}

				$nodes = $xpath->findnodes($child, $datum);
				foreach my $subnode ($nodes->get_nodelist) {
					my ($skey, $sval);
					if ($type eq 'array') {
						$sval = $subnode->string_value();
						push @{$port{$name}}, $sval;
					} else {
						$skey = $subnode->getAttribute('name');
						$sval = $subnode->getAttribute('value');
						$port{$name}->{$skey} = $sval;
					}
				}
				next;
			}
		}

		# Fill in defaults

		foreach my $key (keys %defaults) {
			if (!exists $port{$key}) {
				if (!ref $defaults{$key}) {
					$port{$key} = $defaults{$key}
				} elsif (ref $defaults{$key} eq 'ARRAY') {
					$port{$key} = [ @{$defaults{$key}} ];
				} elsif (ref $defaults{$key} eq 'HASH') {
					$port{$key} = { %{$defaults{$key}} };
				}
			}
		}

		# Perform auto replacements

		foreach my $key (keys %port) {
			if (!ref $port{$key}) {
				(1) while (
					$port{$key} =~ s/%\((.*?)\)/
						my $v = $singlemap{$1} || $1;
						(exists $port{$v} && !ref $port{$v}) ? $port{$v} : ''
					/ge
				);
			} elsif (ref $port{$key} eq 'ARRAY') {
				for (my $i = 0; $i <= $#{$port{$key}}; $i++) {
					(1) while (
						${$port{$key}}[$i] =~ s/%\((.*?)\)/
							my $v = $singlemap{$1} || $1;
							(exists $port{$v} && !ref $port{$v}) ? $port{$v} : ''
						/ge
					);
				}
			}
		}

		# Check that this port is actually desired

		if (!wantport($port{name}, $port{category}, $port{maintainer})) {
			$num_ports--;
			next;
		}

		$got_ports++;

		print '[' . strchop($port{category}, 15) . '] ' unless ($settings{quiet});
		info($port{name}, "(got $got_ports out of $num_ports)");

		$ps->AddPort(\%port);
	}

	print "\nDone.\n";

	return 1;
}


#------------------------------------------------------------------------------
# Func: Rebuild()
# Desc: As above, but only update what has changed.
#
# Args: n/a
#
# Retn: $success - true/false
#------------------------------------------------------------------------------

sub Rebuild
{
	my $self = shift;

	# XXX: need to, at the least, uncheck new vers
	$self->Build();

	return 1;
}


#------------------------------------------------------------------------------
# Func: Count()
# Desc: Return a count of the software items.
#
# Args: n/a
#
# Retn: $count - Result.
#------------------------------------------------------------------------------

sub Count
{
	my $self = shift;

	my ($xpath, $items, $num_ports);

	$xpath = XML::XPath->new(filename => $self->{opts}->{file});

	$items = $xpath->findnodes('/items/item');

	$num_ports++ foreach ($items->get_nodelist);

	return $num_ports;
}


1;

=pod

=head1 NAME

Portscout::DataSrc::XML

XML file DataSrc backend for Portscout.

=head1 DESCRIPTION

This module provides a simple means of describing software you want to
monitor to Portscout. Instead of checking the FreeBSD ports tree,
Portscout will read the required data from an XML file.

The XML module is also intended as a demonstration for developers
wishing to extend Portscout to support other repositories.

=head1 CONFIGURATION

Update F<portscout.conf> to enable XML as the DataSrc backend:

    datasrc = Portscout::DataSrc::XML
    datasrc_opts = file:/path/to/file.xml

=head1 FILE FORMAT

The file should be in the following format. It must contain well-formed
XML and be in the location specified in F<portscout.conf>.

    <items>
        <item>
            <category>software</category>
            <name>foo</name>
            <desc>Foomatic Professional</desc>
            <version>0.4.3</version>
            <suffix>.tar.gz</suffix>
            <distname>%(name)-%(version)</distname>
            <distfiles>
                <file>%(distname)%(suffix)</file>
            </distfiles>
            <sites>
                <site>http://foo.example.net/releases/</site>
                <site>ftp://mirror.local/pub/foo/</site>
            </sites>
            <options>
                <option name="limit" value="1,even" />
            </options>
        </item>
        <item>
            <category>software</category>
            <name>bar</name>
            <desc>Barware</desc>
            <version>1.8</version>
            <sites>
                <site>http://example.org/software/bar/</site>
            </sites>
        </item>
    </items>

=head1 TIPS

You can refer to other values within each E<lt>itemE<gt> element as shown
above, using the %(variable) notation.

Note that the values for E<lt>categoryE<gt>, E<lt>suffixE<gt>,
E<lt>distnameE<gt> and E<lt>distfilesE<gt> in the "Foo" entry above are
the defaults and can be omitted.

=head1 USING THE BACKEND

Once you have your file ready, you can use the standard C<build> and
C<rebuild> commands to update Portscout's internal database with any
changes.

=cut
