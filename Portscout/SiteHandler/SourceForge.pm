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
# $Id: SourceForge.pm,v 1.8 2010/05/05 01:54:16 samott Exp $
#------------------------------------------------------------------------------

package Portscout::SiteHandler::SourceForge;

use XML::XPath;
use XML::XPath::XMLParser;
use LWP::UserAgent;

use Portscout::Const;
use Portscout::Config;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

push @Portscout::SiteHandler::sitehandlers, __PACKAGE__;

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
	my $self      = {};
	my $class     = shift;

	$self->{name} = 'SourceForge';

	bless ($self, $class);
	return $self;
}


#------------------------------------------------------------------------------
# Func: CanHandle()
# Desc: Ask if this handler (package) can handle the given site.
#
# Args: $url - URL of site.
#
# Retn: $res - true/false.
#------------------------------------------------------------------------------

sub CanHandle
{
	my $self = shift;

	my ($url) = @_;

	return ($url =~ /^http:\/\/[^\/]*?\.sourceforge\.net\/project\//);
}


#------------------------------------------------------------------------------
# Func: GetFiles()
# Desc: Extract a list of files from the given URL. In the case of SourceForge,
#       we are actually pulling the files from an RSS feed helpfully provided
#       for each "project".
#
# Args: $url     - URL we would normally fetch from.
#       \%port   - Port hash fetched from database.
#       \@files  - Array to put files into.
#
# Retn: $success - False if file list could not be constructed; else, true.
#------------------------------------------------------------------------------

sub GetFiles
{
	my $self = shift;

	my ($url, $port, $files) = @_;

	if ($url =~ /[^\/]*\/project\/([^\/]*)\//) {
		my ($rsspage, $projname, $ua, $response, $xpath, $items);

		$projname = $1;

		# Find the RSS feed for this project.
		$rsspage = 'http://sourceforge.net/api/file/index/project-name/'
			. $projname . '/mtime/desc/rss';

		_debug("Trying RSS @ $rsspage");

		$ua = LWP::UserAgent->new;

		$ua->agent(USER_AGENT);
		$ua->timeout($settings{http_timeout});

		$response = $ua->get($rsspage);

		if (!$response->is_success || $response->status_line !~ /^2/) {
			_debug('RSS feed failed: ' . $response->status_line);
			return 0;
		}

		$xpath = XML::XPath->new(xml => $response->content);

		$items = $xpath->findnodes('/rss/channel/item');

		foreach my $item ($items->get_nodelist) {
			my ($data, $tnode, $file, $lnode, $url);

			$data = $xpath->findnodes('./title', $item);
			$tnode = ($data->get_nodelist)[0];
			$file = "/project/$projname" . $tnode->string_value();

			# There doesn't seem to be a canonical way of
			# determining which entries are directories;
			# but directories seem to (rightly) have
			# trailing slashes in the full URL, in <link />.

			$data = $xpath->findnodes('./link', $item);
			$lnode = ($data->get_nodelist)[0];
			$url = $lnode->string_value();

			next if ($url =~ /\/$/);

			# Note this file.

			push @$files, $file;
		}

		_debug('Found ' . scalar @$files . ' files');
	} else {
		return 0;
	}

	return 1;
}


#------------------------------------------------------------------------------
# Func: _debug()
# Desc: Print a debug message.
#
# Args: $msg - Message.
#
# Retn: n/a
#------------------------------------------------------------------------------

sub _debug
{
	my ($msg) = @_;

	$msg = '' if (!$msg);

	print STDERR "(SiteHandler::SourceForge) $msg\n"
		if ($settings{debug});
}


1;
