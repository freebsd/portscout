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
# $Id: Const.pm,v 1.5 2011/05/15 17:27:05 samott Exp $
#------------------------------------------------------------------------------

package Portscout::Const;

require Exporter;

use strict;

require 5.006;

our @ISA = qw(Exporter);


#------------------------------------------------------------------------------
# Constants
#------------------------------------------------------------------------------

use constant {
	APPNAME     		=> 'portscout',
	APPVER      		=> '0.8.1',
	AUTHOR      		=> 'Shaun Amott',

	USER_AGENT  		=> 'portscout/0.8.1',

	DB_VERSION  		=> 2011040901,

	MAX_PATH    		=> 1024,

	PREFIX      		=> '/usr/local',
	CONFIG_FILE 		=> 'portscout.conf',

	METHOD_GUESS		=> 1,
	METHOD_LIST 		=> 2,

	ROBOTS_ALLOW   		=> 0,
	ROBOTS_UNKNOWN 		=> 1,
	ROBOTS_BLANKET 		=> 2,
	ROBOTS_SPECIFIC		=> 3,

	TYPE_INT    		=> 1,
	TYPE_BOOL   		=> 2,
	TYPE_STRING 		=> 3,
};


#------------------------------------------------------------------------------
# Export our constants.
#------------------------------------------------------------------------------

our @EXPORT = grep s/^Portscout::Const:://, keys %constant::declared;


1;
