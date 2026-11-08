package Portscout::SiteHandler::GitHub;

#
# Copyright (c) 2006-2024 The FreeBSD Project.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
# IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

use Cwd qw(getcwd);
use IPC::Open3;

use Portscout::Const;
use Portscout::Config;

use strict;
require 5.006;

push @Portscout::SiteHandler::sitehandlers, __PACKAGE__;
our %settings;

sub new
{
	my $class = shift;
	my $self = {};

	$self->{name} = 'GitHub';

	bless $self, $class;
	return $self;
}

sub CanHandle
{
	my $self = shift;
	my ($url) = @_;

	return ($url =~
	    m{^https?://(?:www\.)?(?:github\.com|codeload\.github\.com)/[^/]+/[^/]+(?:/|$)}i);
}

sub GetFiles
{
	my $self = shift;
	my ($url, $port, $files) = @_;
	my ($owner, $project);

	my $category = $port->{cat};
	my $name = $port->{name};

	if (!$category || !$name) {
		_debug('Port category or name is missing');
		return 0;
	}

	my $dir = $settings{ports_dir} . '/' .
	    $category . '/' . $name;
	my $cwd = getcwd();
	my $make_output;

	if (!chdir($dir)) {
		_debug("Couldn't chdir to $dir");
		return 0;
	}

	$make_output = qx(make -V USE_GITHUB -V GH_ACCOUNT -V GH_PROJECT -V MASTER_SITES 2>/dev/null);
	my $make_status = $?;

	chdir($cwd);

	if ($make_status != 0) {
		_debug("make failed for $dir");
		return 0;
	}

	my @mv = split /\n/, $make_output, -1;
	my $use_github = shift @mv;
	$owner = shift @mv;
	$project = shift @mv;
	my $master_sites = shift @mv;

	$use_github = '' unless defined $use_github;
	$owner = '' unless defined $owner;
	$project = '' unless defined $project;
	$master_sites = '' unless defined $master_sites;

	return 0 if ($use_github eq 'nodefault');

	if ($use_github eq 'yes') {
		if (!$owner || !$project) {
			_debug('USE_GITHUB=yes but GH_ACCOUNT/GH_PROJECT are missing');
			return 0;
		}
	} else {
		my $github_site;

		foreach my $site (split /\s+/, $master_sites) {
			next unless ($site =~
			    m{^https?://(?:www\.)?(?:github\.com|codeload\.github\.com)/}i);

			my $without_scheme = $site;
			$without_scheme =~ s{^[^:]+://}{};

			# A :label suffix means this MASTER_SITES entry is
			# labelled and therefore is not the primary source.
			next if ($without_scheme =~ /:/);

			$github_site = $site;
			last;
		}

		if (!$github_site) {
			_debug("No unlabelled GitHub MASTER_SITES entry for " .
			    "$port->{category}/$port->{name}");
			return 0;
		}

		if ($github_site =~
		    m{^https?://(?:www\.)?(?:github\.com|codeload\.github\.com)/([^/]+)/([^/?]+)}i) {
			$owner = $1;
			$project = $2;
		} else {
			_debug("Couldn't extract project name from URL $github_site");
			return 0;
		}
	}

	my $remote = "https://github.com/$owner/$project.git";

	_debug("git ls-remote --tags --refs $remote");

	my ($output, $status, $timed_out) = _git_tags($remote);

	return 0 if ($timed_out || $status != 0);

	foreach my $line (split /\n/, $output) {
		if ($line =~ m{^[0-9a-fA-F]+\s+refs/tags/(.+)$}) {
			push @$files, $1;
		}
	}

	_debug('Found ' . scalar(@$files) . ' Git tags');

	return 1;
}

sub _git_tags
{
	my ($remote) = @_;
	my ($output, $status, $timed_out) = ('', -1, 0);
	my ($pid, $in, $out, $err);

	eval {
		open($err, '>', '/dev/null') or
		    die "open /dev/null failed: $!\n";

		local $ENV{GIT_TERMINAL_PROMPT} = '0';

		$pid = open3($in, $out, $err,
		    'git', 'ls-remote', '--tags', '--refs', $remote);

		close($in);

		local $SIG{ALRM} = sub {
			die "__PORTSCOUT_GITHUB_TIMEOUT__\n"
		};

		alarm($settings{http_timeout});

		while (my $line = <$out>) {
			$output .= $line;
		}

		alarm(0);

		close($out);
		close($err);

		waitpid($pid, 0);
		$status = $?;
	};

	if ($@) {
		alarm(0);

		$timed_out = 1
		    if ($@ =~ /__PORTSCOUT_GITHUB_TIMEOUT__/);

		if ($pid) {
			kill('KILL', $pid);
			waitpid($pid, 0);
		}

		close($out) if ($out);
		close($err) if ($err);

		_debug('git ls-remote timed out') if ($timed_out);

		return ($output, -1, $timed_out);
	}

	if ($status != 0) {
		_debug("git ls-remote failed with status $status");
	}

	return ($output, $status, 0);
}

sub _debug
{
	my ($msg) = @_;

	$msg = '' if (!$msg);

	print STDERR "(" . __PACKAGE__ . ") $msg\n"
	    if ($settings{debug});
}

1;