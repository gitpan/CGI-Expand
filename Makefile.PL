use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'        => 'CGI::Expand',
    'VERSION_FROM'    => 'Expand.pm', # finds $VERSION
    'PREREQ_PM'        => {
        'Test::Exception' => 0,
        'Test::More' => 0,
    }, # e.g., Module::Name => 1.1

    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Expand.pm', # retrieve abstract from module
       AUTHOR     => 'Brad Bowman <cgi-expand@bereft.net>') : ()),

    dist            => {
        # expand my tabs to 4
        PREOP => "(cd \$(DISTVNAME); \\
                    perl -MExtUtils::Manifest=maniread \\
                        -pi -e 'BEGIN{\@ARGV=keys \%{maniread()}; } \\
                                s/\\t/    /g' \\
                    )" },

);
