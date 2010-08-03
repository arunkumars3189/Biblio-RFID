#!/usr/bin/perl

use warnings;
use strict;

use Data::Dump qw(dump);
use Getopt::Long;
use lib 'lib';
use RFID::Biblio::Readers;
use RFID::Biblio::RFID501;

my $reader;

GetOptions(
	'reader=s', => \$reader,
) || die $!;

my ( $sid, $content ) =  @ARGV;
die "usage: $0 [--reader regex_filter] [--afi 214] E0_RFID_SID [barcode]\n" unless $sid && ( $content | $afi );

my @rfid = RFID::Biblio::Readers->available( $reader );

foreach my $rfid ( @rfid ) {
	my $visible = $rfid->scan;
	foreach my $tag ( keys %$visible ) {
		next unless $tag eq $sid;
		warn "PROGRAM $tag with $content\n";
		$rfid->write_blocks( $tag => RFID::Biblio::RFID501->from_hash({ content => $content }) );
	}
}

