#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;
use File::Slurp qw(read_file);

my @subclasses = qw(YAML RFC822);

plan 'tests' => 45 * scalar(@subclasses);

foreach my $subclass (@subclasses) {
    
    my $package = "IO::WithHeader::$subclass";
    
    use_ok( $package );
    
    my $io;
    
    my $path = "t/sandbox/$subclass/append";
    my $header = {
        'title' => 'none',
        'author' => 'nobody',
        'date' => 'never',
    };
    my $body = '';
    
    unlink $path if -e $path;
    
    ok( $io = $package->new('header' => $header, 'body' => $body), "$package instantiate" );
    isa_ok( $io, $package, "$package instance" );
    ok( $io->open(">>$path"), "$package open for append" );
    is( $!, '', 'open $!' );
    
    is_deeply( $io->header, $header, "$package header" );
    
    my $newbody = $io->body;
    is_deeply( $newbody,    $body,   "$package body"   );
    
    $io->autoflush(1);
    
    # --- Make sure the cursor is at the end of the body
    ok( $io->eof, "$package eof" );
    
    ok( $io->close, "$package close" );
    
    my $file_size = -s $path;
    
    foreach (1..9) {
        ok( $io->open(">>$path"), "$package open for append $_" );
        ok( $io->print($_), "$package print $_" );
        ok( $io->close, "$package close $_" );
        is( -s $path, ++$file_size, "$package file size" );
    }


}
