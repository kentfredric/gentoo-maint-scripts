#!perl
use strict;
use warnings;
use Digest::SHA;


my $file = 't/porting/customized.dat';
if ( !-r $file ) {
  die "$file needed relative to CWD, please run this in a (patched) perl checkout";
}
open my $fh, q[<], $file or die "Can't read $file, $!";
for my $line ( <$fh> ) {
  chomp $line;
  my ( $dist, $path, $sha ) = split /[ ]/, $line;
  my $digest = Digest::SHA->new();
  $digest->addfile( $path , 'b');
  printf "%s %s %s\n", $dist, $path, $digest->hexdigest;
}


