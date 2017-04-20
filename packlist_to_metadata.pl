#!/usr/bin/env perl
# FILENAME: packlist_to_metadata.pl
# CREATED: 08/03/16 02:53:52 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Turn a .packlist into a <upstream> list

use strict;
use warnings;

use constant PADDING => "  ";
use constant PREFIX  => quotemeta("/usr/lib64/perl5/vendor_perl/5.22.1/");

use ExtUtils::Packlist;
use Module::Metadata;
use Carp qw( croak );

no warnings 'redefine';
*Module::Metadata::provides = sub {
    my $class = shift;

    croak "provides() requires key/value pairs \n" if @_ % 2;
    my %args = @_;

    croak "provides() takes only one of 'dir' or 'files'\n"
      if $args{dir} && $args{files};

    croak "provides() requires a 'version' argument"
      unless defined $args{version};

    croak "provides() does not support version '$args{version}' metadata"
      unless grep { $args{version} eq $_ } qw/1.4 2/;

    $args{prefix} = 'lib' unless defined $args{prefix};

    my $p;
    if ( $args{dir} ) {
        $p = $class->package_versions_from_directory( $args{dir} );
    }
    else {
        croak "provides() requires 'files' to be an array reference\n"
          unless ref $args{files} eq 'ARRAY';
        $p = $class->package_versions_from_directory( '/var/empty', $args{files} );
    }

    # Now, fix up files with prefix
    if ( length $args{prefix} ) {    # check in case disabled with q{}
        $args{prefix} =~ s{/$}{};
        for my $v ( values %$p ) {
            $v->{file} = "$args{prefix}/$v->{file}";
        }
    }

    return $p;
};

my $pl       = ExtUtils::Packlist->new( $ARGV[0] );
my $provides = Module::Metadata->provides(
    version => 2,
    files   => [ sort keys %{$pl} ]
);

for my $entry ( sort keys %{$provides} ) {

    #    next unless $entry =~ /\.pm$/;
    #    $entry =~ s{@{[PREFIX]}}{};
    #    $entry =~ s{\.pm$}{};
    #    $entry =~ s{/}{::}g;

    print(
        PADDING x 2 . "<remote-id type=\"cpan-module\">$entry</remote-id>\n" );
}

