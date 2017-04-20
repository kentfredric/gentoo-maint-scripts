#!/usr/bin/env perl
# FILENAME: pm_new.pl
# CREATED: 17/03/16 08:58:26 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Add new PM Thing

use strict;
use warnings;

use constant repo => '/usr/local/gentoo';
use Path::Tiny qw( path cwd );
use Capture::Tiny qw( capture_stdout );
use Gentoo::PerlMod::Version qw( gentooize_version );

my $catpkg   = cwd_cat_pkg( repo, cwd() );
my $version  = args_version( \@ARGV );
my $gv       = gentooize_version( $version, { lax => 1 } );
my $basename = "$catpkg->{package}-$gv.ebuild";
my $basedir  = path( repo, $catpkg->{category}, $catpkg->{package} );
my $destfile = $basedir->child($basename);

my $template =
  get_newest_ebuild( repo, $catpkg->{category}, $catpkg->{package} );
$template = fix_year( $template, 1900 + [localtime]->[5] );
$template = force_eapi6($template);
$template = set_version( $template, $version );
if ( $ENV{DIST_AUTHOR} ) {
    $template = set_author( $template, $ENV{DIST_AUTHOR} );
}
$destfile->spew_raw($template);
ensure_xml( repo, $catpkg->{category}, $catpkg->{package} );
drop_keywords($destfile);
system( 'git', 'add', '.' );
system( 'repoman', 'manifest' );

sub cwd_cat_pkg {
    my ( $repo, $cwd ) = @_;
    my $relpath = path($cwd)->absolute->relative($repo);
    if ( my ( $cat, $package ) = $relpath =~ m{\A([^/]+)/([^/]+)\z} ) {
        return { category => $cat, package => $package };
    }
    die "Cannot parse $relpath into category and package";
}

sub args_version {
    my ($arglist) = @_;
    if ( not $arglist->[0] ) {
        die "Need to specify a version number in upstream semantics";
    }
    return shift @{$arglist};
}

sub get_newest_ebuild {
    my ( $repo, $cat, $package ) = @_;
    my $workd = path($repo)->child( $cat, $package );
    $workd->mkpath;
    my @children = $workd->children(qr/\.ebuild$/);
    if ( not @children ) {
        warn "Using internal template";
        return generate_ebuild_template();
    }
    my ( $best, @rest ) =
      map { $_->[1] }
      sort { atom_cmp( $a->[0], $b->[0] ) }
      map { [ "$cat/" . $_->basename('.ebuild'), $_ ] } @children;
    warn "Using $best as a template";
    return $best->slurp_raw();
}

sub ensure_xml {
    my ( $repo, $cat, $pkg ) = @_;
    my $workd = path($repo)->child( $cat, $pkg );
    my $xml = $workd->child('metadata.xml');
    if ( not -e $xml ) {
        my $modname = $pkg;
        $modname =~ s/-/::/g;
        $xml->spew_raw( generate_xml_template( $pkg, $modname ) );
    }
}

sub atom_cmp {
    my ( $left, $right ) = @_;
    my $out = capture_stdout {
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

sub fix_year {
    my ( $content, $year ) = @_;
    $content =~ s/1999-20\d\d/1999-${year}/g;
    return $content;
}

sub force_eapi6 {
    my ($content) = @_;
    $content =~ s/^EAPI=.*?$/EAPI=6/msx;
    $content =~ s/MY_PN/DIST_NAME/g;
    $content =~ s/MODULE_AUTHOR/DIST_AUTHOR/g;
    $content =~ s/MODULE_VERSION/DIST_VERSION/g;
    return $content;
}

sub set_version {
    my ( $content, $version ) = @_;
    if ( $content =~ /DIST_VERSION/ ) {
        $content =~ s/^DIST_VERSION=(.*?)$/DIST_VERSION=$version/msx;
        return $content;
    }
    $content =~ s{(^inherit perl-module)}{DIST_VERSION=$version\n$1}msx;
    return $content;
}

sub set_author {
    my ( $content, $author ) = @_;
    if ( $content =~ /DIST_AUTHOR/ ) {
        $content =~ s/^DIST_AUTHOR=(.*?)$/DIST_AUTHOR=$author/msx;
        return $content;
    }
    $content =~ s{(^inherit perl-module)}{DIST_AUTHOR=$author\n$1}msx;
    return $content;
}

sub drop_keywords {
    my ($ebuild) = @_;
    my $cwd = cwd();
    chdir $ebuild->parent;
    eval { system( "ekeyword", "~all", $ebuild->basename ); };
    chdir $cwd;
}

sub generate_ebuild_template {
    my ( $cat, $package ) = @_;
    my $content = <<"EOF";
# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=6

DIST_AUTHOR=\$(die missing author)
DIST_VERSION=\$(die missing version)
inherit perl-module

DESCRIPTION=\$(die missing description)
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="test"

RDEPEND=""
DEPEND="\${RDEPEND}
	test? (
		
	)
"
EOF

}

sub generate_xml_template {
    my ( $distname, $modulename ) = @_;
    my $content = <<"EOF";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE pkgmetadata SYSTEM "http://www.gentoo.org/dtd/metadata.dtd">
<pkgmetadata>
  <maintainer type="project">
    <email>perl\@gentoo.org</email>
    <name>Gentoo Perl Project</name>
  </maintainer>
  <upstream>
    <remote-id type="cpan">$distname</remote-id>
    <remote-id type="cpan-module">$modulename</remote-id>
  </upstream>
</pkgmetadata>
EOF
}
