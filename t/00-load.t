#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Try::XS' ) || print "Bail out!\n";
}

diag( "Testing Try::XS $Try::XS::VERSION, Perl $], $^X" );
