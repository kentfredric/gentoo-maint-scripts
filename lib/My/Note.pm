package My::Note;

use strict;
use warnings;
use Exporter ();
use Term::ANSIColor qw( colored );

BEGIN { *import = \&Exporter::import }

our @EXPORT_OK = qw( note $TASK );

our $TASK = undef;

sub note {
    my $sym = '* ';
    print STDERR ref $_[1] ? colored( $_[1], "$sym " ) : "$sym ";
    if ($TASK) {
        print STDERR "<$TASK> ";
    }
    print STDERR ( ref $_[1] ? colored( $_[1], $_[0] ) : $_[0] ) . "\n";
}

1;

