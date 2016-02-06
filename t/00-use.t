# Check that all the modules work.

use Test;

BEGIN { plan tests => 15; }

use strict;
use warnings;

eval 'use Portscout::Const ();';                    ok(!$@);
eval 'use Portscout::API();';                       ok(!$@);
eval 'use Portscout::Util ();';                     ok(!$@);
eval 'use Portscout::Config ();';                   ok(!$@);

eval 'use Portscout::SiteHandler ();';              ok(!$@);
eval 'use Portscout::SiteHandler::SourceForge ();'; ok(!$@);

eval 'use Portscout::SQL ();';                      ok(!$@);
eval 'use Portscout::SQL::SQLite ();';              ok(!$@);
eval 'use Portscout::SQL::Pg ();';                  ok(!$@);

eval 'use Portscout::Make ();';                     ok(!$@);
eval 'use Portscout::Template ();';                 ok(!$@);

eval 'use Portscout::DataSrc ();';                  ok(!$@);
eval 'use Portscout::DataSrc::Ports ();';           ok(!$@);
eval 'use Portscout::DataSrc::XML ();';             ok(!$@);

eval 'use Portscout ();';                           ok(!$@);
