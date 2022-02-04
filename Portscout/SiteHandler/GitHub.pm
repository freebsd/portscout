#------------------------------------------------------------------------------
# Copyright (C) 2014, Jasper Lievisse Adriaanse <jasper@openbsd.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
#------------------------------------------------------------------------------

package Portscout::SiteHandler::GitHub;

use JSON qw(decode_json);
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
	my $self = {};
	my $class = shift;

	$self->{name} = 'GitHub';

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

	return ($url =~ /^https?:\/\/([^\/.]+\.)?github\.com\/(.*?)\/tar.gz/);
}


#------------------------------------------------------------------------------
# Func: GetFiles()
# Desc: Extract a list of files from the given URL. In the case of GitHub,
#       we are actually pulling the files from the project's Atom feed and
#       extract the release url, containing the tag it was based on.
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
	my $files_count_before = scalar @$files;
	my $projname;

	# Extract project name from URL
	if ($url =~ /https?:\/\/codeload\.github\.com\/(.+?)\/tar.gz\//) {
		$projname = $1;
	} elsif ($url =~ /https:\/\/github\.com\/(.+?)\/archive\//) {
		$projname = $1;
	} elsif ($url =~ /https:\/\/github.com\/downloads\/(.+)\//) {
		$projname = $1;
	} else {
		_debug("Couldn't extract project name from URL $url");
		return 0;
	}

	# See if there are any releases
	my $releases = _call_github_api('/repos/' . $projname . '/releases')
	  or return 0;
	foreach my $release (@$releases) {
		if (!$release->{prerelease} && !$release->{draft}) {
			my $release_url = $release->{tarball_url};
			push(@$files, $release_url);
		}
	}

	# In case there aren't any releases, try tags tags instead
	if (scalar @$files == $files_count_before) {
		my $tags = _call_github_api('/repos/' . $projname . '/tags')
		  or return 0;
		foreach my $tag (@$tags) {
			my $tag_url = $tag->{tarball_url};
			push(@$files, $tag_url);
		}
	}

	_debug('Found ' . (scalar @$files - $files_count_before) . ' files');
	return 1;
}


#------------------------------------------------------------------------------
# Func: _call_github_api()
# Desc: Calls the github api making use of settings.
#
# Args: $resource - Resource to query (e.g. "/repos/project/releases")
#
# Retn: Parsed JSON
#------------------------------------------------------------------------------

sub _call_github_api {
	my $resource = shift;

	my $url = 'https://api.github.com' . $resource;
	_debug("GET $url");

	my $ua = LWP::UserAgent->new;
	$ua->agent(USER_AGENT);
	$ua->timeout($settings{http_timeout});

	my $response = $ua->request(
		HTTP::Request->new(
			GET => $url,
			$settings{github_token}
			? ["Authorization" => "token $settings{github_token}"]
			: []
		)
	);
	if (!$response->is_success || $response->status_line !~ /^2/) {
		_debug('GET failed: ' . $response->status_line);
		return;
	}
	return decode_json($response->decoded_content);
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

	print STDERR "(" . __PACKAGE__ . ") $msg\n" if ($settings{debug});
}

1;
