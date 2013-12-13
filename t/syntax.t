use strict;
use warnings;

use Test::More tests => 1;

is(system("$^X -c -Ilib lib/Test/Http/LWP.pm"), 0, 'LWP.pm syntax OK');
