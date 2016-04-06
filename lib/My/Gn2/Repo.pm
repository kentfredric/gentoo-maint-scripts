use strict;
use warnings;
package My::Gn2::Repo;

use My::Git::Utils qw( git );
use My::Note qw( note );

use Exporter ();

BEGIN {    *import = \&Exporter::import }

our @EXPORT_OK = qw( show_new_since );

sub show_new_since {
  my ( $repo, $tracking_master, $tracking_slave ) = @_;
  my (@data) = git( $repo )->merge_base($tracking_master, $tracking_slave);
  # note("Common ancestor between $tracking_master .. $tracking_slave ...: $data[0]");
  local $ENV{PAGER}      = 'cat';
  local $ENV{GIT_EDITOR} = ' ';
  git( $repo )->RUN_DIRECT('log','--oneline', $data[0] . '...' . $tracking_master );
}



1;

