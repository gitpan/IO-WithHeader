#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

my @subclasses = qw(YAML RFC822);

plan 'tests' => 6 * scalar(@subclasses);

foreach my $subclass (@subclasses) {
    
    my $package = "IO::WithHeader::$subclass";
    
    use_ok( $package );
    
    my $io;
    
    my $path = "t/sandbox/$subclass/read";
    my $header = {
        'title'  => 'none',
        'author' => 'nobody',
        'date'   => 'never',
    };
    
    ok(     $io = $package->new, "$package instantiate"    );
    isa_ok( $io, $package,       "$package instance"       );
    ok(     $io->open("<$path"), "$package open read-only" );
    
    my @should_be = ( "empty\n" );
    
    my @lines = <$io>;
    
    is_deeply( \@lines, \@should_be, "$package body" );
    ok( $io->close, "$package close" );
    
}
