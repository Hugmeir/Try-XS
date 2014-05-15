{ require 5.008 };
use strict;
use warnings FATAL => 'all';

use if $] < 5.014, "Devel::CallChecker";
use Devel::CallParser;
use IO::File;


write_header('callparser1.h', &Devel::CallParser::callparser1_h);
write_header('callchecker0.h', &Devel::CallChecker::callchecker0_h) if $] < 5.014;

sub write_header {
    my ($header, $content) = @_;
    my $fh = IO::File->new($header, 'w') or die $!;
    $fh->print($content) or die $!;
    $fh->close or die $!;
}

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Try::XS',
    AUTHOR           => q{Brian Fraser <fraserbn@gmail.com>},
    VERSION_FROM     => 'lib/Try/XS.pm',
    ABSTRACT_FROM    => 'lib/Try/XS.pm',
    LICENSE          => 'Artistic_2_0',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
        "Devel::CallChecker"  => 0,
        "Devel::CallParser"   => 0,
        "IO::File"            => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        "Devel::CallChecker" => 0,
        "Devel::CallParser"  => 0,
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'Try-XS-*' },
);
