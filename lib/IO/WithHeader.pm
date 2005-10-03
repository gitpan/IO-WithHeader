package IO::WithHeader;

use IO::File;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);
use Errno;
use Symbol;

use vars qw($VERSION $AUTOLOAD);

$VERSION = '0.05';

sub new {
    my ($cls, @args) = @_;
    if (scalar(@args) % 2) {
        # --- Odd number of args
        if (UNIVERSAL::isa($args[0], 'GLOB')) {
            unshift @args, 'handle';
        } elsif (UNIVERSAL::isa($args[0], 'HASH')) {
            unshift @args, 'header';
        } elsif (ref($args[0]) eq '') {
            unshift @args, 'path';
        } else {
            die "Can't interpret first argument in concise constructor"
        }
    }
    my %args = @args;
    my $self = bless Symbol::gensym(), $cls;
    foreach (keys %args) {
        *$self->{$_} = $args{$_};
    }
    return $self->init;
}

sub path { scalar @_ > 1 ? *{$_[0]}->{'path'} = $_[1] : *{$_[0]}->{'path'} }
sub mode { scalar @_ > 1 ? *{$_[0]}->{'mode'} = $_[1] : *{$_[0]}->{'mode'} }

sub auto_save { scalar @_ > 1 ? *{$_[0]}->{'auto_save'} = $_[1] : *{$_[0]}->{'auto_save'} }

sub reader { scalar @_ > 1 ? *{$_[0]}->{'reader'} = $_[1] : *{$_[0]}->{'reader'} }
sub writer { scalar @_ > 1 ? *{$_[0]}->{'writer'} = $_[1] : *{$_[0]}->{'writer'} }

sub header {
    my $self = shift;
    return *$self->{'header'}
        unless scalar @_;      # $io->header
    return delete *$self->{'header'}
        unless defined $_[0];  # $io->header(undef)
    if (UNIVERSAL::isa($_[0], 'HASH')) {
        # $io->header(\%header)
        *$self->{'header'} = $_[0];
        $self->is_dirty(1);
        return $_[0];
    } else {
        my $key  = shift;
        my $header = $self->{'header'};
        if (scalar @_) {
            # $io->header('foo' => $bar)
            $header->{$key} = $_[0];
            $self->is_dirty(1);
            return $_[0];
        } else {
            # $io->header('foo')
            return $header->{$key};
        }
    }
}

sub body {
    my $self = shift;
    if (scalar @_) {
        # $io->body($foo,...)
        *$self->{'body'} = join('', @_);
        $self->is_dirty(1);
    # } elsif (defined *$self->{'body'}) {
    #     # $io->body() after body has been read
    #     # $self->seek($saved_pos, SEEK_SET) || die "Can't restore cursor: $!";
    #     return *$self->{'body'};
    } else {
        # $io->body() - read body
        my $saved_pos = $self->tell;
        my $errno;
        eval {
            $self->read_body;
        };
        my $err = $@;
        $self->seek($saved_pos, SEEK_SET) || die "Can't restore cursor: $err";
        die "Can't read body: $err"
            if $err;
    }
#    return *$self->{'body'};
   return wantarray
       ? split(qr{(?<=$/)}, *$self->{'body'})
       : *$self->{'body'};
}

sub open {
    my ($self, $path, $mode) = @_;
    
    my $fh = $self->handle;
    if (defined $path and defined $fh) {
        # --- Reopen a different file
        $self->close;
        undef $fh;
    }
    
    if (defined $fh) {
        
        # --- If the user gave us a header, we don't try to read it
        # --- Ditto the body
        
        my ($header, $body) = @{*$self}{qw(header body)};
        if (defined *$self->{'header'}) {
            eval {
                $self->write_header;
                $self->write_body if defined *$self->{'body'};
            };
        }
        $self->seek(0, SEEK_SET);
        $mode = '<' unless defined $mode;
        
    } else {
        
        $path ||= $self->path;
        
        unless (defined $path) {
            # $! = "No such file or directory";
            if (exists &Errno::ENOENT) {
                $! = &Errno::ENOENT;
            } else {
                CORE::open(gensym, undef);
            }
            return;
        }
        
        $fh = IO::File->new;
        $self->handle($fh);
        
        ($path, $mode) = $self->normalize_path_and_mode($path, $mode || $self->mode);
        $self->path($path);
        $self->mode($mode);
        
        eval {
        
            if ($mode =~ /^\+?<$/) {
                # '<' (read) or '+<' (read and write)
                $fh->open("$mode$path") or die;
                warn "Ignoring specified header data"
                    if defined $self->header;
                $self->read_header;
                $self->seek(0, SEEK_SET)
                    if $mode eq '+<';
            } elsif ($mode eq '>') {
                # write
                $fh->open("$mode$path") or die;
                $self->dump;
            } elsif ($mode =~ /^[+>]>$/) {
                # >> (append) or +> (clobber, then read and write)
                if (-e $path and $mode eq '>>') {
                    warn "Ignoring specified header data"
                        if defined $self->header;
                    $fh->open($path, '<') or die;
                    $self->read_header;
                    $fh->close or die;
                    $fh->open("$mode$path") or die;
                    $self->seek(0, SEEK_SET) or die;
                } else {
                    # Clobber
                    $fh->open("$mode$path") or die;
                    $self->dump;
                }
            } else {
                die "Unknown mode: $mode";
            }
            
        };
        if ($@) {
            $self->handle(undef);
            unlink $path
                if -e $path and $mode eq '>';
            return;
        }
        
        $self->auto_close(1);
        
    }
    
    $! = 0;
    return $fh;
    
}

sub close {
    my ($self) = @_;
    my $fh = $self->handle;
    if (defined $fh) {
        fh_close($fh);
        $self->save
            if $self->auto_save;
    }
    undef *$self->{$_} for keys %{ *$self };
    return $self;
}

sub load {
    my ($self, $fh) = @_;
    if (defined $fh) {
        my $old_fh = $self->handle;
        fh_close($old_fh)
            if defined $old_fh
            and $old_fh ne $fh;
        $self->handle($fh);
    } else {
        die "No filehandle to load from"
            unless defined $self->handle;
    }
    $self->read_header;
    return $self;
}

sub dump {
    my ($self, $fh) = @_;
    if (defined $fh) {
        my $old_fh = $self->handle;
        fh_close($old_fh)
            if defined $old_fh
            and $old_fh ne $fh;
        $self->handle($fh);
    } else {
        die "No filehandle to dump to"
            unless defined $self->handle;
    }
    my $header = $self->header;
    $self->header($header = {})
        unless defined $header;
    $self->write_header($header);
    my $body = *$self->{'body'};
    $self->write_body($body)
        if defined $body
        and $body ne '';
    $self->is_dirty(0);
    return $self;
}

sub print {
    my $self = shift;
    my $fh = $self->handle || $self->open || die;
    fh_print($fh, @_);
}

sub getline {
    my ($self) = @_;
    my $fh = $self->handle || $self->open || die;
    my $line = <$fh>;
    return $line;
}

sub getlines {
    my ($self) = @_;
    my $fh = $self->handle || $self->open || die;
    my @lines = <$fh>;
    return @lines;
}

sub seek {
    my ($self, $pos, $whence) = @_;
    $pos += $self->header_length
        if $whence == SEEK_SET;
    my $fh = $self->handle || $self->open || die;
    fh_seek($fh, $pos, $whence)
        or die "Couldn't seek: $!";
}

sub tell {
    my ($self) = @_;
    my $fh = $self->handle || $self->open || die;
    my $pos = fh_tell($fh);
    die "Can't return cursor pos: $!" if $!;
    return $pos - $self->header_length;
}

sub truncate {
    my ($self, $length) = @_;
    my $fh = $self->handle || $self->open || die;
    fh_truncate($fh, $self->header_length + $length);
    return $! ne '';
}

sub eof {
    my ($self) = @_;
    my $fh = $self->handle || $self->open || die;
    fh_eof($fh);
}

sub save {
    my ($self, $path) = @_;
    if ($path) {
        $self->open($path, '+>');
        $self->dump;
    } elsif ($self->is_dirty) {
        $self->dump;
    }
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    $self->close if $self->handle;
    unless ( $^V and $^V lt '5.8.0' ) {
        untie *$self if tied *$self;
    }
}

sub AUTOLOAD {
    my $self = shift;
    my $fh = $self->handle;
    (my $method = $AUTOLOAD) =~ s/.*:://;
    my $f = UNIVERSAL::can($fh, $method);
    die "Unknown method '$method' called"
        unless defined $f;
    unshift @_, $fh;
    goto &$f;
}

# --- Private methods

sub normalize_path_and_mode {
    my ($self, $path, $mode) = @_;
    if ($path =~ s/^(\+?<|>>|\+?>)\s*//) {
        $mode = $1;
    }
    return ($path, '<') unless defined $mode;
    my %mode_norm = qw(
        <   <
        >   >
        >>  >>
        +<  +<
        +>  +>
        r   <
        w   >
        a   >>
        rw  +<
        r+  +<
        w+  +>
    );
    $mode = $mode_norm{$mode}
        or die "Unknown mode: '$mode'";
    return ($path, $mode);
}

sub is_dirty {
    my $self = shift;
    return *$self->{'is_dirty'} unless scalar @_;
    my $dirty = shift;
    return *$self->{'is_dirty'} = 0 unless $dirty;
    if ($self->auto_save) {
        $self->save;
        return 0;
    } else {
        return *$self->{'is_dirty'} = 1;
    }
}

sub auto_close { scalar @_ > 1 ? *{$_[0]}->{'auto_close'} = $_[1] : *{$_[0]}->{'auto_close'} }

sub handle      { scalar @_ > 1 ? *{$_[0]}->{'handle'}      = $_[1] : *{$_[0]}->{'handle'}      }
sub header_length { scalar @_ > 1 ? *{$_[0]}->{'header_length'} = $_[1] : *{$_[0]}->{'header_length'} }

sub getprop { *{$_[0]}->{$_[1]} }

sub setprop { *{$_[0]}->{$_[1]} = $_[2]; $_[0]->is_dirty(1); $_[2] }
sub setheader { *{$_[0]}->{'header'}->{$_[1]} = $_[2]; $_[0]->is_dirty(1); $_[2] }

sub init {
    my ($self) = @_;
    $self->auto_close(0);
    $self->is_dirty(0);
    my $path = $self->path;
    my $fh   = $self->handle;
    if ($fh) {
        $self->load;
    } elsif (defined $path) {
        $self->open($path, $self->mode);
    } else {
        # --- Nothing to do
    }
    $self->tie;
    return $self;
}

sub read_body {
    my ($self) = @_;
    my $fh = $self->handle;
    $self->seek(0, SEEK_SET) || die "Can't seek to beginning of body: $!";
    local $/;
    *$self->{'body'} = <$fh>;
    return *$self->{'body'};
}

sub write_body {
    my ($self, $body) = @_;
    return unless defined $body;
    my $fh = $self->handle;
    if (UNIVERSAL::isa($body, 'GLOB')) {
        File::Copy::copy($body, $fh);
    } else {
        fh_print($fh, $body) unless $body eq '';
    }
    fh_truncate($fh, fh_tell($fh))
        or die "Couldn't truncate: $!";
}

# --- Tie interface

sub tie {
    my ($self) = @_;
    tie *$self, $self; 
    return $self;
}

sub TIEHANDLE() {
    return $_[0] if ref $_[0];
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    $self->init(@_);
}

sub READLINE() {
    goto &getlines if wantarray;
    goto &getline;
}

sub BINMODE { 
    binmode shift()->handle;
}

sub GETC {
    getc shift()->handle;
}

sub PRINT {
    shift()->print(@_);
}

sub PRINTF {
    my $self = shift;
    $self->print(sprintf(@_));
}

sub READ {
    my $self = shift();
    my $buffref = \$_[0];
    my (undef, $length, $offset) = @_;
    $offset ||= 0;
    read(shift()->handle, $$buffref, $length, $offset);
}

sub WRITE {
    write shift()->handle, @_;
}

sub SEEK {
    shift()->seek(@_);
}

sub TELL {
    shift()->tell;
}

sub EOF {
    shift()->eof;
}

sub CLOSE {
    shift()->close;
}

sub FILENO {
    fileno shift()->handle;
}

# --- Functions

sub fh_print {
    my $fh = shift;
    if (UNIVERSAL::can($fh, 'print')) {
        $fh->print(@_);
    } else {
        CORE::print($fh, @_);
    }
}

sub fh_close {
    my ($fh) = @_;
    if (UNIVERSAL::can($fh, 'close')) {
        $fh->close;
    } else {
        CORE::close($fh);
    }
}

sub fh_seek {
    my ($fh, $pos, $whence) = @_;
    if (UNIVERSAL::can($fh, 'seek')) {
        $fh->seek($pos, $whence);
    } else {
        CORE::seek($fh, $pos, $whence);
    }
}

sub fh_tell {
    my ($fh) = @_;
    if (UNIVERSAL::can($fh, 'tell')) {
        $fh->tell;
    } else {
        CORE::tell($fh);
    }
}

sub fh_truncate {
    my ($fh, $length) = @_;
    if (UNIVERSAL::can($fh, 'truncate')) {
        $fh->truncate ($length);
    } else {
        CORE::truncate($fh, $length);
    }
}

sub fh_eof {
    my ($fh) = @_;
    if (UNIVERSAL::can($fh, 'eof')) {
        $fh->eof;
    } else {
        CORE::eof($fh);
    }
}

sub read_header {
    my ($self) = @_;
    my $reader = $self->reader
        || $self->can('_read_header')
        || die "Don't know how to read header";
    my $fh = $self->handle;
    fh_tell($fh) == 0
        or fh_seek($fh, 0, SEEK_SET)
        or die "Couldn't seek to read header: $!";
    if (UNIVERSAL::isa($reader, 'CODE')) {
        $header = $reader->($fh);
    } elsif (ref($reader)) {
        $header = $reader->read($fh);
    }
    $self->header($header);
    $self->header_length(fh_tell($fh));
}

sub write_header {
    my ($self, $header) = @_;
    my $writer = $self->writer
        || $self->can('_write_header')
        || die "Don't know how to write header";
    my $fh = $self->handle;
    fh_tell($fh) == 0
        or fh_seek($fh, 0, SEEK_SET)
        or die "Couldn't seek to write header: $!";
    if (UNIVERSAL::isa($writer, 'CODE')) {
        $writer->($fh, $header);
    } elsif (ref($writer)) {
        $writer->write($fh, $header);
    }
    $self->header_length(fh_tell($fh));
}

sub as_hash {
    # Return self as a hash (useful for debugging)
    my ($self) = @_;
    return \%{ *$self };
}


1;


=head1 NAME

IO::WithHeader - read/write header and body in a single file

=head1 SYNOPSIS

    use IO::WithHeader::MySubclass;
    
    $io = IO::WithHeader::MySubclass->new($path_or_filehandle);
    $io = IO::WithHeader::MySubclass->new(\%header);
    $io = IO::WithHeader::MySubclass->new(
        'path'   => '/path/to/a/file/which/might/not/exist/yet',
        'handle' => $fh,  # Mutually exclusive with path
        'mode'   => $mode,
        'header' => { 'title' => $title, ... },
        'body'   => $scalar_or_filehandle_to_copy_from,
    );
    
    $io->open($path, 'mode' => '>') or die;  # Open the body
    print $io "Something to put in the file's body\n";
    
    $path = $io->path;
    $io->path('/path/to/a/file');
    $io->open or die;
    while (<$io>) { ... }
    
    # Fetch and store 
    %header = %{ $io->header };
    $io->header(\%header);
    
    $body = $io->body;  # Read the entire body
    $io->body($body);   # Write the entire body

=head1 DESCRIPTION

B<IO::WithHeader> and its subclasses allow you to read and write a file
containing both a header and a body.  The header and body may be changed
without affecting the other.

B<IO::WithHeader> itself doesn't provide code to actually read and write a
file's header, since there are so many different varieties of headers.  Instead,
it must be subclassed to provide the desired functionality.

The B<IO::WithHeader> distribution comes with two such subclasses,
L<IO::WithHeader::YAML|IO::WithHeader::YAML> and
L<IO::WithHeader::RFC822|IO::WithHeader::RFC822>.

=head1 METHODS

The following methods provide access to the body of the file; see L<perlfunc>
and L<IO::Handle|IO::Handle> for complete descriptions:

=over 4

=item B<eof>

=item B<fileno>

=item B<format_write>([I<format_name>])

=item B<getc>

=item B<read>(I<buf>, I<len>, [I<offset>])

=item B<print>(I<args>)

=item B<printf>(I<fmt>, [I<args>])

=item B<stat>

=item B<sysread>(I<buf>, I<len>, [I<offset>])

=item B<syswrite>(I<buf>, [I<len>, [I<offset>]])

=item B<truncate>(I<len>)

=back

The remaining methods are as follows:

=over 4

=item B<new>

    $subclass = 'IO::WithHeader::MySubclass';  # or whatever
    
    use IO::WithHeader::MySubclass;  # or whatever
    
    # Simplest constructor - must call $io->open(...) later
    $io = $subclass->new;
    
    # Concise forms
    $io = $subclass->new("$file");  # Default is read-only
    $io = $subclass->new("<$file"); # Read-only made explicit
    $io = $subclass->new(">$file"); # Read-write (empty header & body)
    $io = $subclass->new($file, 'mode' => '<');  # Or '>', '+<', 'r', etc.
    $io = $subclass->new(\*STDIN);
    $io = $subclass->new(\*STDOUT, 'mode' => '>');
    $io = $subclass->new($anything_that_isa_GLOB);
    
    # Full form (all arguments optional)
    $io = $subclass->new(
        'path'   => $file,       # File will be opened or created
           - or -
        'handle' => $fh,         # File handle (already open)
        'mode'   => '+>',        # Default is '<'
        'header' => \%hash,      # Default is {}
        'body'   => $scalar,     # Content to write to the new file
           - or -
        'body'   => $filehandle, # Copy from a file handle to the new file
    );
    
    # Specify header and/or body
    $io = $subclass->new('header' => \%hash);     # Empty body
    $io = $subclass->new('body' => $scalar);      # Empty header
    $io = $subclass->new('body' => $filehandle);  # Empty header
    $io = $subclass->new(..., 'body' => $scalar, ...);
    $io = $subclass->new(..., 'body' => $filehandle, ...);

Instantiate an IO::WithHeader object (or, rather, an instance of a subclass of
IO::WithHeader).  An exception is thrown if anything goes wrong.

The B<new()> method may be called in a concise form, in which the first argument
is a file name, file handle, or hash reference and the (optional) remaining
arguments are key-value pairs; or it may be called in a full form in which all
(optional) arguments are specified as key-value pairs.

If a path is specified, the file at that path will be opened.  If the file
doesn't already exist, it will be created -- but only if you've specified a mode
that permits writing; if you haven't, an exception will be thrown.

To use an already-open file handle, pass it to the constructor rather than the
name of a file.

If neither a path nor a file handle is specified, you'll have to call the
C<open()> method yourself.

The following arguments may be specified in the constructor:

=over 4

=item B<path>

Path to a file to open (creating it, if possible, if write or append mode is
specified).

=item B<mode>

Read/write/append mode for the new file.  This must be specified in one
of the following forms:

=over 4

=item C<< E<lt> >>

=item C<< E<gt> >>

=item C<< +E<gt> >>

=item C<< +E<lt> >>

=item C<< r >>

=item C<< r+ >>

=item C<< rw >>

Or any other standard form that I've forgotten about.

=back

B<NOTE:> Numeric modes and PerlIO layers are not yet implemented.

=item B<auto_save>

If set to a true value, automatically save changes to the file's header (i.e.,
changes made by calling C<< $io->header(\%myheader) >>).

=back

If an odd number of arguments are given, the first argument is interpreted
according to its type:

=over 4

=item B<GLOB>

File handle.

=item B<any scalar value>

File path.

=item B<HASH>

The header (to be written to the file).  Don't use this unless you're opening
the file for write (or append) access.

=back

=item B<open>

    $io = IO::WithHeader->new;
    $io->open("<$file") or die $!;
    $io->open($file, $mode) or die $!;

Open a file with the specified name and mode.  You must use this method
if the instance was created without a C<path> or C<handle> element (and one has
not been assigned using the C<path()> or C<handle()> methods).

Upon failure, sets C<$!> to a meaningful message and returns a false
value.

The possible modes are as described for B<new>.

The C<open()> method may be called repeatedly on the same instance,
without having to close it first.

=item B<close>

    $io->close or die $!;

Close the filehandle.  Any changes made to the file's header (i.e., by calling
C<< $io->head(\%myheader) >> will be saved if (and only if) I<auto_save> has
been turned on.

=item B<header>

    $header = $io->header;
    $io->header({...});
    
    $foo = $io->header('foo');
    $io->header('foo' => $foo);

Get or set the header, or a single element in the header.  XXX If setting all or
part of the header, you must call B<save()> for the change to be written to the
file (or file handle).

The header's value must be a hash or a hash-based object:

    $io->header( [1, 2, 3, 4, 5] );   # ERROR
    $io->header( MyClass->new(...) ); # OK if hash-based

=item B<body>

    $body = $io->body;
    @lines = $io->body;
    
    $io->body($body);
    $io->body(@lines);

Read or write the entire file body.

XXX If called in list context, the lines of the file are returned as a list; this
means that these are equivalent:

    @lines = <$io>;
    @lines = $io->getlines;

=item B<print>

    print $io @one_or_more_scalar_values;
    $io->print(@one_or_more_scalar_values);

Print to the body of the file or filehandle.

=item B<getline>

    $line = $io->getline;

Read a single line from the body.

=item B<getlines>

Read all lines of the body.

=item B<seek>

    use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);  # Handy constants
    $io->seek($whence, $pos);

Move the filehandle's cursor to a position within the body.
    
=item B<tell>

    $pos = $io->tell;

Get the position of the cursor within the body of the file or filehandle.

=item B<binmode>

=item B<seek>

=item B<save>

Save changes made to the file's header.

=item B<handle>

Get or set the underlying filehandle. It's not a good idea to set this value!

=back


=begin private

=head1 PRIVATE METHODS

The following methods are private to this module:

=over 4

=item B<BINMODE>
=item B<CLOSE>
=item B<EOF>
=item B<FILENO>
=item B<GETC>
=item B<PRINT>
=item B<PRINTF>
=item B<READ>
=item B<READLINE>
=item B<SEEK>
=item B<TELL>
=item B<TIEHANDLE>
=item B<WRITE>
=item B<as_hash>
=item B<auto_close>
=item B<dump>
=item B<fh_close>
=item B<fh_eof>
=item B<fh_print>
=item B<fh_seek>
=item B<fh_tell>
=item B<fh_truncate>
=item B<getprop>
=item B<header_length>
=item B<init>
=item B<is_dirty>
=item B<load>
=item B<normalize_path_and_mode>
=item B<read_body>
=item B<read_header>
=item B<reader>
=item B<setheader>
=item B<setprop>
=item B<tie>
=item B<write_body>
=item B<write_header>
=item B<writer>

=back

=end private

=head1 SUBCLASSING

Generally speaking, the only methods your subclass needs to provide are
B<_read_header> and B<_write_header>.  For example, here's the complete source
code of L<IO::WithHeader::YAML|IO::WithHeader::YAML>:

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

See L<IO::WithHeader::RFC822|IO::WithHeader::RFC822> for another example.

=head1 BUGS

Autoflush might not be working.

=head1 TO DO

Deal with PerlIO layers.

Implement permissions and numeric modes.

Allow for non-hash headers?

Implement auto-save.

=head1 SEE ALSO

L<IO::WithHeader::YAML|IO::WithHeader::YAML>,
L<IO::WithHeader::RFC822|IO::WithHeader::RFC822>

=head1 AUTHOR

Paul Hoffman (nkuitse AT cpan DOT org)

=head1 COPYRIGHT

Copyright 2004 Paul M. Hoffman.

This is free software, and is made available under the same terms as
Perl itself.

