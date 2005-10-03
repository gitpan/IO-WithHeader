use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'         => 'IO-WithHeader',
    'AUTHOR'       => 'Paul Hoffman (nkuitse AT cpan DOT org)',
    'VERSION_FROM' => 'lib/IO/WithHeader.pm',
    'PREREQ_PM'    => {
        'IO::File'     => 0,
        'File::Copy'   => 0,
        'File::Slurp'  => 0,
        'YAML'         => 0,
        'Text::Header' => 0,
        'Fcntl'        => 0,
        'Errno'        => 0,
        'Symbol'       => 0,
    },
);

