use strict;
use warnings;

my $from = "dev-perl/Period";
my $to   = "dev-perl/Time-Period";

use Path::Tiny qw( path cwd );

for my $child ( cwd->children(qr/\.ebuild$/) ) {
  my $content = $child->slurp_raw;
  next unless $content =~ s/$from/$to/g;
  $content =~ s/1999-20\d\d/1999-2016/g;
  $child->spew_raw($content);
}
