package IO::WithHeader::RFC822;

use IO::WithHeader;
use Text::Header qw();

@IO::WithHeader::RFC822::ISA = 'IO::WithHeader';

sub _read_header {
    my ($fh) = @_;
    my @lines;
    local $_;
    while (<$fh>) {
        last if /^$/;
        if (s/^\s+//) {
            die "First line in header begins with whitespace"
                unless scalar @lines;
            $lines[0] .= " $_";
        } else {
            push @lines, $_;
        }
    }
    my %lines;
    my $spurious_last_line_to_avoid_Text_Header_warnings = '';
    %lines = map { split(/:\s+/, $_, 1) } Text::Header::unheader(
        @lines,
        $spurious_last_line_to_avoid_Text_Header_warnings
    ) if (scalar @lines);
    return \%lines;
}

sub _write_header {
    my ($fh, $header) = @_;
    my @lines;
    @lines = Text::Header::header(%$header)
        if scalar keys %$header;
    print $fh @lines, "\n";
}


1;


=head1 NAME

IO::WithHeader::RFC822 - read/write RFC 822 header and body in one file

=head1 SYNOPSIS

    use IO::WithHeader::RFC822;
    
    $io = IO::WithHeader::RFC822->new($path_or_filehandle);
    $io = IO::WithHeader::RFC822->new(\%header);
    $io = IO::WithHeader::RFC822->new(
        'path'   => '/path/to/a/file/which/might/not/exist/yet',
        'handle' => $fh,
        'header' => { 'From' => $from, 'Date' => $date, ... },
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

B<IO::WithHeader::RFC822> reads and writes files containing a header in RFC 822
form. The header may be changed without changing the body, and the body may be
read from or writen to without disturbing the header.

The file (or filehandle) must begin with a valid RFC 822 header, followed by a
blank line.  The rest of the file or stream can be anything at all.  Here's a
simple example:

    Name: Ulysses K. Fishwick
    E-mail: fishwick@example.com
    Age: 93
    
    Ulysses plays well with others.
    ^D

(Here, C<^D> indicates the end of the file.)

For more information, see the documentation for the superclass,
L<IO::WithHeader|IO::WithHeader>.

=head1 BUGS

None that I know of.

=head1 SEE ALSO

L<IO::WithHeader|IO::WithHeader>,
L<IO::WithHeader::YAML|IO::WithHeader::YAML>,
L<YAML|YAML>

=head1 AUTHOR

Paul Hoffman (nkuitse AT cpan DOT org)

=head1 COPYRIGHT

Copyright 2004 Paul M. Hoffman.

This is free software, and is made available under the same terms as
Perl itself.

