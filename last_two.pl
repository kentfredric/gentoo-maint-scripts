#!perl
use strict;
use warnings;

use Path::Tiny qw( path cwd );
use Capture::Tiny qw( capture_stdout );

printf "%s\n%s\n", get_latest();

sub get_latest {
    my (@ebuilds) = cwd->children(qr{\.ebuild$});
    return unless @ebuilds;
    my $cat = cwd->parent->basename;

    my ( $best, $second, @rest ) =
      sort { atom_cmp( $a->[0], $b->[0] ) }
      map { [ "$cat/" . $_->basename('.ebuild'), $_ ] } @ebuilds;

    return $second->[1], $best->[1];

}

sub atom_cmp {
    my ( $left, $right ) = @_;
    my ( $out,  $ret )   = capture_stdout {
        system( "qatom", "-c", $left, $right );
    };
    if ( $out =~ /</ ) {
        return 1;
    }
    if ( $out =~ />/ ) {
        return -1;
    }
    return 0;
}

