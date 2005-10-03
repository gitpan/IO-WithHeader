#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;
use File::Copy qw(copy);
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);

my @subclasses = qw(YAML RFC822);

plan 'tests' => 26 * scalar(@subclasses);

foreach my $subclass (@subclasses) {
    
    my $package = "IO::WithHeader::$subclass";
    
    use_ok( $package );
    
    my $io;
    
    my $path = "t/sandbox/$subclass/readupdate";
    my $header = {
        'title' => 'none',
        'author' => 'nobody',
        'date' => 'never',
    };
    my $body = "one\ntwo\nthree\n";
    
    # --- Start with a clean copy
    copy("t/sandbox/$subclass/read", $path);
    
    ok(     $io = $package->new,  "$package instantiate"      );
    isa_ok( $io, $package,        "$package the instance"     );
    ok(     $io->open("+<$path"), "$package open read/update" );
    
    # --- Make sure the cursor is at the beginning of the body
    is( $io->handle->tell, $io->header_length, "$package cursor pos" );
    
    # --- Check autoflush and tell
    $io->autoflush;
    is( $!,        '', "$package autoflush" );
    is( $io->tell, 0,  "$package tell"      );
    
    # --- Make sure the header and body are read correctly
    is_deeply( $io->header, $header, "$package header"                    );
    is(        $io->tell,   0,       "$package cursor pos restored"       );
    is(        $io->body,   $body,   "$package body"                      );
    is(        $io->tell,   0,       "$package cursor pos restored again" );
    
    my $file_size = -s $path;
    
    # --- Move the cursor to the end of the body
    ok( $io->seek(0, SEEK_END),                             "$package seek to end"   );
    is( $io->handle->tell, $file_size,                      "$package cursor at end" );
    is( $io->tell,         $file_size - $io->header_length, "$package tell at end"   );
    ok( $io->eof,                                           "$package eof"           );
    
    ok( $io->print("four\n"), "$package print" );
    is( -s $path, $file_size + length("four\n"), "$package new file size" );
    
    # --- Move the cursor back to the beginning of the body
    $io->seek(0, SEEK_SET);
    is( $!,                '',                 "$package seek to beginning" );
    is( $io->handle->tell, $io->header_length, "$package cursor pos"        );
    is( $io->tell,         0,                  "$package tell"              );
    
    ok( $io->print("four\n"), "$package print" );
    
    my $pos = $io->tell;
    is( $!, '', "$package tell again" );
    
    $io->truncate($pos);
    is( $!, '', "$package truncate" );
    
    is( -s $path, $io->header_length + length("four\n"),  "$package file size"       );
    
    is( $io->body, "four\n",     "$package read body"        );
    
    ok( $io->close,              "$package close"            );
    
}
