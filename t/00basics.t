#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

my @subclasses = qw(YAML RFC822);

plan 'tests' => 3 * scalar(@subclasses);

foreach my $subclass (@subclasses) {
    
    my $package = "IO::WithHeader::$subclass";
    
    use_ok( $package );
    
    my $io;
    
    ok( $io = $package->new, "$package instantiate" );
    
    isa_ok( $io, $package );
    
}

