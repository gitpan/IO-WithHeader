#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;
use File::Slurp;

my @subclasses = qw(YAML RFC822);

plan 'tests' => 7 * scalar(@subclasses);

foreach my $subclass (@subclasses) {
    
    my $package = "IO::WithHeader::$subclass";
    
    use_ok( $package );
    
    my $io;
    
    my $path = "t/sandbox/$subclass/read";
    my $header = {
        'title' => 'none',
        'author' => 'nobody',
        'date' => 'never',
    };
    my $body = "empty\n";
    
    ok(        $io = $package->new,  "$package instantiate"    );
    isa_ok(    $io, $package,        "$package the instance"   );
    ok(        $io->open("<$path"),  "$package open read-only" );
    is_deeply( $io->header, $header, "$package header"         );
    is(        $io->body,   $body,   "$package body"           );
    ok(        $io->close,           "$package close"          );
    
}
