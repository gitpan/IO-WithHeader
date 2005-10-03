#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;
use File::Slurp;

my @subclasses = qw(YAML RFC822);

plan 'tests' => 8 * scalar(@subclasses);

foreach my $subclass (@subclasses) {
    
    my $package = "IO::WithHeader::$subclass";
    
    use_ok( $package );
    
    my $io;
    
    # --- Open for writing
    
    my $path = "t/sandbox/$subclass/new-path";
    
    unlink $path if -e $path;
    
    my $header = { 'title' => 'Test' };
    my $body = "Testing 1, 2, 3\n";
    
    ok( $io = $package->new(">$path"), "$package instantiate with path only" );
    isa_ok( $io, $package );
    
    ok( $io->print($body), "$package print body" );
    ok( $io->close,        "$package close"      );
    
    $io->header(undef);
    
    ok( $io->open($path),  "$package reopen read-only" );
    
    my $newbody = $io->body;
    is( $newbody, $body,   "$package body" );
    
    ok( $io->close,        "$package close"      );
    
}
