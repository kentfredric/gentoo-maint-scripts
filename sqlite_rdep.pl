use strict;
use warnings;

use DBD::SQLite;
use DBI;

my $dbh = DBI->connect("dbi:SQLite:dbname=/var/cache/edb/dep/usr/local/gentoo.sqlite","","", {
  ReadOnly   => 1,
  RaiseError => 1
});

my @keywords = ( 
#  "m68k"
  # "arm64",
  # "mips",
  #"ia64-hpux"
);
if ( $ENV{KEYWORDS} ) {
  push @keywords, split / /, $ENV{KEYWORDS};
}
#@keywords = ();
#push @keywords, "amd64";

my @bindvars;

my $keyword_construct = join q[ OR ], map { " KEYWORDS LIKE ? " } @keywords;
push @bindvars, map { "%$_%" } @keywords;

if ( @keywords ) {
  $keyword_construct = "( $keyword_construct ) AND "
}

my $sth = $dbh->prepare("SELECT * FROM portage_packages WHERE 
    $keyword_construct (
        DEPEND LIKE ?
      OR
        HDEPEND LIKE ?
      OR
        PDEPEND LIKE ?
      OR
        RDEPEND LIKE ?
    )
");
my $atom = $ARGV[0];
$sth->execute(@bindvars, "%$atom%", "%$atom%", "%$atom%", "%$atom%");
use Data::Dump qw(pp);
while ( my $rc = $sth->fetchrow_hashref ) {

  my @lines;
  push @lines, sprintf "%20s: %s", "KEYWORDS", matched_keywords($rc);
  push @lines, sprintf "%20s: %s", "DEPS IN PHASES", matched_phases($rc);
  push @lines, sprintf "%20s: %s", "DEPSTRINGS", matched_atoms($rc);

  printf "%s\n %s\n\n", $rc->{portage_package_key}, join qq[\n ], @lines;
}

sub matched_keywords {
  my ($rec) = @_;
  my @fields = split / /, $rec->{KEYWORDS};
  if ( not @keywords ) {
    return join q[ ], @fields;
  }
  my @matched_fields;
  fields: for my $f (@fields) {
    for my $k ( @keywords  ) {
      if ( $f =~ /\Q$k\E/ ) {
        push @matched_fields, $f;
        next fields;
      }
    }
  }
  return join q[ ], @matched_fields;
}

sub matched_phases {
  my ($rec) = @_;
  my @matched_fields;
  for my $field ( qw( DEPEND HDEPEND PDEPEND RDEPEND )) {
    push @matched_fields, $field if $rec->{$field} =~ /\Q$atom\E/;
  }
  return join q[,], @matched_fields;
}

sub matched_atoms {

  my ($rec) = @_;
  my @fields;
  
  push @fields, split / /, $rec->{$_} for qw( DEPEND HDEPEND PDEPEND RDEPEND );
  my %matched_fields;
  fields: for my $f (@fields) {
    next if exists $matched_fields{$f};
    if ( $f =~ /\Q$atom\E/ ) {
      $matched_fields{$f}++;
      next fields;
    }
  }
  return join q[ ], sort keys %matched_fields;
}
