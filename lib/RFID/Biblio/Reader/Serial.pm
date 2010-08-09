package RFID::Biblio::Reader::Serial;

use warnings;
use strict;

use Device::SerialPort qw(:STAT);
use Data::Dump qw(dump);

=head1 NAME

RFID::Biblio::Reader::Serial - base class for serial RFID readers

=head1 METHODS

=head2 new

Open serial port (if needed) and init reader

=cut

sub new {
	my $class = shift;
	my $self = {@_};
	bless $self, $class;

	$self->port && $self->init && return $self;
}


=head2 port

  my $serial_obj = $self->port;

=cut

our $serial_device;

sub port {
	my $self = shift;

	return $self->{port} if defined $self->{port};

	my $settings = $self->serial_settings;
	my @devices  = ( $ENV{RFID_DEVICE} );
	@devices = glob '/dev/ttyUSB*';

	warn "# port devices ",dump(@devices);

	foreach my $device ( @devices ) {

		next if $serial_device->{$device};

		if ( my $port = Device::SerialPort->new($device) ) {
			foreach my $opt ( qw/handshake baudrate databits parity stopbits/ ) {
				$port->$opt( $settings->{$opt} );
			}
			warn "found ", ref($self), " $device settings ",dump $settings;
			$self->{port} = $port;
			$serial_device->{$device} = $port;
			last;
		}
	}

	warn "# serial_device ",dump($serial_device);

	return $self->{port};
}

1
__END__

=head1 SEE ALSO

L<RFID::Biblio::Reader::3M810>

L<RFID::Biblio::Reader::CPRM01>

L<RFID::Biblio::Reader::API>

