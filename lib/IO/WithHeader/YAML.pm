package IO::WithHeader::YAML;

use IO::WithHeader;
use YAML qw();

@IO::WithHeader::YAML::ISA = 'IO::WithHeader';

sub _read_header {
    my ($fh) = @_;
    my $yaml = '';
    local $_;
    while (<$fh>) {
        last if /^\.\.\.$/;
        $yaml .= $_;
    }
    return YAML::Load($yaml);
}

sub _write_header {
    my ($fh, $header) = @_;
    my $yaml = YAML::Dump($header) . "...\n";
    print $fh $yaml;
}


1;


=head1 NAME

IO::WithHeader::YAML - read/write YAML header and body in one file

=head1 SYNOPSIS

    use IO::WithHeader::YAML;
    
    $io = IO::WithHeader::YAML->new($path_or_filehandle);
    $io = IO::WithHeader::YAML->new(\%header);
    $io = IO::WithHeader::YAML->new(
        'path'   => '/path/to/a/file/which/might/not/exist/yet',
        'handle' => $fh,
        'header' => { 'title' => $title, 'author' => $author, ... },
        'body'   => $scalar_or_filehandle_to_copy_from,
    );
    
    $io->open($path, '>') or die;  # Open the body
    print $io "Something to put in the file's body\n";
    
    $path = $io->path;
    $io->path('/path/to/a/file');
    $io->open or die;
    while (<$io>) { ... }
    
    %header = %{ $io->header };
    $io->header(\%header);
    
    $body = $io->body;  # Read the entire body
    $io->body($body);   # Write the entire body

=head1 DESCRIPTION

B<IO::WithHeader::YAML> reads and writes files containing a header in YAML form.
The header may be changed without changing the body, and the body may be read
from or writen to without disturbing the header.

The file (or filehandle) must begin with the YAML representation of a hash,
followed by the YAML end-of-stream marker `...'.  The rest of the file or
stream can be anything at all.  Here's a simple example:

    --- #YAML:1.0
    title: Testing 1, 2, 3
    author: nkuitse
    date: 2004-03-05
    ...
    This is a test.  This is only a test.
    That's all I have to say at this time.
    ^D

(Here, C<^D> indicates the end of the file.)

In this next example, the file's body is empty, as is its header:

    --- #YAML:1.0 {}
    ...
    ^D

For more information, see the documentation for the superclass,
L<IO::WithHeader|IO::WithHeader>.

=head1 BUGS

None that I know of.

=head1 SEE ALSO

L<IO::WithHeader|IO::WithHeader>,
L<IO::WithHeader::RFC822|IO::WithHeader::RFC822>,
L<YAML|YAML>

=head1 AUTHOR

Paul Hoffman (nkuitse AT cpan DOT org)

=head1 COPYRIGHT

Copyright 2004 Paul M. Hoffman.

This is free software, and is made available under the same terms as
Perl itself.

