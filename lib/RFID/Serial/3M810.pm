package RFID::Serial::3M810;

use base 'RFID::Serial';
use RFID::Serial;

use Data::Dump qw(dump);
use Carp qw(confess);
use Time::HiRes;
use Digest::CRC;

sub serial_settings {{
	device    => "/dev/ttyUSB1", # FIXME comment out before shipping
	baudrate  => "19200",
	databits  => "8",
	parity	  => "none",
	stopbits  => "1",
	handshake => "none",
}}

my $port;
sub init {
	my $self = shift;
	$port = $self->port;

	# drain on startup
	my ( $count, $str ) = $port->read(3);
	my $data = $port->read( ord(substr($str,2,1)) );
	warn "drain ",as_hex( $str, $data ),"\n";

	setup();

}

sub checksum {
	my $bytes = shift;
	my $crc = Digest::CRC->new(
		# midified CCITT to xor with 0xffff instead of 0x0000
		width => 16, init => 0xffff, xorout => 0xffff, refout => 0, poly => 0x1021, refin => 0,
	) or die $!;
	$crc->add( $bytes );
	pack('n', $crc->digest);
}

sub wait_device {
	Time::HiRes::sleep 0.015;
}

sub cmd {
	my ( $hex, $description, $coderef ) = @_;
	my $bytes = hex2bytes($hex);
	if ( substr($bytes,0,1) !~ /(\xD5|\xD6)/ ) {
		my $len = pack( 'n', length( $bytes ) + 2 );
		$bytes = $len . $bytes;
		my $checksum = checksum($bytes);
		$bytes = "\xD6" . $bytes . $checksum;
	}

	warn ">> ", as_hex( $bytes ), "\t\t[$description]\n";
	$port->write( $bytes );

	wait_device;

	my $r_len = $port->read(3);

	while ( ! $r_len ) {
		wait_device;
		$r_len = $port->read(3);
	}

	wait_device;

	my $len = ord( substr($r_len,2,1) );
	$data = $port->read( $len );
	warn "<< ", as_hex($r_len,$data)," $len\n";

	$coderef->( $data ) if $coderef;

}

sub assert {
	my ( $got, $expected ) = @_;
	$expected = hex2bytes($expected);

	my $len = length($got);
	$len = length($expected) if length $expected < $len;

	confess "got ", as_hex($got), " expected ", as_hex($expected)
	unless substr($got,0,$len) eq substr($expected,0,$len);

	return substr($got,$len);
}

sub setup {

cmd(
'D5 00  05   04 00 11   8C66', 'hw version', sub {
	my $data = shift;
	my $rest = assert $data => '04 00 11';
	my $hw_ver = join('.', unpack('CCCC', $rest));
	print "hardware version $hw_ver\n";
});

cmd(
'13  04 01 00 02 00 03 00 04 00','FIXME: stats? rf-on?', sub { assert(shift,
'13  00 02 01 01 03 02 02 03 00'
)});
}

sub tag_hex { uc(unpack('H16', shift)) }

sub inventory {

	my $inventory;

cmd( 'FE  00 05', 'scan for tags', sub {
	my $data = shift;
	my $rest = assert $data => 'FE 00 00 05';
	my $nr = ord( substr( $rest, 0, 1 ) );

	if ( ! $nr ) {
		warn "# no tags in range\n";
	} else {
		my $tags = substr( $rest, 1 );
		my $tl = length( $tags );
		die "wrong length $tl for $nr tags: ",dump( $tags ) if $tl =! $nr * 8;

		foreach ( 0 .. $nr - 1 ) {
			my $tag = tag_hex substr($tags, $_ * 8, 8);
			$invetory->{$tag} ||= read_tag($tag);
		}
	}

});

	return $invetory;
}


# 3M defaults: 8,4
# cards 16, stickers: 8
my $max_rfid_block = 8;
my $blocks = 8;

sub _matched {
	my ( $data, $hex ) = @_;
	my $b = hex2bytes $hex;
	my $l = length($b);
	if ( substr($data,0,$l) eq $b ) {
		warn "_matched $hex [$l] in ",as_hex($data);
		return substr($data,$l);
	}
}

sub read_tag {
	my $tag = shift || confess "no tag?";
	warn "# read $tag\n";

	my $tag_blocks;
	my $start = 0;
	cmd(
		 sprintf( "02 $tag %02x %02x", $start, $blocks ) => "read $tag $start/$blocks", sub {
			my $data = shift;
			if ( my $rest = _matched $data => '02 00' ) {

				my $tag = tag_hex substr($rest,0,8);
				my $blocks = ord(substr($rest,8,1));
				warn "# response from $tag $blocks blocks ",as_hex substr($rest,9);
				foreach ( 1 .. $blocks ) {
					my $pos = ( $_ - 1 ) * 6 + 9;
					my $nr = unpack('v', substr($rest,$pos,2));
					my $payload = substr($rest,$pos+2,4);
					warn "## pos $pos block $nr ",as_hex($payload), $/;
					$tag_blocks->{$tag}->[$nr] = $payload;
				}
			} elsif ( my $rest = _matched $data => 'FE 00 00 05 01' ) {
				warn "FIXME ready? ",as_hex $test;
			} elsif ( my $rest = _matched $data => '02 06' ) {
				warn "ERROR ",as_hex($rest);
			}
	});

	warn "# tag_blocks ",dump($tag_blocks);
}

1
