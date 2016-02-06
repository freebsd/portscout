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
# $Id: SiteHandler.pm,v 1.2 2010/04/29 01:07:51 samott Exp $
#------------------------------------------------------------------------------

package Portscout::SiteHandler;

use XML::XPath;
use XML::XPath::XMLParser;

use Portscout::SiteHandler::SourceForge;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Globals
#------------------------------------------------------------------------------

our @sitehandlers;


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

	bless ($self, $class);
	return $self;
}


#------------------------------------------------------------------------------
# Func: FindHandler()
# Desc: Iterate over known handlers to find one, if any, that can handle the
#       given site.
#
# Args: $url - A URL we want to "handle".
#
# Retn: $sitehandler or undef
#------------------------------------------------------------------------------

sub FindHandler
{
	my $self = shift;

	my ($url) = @_;

	foreach (@sitehandlers) {
		return new $_ if $_->CanHandle($url);
	}

	return undef;
}


1;
