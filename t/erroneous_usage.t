#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Try::XS;

sub _eval {
  local $@;
  local $Test::Builder::Level = $Test::Builder::Level + 2;
  return ( scalar(eval { $_[0]->(); 1 }), $@ );
}

my $ret;
my $x = 0;
$ret = eval q{
  if ($x) { try { 1 }; catch { 2 } }; 1234
};
like(
    $@,
    qr/\QUseless bare catch { ... }/,
    'Bare catch() detected at compile time'
);

$ret = eval q{
  try { 1 }; finally { 2 };
};
like(
    $@,
    qr/\QUseless bare finally { ... }/, 'Bare finally() detected'
);

$ret = eval q{
  try { 1 }; catch { 2 } finally { 2 };
};
like(
    $@,
    qr/\QUseless bare finally { ... }/, 'Bare catch()/finally() detected');

$ret = eval q{
  try { 1 }; finally { 2 } catch { 2 };
};
like(
    $@,
    qr/\QUseless bare catch { ... }/, 'Bare finally()/catch() detected');


$ret = eval q{
  try { 1 } catch { 2 } catch { 3 } finally { 4 } finally { 5 }
};
like(
    $@,
    qr/\QA try { ... } may not be followed by multiple catch { ... } blocks/, 'Multi-catch detected');


$ret = eval q{
  try { 1 } catch { 2 }
  do { 2 }
};
like(
    $@,
    qr/\Qsyntax error/,
  'Unterminated try detected'
);

done_testing;
